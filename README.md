# aether-toolskit
Ambiente para orquestração dos containeres utilizados pelo projeto Aether, onde concentram-se containeres do Docker que permitem a execução e teste de todas as APIS do projeto, além de ser um facilitador para clonar todos os repositórios.

### Como clonar todos os repositórios?
```
./scripts/repos.ps1
```
Esse comando clonará todos os repositórios do projeto para a pasta resources

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
