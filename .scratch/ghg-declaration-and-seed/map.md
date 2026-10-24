# Declaração GHG e seed de segundo ano

## Destination

Implementar as duas specs da iniciativa: `fn_ghg_complete_declaration` em `dbAether2Year`, depois o dataload mínimo de 500 linhas nas tabelas operacionais, sem quebrar `fn_dash_*` nem o contrato da declaração.

## Notes

- Domain: SQL de segundo ano (`init-postgres/`), `dbAether2Year`.
- Specs (fonte de verdade, não duplicar nestes tickets):
  - [`CAPABILITY-MAP.md`](specs/CAPABILITY-MAP.md)
  - [`SPEC-ghg-complete-declaration.md`](specs/SPEC-ghg-complete-declaration.md)
  - [`SPEC-seed-minimum-500.md`](specs/SPEC-seed-minimum-500.md)
- Skills: spec-driven-development (spec já escrita; próxima fase é plan/tasks após aprovação humana), TDD na implementação.
- Tracker: markdown local nesta pasta. Referir tickets **pelo título**, não pelo número.
- Ordem: declaração primeiro; seed depois (`Blocked by` no ticket do seed).

## Decisions so far

Decisões de desenho estão nas specs (grilling + specify). Este mapa só registra o que os tickets de implementação resolverem.

## Not yet specified

- Aprovação humana das Open Questions das duas specs (slugs dos gases de nome longo; `ISSUED` fora; sem `p_employee_id`; se “cada tabela” inclui `scope`/`audit`; `200` vs `201`; unidades extras na Aurora).
- Plano de implementação (`tasks/` / `docs/superpowers/plans/`) — só depois da aprovação das specs.

## Out of scope

- Schema e seed de `dbAether1Year` / `08-first-year-*`.
- Quadro 1.4 e totais automáticos da planilha.
- Endpoint HTTP / DTO Java/Python do backend.
- Inflar `scope` a 500 nomes fictícios.
- Tratar `reduction` como remoção biogênica.
