# Task 3: Documentar o contrato novo

Read: `docs/superpowers/specs/2026-10-09-cluster-only-lifecycle-design.md`

## Goal

Align user-facing and historical docs with cluster-only environment start/teardown.

## Ownership

- Exclusive: `README.md`, `docs/superpowers/specs/2026-10-06-aether-env-console-design.md`
- Do not modify: `aether_env/**`, `tests/**`, the 2026-10-09 spec/plan (already written)

## Step 1: README

In `README.md`, replace the last paragraph's start/tear-down sentence so the How-to section says:

```
Start environment creates the EKS cluster and managed node group. Tear down environment deletes the node groups and the cluster. Workloads are started, stopped, and updated from Choose workload. QA asks for `yes`. Production asks for `aether-prod`.
```

Keep the rest of the README (clone repos, pip install, python -m aether_env, colors/branches) unless a sentence still claims start publishes apps or teardown deletes ECR.

## Step 2: Old spec pointer

At the top of `docs/superpowers/specs/2026-10-06-aether-env-console-design.md`, immediately after the `# Console de ambientes QA e produção` title, add:

```
> **Superseded for environment start/teardown:** cluster and node group only. See `docs/superpowers/specs/2026-10-09-cluster-only-lifecycle-design.md`. Workload actions in this document remain in force.
```

Do not rewrite the rest of that historical spec.

## Constraints

- Do not commit.
- No production code.

## Done when

README and the pointer exist. Write report to `.superpowers/sdd/task-3-report.md`.
