\connect dbAether2Year

BEGIN;

CREATE TYPE AUDIT_OPERATION AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE'
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aether_app') THEN
        CREATE ROLE aether_app NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aether_auditor') THEN
        CREATE ROLE aether_auditor NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aether_admin') THEN
        CREATE ROLE aether_admin NOLOGIN;
    END IF;
END
$$;

GRANT aether_auditor TO aether_admin;

CREATE TABLE audit_row_event (
    id BIGSERIAL,
    operation AUDIT_OPERATION NOT NULL,
    table_name TEXT NOT NULL,
    record_key JSONB NOT NULL,
    row_state JSONB NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    transaction_id xid8 NOT NULL DEFAULT pg_current_xact_id(),
    db_user TEXT NOT NULL DEFAULT current_user,
    app_actor_id TEXT,
    logical_origin TEXT,
    client_addr INET DEFAULT inet_client_addr(),
    CONSTRAINT pk_audit_row_event PRIMARY KEY (id),
    CONSTRAINT ck_audit_row_event_operation CHECK (operation IN ('INSERT', 'DELETE'))
);

CREATE TABLE audit_row_update (
    id BIGSERIAL,
    operation AUDIT_OPERATION NOT NULL DEFAULT 'UPDATE',
    table_name TEXT NOT NULL,
    record_key JSONB NOT NULL,
    previous_state JSONB NOT NULL,
    new_state JSONB NOT NULL,
    changed_fields JSONB NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    transaction_id xid8 NOT NULL DEFAULT pg_current_xact_id(),
    db_user TEXT NOT NULL DEFAULT current_user,
    app_actor_id TEXT,
    logical_origin TEXT,
    client_addr INET DEFAULT inet_client_addr(),
    CONSTRAINT pk_audit_row_update PRIMARY KEY (id),
    CONSTRAINT ck_audit_row_update_operation CHECK (operation = 'UPDATE')
);

CREATE TABLE audit_purge_log (
    id BIGSERIAL,
    purged_by_db_user TEXT NOT NULL,
    purged_by_app_actor TEXT,
    reason TEXT NOT NULL,
    interval_start TIMESTAMPTZ NOT NULL,
    interval_end TIMESTAMPTZ NOT NULL,
    events_removed INTEGER NOT NULL CHECK (events_removed >= 0),
    updates_removed INTEGER NOT NULL CHECK (updates_removed >= 0),
    purged_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT pk_audit_purge_log PRIMARY KEY (id),
    CONSTRAINT ck_audit_purge_log_interval CHECK (interval_end >= interval_start)
);

COMMENT ON TABLE audit_row_event IS
    'INSERT and DELETE log. Stores the created state or the last known state, with sensitive fields masked. AUD-FR-001, AUD-FR-005.';
COMMENT ON TABLE audit_row_update IS
    'UPDATE log with previous state, new state, and field diffs. Updates that change no values do not create an event. AUD-FR-001, AUD-FR-004.';
COMMENT ON TABLE audit_purge_log IS
    'Evidence of authorized log removal: actor, reason, and interval, kept outside the purged tables. AUD-FR-012.';
COMMENT ON COLUMN audit_row_event.app_actor_id IS
    'Application actor identifier when provided via aether.app_actor_id. NULL means the identity was not provided.';
COMMENT ON COLUMN audit_row_update.app_actor_id IS
    'Application actor identifier when provided via aether.app_actor_id. NULL means the identity was not provided.';
COMMENT ON COLUMN audit_row_event.occurred_at IS
    'Event timestamp as timestamptz (stored in UTC), captured with clock_timestamp().';
COMMENT ON COLUMN audit_row_update.changed_fields IS
    'Map of field -> {from, to}. SENSIVEL/SECRETO fields record that a change occurred with [REDACTED] values.';

-- Builds the primary key of a row as jsonb, including composite keys.
CREATE OR REPLACE FUNCTION fn_audit_record_key(p_relid oid, p_row jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(
        jsonb_object_agg(a.attname, p_row -> a.attname),
        '{}'::jsonb
    )
    FROM pg_index i
    JOIN pg_attribute a
      ON a.attrelid = i.indrelid
     AND a.attnum = ANY (i.indkey)
    WHERE i.indrelid = p_relid
      AND i.indisprimary
      AND a.attnum > 0
      AND NOT a.attisdropped;
$$;

COMMENT ON FUNCTION fn_audit_record_key(oid, jsonb) IS
    'Extracts the primary key, including composite keys, from a jsonb row. AUD-FR-003.';

-- Lists columns that must be masked in audit logs.
CREATE OR REPLACE FUNCTION fn_audit_sensitive_columns(p_table_name text)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_columns text[];
BEGIN
    IF to_regclass('public.technical_metadata') IS NOT NULL THEN
        SELECT COALESCE(array_agg(column_name), ARRAY[]::text[])
          INTO v_columns
          FROM technical_metadata
         WHERE object_kind = 'COLUMN'
           AND table_name = p_table_name
           AND definition_status = 'VIGENTE'
           AND sensitivity IN ('SENSIVEL', 'SECRETO');
    ELSE
        v_columns := ARRAY[]::text[];
    END IF;

    -- AUD-NFR-002: credentials are never persisted in full, even without the catalog.
    IF NOT ('password_hash' = ANY (v_columns)) THEN
        v_columns := array_append(v_columns, 'password_hash');
    END IF;

    RETURN v_columns;
END;
$$;

-- Replaces sensitive and secret values with [REDACTED].
CREATE OR REPLACE FUNCTION fn_audit_mask_row(p_table_name text, p_row jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_col text;
    v_masked jsonb := p_row;
BEGIN
    FOREACH v_col IN ARRAY fn_audit_sensitive_columns(p_table_name)
    LOOP
        IF v_masked ? v_col AND v_masked -> v_col IS NOT NULL THEN
            v_masked := jsonb_set(v_masked, ARRAY[v_col], '"[REDACTED]"'::jsonb, false);
        END IF;
    END LOOP;
    RETURN v_masked;
END;
$$;

COMMENT ON FUNCTION fn_audit_mask_row(text, jsonb) IS
    'Replaces SENSIVEL/SECRETO column values and password_hash with [REDACTED]. AUD-FR-008.';

-- Returns the field differences between two jsonb row states.
CREATE OR REPLACE FUNCTION fn_audit_jsonb_diff(p_old jsonb, p_new jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(
        jsonb_object_agg(
            k,
            jsonb_build_object('from', p_old -> k, 'to', p_new -> k)
        ),
        '{}'::jsonb
    )
    FROM (
        SELECT DISTINCT key AS k
        FROM (
            SELECT jsonb_object_keys(COALESCE(p_old, '{}'::jsonb)) AS key
            UNION
            SELECT jsonb_object_keys(COALESCE(p_new, '{}'::jsonb))
        ) keys
    ) s
    WHERE (p_old -> k) IS DISTINCT FROM (p_new -> k);
$$;

-- Reads the application actor from the current session, if set.
CREATE OR REPLACE FUNCTION fn_audit_session_actor()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT NULLIF(current_setting('aether.app_actor_id', true), '');
$$;

-- Reads the logical origin from the current session, if set.
CREATE OR REPLACE FUNCTION fn_audit_session_origin()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT NULLIF(current_setting('aether.logical_origin', true), '');
$$;

-- Logs INSERT and DELETE events in the same transaction.
CREATE OR REPLACE FUNCTION fn_audit_insert_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_row jsonb;
    v_key jsonb;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_row := to_jsonb(NEW);
        v_key := fn_audit_record_key(TG_RELID, v_row);
        INSERT INTO audit_row_event (
            operation, table_name, record_key, row_state,
            app_actor_id, logical_origin
        ) VALUES (
            'INSERT',
            TG_TABLE_NAME,
            v_key,
            fn_audit_mask_row(TG_TABLE_NAME, v_row),
            fn_audit_session_actor(),
            fn_audit_session_origin()
        );
        RETURN NEW;
    END IF;

    v_row := to_jsonb(OLD);
    v_key := fn_audit_record_key(TG_RELID, v_row);
    INSERT INTO audit_row_event (
        operation, table_name, record_key, row_state,
        app_actor_id, logical_origin
    ) VALUES (
        'DELETE',
        TG_TABLE_NAME,
        v_key,
        fn_audit_mask_row(TG_TABLE_NAME, v_row),
        fn_audit_session_actor(),
        fn_audit_session_origin()
    );
    RETURN OLD;
END;
$$;

COMMENT ON FUNCTION fn_audit_insert_delete() IS
    'AFTER INSERT/DELETE trigger. Runs in the same transaction as the change. AUD-FR-002, AUD-FR-006.';

-- Logs UPDATE events with previous state, new state, and diffs.
CREATE OR REPLACE FUNCTION fn_audit_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_old jsonb := to_jsonb(OLD);
    v_new jsonb := to_jsonb(NEW);
    v_diff jsonb;
    v_col text;
BEGIN
    IF v_old = v_new THEN
        RETURN NEW;
    END IF;

    v_diff := fn_audit_jsonb_diff(v_old, v_new);

    FOREACH v_col IN ARRAY fn_audit_sensitive_columns(TG_TABLE_NAME)
    LOOP
        IF v_diff ? v_col THEN
            v_diff := jsonb_set(
                v_diff,
                ARRAY[v_col],
                jsonb_build_object('from', '[REDACTED]', 'to', '[REDACTED]'),
                false
            );
        END IF;
    END LOOP;

    INSERT INTO audit_row_update (
        table_name, record_key, previous_state, new_state, changed_fields,
        app_actor_id, logical_origin
    ) VALUES (
        TG_TABLE_NAME,
        fn_audit_record_key(TG_RELID, v_new),
        fn_audit_mask_row(TG_TABLE_NAME, v_old),
        fn_audit_mask_row(TG_TABLE_NAME, v_new),
        v_diff,
        fn_audit_session_actor(),
        fn_audit_session_origin()
    );

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_audit_update() IS
    'AFTER UPDATE trigger. Skips updates that change no values. AUD-FR-004.';

-- Attaches audit triggers to application tables, excluding logs and catalog.
CREATE OR REPLACE PROCEDURE sp_attach_audit_triggers()
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
    denylist text[] := ARRAY[
        'audit_row_event',
        'audit_row_update',
        'audit_purge_log',
        'technical_metadata'
    ];
BEGIN
    FOR r IN
        SELECT c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind = 'r'
          AND NOT (c.relname = ANY (denylist))
        ORDER BY c.relname
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_insert_delete ON %I', r.relname);
        EXECUTE format(
            'CREATE TRIGGER trg_audit_insert_delete AFTER INSERT OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION fn_audit_insert_delete()',
            r.relname
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_update ON %I', r.relname);
        EXECUTE format(
            'CREATE TRIGGER trg_audit_update AFTER UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION fn_audit_update()',
            r.relname
        );
    END LOOP;
END;
$$;

COMMENT ON PROCEDURE sp_attach_audit_triggers() IS
    'Installs audit triggers on application tables, excluding log tables and the technical catalog. AUD-FR-009, AUD-FR-010.';

-- Purges audit logs in an interval and records who removed them.
CREATE OR REPLACE PROCEDURE sp_purge_audit_events(
    OUT p_events_removed integer,
    OUT p_updates_removed integer,
    IN p_interval_start timestamptz,
    IN p_interval_end timestamptz,
    IN p_reason text,
    IN p_app_actor text DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_interval_start IS NULL OR p_interval_end IS NULL THEN
        RAISE EXCEPTION 'Purge interval is required'
            USING ERRCODE = '22023';
    END IF;
    IF p_interval_end < p_interval_start THEN
        RAISE EXCEPTION 'interval_end must be greater than or equal to interval_start'
            USING ERRCODE = '22023';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'Reason for authorized removal is required'
            USING ERRCODE = '22023';
    END IF;

    DELETE FROM audit_row_event
     WHERE occurred_at >= p_interval_start
       AND occurred_at <= p_interval_end;
    GET DIAGNOSTICS p_events_removed = ROW_COUNT;

    DELETE FROM audit_row_update
     WHERE occurred_at >= p_interval_start
       AND occurred_at <= p_interval_end;
    GET DIAGNOSTICS p_updates_removed = ROW_COUNT;

    INSERT INTO audit_purge_log (
        purged_by_db_user,
        purged_by_app_actor,
        reason,
        interval_start,
        interval_end,
        events_removed,
        updates_removed
    ) VALUES (
        current_user,
        COALESCE(p_app_actor, fn_audit_session_actor()),
        btrim(p_reason),
        p_interval_start,
        p_interval_end,
        p_events_removed,
        p_updates_removed
    );
END;
$$;

COMMENT ON PROCEDURE sp_purge_audit_events(integer, integer, timestamptz, timestamptz, text, text) IS
    'Removes logs in the given interval and writes evidence to audit_purge_log. Input: start, end, reason, actor. Output: removed counts. Errors if the reason or interval is invalid. AUD-FR-012.';

CALL sp_attach_audit_triggers();

REVOKE ALL ON TABLE audit_row_event, audit_row_update, audit_purge_log FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_audit_insert_delete() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_audit_update() FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_purge_audit_events(integer, integer, timestamptz, timestamptz, text, text) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_attach_audit_triggers() FROM PUBLIC;

GRANT SELECT ON TABLE audit_row_event, audit_row_update, audit_purge_log TO aether_auditor;
GRANT SELECT, DELETE ON TABLE audit_row_event, audit_row_update TO aether_admin;
GRANT SELECT, INSERT ON TABLE audit_purge_log TO aether_admin;
GRANT EXECUTE ON PROCEDURE sp_purge_audit_events(integer, integer, timestamptz, timestamptz, text, text) TO aether_admin;
GRANT EXECUTE ON PROCEDURE sp_attach_audit_triggers() TO aether_admin;

COMMIT;
