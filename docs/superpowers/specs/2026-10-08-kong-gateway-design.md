# Kong Gateway — Design Spec

## Contexto

O `aether_env` publica microserviços no EKS com um Ingress nginx que expõe cada carga em um prefixo de path (`/auth`, `/inventory`, `/hub`, `/`, `/admin`). O nginx faz rewrite para remover o prefixo antes de encaminhar ao backend.

Os contratos de API estão documentados em `api_java.txt` (Java: auth, profile, inventories, cloudinary) e `api_ms_aeko_hub.txt` (Python: rotas `/aether-api/v1/...`).

O repositório `aether-kong-gateway` existia fora do escopo; agora o gateway passa a ser parte do deploy.

## Objetivo

Substituir o roteamento multi-backend do Ingress nginx por um **único ponto de entrada público: Kong Gateway**. O script `aether_env` deve expor apenas o Kong via Load Balancer. Todos os microserviços e frontends ficam internos (ClusterIP) e são alcançados exclusivamente pelo Kong.

## Decisões fechadas

- Kong em modo **DB-less** com configuração declarativa (`kong.yml`).
- Imagem Kong definida em `dockerfiles/kong/` no toolskit (sem clone de repositório externo).
- Porta do proxy Kong: **8000**.
- O Ingress nginx permanece como controlador de entrada no cluster, mas com **uma única regra** apontando para o Service `kong:8000`.
- Os prefixos de path externos permanecem os mesmos para compatibilidade com `aether-web-flow` (`API_URL=http://<lb>`):
  - `/auth` → `aether-ms-auth:8080` (strip prefix)
  - `/calculator` → `aether-ms-calculator:8080` (strip prefix)
  - `/inventory` → `aether-ms-inventory:8080` (strip prefix)
  - `/cloudinary` → `aether-ms-cloudinary:8080` (strip prefix)
  - `/hub` → `ms-aeko-hub:8000` (strip prefix)
  - `/admin` → `aether-web-administrative:8080` (strip prefix)
  - `/` → `aether-web-flow:80` (sem strip)
- Nenhum microserviço ou frontend mantém `ingress_path` no catálogo; apenas `kong` tem `ingress_path: "/"`.
- `aether-rpa` continua sem exposição HTTP.
- Bancos (postgres, mongo, redis) permanecem internos.

## Arquitetura

```
Internet
  → NLB (ingress-nginx-controller)
    → Ingress (única regra: / → kong:8000)
      → Kong Gateway (DB-less, kong.yml)
        → aether-ms-auth:8080
        → aether-ms-calculator:8080
        → aether-ms-inventory:8080
        → aether-ms-cloudinary:8080
        → ms-aeko-hub:8000
        → aether-web-flow:80
        → aether-web-administrative:8080
```

## Mapeamento Kong (rotas)

| Rota externa | Serviço upstream | strip_path | Endpoints cobertos (api_*.txt) |
|---|---|---|---|
| `/auth` | aether-ms-auth | sim | `/api/auth/*`, `/api/profile` |
| `/calculator` | aether-ms-calculator | sim | (sem spec no txt; mantém rota existente) |
| `/inventory` | aether-ms-inventory | sim | `/api/inventories/*` |
| `/cloudinary` | aether-ms-cloudinary | sim | `/api/cloudinary/*` |
| `/hub` | ms-aeko-hub | sim | `/aether-api/v1/*` |
| `/admin` | aether-web-administrative | sim | frontend admin |
| `/` | aether-web-flow | não | frontend principal |

Prioridade de rotas no Kong: paths mais específicos (`/admin`, `/auth`, etc.) antes de `/`.

## Componentes novos

| Arquivo | Responsabilidade |
|---|---|
| `dockerfiles/kong/Dockerfile` | Imagem `kong:3.9` com `kong.yml` embutido |
| `dockerfiles/kong/kong.yml` | Config declarativa (services + routes) |
| `aether_env/kong.py` | Gera `kong.yml` a partir do catálogo (testável) |

## Componentes alterados

| Arquivo | Mudança |
|---|---|
| `aether_env/catalog.py` | Adiciona workload `kong`; remove `ingress_path` dos backends |
| `aether_env/manifests.py` | `render_ingress` simplificado (só Kong); ConfigMap para kong.yml opcional se gerado em runtime |
| `aether_env/actions.py` | Publica imagem Kong; aplica antes do Ingress; imprime apenas URL base do Kong |
| `tests/*` | Atualiza asserções de ingress e catálogo |

## Abordagens consideradas

1. **Kong DB-less no toolskit (recomendada)** — Simples, sem banco adicional, config versionada, alinhada ao padrão de `dockerfiles/` existente.
2. **Kong Ingress Controller** — Mais complexo; exige CRDs e outro operador no cluster.
3. **Clone do repo `aether-kong-gateway`** — Dependência externa; o toolskit perde autonomia de deploy.

Recomendação: opção 1.

## Fluxo de deploy atualizado

1. Publicar imagens das apps (incluindo `kong`).
2. Aplicar namespace, secret, configmaps de init dos bancos.
3. Aplicar StatefulSets dos bancos.
4. Aplicar Deployments das apps (sem Ingress individual).
5. Instalar ingress-nginx (inalterado).
6. Aplicar Ingress único → Kong.
7. Aguardar hostname do LB.
8. Construir `aether-web-flow` com `API_URL=http://<hostname>`.

## Testes

- Unitários em `kong.py` (geração de rotas).
- Unitários em `manifests.py` (ingress único para Kong).
- Unitários em `catalog.py` (só Kong com `ingress_path`).
- Unitários em `actions.py` (fluxo de deploy inclui Kong antes do Ingress).

## Fora de escopo

- Autenticação/rate-limit no Kong (plugins futuros).
- TLS/HTTPS no Kong.
- Migração de clientes para paths sem prefixo.
