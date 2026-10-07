# Archive Report: platform-user-management

**Change**: platform-user-management
**Archived to**: `openspec/changes/archive/2026-10-08-platform-user-management/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED WITH ONE DEFERRED TASK; THE ONE REQUIREMENT SKIPPED AT ARCHIVE TIME WAS MERGED AFTERWARDS. No verify-report existed;
verification was not run as an SDD phase. `tasks.md` has 27 tasks checked and 1 unchecked (6.4), and records the
observed runs in its `## Verification` section (2946 api tests, 2939 passed, 7 skipped, 0 failed; 1410 unit
tests green; coverage 94.3% lines).

## Summary

Superadmins manage BEAI's own people (platform users) from the all-clients scope, with a last-active-superadmin
guard, and the backoffice Users section follows the selected scope. Observed on disk at archive time:

- api commit `f5bd5e6` ("feat(users): manage BEAI's own people from the all-clients scope"), then `4b0cc46` and
  `453dd57`; all on api `develop`. Routes `admin/platform-users` (index, store, update) are in
  `api/routes/api.php:422-424`; `PlatformUserController`, `PlatformUserGuards`, `PlatformUserReader` and
  `PlatformUserCrudTest` exist.
- backoffice commit `db40915` ("feat(settings): Users and roles follows the selected scope", on backoffice
  `develop`); `backoffice/app/composables/usePlatformUsers.ts` exists.
- The 409 behaviour of the MODIFIED requirement is present in code: `api/app/Http/Controllers/Api/UserController.php`
  documents and returns a 409 with a machine code for a missing organization (docblock at line 267).

## Specs merged

Composition used `gentle-ai sdd-archive-compose`. Both merges are pure additions (108 inserted lines, 0 deleted).

| Capability | Requirements before -> after | Delta |
|---|---|---|
| superadmin-clients-console | 11 -> 13 | 2 added, 1 MODIFIED skipped (see below) |
| user-management | 11 -> 12 | 1 added |

### Not merged at archive time

- **superadmin-clients-console**: the delta's `## MODIFIED Requirements` block, "The org-scoped user surface
  refuses a missing organization legibly" (`POST /api/users` without an organization context answers 409 with a
  machine-readable code; the org-scoped surface keeps excluding superadmins), was NOT merged. The compose command
  refused it (`no canonical requirement named "The org-scoped user surface refuses a missing organization
  legibly"`) and no similarly named requirement exists in `superadmin-clients-console`, `user-management` or
  `tenancy`. The two ADDED requirements were composed from a scratch copy of the delta with that block removed
  (scratch file only; the archived delta in this folder is the unmodified original). The behaviour itself is
  implemented (see above); only the canonical spec lacks it. Where it belongs (as ADDED to `user-management` or
  `superadmin-clients-console`) is a spec decision for a human.

  **Post-hoc merge (2026-10-08).** The requirement was merged into `openspec/specs/user-management/spec.md` as
  ADDED (+25 lines, 0 deleted; `user-management` 12 -> 13 requirements), composed with `gentle-ai
  sdd-archive-compose` from a scratch delta holding only that block under `## ADDED Requirements`. Its text was
  checked against code: `UserController::requireOrgId()` aborts 409 `organization_context_required` when
  `TenantResolver::getOrgId()` is null, `UpdateUserRequest` does the same, `UserAdminReader` filters
  `is_superadmin = false` unconditionally, and `UserCrudTest` covers both scenarios. It was placed in
  `user-management` (the capability that owns the `/api/users` surface), not `superadmin-clients-console`.

## Not delivered / deferred

- **Task 6.4 (left unchecked)**: E2E that the Users section switches with the client selection. NOT DONE. It
  needs a superadmin Playwright fixture with a live client switch, which no E2E spec sets up today; unit coverage
  pins the resolution rule and its fail-closed branch.
- Follow-up recorded in `tasks.md`, not in this change: a lesser BEAI role (clients console without platform
  settings). Nothing specifies it and it needs a new authorization concept.

## Traceability

Mode openspec. Artifacts read from the filesystem: proposal.md, design.md, tasks.md, two delta specs. Absent:
verify-report, apply-progress, exploration.md.

## Copy verification

Moved with `git mv` (no file rewritten). This report is additive.
