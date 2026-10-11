# Archive Report: acting-org-409-contract

**Change**: acting-org-409-contract
**Archived to**: `openspec/changes/archive/2026-10-08-acting-org-409-contract/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED. All tasks in `tasks.md` are checked (1.1-6.3). No `design.md`, `apply-progress.md`
or verify-report existed for this change; verification was not run as an SDD phase and no test suite was run by
this archive.

## Summary

The contract of the state "superadmin with NO acting organization" is now one legible answer. Operations that need an
organization to act on answer `409 {"message": "organization_context_required"}` through the existing `org.context`
middleware (`RequireOrganizationContext`), `UserAbilities::for()` suppresses the org-scoped ability groups for that
state, and an architecture test stops a new ambient `$user->organization_id` read from appearing under `app/Http`.

## What was delivered

| Repo | Pull request merge | Into |
|---|---|---|
| api | PR #143, merge `e0c30d3` | `develop` |
| backoffice | PR #83, merge `05dfea9` | `develop` |
| frontend | PR #66, merge `99523a3` | `develop` |

- api commits: `299f559` (409 `organization_context_required` when no organization is in context), `cb33968`
  (suppress org-scoped abilities), `e6289f1` (architecture guard against new user `organization_id` reads under
  `app/Http`), `b733222` (publish the 409 responses in `openapi.json`), `5fb4097` (project-creation test expects the
  409), `d86f683` (type the acting organization on the ability subject for PHPStan).
- backoffice `22c0f1e` and frontend `891652f`: sync of `openapi.json` and the typed client with the 409 contract
  (task 5.3). Task 3.3 records that no client logic change was needed.
- Wrapper: proposal, tasks and the apply record (`89fb5d8`, `0721aa1`), the tenancy wording (`0e5b527`) and the review
  fixes (`a535be9`).

## Deliberate decisions

- **`GET /api/organization` keeps answering `200 {"data": null}`** with no acting organization. The backoffice shell
  reads it on every authenticated page to paint the brand colour and the settings page degrades on `null`. It is the
  only organization-required read that does not refuse, and the specs now say so.
- **4 of the 7 ability groups are suppressed**: `organization`, `apiClients`, `projects`, `participants`. The groups
  `users`, `llmCredentials` and `avatarTemplates` (plus `clients`, `platformSettings`, `catalogue`) are NOT suppressed:
  with no organization context they are platform scope, and `users.viewAny` is the ability that guards `/settings`.
  Suppression lives in `UserAbilities` because `Gate::before` grants a superadmin every policy before a policy body runs.
- **`no_client_selected` was removed as an error-code change**: `POST /api/m2m/clients` no longer answers its bespoke
  409; both `POST` and `GET /api/m2m/clients` answer `organization_context_required`. The old `GET` empty list is gone.
- **Activate and deactivate were included** (`POST /api/users/{user}/activate|deactivate`), a decision taken during
  apply to close authorization-matrix record KQ-2 completely. `POST /api/users` and `PATCH /api/users/{user}` give the
  same 409 through `UserController::requireOrgId()`, not through the middleware.

## Specs merged

Composition used `gentle-ai sdd-archive-compose` (exit 0 for all six). Requirements before -> after:

| Capability | Before -> after | Delta applied |
|---|---|---|
| admin-backoffice | 83 -> 84 | 1 added (navigation and route guards follow the suppressed abilities) |
| m2m-auth | 12 -> 12 | 1 modified (Credential Management Endpoints (Admin Only)) |
| organization-settings | 7 -> 7 | 1 modified (Singular Self-Resolving Organization Route) |
| project-config | 17 -> 18 | 1 added (project creation requires an organization context) |
| superadmin-clients-console | 13 -> 14 | 1 added (org-scoped abilities are suppressed with no acting organization) |
| tenancy | 23 -> 25 | 2 added (organization-required operations refuse legibly; no new ambient `organization_id` reads under `App\Http`) |

Totals: 6 delta files, 7 added, 2 modified, 0 skipped. No ADDED title already existed.

Notes on the merge:

- The composer drops the blank line (and, in `m2m-auth`, the `---` separator) that follows a replaced or appended
  requirement. They were restored by hand so every `### Requirement:` heading is preceded by a blank line, and the
  `---` between the modified `m2m-auth` requirement and "Machine `whoami` Endpoint" is kept as in the previous text.
  No requirement text was altered by that step.
- Each delta requirement block was checked to be present verbatim (substring) in the merged main spec and its title
  to occur exactly once, with one exception: the scenario named in the last bullet below, reworded after the merge.
- `admin-backoffice/spec.md` already contained five duplicated scenario titles before this archive (for example "A
  viewer never sees the action"); none of them come from this change and they were left alone.
- The merged `superadmin-clients-console` scenario "An org-bound user is never subject to suppression" was merged
  verbatim from the delta, whose last line read "the abilities are exactly those they had before this change". That
  is change-history wording, so in the MAIN spec it was reworded (commit `b2b3f06`) to "no ability group is
  suppressed and the abilities are computed from their role alone". The archived delta intentionally keeps the
  original text, so this one block no longer matches the main spec verbatim.

### Not merged - needs human review

None. The composer refused nothing.

## Carried over, out of scope

- `ApiClientController::destroy` route-binding scoping.
- `AvatarTemplatePolicy` `viewAny` / `view` restriction.
- `OrganizationLogoController::store` has no published docblock for its 409.
- The `ApiClientController::organizationInContext()` `LogicException` branch is untested.
- The activate/deactivate 409 message body is not asserted in `ActingOrganizationContractTest`.

## Review record

- **api commits**: native review APPROVED (reliability lens) with 2 non-blocking warnings: the
  `organizationInContext()` `LogicException` branch is untested, and the activate/deactivate 409 message body is not
  asserted in `ActingOrganizationContractTest`. Both are listed above.
- **Wrapper docs commits**: native review ran 4 lenses; its risk assessment came out `high`, a false positive caused
  by the filename "m2m-auth". The transaction ended `escalated`. One lens opened a bounded correction (the tenancy
  requirement wording) and the targeted validator rejected the first correction, because the opening clause named one
  exception while the text disclosed two. The wording was then fixed properly, together with six further
  independent-review warnings, in commit `a535be9`, and `gga` PASSED on the final text. No native approval exists for
  the docs commits.

## Traceability

Mode openspec. Artifacts read from the filesystem: `proposal.md`, `tasks.md` and six delta specs. Absent: `design.md`,
`apply-progress.md`, verify-report.

## Copy verification

Moved with `git mv`. File counts and line counts of the change folder (excluding this report) are identical before
and after: `proposal.md` 115, `tasks.md` 66, and the six delta specs 31/89/61/30/42/71 (8 files). This report is
additive.
