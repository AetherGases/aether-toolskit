# Aether Toolskit

Ambiente local e **fonte do schema de banco de dados** do [Aether](https://github.com/AetherGases). O `compose.yaml` sobe PostgreSQL, MongoDB e Redis já inicializados (tabelas, funções, views analíticas, dados fictícios e gatilhos do RPA), o que basta para rodar e testar os microsserviços na sua máquina.

Também documenta o banco (backup, recuperação e otimização de consultas) e reúne um script para clonar todos os repositórios.

## Começando

Pré-requisitos: Docker com Compose.

```bash
git clone https://github.com/AetherGases/aether-toolskit.git
cd aether-toolskit
cp .env.example .env     # ajuste senhas e portas se quiser
docker compose up -d
```

| Serviço | Container | Imagem | Porta padrão do `compose.yaml` |
| --- | --- | --- | --- |
| PostgreSQL | `aether_postgres` | `postgres:16.10` | `5432` (`POSTGRES_PORT`) |
| MongoDB | `aether_mongo` | `mongo:8.0.13` | `27017` (`MONGO_PORT`) |
| Redis | `aether_redis` | `redis:8.2` (com `appendonly`) | `6379` (`REDIS_PORT`) |

Os scripts em `init-postgres/` e `init-mongo/` rodam **apenas na primeira inicialização** do volume. Para recriar do zero: `docker compose down -v && docker compose up -d`.

> O `.env.example` traz portas diferentes das padrão (`5435`, `27018` e `6380`) para não colidir com bancos já instalados na máquina. Use os mesmos valores nos `.env` dos serviços. Sem `.env`, o Compose usa os padrões da tabela e as credenciais `sa` / `password`.

## O que é criado

Dois bancos PostgreSQL convivem de propósito, e o [aether-rpa](https://github.com/AetherGases/aether-rpa) os mantém sincronizados:

| Banco | Origem | Usado por |
| --- | --- | --- |
| `dbAether1Year` | Modelo do 1º ano (cadastro) | [aether-web-administrative](https://github.com/AetherGases/aether-web-administrative) e o outbox do RPA |
| `dbAether2Year` | Modelo normalizado (3FN) do 2º ano | Microsserviços Java, BI e auditoria |

Ordem dos scripts de `init-postgres/` (o Postgres executa em ordem alfabética):

| Script | Conteúdo |
| --- | --- |
| `01` | Criação dos dois bancos |
| `02` | Tabelas e enums do 2º ano (escopos, categorias, gases, inventários, emissões, reduções, selo) |
| `03` | Auditoria e logs, com mascaramento de dados sensíveis |
| `04` | Funções e procedures (registrar emissão e redução, totais por inventário) |
| `05` | Camada analítica: views de fatos (`vw_fact_emission`, `vw_fact_reduction`), hierarquia e totais por período |
| `06` | Índices para as consultas analíticas |
| `07` | Catálogo de metadados (domínio, finalidade, sensibilidade) |
| `08` (`.legacy`) | Versão antiga do schema do 1º ano. Não é executada |
| `10` | Banco do 1º ano (MVP) |
| `11` | Monitoramento de usuários ativos por dia (DAU) |
| `12` | Carga inicial do 1º ano (planos, gases, permissões) |
| `13` | **Outbox e triggers do RPA** nos dois bancos |
| `200` | Dados fictícios para desenvolvimento e BI |
| `201` | Privilégios dos papéis (servlet, usuários) |

O MongoDB recebe o banco `dbAether` com as coleções iniciais (`init-mongo/init.js`), usado pelas sessões de IA e pelas notificações.

## Clonar todos os repositórios

```powershell
./scripts/repos.ps1
```

Clona os repositórios do projeto em `resources/`. O script é PowerShell (use `pwsh` no Linux ou macOS).

> **Atenção:** a lista em `scripts/repos.ps1` está defasada. Ela ainda inclui `aether-analytics` (hoje `aether-bi`), `aether-landing` e `aether-user-experience` (não encontrados na organização) e `aether-core-api` (arquivado e privado), e não inclui `aether-bi`, `aether-infra` (privado) nem o `.github`. O `git clone` desses itens falha, mas o restante é clonado. Veja o [perfil da organização](https://github.com/AetherGases) para a lista atual.

## Documentação operacional

- [`docs/backup-recovery.md`](docs/backup-recovery.md): o que proteger, política de backup, recuperação total, de uma tabela e por ponto no tempo, e o passo de pós-restauração do RPA.
- [`docs/query-optimization.md`](docs/query-optimization.md): método e resultados da otimização das consultas analíticas.

## Ao alterar o schema

1. Edite o script SQL correspondente aqui. O Hibernate dos microsserviços roda com `ddl-auto: validate` e nunca altera o banco.
2. Se a mudança envolver uma das 11 tabelas replicadas, atualize também o `13-rpa-outbox-triggers.sql` e o `src/definition.py` do `aether-rpa`.
3. Reflita a mudança nas entidades JPA dos microsserviços afetados.

## Justificativa do projeto

Empresas que querem reduzir emissões precisam primeiro medir o que emitem. No Brasil, essa medição segue o padrão do **GHG Protocol** (Programa Brasileiro GHG Protocol), que organiza o inventário de gases de efeito estufa (GEE) por escopo, categoria e gás. No Paraná, empresas que querem obter o **Selo Clima Paraná**, concedido pela **SEDEST** (Secretaria do Desenvolvimento Sustentável), precisam enviar esse inventário pela planilha de inscrição do selo.

Hoje esse processo é manual: os dados ficam espalhados em planilhas, são difíceis de consolidar entre unidades e de comparar ano a ano. O Aether centraliza esses inventários em um único banco de dados, valida os dados e gera análises e previsões para apoiar a empresa na redução de emissões e na conquista do selo.

Por isso, **o banco de dados foi modelado para ter máxima compatibilidade com os inventários de gases do GHG Protocol e com a planilha de inscrição do Selo Clima Paraná (SEDEST)**. Cada campo do inventário tem um lugar próprio no modelo, sem conversões ou perda de informação na importação e na exportação.

### Evidências no modelo de dados

Todas as referências abaixo estão em [`init-postgres/02-creating-initial-tables-second-year.sql`](init-postgres/02-creating-initial-tables-second-year.sql) (estrutura) e [`init-postgres/200-adding-users-initial.sql`](init-postgres/200-adding-users-initial.sql) (dados de catálogo).

**Compatibilidade com o GHG Protocol**

| Conceito do GHG Protocol | Onde está no banco |
|---|---|
| Escopos 1, 2 e 3 | Tabela `scope`, com os registros `Scope 1`, `Scope 2` e `Scope 3` |
| Categorias de emissão de cada escopo (combustão estacionária, combustão móvel, emissões fugitivas, processos industriais, energia adquirida etc.) | Tabela `category` |
| 15 categorias do Escopo 3, separadas em upstream e downstream | Coluna `category.classification` (enum `CATEGORY_CLASSIFICATION`: `UPSTREAM` / `DOWNSTREAM`) |
| Os 7 gases do Protocolo de Quioto (CO2, CH4, N2O, HFCs, PFCs, SF6 e NF3), incluindo cada HFC e PFC individual | Tabela `gas` (`name`, `formula`) |
| Conversão para CO2 equivalente pelo potencial de aquecimento global (GWP) | Coluna `gas.gwp`, com valores do IPCC AR5 (ex.: CH4 = 28, N2O = 265, SF6 = 23500) |
| Relato separado de CO2 biogênico | Coluna `gas.is_biogenic` e gás `CO2(b)` |
| Informações descritivas do inventário: abordagem de consolidação e período inventariado | Tabela `inventory` (`consolidation_approach`, `inventorying_period_start`, `inventorying_period_end`) |
| Emissões em tCO2e por escopo, categoria e gás | Tabela `emission` (`quantity_co2e`, `id_scope`, `id_category`, `id_gas`) |
| Descrição da metodologia e percentual de dados de fornecedores (Escopo 3) | Colunas `emission.methodology_description` e `emission.supplier_data_percentage` |
| Reduções de emissões | Tabela `reduction` (`quantity_co2e`, `id_category`) |

**Compatibilidade com a planilha de inscrição do Selo Clima Paraná (SEDEST)**

| Informação da inscrição | Onde está no banco |
|---|---|
| Identificação da empresa (razão social, nome fantasia, CNPJ) | Tabela `enterprise` (`name`, `trade_name`, `cnpj`) |
| Identificação de cada unidade (CNPJ e CNAE) | Tabela `unit` (`cnpj`, `cnae`) |
| Localização da unidade (estado, cidade, endereço) | Tabela `address` |
| Inventário de emissões da unidade no período | Tabelas `inventory` e `emission`, ligadas à unidade por meio de `department` |
| Pontuação, nível e validade do selo | Tabela `parana_seal_forecast` (`score`, `level`, `valid_until`) |

A camada analítica ([`init-postgres/05-second-year-analytical-layer.sql`](init-postgres/05-second-year-analytical-layer.sql)) reaproveita as mesmas dimensões do GHG Protocol (unidade, período, escopo, categoria e gás) nas views `vw_fact_emission` e `vw_fact_reduction`. Assim, os relatórios e dashboards usam a mesma estrutura que o inventário oficial.
