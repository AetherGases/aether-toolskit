# Task 2: Implementar subida e descida cluster-only

Read first: `docs/superpowers/specs/2026-10-09-cluster-only-lifecycle-design.md`
Plan Task 2: `docs/superpowers/plans/2026-10-09-cluster-only-lifecycle.md`
Tests already written (RED): `tests/test_actions.py`

## Goal

Make `Actions.subir_ambiente` create only the EKS cluster + managed node group, and `Actions.derrubar_ambiente` delete only node groups + cluster. Turn the Task 1 tests green.

## Ownership

- Exclusive: `aether_env/actions.py`
- Allowed extra: patch `_wait_cluster_active` in existing slow tests in `tests/test_actions.py` that call `subir_ambiente` without the patch (`test_failed_stack_is_removed_before_create`, `test_stack_cleanup_deletes_orphaned_eks_security_group`, `test_delete_failed_stack_retains_vpc_lattice_resources`, `test_delete_failed_stack_is_retried_before_create`, `test_missing_cluster_starts_eksctl`). Do not weaken assertions. Do not reintroduce removed tests.
- Do not modify README or specs (Task 3).

## Shared contracts (do not change)

```python
def subir_ambiente(self, cluster_name: str) -> int
def derrubar_ambiente(self, cluster_name: str, typed: str) -> int
```

Workload methods stay: `subir_workload`, `derrubar_workload`, `update_workload`.
Keep `_bootstrap_cluster` and stack reconciliation.

## Implementation (verbatim)

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

The ACTIVE message must be exactly `Cluster already exists.` as its own `write()` argument (tests use `in messages`, not substring of a longer line).

In `derrubar_ambiente`:
- Keep phrase check, nodegroup delete + wait, cluster delete + wait, denied-describe still deletes, already-absent message, and the CloudFormation-only message.
- Remove `theme_for` slug usage if only used for ECR.
- Remove `_delete_ecr_repositories(...)` call.
- Remove kubeconfig `unlink`.
- Return `1` only when nodegroup/cluster delete `failed`.
- If `_delete_ecr_repositories` has no remaining callers, delete the method.

Keep `_publish_image`, `_apply_workloads`, `_apply_checked`, ingress helpers used by workload actions.

## TDD

1. Confirm RED on the three new tests (they should still fail before your code change).
2. Implement.
3. Run:

```
python -m pytest tests/test_actions.py -v
```

Must finish in well under a few minutes. If a test hangs in `_wait_cluster_active`, add the patch listed above.

4. Run full suite:

```
python -m pytest -q
```

5. Do NOT commit.

## Done when

- Task 1 contract tests pass
- Existing bootstrap/teardown/workload tests pass
- No ECR delete or kubeconfig unlink on environment teardown
- No Docker/kubectl/ECR/kubeconfig on environment start
- Report written to `.superpowers/sdd/task-2-report.md`
