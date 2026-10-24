\connect dbAether2Year

BEGIN;

-- Recursive hierarchy: enterprise → unit → department, with depth and path.
CREATE OR REPLACE VIEW vw_dim_org_hierarchy AS
WITH RECURSIVE org AS (
    SELECT
        'ENTERPRISE'::text AS node_type,
        e.id AS node_id,
        e.name::text AS node_name,
        0 AS depth,
        e.id AS root_id,
        e.name::text AS path,
        e.id AS enterprise_id,
        NULL::integer AS unit_id,
        NULL::integer AS department_id
    FROM enterprise e

    UNION ALL

    SELECT
        CASE o.node_type
            WHEN 'ENTERPRISE' THEN 'UNIT'
            WHEN 'UNIT' THEN 'DEPARTMENT'
        END,
        CASE o.node_type
            WHEN 'ENTERPRISE' THEN u.id
            WHEN 'UNIT' THEN d.id
        END,
        CASE o.node_type
            WHEN 'ENTERPRISE' THEN ('Unit ' || u.cnpj)::text
            WHEN 'UNIT' THEN d.name::text
        END,
        o.depth + 1,
        o.root_id,
        CASE o.node_type
            WHEN 'ENTERPRISE' THEN (o.path || ' > Unit ' || u.cnpj)::text
            WHEN 'UNIT' THEN (o.path || ' > ' || d.name)::text
        END,
        o.enterprise_id,
        CASE o.node_type
            WHEN 'ENTERPRISE' THEN u.id
            WHEN 'UNIT' THEN o.unit_id
        END,
        CASE o.node_type
            WHEN 'UNIT' THEN d.id
            ELSE NULL::integer
        END
    FROM org o
    LEFT JOIN unit u
      ON o.node_type = 'ENTERPRISE'
     AND u.id_enterprise = o.enterprise_id
    LEFT JOIN department d
      ON o.node_type = 'UNIT'
     AND d.id_unit = o.unit_id
    WHERE (o.node_type = 'ENTERPRISE' AND u.id IS NOT NULL)
       OR (o.node_type = 'UNIT' AND d.id IS NOT NULL)
)
SELECT
    node_type,
    node_id,
    node_name,
    depth,
    root_id,
    path,
    enterprise_id,
    unit_id,
    department_id
FROM org;

COMMENT ON VIEW vw_dim_org_hierarchy IS
    'Organizational hierarchy enterprise → unit → department via recursive CTE. Grain: one node. Dimensions: type, identifier, depth, root, and path. Enterprises without descendants remain as roots. Orphan nodes are not attached. AN-FR-007.';
COMMENT ON COLUMN vw_dim_org_hierarchy.node_type IS 'Node type: ENTERPRISE, UNIT, or DEPARTMENT.';
COMMENT ON COLUMN vw_dim_org_hierarchy.node_id IS 'Node identifier at its own level.';
COMMENT ON COLUMN vw_dim_org_hierarchy.node_name IS 'Display name of the node. Units use CNPJ because they have no dedicated name.';
COMMENT ON COLUMN vw_dim_org_hierarchy.depth IS 'Depth from the enterprise (0 = root).';
COMMENT ON COLUMN vw_dim_org_hierarchy.root_id IS 'Identifier of the root enterprise for the path.';
COMMENT ON COLUMN vw_dim_org_hierarchy.path IS 'Full hierarchical path from the enterprise.';
COMMENT ON COLUMN vw_dim_org_hierarchy.enterprise_id IS 'Enterprise of the node. Equals node_id when the type is ENTERPRISE.';
COMMENT ON COLUMN vw_dim_org_hierarchy.unit_id IS 'Unit of the node; null on enterprise nodes.';
COMMENT ON COLUMN vw_dim_org_hierarchy.department_id IS 'Department of the node; null above that level.';

-- Star fact of emissions at one-row-per-emission grain.
CREATE OR REPLACE VIEW vw_fact_emission AS
SELECT
    e.id AS emission_id,
    i.id AS inventory_id,
    i.name AS inventory_name,
    i.inventorying_period_start AS period_start,
    i.inventorying_period_end AS period_end,
    i.status AS inventory_status,
    i.type AS inventory_type,
    en.id AS enterprise_id,
    en.name AS enterprise_name,
    u.id AS unit_id,
    u.cnpj AS unit_cnpj,
    d.id AS department_id,
    d.name AS department_name,
    s.id AS scope_id,
    s.name AS scope_name,
    c.id AS category_id,
    CASE WHEN e.id_category IS NULL THEN 'Uninformed' ELSE c.name END AS category_name,
    (e.id_category IS NULL) AS category_uninformed,
    c.classification AS category_classification,
    g.id AS gas_id,
    g.name AS gas_name,
    g.formula AS gas_formula,
    g.is_biogenic AS gas_is_biogenic,
    g.gwp AS gas_gwp,
    e.quantity_co2e,
    NULLIF(BTRIM(a.city::text), '') AS city,
    NULLIF(BTRIM(a.state::text), '') AS state,
    CASE WHEN a.id IS NOT NULL THEN 'Brazil'::text ELSE NULL::text END AS country
FROM emission e
JOIN inventory i ON i.id = e.id_inventory
LEFT JOIN department d ON d.id = i.id_department
LEFT JOIN unit u ON u.id = d.id_unit
LEFT JOIN enterprise en ON en.id = u.id_enterprise
LEFT JOIN address a ON a.id = u.id_address
LEFT JOIN scope s ON s.id = e.id_scope
LEFT JOIN category c ON c.id = e.id_category
LEFT JOIN gas g ON g.id = e.id_gas;

COMMENT ON COLUMN vw_fact_emission.city IS 'City from the unit address, never parsed from inventory_name. Null when unavailable.';
COMMENT ON COLUMN vw_fact_emission.state IS 'State from the unit address. Null when unavailable.';
COMMENT ON COLUMN vw_fact_emission.country IS 'Brazil for registered unit addresses: domestic-only business assumption. Review before adding foreign units.';

COMMENT ON VIEW vw_fact_emission IS
    'Star-schema emission fact. Minimum grain: one emission. Dimensions: enterprise, unit, department, inventory period, scope, category, and gas. Metric: quantity_co2e. Missing dimensions are not inferred. AN-FR-001, AN-FR-003, AN-FR-008, AN-FR-009.';
COMMENT ON COLUMN vw_fact_emission.emission_id IS 'Emission identifier (fact grain).';
COMMENT ON COLUMN vw_fact_emission.inventory_id IS 'Inventory to which the emission belongs.';
COMMENT ON COLUMN vw_fact_emission.inventory_name IS 'Name of the source inventory.';
COMMENT ON COLUMN vw_fact_emission.period_start IS 'Start of the analytical period, derived from the inventory interval.';
COMMENT ON COLUMN vw_fact_emission.period_end IS 'End of the analytical period, derived from the inventory interval.';
COMMENT ON COLUMN vw_fact_emission.inventory_status IS 'Operational inventory status, with no personal data.';
COMMENT ON COLUMN vw_fact_emission.inventory_type IS 'Inventory type (INPUT/OUTPUT).';
COMMENT ON COLUMN vw_fact_emission.enterprise_id IS 'Enterprise from the inventory department hierarchy. Null if the hierarchy is incomplete.';
COMMENT ON COLUMN vw_fact_emission.enterprise_name IS 'Enterprise name when the organizational dimension exists.';
COMMENT ON COLUMN vw_fact_emission.unit_id IS 'Unit in the hierarchy. Null if there is no department or unit.';
COMMENT ON COLUMN vw_fact_emission.unit_cnpj IS 'Unit CNPJ, used as the analytical identifier of the unit.';
COMMENT ON COLUMN vw_fact_emission.department_id IS 'Inventory department. Null when not provided.';
COMMENT ON COLUMN vw_fact_emission.department_name IS 'Department name, when present.';
COMMENT ON COLUMN vw_fact_emission.scope_id IS 'GHG scope of the emission.';
COMMENT ON COLUMN vw_fact_emission.scope_name IS 'GHG scope name.';
COMMENT ON COLUMN vw_fact_emission.category_id IS 'Emission category. Remains null when not provided.';
COMMENT ON COLUMN vw_fact_emission.category_name IS 'Category name or the Uninformed label. The label does not match a registered category.';
COMMENT ON COLUMN vw_fact_emission.category_uninformed IS 'True when the category is null in the operational fact.';
COMMENT ON COLUMN vw_fact_emission.category_classification IS 'Upstream/downstream classification of the category, when applicable.';
COMMENT ON COLUMN vw_fact_emission.gas_id IS 'Gas of the emission.';
COMMENT ON COLUMN vw_fact_emission.gas_name IS 'Gas name.';
COMMENT ON COLUMN vw_fact_emission.gas_formula IS 'Chemical formula of the gas.';
COMMENT ON COLUMN vw_fact_emission.gas_is_biogenic IS 'Indicates biogenic origin of the gas.';
COMMENT ON COLUMN vw_fact_emission.gas_gwp IS 'GWP factor used at the emission source.';
COMMENT ON COLUMN vw_fact_emission.quantity_co2e IS 'Emitted quantity in tCO2e. Aggregable without double counting at this grain.';

-- Star fact of reductions at one-row-per-reduction grain.
CREATE OR REPLACE VIEW vw_fact_reduction AS
SELECT
    r.id AS reduction_id,
    i.id AS inventory_id,
    i.name AS inventory_name,
    i.inventorying_period_start AS period_start,
    i.inventorying_period_end AS period_end,
    i.status AS inventory_status,
    i.type AS inventory_type,
    en.id AS enterprise_id,
    en.name AS enterprise_name,
    u.id AS unit_id,
    u.cnpj AS unit_cnpj,
    d.id AS department_id,
    d.name AS department_name,
    c.id AS category_id,
    CASE WHEN r.id_category IS NULL THEN 'Uninformed' ELSE c.name END AS category_name,
    (r.id_category IS NULL) AS category_uninformed,
    r.quantity_co2e,
    NULLIF(BTRIM(a.city::text), '') AS city,
    NULLIF(BTRIM(a.state::text), '') AS state,
    CASE WHEN a.id IS NOT NULL THEN 'Brazil'::text ELSE NULL::text END AS country
FROM reduction r
JOIN inventory i ON i.id = r.id_inventory
LEFT JOIN department d ON d.id = i.id_department
LEFT JOIN unit u ON u.id = d.id_unit
LEFT JOIN enterprise en ON en.id = u.id_enterprise
LEFT JOIN address a ON a.id = u.id_address
LEFT JOIN category c ON c.id = r.id_category;

COMMENT ON COLUMN vw_fact_reduction.city IS 'City from the unit address, never parsed from inventory_name. Null when unavailable.';
COMMENT ON COLUMN vw_fact_reduction.state IS 'State from the unit address. Null when unavailable.';
COMMENT ON COLUMN vw_fact_reduction.country IS 'Brazil for registered unit addresses: domestic-only business assumption. Review before adding foreign units.';

COMMENT ON VIEW vw_fact_reduction IS
    'Star-schema reduction fact. Minimum grain: one reduction. Dimensions: organizational, inventory period, and category. Does not publish gas or scope. AN-FR-002, AN-FR-003, AN-FR-008, AN-FR-009.';
COMMENT ON COLUMN vw_fact_reduction.reduction_id IS 'Reduction identifier (fact grain).';
COMMENT ON COLUMN vw_fact_reduction.inventory_id IS 'Inventory to which the reduction belongs.';
COMMENT ON COLUMN vw_fact_reduction.inventory_name IS 'Name of the source inventory.';
COMMENT ON COLUMN vw_fact_reduction.period_start IS 'Start of the analytical period, derived from the inventory interval.';
COMMENT ON COLUMN vw_fact_reduction.period_end IS 'End of the analytical period, derived from the inventory interval.';
COMMENT ON COLUMN vw_fact_reduction.inventory_status IS 'Operational inventory status, with no personal data.';
COMMENT ON COLUMN vw_fact_reduction.inventory_type IS 'Inventory type (INPUT/OUTPUT).';
COMMENT ON COLUMN vw_fact_reduction.enterprise_id IS 'Enterprise from the inventory department hierarchy.';
COMMENT ON COLUMN vw_fact_reduction.enterprise_name IS 'Enterprise name when the organizational dimension exists.';
COMMENT ON COLUMN vw_fact_reduction.unit_id IS 'Unit in the hierarchy.';
COMMENT ON COLUMN vw_fact_reduction.unit_cnpj IS 'Unit CNPJ.';
COMMENT ON COLUMN vw_fact_reduction.department_id IS 'Inventory department.';
COMMENT ON COLUMN vw_fact_reduction.department_name IS 'Department name.';
COMMENT ON COLUMN vw_fact_reduction.category_id IS 'Reduction category. Remains null when not provided.';
COMMENT ON COLUMN vw_fact_reduction.category_name IS 'Category name or the Uninformed label.';
COMMENT ON COLUMN vw_fact_reduction.category_uninformed IS 'True when the category is null in the operational fact.';
COMMENT ON COLUMN vw_fact_reduction.quantity_co2e IS 'Reduced quantity in tCO2e. Aggregable without double counting at this grain.';

-- Inventory totals by organization and period, with previous value, variation, cumulative, and rank.
CREATE OR REPLACE VIEW vw_analytics_org_period AS
WITH dimensional_prep AS (
    SELECT
        i.id AS inventory_id,
        i.name AS inventory_name,
        i.inventorying_period_start AS period_start,
        i.inventorying_period_end AS period_end,
        en.id AS enterprise_id,
        en.name AS enterprise_name,
        u.id AS unit_id,
        u.cnpj AS unit_cnpj,
        d.id AS department_id,
        d.name AS department_name
    FROM inventory i
    LEFT JOIN department d ON d.id = i.id_department
    LEFT JOIN unit u ON u.id = d.id_unit
    LEFT JOIN enterprise en ON en.id = u.id_enterprise
),
fact_totals AS (
    SELECT
        i.id AS inventory_id,
        COALESCE((
            SELECT SUM(e.quantity_co2e)
            FROM emission e
            WHERE e.id_inventory = i.id
        ), 0) AS total_emitted,
        COALESCE((
            SELECT SUM(r.quantity_co2e)
            FROM reduction r
            WHERE r.id_inventory = i.id
        ), 0) AS total_reduced
    FROM inventory i
),
composed AS (
    SELECT
        p.inventory_id,
        p.inventory_name,
        p.period_start,
        p.period_end,
        p.enterprise_id,
        p.enterprise_name,
        p.unit_id,
        p.unit_cnpj,
        p.department_id,
        p.department_name,
        t.total_emitted,
        t.total_reduced,
        t.total_emitted - t.total_reduced AS net_balance
    FROM dimensional_prep p
    JOIN fact_totals t ON t.inventory_id = p.inventory_id
),
windowed AS (
    SELECT
        c.*,
        LAG(c.total_emitted) OVER (
            PARTITION BY c.enterprise_id, c.unit_id, c.department_id
            ORDER BY c.period_start, c.inventory_id
        ) AS prev_total_emitted,
        LAG(c.total_reduced) OVER (
            PARTITION BY c.enterprise_id, c.unit_id, c.department_id
            ORDER BY c.period_start, c.inventory_id
        ) AS prev_total_reduced,
        LAG(c.net_balance) OVER (
            PARTITION BY c.enterprise_id, c.unit_id, c.department_id
            ORDER BY c.period_start, c.inventory_id
        ) AS prev_net_balance,
        SUM(c.total_emitted) OVER (
            PARTITION BY c.enterprise_id, c.unit_id, c.department_id
            ORDER BY c.period_start, c.inventory_id
        ) AS cumulative_emitted,
        SUM(c.total_reduced) OVER (
            PARTITION BY c.enterprise_id, c.unit_id, c.department_id
            ORDER BY c.period_start, c.inventory_id
        ) AS cumulative_reduced,
        SUM(c.net_balance) OVER (
            PARTITION BY c.enterprise_id, c.unit_id, c.department_id
            ORDER BY c.period_start, c.inventory_id
        ) AS cumulative_net,
        RANK() OVER (
            PARTITION BY c.enterprise_id, c.period_start
            ORDER BY c.total_emitted DESC, c.inventory_id
        ) AS rank_emitted_in_enterprise_period,
        RANK() OVER (
            PARTITION BY c.enterprise_id, c.period_start
            ORDER BY c.net_balance DESC, c.inventory_id
        ) AS rank_net_in_enterprise_period
    FROM composed c
)
SELECT
    inventory_id,
    inventory_name,
    period_start,
    period_end,
    enterprise_id,
    enterprise_name,
    unit_id,
    unit_cnpj,
    department_id,
    department_name,
    total_emitted,
    total_reduced,
    net_balance,
    prev_total_emitted,
    prev_total_reduced,
    prev_net_balance,
    total_emitted - prev_total_emitted AS variation_emitted_abs,
    CASE
        WHEN prev_total_emitted IS NULL OR prev_total_emitted = 0 THEN NULL
        ELSE (total_emitted - prev_total_emitted) / prev_total_emitted * 100
    END AS variation_emitted_pct,
    total_reduced - prev_total_reduced AS variation_reduced_abs,
    CASE
        WHEN prev_total_reduced IS NULL OR prev_total_reduced = 0 THEN NULL
        ELSE (total_reduced - prev_total_reduced) / prev_total_reduced * 100
    END AS variation_reduced_pct,
    net_balance - prev_net_balance AS variation_net_abs,
    CASE
        WHEN prev_net_balance IS NULL OR prev_net_balance = 0 THEN NULL
        ELSE (net_balance - prev_net_balance) / prev_net_balance * 100
    END AS variation_net_pct,
    cumulative_emitted,
    cumulative_reduced,
    cumulative_net,
    rank_emitted_in_enterprise_period,
    rank_net_in_enterprise_period,
    NULLIF(BTRIM(a_geo.city::text), '') AS city,
    NULLIF(BTRIM(a_geo.state::text), '') AS state,
    CASE WHEN a_geo.id IS NOT NULL THEN 'Brazil'::text ELSE NULL::text END AS country
FROM windowed w
LEFT JOIN inventory i_geo ON i_geo.id = w.inventory_id
LEFT JOIN department d_geo ON d_geo.id = i_geo.id_department
LEFT JOIN unit u_geo ON u_geo.id = d_geo.id_unit
LEFT JOIN address a_geo ON a_geo.id = u_geo.id_address;

COMMENT ON COLUMN vw_analytics_org_period.city IS 'City from the unit address, never parsed from inventory_name. Null when unavailable.';
COMMENT ON COLUMN vw_analytics_org_period.state IS 'State from the unit address. Null when unavailable.';
COMMENT ON COLUMN vw_analytics_org_period.country IS 'Brazil for registered unit addresses: domestic-only business assumption. Review before adding foreign units.';

COMMENT ON VIEW vw_analytics_org_period IS
    'Analytical contract by inventory/period with CTEs for dimensional preparation, aggregation, and composition, plus window functions for previous period, variation, cumulative totals, and ranking. Inventories without facts appear with zero totals. AN-FR-004, AN-FR-005, AN-FR-006.';
COMMENT ON COLUMN vw_analytics_org_period.inventory_id IS 'Aggregated inventory. Grain of the view.';
COMMENT ON COLUMN vw_analytics_org_period.inventory_name IS 'Inventory name.';
COMMENT ON COLUMN vw_analytics_org_period.period_start IS 'Start of the inventory period, with no allocation across years.';
COMMENT ON COLUMN vw_analytics_org_period.period_end IS 'End of the inventory period.';
COMMENT ON COLUMN vw_analytics_org_period.enterprise_id IS 'Enterprise of the organizational partition.';
COMMENT ON COLUMN vw_analytics_org_period.enterprise_name IS 'Enterprise name.';
COMMENT ON COLUMN vw_analytics_org_period.unit_id IS 'Unit of the organizational partition.';
COMMENT ON COLUMN vw_analytics_org_period.unit_cnpj IS 'Unit CNPJ.';
COMMENT ON COLUMN vw_analytics_org_period.department_id IS 'Department of the organizational partition.';
COMMENT ON COLUMN vw_analytics_org_period.department_name IS 'Department name.';
COMMENT ON COLUMN vw_analytics_org_period.total_emitted IS 'Sum of inventory emissions in tCO2e. Zero when there are no facts.';
COMMENT ON COLUMN vw_analytics_org_period.total_reduced IS 'Sum of inventory reductions in tCO2e. Zero when there are no facts.';
COMMENT ON COLUMN vw_analytics_org_period.net_balance IS 'Net balance emitted - reduced. May be negative.';
COMMENT ON COLUMN vw_analytics_org_period.prev_total_emitted IS 'Emission of the previous period in the organizational partition. Null if there is no previous period.';
COMMENT ON COLUMN vw_analytics_org_period.prev_total_reduced IS 'Reduction of the previous period in the organizational partition. Null if there is no previous period.';
COMMENT ON COLUMN vw_analytics_org_period.prev_net_balance IS 'Net balance of the previous period in the organizational partition. Null if there is no previous period.';
COMMENT ON COLUMN vw_analytics_org_period.variation_emitted_abs IS 'Absolute emission variation versus the previous period. Null without a previous period.';
COMMENT ON COLUMN vw_analytics_org_period.variation_emitted_pct IS 'Percentage emission variation. Null if the previous period is missing or equal to zero.';
COMMENT ON COLUMN vw_analytics_org_period.variation_reduced_abs IS 'Absolute reduction variation versus the previous period.';
COMMENT ON COLUMN vw_analytics_org_period.variation_reduced_pct IS 'Percentage reduction variation. Null if the previous base is missing or zero.';
COMMENT ON COLUMN vw_analytics_org_period.variation_net_abs IS 'Absolute net-balance variation.';
COMMENT ON COLUMN vw_analytics_org_period.variation_net_pct IS 'Percentage net-balance variation. Null if the previous base is missing or zero.';
COMMENT ON COLUMN vw_analytics_org_period.cumulative_emitted IS 'Cumulative emissions in the organizational partition ordered by period.';
COMMENT ON COLUMN vw_analytics_org_period.cumulative_reduced IS 'Cumulative reductions in the organizational partition ordered by period.';
COMMENT ON COLUMN vw_analytics_org_period.cumulative_net IS 'Cumulative net balance in the organizational partition.';
COMMENT ON COLUMN vw_analytics_org_period.rank_emitted_in_enterprise_period IS 'Emission ranking within the enterprise in the period.';
COMMENT ON COLUMN vw_analytics_org_period.rank_net_in_enterprise_period IS 'Net-balance ranking within the enterprise in the period.';

-- Resolves the organizational visibility shared by all dashboard functions.
CREATE OR REPLACE FUNCTION fn_dash_visible_units(
    p_employee_id integer,
    p_plant_id integer,
    p_visibility_permission_pattern text
)
RETURNS TABLE (
    unit_id integer,
    enterprise_id integer,
    has_high_visibility boolean
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_unit_id integer;
    v_enterprise_id integer;
    v_permission_group_id integer;
    v_has_high_visibility boolean;
BEGIN
    IF p_employee_id IS NULL THEN
        RAISE EXCEPTION 'employee_id is required'
            USING ERRCODE = '22023';
    END IF;

    IF p_visibility_permission_pattern IS NULL
       OR btrim(p_visibility_permission_pattern) = '' THEN
        RAISE EXCEPTION 'visibility_permission_pattern is required'
            USING ERRCODE = '22023';
    END IF;

    SELECT
        u.id,
        u.id_enterprise,
        e.id_permission_group
    INTO
        v_unit_id,
        v_enterprise_id,
        v_permission_group_id
    FROM employee e
    LEFT JOIN department d ON d.id = e.id_department
    LEFT JOIN unit u ON u.id = d.id_unit
    WHERE e.id = p_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Employee % not found', p_employee_id
            USING ERRCODE = '23503';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM permission_group_permission pgp
        JOIN permission p ON p.id = pgp.id_permission
        WHERE pgp.id_permission_group = v_permission_group_id
          AND p_visibility_permission_pattern ~ p.pattern
    )
    INTO v_has_high_visibility;

    RETURN QUERY
    SELECT
        u.id,
        u.id_enterprise,
        v_has_high_visibility
    FROM unit u
    WHERE u.id_enterprise = v_enterprise_id
      AND (v_has_high_visibility OR u.id = v_unit_id)
      AND (p_plant_id IS NULL OR u.id = p_plant_id)
    ORDER BY u.id;
END;
$$;

COMMENT ON FUNCTION fn_dash_visible_units(integer, integer, text) IS
    'Returns the optionally selected plant when visible to an employee, using the permission probe supplied by the caller. Raises 22023 for invalid parameters and 23503 when the employee is absent. DASH-FR-001, DASH-FR-002, DASH-FR-003, DASH-FR-004, DASH-FR-016.';

-- Returns generated savings for the reference year and its YoY variation.
CREATE OR REPLACE FUNCTION fn_dash_generated_savings(
    p_employee_id integer,
    p_reference_year integer,
    p_months integer[],
    p_plant_id integer,
    p_visibility_permission_pattern text,
    p_previous_year_offset integer,
    p_percentage_scale numeric
)
RETURNS TABLE (
    total_tco2e numeric,
    previous_tco2e numeric,
    variation_pct numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_reference_year IS NULL
       OR p_previous_year_offset IS NULL OR p_previous_year_offset <= 0
       OR p_percentage_scale IS NULL OR p_percentage_scale <= 0
       OR EXISTS (
           SELECT 1 FROM unnest(p_months) AS selected_month
           WHERE selected_month IS NULL OR selected_month NOT BETWEEN 1 AND 12
       ) THEN
        RAISE EXCEPTION 'invalid dashboard parameters'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH visible AS MATERIALIZED (
        SELECT vu.unit_id
        FROM fn_dash_visible_units(
            p_employee_id,
            p_plant_id,
            p_visibility_permission_pattern
        ) vu
    ),
    totals AS (
        SELECT
            SUM(fr.quantity_co2e) FILTER (
                WHERE EXTRACT(YEAR FROM fr.period_start)::integer = p_reference_year
            ) AS current_total,
            SUM(fr.quantity_co2e) FILTER (
                WHERE EXTRACT(YEAR FROM fr.period_start)::integer = p_reference_year - p_previous_year_offset
            ) AS previous_total
        FROM vw_fact_reduction fr
        JOIN visible vu ON vu.unit_id = fr.unit_id
        WHERE fr.unit_id IS NOT NULL
          AND EXTRACT(YEAR FROM fr.period_start)::integer IN (
              p_reference_year,
              p_reference_year - p_previous_year_offset
          )
          AND (
              p_months IS NULL
              OR cardinality(p_months) = 0
              OR EXTRACT(MONTH FROM fr.period_start)::integer = ANY(p_months)
          )
    )
    SELECT
        COALESCE(t.current_total, 0),
        t.previous_total,
        CASE
            WHEN t.previous_total IS NULL OR t.previous_total = 0 THEN NULL
            ELSE (COALESCE(t.current_total, 0) - t.previous_total)
                / t.previous_total * p_percentage_scale
        END
    FROM totals t;
END;
$$;

COMMENT ON FUNCTION fn_dash_generated_savings(integer, integer, integer[], integer, text, integer, numeric) IS
    'Returns filtered reduction savings in tCO2e for the reference and caller-defined comparison years, with caller-defined percentage scale. DASH-FR-001, DASH-FR-004, DASH-FR-005, DASH-FR-014, DASH-NFR-002, DASH-NFR-004.';

-- Counts inventory insertions in the reference and previous years.
CREATE OR REPLACE FUNCTION fn_dash_analyses(
    p_employee_id integer,
    p_reference_year integer,
    p_months integer[],
    p_plant_id integer,
    p_visibility_permission_pattern text,
    p_previous_year_offset integer,
    p_percentage_scale numeric
)
RETURNS TABLE (
    analyses_count integer,
    previous_count integer,
    variation_pct numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_reference_year IS NULL
       OR p_previous_year_offset IS NULL OR p_previous_year_offset <= 0
       OR p_percentage_scale IS NULL OR p_percentage_scale <= 0
       OR EXISTS (
           SELECT 1 FROM unnest(p_months) AS selected_month
           WHERE selected_month IS NULL OR selected_month NOT BETWEEN 1 AND 12
       ) THEN
        RAISE EXCEPTION 'invalid dashboard parameters'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH visible AS MATERIALIZED (
        SELECT vu.unit_id
        FROM fn_dash_visible_units(
            p_employee_id,
            p_plant_id,
            p_visibility_permission_pattern
        ) vu
    ),
    counts AS (
        SELECT
            COUNT(*) FILTER (
                WHERE EXTRACT(YEAR FROM i.created_at)::integer = p_reference_year
            )::integer AS current_count,
            COUNT(*) FILTER (
                WHERE EXTRACT(YEAR FROM i.created_at)::integer = p_reference_year - p_previous_year_offset
            )::integer AS prior_count
        FROM inventory i
        JOIN department d ON d.id = i.id_department
        JOIN visible vu ON vu.unit_id = d.id_unit
        WHERE d.id_unit IS NOT NULL
          AND EXTRACT(YEAR FROM i.created_at)::integer IN (
              p_reference_year,
              p_reference_year - p_previous_year_offset
          )
          AND (
              p_months IS NULL
              OR cardinality(p_months) = 0
              OR EXTRACT(MONTH FROM i.created_at)::integer = ANY(p_months)
          )
    )
    SELECT
        c.current_count,
        c.prior_count,
        CASE
            WHEN c.prior_count = 0 THEN NULL
            ELSE (c.current_count - c.prior_count)::numeric
                / c.prior_count * p_percentage_scale
        END
    FROM counts c;
END;
$$;

COMMENT ON FUNCTION fn_dash_analyses(integer, integer, integer[], integer, text, integer, numeric) IS
    'Counts filtered inventory insertions for caller-defined reference and comparison years and percentage scale. DASH-FR-001, DASH-FR-004, DASH-FR-006, DASH-FR-014, DASH-NFR-002.';

-- Counts active plants with at least one inventory insertion in each year.
CREATE OR REPLACE FUNCTION fn_dash_active_plants(
    p_employee_id integer,
    p_reference_year integer,
    p_months integer[],
    p_plant_id integer,
    p_visibility_permission_pattern text,
    p_previous_year_offset integer,
    p_percentage_scale numeric,
    p_required_active_status boolean
)
RETURNS TABLE (
    active_count integer,
    previous_count integer,
    variation_pct numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_reference_year IS NULL
       OR p_previous_year_offset IS NULL OR p_previous_year_offset <= 0
       OR p_percentage_scale IS NULL OR p_percentage_scale <= 0
       OR p_required_active_status IS NULL
       OR EXISTS (
           SELECT 1 FROM unnest(p_months) AS selected_month
           WHERE selected_month IS NULL OR selected_month NOT BETWEEN 1 AND 12
       ) THEN
        RAISE EXCEPTION 'invalid dashboard parameters'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH visible AS MATERIALIZED (
        SELECT vu.unit_id
        FROM fn_dash_visible_units(
            p_employee_id,
            p_plant_id,
            p_visibility_permission_pattern
        ) vu
    ),
    counts AS (
        SELECT
            COUNT(*) FILTER (
                WHERE u.is_active IS NOT DISTINCT FROM p_required_active_status
                  AND EXTRACT(YEAR FROM u.created_at)::integer <= p_reference_year
                  AND EXISTS (
                      SELECT 1
                      FROM inventory i
                      JOIN department d ON d.id = i.id_department
                      WHERE d.id_unit = u.id
                        AND EXTRACT(YEAR FROM i.created_at)::integer = p_reference_year
                        AND (
                            p_months IS NULL
                            OR cardinality(p_months) = 0
                            OR EXTRACT(MONTH FROM i.created_at)::integer = ANY(p_months)
                        )
                  )
            )::integer AS current_count,
            COUNT(*) FILTER (
                WHERE u.is_active IS NOT DISTINCT FROM p_required_active_status
                  AND EXTRACT(YEAR FROM u.created_at)::integer
                      <= p_reference_year - p_previous_year_offset
                  AND EXISTS (
                      SELECT 1
                      FROM inventory i
                      JOIN department d ON d.id = i.id_department
                      WHERE d.id_unit = u.id
                        AND EXTRACT(YEAR FROM i.created_at)::integer
                            = p_reference_year - p_previous_year_offset
                        AND (
                            p_months IS NULL
                            OR cardinality(p_months) = 0
                            OR EXTRACT(MONTH FROM i.created_at)::integer = ANY(p_months)
                        )
                  )
            )::integer AS prior_count
        FROM unit u
        JOIN visible vu ON vu.unit_id = u.id
    )
    SELECT
        c.current_count,
        c.prior_count,
        CASE
            WHEN c.prior_count = 0 THEN NULL
            ELSE (c.current_count - c.prior_count)::numeric
                / c.prior_count * p_percentage_scale
        END
    FROM counts c;
END;
$$;

COMMENT ON FUNCTION fn_dash_active_plants(integer, integer, integer[], integer, text, integer, numeric, boolean) IS
    'Counts filtered visible units matching the caller-defined active status in the reference and comparison years. DASH-FR-001, DASH-FR-004, DASH-FR-007, DASH-FR-014, DASH-NFR-002.';

-- Returns the mean interval between consecutive inventory insertions.
CREATE OR REPLACE FUNCTION fn_dash_average_insertion_interval(
    p_employee_id integer,
    p_reference_year integer,
    p_months integer[],
    p_plant_id integer,
    p_visibility_permission_pattern text,
    p_seconds_per_day numeric
)
RETURNS TABLE (
    average_interval_days numeric,
    sample_size integer
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_reference_year IS NULL
       OR p_seconds_per_day IS NULL OR p_seconds_per_day <= 0
       OR EXISTS (
           SELECT 1 FROM unnest(p_months) AS selected_month
           WHERE selected_month IS NULL OR selected_month NOT BETWEEN 1 AND 12
       ) THEN
        RAISE EXCEPTION 'invalid dashboard parameters'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH visible AS MATERIALIZED (
        SELECT vu.unit_id
        FROM fn_dash_visible_units(
            p_employee_id,
            p_plant_id,
            p_visibility_permission_pattern
        ) vu
    ),
    ordered_insertions AS (
        SELECT
            i.created_at,
            LAG(i.created_at) OVER (ORDER BY i.created_at, i.id) AS previous_created_at
        FROM inventory i
        JOIN department d ON d.id = i.id_department
        JOIN visible vu ON vu.unit_id = d.id_unit
        WHERE d.id_unit IS NOT NULL
          AND EXTRACT(YEAR FROM i.created_at)::integer = p_reference_year
          AND (
              p_months IS NULL
              OR cardinality(p_months) = 0
              OR EXTRACT(MONTH FROM i.created_at)::integer = ANY(p_months)
          )
    )
    SELECT
        AVG(EXTRACT(EPOCH FROM (oi.created_at - oi.previous_created_at)) / p_seconds_per_day)
            FILTER (WHERE oi.previous_created_at IS NOT NULL),
        COUNT(*)::integer
    FROM ordered_insertions oi;
END;
$$;

COMMENT ON FUNCTION fn_dash_average_insertion_interval(integer, integer, integer[], integer, text, numeric) IS
    'Returns the filtered average consecutive inventory insertion interval using the caller-defined seconds-per-day conversion. DASH-FR-001, DASH-FR-004, DASH-FR-009, DASH-FR-014.';

-- Returns savings and net reduction percentage for every visible plant.
CREATE OR REPLACE FUNCTION fn_dash_plants_table(
    p_employee_id integer,
    p_reference_year integer,
    p_months integer[],
    p_plant_id integer,
    p_visibility_permission_pattern text,
    p_percentage_scale numeric,
    p_minimum_reduction_pct numeric
)
RETURNS TABLE (
    plant_id integer,
    plant_name text,
    economia_tco2e numeric,
    reducao_pct numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_reference_year IS NULL
       OR p_percentage_scale IS NULL OR p_percentage_scale <= 0
       OR p_minimum_reduction_pct IS NULL
       OR EXISTS (
           SELECT 1 FROM unnest(p_months) AS selected_month
           WHERE selected_month IS NULL OR selected_month NOT BETWEEN 1 AND 12
       ) THEN
        RAISE EXCEPTION 'invalid dashboard parameters'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH visible AS MATERIALIZED (
        SELECT vu.unit_id
        FROM fn_dash_visible_units(
            p_employee_id,
            p_plant_id,
            p_visibility_permission_pattern
        ) vu
    ),
    emitted AS (
        SELECT fe.unit_id, SUM(fe.quantity_co2e) AS total
        FROM vw_fact_emission fe
        JOIN visible vu ON vu.unit_id = fe.unit_id
        WHERE fe.unit_id IS NOT NULL
          AND EXTRACT(YEAR FROM fe.period_start)::integer = p_reference_year
          AND (
              p_months IS NULL
              OR cardinality(p_months) = 0
              OR EXTRACT(MONTH FROM fe.period_start)::integer = ANY(p_months)
          )
        GROUP BY fe.unit_id
    ),
    reduced AS (
        SELECT fr.unit_id, SUM(fr.quantity_co2e) AS total
        FROM vw_fact_reduction fr
        JOIN visible vu ON vu.unit_id = fr.unit_id
        WHERE fr.unit_id IS NOT NULL
          AND EXTRACT(YEAR FROM fr.period_start)::integer = p_reference_year
          AND (
              p_months IS NULL
              OR cardinality(p_months) = 0
              OR EXTRACT(MONTH FROM fr.period_start)::integer = ANY(p_months)
          )
        GROUP BY fr.unit_id
    )
    SELECT
        u.id,
        u.cnpj::text,
        COALESCE(r.total, 0),
        CASE
            WHEN COALESCE(e.total, 0) = 0 THEN NULL
            ELSE GREATEST(
                p_minimum_reduction_pct,
                (e.total - COALESCE(r.total, 0)) / e.total * p_percentage_scale
            )
        END
    FROM visible vu
    JOIN unit u ON u.id = vu.unit_id
    LEFT JOIN emitted e ON e.unit_id = u.id
    LEFT JOIN reduced r ON r.unit_id = u.id
    ORDER BY u.id;
END;
$$;

COMMENT ON FUNCTION fn_dash_plants_table(integer, integer, integer[], integer, text, numeric, numeric) IS
    'Returns filtered visible plants with annual reduction savings and caller-defined percentage scale and floor. DASH-FR-001, DASH-FR-004, DASH-FR-010, DASH-FR-014, DASH-NFR-002, DASH-NFR-004.';

-- Detects lower-tail production anomalies from each plant's historical distribution.
CREATE OR REPLACE FUNCTION fn_dash_production_alert(
    p_employee_id integer,
    p_reference_year integer,
    p_months integer[],
    p_plant_id integer,
    p_visibility_permission_pattern text,
    p_stddev_multiplier numeric,
    p_minimum_history_years integer
)
RETURNS TABLE (
    plant_id integer,
    plant_name text,
    last_year integer,
    last_year_tco2e numeric,
    historical_mean_tco2e numeric,
    historical_stddev_tco2e numeric,
    sample_years integer,
    threshold_tco2e numeric,
    is_alert boolean
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_reference_year IS NULL
       OR p_stddev_multiplier IS NULL OR p_stddev_multiplier < 0
       OR p_minimum_history_years IS NULL OR p_minimum_history_years <= 0
       OR EXISTS (
           SELECT 1 FROM unnest(p_months) AS selected_month
           WHERE selected_month IS NULL OR selected_month NOT BETWEEN 1 AND 12
       ) THEN
        RAISE EXCEPTION 'invalid dashboard parameters'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH visible AS MATERIALIZED (
        SELECT vu.unit_id
        FROM fn_dash_visible_units(
            p_employee_id,
            p_plant_id,
            p_visibility_permission_pattern
        ) vu
    ),
    annual_series AS (
        SELECT
            fe.unit_id,
            EXTRACT(YEAR FROM fe.period_start)::integer AS period_year,
            SUM(fe.quantity_co2e) AS total_tco2e
        FROM vw_fact_emission fe
        JOIN visible vu ON vu.unit_id = fe.unit_id
        WHERE fe.unit_id IS NOT NULL
          AND EXTRACT(YEAR FROM fe.period_start)::integer <= p_reference_year
          AND (
              p_months IS NULL
              OR cardinality(p_months) = 0
              OR EXTRACT(MONTH FROM fe.period_start)::integer = ANY(p_months)
          )
        GROUP BY fe.unit_id, EXTRACT(YEAR FROM fe.period_start)::integer
    ),
    plant_stats AS (
        SELECT
            u.id AS unit_id,
            u.cnpj::text AS unit_name,
            p_reference_year AS period_year,
            COALESCE(current_year.total_tco2e, 0) AS current_total,
            history.mean_tco2e,
            history.stddev_tco2e,
            COALESCE(history.year_count, 0)::integer AS year_count
        FROM visible vu
        JOIN unit u ON u.id = vu.unit_id
        LEFT JOIN annual_series current_year
          ON current_year.unit_id = u.id
         AND current_year.period_year = p_reference_year
        LEFT JOIN LATERAL (
            SELECT
                AVG(s.total_tco2e) AS mean_tco2e,
                STDDEV_SAMP(s.total_tco2e) AS stddev_tco2e,
                COUNT(*) AS year_count
            FROM annual_series s
            WHERE s.unit_id = u.id
              AND s.period_year < p_reference_year
        ) history ON true
    )
    SELECT
        ps.unit_id,
        ps.unit_name,
        ps.period_year,
        ps.current_total,
        ps.mean_tco2e,
        ps.stddev_tco2e,
        ps.year_count,
        ps.mean_tco2e - (p_stddev_multiplier * ps.stddev_tco2e),
        ps.year_count >= p_minimum_history_years
            AND ps.stddev_tco2e IS NOT NULL
            AND ps.current_total
                < ps.mean_tco2e - (p_stddev_multiplier * ps.stddev_tco2e)
    FROM plant_stats ps
    ORDER BY ps.unit_id;
END;
$$;

COMMENT ON FUNCTION fn_dash_production_alert(integer, integer, integer[], integer, text, numeric, integer) IS
    'Returns filtered lower-tail production alerts using historical mean minus a caller-defined multiple of sample standard deviation. DASH-FR-001, DASH-FR-004, DASH-FR-008, DASH-FR-011, DASH-FR-014, DASH-NFR-004.';

-- Counts critical production alerts in the reference and previous years.
CREATE OR REPLACE FUNCTION fn_dash_critical_anomalies(
    p_employee_id integer,
    p_reference_year integer,
    p_months integer[],
    p_plant_id integer,
    p_visibility_permission_pattern text,
    p_previous_year_offset integer,
    p_percentage_scale numeric,
    p_stddev_multiplier numeric,
    p_minimum_history_years integer
)
RETURNS TABLE (
    critical_count integer,
    previous_count integer,
    variation_pct numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_reference_year IS NULL
       OR p_previous_year_offset IS NULL OR p_previous_year_offset <= 0
       OR p_percentage_scale IS NULL OR p_percentage_scale <= 0 THEN
        RAISE EXCEPTION 'invalid dashboard parameters'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH visible AS MATERIALIZED (
        SELECT vu.unit_id
        FROM fn_dash_visible_units(
            p_employee_id,
            p_plant_id,
            p_visibility_permission_pattern
        ) vu
    ),
    visibility_guard AS MATERIALIZED (
        SELECT COUNT(*) AS unit_count
        FROM visible
    ),
    counts AS (
        SELECT
            (
                SELECT COUNT(*)::integer
                FROM fn_dash_production_alert(
                    p_employee_id,
                    p_reference_year,
                    p_months,
                    p_plant_id,
                    p_visibility_permission_pattern,
                    p_stddev_multiplier,
                    p_minimum_history_years
                ) a
                WHERE a.is_alert
            ) AS current_count,
            (
                SELECT COUNT(*)::integer
                FROM fn_dash_production_alert(
                    p_employee_id,
                    p_reference_year - p_previous_year_offset,
                    p_months,
                    p_plant_id,
                    p_visibility_permission_pattern,
                    p_stddev_multiplier,
                    p_minimum_history_years
                ) a
                WHERE a.is_alert
            ) AS prior_count
        FROM visibility_guard
    )
    SELECT
        c.current_count,
        c.prior_count,
        CASE
            WHEN c.prior_count = 0 THEN NULL
            ELSE (c.current_count - c.prior_count)::numeric
                / c.prior_count * p_percentage_scale
        END
    FROM counts c;
END;
$$;

COMMENT ON FUNCTION fn_dash_critical_anomalies(integer, integer, integer[], integer, text, integer, numeric, numeric, integer) IS
    'Counts filtered production alerts in caller-defined comparison years using the same statistical parameters as fn_dash_production_alert. DASH-FR-001, DASH-FR-004, DASH-FR-008, DASH-FR-014, DASH-NFR-002.';

-- Returns annual polluting, biogenic, and reduced tCO2e series.
CREATE OR REPLACE FUNCTION fn_dash_emissions_series(
    p_employee_id integer,
    p_start_year integer,
    p_end_year integer,
    p_months integer[],
    p_plant_id integer,
    p_visibility_permission_pattern text
)
RETURNS TABLE (
    period_year integer,
    polluting_tco2e numeric,
    green_tco2e numeric,
    reduced_tco2e numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_start_year IS NULL OR p_end_year IS NULL OR p_start_year > p_end_year
       OR EXISTS (
           SELECT 1 FROM unnest(p_months) AS selected_month
           WHERE selected_month IS NULL OR selected_month NOT BETWEEN 1 AND 12
       ) THEN
        RAISE EXCEPTION 'invalid dashboard parameters'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH visible AS MATERIALIZED (
        SELECT vu.unit_id
        FROM fn_dash_visible_units(
            p_employee_id,
            p_plant_id,
            p_visibility_permission_pattern
        ) vu
    ),
    emissions AS (
        SELECT
            EXTRACT(YEAR FROM fe.period_start)::integer AS fact_year,
            SUM(fe.quantity_co2e) FILTER (WHERE NOT fe.gas_is_biogenic) AS polluting,
            SUM(fe.quantity_co2e) FILTER (WHERE fe.gas_is_biogenic) AS green
        FROM vw_fact_emission fe
        JOIN visible vu ON vu.unit_id = fe.unit_id
        WHERE fe.unit_id IS NOT NULL
          AND EXTRACT(YEAR FROM fe.period_start)::integer
              BETWEEN p_start_year AND p_end_year
          AND (
              p_months IS NULL
              OR cardinality(p_months) = 0
              OR EXTRACT(MONTH FROM fe.period_start)::integer = ANY(p_months)
          )
        GROUP BY EXTRACT(YEAR FROM fe.period_start)::integer
    ),
    reductions AS (
        SELECT
            EXTRACT(YEAR FROM fr.period_start)::integer AS fact_year,
            SUM(fr.quantity_co2e) AS reduced
        FROM vw_fact_reduction fr
        JOIN visible vu ON vu.unit_id = fr.unit_id
        WHERE fr.unit_id IS NOT NULL
          AND EXTRACT(YEAR FROM fr.period_start)::integer
              BETWEEN p_start_year AND p_end_year
          AND (
              p_months IS NULL
              OR cardinality(p_months) = 0
              OR EXTRACT(MONTH FROM fr.period_start)::integer = ANY(p_months)
          )
        GROUP BY EXTRACT(YEAR FROM fr.period_start)::integer
    ),
    years AS (
        SELECT e.fact_year FROM emissions e
        UNION
        SELECT r.fact_year FROM reductions r
    )
    SELECT
        y.fact_year,
        COALESCE(e.polluting, 0),
        COALESCE(e.green, 0),
        COALESCE(r.reduced, 0)
    FROM years y
    LEFT JOIN emissions e ON e.fact_year = y.fact_year
    LEFT JOIN reductions r ON r.fact_year = y.fact_year
    ORDER BY y.fact_year;
END;
$$;

COMMENT ON FUNCTION fn_dash_emissions_series(integer, integer, integer, integer[], integer, text) IS
    'Returns the filtered annual series of non-biogenic emissions, biogenic emissions, and reductions within a caller-defined year range. DASH-FR-001, DASH-FR-004, DASH-FR-012, DASH-NFR-004.';

-- Returns annual emission totals and shares by scope.
CREATE OR REPLACE FUNCTION fn_dash_emissions_by_scope(
    p_employee_id integer,
    p_reference_year integer,
    p_months integer[],
    p_plant_id integer,
    p_visibility_permission_pattern text,
    p_percentage_scale numeric
)
RETURNS TABLE (
    scope_id integer,
    scope_name text,
    emitted_tco2e numeric,
    share_pct numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_reference_year IS NULL
       OR p_percentage_scale IS NULL OR p_percentage_scale <= 0
       OR EXISTS (
           SELECT 1 FROM unnest(p_months) AS selected_month
           WHERE selected_month IS NULL OR selected_month NOT BETWEEN 1 AND 12
       ) THEN
        RAISE EXCEPTION 'invalid dashboard parameters'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH visible AS MATERIALIZED (
        SELECT vu.unit_id
        FROM fn_dash_visible_units(
            p_employee_id,
            p_plant_id,
            p_visibility_permission_pattern
        ) vu
    ),
    by_scope AS (
        SELECT
            fe.scope_id,
            fe.scope_name::text,
            SUM(fe.quantity_co2e) AS emitted
        FROM vw_fact_emission fe
        JOIN visible vu ON vu.unit_id = fe.unit_id
        WHERE fe.unit_id IS NOT NULL
          AND fe.scope_id IS NOT NULL
          AND EXTRACT(YEAR FROM fe.period_start)::integer = p_reference_year
          AND (
              p_months IS NULL
              OR cardinality(p_months) = 0
              OR EXTRACT(MONTH FROM fe.period_start)::integer = ANY(p_months)
          )
        GROUP BY fe.scope_id, fe.scope_name
    ),
    with_total AS (
        SELECT
            bs.*,
            SUM(bs.emitted) OVER () AS total_emitted
        FROM by_scope bs
    )
    SELECT
        wt.scope_id,
        wt.scope_name,
        wt.emitted,
        wt.emitted / wt.total_emitted * p_percentage_scale
    FROM with_total wt
    WHERE wt.total_emitted <> 0
    ORDER BY wt.scope_id;
END;
$$;

COMMENT ON FUNCTION fn_dash_emissions_by_scope(integer, integer, integer[], integer, text, numeric) IS
    'Returns filtered emitted tCO2e and caller-scaled participation by scope, with no rows when the total is zero. DASH-FR-001, DASH-FR-004, DASH-FR-013, DASH-FR-014, DASH-NFR-002, DASH-NFR-004.';

-- Manual cells of the complete GHG emission declaration (frames 1.1, 1.2, 1.3, 1.5).
CREATE OR REPLACE FUNCTION fn_ghg_complete_declaration(
    p_enterprise_id integer
)
RETURNS TABLE (
    quadro text,
    eixo   text,
    codigo text,
    valor  numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_target_year integer;
    v_period_start date;
    v_period_end date;
BEGIN
    IF p_enterprise_id IS NULL THEN
        RAISE EXCEPTION 'enterprise_id is required'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM enterprise e
        WHERE e.id = p_enterprise_id
    ) THEN
        RAISE EXCEPTION 'Enterprise % not found', p_enterprise_id
            USING ERRCODE = '23503';
    END IF;

    v_target_year := EXTRACT(YEAR FROM CURRENT_DATE)::integer - 1;
    v_period_start := make_date(v_target_year, 1, 1);
    v_period_end := make_date(v_target_year, 12, 31);

    RETURN QUERY
    WITH skeleton AS (
        SELECT '1.1'::text AS cell_quadro, 'GAS'::text AS cell_eixo, gas_code AS cell_codigo
        FROM unnest(ARRAY[
            'CO2', 'CH4', 'N2O', 'HFCs',
            'HFC-23', 'HFC-32', 'HFC-41', 'HFC-125', 'HFC-134', 'HFC-134a',
            'HFC-143', 'HFC-143a', 'HFC-152', 'HFC-152a', 'HFC-161',
            'HFC-227ea', 'HFC-236cb', 'HFC-236ea', 'HFC-236fa',
            'HFC-245ca', 'HFC-245fa', 'HFC-365mfc', 'HFC-43-10mee',
            'PFCs',
            'PFC-14', 'PFC-116', 'PFC-218', 'PFC-318',
            'PFC-3-1-10', 'PFC-4-1-12', 'PFC-5-1-14', 'PFC-9-1-18',
            'trifluorometil_pentafluoreto_enxofre', 'perfluorociclopropano',
            'SF6', 'NF3'
        ]::text[]) AS gas_code

        UNION ALL
        SELECT '1.1', 'CATEGORIA', cat_code
        FROM unnest(ARRAY[
            'combustao_movel',
            'combustao_estacionaria',
            'emissoes_fugitivas',
            'processos_industriais',
            'atividades_agricolas_e_mudancas_uso_solo',
            'residuos'
        ]::text[]) AS cat_code

        UNION ALL
        SELECT frame, 'GAS', gas_code
        FROM unnest(ARRAY['1.2', '1.3']::text[]) AS frame
        CROSS JOIN unnest(ARRAY[
            'CO2', 'CH4', 'N2O', 'HFC', 'PFC', 'SF6', 'NF3'
        ]::text[]) AS gas_code

        UNION ALL
        SELECT '1.2', 'CATEGORIA', cat_code
        FROM unnest(ARRAY[
            'energia_eletrica_localizacao',
            'energia_termica',
            'perdas_transmissao_distribuicao'
        ]::text[]) AS cat_code

        UNION ALL
        SELECT '1.3', axis, cat_code
        FROM unnest(ARRAY[
            'CATEGORIA', 'BIOGENICO_EMISSAO', 'BIOGENICO_REMOCAO'
        ]::text[]) AS axis
        CROSS JOIN unnest(ARRAY[
            'transporte_distribuicao_upstream',
            'residuos_solidos_operacao',
            'efluentes_liquidos',
            'viagens_a_negocios',
            'deslocamento_casa_trabalho',
            'transporte_distribuicao_downstream',
            'outras_escopo_iii'
        ]::text[]) AS cat_code

        UNION ALL
        SELECT '1.5', axis, scope_code
        FROM unnest(ARRAY[
            'BIOGENICO_EMISSAO', 'BIOGENICO_REMOCAO'
        ]::text[]) AS axis
        CROSS JOIN unnest(ARRAY['ESCOPO_I', 'ESCOPO_II']::text[]) AS scope_code
    ),
    quadro_scope AS (
        SELECT *
        FROM (VALUES
            ('1.1'::text, 'scope 1'::text),
            ('1.2'::text, 'scope 2'::text),
            ('1.3'::text, 'scope 3'::text)
        ) AS t(cell_quadro, scope_key)
    ),
    category_alias AS (
        SELECT *
        FROM (VALUES
            ('1.1'::text, 'combustao_movel'::text, 'Combustão móvel'::text),
            ('1.1', 'combustao_estacionaria', 'Combustão estacionária'),
            ('1.1', 'emissoes_fugitivas', 'Emissões fugitivas'),
            ('1.1', 'processos_industriais', 'Processos industriais'),
            ('1.1', 'atividades_agricolas_e_mudancas_uso_solo', 'Atividades agrícolas e mudanças no uso do solo'),
            ('1.1', 'residuos', 'Resíduos (resíduos sólidos + efluentes)'),
            ('1.1', 'residuos', 'Resíduos'),
            ('1.2', 'energia_eletrica_localizacao', 'Compra de Energia Elétrica, pelo critério de localização geográfica'),
            ('1.2', 'energia_eletrica_localizacao', 'Energia elétrica adquirida'),
            ('1.2', 'energia_termica', 'Compra de Energia Térmica'),
            ('1.2', 'perdas_transmissao_distribuicao', 'Perdas na Transmissão e Distribuição'),
            ('1.3', 'transporte_distribuicao_upstream', 'Transporte e distribuição (upstream)'),
            ('1.3', 'transporte_distribuicao_upstream', 'Transporte e distribuição upstream'),
            ('1.3', 'residuos_solidos_operacao', 'Resíduos sólidos gerados na operação'),
            ('1.3', 'residuos_solidos_operacao', 'Resíduos gerados nas operações'),
            ('1.3', 'efluentes_liquidos', 'Efluentes líquidos gerados'),
            ('1.3', 'viagens_a_negocios', 'Viagens a negócios'),
            ('1.3', 'deslocamento_casa_trabalho', 'Deslocamento (casa-trabalho)'),
            ('1.3', 'deslocamento_casa_trabalho', 'Deslocamento de funcionários'),
            ('1.3', 'transporte_distribuicao_downstream', 'Transporte e distribuição (downstream)'),
            ('1.3', 'transporte_distribuicao_downstream', 'Transporte e distribuição downstream')
        ) AS t(cell_quadro, cell_codigo, alias_name)
    ),
    eligible AS MATERIALIZED (
        SELECT
            fe.scope_name,
            fe.category_name,
            fe.gas_id,
            fe.gas_name,
            fe.gas_formula,
            fe.gas_is_biogenic,
            fe.quantity_co2e
        FROM vw_fact_emission fe
        WHERE fe.enterprise_id = p_enterprise_id
          AND fe.inventory_status = 'APPROVED'
          AND fe.period_start = v_period_start
          AND fe.period_end = v_period_end
    ),
    gas_matches AS (
        SELECT DISTINCT
            sk.cell_quadro,
            sk.cell_codigo,
            catalog_gas.gas_id
        FROM skeleton sk
        CROSS JOIN (
            SELECT DISTINCT
                el.gas_id,
                el.gas_formula,
                el.gas_name
            FROM eligible el
            WHERE el.gas_id IS NOT NULL
        ) AS catalog_gas
        WHERE sk.cell_eixo = 'GAS'
          AND (
              lower(btrim(catalog_gas.gas_formula)) = lower(sk.cell_codigo)
              OR lower(btrim(catalog_gas.gas_name)) = lower(sk.cell_codigo)
              OR (
                  sk.cell_codigo IN ('HFCs', 'HFC')
                  AND (
                      lower(btrim(catalog_gas.gas_formula)) IN ('hfcs', 'hfc')
                      OR lower(btrim(catalog_gas.gas_name)) IN ('hfcs', 'hfc')
                  )
              )
              OR (
                  sk.cell_codigo IN ('PFCs', 'PFC')
                  AND (
                      lower(btrim(catalog_gas.gas_formula)) IN ('pfcs', 'pfc')
                      OR lower(btrim(catalog_gas.gas_name)) IN ('pfcs', 'pfc')
                  )
              )
              OR (
                  sk.cell_codigo = 'trifluorometil_pentafluoreto_enxofre'
                  AND (
                      lower(btrim(catalog_gas.gas_formula)) = 'sf5cf3'
                      OR lower(btrim(catalog_gas.gas_name))
                          = 'trifluorometil pentafluoreto de enxofre'
                  )
              )
              OR (
                  sk.cell_codigo = 'perfluorociclopropano'
                  AND (
                      lower(btrim(catalog_gas.gas_formula)) = 'c-c3f6'
                      OR lower(btrim(catalog_gas.gas_name)) = 'perfluorociclopropano'
                  )
              )
          )
    ),
    gas_values AS (
        SELECT
            sk.cell_quadro,
            sk.cell_eixo,
            sk.cell_codigo,
            SUM(el.quantity_co2e) AS cell_valor
        FROM skeleton sk
        JOIN quadro_scope qs
          ON qs.cell_quadro = sk.cell_quadro
        JOIN gas_matches gm
          ON gm.cell_quadro = sk.cell_quadro
         AND gm.cell_codigo = sk.cell_codigo
        JOIN eligible el
          ON el.gas_id = gm.gas_id
         AND el.gas_is_biogenic IS FALSE
         AND lower(btrim(el.scope_name)) = qs.scope_key
        WHERE sk.cell_eixo = 'GAS'
        GROUP BY sk.cell_quadro, sk.cell_eixo, sk.cell_codigo
    ),
    category_values AS (
        SELECT
            sk.cell_quadro,
            sk.cell_eixo,
            sk.cell_codigo,
            SUM(el.quantity_co2e) AS cell_valor
        FROM skeleton sk
        JOIN quadro_scope qs
          ON qs.cell_quadro = sk.cell_quadro
        JOIN category_alias ca
          ON ca.cell_quadro = sk.cell_quadro
         AND ca.cell_codigo = sk.cell_codigo
        JOIN eligible el
          ON el.gas_is_biogenic IS FALSE
         AND lower(btrim(el.scope_name)) = qs.scope_key
         AND lower(btrim(el.category_name)) = lower(btrim(ca.alias_name))
        WHERE sk.cell_eixo = 'CATEGORIA'
          AND sk.cell_codigo <> 'outras_escopo_iii'
        GROUP BY sk.cell_quadro, sk.cell_eixo, sk.cell_codigo
    ),
    scope3_other_values AS (
        SELECT
            '1.3'::text AS cell_quadro,
            'CATEGORIA'::text AS cell_eixo,
            'outras_escopo_iii'::text AS cell_codigo,
            SUM(el.quantity_co2e) AS cell_valor
        FROM eligible el
        WHERE el.gas_is_biogenic IS FALSE
          AND lower(btrim(el.scope_name)) = 'scope 3'
          AND (
              el.category_name IS NULL
              OR NOT EXISTS (
                  SELECT 1
                  FROM category_alias ca
                  WHERE ca.cell_quadro = '1.3'
                    AND lower(btrim(el.category_name)) = lower(btrim(ca.alias_name))
              )
          )
        HAVING SUM(el.quantity_co2e) IS NOT NULL
    ),
    biogenic_category_values AS (
        SELECT
            sk.cell_quadro,
            sk.cell_eixo,
            sk.cell_codigo,
            SUM(el.quantity_co2e) AS cell_valor
        FROM skeleton sk
        JOIN category_alias ca
          ON ca.cell_quadro = '1.3'
         AND ca.cell_codigo = sk.cell_codigo
        JOIN eligible el
          ON el.gas_is_biogenic IS TRUE
         AND lower(btrim(el.scope_name)) = 'scope 3'
         AND lower(btrim(el.category_name)) = lower(btrim(ca.alias_name))
        WHERE sk.cell_quadro = '1.3'
          AND sk.cell_eixo = 'BIOGENICO_EMISSAO'
          AND sk.cell_codigo <> 'outras_escopo_iii'
        GROUP BY sk.cell_quadro, sk.cell_eixo, sk.cell_codigo
    ),
    biogenic_scope3_other_values AS (
        SELECT
            '1.3'::text AS cell_quadro,
            'BIOGENICO_EMISSAO'::text AS cell_eixo,
            'outras_escopo_iii'::text AS cell_codigo,
            SUM(el.quantity_co2e) AS cell_valor
        FROM eligible el
        WHERE el.gas_is_biogenic IS TRUE
          AND lower(btrim(el.scope_name)) = 'scope 3'
          AND (
              el.category_name IS NULL
              OR NOT EXISTS (
                  SELECT 1
                  FROM category_alias ca
                  WHERE ca.cell_quadro = '1.3'
                    AND lower(btrim(el.category_name)) = lower(btrim(ca.alias_name))
              )
          )
        HAVING SUM(el.quantity_co2e) IS NOT NULL
    ),
    biogenic_15_values AS (
        SELECT
            '1.5'::text AS cell_quadro,
            'BIOGENICO_EMISSAO'::text AS cell_eixo,
            CASE lower(btrim(el.scope_name))
                WHEN 'scope 1' THEN 'ESCOPO_I'
                WHEN 'scope 2' THEN 'ESCOPO_II'
            END AS cell_codigo,
            SUM(el.quantity_co2e) AS cell_valor
        FROM eligible el
        WHERE el.gas_is_biogenic IS TRUE
          AND lower(btrim(el.scope_name)) IN ('scope 1', 'scope 2')
        GROUP BY 3
    ),
    cell_value AS (
        SELECT * FROM gas_values
        UNION ALL
        SELECT * FROM category_values
        UNION ALL
        SELECT * FROM scope3_other_values
        UNION ALL
        SELECT * FROM biogenic_category_values
        UNION ALL
        SELECT * FROM biogenic_scope3_other_values
        UNION ALL
        SELECT * FROM biogenic_15_values
    )
    SELECT
        sk.cell_quadro,
        sk.cell_eixo,
        sk.cell_codigo,
        cv.cell_valor
    FROM skeleton sk
    LEFT JOIN cell_value cv
      ON cv.cell_quadro = sk.cell_quadro
     AND cv.cell_eixo = sk.cell_eixo
     AND cv.cell_codigo = sk.cell_codigo;
END;
$$;

COMMENT ON FUNCTION fn_ghg_complete_declaration(integer) IS
    'Returns the 84 manual cells of the complete GHG emission declaration (frames 1.1, 1.2, 1.3, 1.5) for one enterprise. Eligible facts are APPROVED inventories whose period is 1 Jan–31 Dec of the calendar year before CURRENT_DATE. valor is SUM(quantity_co2e) in tCO2e, or NULL when no fact matches. Does not return frame 1.4, spreadsheet automatic totals, reductions, or biogenic removals. Raises 22023 when enterprise_id is null and 23503 when the enterprise does not exist.';

REVOKE ALL ON FUNCTION fn_dash_visible_units(integer, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_dash_generated_savings(integer, integer, integer[], integer, text, integer, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_dash_analyses(integer, integer, integer[], integer, text, integer, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_dash_active_plants(integer, integer, integer[], integer, text, integer, numeric, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_dash_critical_anomalies(integer, integer, integer[], integer, text, integer, numeric, numeric, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_dash_average_insertion_interval(integer, integer, integer[], integer, text, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_dash_plants_table(integer, integer, integer[], integer, text, numeric, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_dash_production_alert(integer, integer, integer[], integer, text, numeric, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_dash_emissions_series(integer, integer, integer, integer[], integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_dash_emissions_by_scope(integer, integer, integer[], integer, text, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_ghg_complete_declaration(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_dash_visible_units(integer, integer, text) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_dash_generated_savings(integer, integer, integer[], integer, text, integer, numeric) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_dash_analyses(integer, integer, integer[], integer, text, integer, numeric) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_dash_active_plants(integer, integer, integer[], integer, text, integer, numeric, boolean) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_dash_critical_anomalies(integer, integer, integer[], integer, text, integer, numeric, numeric, integer) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_dash_average_insertion_interval(integer, integer, integer[], integer, text, numeric) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_dash_plants_table(integer, integer, integer[], integer, text, numeric, numeric) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_dash_production_alert(integer, integer, integer[], integer, text, numeric, integer) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_dash_emissions_series(integer, integer, integer, integer[], integer, text) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_dash_emissions_by_scope(integer, integer, integer[], integer, text, numeric) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_ghg_complete_declaration(integer) TO aether_app, aether_auditor, aether_admin;

GRANT SELECT ON vw_dim_org_hierarchy, vw_fact_emission, vw_fact_reduction, vw_analytics_org_period
    TO aether_app, aether_auditor, aether_admin;

COMMIT;
