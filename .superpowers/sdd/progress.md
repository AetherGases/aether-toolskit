# Cluster-only lifecycle SDD ledger

- Plan: `docs/superpowers/plans/2026-10-09-cluster-only-lifecycle.md`
- Spec: `docs/superpowers/specs/2026-10-09-cluster-only-lifecycle-design.md`
- Workspace: in-place on `develop` (not a linked worktree; dirty tree with Kong work already present)
- Commits: none requested; tasks must not commit

Task 1: complete (tests RED in tests/test_actions.py, review clean by controller, no commit)
Task 2: complete (cluster-only subir/derrubar; 17/17 + 55/55 pytest; controller removed dead start helpers; no commit)
Task 3: complete (README + old spec pointer; no commit)
Final: pytest -q 55 passed (controller re-run after dead-code cleanup)
