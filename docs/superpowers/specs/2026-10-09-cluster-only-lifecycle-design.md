# Ciclo de ambiente: somente cluster e node group

## Contexto

O console `python -m aether_env` opera os clusters `aether-qa` e `aether-prod`. Hoje, **Start environment** cria o EKS e em seguida publica imagens, aplica manifestos, instala ingress-nginx e constrói o gateway. **Tear down environment** apaga node groups e o cluster, e ainda remove repositórios ECR e o kubeconfig local.

Essa spec substitui o contrato de subida e descida do ambiente. As ações por carga (Start / Tear down / Update de um workload) não mudam.

## Objetivo

A subida do ambiente constrói apenas o cluster EKS e o node group gerenciado. A descida apaga o node group, o cluster e as stacks CloudFormation `eksctl-*` daquele ambiente, para a próxima subida não encontrar VPC órfã. Publicação de imagens, apply de Kubernetes, ECR e arquivos locais ficam fora desses dois fluxos.

## Decisões fechadas

- `subir_ambiente` cria o cluster e o node group `ng` via `_bootstrap_cluster` / `eksctl create cluster`. Não faz login ECR, clone, `docker build`, `docker push`, `kubectl apply`, instalação de ingress, espera de Load Balancer nem impressão de URL do gateway.
- Se o cluster já está `ACTIVE`, a subida informa que o cluster já existe e retorna `0` sem republicar cargas.
- Se o cluster está `CREATING` ou `PENDING`, a subida espera `ACTIVE` (comportamento já existente em `_bootstrap_cluster`) e retorna sem publicar cargas.
- Status de cluster existente diferente de `ACTIVE` / `CREATING` / `PENDING` interrompe a subida com código `1` e imprime o status.
- Reconciliação de stacks CloudFormation na subida permanece: é pré-requisito para o `eksctl create cluster` funcionar quando sobrou stack órfã ou `DELETE_FAILED`. Isso não é deploy de carga.
- `derrubar_ambiente` continua exigindo a frase (`yes` em QA, `aether-prod` em produção). Frase errada não chama delete.
- A descida lista node groups, apaga cada um, espera a deleção, apaga o cluster, espera a deleção e em seguida apaga as stacks `eksctl-*` (node group primeiro, depois cluster), incluindo stacks `CREATE_COMPLETE` que sobraram. Não apaga repositórios ECR e não remove o kubeconfig local.
- Cluster já ausente: imprime `Cluster was already absent.` e ainda assim remove stacks `eksctl-*` daquele ambiente, se existirem. Não limpa ECR nem kubeconfig.
- Falha de `describe-cluster` que não seja "não existe" ainda tenta apagar node group, cluster e stacks.
- Start de um workload exige o cluster `ACTIVE`. Antes de aplicar a carga, grava o kubeconfig, cria o namespace `aether`, o Secret e os ConfigMaps de init. Start do Kong também instala o ingress-nginx, aplica o Ingress e imprime a URL externa.
- Tear down / Update de workload, catálogo, menu e confirmação não mudam. Com cluster ausente, essas ações ainda recusam criar cluster.

## Fluxo de subir ambiente

1. Validar `.env` e CLIs (já ocorre em `__main__` antes do menu).
2. Consultar `aws eks describe-cluster`.
3. `ACTIVE`: imprimir `Cluster already exists.` e sair `0`.
4. Ausente, `CREATING` ou `PENDING`: `_bootstrap_cluster` (reconcilia stack se preciso, `eksctl create cluster` com node group `ng`, espera `ACTIVE`).
5. Outro status: imprimir `Cluster status is {status}.` e sair `1`.
6. Nenhum passo de kubeconfig explícito, ECR, Docker, Git ou kubectl neste fluxo.

## Fluxo de derrubar ambiente

1. Exigir a frase do ambiente.
2. Descrever o cluster. Se ausente, informar e seguir para as stacks.
3. Para cada node group: `aws eks delete-nodegroup` e `wait nodegroup-deleted`.
4. `aws eks delete-cluster` e `wait cluster-deleted`.
5. Apagar stacks `eksctl-<cluster>-*` via CloudFormation (node group, depois cluster) e esperar a deleção.
6. Não chamar `aws ecr delete-repository`.
7. Não apagar `.kube/<cluster>`.
8. Não chamar `eksctl delete`.

## Fora do escopo

Publicar cargas, aplicar manifestos, Kong, ingress-nginx, URL do gateway, exclusão de ECR, exclusão de kubeconfig, e mudanças no menu além do comportamento das duas ações de ambiente.
