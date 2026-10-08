# Archive Report: stale-interview-reaper

**Change**: stale-interview-reaper
**Archived to**: `openspec/changes/archive/2026-10-08-stale-interview-reaper/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED. No verify-report existed; verification was not run as an SDD phase. `tasks.md`
has all tasks checked and records the observed runs (2956 api tests, 2949 passed, 7 skipped, 0 failed; pint and
phpstan clean; `schedule:list` shows the 15-minute entry).

## Summary

A scheduled sweep that ends interview sessions abandoned in `in_corso`, settles the participant (scores what
the candidate did say, or moves to `errore` when there is no candidate speech), and supports a report-only
`--dry-run`. Observed on disk at archive time:

- api commit `19a1db2` ("feat(interview): ask the operator's question, and end what the browser never ended"),
  an ancestor of api `develop` and `origin/main`.
- `api/app/Console/Commands/ReapStaleInterviews.php` and
  `api/tests/Feature/Interview/ReapStaleInterviewsTest.php` exist; `api/config/interview.php:65` defines
  `stale_after_minutes` (default 30); `api/bootstrap/app.php:106` schedules the command.

## Specs merged

| Capability | Requirements before -> after | Delta |
|---|---|---|
| interview-session | 44 -> 47 | 3 added (pure additions: 75 inserted lines, 0 deleted) |

Composition used `gentle-ai sdd-archive-compose` (exit 0).

## Not delivered / deferred

Nothing in `tasks.md`. The change's own "NOT in this change" section stays out of scope: why the avatar fails to
speak its closing phrase (a separate conversation defect) and backoffice UX for a stalled participant.

## Traceability

Mode openspec. Artifacts read from the filesystem: proposal.md, design.md, tasks.md, one delta spec. Absent:
verify-report, apply-progress, exploration.md.

## Copy verification

Moved with `git mv` (no file rewritten). This report is additive.
