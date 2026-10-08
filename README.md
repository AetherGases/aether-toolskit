# aether-toolskit
Ambiente para orquestração dos containeres utilizados pelo projeto Aether, onde concentram-se containeres do Docker que permitem a execução e teste de todas as APIS do projeto, além de ser um facilitador para clonar todos os repositórios.

### Como clonar todos os repositórios?
```
./scripts/repos.ps1
```
Esse comando clonará todos os repositórios do projeto para a pasta resources

### How do I operate QA and production?
Fill in the AWS keys in `.env`. The machine needs Python 3.11, aws, eksctl, kubectl, docker, and git.

```
pip install -r requirements.txt
python -m aether_env
```

QA uses blue and white and builds from `develop`. Production uses red and white and builds from `main`. Start environment creates the EKS cluster and publishes the applications and databases. Tear down environment deletes the cluster, disks, and ECR repositories. QA asks for `yes`. Production asks for `aether-prod`.