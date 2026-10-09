# Cluster-only environment lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer `subir_ambiente` criar só o cluster EKS e o node group, e `derrubar_ambiente` apagar só node groups e o cluster.

**Architecture:** O orquestrador em `Actions` já separa bootstrap (`_bootstrap_cluster`) da publicação de cargas. A subida do ambiente passa a terminar no bootstrap. A descida mantém delete de node group + cluster e deixa de tocar ECR e kubeconfig. Workload start/stop/update continuam usando os helpers de imagem e kubectl.

**Tech Stack:** Python 3.11, pytest, runner falso (`FakeRunner`), aws CLI / eksctl já encapsulados em `aether_env/awscli.py`.

## Global Constraints

- Clusters: `aether-qa` e `aether-prod`; node group gerenciado nome `ng`.
- Subida do ambiente: somente cluster + node group. Sem ECR, Docker, Git, kubectl apply, ingress ou URL de gateway.
- Cluster `ACTIVE`: imprimir `Cluster already exists.` e retornar `0` sem republicar cargas.
- Bootstrap/reconciliação de stack CloudFormation na subida permanece (necessário para `eksctl create cluster`).
- Descida: frase de confirmação inalterada (`yes` / `aether-prod`).
- Descida: delete node groups, depois delete cluster; sem ECR, sem kubeconfig, sem `eksctl delete`, sem `cloudformation delete-stack`.
- Ações por workload não mudam.
- Suíte não chama AWS de verdade. Usar `FakeRunner` em `tests/test_actions.py`.
- Não commitar. O usuário não pediu commit.

## File structure

- Modify: `tests/test_actions.py` — contrato novo de subida/descida; remover expectativas de publish/ingress/ECR/kubeconfig nesses fluxos.
- Modify: `aether_env/actions.py` — `subir_ambiente` e `derrubar_ambiente`.
- Modify: `README.md` — uma linha descrevendo start/tear down.
- Modify: `docs/superpowers/specs/2026-10-06-aether-env-console-design.md` — apontar que o ciclo de ambiente foi substituído pela spec de 2026-10-09.

---

### Task 1: Testes do contrato cluster-only

**Files:**
- Modify: `tests/test_actions.py`
- Test: `tests/test_actions.py`

**Interfaces:**
- Consumes: `Actions.subir_ambiente(cluster_name: str) -> int`, `Actions.derrubar_ambiente(cluster_name: str, typed: str) -> int`, `FakeRunner`
- Produces: testes que falham contra o código atual e passam depois da Task 2

- [ ] **Step 1: Write the failing tests**

Replace the workload/ingress/ECR assertions on environment start/teardown. Keep bootstrap/stack tests that still call `subir_ambiente`. Add:

```python
def test_subir_ambiente_creates_only_cluster_when_missing():
    root = Path(__file__).resolve().parents[1]
    runner = FakeRunner(describe_code=254, describe_stdout="")
    actions = Actions(_settings(), runner, root, lambda message: None)
    with patch.object(Actions, "_wait_cluster_active", return_value=True):
        assert actions.subir_ambiente("aether-qa") == 0
    assert any(call[:3] == ("eksctl", "create", "cluster") for call in runner.calls)
    assert all(call[:2] != ("docker", "build") for call in runner.calls)
    assert all(call[:2] != ("docker", "push") for call in runner.calls)
    assert all(call[0] != "kubectl" for call in runner.calls)
    assert all(call[:3] != ("aws", "eks", "update-kubeconfig") for call in runner.calls)
    assert all(call[:3] != ("aws", "ecr", "get-login-password") for call in runner.calls)
    assert all(call[:3] != ("aws", "ecr", "create-repository") for call in runner.calls)


def test_active_cluster_start_does_not_publish_workloads():
    root = Path(__file__).resolve().parents[1]
    messages = []
    runner = FakeRunner()
    actions = Actions(_settings(), runner, root, messages.append)
    assert actions.subir_ambiente("aether-qa") == 0
    assert "Cluster already exists." in messages
    assert "Publishing workloads." not in "\n".join(messages)
    assert all(call[:3] != ("eksctl", "create", "cluster") for call in runner.calls)
    assert all(call[:2] != ("docker", "build") for call in runner.calls)
    assert all(call[0] != "kubectl" for call in runner.calls)


def test_teardown_does_not_delete_ecr_or_kubeconfig(tmp_path):
    kubeconfig = tmp_path / ".kube" / "aether-qa"
    kubeconfig.parent.mkdir(parents=True)
    kubeconfig.write_text("config", encoding="utf-8")

    def listed_nodegroup(tup):
        if tup[:3] == ("aws", "eks", "list-nodegroups"):
            return CommandResult(tup, 0, "ng\n", "")
        return None

    runner = FakeRunner(scripted_fn=listed_nodegroup)
    actions = Actions(_settings(), runner, tmp_path, lambda message: None)
    assert actions.derrubar_ambiente("aether-qa", "yes") == 0
    assert kubeconfig.exists()
    assert all(call[:3] != ("aws", "ecr", "delete-repository") for call in runner.calls)
    assert any(call[:3] == ("aws", "eks", "delete-nodegroup") for call in runner.calls)
    assert any(call[:3] == ("aws", "eks", "delete-cluster") for call in runner.calls)
```

Remove or rewrite these tests so they no longer require environment start to deploy workloads:

- `test_failed_kubectl_apply_stops_subir_ambiente`
- `test_failed_ingress_nginx_apply_stops_subir_ambiente`
- `test_failed_secret_apply_does_not_print_secret`
- `test_failed_rev_parse_skips_image_push`
- `test_subir_ambiente_waits_for_ingress_nginx_before_gateway_ingress`
- `test_subir_ambiente_publishes_kong`
- `test_subir_ambiente_prints_external_gateway_url`
- `test_subir_ambiente_prints_unavailable_gateway_url`
- `test_failed_ecr_delete_returns_error`

Keep `test_teardown_deletes_nodegroup_before_cluster` and add:

```python
    assert all(call[:3] != ("aws", "ecr", "delete-repository") for call in runner.calls)
```

Do not delete tests of `subir_workload` / `update_workload`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m pytest tests/test_actions.py::test_subir_ambiente_creates_only_cluster_when_missing tests/test_actions.py::test_active_cluster_start_does_not_publish_workloads tests/test_actions.py::test_teardown_does_not_delete_ecr_or_kubeconfig -v`

Expected: FAIL because current `subir_ambiente` still publishes and current `derrubar_ambiente` still deletes ECR/kubeconfig.

- [ ] **Step 3: Do not implement production code in this task**

- [ ] **Step 4: Do not commit**

---

### Task 2: Implementar subida e descida cluster-only

**Files:**
- Modify: `aether_env/actions.py` (`subir_ambiente`, `derrubar_ambiente`; remover `_delete_ecr_repositories` se ficar sem callers)

**Interfaces:**
- Consumes: `_bootstrap_cluster`, `_status`, `_nodegroup_names`, `delete_nodegroup_args`, `delete_cluster_args`, `phrase_accepted`
- Produces: `subir_ambiente` retorna após bootstrap; `derrubar_ambiente` não chama ECR nem unlink de kubeconfig

- [ ] **Step 1: Confirm Task 1 tests still fail**

Run the three new tests. Expected: FAIL.

- [ ] **Step 2: Write minimal implementation**

Replace `subir_ambiente` with:

```python
    def subir_ambiente(self, cluster_name: str) -> int:
        status = self._status(cluster_name)
        if status == "ACTIVE":
            self.write("Cluster already exists.")
            return 0
        if status in (None, "CREATING", "PENDING"):
            return self._bootstrap_cluster(cluster_name)
        self.write(f"Cluster status is {status}.")
        return 1
```

In `derrubar_ambiente`, keep phrase check, nodegroup delete, cluster delete, and the CloudFormation message. Remove:

- `slug = theme_for(cluster_name).slug`
- `ecr_failed = self._delete_ecr_repositories(slug) != 0`
- kubeconfig `unlink`
- return path that depends on `ecr_failed`

Return `1` only when `failed` is true.

If `_delete_ecr_repositories` has no remaining callers, delete that method.

Keep `_publish_image`, `_apply_workloads`, `_apply_checked`, ingress helpers: `subir_workload` / `update_workload` still need them.

- [ ] **Step 3: Run tests**

Run: `python -m pytest tests/test_actions.py -v`

Expected: PASS for the environment lifecycle tests. Workload tests still pass.

- [ ] **Step 4: Run the full suite**

Run: `python -m pytest -q`

Expected: all tests pass.

- [ ] **Step 5: Do not commit**

---

### Task 3: Documentar o contrato novo

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-10-06-aether-env-console-design.md` (nota no topo apontando a spec nova)

**Interfaces:**
- Consumes: spec `docs/superpowers/specs/2026-10-09-cluster-only-lifecycle-design.md`
- Produces: README alinhado; spec antiga marcada como substituída no ciclo de ambiente

- [ ] **Step 1: Update README**

Replace the last paragraph's start/tear-down sentence with:

```
Start environment creates the EKS cluster and managed node group. Tear down environment deletes the node groups and the cluster. Workloads are started, stopped, and updated from Choose workload. QA asks for `yes`. Production asks for `aether-prod`.
```

- [ ] **Step 2: Point the old spec at the new one**

At the top of `docs/superpowers/specs/2026-10-06-aether-env-console-design.md`, after the title, add:

```
> **Superseded for environment start/teardown:** cluster and node group only. See `docs/superpowers/specs/2026-10-09-cluster-only-lifecycle-design.md`. Workload actions in this document remain in force.
```

- [ ] **Step 3: Do not commit**
