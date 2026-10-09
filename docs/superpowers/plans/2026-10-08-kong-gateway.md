# Kong Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expor apenas o Kong Gateway publicamente no EKS, roteando todos os microserviços e frontends internamente.

**Architecture:** Kong DB-less com `kong.yml` gerado por `aether_env/kong.py`, imagem em `dockerfiles/kong/`, Ingress nginx com regra única para `kong:8000`. Backends sem `ingress_path`.

**Tech Stack:** Kong 3.9, Python 3.11, Kubernetes Ingress nginx, pytest.

## Global Constraints

- Não executar `python -m aether_env` nem procurar ambientes AWS reais.
- Subagentes de implementação usam modelo `composer-2.5` (nunca `composer-2.5-fast`).
- Apenas Kong tem `ingress_path` no catálogo.
- Prefixos externos inalterados: `/auth`, `/calculator`, `/inventory`, `/cloudinary`, `/hub`, `/admin`, `/`.
- `aether-rpa` sem exposição HTTP.
- Rodar `pytest` para validar; não fazer commit salvo pedido explícito.

---

### Task 1: Módulo Kong e Dockerfile

**Files:**
- Create: `aether_env/kong.py`
- Create: `dockerfiles/kong/Dockerfile`
- Create: `dockerfiles/kong/kong.yml`
- Create: `tests/test_kong.py`

**Interfaces:**
- Produces: `KONG_ROUTES: tuple[KongRoute, ...]`, `render_kong_config() -> str`

- [ ] **Step 1: Write the failing test**

```python
from aether_env.kong import KONG_ROUTES, render_kong_config


def test_kong_routes_cover_all_public_backends():
    paths = {route.path for route in KONG_ROUTES}
    assert paths == {"/auth", "/calculator", "/inventory", "/cloudinary", "/hub", "/admin", "/"}


def test_render_kong_config_declares_services_and_strip_path():
    text = render_kong_config()
    assert '_format_version: "3.0"' in text
    assert "name: aether-ms-auth" in text
    assert "strip_path: true" in text
    assert "http://aether-ms-auth.aether.svc.cluster.local:8080" in text
    assert "http://ms-aeko-hub.aether.svc.cluster.local:8000" in text
    assert "paths:" in text
    assert "path: /" in text
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_kong.py -v`
Expected: FAIL with import error

- [ ] **Step 3: Write minimal implementation**

`aether_env/kong.py`:
```python
from dataclasses import dataclass


@dataclass(frozen=True)
class KongRoute:
    name: str
    path: str
    upstream_host: str
    upstream_port: int
    strip_path: bool


KONG_ROUTES: tuple[KongRoute, ...] = (
    KongRoute("aether-ms-auth", "/auth", "aether-ms-auth.aether.svc.cluster.local", 8080, True),
    KongRoute("aether-ms-calculator", "/calculator", "aether-ms-calculator.aether.svc.cluster.local", 8080, True),
    KongRoute("aether-ms-inventory", "/inventory", "aether-ms-inventory.aether.svc.cluster.local", 8080, True),
    KongRoute("aether-ms-cloudinary", "/cloudinary", "aether-ms-cloudinary.aether.svc.cluster.local", 8080, True),
    KongRoute("ms-aeko-hub", "/hub", "ms-aeko-hub.aether.svc.cluster.local", 8000, True),
    KongRoute("aether-web-administrative", "/admin", "aether-web-administrative.aether.svc.cluster.local", 8080, True),
    KongRoute("aether-web-flow", "/", "aether-web-flow.aether.svc.cluster.local", 80, False),
)


def render_kong_config() -> str:
    lines = ['_format_version: "3.0"', "services:"]
    for route in KONG_ROUTES:
        lines.extend([
            f"  - name: {route.name}",
            f"    url: http://{route.upstream_host}:{route.upstream_port}",
            "    routes:",
            f"      - name: {route.name}-route",
            "        paths:",
            f"          - {route.path}",
            f"        strip_path: {'true' if route.strip_path else 'false'}",
        ])
    return "\n".join(lines) + "\n"
```

`dockerfiles/kong/kong.yml`: copiar saída de `render_kong_config()` (arquivo estático para build).

`dockerfiles/kong/Dockerfile`:
```dockerfile
FROM kong:3.9
COPY kong.yml /etc/kong/kong.yml
ENV KONG_DATABASE=off
ENV KONG_DECLARATIVE_CONFIG=/etc/kong/kong.yml
ENV KONG_PROXY_LISTEN=0.0.0.0:8000
ENV KONG_ADMIN_LISTEN=off
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_kong.py -v`
Expected: PASS

---

### Task 2: Catálogo e Manifests

**Files:**
- Modify: `aether_env/catalog.py`
- Modify: `aether_env/manifests.py`
- Modify: `tests/test_catalog.py`
- Modify: `tests/test_manifests.py`

**Interfaces:**
- Consumes: `KongRoute` from Task 1 (not directly; catalog is independent)
- Produces: workload `kong` with `ingress_path="/"`, `container_port=8000`; `render_ingress(workloads)` returns single Ingress to kong

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_catalog.py`:
```python
def test_only_kong_has_ingress_path():
    with_ingress = [w.key for w in WORKLOADS if w.ingress_path]
    assert with_ingress == ["kong"]
```

Update `tests/test_manifests.py`:
```python
def test_ingress_exposes_only_kong():
    kong = get_workload("kong")
    ingress = render_ingress([kong])
    assert "name: kong" in ingress
    assert "aether-apis" not in ingress
    assert "rewrite-target" not in ingress
    assert "aether-ms-auth" not in ingress
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/test_catalog.py tests/test_manifests.py -v`
Expected: FAIL

- [ ] **Step 3: Implement**

In `catalog.py`:
- Add `Workload("kong", "Kong Gateway", "app", None, 8000, "deployment", "/", None, False)` as first app entry (before auth).
- Set `ingress_path` to `None` for: auth, calculator, inventory, cloudinary, hub, web-flow, web-administrative.

In `manifests.py`, replace `render_ingress`:
```python
def render_ingress(workloads: Sequence[Workload]) -> str:
    gateway = next((w for w in workloads if w.key == "kong"), None)
    if gateway is None:
        return ""
    port = gateway.container_port or 8000
    return f"""apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aether-gateway
  namespace: aether
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {gateway.key}
                port:
                  number: {port}
"""
```

- [ ] **Step 4: Run tests**

Run: `pytest tests/test_catalog.py tests/test_manifests.py -v`
Expected: PASS

---

### Task 3: Integração no deploy (actions)

**Files:**
- Modify: `aether_env/actions.py`
- Modify: `tests/test_actions.py`

**Interfaces:**
- Consumes: `render_ingress([get_workload("kong")])`, workload `kong` in WORKLOADS
- Produces: `subir_ambiente` publica e aplica Kong; imprime apenas URL base

- [ ] **Step 1: Write failing test**

```python
def test_subir_ambiente_publishes_kong_before_ingress():
    root = Path(__file__).resolve().parents[1]
    runner = FakeRunner()
    actions = Actions(_settings(), runner, root, lambda message: None)
    actions.subir_ambiente("aether-qa")
    kong_builds = [c for c in runner.calls if c[:2] == ("docker", "build") and any("kong" in p for p in c)]
    assert kong_builds
    ingress_applies = [c for c in runner.calls if c[0] == "kubectl" and c[-2:] == ("-f", "-")]
    assert ingress_applies
```

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement in actions.py**

Changes:
1. In publish loop, include `kong` workload (build from `dockerfiles/kong/`, context = `root/dockerfiles/kong`).
2. Special-case `_publish_image` for kong: no git clone; build from `root / "dockerfiles" / "kong"`.
3. Apply kong deployment before ingress-nginx.
4. Change `render_ingress([item for item in WORKLOADS if item.ingress_path])` — already only kong.
5. Update summary URLs: print only `api_url` (base), not per-service paths.

Add helper in `images.py` or handle in actions:
```python
def is_local_dockerfile(workload: Workload) -> bool:
    return workload.key == "kong"
```

For kong publish: skip git sync, use `dockerfiles/kong` as context, tag with timestamp or branch.

6. Update `_publish_image` to handle workloads without repo (kong).

- [ ] **Step 4: Run tests**

Run: `pytest tests/test_actions.py tests/test_kong.py tests/test_catalog.py tests/test_manifests.py -v`
Expected: PASS

---

### Task 4: Ajustes finais e suite completa

**Files:**
- Modify: `aether_env/images.py` (if needed for kong local build)
- Modify: `tests/test_dockerfiles.py` (assert kong Dockerfile exists)

- [ ] **Step 1: Add test for kong dockerfile**

```python
def test_kong_dockerfile_exists():
    path = Path(__file__).resolve().parents[1] / "dockerfiles" / "kong" / "Dockerfile"
    assert path.is_file()
```

- [ ] **Step 2: Run full suite**

Run: `pytest -v`
Expected: all PASS
