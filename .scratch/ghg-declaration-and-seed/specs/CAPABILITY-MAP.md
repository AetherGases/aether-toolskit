# Capability Map: Declaração GHG e seed de segundo ano

| Module id | Responsibility | Depends on |
|---|---|---|
| ghg-complete-declaration | Função SQL `fn_ghg_complete_declaration` que devolve as células manuais da Declaração Completa de Emissão de GEE (quadros 1.1, 1.2, 1.3 e 1.5) | — |
| seed-minimum-100 | Ampliar o dataload de `dbAether2Year` (≥ 100 linhas nas tabelas operacionais) e manter funções/views existentes válidas com o volume maior | ghg-complete-declaration |

Build order: `ghg-complete-declaration` → `seed-minimum-100`

## Fronteira entre módulos

O contrato de lookup (códigos da planilha, aliases, biogênico, filtro `APPROVED`, esqueleto de 84 linhas) vive na spec do provedor `ghg-complete-declaration`. O módulo `seed-minimum-100` consome esse contrato: acrescenta gases/categorias reais que a função resolve, não redefine a assinatura nem o formato de retorno.

## Índice das specs

Tudo vive em `.scratch/ghg-declaration-and-seed/`.

| Module id | Spec |
|---|---|
| — | [`CAPABILITY-MAP.md`](CAPABILITY-MAP.md) (este mapa) |
| ghg-complete-declaration | [`SPEC-ghg-complete-declaration.md`](SPEC-ghg-complete-declaration.md) |
| seed-minimum-100 | [`SPEC-seed-minimum-100.md`](SPEC-seed-minimum-100.md) |

Tickets: [Implementar fn_ghg_complete_declaration](../issues/01-implementar-fn-ghg-complete-declaration.md) · [Expandir seed mínimo a 100 linhas](../issues/02-expandir-seed-minimum-100.md)
