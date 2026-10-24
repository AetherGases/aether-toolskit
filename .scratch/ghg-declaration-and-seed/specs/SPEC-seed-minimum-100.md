# Spec: seed-minimum-100

**Module id:** `seed-minimum-100`

**Dependência (contrato):** `ghg-complete-declaration`

**Ordem de build:** `ghg-complete-declaration` → `seed-minimum-100`

Este documento especifica a expansão da massa fictícia de `dbAether2Year`. Não é plano de implementação, não contém `INSERT`s, DDL nem testes.

---

## Objective

Ampliar o seed PostgreSQL de **dbAether2Year** para que **toda tabela de classe B (fato / operacional / demo)** tenha **pelo menos 100 linhas**, preservando a história atual do demo e adaptando o restante (funções, views, comentários, sequences) para continuar válido com o catálogo e o volume maiores.

O seed maior **não pode**:

- quebrar FKs, UNIQUEs ou CHECKs;
- inventar 100 escopos GHG (nem outros catálogos fechados);
- substituir identidades já usadas pelos dashboards;
- assumir que o catálogo atual de 6 gases / 12 categorias é o universo inteiro da declaração.

Quem usa: quem sobe o ambiente local/QA (Docker init ou `scripts/load_postgres_init.py`) e consome `fn_dash_*`, rotinas de registro e, quando existir, `fn_ghg_complete_declaration`.

---

## Assumptions

1. O alvo é **somente** `dbAether2Year`. `dbAether1Year` e `init-postgres/08-first-year-creating-initial-tables.sql` estão **fora de escopo**.
2. “Cada tabela” **não** significa literalmente toda relação em `public`. Significa toda tabela **de classe B**. Catálogos fechados (classe A) e tabelas de auditoria/sistema (classe C) **não** são inflados com valores falsos só para chegar a 100.
3. A função `fn_ghg_complete_declaration(p_enterprise_id, p_initial_year, p_target_year)` pode ainda **não estar implementada**. Este módulo depende do **contrato**, não da existência do arquivo SQL no momento da redação desta spec. A ordem de build continua declaração → seed.
4. Contrato da declaração (não negociável neste módulo):
   - filtra inventários `APPROVED`;
   - ano via `EXTRACT(YEAR FROM inventorying_period_start)`, intervalo inclusivo;
   - gases e categorias são resolvidos **dinamicamente** (não hardcodar 6 / 12);
   - nomes de escopo permanecem `Scope 1`, `Scope 2`, `Scope 3` — **não** renomear nem proliferar escopos fictícios;
   - categorias Scope 3 sem mapeamento vão para o código `outras_escopo_iii`;
   - biogênico via `gas.is_biogenic`;
   - `reduction` **não** é remoção biogênica.
5. Não há suíte pytest SQL neste repositório. A verificação deste módulo é **load-init + asserções SQL** após o init do Postgres.
6. `python -m pytest` de `aether_env` **não** precisa mudar, a menos que se altere a lista de arquivos do loader (`scripts/load_postgres_init.py`) ou o conjunto montado em `init-postgres/`.
7. Endereços novos permanecem no Brasil (a view analítica assume país `Brazil` para unidade com endereço). Não criar unidades estrangeiras.
8. Todos os documentos, e-mails, nomes e caminhos são **fictícios**, como já declara o cabeçalho de `200-adding-users-initial.sql`. Exceção já existente: e-mails reais dos funcionários QA 13–17; esses registros **não** são alterados nem colidem com novos e-mails.
9. Identidades do demo atual são **preservadas por append**. Totais numéricos de tCO2e **podem mudar** se fatos novos forem ligados a inventários Aurora — não existem golden numbers SQL no repo.
10. `scripts/load_postgres_init.py` aplica, na ordem observada no índice do repositório: `02`–`07` em `dbAether2Year`, `08` em `dbAether1Year`, `200` em `dbAether2Year`. O volume Docker (`compose.yaml` monta `./init-postgres` em `/docker-entrypoint-initdb.d`) executa **ordem lexicográfica** num **único** `POSTGRES_DB` (`dbAether2Year`). `08` **não** tem `\connect`; isso é risco pré-existente, não deste módulo.

---

## Tech Stack

- PostgreSQL **16.10** (`compose.yaml`, serviço `postgres`)
- Banco: `dbAether2Year` (default `POSTGRES_DB_SECOND_YEAR`)
- Seed / DDL: SQL em `init-postgres/`, psql (`\connect`, `BEGIN`/`COMMIT`)
- Loader opcional de reaplicação: `scripts/load_postgres_init.py` (lê `.env`)
- Orquestração local: Docker Compose
- Testes de produto Python (fora do contrato SQL deste módulo): `python -m pytest` sobre `tests/` / `aether_env`
- Sem ORM, sem migração Alembic, sem pytest SQL

---

## Commands

Init Docker (scripts de `init-postgres/` só rodam em volume **vazio**):

```bash
docker compose down -v
docker compose up -d postgres
```

Reaplicar SQL num Postgres já configurado via `.env` (não substitui o init Docker em volume persistente):

```bash
python scripts/load_postgres_init.py
```

Pytest de `aether_env` (não é o aceite deste módulo; não deve quebrar):

```bash
python -m pytest -q
```

Asserções SQL após o init (padrão de verificação). Substituir conexão pelos valores de `.env` / `POSTGRES_*`:

```sql
-- Cardinalidade classe B (todas devem ter n >= 100)
SELECT c.relname, c.n_live_tup
FROM pg_stat_user_tables c
WHERE c.schemaname = 'public'
  AND c.relname IN (
    'plan', 'address', 'enterprise', 'plan_subscription', 'payment',
    'unit', 'department', 'permission_group', 'permission_group_permission',
    'parana_seal_forecast', 'administrator', 'storage_file', 'employee',
    'inventory', 'emission', 'reduction', 'reported_problem'
  )
ORDER BY c.relname;

-- Preferível (contagem exata, não estimate de vacuum):
SELECT 'plan' AS t, COUNT(*) FROM plan
UNION ALL SELECT 'address', COUNT(*) FROM address
UNION ALL SELECT 'enterprise', COUNT(*) FROM enterprise
UNION ALL SELECT 'plan_subscription', COUNT(*) FROM plan_subscription
UNION ALL SELECT 'payment', COUNT(*) FROM payment
UNION ALL SELECT 'unit', COUNT(*) FROM unit
UNION ALL SELECT 'department', COUNT(*) FROM department
UNION ALL SELECT 'permission_group', COUNT(*) FROM permission_group
UNION ALL SELECT 'permission_group_permission', COUNT(*) FROM permission_group_permission
UNION ALL SELECT 'parana_seal_forecast', COUNT(*) FROM parana_seal_forecast
UNION ALL SELECT 'administrator', COUNT(*) FROM administrator
UNION ALL SELECT 'storage_file', COUNT(*) FROM storage_file
UNION ALL SELECT 'employee', COUNT(*) FROM employee
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL SELECT 'emission', COUNT(*) FROM emission
UNION ALL SELECT 'reduction', COUNT(*) FROM reduction
UNION ALL SELECT 'reported_problem', COUNT(*) FROM reported_problem;

-- Classe A: cardinalidade legal (não 100 fictícios)
SELECT COUNT(*) FROM scope;       -- = 3
SELECT COUNT(*) FROM permission;  -- = 5 (catálogo atual de padrões)
SELECT name FROM scope ORDER BY id;
SELECT formula FROM gas ORDER BY id;
SELECT name FROM category ORDER BY id;

-- Demo Aurora intacto
SELECT id, name, cnpj FROM enterprise WHERE id = 1;
SELECT id FROM unit WHERE id BETWEEN 1 AND 6 ORDER BY id;
SELECT id, status, type, inventorying_period_start
FROM inventory WHERE id BETWEEN 1 AND 24 ORDER BY id;

-- Dashboard do funcionário Aurora com visibilidade
SELECT * FROM fn_dash_visible_units(1, NULL, 'user:analytics:visibility:high');
SELECT * FROM fn_dash_emissions_by_scope(1, 2024, NULL, NULL, 'user:analytics:visibility:high', 100);
SELECT * FROM fn_dash_emissions_series(1, 2022, 2025, NULL, NULL, 'user:analytics:visibility:high');

-- Completude do catálogo técnico (objetos de 2º ano)
SELECT * FROM fn_metadata_completeness();

-- Declaração (quando a função existir)
-- SELECT COUNT(*) FROM fn_ghg_complete_declaration(1, 2022, 2025);
```

Critério do padrão: para cada tabela de classe B, `COUNT(*) >= 100`.

---

## Project Structure

```
init-postgres/
  01-creating-databases.sql                  → cria dbAether1Year (fora de escopo de seed)
  02-creating-initial-tables-second-year.sql → schema 2º ano (não alterar salvo Ask first)
  03-second-year-audit-and-logs.sql          → auditoria (classe C; não semear)
  04-second-year-functions-and-procedures.sql
  05-second-year-analytical-layer.sql        → views + fn_dash_*
  06-second-year-indexes.sql
  07-second-year-metadata-catalog.sql        → technical_metadata (classe C)
  08-first-year-creating-initial-tables.sql  → FORA DE ESCOPO
  200-adding-users-initial.sql               → seed atual; ponto de extensão deste módulo
scripts/load_postgres_init.py                → ordem de reaplicação; só mudar se o artefato SQL mudar de arquivo
compose.yaml                                 → volume init-postgres → docker-entrypoint-initdb.d
tests/                                       → pytest aether_env; não é suíte SQL
.scratch/ghg-declaration-and-seed/
  specs/SPEC-seed-minimum-100.md              → esta spec
  specs/SPEC-ghg-complete-declaration.md      → contrato que este módulo consome
  issues/02-expandir-seed-minimum-100.md
```

**Arquivo a alterar (default):** `init-postgres/200-adding-users-initial.sql` — **append** de linhas e `setval`, sem apagar o bloco atual.

**Não criar** `201-*.sql` a menos que o tamanho de `200` se torne impraticável. Um arquivo extra **obriga** atualizar a tupla em `load_postgres_init.py` (e, no Docker, entra pela ordem lexicográfica). Isso é a única razão prevista para tocar pytest/`aether_env`. Preferir append em `200`.

**Não alterar** `08-first-year-*`.

---

## Code Style

Seguir o estilo já usado em `200-adding-users-initial.sql` e no SQL de segundo ano:

- `\connect dbAether2Year` no topo; um `BEGIN` / `COMMIT` (ou transação equivalente) envolvendo os novos `INSERT`s e os `setval`.
- IDs **explícitos** em todas as tabelas com `SERIAL`.
- Nomes, razões sociais, departamentos, descrições e cidades em **português fictício**.
- Documentos únicos: `enterprise.cnpj` e `unit.cnpj` = `CHAR(14)` só dígitos; `employee.cpf` = `CHAR(11)` só dígitos; `address.zip_code` = `CHAR(8)`; `unit.cnae` = `CHAR(7)`.
- E-mails únicos (`employee`, `administrator`). Não reutilizar os e-mails QA já semeados.
- `password_hash` de funcionários novos: hash mock acadêmico (padrão `$2b$12$mock.hash...` dos ids 1–12). Não copiar/alterar os Argon2id dos QA 13–17.
- Após IDs explícitos, avançar sequences com o mesmo padrão já existente:

  `SELECT setval(pg_get_serial_sequence('<tabela>', 'id'), COALESCE((SELECT MAX(id) FROM <tabela>), 1), TRUE);`

  Incluir as sequences **hoje omitidas** porque as tabelas estão vazias: `plan`, `plan_subscription`, `payment`, `administrator`.
- `COMMENT ON` novos, se houver, em **inglês**, como o restante do segundo ano.
- Não gerar SQL dinâmico dentro do seed. Sem `generate_series` que invente escopos/gases/categorias ilegais. `generate_series` é aceitável **apenas** para fatos/operacionais de classe B, se o resultado continuar explícito, determinístico e revisável — preferir `INSERT ... VALUES` legível.
- Um fato físico de emissão **não** deve ser duplicado no gás-família `HFCs` (`formula = 'HFCs'`, id 5) e numa espécie (ex.: HFC-23) ao mesmo tempo.

Exemplo de forma (ilustrativo, **não** é implementação):

```sql
\connect dbAether2Year

BEGIN;

-- Dados fictícios. Append: não reutilizar ids 1..N já ocupados.
INSERT INTO enterprise (id, name, trade_name, cnpj, id_address) VALUES
    (4, 'Empresa Fictícia Exemplo Ltda.', 'Exemplo Verde', '40000000000104', 7);

SELECT setval(pg_get_serial_sequence('enterprise', 'id'), COALESCE((SELECT MAX(id) FROM enterprise), 1), TRUE);

COMMIT;
```

---

## Testing Strategy

Não há pytest SQL. Não criar suíte pytest só para este módulo, a menos que o loader mude de caminho.

Níveis:

1. **Load-init:** `docker compose down -v && docker compose up -d postgres` aplica `02`–`07`, `08` (1º ano / risco Docker) e `200` sem erro de FK, UNIQUE, CHECK, trigger ou `setval`.
2. **Asserções de cardinalidade:** `COUNT(*) >= 100` em **todas** as tabelas de classe B; classe A com cardinalidade legal; classe C sem `INSERT` manual.
3. **Identidades:** Aurora id 1, unidades 1–6, funcionários 1–17, inventários 1–24 `APPROVED` + `INPUT` 2022–2025, escopos `Scope 1/2/3`, permissão `user:analytics:visibility:high` no grupo 1.
4. **Dashboards:** `fn_dash_visible_units(1, NULL, 'user:analytics:visibility:high')` devolve as unidades da Aurora; `fn_dash_emissions_by_scope` e `fn_dash_emissions_series` devolvem linhas para 2022–2025; split biogênico usa `gas.is_biogenic` (redução **não** entra em `green_tco2e`).
5. **Rotinas:** após `setval`, `sp_register_emission` / `sp_register_reduction` inserem id novo sem colidir com o seed. `fn_inventory_environmental_balance(1)` retorna totais (não precisa coincidir com valores pré-expansão).
6. **Metadados:** `fn_metadata_completeness()` não aponta buraco **causado por este módulo** (este módulo não cria tabelas/colunas). Lacunas pré-existentes de `08` no mesmo banco, se o Docker as materializar, estão fora de escopo.
7. **Declaração (contrato):** se `fn_ghg_complete_declaration` existir, `fn_ghg_complete_declaration(1, 2022, 2025)` produz o esqueleto de **84 linhas** (conceito do módulo provedor). Gases/categorias novos mapeados aparecem quando há fato; categorias Scope 3 extras caem em `outras_escopo_iii`; espécies não são somadas na família. Se a função ainda não existir, estas asserções ficam pendentes da ordem de build — o seed mesmo assim **deve** ser compatível com esse contrato.

Não exigir que `n_live_tup` de `pg_stat_user_tables` seja a fonte da verdade sem `ANALYZE`; usar `COUNT(*)`.

---

## Boundaries

- Always:
  - Tratar `scope` como catálogo fechado de 3 nomes GHG Protocol (`Scope 1`, `Scope 2`, `Scope 3`).
  - Preservar por append as identidades listadas em “Identidades imutáveis do demo”.
  - Avançar **todas** as sequences tocadas, inclusive as de tabelas hoje vazias.
  - Manter CNPJ/CPF/e-mail/`formula`/`permission.pattern`/`category.name`/`plan.name` únicos quando o schema exige.
  - Incluir no catálogo de gás **espécies** que a planilha de declaração conhece (HFC-23, NF3, PFCs etc.) **sem** apagar a linha-família `HFCs` e **sem** inflar para 100 fórmulas inventadas.
  - Incluir categorias que a declaração mapeia (`Emissões fugitivas`, `Processos industriais`, restantes do Scope 3 GHG Protocol) **e** categorias Scope 3 extras que exercitem `outras_escopo_iii`.
  - Ligar pelo menos alguns fatos `emission` Aurora (`APPROVED`, anos 2022–2025) às espécies/categorias novas, para o lookup dinâmico não devolver nulo quando o fato existe.
  - Respeitar triggers `fn_validate_employee_permission_group_enterprise`: grupo com `id_enterprise` precisa coincidir com a empresa da unidade do departamento; grupo global (`id_enterprise` NULL, hoje id 4) permanece válido.
  - Dados fictícios; descrições de `reported_problem` cabem em `VARCHAR(100)`; nomes de `plan` cabem em `VARCHAR(50)`.
  - Verificar load-init + `COUNT(*)` antes de declarar o módulo feito.
- Ask first:
  - Qualquer DDL (nova tabela, coluna, CHECK, UNIQUE, enum).
  - Mudar nomes dos 3 escopos ou adicionar `Scope 4` / escopos inventados.
  - Recriar/substituir (em vez de append) os ids 1–N do demo.
  - Semear `audit_row_event`, `audit_row_update`, `audit_purge_log` ou `technical_metadata` com linhas falsas.
  - Inflar `gas`, `category` ou `permission` até 100 valores sem significado de domínio.
  - Criar `201-*.sql` (muda loader / ordem Docker).
  - Alterar `08-first-year-*` ou semear `dbAether1Year`.
  - Se um UNIQUE/CHECK tornar 100 linhas de classe B **impossível** sem mudar o schema.
  - Desligar triggers de auditoria durante o seed.
- Never:
  - Escrever implementação nesta spec (sem `INSERT`s reais, sem testes, sem patches de função “por via das dúvidas”).
  - Inventar 100 scopes, 100 permissões de backend, 100 gases químicos falsos ou 100 categorias GHG sem protocolo.
  - Tratar `reduction.quantity_co2e` como remoção biogênica.
  - Enrolar espécie (HFC-23, CF4, …) no total da família `HFCs` / `PFCs` como se fossem a mesma linha.
  - Usar documentos/e-mails duplicados ou dados reais novos além dos QA já presentes.
  - Commitar segredos; os hashes atuais são mocks acadêmicos e devem permanecer mocks.
  - “Corrigir” funções set-based que já agregam `JOIN`/`GROUP BY` só porque o volume cresceu.

---

## Inventário de tabelas (dbAether2Year, schema de segundo ano)

Fonte: `CREATE TABLE` em `02`, `03`, `07`; `INSERT` em `200`; sequences no final de `200`. Contagens do seed = número de tuplas em `200-adding-users-initial.sql` (total de linhas de valor = 561). Views (`vw_*`) não são tabelas.

### Classificação (default desta spec)

| Classe | Significado | Meta de 100 linhas? |
|---|---|---|
| **A — catálogo fechado** | Cardinalidade definida por protocolo, enum de produto ou UNIQUE de domínio que **não** admite 100 valores inventados | **Não.** Expandir só com valores legalmente mapeáveis |
| **B — fato / operacional / demo** | Instâncias de negócio; 100 linhas são legais no domínio | **Sim. `COUNT(*) >= 100`** |
| **C — auditoria / sistema** | Gerada em runtime (trigger, `sp_sync_*`) | **Não semear.** Não entra no critério “cada tabela ≥ 100” |

### Classe A — não inflar até 100

| Tabela | Seed atual | UNIQUE / teto | 100 é legal? | Ação |
|---|---|---|---|---|
| `scope` | **3** | `name UNIQUE`; protocolo GHG = 3 escopos | **Não** | Manter ids 1–3 e nomes `Scope 1/2/3`. **Proibido** inventar Scope 4…100 |
| `category` | **12** | `name UNIQUE`; comentário do schema: 15 cats. Scope 3 + Other; Scope 1/2 também fechados | **Não** como padding falso | **Expandir** com nomes mapeados + extras Scope 3 para `outras_escopo_iii`. Não ir a 100 nomes inventados |
| `gas` | **6** | `formula UNIQUE`; GWP `CHECK (gwp > 0)` | **Não** como química fictícia | **Expandir** com fórmulas da planilha (espécies HFC/PFC, NF3, …). Não apagar `CO2`, `CH4`, `N2O`, `CO2(b)`, `HFCs`, `SF6` |
| `permission` | **5** | `pattern UNIQUE` + `CHECK` não vazio; catálogo do backend (`user:analytics:visibility:high`, `inventory:analysis`, `inventory:edit`, `calculator`, `chatbot`) | **Não** | Manter os 5 padrões. Não criar 95 permissões fantasmas |

Justificativa `scope`: inflar quebra o significado GHG Protocol **e** o contrato da declaração (mapeia `Scope 1/2/3` como existem hoje). `fn_dash_emissions_by_scope` agrupa por linhas reais de `scope`; 100 escopos produziriam 100 fatias sem sentido.

Justificativa `permission`: `fn_dash_visible_units` faz match de regex em `permission.pattern`. Padrões extras não autorizados pelo backend poluem autorização.

Justificativa `gas` / `category`: o schema **permite** 100 linhas (só UNIQUE de nome/fórmula), mas o domínio e a declaração **não**. A expansão é **qualitativa** (cobertura do mapa), não quantitativa (padding).

### Classe B — obrigatório ≥ 100

| Tabela | Seed atual | UNIQUE / CHECK relevantes | 100 é legal? | Alvo |
|---|---|---|---|---|
| `plan` | **0** | `name UNIQUE` (`VARCHAR(50)`); `price >= 0`; `duration_days > 0` | Sim | ≥ 100 planos fictícios |
| `address` | **6** | sem UNIQUE de negócio | Sim | ≥ 100; Brasil; ids 1–6 intactos |
| `enterprise` | **3** | `cnpj CHAR(14) UNIQUE` | Sim | ≥ 100; **id 1 Aurora permanece** |
| `plan_subscription` | **0** | `installments >= 0`; FKs plan+enterprise | Sim | ≥ 100 |
| `payment` | **0** | `value > 0`; `due_date NOT NULL`; enum `PAYMENT_STATUS`; FK subscription `ON DELETE RESTRICT` | Sim | ≥ 100 |
| `unit` | **6** | `cnpj UNIQUE`; FK enterprise+address | Sim | ≥ 100; **ids 1–6 intactos** (não acrescentar plantas na Aurora se isso puder ser evitado) |
| `department` | **12** | sem UNIQUE `(name, unit)` — nomes repetidos já existem | Sim | ≥ 100 |
| `permission_group` | **4** | `id_enterprise` opcional (NULL = global) | Sim (grupos por empresa) | ≥ 100; ids 1–4 intactos; grupo 1 Aurora com visibilidade; grupo 4 global QA |
| `permission_group_permission` | **17** | UNIQUE `(id_permission, id_permission_group)` | Sim, teto = 5 permissões × N grupos | ≥ 100, só com as 5 permissões existentes |
| `parana_seal_forecast` | **24** | `score >= 0`, `level >= 0`; N:1 com unit | Sim | ≥ 100 |
| `administrator` | **0** | `email UNIQUE` | Sim (operadores fictícios) | ≥ 100 |
| `storage_file` | **5** | sem UNIQUE de path no schema | Sim | ≥ 100 caminhos fictícios |
| `employee` | **17** | `cpf UNIQUE`, `email UNIQUE`; status enum; grupo/dept obrigatórios | Sim | ≥ 100; ids 1–17 intactos |
| `inventory` | **24** | período `end >= start`; status/type enums | Sim | ≥ 100; **ids 1–24** `APPROVED`+`INPUT` 2022–2025 intactos |
| `emission` | **359** | `quantity_co2e >= 0`; `supplier_data_percentage` 0–100; FKs gas/scope/category/inventory | Sim (já ≥ 100) | Manter 1–359; **append** fatos para gases/categorias novos |
| `reduction` | **48** | FK inventory+category; sem CHECK de sinal na tabela | Sim | ≥ 100; ids 1–48 intactos; **não** marcar como biogênico |
| `reported_problem` | **10** | enum `PROBLEM_CATEGORY`; `description VARCHAR(100)` | Sim | ≥ 100 |

Nenhuma CHECK/UNIQUE de classe B impede 100 linhas. **Não** propor DDL.

### Classe C — runtime, não semear

| Tabela | Como nasce | UNIQUE | Decisão |
|---|---|---|---|
| `audit_row_event` | trigger `trg_audit_insert_delete` em todo `INSERT`/`DELETE` de tabela de aplicação | PK | **Não** `INSERT` manual. O próprio seed expandido gera milhares de eventos INSERT. Não exige ≥ 100 como critério de aceite (embora o volume natural ultrapasse) |
| `audit_row_update` | trigger de `UPDATE` | PK | **Não** semear. Permanece ~0 se o seed só insere |
| `audit_purge_log` | `sp_purge_audit_events` | PK | **Não** semear. Não chamar purge no init |
| `technical_metadata` | `sp_sync_technical_metadata` + governance em `07` | UNIQUE parcial tabela / (tabela, coluna) | **Não** inflar. Padding exigiria relações falsas e quebraria `fn_metadata_completeness` |

`sp_attach_audit_triggers` ignora as três tabelas de audit e `technical_metadata`. Deixar os triggers ligados no seed (efeito colateral esperado: muitos `audit_row_event`).

### Fora de escopo

- Tabelas de **primeiro ano** (`addresses`, `companies`, `units`, `employees`, …) mesmo que o init Docker as crie em `dbAether2Year` por `08` sem `\connect`.
- Views analíticas (`vw_dim_org_hierarchy`, `vw_fact_emission`, `vw_fact_reduction`, `vw_analytics_org_period`).

### Exceções de domínio fechado (resumo)

Não padar: `scope`, `permission`, `gas` (exceto espécies reais), `category` (exceto nomes de protocolo / extras deliberados para `outras_escopo_iii`), nem classe C.

O desacordo possível (“cada tabela inclui `scope` e `audit_row_event`?”) está em Open Questions. **Default: não inclui.**

---

## Identidades imutáveis do demo (append, não replace)

| Objeto | Preservar |
|---|---|
| Empresa 1 | `Aurora Alimentos Sustentáveis S.A.` / `Aurora Verde` / CNPJ `10000000000101` |
| Empresas 2–3 | Horizonte Logística; Vale Circular |
| Unidades 1–6 | CNPJs e endereços atuais; `is_active = TRUE` |
| Departamentos 1–12 | pares Operações/Administrativo das 6 unidades |
| Escopos 1–3 | nomes exatamente `Scope 1`, `Scope 2`, `Scope 3` |
| Categorias 1–12 | nomes atuais (combustão, energia, Scope 3 4–12) |
| Gases 1–6 | `CO2`, `CH4`, `N2O`, `CO2(b)` biogênico, `HFCs`, `SF6` |
| Permissão 1 | `user:analytics:visibility:high` (pattern idêntico ao name) |
| Permissões 2–5 | `inventory:analysis`, `inventory:edit`, `calculator`, `chatbot` |
| Grupo 1 | `Grupo padrão Aurora` + visibilidade high (pgp id 1) |
| Grupos 2–3 | Horizonte, Vale Circular **sem** visibilidade high |
| Grupo 4 | `Grupo global QA` (`id_enterprise` NULL) |
| Funcionários 1–12 | `responsavelNN@exemplo.com` |
| Funcionários 13–17 | e-mails QA reais + hashes Argon2id atuais |
| Inventários 1–24 | anuais 2022–2025, `status = APPROVED`, `type = INPUT` |
| Emissões 1–359 e reduções 1–48 | linhas atuais intactas |
| Arquivos 1–5 e problemas 1–10 | intactos |
| Selos 1–24 | intactos |

Novos ids começam em `MAX(id)+1` de cada tabela.

**Recomendação de grafo para não distorcer o dashboard Aurora:** unidades, departamentos e inventários **novos** pertencem sobretudo a **empresas 4+**. Aurora (funcionário 1, visibilidade high) continua vendo **unidades 1 e 2**. Totais podem subir só se fatos novos forem ligados aos inventários 1–24 — permitido de forma pontual para espécies/categorias da declaração, não para “encher” a Aurora até 100 plantas.

---

## Expansão permitida de catálogo (classe A qualitativa)

### Gases a acrescentar (SHOULD)

Linhas **novas**, `formula` única, `gwp > 0` (usar GWP publicado AR5/AR6, não zero). `is_biogenic = FALSE` salvo biogênico explícito extra.

Espécies que a planilha de declaração costuma conhecer (lista mínima, nomes/fórmulas alinháveis ao mapa do módulo `ghg-complete-declaration`):

- HFC-23 (`CHF3` ou a fórmula que o mapa da declaração usar — **uma** fórmula estável, nunca as duas se o UNIQUE colidir)
- Outros HFC de espécie (ex.: HFC-32, HFC-125, HFC-134a, HFC-143a, HFC-152a, HFC-227ea) conforme o mapa
- PFCs de espécie (ex.: `CF4`, `C2F6`, `C3F8`) — **não** colapsar no total da família
- `NF3`
- Opcional: mais biogênico além de `CO2(b)` **somente** se o mapa da declaração tiver fórmula distinta

Manter a linha família `HFCs` (id 5). Fatos de teste de lookup usam a **espécie**. Não emitir a mesma quantidade nas duas linhas.

### Categorias a acrescentar (SHOULD)

`name UNIQUE`. `classification` NULL fora de Scope 3; `UPSTREAM` / `DOWNSTREAM` no Scope 3, como o schema descreve.

Mapeadas (exemplos exigidos pelo enunciado + buracos do GHG Protocol Scope 3 em relação ao seed atual 4–12):

- `Emissões fugitivas`
- `Processos industriais`
- Atividades relacionadas a combustível e energia (não incluídas nos Escopos 1 e 2)
- Ativos arrendados upstream
- Processamento de produtos vendidos
- Ativos arrendados downstream
- Franquias
- Investimentos
- Uma linha explícita de “outras” se o mapa da declaração a distinguir do fallback

**Extras Scope 3** (não mapeadas) para exercitar `outras_escopo_iii` — nomes que **não** coincidam com o mapa, por exemplo serviços de nuvem, eventos corporativos, embalagens terciárias. Pelo menos **duas** extras com fatos em inventário Aurora `APPROVED`.

Não completar até 100.

---

## Estratégia de preenchimento classe B (sem SQL)

Ordem lógica de FKs (a mesma do arquivo atual): `plan` / `address` → `enterprise` → `plan_subscription` → `payment`; `address`+`enterprise` → `unit` → `department` → `permission_group` → `permission_group_permission` → `employee`; catálogo A → `inventory` → `emission` / `reduction`; `storage_file` → `reported_problem`; `unit` → `parana_seal_forecast`; `administrator` independente.

1. **plan (≥ 100):** nomes únicos ≤ 50 caracteres; preços ≥ 0; `duration_days > 0`.
2. **address (≥ 100):** ids 1–6 intactos; CEPs `CHAR(8)`; cidades brasileiras.
3. **enterprise (≥ 100):** id 1–3 intactos; 97+ CNPJs únicos.
4. **unit (≥ 100):** ids 1–6 intactos; CNPJs únicos; preferir 1 unidade por empresa nova (evita inflar Aurora).
5. **department (≥ 100):** pelo menos um departamento por unidade nova.
6. **permission_group (≥ 100):** um grupo scoped por empresa nova; **não** copiar visibilidade high para todos — só Aurora grupo 1 (e o que já existe) tem `user:analytics:visibility:high`.
7. **permission_group_permission (≥ 100):** combinações novas `(permission existente, grupo novo)` até ≥ 100 linhas no total. Teto confortável: 5 × ~100 grupos.
8. **employee (≥ 100):** ids 1–17 intactos; CPF/e-mail únicos; grupo da **mesma** empresa do departamento (ou grupo 4 global, com parcimônia). Funcionário 1 permanece `ACTIVE`, dept 1, grupo 1.
9. **plan_subscription / payment (≥ 100 cada):** `payment.value > 0`; status no enum; FK válida. Mistura `PAID` / `WAITING` / `CANCELLED` é aceitável.
10. **administrator (≥ 100):** e-mails únicos fictícios; hash mock.
11. **inventory (≥ 100):** ids 1–24 intactos (`APPROVED`+`INPUT`, períodos calendário 2022–2025). Novos podem misturar `UNDER_REVIEW`, `REJECTED`, `PROCESSING`, `ISSUED` etc., para o filtro `APPROVED` da declaração continuar seletivo. Incluir alguns `APPROVED` em empresas novas se quiser exercitar a declaração fora da Aurora, sem substituir a Aurora.
12. **emission:** já 359. Append: espécies/categorias novas nos inventários Aurora 1–24 **e/ou** fatos nas empresas novas. `id_scope` só 1–3. `id_category` pode ser NULL (já existe no seed; a view marca `Uninformed`).
13. **reduction (≥ 100):** append; `id_category` NOT NULL na procedure de registro — no seed, seguir o padrão atual (categoria 3 e 6) e também categorias novas **não biogênicas**.
14. **storage_file / reported_problem / parana_seal_forecast:** completar até ≥ 100. Selos: vários anos por unidade são legais (já 4 por unidade nas 6 atuais).

Sequences: além das 17 já ajustadas no final de `200`, incluir `plan`, `plan_subscription`, `payment`, `administrator`. Sem isso, `sp_register_emission` não é o único risco — qualquer `INSERT` sem id explícito nessas tabelas colide ou reutiliza id 1 em tabela vazia (sequence default).

---

## Impacto nas funções, views, comentários e testes

Nenhuma função atual **hardcoda** “no máximo N plantas”, “6 gases” ou “12 categorias”. São set-based. **Default: não alterar o corpo SQL** de `04` / `05` / `07`.

| Artefato | Comportamento com seed maior | Adaptação exigida |
|---|---|---|
| `fn_dash_visible_units` | Visibilidade high = todas as unidades da empresa do funcionário | Nenhuma se Aurora não ganhar unidades extras. Se ganhar, o funcionário 1 passa a ver mais plantas — semanticamente correto para high visibility |
| `fn_dash_generated_savings` | Soma `vw_fact_reduction` no ano | Sem mudança de código. Totais mudam se reduções novas tocarem unidades visíveis |
| `fn_dash_analyses` | Conta inventários por `created_at` | Sem mudança. Inventários novos em empresas não-Aurora **não** alteram a conta do funcionário 1 |
| `fn_dash_active_plants` | Conta unidades visíveis ativas com inventário no ano | Sem mudança; continua 2 para Aurora se unidades 1–2 forem as únicas da empresa 1 |
| `fn_dash_average_insertion_interval` | LAG em `inventory.created_at` | Sem mudança. Ids 1–24 compartilham `created_at` default de init — intervalos novos só aparecem se `created_at` for preenchido de forma distinta nos appends |
| `fn_dash_plants_table` | Uma linha por unidade visível; `plant_name` = CNPJ | Sem mudança |
| `fn_dash_production_alert` / `fn_dash_critical_anomalies` | Histórico anual por unidade; alerta de cauda inferior | Sem mudança. Mais anos/fatos podem ligar/desligar `is_alert`; não há golden number |
| `fn_dash_emissions_series` | `polluting` = `NOT gas_is_biogenic`; `green` = biogênico; `reduced` separado | Sem mudança. Novos gases fósseis não podem ir para `green`. Redução não entra em `green_tco2e` |
| `fn_dash_emissions_by_scope` | Group by `scope_id` / `scope_name` | Sem mudança **desde que** `scope` continue com 3 linhas. Proibido inflar `scope` |
| `vw_fact_emission` / `vw_fact_reduction` / `vw_analytics_org_period` / `vw_dim_org_hierarchy` | CTE/joins set-based; país Brazil | Sem mudança. Hierarquia cresce com empresas novas |
| `fn_inventory_environmental_balance` | `SUM` por inventário | Sem mudança. Inventário 1 muda se receber emissões/reduções novas |
| `fn_original_gas_quantity` | aritmética CO2e/GWP | Sem mudança. GWP novo deve ser `> 0` |
| `sp_register_emission` / `sp_register_reduction` | `INSERT` sem id → serial | **Obrigatório** `setval` em `emission`/`reduction` (já existe) e nas demais tocadas |
| `fn_validate_employee_permission_group_enterprise` (+ trigger) | bloqueia grupo de outra empresa | Seed novo tem de respeitar. Sem mudança de função |
| `fn_metadata_completeness` / `sp_sync_technical_metadata` | compara `information_schema` | Sem mudança se não houver DDL. Não padar `technical_metadata` |
| `sp_apply_technical_metadata_governance` | lista de tabelas **sem** `reported_problem` | Pré-existente; fora de escopo. Sync genérico ainda cobre a tabela |
| Índices em `06` | covering set-based | Sem mudança; volume maior é o uso esperado |
| Testes SQL / pytest golden | **não existem** para estas funções | Nada a atualizar. Se surgirem golden numbers (6 plantas, 24 inventários, tCO2e fixo), atualizá-los — hoje não há |
| Comentários `COMMENT ON` | descrevem regra, não cardinalidade do seed | Só atualizar se algum comentário afirmar “três empresas” / “seis gases” como teto. Hoje falam de domínio (`Name is unique`, GWP, etc.) |
| `fn_ghg_complete_declaration` | contrato do módulo anterior | Este seed **não** implementa a função. Deve ser consumível: lookup dinâmico, 84 linhas de esqueleto, fallback `outras_escopo_iii`, biogênico só via `gas.is_biogenic` |

Se uma função **implícita** “no máximo N plantas” for descoberta depois (não está no SQL atual), a adaptação é torná-la set-based — e isso cai em **Ask first** só se exigir mudança de contrato da API.

---

## Relação com `ghg-complete-declaration`

Este módulo **não** redefine a função. Consome o contrato:

- assinatura `fn_ghg_complete_declaration(p_enterprise_id, p_initial_year, p_target_year)`;
- inventários `APPROVED` cuja `EXTRACT(YEAR FROM inventorying_period_start)` está no intervalo inclusivo;
- gases/categorias lidos do catálogo (por isso o seed acrescenta espécies/nomes reais, não assume 6/12);
- escopos somente `Scope 1/2/3`;
- Scope 3 sem mapa → `outras_escopo_iii`;
- biogênico = `gas.is_biogenic`; redução ≠ remoção biogênica;
- esqueleto conceitual de **84 linhas** permanece, independentemente de quantas espécies extras existam no catálogo.

Fatos do seed devem existir para que um lookup de HFC-23 / NF3 / categoria mapeada **não** seja nulo **quando** a declaração for executada sobre a Aurora 2022–2025.

---

## Success Criteria

Testáveis após init limpo de `dbAether2Year`:

1. Todo script de init relevante (`02`–`07`, `200`, e o loader Python na ordem documentada) aplica **sem** erro de FK, UNIQUE, CHECK, trigger de permissão ou colisão de serial.
2. `COUNT(*) >= 100` em **cada** tabela de classe B listada nesta spec.
3. Classe A: `scope` = 3 com nomes `Scope 1`, `Scope 2`, `Scope 3`; `permission` = 5 padrões atuais; `gas` e `category` contêm os ids 1–N atuais **mais** as expansões mapeadas, **sem** padding a 100 fictícios.
4. Classe C: nenhum `INSERT` manual em `audit_*` nem `technical_metadata`.
5. Identidades do demo (tabela acima) intactas; sequences ≥ `MAX(id)` em toda tabela semeada com id explícito, incluindo `plan`, `plan_subscription`, `payment`, `administrator`.
6. `fn_dash_visible_units(1, NULL, 'user:analytics:visibility:high')` retorna as unidades da Aurora; `fn_dash_emissions_by_scope` e `fn_dash_emissions_series` retornam linhas no intervalo 2022–2025 para esse funcionário.
7. Split biogênico das séries: `CO2(b)` (e quaisquer biogênicos extras) em `green_tco2e`; fósseis em `polluting_tco2e`; `reduction` só em `reduced_tco2e`.
8. `sp_register_emission` após o seed devolve um id **novo**, sem UNIQUE/PK violation.
9. `fn_inventory_environmental_balance` e `fn_metadata_completeness` executam. Completeness não regride por causa deste módulo (sem DDL).
10. Contrato da declaração: esqueleto de 84 linhas **conceitualmente** válido; espécies/categorias novas não quebram o mapa; extras Scope 3 alimentam `outras_escopo_iii`; quando a função existir, a chamada para empresa 1 / 2022–2025 não falha por FK/catálogo.
11. `python -m pytest -q` de `aether_env` permanece verde **sem** mudança, salvo se (Ask first) o loader ganhar um arquivo novo.
12. Nenhum DDL novo.

---

## Open Questions

1. **“Cada tabela” inclui `scope` e `audit_row_event`?** Default desta spec: **não**. `scope` é classe A (3 linhas). `audit_row_event` é classe C (preenchida por trigger). Se o aceite humano exigir 100 linhas em **todas** as relações de `public`, isso **conflita** com GHG Protocol e com a semântica de auditoria — precisa de decisão explícita antes do implemento.
2. **Catálogos `gas`, `category`, `permission` devem chegar a 100?** Default: **não**. Só expansão qualitativa (declaração + extras `outras_escopo_iii`). `permission` permanece 5.
3. **`administrator` e `plan` / `payment` / `plan_subscription` (hoje 0 linhas) entram na meta 100?** Default: **sim**, classe B. São dados operacionais/demo, não protocolo GHG.
4. **Tabelas de auditoria devem ser semeadas?** Default: **não**. O seed expandido já gera `audit_row_event` em massa. `audit_row_update` e `audit_purge_log` ficam naturalmente vazios.
5. **Primeiro ano (`08`, `dbAether1Year`) está no escopo?** Default: **não**. Não alterar `08-first-year-*`. Risco conhecido: no volume Docker, `08` roda **depois** de `07` **sem** `\connect` e pode criar tabelas de 1º ano **dentro** de `dbAether2Year`. Este módulo **não** as preenche até 100 e **não** corrige esse `\connect` (Ask first se o init quebrar por colisão de tipos/nomes — hoje os nomes são distintos: `address` vs `addresses`).
6. **Append em `200` vs arquivo `201`?** Default: append em `200-adding-users-initial.sql` para não mudar `load_postgres_init.py` nem pytest.
7. **Unidades extras na Aurora?** Default: **não**, para o funcionário 1 continuar a ver exatamente as plantas 1–2. Volume operacional vai para empresas 4+.
8. **Totais tCO2e dos inventários 1–24 podem mudar?** Default: **sim, pontualmente**, para fatos de espécies/categorias novas necessários à declaração. Não há golden SQL. Se algum notebook externo fixou números do seed antigo, esse notebook está fora deste repo.
9. **GWP e fórmulas exatas:** copiar 1:1 o mapa de [`SPEC-ghg-complete-declaration.md`](SPEC-ghg-complete-declaration.md). Espécies usam `gas.formula` **igual** ao `codigo` da planilha (`HFC-23`, `NF3`, `PFC-14`, …), não o sinônimo químico (`CHF3` no lugar de `HFC-23`). GWP publicado AR5/AR6, `> 0`.
10. **`technical_metadata` para `reported_problem`** não aparece na lista de governance em `07`. Fora de escopo, a menos que completeness/governance virem aceite formal deste módulo.

---

## Stop

Esta spec é o artefato do módulo `seed-minimum-100`. Não avançar para plano, tasks ou SQL até aprovação humana (ou correção das Open Questions).
