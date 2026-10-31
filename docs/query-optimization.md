# Otimização de consultas — EXPLAIN ANALYZE

Índices avaliados: os quatro criados em `init-postgres/06-second-year-indexes.sql`.

## Método

- PostgreSQL 16.10, `dbAether2Year` clonado para um banco de teste.
- Volume inflado só no clone (a carga oficial tem ~500 linhas por tabela, pequena demais para o planner preferir índices): 40 500 `inventory`, 800 507 `emission`, 200 500 `reduction`.
- `max_parallel_workers_per_gather = 0`, `VACUUM ANALYZE` antes de cada rodada, cada consulta executada duas vezes (a segunda é a medida).
- "Antes" = os quatro índices do `06` removidos; "depois" = recriados. Índices de FK do script `02` permaneceram nas duas rodadas.

## Resultados

| Consulta | Antes | Depois | Ganho |
| --- | --- | --- | --- |
| Q3 — emissão por escopo/categoria/gás, inventários publicados de 2022 | 211 ms | 53 ms | 4,0× |
| Q4 — redução por inventário/categoria (tabela inteira) | 284 ms | 267 ms | ~6% |
| Q5 — `vw_analytics_org_period` completa | 2761 ms | 1818 ms | 1,5× |

### Q3 (principal ganho)

```sql
SELECT em.id_scope, em.id_category, em.id_gas, SUM(em.quantity_co2e)
FROM emission em JOIN inventory i ON i.id = em.id_inventory
WHERE i.status IN ('APPROVED','ISSUED')
  AND i.inventorying_period_start >= DATE '2022-01-01'
  AND i.inventorying_period_start <  DATE '2023-01-01'
GROUP BY 1,2,3;
```

Antes — varredura sequencial das 800 507 linhas de `emission` e de todo `inventory` (38 462 linhas descartadas pelo filtro):

```
HashAggregate  (actual time=211.154..211.183 rows=39)
  -> Hash Join  (actual time=6.384..197.102 rows=40100)
       -> Seq Scan on emission em  (actual time=0.015..68.149 rows=800507)
       -> Seq Scan on inventory i  (Rows Removed by Filter: 38462)
Execution Time: 211.288 ms
```

Depois — o índice parcial seleciona só os 2 038 inventários publicados do período, e o índice de cobertura responde sem acessar a tabela:

```
HashAggregate  (actual time=52.521..52.565 rows=39)
  -> Bitmap Heap Scan on inventory i
       -> Bitmap Index Scan on idx_inventory_reporting_period  (rows=2038)
  -> Index Only Scan using idx_emission_inventory_scope_category_gas on emission em
       Heap Fetches: 0
Execution Time: 52.830 ms
```

### Q4 e Q5

- **Q4** lê a tabela inteira; o *Index Only Scan* em `idx_reduction_inventory_category_qty` só evita o acesso ao heap (`Heap Fetches: 0`). Ganho pequeno, esperado para agregação total.
- **Q5** continua lenta (1,8 s) porque `vw_analytics_org_period` calcula `total_emitted`/`total_reduced` com subconsultas correlacionadas, executadas 40 500 vezes (uma por inventário). Os índices de cobertura baixaram o custo de cada laço, mas o formato da consulta é o gargalo.

## Recomendações

1. Reescrever o CTE `fact_totals` da view com `LEFT JOIN (SELECT id_inventory, SUM(...) … GROUP BY id_inventory)` em vez de subconsultas escalares. Não aplicado: mudaria uma view consumida pelo BI e fica fora do escopo desta análise.
2. Manter `idx_inventory_reporting_period` (parcial): só indexa `APPROVED`/`ISSUED`, o recorte usado pelos relatórios.
3. Reavaliar com `EXPLAIN (ANALYZE, BUFFERS)` quando o volume real de produção for conhecido; com ~500 linhas por tabela o planner usa varredura sequencial por escolha própria.
4. `daily_active_user` tem `idx_daily_active_user_access_date` (com `INCLUDE (id_employee)`) para a contagem distinta por dia em `vw_dau`.

## Reprodução

```bash
# volume (no clone, com triggers de auditoria desligados na sessão)
SET session_replication_role = replica;
INSERT INTO inventory (...) SELECT ... FROM generate_series(1, 40000) g;
INSERT INTO emission  (...) SELECT ... FROM generate_series(1, 20) g CROSS JOIN (SELECT id FROM inventory WHERE name LIKE 'Perf inv%') i;
```

Atenção: o `06` começa com `\connect dbAether2Year`; ao reaplicá-lo em outro banco, remova essa linha.
