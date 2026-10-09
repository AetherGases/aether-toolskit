# Task 2 Report: Cluster-only environment start/teardown

## Goal

Make `Actions.subir_ambiente` bootstrap EKS only and `Actions.derrubar_ambiente` delete node groups + cluster only (no ECR, no kubeconfig unlink). Turn Task 1 contract tests green.

## TDD: RED

Command:

```
py -3.11 -m pytest tests/test_actions.py::test_subir_ambiente_creates_only_cluster_when_missing tests/test_actions.py::test_active_cluster_start_does_not_publish_workloads tests/test_actions.py::test_teardown_does_not_delete_ecr_or_kubeconfig -v
```

Result: **3 failed** in 0.84s (before `actions.py` changes).

| Test | Failure |
|------|---------|
| `test_subir_ambiente_creates_only_cluster_when_missing` | `docker build` present in `runner.calls` after bootstrap |
| `test_active_cluster_start_does_not_publish_workloads` | Message was `Cluster already exists. Publishing workloads.`; workloads/docker/kubectl ran |
| `test_teardown_does_not_delete_ecr_or_kubeconfig` | Kubeconfig file removed after teardown |

## Implementation

### `aether_env/actions.py`

1. **`subir_ambiente`** — Replaced with spec/plan verbatim implementation:
   - `ACTIVE` → write exactly `Cluster already exists.`, return `0`
   - `None`, `CREATING`, or `PENDING` → `return self._bootstrap_cluster(cluster_name)`
   - Other status → message + return `1`
   - Removed entire workload path (kubeconfig, ECR login, docker, kubectl, ingress, gateway URL).

2. **`derrubar_ambiente`** — Removed `theme_for` / slug, `_delete_ecr_repositories`, kubeconfig `unlink`, and `ecr_failed` from return logic. Return `1` only when nodegroup/cluster delete `failed` is true.

3. **Removed** `_delete_ecr_repositories` and unused imports: `delete_ecr_args`, `DEFAULT_TEARDOWN_WORKERS`.

Workload helpers (`_publish_image`, `_apply_workloads`, etc.) unchanged for `subir_workload` / `update_workload`.

### `tests/test_actions.py` (allowed patches)

Five bootstrap tests that call `subir_ambiente` without mocks now return immediately after cluster-only start (they previously “escaped” real `_wait_cluster_active` / `_wait_stack_absent` loops only because the old path spent time elsewhere). Patched:

- `test_failed_stack_is_removed_before_create`
- `test_stack_cleanup_deletes_orphaned_eks_security_group`
- `test_delete_failed_stack_retains_vpc_lattice_resources`
- `test_delete_failed_stack_is_retried_before_create`
- `test_missing_cluster_starts_eksctl`

Each uses `patch.object(Actions, "_wait_stack_absent", return_value=True)` and `patch.object(Actions, "_wait_cluster_active", return_value=True)` (same pattern as `test_start_does_not_wait_on_cloudformation_stack_delete`). **Assertions unchanged.**

## TDD: GREEN

```
py -3.11 -m pytest tests/test_actions.py -v
```

**17 passed in 0.22s**

```
py -3.11 -m pytest -q
```

**55 passed in 0.66s**

## Files changed

| File | Change |
|------|--------|
| `aether_env/actions.py` | Cluster-only `subir_ambiente` / `derrubar_ambiente`; removed `_delete_ecr_repositories` |
| `tests/test_actions.py` | Wait patches on five slow bootstrap tests |

## Self-review

- Public signatures unchanged: `subir_ambiente(self, cluster_name: str) -> int`, `derrubar_ambiente(self, cluster_name: str, typed: str) -> int`.
- `_bootstrap_cluster` and stack reconciliation untouched.
- Teardown still prints CloudFormation disclaimer; phrase gate and delete ordering preserved.
- `PENDING` included in bootstrap branch per brief (was `CREATING` only in old code).

## Concerns

- Slow-test fix required **`_wait_stack_absent`** in addition to `_wait_cluster_active`; brief listed only the latter, but ROLLBACK/DELETE_FAILED reconcile paths wait on stack absence and hang with static `FakeRunner` stack status.
- No commit (per task instructions).

## Commits

None.
