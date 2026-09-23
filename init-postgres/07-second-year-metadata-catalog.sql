\connect dbAether2Year

BEGIN;

CREATE TYPE METADATA_OBJECT_KIND AS ENUM (
    'TABLE',
    'COLUMN'
);

CREATE TYPE DATA_SENSITIVITY AS ENUM (
    'PUBLICO',
    'INTERNO',
    'RESTRITO',
    'SENSIVEL',
    'SECRETO'
);

CREATE TYPE METADATA_DEFINITION_STATUS AS ENUM (
    'VIGENTE',
    'OBSOLETO'
);

CREATE TABLE technical_metadata (
    id SERIAL,
    object_kind METADATA_OBJECT_KIND NOT NULL,
    table_name TEXT NOT NULL,
    column_name TEXT,
    domain TEXT NOT NULL,
    purpose TEXT NOT NULL,
    logical_type TEXT,
    is_required BOOLEAN,
    business_rule TEXT NOT NULL,
    sensitivity DATA_SENSITIVITY NOT NULL,
    functional_permission TEXT NOT NULL,
    id_permission INTEGER,
    logical_owner TEXT NOT NULL,
    definition_status METADATA_DEFINITION_STATUS NOT NULL DEFAULT 'VIGENTE',
    last_reviewed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    reviewed_by TEXT NOT NULL,
    requirement_id TEXT,
    CONSTRAINT pk_technical_metadata PRIMARY KEY (id),
    CONSTRAINT fk_technical_metadata_permission
        FOREIGN KEY (id_permission) REFERENCES permission (id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_technical_metadata_shape CHECK (
        (object_kind = 'TABLE' AND column_name IS NULL)
        OR (object_kind = 'COLUMN' AND column_name IS NOT NULL)
    )
);

CREATE UNIQUE INDEX uq_technical_metadata_table
    ON technical_metadata (table_name)
    WHERE object_kind = 'TABLE';

CREATE UNIQUE INDEX uq_technical_metadata_column
    ON technical_metadata (table_name, column_name)
    WHERE object_kind = 'COLUMN';

COMMENT ON TABLE technical_metadata IS
    'Persistent technical catalog of dbAether2Year tables and columns, including sensitivity classification and functional permission. Does not store actual values of the described columns. META-FR-001, META-NFR-002.';
COMMENT ON COLUMN technical_metadata.object_kind IS 'Whether the definition describes a table/view or a column.';
COMMENT ON COLUMN technical_metadata.table_name IS 'Name of the documented relation in public.';
COMMENT ON COLUMN technical_metadata.column_name IS 'Column name. Null only on table-level definitions.';
COMMENT ON COLUMN technical_metadata.domain IS 'Functional domain: institutional, environmental, authorization, audit, catalog, or analytical.';
COMMENT ON COLUMN technical_metadata.purpose IS 'Purpose of the object.';
COMMENT ON COLUMN technical_metadata.logical_type IS 'Logical column type, aligned with the native catalog.';
COMMENT ON COLUMN technical_metadata.is_required IS 'Column requiredness (NOT NULL in the schema). Null on table-level definitions.';
COMMENT ON COLUMN technical_metadata.business_rule IS 'Business rule, or an explicit record that there is no additional rule.';
COMMENT ON COLUMN technical_metadata.sensitivity IS 'Controlled classification: PUBLICO, INTERNO, RESTRITO, SENSIVEL, or SECRETO.';
COMMENT ON COLUMN technical_metadata.functional_permission IS 'Application functional permission or TECHNICAL_ADMINISTRATIVE_ACCESS.';
COMMENT ON COLUMN technical_metadata.id_permission IS 'Optional FK to an existing permission. Null when access is technical/administrative.';
COMMENT ON COLUMN technical_metadata.logical_owner IS 'Logical owner of the object.';
COMMENT ON COLUMN technical_metadata.definition_status IS 'VIGENTE or OBSOLETO. Objects removed from the schema are marked obsolete.';
COMMENT ON COLUMN technical_metadata.last_reviewed_at IS 'Timestamp of the last definition review.';
COMMENT ON COLUMN technical_metadata.reviewed_by IS 'Person or process responsible for the last review.';
COMMENT ON COLUMN technical_metadata.requirement_id IS 'Stable identifier of the associated requirement, when present.';

-- Compares the technical catalog with the native schema and lists gaps.
CREATE OR REPLACE FUNCTION fn_metadata_completeness()
RETURNS TABLE (
    issue_type text,
    table_name text,
    column_name text,
    detail text
)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    WITH native_tables AS (
        SELECT t.table_name
        FROM information_schema.tables t
        WHERE t.table_schema = 'public'
          AND t.table_type IN ('BASE TABLE', 'VIEW')
    ),
    native_columns AS (
        SELECT c.table_name, c.column_name
        FROM information_schema.columns c
        JOIN native_tables nt ON nt.table_name = c.table_name
        WHERE c.table_schema = 'public'
    )
    SELECT 'MISSING_TABLE', nt.table_name, NULL::text,
           'Table/view without a current catalog definition'
    FROM native_tables nt
    WHERE NOT EXISTS (
        SELECT 1
        FROM technical_metadata m
        WHERE m.object_kind = 'TABLE'
          AND m.table_name = nt.table_name
          AND m.definition_status = 'VIGENTE'
    )
    UNION ALL
    SELECT 'MISSING_COLUMN', nc.table_name, nc.column_name,
           'Column without a current catalog definition'
    FROM native_columns nc
    WHERE NOT EXISTS (
        SELECT 1
        FROM technical_metadata m
        WHERE m.object_kind = 'COLUMN'
          AND m.table_name = nc.table_name
          AND m.column_name = nc.column_name
          AND m.definition_status = 'VIGENTE'
    )
    UNION ALL
    SELECT 'OBSOLETE_TABLE', m.table_name, NULL::text,
           'Current definition without a matching schema object'
    FROM technical_metadata m
    WHERE m.object_kind = 'TABLE'
      AND m.definition_status = 'VIGENTE'
      AND NOT EXISTS (
          SELECT 1 FROM native_tables nt WHERE nt.table_name = m.table_name
      )
    UNION ALL
    SELECT 'OBSOLETE_COLUMN', m.table_name, m.column_name,
           'Current definition without a matching schema column'
    FROM technical_metadata m
    WHERE m.object_kind = 'COLUMN'
      AND m.definition_status = 'VIGENTE'
      AND NOT EXISTS (
          SELECT 1
          FROM native_columns nc
          WHERE nc.table_name = m.table_name
            AND nc.column_name = m.column_name
      )
    UNION ALL
    SELECT 'DUPLICATE', m.table_name, m.column_name,
           'More than one current definition for the same object'
    FROM technical_metadata m
    WHERE m.definition_status = 'VIGENTE'
    GROUP BY m.object_kind, m.table_name, m.column_name
    HAVING COUNT(*) > 1
    ORDER BY 1, 2, 3;
$$;

COMMENT ON FUNCTION fn_metadata_completeness() IS
    'Compares the technical catalog with information_schema and lists missing, duplicate, and obsolete objects. META-FR-009, META-FR-010.';

-- Inserts missing catalog rows and marks obsolete objects.
CREATE OR REPLACE PROCEDURE sp_sync_technical_metadata(
    IN p_reviewed_by text DEFAULT 'system-sync'
)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO technical_metadata (
        object_kind, table_name, domain, purpose, business_rule,
        sensitivity, functional_permission, logical_owner,
        definition_status, reviewed_by
    )
    SELECT
        'TABLE',
        t.table_name,
        'application',
        'Relation ' || t.table_name || ' synchronized from the native catalog.',
        'No additional rule.',
        'INTERNO',
        'TECHNICAL_ADMINISTRATIVE_ACCESS',
        'platform',
        'VIGENTE',
        p_reviewed_by
    FROM information_schema.tables t
    WHERE t.table_schema = 'public'
      AND t.table_type IN ('BASE TABLE', 'VIEW')
      AND NOT EXISTS (
          SELECT 1
          FROM technical_metadata m
          WHERE m.object_kind = 'TABLE'
            AND m.table_name = t.table_name
      );

    INSERT INTO technical_metadata (
        object_kind, table_name, column_name, domain, purpose,
        logical_type, is_required, business_rule, sensitivity,
        functional_permission, logical_owner, definition_status, reviewed_by
    )
    SELECT
        'COLUMN',
        c.table_name,
        c.column_name,
        'application',
        COALESCE(
            col_description(
                format('%I.%I', c.table_schema, c.table_name)::regclass,
                c.ordinal_position
            ),
            'Column ' || c.column_name || ' of relation ' || c.table_name || '.'
        ),
        c.data_type,
        (c.is_nullable = 'NO'),
        'No additional rule.',
        'INTERNO',
        'TECHNICAL_ADMINISTRATIVE_ACCESS',
        'platform',
        'VIGENTE',
        p_reviewed_by
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema
     AND t.table_name = c.table_name
    WHERE c.table_schema = 'public'
      AND t.table_type IN ('BASE TABLE', 'VIEW')
      AND NOT EXISTS (
          SELECT 1
          FROM technical_metadata m
          WHERE m.object_kind = 'COLUMN'
            AND m.table_name = c.table_name
            AND m.column_name = c.column_name
      );

    UPDATE technical_metadata m
    SET definition_status = 'OBSOLETO',
        last_reviewed_at = clock_timestamp(),
        reviewed_by = p_reviewed_by
    WHERE m.definition_status = 'VIGENTE'
      AND (
          (m.object_kind = 'TABLE' AND NOT EXISTS (
              SELECT 1
              FROM information_schema.tables t
              WHERE t.table_schema = 'public'
                AND t.table_type IN ('BASE TABLE', 'VIEW')
                AND t.table_name = m.table_name
          ))
          OR
          (m.object_kind = 'COLUMN' AND NOT EXISTS (
              SELECT 1
              FROM information_schema.columns c
              JOIN information_schema.tables t
                ON t.table_schema = c.table_schema
               AND t.table_name = c.table_name
              WHERE c.table_schema = 'public'
                AND t.table_type IN ('BASE TABLE', 'VIEW')
                AND c.table_name = m.table_name
                AND c.column_name = m.column_name
          ))
      );

    UPDATE technical_metadata m
    SET definition_status = 'VIGENTE',
        last_reviewed_at = clock_timestamp(),
        reviewed_by = p_reviewed_by
    WHERE m.definition_status = 'OBSOLETO'
      AND (
          (m.object_kind = 'TABLE' AND EXISTS (
              SELECT 1
              FROM information_schema.tables t
              WHERE t.table_schema = 'public'
                AND t.table_type IN ('BASE TABLE', 'VIEW')
                AND t.table_name = m.table_name
          ))
          OR
          (m.object_kind = 'COLUMN' AND EXISTS (
              SELECT 1
              FROM information_schema.columns c
              WHERE c.table_schema = 'public'
                AND c.table_name = m.table_name
                AND c.column_name = m.column_name
          ))
      );
END;
$$;

COMMENT ON PROCEDURE sp_sync_technical_metadata(text) IS
    'Synchronizes missing or obsolete definitions with the native schema, without storing business values. META-FR-007, META-FR-009.';

-- Applies domain, purpose, sensitivity, and ownership to catalog rows.
CREATE OR REPLACE PROCEDURE sp_apply_technical_metadata_governance()
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE technical_metadata AS m
    SET domain = v.domain,
        purpose = v.purpose,
        business_rule = v.business_rule,
        sensitivity = v.sensitivity,
        functional_permission = 'TECHNICAL_ADMINISTRATIVE_ACCESS',
        logical_owner = v.logical_owner,
        last_reviewed_at = clock_timestamp(),
        reviewed_by = 'spec-db2y-05',
        requirement_id = v.requirement_id
    FROM (
        VALUES
            ('plan', 'institutional', 'Commercial plans offered to enterprises.', 'Non-negative price and duration in days greater than zero.', 'INTERNO'::DATA_SENSITIVITY, 'product', 'META-FR-002'),
            ('address', 'institutional', 'Postal address of enterprises and units.', 'No additional rule beyond required location fields.', 'RESTRITO', 'registry', 'META-FR-002'),
            ('enterprise', 'institutional', 'Legal entity that is a platform customer.', 'CNPJ is unique per enterprise.', 'INTERNO', 'registry', 'META-FR-002'),
            ('plan_subscription', 'institutional', 'Plan subscription for an enterprise.', 'May be deactivated without a mandatory physical delete.', 'INTERNO', 'finance', 'META-FR-002'),
            ('payment', 'institutional', 'Payments associated with subscriptions.', 'Positive amount and status controlled by enumeration.', 'RESTRITO', 'finance', 'META-FR-002'),
            ('unit', 'institutional', 'Operational unit linked to an enterprise.', 'CNPJ is unique per unit.', 'INTERNO', 'registry', 'META-FR-002'),
            ('department', 'institutional', 'Department linked to a unit.', 'Unit deletion is restricted while departments exist.', 'INTERNO', 'registry', 'META-FR-002'),
            ('permission_group', 'authorization', 'Permission grouping scoped to one enterprise.', 'id_enterprise is required. Each group belongs to exactly one enterprise.', 'INTERNO', 'authorization', 'AUTH-FR-005'),
            ('permission', 'authorization', 'Application functional permission.', 'Identified by name and URL.', 'INTERNO', 'authorization', 'META-FR-006'),
            ('permission_group_permission', 'authorization', 'N:N association between group and permission.', 'The group-permission pair is unique.', 'INTERNO', 'authorization', 'META-FR-002'),
            ('parana_seal_forecast', 'institutional', 'Paraná seal forecast for the unit.', 'Score and level are non-negative.', 'INTERNO', 'sustainability', 'META-FR-002'),
            ('administrator', 'institutional', 'Platform administrator.', 'Contains a credential and personal data; access is restricted.', 'RESTRITO', 'platform', 'META-FR-005'),
            ('storage_file', 'institutional', 'Metadata of a stored file.', 'Does not store the binary content.', 'INTERNO', 'platform', 'META-FR-002'),
            ('employee', 'institutional', 'Employee of a customer enterprise.', 'Belongs to one department and exactly one permission group of the same enterprise. Contains personal data and a credential; access is restricted.', 'RESTRITO', 'registry', 'AUTH-FR-002'),
            ('scope', 'environmental', 'GHG Protocol scope of the emission.', 'Name is unique.', 'PUBLICO', 'inventory', 'META-FR-002'),
            ('category', 'environmental', 'Environmental category, including Scope 3.', 'classification applies mainly to Scope 3.', 'PUBLICO', 'inventory', 'META-FR-002'),
            ('gas', 'environmental', 'Greenhouse gas and its GWP.', 'GWP must be greater than zero.', 'PUBLICO', 'inventory', 'META-FR-002'),
            ('inventory', 'environmental', 'Emissions inventory for a department and period.', 'End period is not before start. Status and type are required.', 'INTERNO', 'inventory', 'META-FR-002'),
            ('emission', 'environmental', 'Emission fact in tCO2e linked to inventory, gas, and scope.', 'quantity_co2e is non-negative. Category may be null.', 'INTERNO', 'inventory', 'META-FR-002'),
            ('reduction', 'environmental', 'Reduction fact in tCO2e linked to inventory and category.', 'Category may be null in the operational model.', 'INTERNO', 'inventory', 'META-FR-002'),
            ('audit_row_event', 'audit', 'INSERT and DELETE log of auditable tables.', 'Does not audit itself. Sensitive fields are masked.', 'RESTRITO', 'governance', 'AUD-FR-001'),
            ('audit_row_update', 'audit', 'UPDATE log with states and diffs.', 'An update with no value change does not create an event.', 'RESTRITO', 'governance', 'AUD-FR-001'),
            ('audit_purge_log', 'audit', 'Evidence of authorized log purge.', 'Preserved outside the purged tables.', 'RESTRITO', 'governance', 'AUD-FR-012'),
            ('technical_metadata', 'catalog', 'Technical catalog of tables and columns.', 'Does not store data samples. Only authorized identities change definitions.', 'INTERNO', 'governance', 'META-FR-001'),
            ('vw_dim_org_hierarchy', 'analytical', 'View of the enterprise → unit → department hierarchy.', 'Recursive CTE. Does not attach orphan nodes.', 'INTERNO', 'analysis', 'AN-FR-007'),
            ('vw_fact_emission', 'analytical', 'Star emission fact at one-emission grain.', 'Does not expose personal data. Period comes from the inventory.', 'INTERNO', 'analysis', 'AN-FR-001'),
            ('vw_fact_reduction', 'analytical', 'Star reduction fact at one-reduction grain.', 'Does not publish gas or scope.', 'INTERNO', 'analysis', 'AN-FR-002'),
            ('vw_analytics_org_period', 'analytical', 'Totals, evolution, and ranking by organization and period.', 'Window functions and CTEs. Division by zero in percentage variation returns null.', 'INTERNO', 'analysis', 'AN-FR-006')
    ) AS v(table_name, domain, purpose, business_rule, sensitivity, logical_owner, requirement_id)
    WHERE m.object_kind = 'TABLE'
      AND m.table_name = v.table_name;

    UPDATE technical_metadata AS m
    SET domain = t.domain,
        sensitivity = t.sensitivity,
        functional_permission = t.functional_permission,
        logical_owner = t.logical_owner
    FROM technical_metadata AS t
    WHERE m.object_kind = 'COLUMN'
      AND t.object_kind = 'TABLE'
      AND t.table_name = m.table_name
      AND t.definition_status = 'VIGENTE';

    UPDATE technical_metadata AS m
    SET sensitivity = v.sensitivity,
        purpose = v.purpose,
        business_rule = v.business_rule,
        last_reviewed_at = clock_timestamp(),
        reviewed_by = 'spec-db2y-05',
        requirement_id = v.requirement_id
    FROM (
        VALUES
            ('employee', 'cpf', 'SENSIVEL'::DATA_SENSITIVITY, 'Employee CPF.', 'Identifying personal data. Must be unique.', 'META-FR-005'),
            ('employee', 'email', 'SENSIVEL', 'Employee email.', 'Personal contact data. Must be unique.', 'META-FR-005'),
            ('employee', 'phone', 'SENSIVEL', 'Employee phone.', 'Personal contact data.', 'META-FR-005'),
            ('employee', 'name', 'RESTRITO', 'Employee name.', 'Internal identification of the employee.', 'META-FR-003'),
            ('employee', 'password_hash', 'SECRETO', 'Employee password hash.', 'Credential. Never persist the value in clear text or in full in logs.', 'META-FR-005'),
            ('employee', 'id_department', 'RESTRITO', 'Employee department.', 'Required. Defines the organizational path used to resolve the employee enterprise.', 'AUTH-FR-004'),
            ('employee', 'id_permission_group', 'RESTRITO', 'Employee permission group.', 'Required. N:1 link to a permission group of the same enterprise as the department.', 'AUTH-FR-003'),
            ('permission_group', 'id_enterprise', 'INTERNO', 'Enterprise owner of the permission group.', 'Required. Used to filter groups by enterprise.', 'AUTH-FR-005'),
            ('administrator', 'email', 'SENSIVEL', 'Administrator email.', 'Personal contact data. Must be unique.', 'META-FR-005'),
            ('administrator', 'password_hash', 'SECRETO', 'Administrator password hash.', 'Credential. Never persist the value in clear text or in full in logs.', 'META-FR-005'),
            ('gas', 'gwp', 'PUBLICO', 'Gas GWP factor.', 'Must be greater than zero. Used to derive the original quantity (CO2e / GWP).', 'ROT-FR-002'),
            ('emission', 'quantity_co2e', 'INTERNO', 'Emitted quantity already converted to tCO2e.', 'Must be non-negative.', 'AN-FR-004'),
            ('emission', 'id_category', 'INTERNO', 'Emission category, when provided.', 'Null is allowed and must remain identifiable as uninformed.', 'AN-FR-009'),
            ('reduction', 'quantity_co2e', 'INTERNO', 'Reduced quantity in tCO2e.', 'May produce a negative net balance when greater than emissions.', 'ROT-FR-003'),
            ('inventory', 'inventorying_period_start', 'INTERNO', 'Start of the inventoried period.', 'Source of the analytical period; do not use emission created_at.', 'AN-FR-008'),
            ('inventory', 'inventorying_period_end', 'INTERNO', 'End of the inventoried period.', 'Must be greater than or equal to the start. Multi-year intervals are not allocated.', 'AN-FR-008'),
            ('audit_row_event', 'row_state', 'RESTRITO', 'Inserted state or last known state, already masked.', 'Do not persist SENSIVEL/SECRETO values in full.', 'AUD-FR-008'),
            ('audit_row_update', 'previous_state', 'RESTRITO', 'Previous state, already masked.', 'Do not persist SENSIVEL/SECRETO values in full.', 'AUD-FR-008'),
            ('audit_row_update', 'new_state', 'RESTRITO', 'New state, already masked.', 'Do not persist SENSIVEL/SECRETO values in full.', 'AUD-FR-008')
    ) AS v(table_name, column_name, sensitivity, purpose, business_rule, requirement_id)
    WHERE m.object_kind = 'COLUMN'
      AND m.table_name = v.table_name
      AND m.column_name = v.column_name;
END;
$$;

COMMENT ON PROCEDURE sp_apply_technical_metadata_governance() IS
    'Applies domain, purpose, classification, and governance rules from the specs onto the synchronized catalog. META-FR-002 to META-FR-006.';

CALL sp_sync_technical_metadata('init-postgres');
CALL sp_apply_technical_metadata_governance();

REVOKE ALL ON TABLE technical_metadata FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_metadata_completeness() FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_sync_technical_metadata(text) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_apply_technical_metadata_governance() FROM PUBLIC;

GRANT SELECT ON TABLE technical_metadata TO aether_auditor, aether_admin;
GRANT INSERT, UPDATE, DELETE ON TABLE technical_metadata TO aether_admin;
GRANT USAGE, SELECT ON SEQUENCE technical_metadata_id_seq TO aether_admin;
GRANT EXECUTE ON FUNCTION fn_metadata_completeness() TO aether_auditor, aether_admin;
GRANT EXECUTE ON PROCEDURE sp_sync_technical_metadata(text) TO aether_admin;
GRANT EXECUTE ON PROCEDURE sp_apply_technical_metadata_governance() TO aether_admin;

COMMIT;
