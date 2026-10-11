# Archive Report: superadmin-acting-organization-context

**Change**: superadmin-acting-organization-context
**Archived to**: `openspec/changes/archive/2026-10-08-superadmin-acting-organization-context/`
**Archive date**: 2026-10-08
**Status**: CLOSED. THE USER-VISIBLE BUG IS FIXED, BUT BY A DIFFERENT MECHANISM THAN DESIGNED; THE DESIGNED ACCESSOR,
THE 409 CONTRACT, THE ABILITY SUPPRESSION AND THE ARCH GUARD WERE NEVER DELIVERED. NO SPEC WAS MERGED.
No verify-report existed; verification was not run as an SDD phase and no test suite was run by this archive.

## Summary

A superadmin acting as a client (`users.organization_id = null`, acting org held by `ActingOrganization`) hit 404/403/
422/500 on API keys, projects and organization settings because code read `$user->organization_id`. Observed on disk at
archive time:

- **Delivered (the bug fix)**: api commit `c9096df` (2026-09-17, "fix(tenancy): resolve org from TenantResolver, not
  the user column") touched `OrganizationController`, `OrganizationLogoController`, `ProjectController`,
  `StoreProjectRequest`, `UpdateOrganizationRequest`, `UpdateProjectRequest`, with tests in
  `tests/Feature/C4/ProjectCrudTest.php` and `tests/Feature/Superadmin/ActingOrganizationTest.php`. Commit `263dca5`
  covered the M2M API-client controller (`api/app/Http/Controllers/M2m/ApiClientController.php` resolves through
  `TenantResolver::getOrgId()`), tested by `api/tests/Feature/C5/ApiClientActingSuperadminTest.php`. A superadmin
  acting as client A now lists, creates and revokes A's keys, creates projects and reads/updates A's settings.
- **Not delivered (the design)**: `App\Support\Tenancy\EffectiveOrganization` was never created. Only
  `api/app/Support/Tenancy/ActingOrganization.php` exists. The tests named in the tasks
  (`tests/Unit/Support/Tenancy/EffectiveOrganizationTest.php`, `tests/Feature/C5/ApiClientActingOrganizationTest.php`)
  do not exist.

## Specs merged

None. The seven delta specs were read against the code and none was merged, because each states as normative either
a class that does not exist (`EffectiveOrganization`), the `409 organization_context_required` contract for states
that answer something else, or the ability suppression that is not implemented:

| Capability | Requirement (delta) | Why not merged |
|---|---|---|
| tenancy | Effective Organization Accessor Replaces Ambient User Reads | `EffectiveOrganization` does not exist |
| tenancy | No New Ambient organization_id Reads Under App\Http | no arch guard exists (follow-up 3) |
| tenancy | Superadmin Test Identity Fixture Discipline | a test convention; per-endpoint coverage not verified, not confirmed |
| m2m-auth | Credential Management Resolves Organization Via EffectiveOrganization | names `EffectiveOrganization`; no-client `store` answers 409 `{"error":"no_client_selected"}`, `index` answers an empty list (not `organization_context_required`) |
| organization-settings | Organization Read/Write Resolves Via EffectiveOrganization, Not findOrFail(null) | names `EffectiveOrganization`; with no org `GET` answers 200 `data: null` and `PATCH`/logo still `findOrFail(null)` (404), not 409 |
| project-config | Project Creation And Update Resolve Organization Via EffectiveOrganization | names `EffectiveOrganization`; `POST /api/projects` (`api/routes/api.php:360`, `apiResource`) has no `org.context` middleware, so no 409 |
| user-management | requireOrgId Resolves Via EffectiveOrganization | the behaviour IS present (`UserController::requireOrgId()` aborts 409 `organization_context_required` when `TenantResolver::getOrgId()` is null) but the requirement mandates `EffectiveOrganization::require()`, which does not exist; the 409-for-missing-org behaviour is already in the canonical `user-management` spec (merged from `platform-user-management`) |
| superadmin-clients-console | Org-Scoped Abilities Suppressed With No Acting Organization | not implemented: `UserAbilities.php:119` still `Organization::find($user->organization_id)` and `:144` `$orgId = $user->organization_id` |
| admin-backoffice | Org-Scoped Navigation And Routes Are Absent With No Acting Organization | depends on the unimplemented ability suppression |

The unmodified deltas are preserved in this folder under `specs/`. They can be re-submitted after the follow-ups
below, with the `EffectiveOrganization` wording replaced by whatever mechanism is actually built (the existing
`TenantResolver`/`RequireOrganizationContext` middleware is the likely one).

## Checkbox corrections (tasks.md)

Only checkboxes and trailing notes were edited; line count unchanged (114 before and after). Tasks 1.1, 1.2, 1.3,
1.4, 1.5 and 1.7 were checked and are now UNCHECKED with `NOT DONE: ... delivered through TenantResolver instead
(c9096df / 263dca5)`: they name `EffectiveOrganization`, its tests and `requireId()`, none of which exist. Task 1.6
(record the `ApiClientController::destroy` follow-up, no code) stays checked. Nothing was newly checked; every task
in PR 2-5 and the two "follow-ups from the PR 1 bounded review" remain unchecked and unannotated. Note that PR 2
(project composition) and PR 3 (organization read/write/logo) are PARTIALLY realized by `c9096df` through
`TenantResolver` (acting-org reads, writes and slug/avatar-template validation), but not in the form the tasks
specify; only the 409 contract and the accessor are missing.

## Follow-up (not delivered)

These change the API error contract, so they need OpenAPI re-export, SDK regeneration (ts, php, python) and a
release (a MINOR bump, as the original Git Flow section said for the ability semantics). They were NOT implemented by
this archive.

1. **409 `organization_context_required` for the no-acting-org states.** Today: `POST /api/projects` has no
   `org.context` middleware (`api/routes/api.php:360`) and answers 422/403; `PATCH /api/organization` and the logo
   `POST`/`DELETE` call `Organization::findOrFail(getOrgId())` and answer 404/403. Decide separately whether
   `GET /api/organization` keeps answering 200 `data: null` (`OrganizationController.php:34-46`, an intentional
   choice documented there) or moves to 409.
2. **Part B: ability suppression in `UserAbilities::for()`.** For a superadmin with no acting organization the groups
   `organization`, `apiClients`, `users`, `llmCredentials`, `projects`, `participants`, `avatarTemplates` should
   answer `false` while `clients.viewAny` and `platformSettings.viewAny` stay `true`; `UserAbilities.php:119` and
   `:144` still read `$user->organization_id`. The backoffice then needs no client change (nav and route guards
   already key off these abilities), per the `admin-backoffice` delta.
3. **Arch guard against new `$user->organization_id` reads under `app/Http`.** The allowlist will need more than the
   three entries in the delta: `app/Providers/AppServiceProvider.php:287`, `SendUserInvitationJob`,
   `SendPasswordResetLinkJob` and the Console commands (these read the column legitimately, outside the request
   path), plus the two named in the delta (`ResetPasswordController`, `PlatformUserController`'s explicit
   `organization_id = null` write). Use an occurrence-budget allowlist, as the design proposed.
4. **Reconcile `no_client_selected` vs `organization_context_required` in `ApiClientController`.** The M2M
   controller answers `{"error":"no_client_selected"}` with 409 where every other surface answers
   `organization_context_required`; pick one code (changing it is an API contract change, see above).

Also carried over from `tasks.md`: scope `ApiClientController::destroy` route binding for acting superadmins (D6),
and restrict `AvatarTemplatePolicy::viewAny`/`view` to superadmin.

## Traceability

Mode openspec. Artifacts read from the filesystem: proposal.md, design.md, tasks.md, seven delta specs. Absent:
verify-report, apply-progress, exploration.md.

## Copy verification

Moved with `git mv`. Original file counts and line counts are identical after the move (design.md 295, proposal.md
175, tasks.md 114, and the seven delta specs 33/48/58/42/52/78/30). The only edit was the `tasks.md` checkbox and
note change described above. This report is additive.
