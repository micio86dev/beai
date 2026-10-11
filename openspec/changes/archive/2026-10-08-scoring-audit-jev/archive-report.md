# Archive Report: scoring-audit-jev

**Change**: scoring-audit-jev
**Archived to**: `openspec/changes/archive/2026-10-08-scoring-audit-jev/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED. No verify-report existed as a separate SDD phase artifact; the final
verification pass F.1-F.9 is recorded inside `tasks.md` (150 of 150 tasks checked, none unchecked; wrapper
commit `f366431` "docs(sdd): complete scoring-audit-jev final verification (F.1-F.9, 150/150)").

## Summary

A post-hoc, advisory, never-blocking audit of persisted indicator scores: the `AuditJudge` contract with a
TypeSafe/Jev implementation and a fake for tests, append-only audit tables with CHECK constraints, the
`AuditEvaluationJob` and cost estimator, the operator-only trigger endpoint, the per-indicator audit verdict on
the read surface, and the backoffice surface. Observed on disk at archive time:

- api merge commit `a423a6d` ("merge: feature/scoring-audit-jev into develop", 2026-09-18), an ancestor of
  api `develop`; follow-up fixes `29d8072` and `141b4b2` (TypeSafe endpoint path, fixtures, `.env.example`).
- `api/app/Providers/AppServiceProvider.php` binds `AuditJudge` (the `FakeAuditJudge` import is at line 37).
- `api/.env.example` now carries `SCORING_AUDIT_ENABLED`, `TYPESAFE_API_KEY`, `SCORING_AUDIT_JUDGE_MODEL`,
  `SCORING_AUDIT_PROMPT_VERSION` and `SCORING_AUDIT_TIMEOUT` (lines 118-123), which closes the one follow-up
  that `tasks.md` F.9 recorded as outstanding.

## Specs merged

Composition used `gentle-ai sdd-archive-compose` (exit 0 for each of the five deltas); every canonical
requirement not named by a delta is preserved byte for byte. All five merges are pure additions (248 inserted
lines, 0 deleted).

| Capability | Requirements before -> after | Delta |
|---|---|---|
| scoring-audit (NEW) | 0 -> 15 | 15 added (the delta is already in full-spec form, with Purpose; copied byte for byte, `cmp` identical) |
| admin-backoffice | 76 -> 80 | 4 added |
| admin-read-api | 25 -> 26 | 1 added |
| audit-log | 7 -> 8 | 1 added |
| data-retention | 7 -> 9 | 2 added |
| observability | 19 -> 20 | 1 added |

## Not delivered / deferred

- Production activation is NOT part of this archive. `tasks.md` F.9 records that the sub-processor sign-off
  (legal) gates activating the real Jev judge against production data: the code ships, with `FakeAuditJudge`
  bound under `testing` and `TypesafeJevJudge` otherwise. Whether that sign-off has since happened was not
  verified in this archive pass.
- No `@ai` / `workflow_dispatch` real-API test lane was added (decision 0.3, deferred).
- F.8 deploy runbook was recorded, not executed (forward migration only; emergency rollback is
  `SCORING_AUDIT_ENABLED=false`).

## Traceability

Mode openspec. Artifacts read from the filesystem: proposal.md, design.md, tasks.md, apply-progress.md and six
delta specs. Absent: verify-report, exploration.md.

## Copy verification

Moved with `git mv` (no file rewritten). This report is additive.
