# Task 1 Report: Testes do contrato cluster-only

## What was implemented

Updated `tests/test_actions.py` to encode the cluster-only environment lifecycle contract from `docs/superpowers/specs/2026-10-09-cluster-only-lifecycle-design.md`.

**Added tests (verbatim from plan/brief):**

- `test_subir_ambiente_creates_only_cluster_when_missing` — missing cluster path must run `eksctl create cluster` only; no Docker, kubectl, kubeconfig, or ECR calls after bootstrap.
- `test_active_cluster_start_does_not_publish_workloads` — ACTIVE cluster must print `Cluster already exists.` (exact message), not publish workloads, and must not create cluster or run Docker/kubectl.
- `test_teardown_does_not_delete_ecr_or_kubeconfig` — teardown must keep `.kube/<cluster>`, delete node group and cluster, and not call `aws ecr delete-repository`.

**Extended:**

- `test_teardown_deletes_nodegroup_before_cluster` — added assertion that no `aws ecr delete-repository` calls occur.

**Removed (old full-environment-start contract):**

- `test_failed_kubectl_apply_stops_subir_ambiente`
- `test_failed_ingress_nginx_apply_stops_subir_ambiente`
- `test_failed_secret_apply_does_not_print_secret`
- `test_failed_rev_parse_skips_image_push`
- `test_subir_ambiente_waits_for_ingress_nginx_before_gateway_ingress`
- `test_subir_ambiente_publishes_kong`
- `test_subir_ambiente_prints_external_gateway_url`
- `test_subir_ambiente_prints_unavailable_gateway_url`
- `test_failed_ecr_delete_returns_error`

Also removed unused helper `_kubectl_apply_stdin` and import `INGRESS_NGINX_URL`.

**Preserved:** `FakeRunner`, `_settings()`, bootstrap/stack repair tests, `subir_workload` / `update_workload` coverage, wrong-phrase teardown, and related tests.

**Production code:** No edits to `aether_env/**` in this task session (tests only).

## What was tested and results

### Required RED command (three new tests)

```
python -m pytest tests/test_actions.py::test_subir_ambiente_creates_only_cluster_when_missing tests/test_actions.py::test_active_cluster_start_does_not_publish_workloads tests/test_actions.py::test_teardown_does_not_delete_ecr_or_kubeconfig -v
```

**Result:** 3 failed in ~2.6s (expected RED).

### Full `tests/test_actions.py`

A full `-v` run blocks for a long time on five legacy tests that call `subir_ambiente` without patching `_wait_cluster_active` while `describe-cluster` returns 254 (`_wait_cluster_active` polls up to 900s with 15s sleeps).

Completed subset (12 tests, excluding those five slow cases):

```
python -m pytest tests/test_actions.py -v -k "not (failed_stack_is_removed_before_create or stack_cleanup_deletes_orphaned or delete_failed_stack_retains or delete_failed_stack_is_retried or missing_cluster_starts_eksctl)"
```

**Result:** 4 failed, 8 passed, 5 deselected in ~2.3s.

| Test | Result | Notes |
|------|--------|--------|
| `test_teardown_deletes_nodegroup_before_cluster` | FAIL | Expected RED (ECR delete assertion) |
| `test_teardown_still_deletes_when_describe_is_denied` | PASS | |
| `test_wrong_phrase_does_not_delete` | PASS | |
| `test_stopped_environment_refuses_item_action` | PASS | |
| `test_database_update_restarts_and_skips_docker` | PASS | Workload path |
| `test_active_cluster_skips_eksctl_create_even_with_stack` | PASS | `_bootstrap_cluster` |
| `test_reconcile_reuses_healthy_stack_and_creates_cluster` | PASS | |
| `test_delete_failed_stack_is_repaired_before_create` | PASS | |
| `test_start_does_not_wait_on_cloudformation_stack_delete` | PASS | |
| `test_subir_ambiente_creates_only_cluster_when_missing` | FAIL | Expected RED |
| `test_active_cluster_start_does_not_publish_workloads` | FAIL | Expected RED |
| `test_teardown_does_not_delete_ecr_or_kubeconfig` | FAIL | Expected RED |
| Five deselected `subir_ambiente` stack tests | Not run (slow) | Unchanged by this task; still patch-free |

## TDD evidence (RED)

**Command:**

```
python -m pytest tests/test_actions.py::test_subir_ambiente_creates_only_cluster_when_missing tests/test_actions.py::test_active_cluster_start_does_not_publish_workloads tests/test_actions.py::test_teardown_does_not_delete_ecr_or_kubeconfig -v
```

**Relevant failures:**

1. **`test_subir_ambiente_creates_only_cluster_when_missing`** — after `_wait_cluster_active` patch and return `0`, production `subir_ambiente` still runs publish/apply:

   ```
   assert all(call[:2] != ("docker", "build") for call in runner.calls)
   E       assert False
   ```

   Current code continues past bootstrap into kubeconfig, ECR login, and Docker builds.

2. **`test_active_cluster_start_does_not_publish_workloads`** — message contract mismatch:

   ```
   assert "Cluster already exists." in messages
   E   AssertionError: assert 'Cluster already exists.' in ['Cluster already exists. Publishing workloads.', 'Updating kubeconfig.', ...]
   ```

   Production prints a combined message and still publishes.

3. **`test_teardown_does_not_delete_ecr_or_kubeconfig`** — kubeconfig removed and ECR still deleted:

   ```
   assert kubeconfig.exists()
   E   AssertionError: assert False
   ```

4. **`test_teardown_deletes_nodegroup_before_cluster`** (extended assertion):

   ```
   assert all(call[:3] != ("aws", "ecr", "delete-repository") for call in runner.calls)
   E       assert False
   ```

**Why failure was expected:** Spec/plan state that current `subir_ambiente` still publishes workloads and current `derrubar_ambiente` still deletes ECR repos and unlinks local kubeconfig. Task 2 should make these tests pass.

## Files changed

- `tests/test_actions.py` — only file modified for Task 1.

## Self-review

- New tests match brief/plan text and assertions.
- Obsolete environment-start tests removed; workload and bootstrap tests kept.
- `FakeRunner` and `_settings()` unchanged in role and usage.
- No production code changes in this task.
- Removed dead code (`_kubectl_apply_stdin`, `INGRESS_NGINX_URL` import) after deleting dependent tests.
- Minor note: `test_active_cluster_start_does_not_publish_workloads` uses exact `"Cluster already exists." in messages`; production uses a single string containing that phrase plus extra text — Task 2 must align message to spec (exact line or list entry).

## Issues or concerns

- Full-file pytest can take ~15+ minutes per uncached run because five existing stack-repair tests call `subir_ambiente` without mocking `_wait_cluster_active` when the cluster is “missing” (describe exit 254). Consider patching wait in those tests in a later cleanup (out of Task 1 scope).
- Workspace may contain unrelated uncommitted changes under `aether_env/**`; this task did not modify them.
