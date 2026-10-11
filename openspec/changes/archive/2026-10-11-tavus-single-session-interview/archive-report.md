# Archive Report: tavus-single-session-interview

**Change**: tavus-single-session-interview
**Archived to**: `openspec/changes/archive/2026-10-11-tavus-single-session-interview/`
**Archive date**: 2026-10-11
**Status**: CLOSED, shipped DARK. Every box in `tasks.md` is ticked: all API and FE slices are merged on `develop` in
api, frontend and backoffice (see `tasks.md`, "Merge record"; also api #163 for API-03b and api #169 for the hardened
multi-topic rules), and the live gates G-A to G-D were run with the owner's go and recorded with dates. The owner
decisions at the flip were recorded on 2026-10-11. This archive ran no test suite.

## Owner decisions (2026-10-11, orchestrator defaults accepted)

- Q1: up to 5 topics per conversation, with the hardened global rules (api #169).
- Canary scope: no project by default; enabled project by project when the owner decides.
- Default flag at release: OFF (`INTERVIEW_TAVUS_SINGLE_SESSION=false`, empty canary list).
- Mid-competency reconnect (Q5): a fresh conversation, as the code does.
- `participant_left_timeout`: default 60 s stands (G-D).
- Steering wording: both N14 constants confirmed unchanged (G-C).
- Billing: only the client's Tavus invoice is authoritative; derived minutes are estimates.

## Specs merged

Composed with `gentle-ai sdd-archive-compose` (exit 0 each). Before composing, one stale clause in the
interview-session delta ("both constants are provisional wording until the live steering gate") was updated to the
G-C result and now quotes the confirmed constants.

| Capability | Requirements before -> after | Delta applied |
|---|---|---|
| interview-conversation | 31 -> 33 | 2 MODIFIED, 2 ADDED |
| interview-frontend | 44 -> 50 | 3 MODIFIED, 6 ADDED |
| interview-session | 48 -> 57 | 3 MODIFIED, 9 ADDED |

## What stays dark, and open items

The whole single-session path is inert until the owner enables a project: the flag ships `false`, the canary list is
empty, and the frontend acts only on a `/start` response carrying `continuation`. Open: the real Tavus bill (test
windows and later production use) is read from the client's invoice, since Tavus has no usage endpoint. Not verified
live and accepted: the plan-level cap (G-B) and the concurrency slot (G-D).

## Rollback

`INTERVIEW_TAVUS_SINGLE_SESSION=false` and an empty canary list (the current state); see `tasks.md`, "Rollback".
