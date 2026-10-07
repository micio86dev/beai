# Archive Report: scoring-retry-rt-b

**Change**: scoring-retry-rt-b
**Archived to**: `openspec/changes/archive/2026-10-06-scoring-retry-rt-b/`
**Archive date**: 2026-10-06
**Status**: CLOSED WITH OPEN FOLLOW-UPS (see below). No verify-report existed; verification was not run as an SDD phase. Per-slice checks are recorded in `tasks.md`.

## Summary

The single domain retry of a `pending` evaluation (RT-B, ruling 4 RATIFIED 2026-10-05) is delivered:
one shared authorization action used by operator and M2M caller, a fresh single-use link emailed (and
returned) to the candidate, a re-interview that offers only competencies without a valid result, a
scoring branch that merges instead of re-scoring everything, attempt-scoped finalize and webhook
deduplication, and the operator retry panel in the backoffice.

## Final state at close (authoritative; outranks any stale snapshot)

Merged on develop:

- wrapper #72 (PR0w SSO rule), backoffice #75 (PR0b), api #126 (PR0, 24 h emailed links).
- api #127 (PR1a foundations), #128 (PR1b action, 1,233 lines; native review approved after one correction of the architecture test).
- api #129 (PR2a scoring branch), #130 (PR2b failure and webhook dedupe), #131 (PR2c re-interview opening).
- api #132 (PR3a email + read state): the native review closed `escalated` on one inferential finding that CI later disproved.
- api #133 (PR3b endpoints; it found and fixed an `AuditRecorder` actor defect), #134 (`/auth/me` contract), #135 (M2M 403 documentation + potential end-to-end test).
- backoffice #76 (PR4a panel), #77 (PR4b page wiring); frontend #60 (PR4f client).
- wrapper #73 (ruling 4 RATIFIED 2026-10-05 and the domain docs).
- Open at the time of writing: backoffice #79 (client regenerated for the 403) and frontend #61 (client 403).
- Related, unrelated-in-scope change: backoffice #78 (the project form pre-ticks the role's competencies on create) was an owner request made during this work; it is not part of this change's requirements.

Owner decisions recorded: D-A (operator and caller authorize through one action); D-B (email plus returned link);
D-C (no expiry on the retry); emailed invitation links live 24 h while returned ones stay 30 min; a pending
evaluation is unreadable during a retry; the audit row is written after commit; `model_version` and
`prompt_version` are re-stamped on retry while `framework_version` stays pinned; `size:exception` was
accepted for slices PR0, PR1a, PR1b, PR2a, PR2b, PR3a, PR3b, PR4a and PR4b.

## Specs merged

Composition used `gentle-ai sdd-archive-compose` for all nine deltas; every canonical requirement
not named by a delta is preserved byte for byte by that command.

| Capability | Requirements before -> after | Delta |
|---|---|---|
| admin-backoffice | 72 -> 76 | 4 added |
| admin-read-api | 24 -> 25 | 1 added |
| interview-conversation | 23 -> 24 | 1 added (23 includes the 6 added by `potential-assessment-interview`, archived first the same day) |
| interview-session | 42 -> 44 | 1 modified, 2 added |
| m2m-auth | 11 -> 12 | 1 modified, 1 added |
| notifications | 9 -> 10 | 1 added |
| participant-sso | 40 -> 45 | 3 modified, 5 added |
| scoring-engine | 24 -> 24 | 1 modified, 1 added (replaces the removed old RT-B requirement), 1 removed |
| webhooks-integration | 13 -> 13 | 1 modified |

### Deviation, disclosed: scoring-engine composition

The scoring-engine delta lists "Retry — Single Re-Interview of a `pending` Evaluation (RT-B)" under
MODIFIED, but no live requirement carries that name (it replaces "Retry — Fast-Follow Work Unit (RT-B)",
which the same delta REMOVES). The compose command refused: `unapplied MODIFIED delta ... no canonical
requirement named ...`. Instead of a manual merge, a scratch copy of the delta was derived mechanically
(that one block moved from MODIFIED to ADDED; the REMOVED entry's two note lines joined onto one line each
because the command requires a single-line `(Reason: ...)`), and the SAME compose command was run on it
(exit 0). The archived delta in this folder is the unmodified original. Consequence: the new requirement
sits at the end of the live spec, not in the old requirement's position.

### Non-requirement edits applied (scripted, one-match assertions)

- scoring-engine: the "Retry sub-system (chain-PR 4) — DEFERRED" paragraph deleted from Delivery Status (the first-pass line kept); the cross-reference at the log-retry requirement now names the new requirement; the `:63-64` payload note was already carried by the MODIFIED "Job Dispatch and Lifecycle" block.
- notifications: Purpose and the first Non-Goals bullet corrected (candidate transactional email exists, rulings 8 and 10; only reminders and time-triggered notification remain non-goals).
- interview-conversation: the Non-Goals "Domain retry (RT-B)" line rewritten (retry is ratified and specified elsewhere).
- participant-sso: the "30-minute TTL" wording at the mint-claims requirement now states 30 min for returned links and 24 h for emailed ones. The M2M mint line ("TTL: 30 minutes") and the "No Revocation Semantics" text stay true. `reusable-interview-links` lines 9, 1810 and 1820 were checked and stay true (returned links stay 30 min).
- webhooks-integration: the Non-Goals "Domain retry (RT-B ... open decision #4)" bullet was stale and is rewritten.
- `docs/app_description/04-integration-surface/01-sso-ingress.md`: states that the expiry is read from the token's own `exp` claim and never recomputed (task 1.2; the half the earlier docs slice did not confirm).

## Unfinished at archive (recorded, not done)

- **Task 14.1**: pinning the released api, backoffice and frontend tags in the wrapper. No release or tag is made until the owner asks; the submodule pointer bump in the wrapper is also pending.
- **Task 1.2 and task 14.4** are unchecked in the archived `tasks.md` (a snapshot); both were applied by this archive pass. Checkboxes were not rewritten.
- backoffice #79 and frontend #61 (client regenerated for the 403) were open at the time of writing; their merge was not confirmed here.
- The HeyGen branches are unrelated and not yet published.

## Known limits (deliberate or accepted)

- A retry finalization that itself throws leaves the participant `in_valutazione` with only a log line. This is deliberate: the single retry is not burned by an infrastructure fault.
- The architecture guard for the `completato` edge is syntactic.
- A retry for a participant who never re-interviews stays `pending` forever (D-C, no expiry).
- The native review on api #132 closed `escalated` on one inferential finding that CI later disproved; no defect was confirmed from it.

## Traceability

Mode openspec; no Engram observation IDs were read (artifacts were read from the filesystem).
Present: proposal.md, exploration.md, design.md, tasks.md and nine delta specs (108 checked, 3 unchecked tasks). Absent: verify-report, apply-progress.

## Copy verification

`cp -R` from the main checkout (original left in place), then `diff -r source destination`: empty output,
exit 0. This report is additive and excluded from that comparison.
