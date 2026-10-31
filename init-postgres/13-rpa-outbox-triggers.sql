-- RPA outbox: business tables enqueue changes and notify the aether-rpa worker.
-- Installed here by the database owner, since the rpa_aether role does not own
-- the business tables and cannot drop their triggers.
-- Keep the table lists in sync with TABLE_ORDER / table_name_b in aether-rpa/src/definition.py.

\connect dbAether1Year

CREATE TABLE IF NOT EXISTS rpa_outbox (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(150) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    row_pk JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP
);

CREATE OR REPLACE FUNCTION aether_rpa_enqueue_write() RETURNS trigger AS $$
BEGIN
    IF current_setting('application_name', true) = 'aether-rpa' THEN
        RETURN NULL;
    END IF;
    INSERT INTO rpa_outbox (table_name, operation)
    VALUES (TG_TABLE_NAME, lower(TG_OP));
    PERFORM pg_notify('aether_rpa', TG_TABLE_NAME);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION aether_rpa_enqueue_delete() RETURNS trigger AS $$
BEGIN
    IF current_setting('application_name', true) = 'aether-rpa' THEN
        RETURN OLD;
    END IF;
    INSERT INTO rpa_outbox (table_name, operation, row_pk)
    VALUES (TG_TABLE_NAME, 'delete', to_jsonb(OLD));
    PERFORM pg_notify('aether_rpa', TG_TABLE_NAME);
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'addresses',
        'storage_files',
        'permissions',
        'plans',
        'companies',
        'permission_groups',
        'units',
        'sectors',
        'permission_group_permissions',
        'employees',
        'subscriptions'
    ]
    LOOP
        EXECUTE format(
            'CREATE OR REPLACE TRIGGER %I AFTER INSERT OR UPDATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION aether_rpa_enqueue_write()',
            'aether_rpa_write_' || t, t
        );
        EXECUTE format(
            'CREATE OR REPLACE TRIGGER %I AFTER DELETE ON %I FOR EACH ROW EXECUTE FUNCTION aether_rpa_enqueue_delete()',
            'aether_rpa_delete_' || t, t
        );
    END LOOP;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rpa_aether') THEN
        GRANT SELECT, UPDATE ON rpa_outbox TO rpa_aether;
    END IF;
END;
$$;

\connect dbAether2Year

CREATE TABLE IF NOT EXISTS rpa_outbox (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(150) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    row_pk JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP
);

CREATE OR REPLACE FUNCTION aether_rpa_enqueue_write() RETURNS trigger AS $$
BEGIN
    IF current_setting('application_name', true) = 'aether-rpa' THEN
        RETURN NULL;
    END IF;
    INSERT INTO rpa_outbox (table_name, operation)
    VALUES (TG_TABLE_NAME, lower(TG_OP));
    PERFORM pg_notify('aether_rpa', TG_TABLE_NAME);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION aether_rpa_enqueue_delete() RETURNS trigger AS $$
BEGIN
    IF current_setting('application_name', true) = 'aether-rpa' THEN
        RETURN OLD;
    END IF;
    INSERT INTO rpa_outbox (table_name, operation, row_pk)
    VALUES (TG_TABLE_NAME, 'delete', to_jsonb(OLD));
    PERFORM pg_notify('aether_rpa', TG_TABLE_NAME);
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'address',
        'storage_file',
        'permission',
        'plan',
        'enterprise',
        'permission_group',
        'unit',
        'department',
        'permission_group_permission',
        'employee',
        'plan_subscription'
    ]
    LOOP
        EXECUTE format(
            'CREATE OR REPLACE TRIGGER %I AFTER INSERT OR UPDATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION aether_rpa_enqueue_write()',
            'aether_rpa_write_' || t, t
        );
        EXECUTE format(
            'CREATE OR REPLACE TRIGGER %I AFTER DELETE ON %I FOR EACH ROW EXECUTE FUNCTION aether_rpa_enqueue_delete()',
            'aether_rpa_delete_' || t, t
        );
    END LOOP;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rpa_aether') THEN
        GRANT SELECT, UPDATE ON rpa_outbox TO rpa_aether;
    END IF;
END;
$$;
