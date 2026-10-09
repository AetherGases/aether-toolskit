# Task 3 Report: Documentar o contrato novo

## What was implemented

Aligned user-facing and historical documentation with the cluster-only environment start/teardown contract from `docs/superpowers/specs/2026-10-09-cluster-only-lifecycle-design.md`.

**README.md (How-to section, last paragraph):**

Replaced the start/tear-down sentence so it no longer claims that Start publishes applications/databases or that Tear down deletes disks and ECR. The paragraph now states verbatim (per brief):

- Start environment creates the EKS cluster and managed node group.
- Tear down environment deletes the node groups and the cluster.
- Workloads are started, stopped, and updated from Choose workload.
- QA asks for `yes`. Production asks for `aether-prod`.

Left unchanged: clone repos section, pip install / `python -m aether_env`, QA/production colors and branches.

**docs/superpowers/specs/2026-10-06-aether-env-console-design.md:**

Added the superseded pointer immediately after the `# Console de ambientes QA e produção` title (verbatim per brief). Did not rewrite the rest of the historical spec.

## What was tested and results

Documentation-only task; no tests run. Manual verification: grep confirmed README no longer mentions ECR or “publishes” for start/teardown; pointer block present at top of 2026-10-06 spec.

## Files changed

- `README.md`
- `docs/superpowers/specs/2026-10-06-aether-env-console-design.md`

## Self-review

- Both edits match task brief text exactly.
- Scope respected: no changes to `aether_env/**`, `tests/**`, or 2026-10-09 spec/plan.
- No commit created (per constraints).

## Issues or concerns

None.
