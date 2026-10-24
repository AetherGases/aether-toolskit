# Implementar fn_ghg_complete_declaration

Type: task
Status: open

Spec: [`SPEC-ghg-complete-declaration.md`](../specs/SPEC-ghg-complete-declaration.md)

## Goal

Criar `fn_ghg_complete_declaration(p_enterprise_id integer, p_initial_year integer, p_target_year integer)` em `dbAether2Year`, devolvendo as 84 células manuais da planilha (quadros 1.1, 1.2, 1.3 e 1.5) para o backend.

## Do

- Implementar a função em `init-postgres/05-second-year-analytical-layer.sql` sobre `vw_fact_emission`.
- `RETURNS TABLE (quadro text, eixo text, codigo text, valor numeric)`.
- Esqueleto fixo de 84 linhas; `valor` = `SUM` dos fatos que casam, ou `NULL` (nunca `0`).
- Filtro: empresa + inventários `APPROVED` + ano de `inventorying_period_start` no intervalo inclusivo.
- Lookup dinâmico de `gas`/`category` (sem hardcodar ausência do seed).
- Família não soma espécie; biogênico só em `BIOGENICO_EMISSAO`; `BIOGENICO_REMOCAO` nulo; `reduction` ignorada.
- Sobra de Escopo III (e categoria nula nesse escopo) → `outras_escopo_iii`.
- `COMMENT ON`, `REVOKE PUBLIC`, `GRANT EXECUTE` para `aether_app`, `aether_auditor`, `aether_admin`.
- Validação: `22023` se parâmetro nulo ou início > término; `23503` se a empresa não existir.

Não alterar o seed neste ticket. Não devolver quadro 1.4 nem totais automáticos.

## Verify

Após init de `dbAether2Year`:

```sql
SELECT COUNT(*) FROM fn_ghg_complete_declaration(1, 2022, 2025);
-- 84

SELECT * FROM fn_ghg_complete_declaration(1, 2022, 2025);

SELECT * FROM fn_ghg_complete_declaration(999999, 2022, 2025);  -- RAISE 23503
SELECT * FROM fn_ghg_complete_declaration(1, 2025, 2022);       -- RAISE 22023
```

Critérios completos: secção Success Criteria da spec.

## Files

- `init-postgres/05-second-year-analytical-layer.sql` (função, comment, revoke, grant)
- Spec: `specs/SPEC-ghg-complete-declaration.md` (somente leitura)

## Comments

## Answer
