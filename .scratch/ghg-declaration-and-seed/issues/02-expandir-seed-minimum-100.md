# Expandir seed mínimo a 100 linhas

Type: task
Status: open
Blocked by: 01

Spec: [`SPEC-seed-minimum-100.md`](../specs/SPEC-seed-minimum-100.md)

## Goal

Ampliar o seed de `dbAether2Year` para `COUNT(*) >= 100` em toda tabela de **classe B**, preservando o demo Aurora e o contrato da declaração (ticket [Implementar fn_ghg_complete_declaration](01-implementar-fn-ghg-complete-declaration.md)).

## Do

- Append em `init-postgres/200-adding-users-initial.sql` (não substituir ids 1–N do demo).
- Classe B ≥ 100: `plan`, `address`, `enterprise`, `plan_subscription`, `payment`, `unit`, `department`, `permission_group`, `permission_group_permission`, `parana_seal_forecast`, `administrator`, `storage_file`, `employee`, `inventory`, `emission` (já ≥ 100; só append de fatos novos), `reduction`, `reported_problem`.
- Classe A: **não** inflar. `scope` permanece 3 (`Scope 1/2/3`). `permission` permanece 5. `gas`/`category` só expansão qualitativa alinhada à spec da declaração (`formula` = `codigo` nas espécies: `HFC-23`, `NF3`, …).
- Classe C: não semear `audit_*` nem `technical_metadata`.
- Volume novo sobretudo em empresas 4+; Aurora sem unidades extras.
- Alguns fatos Aurora `APPROVED` 2022–2025 nas espécies/categorias novas, para o lookup da declaração não ficar nulo quando o fato existe. Extras de Scope 3 exercitam `outras_escopo_iii`. Não duplicar família `HFCs` e espécie na mesma quantidade.
- `setval` em todas as sequences tocadas, inclusive `plan`, `plan_subscription`, `payment`, `administrator`.
- Não alterar o corpo de `fn_dash_*` / `fn_inventory_environmental_balance` (já são set-based), salvo colisão de serial.

## Verify

```sql
-- cada classe B: COUNT(*) >= 100
SELECT COUNT(*) FROM scope;  -- = 3
SELECT name FROM scope ORDER BY id;

SELECT * FROM fn_dash_visible_units(1, NULL, 'user:analytics:visibility:high');
SELECT * FROM fn_dash_emissions_by_scope(1, 2024, NULL, NULL, 'user:analytics:visibility:high', 100);

SELECT COUNT(*) FROM fn_ghg_complete_declaration(1, 2022, 2025);
-- 84; espécies/categorias novas preenchidas quando houver fato
```

Init limpo (`docker compose down -v && docker compose up -d postgres`) sem erro de FK/UNIQUE. Critérios completos: Success Criteria da spec do seed.

## Files

- `init-postgres/200-adding-users-initial.sql`
- Spec: `specs/SPEC-seed-minimum-100.md` (somente leitura)
- `scripts/load_postgres_init.py` só se (Ask first) nascer um `201-*.sql`

## Comments

## Answer
