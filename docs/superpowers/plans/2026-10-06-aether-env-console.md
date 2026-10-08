# Console de ambientes QA e produção — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar o comando `python -m aether_env`, que sobe e derruba EKS de QA e de produção e opera as oito aplicações e os três bancos.

**Architecture:** Um pacote Python na raiz desenha o menu e monta argumentos de `aws`, `eksctl`, `kubectl`, `docker` e `git`. Os manifestos nascem em memória. Os Dockerfiles que faltam nos repositórios ficam em `dockerfiles/`. A suíte testa catálogo, cores, frases, menu e comandos com um runner falso.

**Tech Stack:** Python 3.11, colorama, pytest, eksctl, kubectl, AWS CLI, Docker, Git.

## Global Constraints

- Comando de entrada: `python -m aether_env`.
- Python 3.11 ou superior.
- CLIs obrigatórias no `PATH`: `aws`, `eksctl`, `kubectl`, `docker`, `git`.
- Credenciais só do `.env`. O processo não pede segredo e não imprime segredo.
- Clusters: `aether-qa` e `aether-prod`, na região `AWS_REGION`, node group `ng`.
- Padrão de nó: `t3.large`, quantidade `2`, trocável por `EKS_NODE_TYPE` e `EKS_NODE_COUNT`.
- A versão do Kubernetes é a padrão do `eksctl` instalado.
- Namespace das cargas: `aether`.
- QA: azul brilhante `\033[94m` no título, no número e no nome do ambiente; branco brilhante `\033[97m` no restante.
- Produção: vermelho brilhante `\033[91m` no título, no número e no nome do ambiente; branco brilhante `\033[97m` no restante.
- Derrubar QA exige a frase `sim`. Derrubar produção exige a frase `aether-prod`.
- Derrubar o ambiente apaga cluster, nós, balanceador, volumes, dados e os repositórios ECR daquele ambiente.
- Subir ou derrubar um item com o cluster ausente imprime `Ambiente desligado. Suba o ambiente antes.` e não cria cluster.
- Subir item: 1 réplica. Derrubar item: 0 réplicas.
- Update de aplicação usa a branch `main`. Update de banco faz `rollout restart` na imagem fixa.
- Imagens fixas: `postgres:16.10`, `mongo:8.0.13`, `redis:8.2`.
- Ingress nginx: manifesto AWS `controller-v1.11.3`.
- `aether-web-flow` ocupa `/` sem rewrite. As outras cargas HTTP usam rewrite do prefixo.
- Sem hostname do balanceador em 5 minutos, `aether-web-flow` é construído com `API_URL` vazio e o resumo diz isso.
- Falha de imagem não apaga o cluster. As outras cargas continuam. O código de saída é 1.
- Fora do menu: `aether-mobile`, `aether-ios`, `aeko-sdk`, `aether-docs`, `aether-analytics`, `aether-landing`, `aether-user-experience`, `aether-kong-gateway`, `aether-core-api`.

---

### Task 1: Catálogo, tema, confirmação e configuração

**Files:**
- Create: `pyproject.toml`
- Create: `aether_env/__init__.py`
- Create: `aether_env/catalog.py`
- Create: `aether_env/theme.py`
- Create: `aether_env/confirm.py`
- Create: `aether_env/config.py`
- Test: `tests/test_catalog.py`
- Test: `tests/test_config.py`

**Interfaces:**
- Consumes: nada
- Produces:
  - `Workload(key, title, kind, repo, container_port, k8s_kind, ingress_path, image, dockerfile_in_repo)`
  - `WORKLOADS: tuple[Workload, ...]`
  - `get_workload(key: str) -> Workload`
  - `Theme(cluster_name, slug, accent, text, reset)`
  - `QA`, `PROD`, `theme_for(cluster_name: str) -> Theme`
  - `required_phrase(cluster_name: str) -> str`
  - `phrase_accepted(cluster_name: str, typed: str) -> bool`
  - `ConfigError(missing: tuple[str, ...])`
  - `Settings(aws_access_key_id, aws_secret_access_key, aws_session_token, aws_region, node_type, node_count, values)`
  - `load_settings(env: Mapping[str, str]) -> Settings`
  - `application_secret_data(settings: Settings) -> dict[str, str]`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_catalog.py
from aether_env.catalog import WORKLOADS, get_workload
from aether_env.confirm import phrase_accepted, required_phrase
from aether_env.theme import PROD, QA


def test_catalog_has_eight_apps_and_three_databases():
    keys = [item.key for item in WORKLOADS]
    assert keys == [
        "aether-ms-auth",
        "aether-ms-calculator",
        "aether-ms-inventory",
        "aether-ms-cloudinary",
        "ms-aeko-hub",
        "aether-rpa",
        "aether-web-flow",
        "aether-web-administrative",
        "postgres",
        "mongo",
        "redis",
    ]
    assert get_workload("postgres").image == "postgres:16.10"
    assert get_workload("mongo").image == "mongo:8.0.13"
    assert get_workload("redis").image == "redis:8.2"
    assert get_workload("aether-rpa").ingress_path is None
    assert get_workload("aether-web-flow").ingress_path == "/"
    assert get_workload("aether-ms-auth").dockerfile_in_repo is True
    assert get_workload("ms-aeko-hub").dockerfile_in_repo is False


def test_themes_and_phrases():
    assert QA.cluster_name == "aether-qa"
    assert QA.accent == "\033[94m"
    assert QA.text == "\033[97m"
    assert PROD.accent == "\033[91m"
    assert required_phrase("aether-qa") == "sim"
    assert required_phrase("aether-prod") == "aether-prod"
    assert phrase_accepted("aether-qa", " sim ") is True
    assert phrase_accepted("aether-prod", "sim") is False
```

```python
# tests/test_config.py
import pytest

from aether_env.config import ConfigError, application_secret_data, load_settings


def _env():
    return {
        "AWS_ACCESS_KEY_ID": "aki",
        "AWS_SECRET_ACCESS_KEY": "secret",
        "AWS_REGION": "sa-east-1",
        "POSTGRES_USER": "sa",
        "POSTGRES_PASSWORD": "p@ss",
        "POSTGRES_DB_FIRST_YEAR": "dbAether1Year",
        "POSTGRES_DB_SECOND_YEAR": "dbAether2Year",
        "MONGO_USER": "mongo",
        "MONGO_PASSWORD": "mp",
        "MONGO_DB": "dbAether",
        "REDIS_PASSWORD": "rp",
        "JWT_SECRET": "jwt",
        "GEMINI_API_KEY": "",
        "POSTGRES_HOST": "localhost",
    }


def test_missing_required_key_lists_only_the_name():
    env = _env()
    env["JWT_SECRET"] = "  "
    with pytest.raises(ConfigError) as caught:
        load_settings(env)
    assert caught.value.missing == ("JWT_SECRET",)


def test_defaults_and_secret_rewrite_hosts():
    settings = load_settings(_env())
    assert settings.node_type == "t3.large"
    assert settings.node_count == 2
    data = application_secret_data(settings)
    assert "AWS_SECRET_ACCESS_KEY" not in data
    assert data["POSTGRES_HOST"] == "postgres"
    assert data["POSTGRES_PORT"] == "5432"
    assert data["API_PORT"] == "8080"
    assert data["SERVER_PORT"] == "8080"
    assert data["PORT"] == "8000"
    assert data["DATABASE_A_URL"] == "postgresql://sa:p%40ss@postgres:5432/dbAether1Year"
    assert data["DATABASE_B_URL"].endswith("/dbAether2Year")
    assert data["MONGO_URI"].startswith("mongodb://mongo:mp@mongo:27017/dbAether")
    assert data["REDIS_URI"] == "redis://:rp@redis:6379/0"
    assert data["GEMINI_API_KEY"] == ""
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m pytest tests/test_catalog.py tests/test_config.py -v`

Expected: FAIL with `ModuleNotFoundError: No module named 'aether_env'`

- [ ] **Step 3: Write the implementation**

```toml
# pyproject.toml
[project]
name = "aether-env"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = ["colorama>=0.4.6"]

[project.optional-dependencies]
dev = ["pytest>=8.3"]

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
```

```python
# aether_env/__init__.py
```

```python
# aether_env/catalog.py
from dataclasses import dataclass


@dataclass(frozen=True)
class Workload:
    key: str
    title: str
    kind: str
    repo: str | None
    container_port: int | None
    k8s_kind: str
    ingress_path: str | None
    image: str | None
    dockerfile_in_repo: bool


WORKLOADS: tuple[Workload, ...] = (
    Workload("aether-ms-auth", "aether-ms-auth", "app", "aether-ms-auth", 8080, "deployment", "/auth", None, True),
    Workload("aether-ms-calculator", "aether-ms-calculator", "app", "aether-ms-calculator", 8080, "deployment", "/calculator", None, True),
    Workload("aether-ms-inventory", "aether-ms-inventory", "app", "aether-ms-inventory", 8080, "deployment", "/inventory", None, True),
    Workload("aether-ms-cloudinary", "aether-ms-cloudinary", "app", "aether-ms-cloudinary", 8080, "deployment", "/cloudinary", None, True),
    Workload("ms-aeko-hub", "ms-aeko-hub", "app", "ms-aeko-hub", 8000, "deployment", "/hub", None, False),
    Workload("aether-rpa", "aether-rpa", "app", "aether-rpa", None, "deployment", None, None, False),
    Workload("aether-web-flow", "aether-web-flow", "app", "aether-web-flow", 80, "deployment", "/", None, False),
    Workload("aether-web-administrative", "aether-web-administrative", "app", "aether-web-administrative", 8080, "deployment", "/admin", None, False),
    Workload("postgres", "Postgres", "database", None, 5432, "statefulset", None, "postgres:16.10", False),
    Workload("mongo", "Mongo", "database", None, 27017, "statefulset", None, "mongo:8.0.13", False),
    Workload("redis", "Redis", "database", None, 6379, "statefulset", None, "redis:8.2", False),
)


def get_workload(key: str) -> Workload:
    for workload in WORKLOADS:
        if workload.key == key:
            return workload
    raise KeyError(key)
```

```python
# aether_env/theme.py
from dataclasses import dataclass


@dataclass(frozen=True)
class Theme:
    cluster_name: str
    slug: str
    accent: str
    text: str
    reset: str


QA = Theme("aether-qa", "qa", "\033[94m", "\033[97m", "\033[0m")
PROD = Theme("aether-prod", "prod", "\033[91m", "\033[97m", "\033[0m")


def theme_for(cluster_name: str) -> Theme:
    if cluster_name == QA.cluster_name:
        return QA
    if cluster_name == PROD.cluster_name:
        return PROD
    raise KeyError(cluster_name)
```

```python
# aether_env/confirm.py
from aether_env.theme import PROD, QA


def required_phrase(cluster_name: str) -> str:
    if cluster_name == QA.cluster_name:
        return "sim"
    if cluster_name == PROD.cluster_name:
        return PROD.cluster_name
    raise KeyError(cluster_name)


def phrase_accepted(cluster_name: str, typed: str) -> bool:
    return typed.strip() == required_phrase(cluster_name)
```

```python
# aether_env/config.py
from collections.abc import Mapping
from dataclasses import dataclass
from urllib.parse import quote


REQUIRED = (
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_REGION",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "POSTGRES_DB_FIRST_YEAR",
    "POSTGRES_DB_SECOND_YEAR",
    "MONGO_USER",
    "MONGO_PASSWORD",
    "MONGO_DB",
    "REDIS_PASSWORD",
    "JWT_SECRET",
)

EXCLUDED_FROM_SECRET = frozenset({
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "AWS_REGION",
    "EKS_NODE_TYPE",
    "EKS_NODE_COUNT",
})


class ConfigError(Exception):
    def __init__(self, missing: tuple[str, ...]) -> None:
        super().__init__(", ".join(missing))
        self.missing = missing


@dataclass(frozen=True)
class Settings:
    aws_access_key_id: str
    aws_secret_access_key: str
    aws_session_token: str | None
    aws_region: str
    node_type: str
    node_count: int
    values: Mapping[str, str]


def load_settings(env: Mapping[str, str]) -> Settings:
    missing = tuple(key for key in REQUIRED if not env.get(key, "").strip())
    if missing:
        raise ConfigError(missing)
    raw_count = env.get("EKS_NODE_COUNT", "").strip() or "2"
    if not raw_count.isdigit() or int(raw_count) < 1:
        raise ConfigError(("EKS_NODE_COUNT",))
    token = env.get("AWS_SESSION_TOKEN", "").strip() or None
    return Settings(
        aws_access_key_id=env["AWS_ACCESS_KEY_ID"].strip(),
        aws_secret_access_key=env["AWS_SECRET_ACCESS_KEY"].strip(),
        aws_session_token=token,
        aws_region=env["AWS_REGION"].strip(),
        node_type=(env.get("EKS_NODE_TYPE", "").strip() or "t3.large"),
        node_count=int(raw_count),
        values={key: value for key, value in env.items()},
    )


def application_secret_data(settings: Settings) -> dict[str, str]:
    data = {
        key: value
        for key, value in settings.values.items()
        if key not in EXCLUDED_FROM_SECRET
    }
    user = quote(data["POSTGRES_USER"], safe="")
    password = quote(data["POSTGRES_PASSWORD"], safe="")
    mongo_user = quote(data["MONGO_USER"], safe="")
    mongo_password = quote(data["MONGO_PASSWORD"], safe="")
    redis_password = quote(data["REDIS_PASSWORD"], safe="")
    mongo_db = data["MONGO_DB"]
    data["POSTGRES_HOST"] = "postgres"
    data["POSTGRES_PORT"] = "5432"
    data["MONGO_HOST"] = "mongo"
    data["MONGO_PORT"] = "27017"
    data["REDIS_HOST"] = "redis"
    data["REDIS_PORT"] = "6379"
    data["API_PORT"] = "8080"
    data["SERVER_PORT"] = "8080"
    data["PORT"] = "8000"
    data["HOST"] = "0.0.0.0"
    data["DB_NAME"] = mongo_db
    data["MONGO_URL"] = (
        f"mongodb://{mongo_user}:{mongo_password}@mongo:27017/{mongo_db}?authSource=admin"
    )
    data["MONGO_URI"] = data["MONGO_URL"]
    data["REDIS_URI"] = f"redis://:{redis_password}@redis:6379/0"
    data["DATABASE_A_URL"] = (
        f"postgresql://{user}:{password}@postgres:5432/{data['POSTGRES_DB_FIRST_YEAR']}"
    )
    data["DATABASE_B_URL"] = (
        f"postgresql://{user}:{password}@postgres:5432/{data['POSTGRES_DB_SECOND_YEAR']}"
    )
    return data
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m pip install -e ".[dev]"`

Run: `python -m pytest tests/test_catalog.py tests/test_config.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add pyproject.toml aether_env/__init__.py aether_env/catalog.py aether_env/theme.py aether_env/confirm.py aether_env/config.py tests/test_catalog.py tests/test_config.py
git commit -m "feat: add environment catalog and settings"
```

---

### Task 2: Menu colorido

**Files:**
- Create: `aether_env/menu.py`
- Test: `tests/test_menu.py`

**Interfaces:**
- Consumes: `WORKLOADS`, `theme_for`, `required_phrase`, `QA`, `PROD`
- Produces:
  - `MenuState(screen, cluster_name=None, workload_key=None, action=None)`
  - `next_state(state: MenuState, choice: str) -> MenuState | None`
  - `render(state: MenuState) -> str`
  - `run_menu(read_line, write, on_run, on_confirm) -> int`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_menu.py
from aether_env.menu import MenuState, next_state, render, run_menu


def test_qa_environment_is_blue_and_white():
    text = render(MenuState("environment", "aether-qa"))
    assert "\033[94m" in text
    assert "\033[97m" in text
    assert "\033[91m" not in text
    assert "Subir ambiente" in text
    assert "Derrubar ambiente" in text


def test_prod_environment_is_red_and_white():
    text = render(MenuState("environment", "aether-prod"))
    assert "\033[91m" in text
    assert "\033[97m" in text
    assert "\033[94m" not in text


def test_navigation_and_actions():
    qa = next_state(MenuState("root"), "1")
    assert qa == MenuState("environment", "aether-qa")
    workloads = next_state(qa, "3")
    assert workloads.screen == "workloads"
    auth = next_state(workloads, "1")
    assert auth.workload_key == "aether-ms-auth"
    update = next_state(auth, "3")
    assert update.action == "update"
    assert next_state(MenuState("root"), "0") is None


def test_run_menu_asks_phrase_before_teardown():
    seen = []
    lines = iter(["2", "2", "nope", "0", "0"])
    writes = []

    def on_confirm(cluster, phrase):
        seen.append((cluster, phrase))
        return 0

    code = run_menu(lambda: next(lines), writes.append, lambda state: 0, on_confirm)
    assert code == 0
    assert seen == [("aether-prod", "nope")]
    assert any("aether-prod" in item for item in writes)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_menu.py -v`

Expected: FAIL with `ModuleNotFoundError: No module named 'aether_env.menu'`

- [ ] **Step 3: Write the implementation**

```python
# aether_env/menu.py
from collections.abc import Callable
from dataclasses import dataclass

from aether_env.catalog import WORKLOADS
from aether_env.confirm import required_phrase
from aether_env.theme import PROD, QA, theme_for


@dataclass(frozen=True)
class MenuState:
    screen: str
    cluster_name: str | None = None
    workload_key: str | None = None
    action: str | None = None


def next_state(state: MenuState, choice: str) -> MenuState | None:
    choice = choice.strip()
    if state.screen == "root":
        if choice == "1":
            return MenuState("environment", QA.cluster_name)
        if choice == "2":
            return MenuState("environment", PROD.cluster_name)
        if choice == "0":
            return None
        return state
    if state.screen == "environment":
        if choice == "1":
            return MenuState("run", state.cluster_name, action="subir-ambiente")
        if choice == "2":
            return MenuState("confirm-teardown", state.cluster_name)
        if choice == "3":
            return MenuState("workloads", state.cluster_name)
        if choice == "0":
            return MenuState("root")
        return state
    if state.screen == "workloads":
        if choice == "0":
            return MenuState("environment", state.cluster_name)
        if choice.isdigit() and 1 <= int(choice) <= len(WORKLOADS):
            workload = WORKLOADS[int(choice) - 1]
            return MenuState("action", state.cluster_name, workload.key)
        return state
    if state.screen == "action":
        actions = {"1": "subir", "2": "derrubar", "3": "update"}
        if choice in actions:
            return MenuState("run", state.cluster_name, state.workload_key, actions[choice])
        if choice == "0":
            return MenuState("workloads", state.cluster_name)
        return state
    return state


def render(state: MenuState) -> str:
    if state.screen == "root":
        return "\n".join([
            f"{QA.text}Aether{QA.reset}",
            f"{QA.accent}1{QA.reset} {QA.text}QA{QA.reset}",
            f"{PROD.accent}2{PROD.reset} {PROD.text}Produção{PROD.reset}",
            f"{QA.text}0 Sair{QA.reset}",
            "",
        ])
    theme = theme_for(state.cluster_name or "")
    if state.screen == "environment":
        lines = [
            f"{theme.accent}{theme.cluster_name}{theme.reset}",
            f"{theme.accent}1{theme.reset} {theme.text}Subir ambiente{theme.reset}",
            f"{theme.accent}2{theme.reset} {theme.text}Derrubar ambiente{theme.reset}",
            f"{theme.accent}3{theme.reset} {theme.text}Escolher carga{theme.reset}",
            f"{theme.text}0 Voltar{theme.reset}",
        ]
    elif state.screen == "workloads":
        lines = [f"{theme.accent}Cargas{theme.reset}"]
        for index, workload in enumerate(WORKLOADS, start=1):
            lines.append(
                f"{theme.accent}{index}{theme.reset} {theme.text}{workload.title}{theme.reset}"
            )
        lines.append(f"{theme.text}0 Voltar{theme.reset}")
    elif state.screen == "confirm-teardown":
        lines = [
            f"{theme.accent}Derrubar {theme.cluster_name} apaga cluster, discos e dados.{theme.reset}",
            f"{theme.text}Digite {required_phrase(theme.cluster_name)}{theme.reset}",
        ]
    else:
        lines = [
            f"{theme.accent}{state.workload_key}{theme.reset}",
            f"{theme.accent}1{theme.reset} {theme.text}Subir{theme.reset}",
            f"{theme.accent}2{theme.reset} {theme.text}Derrubar{theme.reset}",
            f"{theme.accent}3{theme.reset} {theme.text}Update{theme.reset}",
            f"{theme.text}0 Voltar{theme.reset}",
        ]
    return "\n".join(lines) + "\n"


def run_menu(read_line: Callable[[], str], write: Callable[[str], None], on_run: Callable[[MenuState], int], on_confirm: Callable[[str, str], int]) -> int:
    state: MenuState | None = MenuState("root")
    while state is not None:
        if state.screen == "run":
            on_run(state)
            if state.workload_key:
                state = MenuState("action", state.cluster_name, state.workload_key)
            else:
                state = MenuState("environment", state.cluster_name)
            continue
        write(render(state))
        choice = read_line()
        if state.screen == "confirm-teardown":
            on_confirm(state.cluster_name or "", choice)
            state = MenuState("environment", state.cluster_name)
            continue
        state = next_state(state, choice)
    return 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_menu.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add aether_env/menu.py tests/test_menu.py
git commit -m "feat: add colored QA and production menus"
```

---

### Task 3: Runner e pré-checagem

**Files:**
- Create: `aether_env/runner.py`
- Create: `aether_env/preflight.py`
- Test: `tests/test_preflight.py`

**Interfaces:**
- Consumes: nada do pacote além da biblioteca padrão
- Produces:
  - `CommandResult(args, returncode, stdout, stderr)`
  - `SubprocessRunner.run(args, *, env=None, cwd=None, stdin=None, stream=False) -> CommandResult`
  - `REQUIRED_TOOLS`
  - `missing_tools(lookup) -> tuple[str, ...]`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_preflight.py
from aether_env.preflight import missing_tools
from aether_env.runner import CommandResult


def test_missing_tools_reports_absent_names():
    found = {"aws": "aws", "git": "git"}
    assert missing_tools(lambda name: found.get(name)) == ("eksctl", "kubectl", "docker")


def test_command_result_keeps_args():
    result = CommandResult(("aws", "sts"), 0, "123", "")
    assert result.stdout == "123"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_preflight.py -v`

Expected: FAIL with `No module named 'aether_env.preflight'`

- [ ] **Step 3: Write the implementation**

```python
# aether_env/runner.py
import subprocess
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CommandResult:
    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


class SubprocessRunner:
    def run(
        self,
        args: Sequence[str],
        *,
        env: Mapping[str, str] | None = None,
        cwd: Path | None = None,
        stdin: str | None = None,
        stream: bool = False,
    ) -> CommandResult:
        completed = subprocess.run(
            list(args),
            env=None if env is None else dict(env),
            cwd=cwd,
            input=stdin,
            text=True,
            capture_output=not stream,
        )
        return CommandResult(
            tuple(args),
            completed.returncode,
            "" if stream else completed.stdout,
            "" if stream else completed.stderr,
        )
```

```python
# aether_env/preflight.py
import shutil
from collections.abc import Callable


REQUIRED_TOOLS = ("aws", "eksctl", "kubectl", "docker", "git")


def missing_tools(lookup: Callable[[str], str | None] = shutil.which) -> tuple[str, ...]:
    return tuple(name for name in REQUIRED_TOOLS if lookup(name) is None)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_preflight.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add aether_env/runner.py aether_env/preflight.py tests/test_preflight.py
git commit -m "feat: add command runner and CLI preflight"
```

---

### Task 4: Argumentos AWS e EKS

**Files:**
- Create: `aether_env/awscli.py`
- Test: `tests/test_awscli.py`

**Interfaces:**
- Consumes: `Settings`
- Produces: `describe_cluster_args`, `create_cluster_args`, `delete_cluster_args`, `kubeconfig_args`, `caller_identity_args`, `describe_ecr_args`, `create_ecr_args`, `delete_ecr_args`, `ecr_password_args`, `docker_login_args`, `ecr_repository`, `image_uri`, `aws_process_env`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_awscli.py
from aether_env.awscli import (
    aws_process_env,
    create_cluster_args,
    delete_ecr_args,
    ecr_repository,
    image_uri,
)
from aether_env.config import load_settings


def test_create_cluster_uses_managed_nodegroup():
    args = create_cluster_args("sa-east-1", "aether-qa", "t3.large", 2)
    assert args[:4] == ["eksctl", "create", "cluster", "--name"]
    assert "aether-qa" in args
    assert "--managed" in args
    assert args[args.index("--nodes") + 1] == "2"


def test_ecr_names_and_env_do_not_keep_a_stale_session_token():
    assert ecr_repository("qa", "aether-ms-auth") == "aether/qa/aether-ms-auth"
    assert image_uri("123", "sa-east-1", "aether/qa/aether-ms-auth", "main").endswith(":main")
    settings = load_settings({
        "AWS_ACCESS_KEY_ID": "aki",
        "AWS_SECRET_ACCESS_KEY": "secret",
        "AWS_REGION": "sa-east-1",
        "POSTGRES_USER": "sa",
        "POSTGRES_PASSWORD": "pw",
        "POSTGRES_DB_FIRST_YEAR": "a",
        "POSTGRES_DB_SECOND_YEAR": "b",
        "MONGO_USER": "mongo",
        "MONGO_PASSWORD": "mp",
        "MONGO_DB": "db",
        "REDIS_PASSWORD": "rp",
        "JWT_SECRET": "jwt",
    })
    env = aws_process_env(settings, {"AWS_SESSION_TOKEN": "old", "PATH": "/usr/bin"})
    assert "AWS_SESSION_TOKEN" not in env
    assert env["AWS_REGION"] == "sa-east-1"
    delete = delete_ecr_args("sa-east-1", "aether/qa/aether-ms-auth")
    assert "--force" in delete
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_awscli.py -v`

Expected: FAIL with `No module named 'aether_env.awscli'`

- [ ] **Step 3: Write the implementation**

```python
# aether_env/awscli.py
from collections.abc import Mapping

from aether_env.config import Settings


def describe_cluster_args(region: str, cluster_name: str) -> list[str]:
    return [
        "aws", "eks", "describe-cluster",
        "--name", cluster_name,
        "--region", region,
        "--query", "cluster.status",
        "--output", "text",
    ]


def create_cluster_args(region: str, cluster_name: str, node_type: str, node_count: int) -> list[str]:
    return [
        "eksctl", "create", "cluster",
        "--name", cluster_name,
        "--region", region,
        "--nodegroup-name", "ng",
        "--node-type", node_type,
        "--nodes", str(node_count),
        "--managed",
    ]


def delete_cluster_args(region: str, cluster_name: str) -> list[str]:
    return ["eksctl", "delete", "cluster", "--name", cluster_name, "--region", region, "--wait"]


def kubeconfig_args(region: str, cluster_name: str, kubeconfig: str) -> list[str]:
    return [
        "aws", "eks", "update-kubeconfig",
        "--name", cluster_name,
        "--region", region,
        "--kubeconfig", kubeconfig,
    ]


def caller_identity_args() -> list[str]:
    return ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"]


def describe_ecr_args(region: str, repository: str) -> list[str]:
    return ["aws", "ecr", "describe-repositories", "--repository-names", repository, "--region", region]


def create_ecr_args(region: str, repository: str) -> list[str]:
    return ["aws", "ecr", "create-repository", "--repository-name", repository, "--region", region]


def delete_ecr_args(region: str, repository: str) -> list[str]:
    return ["aws", "ecr", "delete-repository", "--repository-name", repository, "--region", region, "--force"]


def ecr_password_args(region: str) -> list[str]:
    return ["aws", "ecr", "get-login-password", "--region", region]


def docker_login_args(registry: str) -> list[str]:
    return ["docker", "login", "--username", "AWS", "--password-stdin", registry]


def ecr_repository(slug: str, workload_key: str) -> str:
    return f"aether/{slug}/{workload_key}"


def image_uri(account: str, region: str, repository: str, tag: str) -> str:
    return f"{account}.dkr.ecr.{region}.amazonaws.com/{repository}:{tag}"


def aws_process_env(settings: Settings, base: Mapping[str, str]) -> dict[str, str]:
    env = dict(base)
    env.pop("AWS_SESSION_TOKEN", None)
    env["AWS_ACCESS_KEY_ID"] = settings.aws_access_key_id
    env["AWS_SECRET_ACCESS_KEY"] = settings.aws_secret_access_key
    env["AWS_REGION"] = settings.aws_region
    env["AWS_DEFAULT_REGION"] = settings.aws_region
    if settings.aws_session_token:
        env["AWS_SESSION_TOKEN"] = settings.aws_session_token
    return env
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_awscli.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add aether_env/awscli.py tests/test_awscli.py
git commit -m "feat: add EKS and ECR command builders"
```

---

### Task 5: Build de imagem

**Files:**
- Create: `aether_env/images.py`
- Test: `tests/test_images.py`

**Interfaces:**
- Consumes: `Workload`, `Path`
- Produces: `sync_main_commands(repo, dest, dest_exists) -> list[list[str]]`, `rev_parse_args(dest) -> list[str]`, `docker_build_args(dockerfile, context, tags, build_args) -> list[str]`, `docker_push_args(tag) -> list[str]`, `dockerfile_for(root, workload, clone) -> Path`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_images.py
from pathlib import Path

from aether_env.catalog import get_workload
from aether_env.images import docker_build_args, dockerfile_for, sync_main_commands


def test_sync_clones_main_or_fetches_it():
    clone = sync_main_commands("aether-ms-auth", "C:/src", False)
    assert clone[0][:4] == ["git", "clone", "--branch", "main"]
    update = sync_main_commands("aether-ms-auth", "C:/src", True)
    assert update[0][:5] == ["git", "-C", "C:/src", "fetch", "--depth"]
    assert update[1][-1] == "FETCH_HEAD"


def test_toolkit_dockerfile_and_build_args():
    workload = get_workload("aether-web-flow")
    path = dockerfile_for(Path("C:/kit"), workload, Path("C:/src"))
    assert path == Path("C:/kit/dockerfiles/aether-web-flow/Dockerfile")
    args = docker_build_args(str(path), "C:/src", ["img:main"], {"API_URL": "http://lb"})
    assert "--build-arg" in args
    assert "API_URL=http://lb" in args
    assert args[-1] == "C:/src"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_images.py -v`

Expected: FAIL with `No module named 'aether_env.images'`

- [ ] **Step 3: Write the implementation**

```python
# aether_env/images.py
from collections.abc import Mapping
from pathlib import Path

from aether_env.catalog import Workload


def sync_main_commands(repo: str, dest: str, dest_exists: bool) -> list[list[str]]:
    if not dest_exists:
        return [[
            "git", "clone", "--branch", "main", "--single-branch",
            f"https://github.com/AetherGases/{repo}.git", dest,
        ]]
    return [
        ["git", "-C", dest, "fetch", "--depth", "1", "origin", "main"],
        ["git", "-C", dest, "checkout", "-B", "main", "FETCH_HEAD"],
    ]


def rev_parse_args(dest: str) -> list[str]:
    return ["git", "-C", dest, "rev-parse", "HEAD"]


def docker_build_args(dockerfile: str, context: str, tags: list[str], build_args: Mapping[str, str]) -> list[str]:
    command = ["docker", "build", "-f", dockerfile]
    for key, value in build_args.items():
        command.extend(["--build-arg", f"{key}={value}"])
    for tag in tags:
        command.extend(["-t", tag])
    command.append(context)
    return command


def docker_push_args(tag: str) -> list[str]:
    return ["docker", "push", tag]


def dockerfile_for(root: Path, workload: Workload, clone: Path) -> Path:
    if workload.dockerfile_in_repo:
        return clone / "Dockerfile"
    return root / "dockerfiles" / workload.key / "Dockerfile"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_images.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add aether_env/images.py tests/test_images.py
git commit -m "feat: add main-branch image build commands"
```

---

### Task 6: Argumentos kubectl

**Files:**
- Create: `aether_env/kube.py`
- Test: `tests/test_kube.py`

**Interfaces:**
- Consumes: nada de AWS
- Produces: `apply_stdin_args`, `apply_url_args`, `scale_args`, `set_image_args`, `rollout_status_args`, `rollout_restart_args`, `get_pods_args`, `ingress_hostname_args`, `ingress_ip_args`
- Constante: `INGRESS_NGINX_URL = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/aws/deploy.yaml"`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_kube.py
from aether_env.kube import INGRESS_NGINX_URL, rollout_restart_args, scale_args, set_image_args


def test_scale_and_image_and_ingress_pin():
    assert scale_args("C:/kube", "statefulset", "postgres", 0)[-2:] == ["statefulset/postgres", "--replicas=0"]
    assert "deployment/aether-ms-auth" in set_image_args("C:/kube", "aether-ms-auth", "img:main")
    assert rollout_restart_args("C:/kube", "redis")[-1] == "statefulset/redis"
    assert INGRESS_NGINX_URL.endswith("controller-v1.11.3/deploy/static/provider/aws/deploy.yaml")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_kube.py -v`

Expected: FAIL with `No module named 'aether_env.kube'`

- [ ] **Step 3: Write the implementation**

```python
# aether_env/kube.py
INGRESS_NGINX_URL = (
    "https://raw.githubusercontent.com/kubernetes/ingress-nginx/"
    "controller-v1.11.3/deploy/static/provider/aws/deploy.yaml"
)


def _base(kubeconfig: str) -> list[str]:
    return ["kubectl", "--kubeconfig", kubeconfig]


def apply_stdin_args(kubeconfig: str) -> list[str]:
    return _base(kubeconfig) + ["apply", "-f", "-"]


def apply_url_args(kubeconfig: str, url: str) -> list[str]:
    return _base(kubeconfig) + ["apply", "-f", url]


def scale_args(kubeconfig: str, k8s_kind: str, name: str, replicas: int) -> list[str]:
    return _base(kubeconfig) + ["-n", "aether", "scale", f"{k8s_kind}/{name}", f"--replicas={replicas}"]


def set_image_args(kubeconfig: str, name: str, image: str) -> list[str]:
    return _base(kubeconfig) + [
        "-n", "aether", "set", "image", f"deployment/{name}", f"{name}={image}",
    ]


def rollout_status_args(kubeconfig: str, k8s_kind: str, name: str) -> list[str]:
    return _base(kubeconfig) + [
        "-n", "aether", "rollout", "status", f"{k8s_kind}/{name}", "--timeout=180s",
    ]


def rollout_restart_args(kubeconfig: str, name: str) -> list[str]:
    return _base(kubeconfig) + ["-n", "aether", "rollout", "restart", f"statefulset/{name}"]


def get_pods_args(kubeconfig: str) -> list[str]:
    return _base(kubeconfig) + ["-n", "aether", "get", "pods"]


def ingress_hostname_args(kubeconfig: str) -> list[str]:
    return _base(kubeconfig) + [
        "-n", "ingress-nginx", "get", "svc", "ingress-nginx-controller",
        "-o", "jsonpath={.status.loadBalancer.ingress[0].hostname}",
    ]


def ingress_ip_args(kubeconfig: str) -> list[str]:
    return _base(kubeconfig) + [
        "-n", "ingress-nginx", "get", "svc", "ingress-nginx-controller",
        "-o", "jsonpath={.status.loadBalancer.ingress[0].ip}",
    ]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_kube.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add aether_env/kube.py tests/test_kube.py
git commit -m "feat: add kubectl command builders"
```

---

### Task 7: Manifestos

**Files:**
- Create: `aether_env/manifests.py`
- Test: `tests/test_manifests.py`

**Interfaces:**
- Consumes: `Workload`, `application_secret_data`
- Produces: `render_namespace() -> str`, `render_secret(data) -> str`, `render_configmap(name, files) -> str`, `render_database(workload) -> str`, `render_app(workload, image) -> str`, `render_ingress(workloads) -> str`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_manifests.py
from aether_env.catalog import WORKLOADS, get_workload
from aether_env.manifests import render_app, render_database, render_ingress, render_secret


def test_secret_quotes_password_and_hides_aws_key():
    text = render_secret({"POSTGRES_PASSWORD": "p:ss", "AWS_SECRET_ACCESS_KEY": "nope"})
    assert "stringData:" in text
    assert '"p:ss"' in text


def test_databases_use_pinned_images_and_apps_use_the_given_image():
    assert "postgres:16.10" in render_database(get_workload("postgres"))
    assert "mongo:8.0.13" in render_database(get_workload("mongo"))
    redis = render_database(get_workload("redis"))
    assert "redis:8.2" in redis
    assert "requirepass" in redis
    app = render_app(get_workload("aether-ms-auth"), "123.dkr.ecr.sa-east-1.amazonaws.com/aether/qa/aether-ms-auth:main")
    assert "containerPort: 8080" in app
    ingress = render_ingress([item for item in WORKLOADS if item.ingress_path])
    assert "rewrite-target: /$2" in ingress
    assert "path: /" in ingress
    assert "aether-web-flow" in ingress
    assert "aether-rpa" not in ingress
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_manifests.py -v`

Expected: FAIL with `No module named 'aether_env.manifests'`

- [ ] **Step 3: Write the implementation**

```python
# aether_env/manifests.py
import json
from collections.abc import Mapping, Sequence

from aether_env.catalog import Workload


def render_namespace() -> str:
    return "apiVersion: v1\nkind: Namespace\nmetadata:\n  name: aether\n"


def render_secret(data: Mapping[str, str]) -> str:
    lines = [
        "apiVersion: v1",
        "kind: Secret",
        "metadata:",
        "  name: aether-env",
        "  namespace: aether",
        "stringData:",
    ]
    for key, value in data.items():
        lines.append(f"  {key}: {json.dumps(value, ensure_ascii=False)}")
    return "\n".join(lines) + "\n"


def render_configmap(name: str, files: Mapping[str, str]) -> str:
    lines = [
        "apiVersion: v1",
        "kind: ConfigMap",
        "metadata:",
        f"  name: {name}",
        "  namespace: aether",
        "data:",
    ]
    for filename, content in files.items():
        lines.append(f"  {filename}: |")
        for line in content.replace("\r\n", "\n").split("\n"):
            lines.append(f"    {line}")
    return "\n".join(lines) + "\n"


def _service(name: str, port: int) -> str:
    return f"""apiVersion: v1
kind: Service
metadata:
  name: {name}
  namespace: aether
spec:
  selector:
    app: {name}
  ports:
    - port: {port}
      targetPort: {port}
"""


def _probe(port: int) -> str:
    return f"""          readinessProbe:
            tcpSocket:
              port: {port}
            initialDelaySeconds: 5
            periodSeconds: 5
"""


def render_database(workload: Workload) -> str:
    if workload.key == "postgres":
        container = """        - name: postgres
          image: postgres:16.10
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: POSTGRES_PASSWORD
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: POSTGRES_DB_SECOND_YEAR
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
            - name: init
              mountPath: /docker-entrypoint-initdb.d
""" + _probe(5432)
        extra_volume = """      volumes:
        - name: init
          configMap:
            name: postgres-init
"""
    elif workload.key == "mongo":
        container = """        - name: mongo
          image: mongo:8.0.13
          ports:
            - containerPort: 27017
          env:
            - name: MONGO_INITDB_ROOT_USERNAME
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: MONGO_USER
            - name: MONGO_INITDB_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: MONGO_PASSWORD
            - name: MONGO_INITDB_DATABASE
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: MONGO_DB
          volumeMounts:
            - name: data
              mountPath: /data/db
            - name: init
              mountPath: /docker-entrypoint-initdb.d
""" + _probe(27017)
        extra_volume = """      volumes:
        - name: init
          configMap:
            name: mongo-init
"""
    else:
        container = """        - name: redis
          image: redis:8.2
          command: ["sh", "-c", "redis-server --requirepass \\"$REDIS_PASSWORD\\" --appendonly yes"]
          ports:
            - containerPort: 6379
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: REDIS_PASSWORD
          volumeMounts:
            - name: data
              mountPath: /data
""" + _probe(6379)
        extra_volume = ""
    body = f"""apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {workload.key}
  namespace: aether
spec:
  serviceName: {workload.key}
  replicas: 1
  selector:
    matchLabels:
      app: {workload.key}
  template:
    metadata:
      labels:
        app: {workload.key}
    spec:
      containers:
{container}{extra_volume}  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
---
{_service(workload.key, workload.container_port or 0)}"""
    return body


def render_app(workload: Workload, image: str) -> str:
    ports = ""
    probe = ""
    if workload.container_port:
        ports = f"""          ports:
            - containerPort: {workload.container_port}
"""
        probe = _probe(workload.container_port)
    body = f"""apiVersion: apps/v1
kind: Deployment
metadata:
  name: {workload.key}
  namespace: aether
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {workload.key}
  template:
    metadata:
      labels:
        app: {workload.key}
    spec:
      containers:
        - name: {workload.key}
          image: {image}
{ports}          envFrom:
            - secretRef:
                name: aether-env
{probe}---
"""
    if workload.container_port:
        body += _service(workload.key, workload.container_port)
    return body


def render_ingress(workloads: Sequence[Workload]) -> str:
    prefixed = []
    root = ""
    for workload in workloads:
        if workload.ingress_path == "/":
            root = f"""apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aether-web
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
                name: {workload.key}
                port:
                  number: {workload.container_port}
"""
            continue
        prefixed.append(f"""          - path: {workload.ingress_path}(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: {workload.key}
                port:
                  number: {workload.container_port}
""")
    apis = """apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aether-apis
  namespace: aether
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
""" + "".join(prefixed)
    return apis + "---\n" + root
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_manifests.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add aether_env/manifests.py tests/test_manifests.py
git commit -m "feat: render Kubernetes manifests from the catalog"
```

---

### Task 8: Dockerfiles que os repositórios não têm

**Files:**
- Create: `dockerfiles/ms-aeko-hub/Dockerfile`
- Create: `dockerfiles/aether-rpa/Dockerfile`
- Create: `dockerfiles/aether-web-flow/Dockerfile`
- Create: `dockerfiles/aether-web-administrative/Dockerfile`
- Test: `tests/test_dockerfiles.py`

**Interfaces:**
- Consumes: os caminhos de `dockerfile_for` para cargas com `dockerfile_in_repo is False` e `kind == "app"`
- Produces: quatro Dockerfiles no disco

- [ ] **Step 1: Write the failing test**

```python
# tests/test_dockerfiles.py
from pathlib import Path

from aether_env.catalog import WORKLOADS
from aether_env.images import dockerfile_for


ROOT = Path(__file__).resolve().parents[1]


def test_toolkit_dockerfiles_exist_and_name_the_process():
    expected = {
        "ms-aeko-hub": "uvicorn",
        "aether-rpa": "src.worker",
        "aether-web-flow": "API_URL",
        "aether-web-administrative": "catalina.sh",
    }
    for workload in WORKLOADS:
        if workload.kind != "app" or workload.dockerfile_in_repo:
            continue
        path = dockerfile_for(ROOT, workload, ROOT / "unused")
        text = path.read_text(encoding="utf-8")
        assert expected[workload.key] in text
        if workload.key != "aether-web-flow":
            assert "/app/.env" in text
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_dockerfiles.py -v`

Expected: FAIL with `FileNotFoundError`

- [ ] **Step 3: Write the Dockerfiles**

```dockerfile
# dockerfiles/ms-aeko-hub/Dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
ENTRYPOINT ["sh", "-c", "env > /app/.env && exec \"$@\"", "sh"]
CMD ["uvicorn", "cmd.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

```dockerfile
# dockerfiles/aether-rpa/Dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENTRYPOINT ["sh", "-c", "env > /app/.env && exec \"$@\"", "sh"]
CMD ["python", "-m", "src.worker"]
```

```dockerfile
# dockerfiles/aether-web-flow/Dockerfile
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG API_URL=
ENV API_URL=$API_URL
ENV VITE_API_URL=$API_URL
RUN npm run build
FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
```

```dockerfile
# dockerfiles/aether-web-administrative/Dockerfile
FROM eclipse-temurin:25-jdk
WORKDIR /src
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates tar \
    && rm -rf /var/lib/apt/lists/*
COPY . .
RUN chmod +x mvnw && ./mvnw -q -DskipTests package \
    && curl -fsSL "https://archive.apache.org/dist/tomcat/tomcat-11/v11.0.10/bin/apache-tomcat-11.0.10.tar.gz" \
      | tar -xz -C /opt \
    && mv /opt/apache-tomcat-11.0.10 /opt/tomcat \
    && rm -rf /opt/tomcat/webapps/* \
    && cp target/*.war /opt/tomcat/webapps/ROOT.war
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "env > /app/.env && exec /opt/tomcat/bin/catalina.sh run"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_dockerfiles.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add dockerfiles tests/test_dockerfiles.py
git commit -m "feat: add Dockerfiles for repos that do not ship one"
```

---

### Task 9: Orquestração

**Files:**
- Create: `aether_env/actions.py`
- Test: `tests/test_actions.py`

**Interfaces:**
- Consumes: todas as funções das tasks 1 a 8, `CommandResult`
- Produces: `Actions(settings, runner, root, write)` com `subir_ambiente(cluster_name) -> int`, `derrubar_ambiente(cluster_name, typed) -> int`, `subir_workload(cluster_name, key) -> int`, `derrubar_workload(cluster_name, key) -> int`, `update_workload(cluster_name, key) -> int`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_actions.py
from pathlib import Path

from aether_env.actions import Actions
from aether_env.config import load_settings
from aether_env.runner import CommandResult


class FakeRunner:
    def __init__(self, describe_code=0, describe_stdout="ACTIVE\n", hostname="lb.example.com"):
        self.calls = []
        self.describe_code = describe_code
        self.describe_stdout = describe_stdout
        self.hostname = hostname

    def run(self, args, *, env=None, cwd=None, stdin=None, stream=False):
        tup = tuple(args)
        self.calls.append(tup)
        stdout = ""
        code = 0
        if tup[:3] == ("aws", "eks", "describe-cluster"):
            return CommandResult(tup, self.describe_code, self.describe_stdout, "")
        if tup[:3] == ("aws", "sts", "get-caller-identity"):
            stdout = "123456789012\n"
        elif "rev-parse" in tup:
            stdout = "abc123\n"
        elif tup[:4] == ("aws", "ecr", "get-login-password"):
            stdout = "token\n"
        elif tup[-1].endswith("hostname}"):
            stdout = self.hostname
        return CommandResult(tup, code, stdout, "")


def _settings():
    return load_settings({
        "AWS_ACCESS_KEY_ID": "aki",
        "AWS_SECRET_ACCESS_KEY": "secret",
        "AWS_REGION": "sa-east-1",
        "POSTGRES_USER": "sa",
        "POSTGRES_PASSWORD": "pw",
        "POSTGRES_DB_FIRST_YEAR": "dbAether1Year",
        "POSTGRES_DB_SECOND_YEAR": "dbAether2Year",
        "MONGO_USER": "mongo",
        "MONGO_PASSWORD": "mp",
        "MONGO_DB": "dbAether",
        "REDIS_PASSWORD": "rp",
        "JWT_SECRET": "jwt",
    })


def test_wrong_phrase_does_not_delete():
    runner = FakeRunner()
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.derrubar_ambiente("aether-prod", "sim") == 1
    assert all("delete" not in call for call in runner.calls)


def test_stopped_environment_refuses_item_action():
    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="")
    actions = Actions(_settings(), runner, Path("."), messages.append)
    assert actions.subir_workload("aether-qa", "postgres") == 1
    assert messages == ["Ambiente desligado. Suba o ambiente antes."]
    assert all("scale" not in call for call in runner.calls)


def test_database_update_restarts_and_skips_docker():
    runner = FakeRunner()
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.update_workload("aether-qa", "postgres") == 0
    flat = [" ".join(call) for call in runner.calls]
    assert any(item.startswith("kubectl") and "rollout restart statefulset/postgres" in item for item in flat)
    assert all(not item.startswith("docker build") for item in flat)


def test_missing_cluster_starts_eksctl():
    root = Path(__file__).resolve().parents[1]
    runner = FakeRunner(describe_code=254, describe_stdout="")
    actions = Actions(_settings(), runner, root, lambda message: None)
    actions.subir_ambiente("aether-qa")
    assert any(call[:3] == ("eksctl", "create", "cluster") for call in runner.calls)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_actions.py -v`

Expected: FAIL with `No module named 'aether_env.actions'`

- [ ] **Step 3: Write the implementation**

```python
# aether_env/actions.py
import os
import time
from pathlib import Path

from aether_env.awscli import (
    aws_process_env,
    caller_identity_args,
    create_cluster_args,
    create_ecr_args,
    delete_cluster_args,
    delete_ecr_args,
    describe_cluster_args,
    describe_ecr_args,
    docker_login_args,
    ecr_password_args,
    ecr_repository,
    image_uri,
    kubeconfig_args,
)
from aether_env.catalog import WORKLOADS, get_workload
from aether_env.config import Settings, application_secret_data
from aether_env.confirm import phrase_accepted
from aether_env.images import docker_build_args, docker_push_args, dockerfile_for, rev_parse_args, sync_main_commands
from aether_env.kube import (
    INGRESS_NGINX_URL,
    apply_stdin_args,
    apply_url_args,
    get_pods_args,
    ingress_hostname_args,
    ingress_ip_args,
    rollout_restart_args,
    rollout_status_args,
    scale_args,
    set_image_args,
)
from aether_env.manifests import (
    render_app,
    render_configmap,
    render_database,
    render_ingress,
    render_namespace,
    render_secret,
)
from aether_env.theme import theme_for


class Actions:
    def __init__(self, settings: Settings, runner, root: Path, write) -> None:
        self.settings = settings
        self.runner = runner
        self.root = root
        self.write = write

    def subir_ambiente(self, cluster_name: str) -> int:
        status = self._status(cluster_name)
        if status is None:
            created = self._run(create_cluster_args(
                self.settings.aws_region,
                cluster_name,
                self.settings.node_type,
                self.settings.node_count,
            ), stream=True)
            if created.returncode != 0:
                self.write("Falha ao criar o cluster.")
                return 1
        elif status != "ACTIVE":
            self.write(f"Cluster em status {status}.")
            return 1
        else:
            self.write("Cluster já existe. Publicando cargas.")
        kubeconfig = self._kubeconfig(cluster_name)
        kubeconfig.parent.mkdir(parents=True, exist_ok=True)
        if self._run(kubeconfig_args(self.settings.aws_region, cluster_name, str(kubeconfig))).returncode != 0:
            return 1
        account = self._account()
        if account is None:
            return 1
        if self._login(account) != 0:
            return 1
        failures = []
        slug = theme_for(cluster_name).slug
        for workload in WORKLOADS:
            if workload.kind == "app" and workload.key != "aether-web-flow":
                if self._publish_image(cluster_name, workload, account, "") != 0:
                    failures.append(workload.key)
        self._apply(kubeconfig, render_namespace())
        self._apply(kubeconfig, render_secret(application_secret_data(self.settings)))
        self._apply(kubeconfig, render_configmap("postgres-init", self._read_dir(self.root / "init-postgres")))
        mongo = (self.root / "init-mongo" / "init.js").read_text(encoding="utf-8")
        self._apply(kubeconfig, render_configmap("mongo-init", {"init.js": mongo}))
        for workload in WORKLOADS:
            if workload.kind == "database":
                self._apply(kubeconfig, render_database(workload))
            elif workload.kind == "app" and workload.key != "aether-web-flow" and workload.key not in failures:
                image = self._image(account, slug, workload.key, "main")
                self._apply(kubeconfig, render_app(workload, image))
        if self._run(apply_url_args(str(kubeconfig), INGRESS_NGINX_URL)).returncode != 0:
            failures.append("ingress-nginx")
        self._apply(kubeconfig, render_ingress([item for item in WORKLOADS if item.ingress_path]))
        address = self._wait_address(kubeconfig)
        if address:
            api_url = f"http://{address}"
        else:
            api_url = ""
            self.write("Balanceador sem hostname. aether-web-flow seguirá com API_URL vazio.")
        web = get_workload("aether-web-flow")
        if self._publish_image(cluster_name, web, account, api_url) != 0:
            failures.append(web.key)
        else:
            self._apply(kubeconfig, render_app(web, self._image(account, slug, web.key, "main")))
        pods = self._run(get_pods_args(str(kubeconfig)))
        self.write(pods.stdout)
        if address:
            for workload in WORKLOADS:
                if workload.ingress_path:
                    self.write(f"{api_url}{'' if workload.ingress_path == '/' else workload.ingress_path}")
        if failures:
            self.write("Falha ao construir " + ", ".join(failures) + ".")
            return 1
        return 0

    def derrubar_ambiente(self, cluster_name: str, typed: str) -> int:
        if not phrase_accepted(cluster_name, typed):
            self.write("Confirmação recusada.")
            return 1
        slug = theme_for(cluster_name).slug
        status = self._status(cluster_name)
        if status is not None:
            deleted = self._run(delete_cluster_args(self.settings.aws_region, cluster_name), stream=True)
            if deleted.returncode != 0:
                self.write("Falha ao apagar o cluster.")
                return 1
        else:
            self.write("Cluster já estava ausente.")
        for workload in WORKLOADS:
            if workload.kind == "app":
                repository = ecr_repository(slug, workload.key)
                self._run(delete_ecr_args(self.settings.aws_region, repository))
        kubeconfig = self._kubeconfig(cluster_name)
        if kubeconfig.exists():
            kubeconfig.unlink()
        return 0

    def subir_workload(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        workload = get_workload(key)
        kubeconfig = self._kubeconfig(cluster_name)
        if workload.kind == "app":
            account = self._account()
            if account is None or self._login(account) != 0:
                return 1
            api_url = ""
            if workload.key == "aether-web-flow":
                address = self._wait_address(kubeconfig)
                api_url = f"http://{address}" if address else ""
            if self._publish_image(cluster_name, workload, account, api_url) != 0:
                self.write(f"Falha ao construir {key}.")
                return 1
            image = self._image(account, theme_for(cluster_name).slug, key, "main")
            if self._apply(kubeconfig, render_app(workload, image)).returncode != 0:
                return 1
        else:
            if self._apply(kubeconfig, render_database(workload)).returncode != 0:
                return 1
        scaled = self._run(scale_args(str(kubeconfig), workload.k8s_kind, key, 1))
        return scaled.returncode

    def derrubar_workload(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        workload = get_workload(key)
        result = self._run(scale_args(str(self._kubeconfig(cluster_name)), workload.k8s_kind, key, 0))
        return result.returncode

    def update_workload(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        workload = get_workload(key)
        kubeconfig = str(self._kubeconfig(cluster_name))
        if workload.kind == "database":
            restarted = self._run(rollout_restart_args(kubeconfig, key))
            if restarted.returncode != 0:
                return restarted.returncode
            return self._run(rollout_status_args(kubeconfig, "statefulset", key)).returncode
        account = self._account()
        if account is None or self._login(account) != 0:
            return 1
        api_url = ""
        if workload.key == "aether-web-flow":
            address = self._wait_address(self._kubeconfig(cluster_name))
            api_url = f"http://{address}" if address else ""
        if self._publish_image(cluster_name, workload, account, api_url) != 0:
            self.write(f"Falha ao construir {key}.")
            return 1
        image = self._image(account, theme_for(cluster_name).slug, key, "main")
        updated = self._run(set_image_args(kubeconfig, key, image))
        if updated.returncode != 0:
            return updated.returncode
        return self._run(rollout_status_args(kubeconfig, "deployment", key)).returncode

    def _require_active(self, cluster_name: str) -> bool:
        if self._status(cluster_name) == "ACTIVE":
            return True
        self.write("Ambiente desligado. Suba o ambiente antes.")
        return False

    def _status(self, cluster_name: str) -> str | None:
        result = self._run(describe_cluster_args(self.settings.aws_region, cluster_name))
        if result.returncode != 0:
            return None
        return result.stdout.strip()

    def _account(self) -> str | None:
        result = self._run(caller_identity_args())
        if result.returncode != 0:
            return None
        return result.stdout.strip()

    def _login(self, account: str) -> int:
        password = self._run(ecr_password_args(self.settings.aws_region))
        if password.returncode != 0:
            return password.returncode
        registry = f"{account}.dkr.ecr.{self.settings.aws_region}.amazonaws.com"
        return self._run(docker_login_args(registry), stdin=password.stdout.strip()).returncode

    def _publish_image(self, cluster_name: str, workload, account: str, api_url: str) -> int:
        repository = ecr_repository(theme_for(cluster_name).slug, workload.key)
        described = self._run(describe_ecr_args(self.settings.aws_region, repository))
        if described.returncode != 0:
            created = self._run(create_ecr_args(self.settings.aws_region, repository))
            if created.returncode != 0:
                return created.returncode
        dest = self.root / "resources" / "build" / cluster_name / workload.repo
        for command in sync_main_commands(workload.repo, str(dest), dest.exists()):
            if self._run(command).returncode != 0:
                return 1
        sha = self._run(rev_parse_args(str(dest))).stdout.strip()
        tags = [
            self._image(account, theme_for(cluster_name).slug, workload.key, f"main-{sha}"),
            self._image(account, theme_for(cluster_name).slug, workload.key, "main"),
        ]
        dockerfile = dockerfile_for(self.root, workload, dest)
        build_args = {"API_URL": api_url} if workload.key == "aether-web-flow" else {}
        built = self._run(docker_build_args(str(dockerfile), str(dest), tags, build_args), stream=True)
        if built.returncode != 0:
            return built.returncode
        for tag in tags:
            if self._run(docker_push_args(tag), stream=True).returncode != 0:
                return 1
        return 0

    def _image(self, account: str, slug: str, key: str, tag: str) -> str:
        return image_uri(account, self.settings.aws_region, ecr_repository(slug, key), tag)

    def _apply(self, kubeconfig: Path, manifest: str):
        return self._run(apply_stdin_args(str(kubeconfig)), stdin=manifest)

    def _wait_address(self, kubeconfig: Path) -> str:
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            host = self._run(ingress_hostname_args(str(kubeconfig))).stdout.strip()
            if host:
                return host
            ip = self._run(ingress_ip_args(str(kubeconfig))).stdout.strip()
            if ip:
                return ip
            time.sleep(5)
        return ""

    def _read_dir(self, directory: Path) -> dict[str, str]:
        files = {}
        for path in sorted(directory.glob("*.sql")):
            files[path.name] = path.read_text(encoding="utf-8")
        return files

    def _kubeconfig(self, cluster_name: str) -> Path:
        return self.root / ".kube" / cluster_name

    def _run(self, args, *, stream=False, stdin=None):
        return self.runner.run(
            args,
            env=aws_process_env(self.settings, os.environ),
            stdin=stdin,
            stream=stream,
        )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_actions.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add aether_env/actions.py tests/test_actions.py
git commit -m "feat: orchestrate cluster and workload actions"
```

---

### Task 10: Entrada, `.env.example` e README

**Files:**
- Create: `aether_env/__main__.py`
- Modify: `.env.example`
- Modify: `.gitignore`
- Modify: `README.md`
- Test: `tests/test_main.py`

**Interfaces:**
- Consumes: `load_settings`, `missing_tools`, `run_menu`, `Actions`, `SubprocessRunner`, `MenuState`
- Produces: `main(argv_env: Mapping[str, str] | None = None) -> int` e o módulo executável

- [ ] **Step 1: Write the failing test**

```python
# tests/test_main.py
from aether_env.__main__ import main


def test_main_stops_when_aws_key_is_absent(monkeypatch):
    monkeypatch.delenv("AWS_ACCESS_KEY_ID", raising=False)
    code = main({})
    assert code == 2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_main.py -v`

Expected: FAIL with `No module named 'aether_env.__main__'`

- [ ] **Step 3: Write the implementation**

```python
# aether_env/__main__.py
import os
from pathlib import Path

import colorama

from aether_env.actions import Actions
from aether_env.config import ConfigError, load_settings
from aether_env.menu import MenuState, run_menu
from aether_env.preflight import missing_tools
from aether_env.runner import SubprocessRunner


def main(env: dict[str, str] | None = None) -> int:
    colorama.init()
    source = os.environ if env is None else env
    try:
        settings = load_settings(source)
    except ConfigError as exc:
        print("Faltam chaves no .env: " + ", ".join(exc.missing))
        return 2
    absent = missing_tools()
    if absent and env is None:
        print("CLIs ausentes: " + ", ".join(absent))
        return 2
    if env is not None:
        return 0
    root = Path(__file__).resolve().parents[1]
    actions = Actions(settings, SubprocessRunner(), root, print)

    def on_run(state: MenuState) -> int:
        if state.action == "subir-ambiente":
            return actions.subir_ambiente(state.cluster_name or "")
        if state.action == "subir":
            return actions.subir_workload(state.cluster_name or "", state.workload_key or "")
        if state.action == "derrubar":
            return actions.derrubar_workload(state.cluster_name or "", state.workload_key or "")
        if state.action == "update":
            return actions.update_workload(state.cluster_name or "", state.workload_key or "")
        return 1

    def on_confirm(cluster: str, phrase: str) -> int:
        return actions.derrubar_ambiente(cluster, phrase)

    return run_menu(input, print, on_run, on_confirm)


if __name__ == "__main__":
    raise SystemExit(main())
```

Add these lines to `.env.example` after the current Redis block:

```
# AWS / EKS
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_SESSION_TOKEN=
AWS_REGION=sa-east-1
EKS_NODE_TYPE=t3.large
EKS_NODE_COUNT=2
JWT_SECRET=
```

Add this line to `.gitignore` under `#Env`:

```
.kube/
```

Add this section at the end of `README.md`:

```markdown
### Como operar QA e produção?
Preencha as chaves AWS no `.env`. A máquina precisa de Python 3.11, aws, eksctl, kubectl, docker e git.

```
python -m pip install -e ".[dev]"
python -m aether_env
```

QA usa azul e branco. Produção usa vermelho e branco. Subir ambiente cria o EKS e publica as aplicações e os bancos. Derrubar ambiente apaga o cluster, os discos e os repositórios ECR. Produção pede a frase `aether-prod`.
```

Load the `.env` file before `load_settings` when `env` is `None`. Add this helper at the top of `main`, after `colorama.init()`:

```python
    if env is None:
        env_file = Path(__file__).resolve().parents[1] / ".env"
        if env_file.exists():
            for line in env_file.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or "=" not in stripped:
                    continue
                key, value = stripped.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())
```

The test passes `{}` and must not read the developer `.env`. The branch `env is None` is the only one that reads the file.

- [ ] **Step 4: Run the suite**

Run: `python -m pytest -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add aether_env/__main__.py tests/test_main.py .env.example .gitignore README.md
git commit -m "feat: open the QA and production console from the terminal"
```
