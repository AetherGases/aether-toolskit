\connect dbAether2Year

BEGIN;

-- Derives original gas quantity as CO2e / GWP, rejecting invalid GWP.
CREATE OR REPLACE FUNCTION fn_original_gas_quantity(
    p_quantity_co2e numeric,
    p_gwp numeric
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_quantity_co2e IS NULL THEN
        RAISE EXCEPTION 'quantity_co2e is required'
            USING ERRCODE = '22023';
    END IF;
    IF p_quantity_co2e < 0 THEN
        RAISE EXCEPTION 'quantity_co2e must be non-negative'
            USING ERRCODE = '22023';
    END IF;
    IF p_gwp IS NULL OR p_gwp <= 0 THEN
        RAISE EXCEPTION 'gwp must be positive; invalid division rejected'
            USING ERRCODE = '22023';
    END IF;

    RETURN p_quantity_co2e / p_gwp;
END;
$$;

COMMENT ON FUNCTION fn_original_gas_quantity(numeric, numeric) IS
    'Derives the original gas quantity (CO2e / GWP) as NUMERIC, without floating-point conversion. Inputs: quantity_co2e >= 0, gwp > 0. Raises 22023 if GWP is null, zero, or negative, or if CO2e is invalid. ROT-FR-002.';

-- Returns emitted, reduced, and net CO2e totals for one inventory.
CREATE OR REPLACE FUNCTION fn_inventory_environmental_balance(
    p_inventory_id integer
)
RETURNS TABLE (
    inventory_id integer,
    total_emitted numeric,
    total_reduced numeric,
    net_balance numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_inventory_id IS NULL THEN
        RAISE EXCEPTION 'inventory_id is required'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT
        i.id,
        COALESCE(e.total_emitted, 0),
        COALESCE(r.total_reduced, 0),
        COALESCE(e.total_emitted, 0) - COALESCE(r.total_reduced, 0)
    FROM inventory i
    LEFT JOIN (
        SELECT em.id_inventory, SUM(em.quantity_co2e) AS total_emitted
        FROM emission em
        GROUP BY em.id_inventory
    ) e ON e.id_inventory = i.id
    LEFT JOIN (
        SELECT rd.id_inventory, SUM(rd.quantity_co2e) AS total_reduced
        FROM reduction rd
        GROUP BY rd.id_inventory
    ) r ON r.id_inventory = i.id
    WHERE i.id = p_inventory_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory % not found', p_inventory_id
            USING ERRCODE = '23503';
    END IF;
END;
$$;

COMMENT ON FUNCTION fn_inventory_environmental_balance(integer) IS
    'Returns total emitted, total reduced, and net balance (emitted - reduced) in CO2e for an inventory. An existing inventory with no facts returns zeros. Negative net balance is preserved. Raises 23503 if the inventory does not exist. ROT-FR-003.';

-- Registers a validated emission and returns its identifier.
CREATE OR REPLACE PROCEDURE sp_register_emission(
    OUT p_emission_id integer,
    IN p_quantity_co2e numeric,
    IN p_id_inventory integer,
    IN p_id_gas integer,
    IN p_id_scope integer,
    IN p_id_category integer DEFAULT NULL,
    IN p_methodology_description varchar DEFAULT NULL,
    IN p_supplier_data_percentage numeric DEFAULT NULL,
    IN p_app_actor_id text DEFAULT NULL,
    IN p_logical_origin text DEFAULT 'PROCEDURE'
)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_app_actor_id IS NOT NULL THEN
        PERFORM set_config('aether.app_actor_id', p_app_actor_id, true);
    END IF;
    PERFORM set_config('aether.logical_origin', COALESCE(p_logical_origin, 'PROCEDURE'), true);

    IF p_quantity_co2e IS NULL OR p_quantity_co2e < 0 THEN
        RAISE EXCEPTION 'quantity_co2e is required and must be non-negative'
            USING ERRCODE = '22023';
    END IF;
    IF p_id_inventory IS NULL THEN
        RAISE EXCEPTION 'id_inventory is required'
            USING ERRCODE = '22023';
    END IF;
    IF p_id_gas IS NULL THEN
        RAISE EXCEPTION 'id_gas is required'
            USING ERRCODE = '22023';
    END IF;
    IF p_id_scope IS NULL THEN
        RAISE EXCEPTION 'id_scope is required'
            USING ERRCODE = '22023';
    END IF;
    IF p_supplier_data_percentage IS NOT NULL
       AND (p_supplier_data_percentage < 0 OR p_supplier_data_percentage > 100) THEN
        RAISE EXCEPTION 'supplier_data_percentage must be between 0 and 100'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventory i WHERE i.id = p_id_inventory) THEN
        RAISE EXCEPTION 'Inventory % not found', p_id_inventory
            USING ERRCODE = '23503';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM gas g WHERE g.id = p_id_gas) THEN
        RAISE EXCEPTION 'Gas % not found', p_id_gas
            USING ERRCODE = '23503';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM scope s WHERE s.id = p_id_scope) THEN
        RAISE EXCEPTION 'Scope % not found', p_id_scope
            USING ERRCODE = '23503';
    END IF;
    IF p_id_category IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM category c WHERE c.id = p_id_category) THEN
        RAISE EXCEPTION 'Category % not found', p_id_category
            USING ERRCODE = '23503';
    END IF;

    INSERT INTO emission (
        quantity_co2e,
        methodology_description,
        supplier_data_percentage,
        id_gas,
        id_scope,
        id_category,
        id_inventory
    ) VALUES (
        p_quantity_co2e,
        p_methodology_description,
        p_supplier_data_percentage,
        p_id_gas,
        p_id_scope,
        p_id_category,
        p_id_inventory
    )
    RETURNING id INTO p_emission_id;
END;
$$;

COMMENT ON PROCEDURE sp_register_emission(integer, numeric, integer, integer, integer, integer, varchar, numeric, text, text) IS
    'Registers an emission atomically and with audit. Validates required fields, non-negative values, and existence of inventory, gas, scope, and category when provided. A null category remains valid. OUT p_emission_id identifies the created row. Validation errors are not suppressed. ROT-FR-005, ROT-FR-007, ROT-FR-008.';

-- Registers a validated reduction and returns its identifier.
CREATE OR REPLACE PROCEDURE sp_register_reduction(
    OUT p_reduction_id integer,
    IN p_quantity_co2e numeric,
    IN p_id_inventory integer,
    IN p_id_category integer,
    IN p_app_actor_id text DEFAULT NULL,
    IN p_logical_origin text DEFAULT 'PROCEDURE'
)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_app_actor_id IS NOT NULL THEN
        PERFORM set_config('aether.app_actor_id', p_app_actor_id, true);
    END IF;
    PERFORM set_config('aether.logical_origin', COALESCE(p_logical_origin, 'PROCEDURE'), true);

    IF p_quantity_co2e IS NULL OR p_quantity_co2e < 0 THEN
        RAISE EXCEPTION 'quantity_co2e is required and must be non-negative'
            USING ERRCODE = '22023';
    END IF;
    IF p_id_inventory IS NULL THEN
        RAISE EXCEPTION 'id_inventory is required'
            USING ERRCODE = '22023';
    END IF;
    IF p_id_category IS NULL THEN
        RAISE EXCEPTION 'id_category is required to register a reduction'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventory i WHERE i.id = p_id_inventory) THEN
        RAISE EXCEPTION 'Inventory % not found', p_id_inventory
            USING ERRCODE = '23503';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM category c WHERE c.id = p_id_category) THEN
        RAISE EXCEPTION 'Category % not found', p_id_category
            USING ERRCODE = '23503';
    END IF;

    INSERT INTO reduction (
        quantity_co2e,
        id_inventory,
        id_category
    ) VALUES (
        p_quantity_co2e,
        p_id_inventory,
        p_id_category
    )
    RETURNING id INTO p_reduction_id;
END;
$$;

COMMENT ON PROCEDURE sp_register_reduction(integer, numeric, integer, integer, text, text) IS
    'Registers a reduction atomically and with audit. Validates non-negative quantity and existence of inventory and category. OUT p_reduction_id identifies the created row. ROT-FR-006, ROT-FR-007, ROT-FR-008.';

REVOKE ALL ON FUNCTION fn_original_gas_quantity(numeric, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_inventory_environmental_balance(integer) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_register_emission(integer, numeric, integer, integer, integer, integer, varchar, numeric, text, text) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_register_reduction(integer, numeric, integer, integer, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_original_gas_quantity(numeric, numeric) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON FUNCTION fn_inventory_environmental_balance(integer) TO aether_app, aether_auditor, aether_admin;
GRANT EXECUTE ON PROCEDURE sp_register_emission(integer, numeric, integer, integer, integer, integer, varchar, numeric, text, text) TO aether_app, aether_admin;
GRANT EXECUTE ON PROCEDURE sp_register_reduction(integer, numeric, integer, integer, text, text) TO aether_app, aether_admin;

COMMIT;
