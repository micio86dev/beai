# Archive Report: candidate-interview-call-ui

**Change**: candidate-interview-call-ui
**Archived to**: `openspec/changes/archive/2026-10-11-candidate-interview-call-ui/`
**Archive date**: 2026-10-11
**Status**: CLOSED. The call screen is the only live interview screen. UI-00 to UI-08 are ticked in `tasks.md` with
their merge records. UI-09 to UI-12 are merged in `frontend` (PR #78 stage assembly, #80 end to end, #81 viewports and
baselines, #82 default on) but their boxes were not ticked in `tasks.md` before this archive; the same holds for the
T-BUG-1 and T-BUG-2 slots. The owner decided on 2026-10-11 to remove the legacy live screen now instead of after a
released soak, so UI-13 landed in frontend hotfix 0.25.1 (branch `hotfix/0.25.1`) and UI-14 closed the docs. The
owner recorded the manual checks M1 to M5 as done on 2026-10-11 (UI-11.4). This archive ran no test suite.

## Specs merged

Composed with `gentle-ai sdd-archive-compose` (exit 0). Before composing, the delta was amended to the end state: the
legacy screen and the `candidateCallUi` flag no longer exist after UI-13, so every "flag on" precondition was dropped
from the ADDED scenarios and the ADDED requirement "The Call Screen Ships Behind The candidateCallUi Flag" was removed
(it would have put a requirement for a deleted flag into the main spec).

| Capability | Requirements before -> after | Delta applied |
|---|---|---|
| interview-frontend | 50 -> 65 | 3 MODIFIED, 15 ADDED (16 proposed, flag requirement dropped) |

UI-14.3: `rg -n 'Pause \(live mute\)|presses Pause' openspec/specs/interview-frontend/spec.md` finds nothing.

## Docs

`DESIGN.md` §7.3 now describes the call stage as the only live screen; the flag-off screen (status pill, live dock,
Pause) and every `candidateCallUi` mention were removed. `CLAUDE.md` and `docs/` carried no reference to the flag or
the legacy screen.

## Open items

- Recording indicator: still not rendered and still an open consent and legal decision (open question 4, `DESIGN.md`
  §7.3 status elements).
- References: UI-13 is frontend hotfix 0.25.1, branch `hotfix/0.25.1` (no PR: Git Flow hotfix finished locally), deletion commit `c3cf938`, release commit `90d9f19`, merge commit `737ea18` on frontend `main`, tag `v0.25.1`. It removed the legacy live screen and the `candidateCallUi` flag; native review `review-5534c34040af2dc8` approved with two accepted warnings (no configuration-level rollback any more; a deployment still setting `NUXT_PUBLIC_CANDIDATE_CALL_UI` is silently ignored; the variable was never set in Railway).

## Rollback

There is no flag to turn off any more: rolling back means reverting frontend hotfix 0.25.1 (which restores the
`candidateCallUi` kill switch with the call screen as its default).
