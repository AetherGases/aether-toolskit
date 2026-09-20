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
    e.quantity_co2e
FROM emission e
JOIN inventory i ON i.id = e.id_inventory
LEFT JOIN department d ON d.id = i.id_department
LEFT JOIN unit u ON u.id = d.id_unit
LEFT JOIN enterprise en ON en.id = u.id_enterprise
LEFT JOIN scope s ON s.id = e.id_scope
LEFT JOIN category c ON c.id = e.id_category
LEFT JOIN gas g ON g.id = e.id_gas;

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
    r.quantity_co2e
FROM reduction r
JOIN inventory i ON i.id = r.id_inventory
LEFT JOIN department d ON d.id = i.id_department
LEFT JOIN unit u ON u.id = d.id_unit
LEFT JOIN enterprise en ON en.id = u.id_enterprise
LEFT JOIN category c ON c.id = r.id_category;

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
    rank_net_in_enterprise_period
FROM windowed;

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

GRANT SELECT ON vw_dim_org_hierarchy, vw_fact_emission, vw_fact_reduction, vw_analytics_org_period
    TO aether_app, aether_auditor, aether_admin;

COMMIT;
