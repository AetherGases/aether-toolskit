# Spec: ghg-complete-declaration

**Module id:** `ghg-complete-declaration`

**Dependência:** nenhuma

**Ordem de build:** este módulo primeiro; `seed-minimum-500` depois

Este documento especifica a função SQL da Declaração Completa de Emissão de Gases de Efeito Estufa. Não é plano de implementação e não contém o corpo da função.

---

## Objective

Entregar `fn_ghg_complete_declaration(p_enterprise_id integer, p_initial_year integer, p_target_year integer)` em `dbAether2Year`, para o backend preencher **somente as células manuais** da planilha (quadros 1.1, 1.2, 1.3 e 1.5).

Quem usa: o backend que mapeia `(quadro, eixo, codigo) → célula`. Totais automáticos da planilha (incluindo o quadro 1.4) **não** são devolvidos.

Sucesso: uma chamada, para uma empresa e um intervalo de anos válidos, devolve **sempre 84 linhas** no contrato abaixo; `valor` é o `SUM` em tCO2e dos fatos que casam, ou `NULL` se não houver fato.

---

## Assumptions

1. Somente `dbAether2Year`. Schema de primeiro ano fora de escopo.
2. A função vive em `init-postgres/05-second-year-analytical-layer.sql`, porque o grão organizacional já está em `vw_fact_emission` (`enterprise_id`, `period_start`, `inventory_status`, `gas_is_biogenic`, `gas_formula`, `category_name`).
3. Não há visibilidade por funcionário: o corte é `p_enterprise_id` explícito, diferente de `fn_dash_*`.
4. Ano = `EXTRACT(YEAR FROM inventorying_period_start)::integer`. Inventário que cruza calendário entra só pelo ano de início.
5. Tipo `INPUT`/`OUTPUT` **não** filtra. Status **somente** `APPROVED` (não `ISSUED`).
6. `valor` ausente é SQL `NULL`, nunca `0`.
7. Códigos estáveis abaixo (slugs + fórmulas da planilha) são o contrato do backend. Rótulos longos da planilha não são o `codigo`.
8. Matching de gás usa `gas.formula` (e `gas.name` quando o código não é fórmula). A **fórmula persistida deve coincidir com o `codigo`** nas espécies (`HFC-23`, `NF3`, `SF6`, …), para o seed do módulo seguinte não inventar `CHF3` no lugar de `HFC-23`.
9. Não há fato de remoção biogênica no modelo. `BIOGENICO_REMOCAO` permanece `NULL` até existir um tipo de fato novo (fora desta spec). `reduction` não entra.
10. Não há suíte pytest SQL. Verificação = init Postgres + `SELECT` na função.
11. Comentários SQL em inglês, como o restante do segundo ano. Spec em português.
12. Backend Java/Python desta função **não** é implementado neste repositório.

→ Corrija agora se alguma destas premissas estiver errada.

---

## Tech Stack

- PostgreSQL 16 (`dbAether2Year`)
- SQL/plpgsql no estilo de `init-postgres/04-second-year-functions-and-procedures.sql` e `05-second-year-analytical-layer.sql`
- Fonte de fatos: `vw_fact_emission` (e `enterprise` para existência)
- Roles: `aether_app`, `aether_auditor`, `aether_admin`
- Sem ORM, sem endpoint HTTP neste módulo

---

## Commands

Init (volume vazio):

```bash
docker compose down -v
docker compose up -d postgres
```

Reaplicar scripts (quando o loader estiver configurado):

```bash
python scripts/load_postgres_init.py
```

Aceite da função (após init):

```sql
-- Contrato de forma: sempre 84 linhas
SELECT COUNT(*) FROM fn_ghg_complete_declaration(1, 2022, 2025);
-- esperado: 84

SELECT quadro, eixo, codigo, valor
FROM fn_ghg_complete_declaration(1, 2022, 2025)
ORDER BY quadro, eixo, codigo;

-- Empresa inexistente
SELECT * FROM fn_ghg_complete_declaration(999999, 2022, 2025);
-- esperado: RAISE 23503

-- Intervalo invertido
SELECT * FROM fn_ghg_complete_declaration(1, 2025, 2022);
-- esperado: RAISE 22023

-- Empresa válida sem APPROVED no intervalo: 84 linhas, valor NULL
```

Pytest de `aether_env` não é aceite deste módulo:

```bash
python -m pytest -q
```

---

## Project Structure

```
init-postgres/05-second-year-analytical-layer.sql  → CREATE OR REPLACE da função, COMMENT, REVOKE, GRANT
init-postgres/02-creating-initial-tables-second-year.sql → schema (não alterar neste módulo)
init-postgres/200-adding-users-initial.sql         → seed atual; volume extra é o módulo seed-minimum-500
.scratch/ghg-declaration-and-seed/
  specs/SPEC-ghg-complete-declaration.md           → esta spec
  specs/CAPABILITY-MAP.md                          → índice dos módulos
  issues/01-implementar-fn-ghg-complete-declaration.md
```

Este módulo **não** altera o seed. Pode ser demonstrado com os 6 gases / 12 categorias atuais (muitas células `NULL`).

---

## Code Style

Seguir as funções analíticas existentes:

- `LANGUAGE plpgsql`, `STABLE`, `SET search_path = public, pg_temp`
- Validar parâmetros no início; `RAISE EXCEPTION … USING ERRCODE = '22023'` para contrato de chamada; `'23503'` se a empresa não existir (mesmo espírito de `fn_inventory_environmental_balance`)
- `COMMENT ON FUNCTION` em inglês, descrevendo filtro, esqueleto e o que **não** devolve (quadro 1.4 / totais automáticos)
- `REVOKE ALL … FROM PUBLIC` + `GRANT EXECUTE` para `aether_app, aether_auditor, aether_admin`
- Sem `SECURITY DEFINER` (as `fn_dash_*` também não usam)
- Sem `COALESCE(sum, 0)` no `valor` das células — `SUM` de conjunto vazio / sem match vira `NULL`

Assinatura e retorno:

```sql
CREATE OR REPLACE FUNCTION fn_ghg_complete_declaration(
    p_enterprise_id integer,
    p_initial_year integer,
    p_target_year integer
)
RETURNS TABLE (
    quadro text,
    eixo   text,
    codigo text,
    valor  numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    -- validar; devolver 84 linhas do contrato
END;
$$;
```

Chaves: `quadro` ∈ {`1.1`,`1.2`,`1.3`,`1.5`}; `eixo` ∈ {`GAS`,`CATEGORIA`,`BIOGENICO_EMISSAO`,`BIOGENICO_REMOCAO`}.

---

## Testing Strategy

Não criar pytest Python para SQL neste módulo, a menos que o plano posterior peça um harness. Níveis de aceite:

1. **Load:** scripts `02`–`07` + `200` aplicam; a função existe em `dbAether2Year`.
2. **Forma:** toda chamada bem-sucedida devolve **84** linhas; conjunto `(quadro, eixo, codigo)` é exatamente o apêndice; sem duplicata.
3. **Validação:** nulos nos três parâmetros, `p_initial_year > p_target_year`, empresa inexistente → `RAISE` (não esqueleto).
4. **Vazio:** empresa existente sem inventário `APPROVED` no intervalo → 84 linhas com `valor` IS NULL.
5. **Filtro:** fatos `UNDER_REVIEW` / `REJECTED` / não-`APPROVED` não entram; fatos de outra empresa não entram; ano fora de `[p_initial_year, p_target_year]` não entra.
6. **Lookup dinâmico (seed atual):** `CO2`, `CH4`, `N2O`, `HFCs`/`HFC`, `SF6` e categorias com match preencham quando houver fato; `HFC-23`, `NF3`, `energia_termica`, etc. fiquem `NULL` **enquanto** não existirem no catálogo/fatos — **não** porque a função hardcodou ausência.
7. **Biogênico:** `CO2(b)` (`is_biogenic`) não soma nas células `GAS`/`CATEGORIA` antrópicas; aparece em `BIOGENICO_EMISSAO` (1.3 por categoria Scope 3 e 1.5 `ESCOPO_I`/`ESCOPO_II`). `BIOGENICO_REMOCAO` sempre NULL neste modelo. `reduction` ignorada.
8. **Família ≠ espécie:** se o seed futuro tiver `HFCs` e `HFC-23`, cada célula soma só a própria identidade.
9. **Sobra Scope 3:** categorias (e `id_category` NULL no escopo 3) que não casam com o mapa vão para `outras_escopo_iii`. Sobra Scope 1/2 não cria célula de categoria; continua no total por gás.
10. **Consolidação:** `p_initial_year = 2022` e `p_target_year = 2024` soma os três anos numa única célula `CO2` (não série anual).

---

## Boundaries

- Always:
  - Devolver o esqueleto completo de 84 linhas em sucesso.
  - Resolver gases/categorias no catálogo em tempo de execução.
  - Filtrar `inventory_status = 'APPROVED'` e `enterprise_id = p_enterprise_id`.
  - Intervalo inclusivo no ano de `period_start`.
  - Isolar biogênico via `gas_is_biogenic`.
  - Documentar a função com `COMMENT ON` e grants iguais às demais analíticas.
- Ask first:
  - Mudar a assinatura, o número de linhas, os códigos, ou incluir quadro 1.4 / totais.
  - Filtrar por funcionário/planta (visibilidade dashboard).
  - Tratar `ISSUED` como aprovado.
  - Introduzir fato/tabela de remoção biogênica.
  - Alterar DDL de `gas`/`category`/`emission`.
- Never:
  - Hardcodar “este gás não existe no seed”.
  - Somar espécies na célula da família.
  - Usar `reduction` como remoção ou como tCO2e da declaração.
  - Devolver `0` no lugar de `NULL` para célula sem fato.
  - Implementar o módulo `seed-minimum-500` nesta spec.
  - Escrever o corpo da função nesta fase (Specify).

---

## Contrato de filtragem e agregação

Fatos elegíveis (`vw_fact_emission`):

- `enterprise_id = p_enterprise_id`
- `inventory_status = 'APPROVED'`
- `EXTRACT(YEAR FROM period_start)::integer` BETWEEN `p_initial_year` AND `p_target_year` (inclusive)
- `scope_id` / `scope_name` alinhados ao quadro (`Scope 1` → 1.1 e biogênico I; `Scope 2` → 1.2 e biogênico II; `Scope 3` → 1.3)

`valor` = `SUM(quantity_co2e)` dos fatos que casam a célula. Sem fatos → `NULL`.

Antrópico (`eixo` `GAS` ou `CATEGORIA`): somente `gas_is_biogenic = FALSE` (e `gas_id` nulo não entra em `GAS`).

Biogênico (`BIOGENICO_EMISSAO`): somente `gas_is_biogenic = TRUE`.

---

## Matching de gás

Ordem: `lower(btrim(gas.formula))` = `lower(codigo)` **ou** alias **ou** `lower(btrim(gas.name))` = rótulo conhecido.

| codigo (1.1) | Aliases de formula/name |
|---|---|
| `CO2` | formula `CO2` **e** `NOT is_biogenic`. `CO2(b)` não casa |
| `CH4` | `CH4` |
| `N2O` | `N2O` |
| `HFCs` | `HFCs`, `HFC` (só a linha-família, não `HFC-23`) |
| `HFC-23` … `HFC-43-10mee` | formula igual ao codigo |
| `PFCs` | `PFCs`, `PFC` (só família) |
| `PFC-14` … `PFC-9-1-18` | formula igual ao codigo |
| `trifluorometil_pentafluoreto_enxofre` | formula `SF5CF3` **ou** name `Trifluorometil pentafluoreto de enxofre` |
| `perfluorociclopropano` | formula `c-C3F6` **ou** name `Perfluorociclopropano` |
| `SF6` | `SF6` |
| `NF3` | `NF3` |

Nos quadros 1.2 e 1.3 o codigo da família é `HFC` e `PFC` (sem “s”); casam as mesmas linhas-família.

Gás do catálogo que não está neste apêndice **não** cria linha; entra só nos totais de **categoria** (soma de todos os antrópicos daquela categoria/escopo).

---

## Matching de categoria

`codigo` estável no retorno; match em `category.name` (case-insensitive, `btrim`).

### Quadro 1.1 (`Scope 1`)

| codigo | Names que casam |
|---|---|
| `combustao_movel` | `Combustão móvel` |
| `combustao_estacionaria` | `Combustão estacionária` |
| `emissoes_fugitivas` | `Emissões fugitivas` |
| `processos_industriais` | `Processos industriais` |
| `atividades_agricolas_e_mudancas_uso_solo` | `Atividades agrícolas e mudanças no uso do solo` |
| `residuos` | `Resíduos (resíduos sólidos + efluentes)` e `Resíduos` se for esse o name persistido |

Categoria `NULL` ou name não listado no Escopo I: **não** preenche célula de categoria; o tCO2e permanece nas células `GAS`.

### Quadro 1.2 (`Scope 2`)

| codigo | Names que casam |
|---|---|
| `energia_eletrica_localizacao` | `Compra de Energia Elétrica, pelo critério de localização geográfica`; alias `Energia elétrica adquirida` |
| `energia_termica` | `Compra de Energia Térmica` |
| `perdas_transmissao_distribuicao` | `Perdas na Transmissão e Distribuição` |

Sobra / `NULL` no Escopo II: só no total por gás.

### Quadro 1.3 (`Scope 3`)

| codigo | Names que casam |
|---|---|
| `transporte_distribuicao_upstream` | `Transporte e distribuição (upstream)`; alias `Transporte e distribuição upstream` |
| `residuos_solidos_operacao` | `Resíduos sólidos gerados na operação`; alias `Resíduos gerados nas operações` |
| `efluentes_liquidos` | `Efluentes líquidos gerados` |
| `viagens_a_negocios` | `Viagens a negócios` |
| `deslocamento_casa_trabalho` | `Deslocamento (casa-trabalho)`; alias `Deslocamento de funcionários` |
| `transporte_distribuicao_downstream` | `Transporte e distribuição (downstream)`; alias `Transporte e distribuição downstream` |
| `outras_escopo_iii` | **Fallback:** todo fato Scope 3 antrópico (ou biogênico, na coluna correspondente) cuja categoria é `NULL` **ou** cujo name não casa com as seis linhas acima |

`outras_escopo_iii` também recebe fatos cuja categoria existe no banco e não está no mapa (bens adquiridos, capital, uso de produtos, fim de vida, extras futuros).

Totais de categoria = todos os gases antrópicos daquele match, não só os gases listados no quadro.

---

## Biogênico e remoções

- `BIOGENICO_EMISSAO` no 1.3: `SUM` biogênico por categoria Scope 3 (mesmo mapa, inclusive fallback `outras_escopo_iii`).
- `BIOGENICO_EMISSAO` no 1.5: codigo `ESCOPO_I` / `ESCOPO_II` = `SUM` biogênico daquele escopo (todas as categorias).
- `BIOGENICO_REMOCAO` (1.3 por categoria e 1.5 por escopo): sempre `NULL` neste modelo.
- Célula `GAS`/`CATEGORIA` **não** inclui `is_biogenic = TRUE`.

---

## Apêndice — as 84 linhas do esqueleto

Ordem de emissão livre, desde que o conjunto seja este (sem extras, sem faltas).

**1.1 GAS (36):** `CO2`, `CH4`, `N2O`, `HFCs`, `HFC-23`, `HFC-32`, `HFC-41`, `HFC-125`, `HFC-134`, `HFC-134a`, `HFC-143`, `HFC-143a`, `HFC-152`, `HFC-152a`, `HFC-161`, `HFC-227ea`, `HFC-236cb`, `HFC-236ea`, `HFC-236fa`, `HFC-245ca`, `HFC-245fa`, `HFC-365mfc`, `HFC-43-10mee`, `PFCs`, `PFC-14`, `PFC-116`, `PFC-218`, `PFC-318`, `PFC-3-1-10`, `PFC-4-1-12`, `PFC-5-1-14`, `PFC-9-1-18`, `trifluorometil_pentafluoreto_enxofre`, `perfluorociclopropano`, `SF6`, `NF3`

**1.1 CATEGORIA (6):** `combustao_movel`, `combustao_estacionaria`, `emissoes_fugitivas`, `processos_industriais`, `atividades_agricolas_e_mudancas_uso_solo`, `residuos`

**1.2 GAS (7):** `CO2`, `CH4`, `N2O`, `HFC`, `PFC`, `SF6`, `NF3`

**1.2 CATEGORIA (3):** `energia_eletrica_localizacao`, `energia_termica`, `perdas_transmissao_distribuicao`

**1.3 GAS (7):** `CO2`, `CH4`, `N2O`, `HFC`, `PFC`, `SF6`, `NF3`

**1.3 CATEGORIA (7):** `transporte_distribuicao_upstream`, `residuos_solidos_operacao`, `efluentes_liquidos`, `viagens_a_negocios`, `deslocamento_casa_trabalho`, `transporte_distribuicao_downstream`, `outras_escopo_iii`

**1.3 BIOGENICO_EMISSAO (7):** os mesmos 7 códigos de categoria 1.3

**1.3 BIOGENICO_REMOCAO (7):** os mesmos 7 códigos de categoria 1.3

**1.5 BIOGENICO_EMISSAO (2):** `ESCOPO_I`, `ESCOPO_II`

**1.5 BIOGENICO_REMOCAO (2):** `ESCOPO_I`, `ESCOPO_II`

Total: 36+6+7+3+7+7+7+7+2+2 = **84**

---

## Success Criteria

1. `fn_ghg_complete_declaration` existe em `dbAether2Year` com a assinatura desta spec.
2. Chamada válida devolve 84 linhas; o conjunto `(quadro, eixo, codigo)` é o apêndice.
3. `GRANT EXECUTE` para `aether_app`, `aether_auditor`, `aether_admin`; `REVOKE` de `PUBLIC`.
4. Parâmetros nulos ou `p_initial_year > p_target_year` → erro `22023`.
5. `p_enterprise_id` inexistente → erro `23503`.
6. Empresa sem `APPROVED` no intervalo → 84 × `valor` NULL, sem erro.
7. Com o seed atual (empresa 1, 2022–2025): células de `CO2`/`CH4`/`N2O`/`HFCs`/`HFC`/`SF6` e categorias com match **não** são todas nulas; espécies ausentes do catálogo são nulas; `BIOGENICO_EMISSAO` 1.5 `ESCOPO_I` reflete `CO2(b)` de Scope 1; `BIOGENICO_REMOCAO` é NULL.
8. Fatos de outra empresa, outro status ou outro ano não alteram os totais da chamada.
9. Quadro 1.4 e totais automáticos não aparecem.
10. Nenhuma alteração de seed ou de DDL neste módulo.

---

## Open Questions

1. Os slugs `trifluorometil_pentafluoreto_enxofre` e `perfluorociclopropano` servem ao backend, ou o `codigo` deve ser o nome completo da planilha?
2. Confirma que `ISSUED` continua **fora** do filtro (somente `APPROVED`)?
3. Confirma que a função **não** aplica visibilidade por `p_employee_id` (só empresa)?

Nada disto bloqueia a redação; os defaults estão nas Assumptions. Responder na revisão humana.

---

## Stop

Esta spec é o artefato do módulo `ghg-complete-declaration`. Não avançar para plano, tasks ou SQL até aprovação humana.
