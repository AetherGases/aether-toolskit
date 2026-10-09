# Task 1: Testes do contrato cluster-only

Read the spec first: `docs/superpowers/specs/2026-10-09-cluster-only-lifecycle-design.md`
Read the plan: `docs/superpowers/plans/2026-10-09-cluster-only-lifecycle.md` (Task 1 only)

## Goal

Change `tests/test_actions.py` so environment start/teardown tests describe the new contract. Do **not** change `aether_env/actions.py` in this task. The new tests must fail against current production code (RED).

## Ownership

- Exclusive: `tests/test_actions.py`
- Do not modify: `aether_env/**`, README, other test files

## Constraints

- Follow TDD: tests only.
- Do not commit.
- Keep `FakeRunner` and `_settings()` helpers.
- Keep tests for `_bootstrap_cluster`, stack repair, `subir_workload`, `update_workload`, wrong teardown phrase, and `test_teardown_deletes_nodegroup_before_cluster` (extend the last one).
- Workload tests must still cover start/update when cluster is ACTIVE.

## Tests to add (verbatim intent)

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

## Tests to remove or rewrite

Remove these environment-start tests that require publishing/ingress/secrets (they belong to the old contract):

- `test_failed_kubectl_apply_stops_subir_ambiente`
- `test_failed_ingress_nginx_apply_stops_subir_ambiente`
- `test_failed_secret_apply_does_not_print_secret`
- `test_failed_rev_parse_skips_image_push`
- `test_subir_ambiente_waits_for_ingress_nginx_before_gateway_ingress`
- `test_subir_ambiente_publishes_kong`
- `test_subir_ambiente_prints_external_gateway_url`
- `test_subir_ambiente_prints_unavailable_gateway_url`
- `test_failed_ecr_delete_returns_error`

In `test_teardown_deletes_nodegroup_before_cluster`, add:

```python
    assert all(call[:3] != ("aws", "ecr", "delete-repository") for call in runner.calls)
```

## Validation

```
python -m pytest tests/test_actions.py::test_subir_ambiente_creates_only_cluster_when_missing tests/test_actions.py::test_active_cluster_start_does_not_publish_workloads tests/test_actions.py::test_teardown_does_not_delete_ecr_or_kubeconfig -v
```

Expected: FAIL for the reason in the spec (current code still publishes on start and still deletes ECR/kubeconfig on teardown). Capture that output in the report.

Also run:

```
python -m pytest tests/test_actions.py -v
```

Report which tests fail (expected RED) vs which still pass.

## Done when

- New tests exist
- Obsolete environment-start tests are gone
- Production code is unchanged
- RED evidence is in the report file
