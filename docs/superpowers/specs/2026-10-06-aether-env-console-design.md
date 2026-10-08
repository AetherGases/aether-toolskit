# Console de ambientes QA e produção

## Contexto

O `aether-toolskit` sobe Postgres, Mongo e Redis no Docker local. QA e produção precisam de um console, no terminal, que crie o EKS do zero, publique as aplicações que têm código e os três bancos, e apague o ambiente inteiro quando ele não estiver em uso.

## Objetivo

Um comando Python, `python -m aether_env`, opera dois clusters na mesma conta AWS. QA aparece em azul e branco. Produção aparece em vermelho e branco. As credenciais saem do `.env`. O console chama `aws`, `eksctl`, `kubectl`, `docker` e `git`. Ele não cria a conta, não pede credencial na tela e não imprime segredo.

## Decisões fechadas

- Subir o ambiente cria o cluster e publica as cargas. Se o cluster já estiver `ACTIVE`, a criação é pulada e as cargas são publicadas de novo.
- Derrubar o ambiente apaga o cluster, os nós, o balanceador, os volumes, os dados e os repositórios ECR daquele ambiente.
- QA só derruba depois que a pessoa digita `sim`. Produção só derruba depois que a pessoa digita `aether-prod`. Qualquer outro texto cancela.
- Subir ou derrubar um item exige o cluster `ACTIVE`. Com o ambiente desligado, o console avisa e não cria cluster.
- Subir um item coloca 1 réplica. Derrubar um item zera as réplicas e deixa o cluster no ar.
- Update de aplicação usa a branch `main`: busca o código, constrói a imagem, envia ao ECR e faz rollout.
- Update de banco não constrói imagem. Reinicia o StatefulSet na imagem fixa.
- Ficam de fora `aether-mobile`, `aether-ios`, `aeko-sdk`, `aether-docs`, `aether-analytics`, `aether-landing`, `aether-user-experience`, `aether-kong-gateway` e `aether-core-api`.

## Cargas

| Chave | Repositório | Porta | Caminho público | Imagem |
| --- | --- | --- | --- | --- |
| `aether-ms-auth` | `AetherGases/aether-ms-auth` | 8080 | `/auth` | Dockerfile do repositório |
| `aether-ms-calculator` | `AetherGases/aether-ms-calculator` | 8080 | `/calculator` | Dockerfile do repositório |
| `aether-ms-inventory` | `AetherGases/aether-ms-inventory` | 8080 | `/inventory` | Dockerfile do repositório |
| `aether-ms-cloudinary` | `AetherGases/aether-ms-cloudinary` | 8080 | `/cloudinary` | Dockerfile do repositório |
| `ms-aeko-hub` | `AetherGases/ms-aeko-hub` | 8000 | `/hub` | `dockerfiles/ms-aeko-hub/Dockerfile` |
| `aether-rpa` | `AetherGases/aether-rpa` | nenhuma | nenhum | `dockerfiles/aether-rpa/Dockerfile` |
| `aether-web-flow` | `AetherGases/aether-web-flow` | 80 | `/` | `dockerfiles/aether-web-flow/Dockerfile` |
| `aether-web-administrative` | `AetherGases/aether-web-administrative` | 8080 | `/admin` | `dockerfiles/aether-web-administrative/Dockerfile` |
| `postgres` | nenhum | 5432 | nenhum | `postgres:16.10` |
| `mongo` | nenhum | 27017 | nenhum | `mongo:8.0.13` |
| `redis` | nenhum | 6379 | nenhum | `redis:8.2` |

O RPA é worker. Não recebe Service HTTP. `DATABASE_A_URL` aponta para `POSTGRES_DB_FIRST_YEAR` e `DATABASE_B_URL` para `POSTGRES_DB_SECOND_YEAR`, ambos no Service `postgres`.

## Menu

A primeira tela oferece `1` QA, `2` Produção e `0` Sair.

Dentro do ambiente: `1` Subir ambiente, `2` Derrubar ambiente, `3` Escolher carga e `0` Voltar.

A lista de cargas numerada termina em `0` Voltar. Na carga: `1` Subir, `2` Derrubar, `3` Update e `0` Voltar.

QA usa azul brilhante (`\033[94m`) no título, no número e no nome do ambiente, e branco brilhante (`\033[97m`) no resto do texto. Produção troca o azul por vermelho brilhante (`\033[91m`) e mantém o branco no texto comum. `colorama` habilita essas sequências no terminal do Windows.

## Arquitetura

O pacote `aether_env` fica na raiz do repositório.

| Módulo | Responsabilidade |
| --- | --- |
| `catalog.py` | Lista fechada de cargas e o que cada uma precisa para build e deploy |
| `config.py` | Lê o `.env` e recusa seguir quando falta chave obrigatória |
| `theme.py` | Nome do cluster e cores |
| `confirm.py` | Frase exata de derrubada |
| `menu.py` | Telas e transição por tecla, sem chamar AWS |
| `runner.py` | Executa um comando e devolve código e saída |
| `preflight.py` | Confere se as cinco CLIs estão no `PATH` |
| `awscli.py` | Monta os argumentos de `aws` e `eksctl` |
| `images.py` | Monta clone, build, login e push |
| `kube.py` | Monta os argumentos de `kubectl` |
| `manifests.py` | Gera o YAML do namespace, dos bancos, das aplicações, do segredo e do Ingress |
| `actions.py` | Liga o menu às CLIs |
| `__main__.py` | Entrada do processo |

Os manifestos nascem em memória e entram no cluster por `kubectl apply -f -`. Senha não fica em arquivo versionado. Os Dockerfiles que os repositórios ainda não têm ficam em `dockerfiles/`.

Clusters: `aether-qa` e `aether-prod`. Namespace das cargas: `aether`. Kubeconfig local: `.kube/<cluster>`, fora do Git. Clone de build: `resources/build/<cluster>/<repo>`, também fora do Git.

Node group gerenciado, nome `ng`. Padrão `t3.large` com 2 nós. `EKS_NODE_TYPE` e `EKS_NODE_COUNT` no `.env` trocam isso. A versão do Kubernetes é a padrão do `eksctl` instalado.

Repositório ECR de aplicação: `aether/<qa|prod>/<chave>`. Tags: `main` e `main-<sha>`. Banco não tem repositório ECR.

## Fluxo de subir ambiente

1. Validar `.env` e CLIs.
2. Consultar `aws eks describe-cluster`. Cluster inexistente dispara `eksctl create cluster`, com a saída aparecendo na tela. Status diferente de `ACTIVE` em um cluster que já existe interrompe a subida e mostra esse status. Status `ACTIVE` pula a criação e publica as cargas.
3. `aws eks update-kubeconfig` grava o kubeconfig daquele cluster.
4. Criar o repositório ECR de cada aplicação que ainda não existe.
5. Clonar ou atualizar a `main`, construir e enviar a imagem de cada aplicação, exceto `aether-web-flow`.
6. Aplicar namespace, Secret, ConfigMaps de `init-postgres/` e `init-mongo/init.js`, StatefulSets e Deployments das outras cargas.
7. Instalar o ingress-nginx pelo manifesto AWS `controller-v1.11.3` e aplicar o Ingress.
8. Esperar até 5 minutos pelo hostname do Service `ingress-nginx-controller`. Com o hostname, construir `aether-web-flow` usando `API_URL=http://<hostname>`. Sem hostname nesse prazo, construir com `API_URL` vazio e dizer isso no resumo.
9. Imprimir o hostname, o caminho de cada carga HTTP e a saída de `kubectl get pods -n aether`. Se uma imagem falhar, as outras continuam. O cluster permanece. O comando termina com código 1 e nomeia as cargas que falharam.

O Ingress reescreve o prefixo. A aplicação continua servindo em `/` dentro do pod. `aether-web-flow` ocupa `/` e não é reescrito.

## Fluxo de derrubar ambiente

1. Exigir a frase do ambiente.
2. `eksctl delete cluster --wait`.
3. `aws ecr delete-repository --force` em cada repositório ECR daquele ambiente.
4. Apagar o kubeconfig local.
5. Cluster inexistente ainda assim remove os repositórios ECR e o kubeconfig, e informa que o cluster já estava ausente.

O StorageClass padrão do EKS usa reclaim `Delete`. O volume some com o PVC, e o PVC some com o cluster.

## Fluxo de um item

Cluster ausente: mensagem `Ambiente desligado. Suba o ambiente antes.` e nenhuma chamada de scale, build ou delete.

Subir: se o workload ainda não existe, publica a imagem (aplicação) e aplica o manifesto daquela carga; em seguida escala para 1. Derrubar: escala para 0. Update de aplicação: atualiza a `main`, faz push das duas tags, `kubectl set image` e `kubectl rollout status` com timeout de 180 segundos. Update de banco: `kubectl rollout restart` no StatefulSet e espera o rollout.

## Configuração

Obrigatórias no `.env`: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB_FIRST_YEAR`, `POSTGRES_DB_SECOND_YEAR`, `MONGO_USER`, `MONGO_PASSWORD`, `MONGO_DB`, `REDIS_PASSWORD`, `JWT_SECRET`.

Opcionais: `AWS_SESSION_TOKEN`, `EKS_NODE_TYPE` (padrão `t3.large`), `EKS_NODE_COUNT` (padrão `2`). Toda outra chave presente no `.env` entra no Secret das aplicações. Chave vazia segue vazia. O console não inventa valor. `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`, `EKS_NODE_TYPE` e `EKS_NODE_COUNT` não entram nesse Secret. Host e porta de Postgres, Mongo e Redis no Secret são sempre os Services do cluster, mesmo que o `.env` traga `localhost`.

Dentro do cluster, host e porta dos bancos são os Services `postgres:5432`, `mongo:27017` e `redis:6379`. As aplicações Java recebem `API_PORT` e `SERVER_PORT` `8080`. O hub recebe `PORT` `8000`, `MONGO_URI` e `REDIS_URI` apontando para esses Services. Os Dockerfiles deste toolkit gravam `/app/.env` antes do processo principal. As quatro imagens Java, que já trazem Dockerfile no repositório, recebem os mesmos valores só pelo ambiente do container. O Spring Boot lê essas variáveis sem arquivo dotenv.

A identidade AWS precisa criar EKS, CloudFormation, VPC, IAM de cluster, ECR e Load Balancer. O console não cria essa identidade.

Pré-requisito da máquina: Python 3.11 ou superior, `aws`, `eksctl`, `kubectl`, `docker` e `git` no `PATH`.

## Falhas

- Falta de chave obrigatória: encerra antes de qualquer CLI de nuvem e lista só o nome das chaves.
- CLI ausente: encerra e lista o executável que não está no `PATH`.
- `eksctl` ou `kubectl` com saída diferente de zero: a etapa para, a saída do comando aparece na tela, e o cluster não é apagado por causa dessa falha.
- Frase de derrubada diferente da esperada: nenhuma chamada de delete.
- Build com falha no meio do ambiente: as cargas seguintes ainda são tentadas; o resumo final separa sucesso e falha.

## Testes

A suíte automatizada não chama AWS, Docker nem Git. Ela cobre catálogo, leitura do `.env`, cores, frase de confirmação, transição do menu, argumentos dos comandos, YAML gerado e um orquestrador com runner falso. Subir um cluster de verdade fica para a pessoa operar o console com a credencial do `.env`.

## Fora do escopo

Conta AWS, domínio próprio, HTTPS, CI de imagem, alterar os repositórios das aplicações, escalar para mais de uma réplica e manter dados depois da derrubada do ambiente.
