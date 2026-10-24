# PRD: Declaração GHG e seed de segundo ano

Feature slug: `ghg-declaration-and-seed`

Este PRD **não** substitui as specs. Ele só aponta o contrato e os tickets.

## Objetivo

O backend precisa de uma função SQL que devolva as células manuais da Declaração Completa de Emissão de GEE (empresa + intervalo de anos). O ambiente de demo precisa de massa ≥ 100 linhas nas tabelas operacionais, sem destruir o catálogo GHG nem as funções analíticas existentes.

## Specs

| Module id | Spec | Ticket |
|---|---|---|
| ghg-complete-declaration | [`SPEC-ghg-complete-declaration.md`](specs/SPEC-ghg-complete-declaration.md) | [Implementar fn_ghg_complete_declaration](issues/01-implementar-fn-ghg-complete-declaration.md) |
| seed-minimum-100 | [`SPEC-seed-minimum-100.md`](specs/SPEC-seed-minimum-100.md) | [Expandir seed mínimo a 100 linhas](issues/02-expandir-seed-minimum-100.md) |

Mapa da iniciativa: [`map.md`](map.md) · [`CAPABILITY-MAP.md`](specs/CAPABILITY-MAP.md)

## Ordem

1. Implementar a função (ticket 01).
2. Expandir o seed (ticket 02), consumindo o contrato da função.

## Fora deste PRD

Plano detalhado, código e testes — só após aprovação humana das specs.
