\connect dbAether2Year

BEGIN;

-- Target queries: aggregations of vw_fact_emission and
-- vw_analytics_org_period by inventory, scope, category, and gas.
-- Distinct from the simple idx_emission_id_inventory index.
CREATE INDEX idx_emission_inventory_scope_category_gas
    ON emission (id_inventory, id_scope, id_category, id_gas)
    INCLUDE (quantity_co2e);

COMMENT ON INDEX idx_emission_inventory_scope_category_gas IS
    'Composite covering index for analytical emission aggregations by inventory, scope, category, and gas. Target: vw_fact_emission / totals by environmental dimension. IDX-FR-003, IDX-FR-005.';

-- Target queries: inventory to department join and period filters
-- used by vw_analytics_org_period and vw_fact_*.
CREATE INDEX idx_inventory_department_period
    ON inventory (id_department, inventorying_period_start, inventorying_period_end);

COMMENT ON INDEX idx_inventory_department_period IS
    'Composite index for analytical filters by department and inventory period. Target: vw_analytics_org_period and environmental facts. IDX-FR-001, IDX-FR-003.';

-- Target queries: stable reporting subset of completed/issued
-- inventories. Partial index (IDX-FR-004).
CREATE INDEX idx_inventory_reporting_period
    ON inventory (id_department, inventorying_period_start)
    WHERE status IN ('APPROVED', 'ISSUED');

COMMENT ON INDEX idx_inventory_reporting_period IS
    'Partial index of APPROVED/ISSUED inventories by department and period start. Target: published-inventory analytical slice. IDX-FR-004.';

-- Target queries: vw_fact_reduction aggregation by inventory and category.
CREATE INDEX idx_reduction_inventory_category_qty
    ON reduction (id_inventory, id_category)
    INCLUDE (quantity_co2e);

COMMENT ON INDEX idx_reduction_inventory_category_qty IS
    'Composite covering index for reduction aggregations by inventory and category. Target: vw_fact_reduction / vw_analytics_org_period totals. IDX-FR-003, IDX-FR-005.';

COMMIT;
