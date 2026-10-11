# Archive Report: backoffice-same-origin-api

**Change**: backoffice-same-origin-api
**Archived to**: `openspec/changes/archive/2026-10-08-backoffice-same-origin-api/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED. Proposal-only change: no delta specs, no design, no tasks, no verify-report.
No spec merge was performed.

## Summary

The backoffice SPA now reaches the API on its own origin (nginx proxies `/api/`), so the `beai_refresh` cookie is
first-party and Safari keeps a session across reloads. Observed on disk at archive time:

- backoffice commit `cd3adbf` ("fix(auth): serve the API from the backoffice origin so Safari can keep a
  session", 2026-08-26), an ancestor of backoffice `develop`. It changed `Dockerfile` (+75),
  `.github/workflows/ci.yml`, retired `tests/e2e/session-cookie.spec.ts`, and added
  `tests/unit/arch/same-origin-api.spec.ts`.
- `backoffice/Dockerfile` contains `location ^~ /api/` with `proxy_pass` (lines 326-327) and requires the
  `NUXT_PUBLIC_API_BASE` build arg (line 40).

## Specs merged

None: the change has no delta spec.

## Not delivered / deferred

- Out of scope by design: the API's CORS configuration stays; removing it belongs to whoever retires the last
  cross-origin caller. Custom domains remain the better long-term answer (the proposal's own open-questions
  note) and are not blocked by this change.
- The candidate `frontend` exclusion in the proposal was scoped to the cookie problem and later amended
  (2026-09-03); the frontend's same-origin work is archived as `frontend-same-origin-api`.

## Traceability

Mode openspec. Only proposal.md existed. Not verified in this pass: a live Safari session (the proposal's
verification of the proxy against a running container is not independently re-run here).

## Copy verification

Moved with `git mv` (no file rewritten). This report is additive.
