\connect dbAether2Year

BEGIN;

-- Daily Active User (DAU): one row per employee per day, upserted on each access.
CREATE TABLE daily_active_user (
    id_employee INTEGER NOT NULL,
    access_date DATE NOT NULL,
    first_access_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    last_access_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    access_count INTEGER NOT NULL DEFAULT 1 CHECK (access_count > 0),
    origin TEXT NOT NULL DEFAULT 'API',
    CONSTRAINT pk_daily_active_user PRIMARY KEY (id_employee, access_date),
    CONSTRAINT fk_daily_active_user_employee
        FOREIGN KEY (id_employee) REFERENCES employee (id) ON DELETE CASCADE,
    CONSTRAINT ck_daily_active_user_window CHECK (last_access_at >= first_access_at)
);

-- Serves the per-day distinct count behind vw_dau.
CREATE INDEX idx_daily_active_user_access_date
    ON daily_active_user (access_date) INCLUDE (id_employee);

COMMENT ON TABLE daily_active_user IS
    'Daily access register used to compute DAU. Grain: employee x UTC day. Written only through sp_register_access.';
COMMENT ON COLUMN daily_active_user.access_count IS 'Number of accesses by the employee on the day.';
COMMENT ON COLUMN daily_active_user.origin IS 'Access channel: API, WEB, MOBILE, or SEED for synthetic data.';

-- Registers an access (idempotent per employee/day) and returns the day counter.
CREATE OR REPLACE PROCEDURE sp_register_access(
    OUT p_access_count integer,
    IN p_id_employee integer,
    IN p_origin text DEFAULT 'API'
)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_id_employee IS NULL THEN
        RAISE EXCEPTION 'id_employee is required'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM employee e
        WHERE e.id = p_id_employee AND e.employee_status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'Active employee % not found', p_id_employee
            USING ERRCODE = '23503';
    END IF;

    INSERT INTO daily_active_user (id_employee, access_date, origin)
    VALUES (p_id_employee, (now() AT TIME ZONE 'UTC')::date, COALESCE(p_origin, 'API'))
    ON CONFLICT (id_employee, access_date) DO UPDATE
        SET access_count = daily_active_user.access_count + 1,
            last_access_at = clock_timestamp()
    RETURNING access_count INTO p_access_count;
END;
$$;

COMMENT ON PROCEDURE sp_register_access(integer, integer, text) IS
    'Registers an employee access for DAU. Rejects unknown or non-ACTIVE employees (23503). Repeated calls on the same UTC day only increment access_count. OUT p_access_count is the day total.';

-- DAU per enterprise and day, with 7-day moving average, previous day, and busiest-day rank.
CREATE OR REPLACE VIEW vw_dau AS
WITH daily AS (
    SELECT
        d.access_date,
        u.id_enterprise AS enterprise_id,
        COUNT(DISTINCT d.id_employee) AS dau,
        SUM(d.access_count) AS total_accesses
    FROM daily_active_user d
    JOIN employee e ON e.id = d.id_employee
    JOIN department dp ON dp.id = e.id_department
    JOIN unit u ON u.id = dp.id_unit
    GROUP BY d.access_date, u.id_enterprise
)
SELECT
    access_date,
    enterprise_id,
    dau,
    total_accesses,
    LAG(dau) OVER w AS prev_day_dau,
    ROUND(AVG(dau) OVER (w ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS dau_7d_avg,
    SUM(total_accesses) OVER (w ROWS UNBOUNDED PRECEDING) AS cumulative_accesses,
    RANK() OVER (PARTITION BY enterprise_id ORDER BY dau DESC, access_date) AS rank_busiest_day
FROM daily
WINDOW w AS (PARTITION BY enterprise_id ORDER BY access_date);

COMMENT ON VIEW vw_dau IS
    'DAU by enterprise and UTC day. CTE for aggregation; window functions for previous day, 7-day moving average, running total, and busiest-day ranking.';

-- Synthetic history for BI tests: last 30 days, roughly two thirds of ACTIVE employees per day.
INSERT INTO daily_active_user (id_employee, access_date, first_access_at, last_access_at, access_count, origin)
SELECT
    e.id,
    d::date,
    d + interval '8 hours' + (e.id % 120) * interval '1 minute',
    d + interval '17 hours' + (e.id % 120) * interval '1 minute',
    1 + (e.id + EXTRACT(day FROM d)::int) % 5,
    'SEED'
FROM employee e
CROSS JOIN generate_series(
    (now() AT TIME ZONE 'UTC')::date - 29,
    (now() AT TIME ZONE 'UTC')::date,
    interval '1 day'
) AS d
WHERE e.employee_status = 'ACTIVE'
  AND (e.id + EXTRACT(day FROM d)::int) % 3 <> 0;

REVOKE ALL ON TABLE daily_active_user FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_register_access(integer, integer, text) FROM PUBLIC;
GRANT SELECT ON TABLE daily_active_user, vw_dau TO aether_auditor, aether_admin;
GRANT EXECUTE ON PROCEDURE sp_register_access(integer, integer, text) TO aether_app, aether_admin;

-- Catalog: sync the new objects, then describe them.
CALL sp_sync_technical_metadata('init-postgres');

UPDATE technical_metadata AS m
SET domain = 'monitoring',
    purpose = v.purpose,
    business_rule = v.business_rule,
    sensitivity = 'RESTRITO',
    logical_owner = 'governance',
    last_reviewed_at = clock_timestamp(),
    reviewed_by = 'init-postgres'
FROM (
    VALUES
        ('daily_active_user', 'Daily access register per employee, source of the DAU metric.', 'One row per employee per UTC day; written only by sp_register_access; only ACTIVE employees.'),
        ('vw_dau', 'DAU by enterprise and day for BI.', 'Window functions and CTE. dau counts distinct employees per day.')
) AS v(table_name, purpose, business_rule)
WHERE m.object_kind = 'TABLE' AND m.table_name = v.table_name;

COMMIT;
