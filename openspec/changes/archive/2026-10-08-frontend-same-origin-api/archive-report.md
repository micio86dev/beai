# Archive Report: frontend-same-origin-api

**Change**: frontend-same-origin-api
**Archived to**: `openspec/changes/archive/2026-10-08-frontend-same-origin-api/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED. The change has no `tasks.md`, no design and no verify-report: it is a proposal
plus one delta spec. The proposal records a regression check ("reintroducing the absolute base and the old
variable name fails 3 of its 5 assertions").

## Summary

The candidate `frontend` now reaches the API on its own origin: `NUXT_PUBLIC_API_BASE` is relative (`/api`), a
Nitro catch-all route proxies `/api` to a server-only `apiOrigin`, and the variable is `NUXT_API_ORIGIN`.
Observed on disk at archive time:

- frontend commits `9ca458f` ("fix(api): reach the API on our own origin, not a Docker-internal hostname",
  2026-09-02) and `7ea4d78` ("fix(api-proxy): name the variable Nuxt actually reads, and guard the mechanism",
  2026-09-03), both ancestors of frontend `develop`.
- `frontend/server/routes/api/[...].ts` exists and its error message names `NUXT_API_ORIGIN` (line 49);
  `frontend/.env.example:25` sets `NUXT_API_ORIGIN`; `frontend/tests/unit/arch/same-origin-api.spec.ts` exists.

## Specs merged

| Capability | Requirements before -> after | Delta |
|---|---|---|
| candidate-frontend (NEW) | 0 -> 2 | 2 added |

`openspec/specs/candidate-frontend/spec.md` did not exist, so `gentle-ai sdd-archive-compose` (which needs a
canonical with at least one requirement) could not be used. The file was built by script: a `Purpose` header
authored for the new capability, followed by the delta's two `### Requirement:` blocks copied byte for byte.
The delta names the capability `candidate-frontend`, distinct from the existing `interview-frontend` (the
interview flow, device check and proctoring of the same app); nothing was merged into `interview-frontend`.
Whether the two should eventually be one capability is a spec decision left to a human.

## Not delivered / deferred

Nothing. The sibling `backoffice-same-origin-api` change is archived separately.

## Traceability

Mode openspec. Artifacts read from the filesystem: proposal.md and one delta spec. Absent: design, tasks,
verify-report, apply-progress, exploration.md.

## Copy verification

Moved with `git mv` (no file rewritten). This report is additive.
