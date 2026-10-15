# Archive Report: live-interview-call-chrome

**Archived**: 2026-10-15
**Archive folder**: `openspec/changes/archive/2026-10-15-live-interview-call-chrome/`
**Artifact store**: hybrid (openspec files + Engram)
**Engram topic key**: `sdd/live-interview-call-chrome/archive-report`

## Artifacts Read (Engram observation IDs)

| Artifact | Engram observation | File locator |
|---|---|---|
| proposal | #3571 | `openspec/changes/archive/2026-10-15-live-interview-call-chrome/proposal.md` |
| spec (digest) | #3572 | `specs/{interview-session,interview-frontend,avatar-templates,admin-backoffice}/spec.md` |
| design | #3573 | `design.md` |
| tasks | #3574 | `tasks.md` (file authoritative) |
| apply-progress | #3575 | `apply-progress.md` |
| verify-report | not present (no Engram topic, no file) | n/a |

Engram digest #3572 states admin-backoffice is "unchanged", while the delta file
`specs/admin-backoffice/spec.md` carries one ADDED requirement (the avatar template form
interviewer display name). Ranking: the file is authoritative and was merged. The digest wording is
inconsistent and is not used as a source for the merge.

## Specs Synced (native composition, `gentle-ai sdd-archive-compose`)

| Domain | Action | Requirements before | Requirements after | Delta |
|---|---|---|---|---|
| interview-session | Updated | 57 | 58 | 1 ADDED, 1 MODIFIED |
| interview-frontend | Updated | 65 | 71 | 6 ADDED, 11 MODIFIED, 3 RENAMED |
| avatar-templates | Updated | 16 | 17 | 1 ADDED |
| admin-backoffice | Updated | 89 | 90 | 1 ADDED |

All four composition runs exited 0. No REMOVED requirements were in the deltas.

## Tasks (from `tasks.md`, the highest-ranked source)

- Completed: 46 of 50 checkboxes.
- Unfinished at archive time (recorded as pending, not done):
  - `T-A3.7` api release gate (not a code task)
  - `R.1` tracker PRs and release order (orchestrator-owned)
  - `R.2` local stack verification after rebuilding images (orchestrator-owned)
  - `R.3` open items for the owner: legal sign-off on persona name (operator text), evaluation-retry budget note (Open Question 1, non-blocking)
- Checkboxes were not modified.

## Final State (launch-prompt facts, rank 2; not independently re-verified here)

- Native reviews: every slice reported approved and acknowledged (api A.i, A.ii, A.iii-a/b/c/d, A.iv, A.v plus follow-up test commit aaf4528; backoffice A2; frontend B.i-a, B.i-b, B.ii, B.ii-b, C1a, C1a-2, C1b, C1b-2, C2a.1 x4, C2a.2 x2, C2b, C3 x3).
- A.iii-b required one bounded correction (c1d8fab: malformed UTF-8 and edge control characters in PersonaDisplayName), validated and approved.
- Review follow-ups closed (api A.v): outline 403/422 documented in OpenAPI; `persona: null` refused with 422; Unicode-space-only names refused; separator-split provider names refused. Outline session ordering proven unnecessary by `unique(participant_id, competency_code)`.
- Review follow-ups closed (frontend C3): outline single-flight lost update fixed; mic toggle during restore re-applied; answer timer picks up the initial speaker; competency ordinal/total move with the session swap, including Tavus continuation; countdown always visible when `interview_max_seconds` is invalid; embedded xl panel scrolls. Nuxt production build reported verified.
- Open non-blocking note: the no-max duration state has no dedicated accessibility test. InterviewTimer is `role="timer"` with an aria-label, so it is exposed.

## Spec Deviation Not Folded Into the Merged Spec

The launch prompt asks to fold the following deviation into `openspec/specs/interview-frontend/spec.md`:
when `interview_max_seconds` is missing or invalid, the Durata heading, figure, bar and sentence stay
hidden, but the enforcing InterviewTimer countdown stays VISIBLE.

The merged spec was produced only by native composition from the delta files. The archive contract
forbids a model-driven Read/Edit merge, and the delta does not state this rule. The rule is therefore
recorded here and is NOT present in the main spec. A follow-up spec change is required to make it
normative.

Other launch-prompt spec clarifications (competency name `name: string|null` with client fallback
"Competenza {ordinal}"; caption prefix token `--color-primary-caption` at 4.5:1; persona clear payload
`persona: {}` with `null` refused) are checked against the delta at archive time and are NOT
confirmed as folded into the main specs by this archive. They remain a follow-up for the same
reason.

## Diff Readback (mechanical copy)

- Source snapshot taken with `cp -R` before the move; `git mv` used for the move.
- Readback `diff -r <pre-move snapshot> openspec/changes/archive/2026-10-15-live-interview-call-chrome`: empty output, status 0.
- Source folder `openspec/changes/live-interview-call-chrome` no longer exists.
- This `archive-report.md` was written after the readback, is additive, and is excluded from the comparison.

## Risks and Open Items

- The merged `interview-frontend` spec does not yet state the invisible-timer rule above; follow-up required.
- Engram digest #3572 wording on admin-backoffice conflicts with the delta file; the file was used.
- Releases R.1 to R.3 and `T-A3.7` remain open and are not implied as done.
- `odd/tasks/seamless-primary-transition.md` and submodule pointers `api`, `backoffice`, `frontend` were not staged by this archive.
