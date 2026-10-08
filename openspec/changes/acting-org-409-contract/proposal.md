# Proposal: Acting-Organization 409 Contract

## Intent

A superadmin has `users.organization_id = NULL` and works "as" a client through the acting-organization context
(`TenantResolver::getOrgId()`, written by `TenantContext` from `ActingOrganization`). Commit `c9096df` (and `263dca5`
for the M2M credential controller) already fixed the user-visible bugs by reading the resolver. What was left, and is
the subject of this change, is the contract of the state "superadmin with NO acting organization":

1. Operations that need an organization to write into answer a different, illegible error on each route
   (`POST /api/projects` 422/404, `PATCH /api/organization` and the logo upload/delete 404/403,
   `POST /api/m2m/clients` a bespoke `{"error":"no_client_selected"}` 409, `GET /api/m2m/clients` an empty list that
   reads as "this client has no keys", `POST /api/users/{user}/activate|deactivate` a 404). The platform already has one legible answer for this state: the
   `org.context` middleware (`RequireOrganizationContext`) answering `409 organization_context_required`.
2. `UserAbilities::for()` still derives the organization from `$user->organization_id`, so a superadmin with no
   acting organization is told they may use org-scoped surfaces that cannot work.
3. Nothing stops a new `$user->organization_id` read under `app/Http` from reintroducing the class of defect
   `c9096df` repaired.

## Scope

### In scope

1. **409 `organization_context_required`** through the existing `org.context` middleware (mechanism:
   `TenantResolver::getOrgId()`), added to: `POST /api/projects`, `PATCH /api/organization`,
   `POST /api/organization/logo`, `DELETE /api/organization/logo`, `POST /api/m2m/clients`, `GET /api/m2m/clients`, and (decision taken during apply, to close the authorization-matrix
   record KQ-2 completely) `POST /api/users/{user}/activate` and `POST /api/users/{user}/deactivate`.
2. **`GET /api/organization` keeps answering `200 {"data": null}`** with no acting organization. This is a decision,
   not an omission: the backoffice shell calls it on every authenticated page to paint the brand colour and the
   settings page degrades on `null`. Documented in the spec so it stops reading as an inconsistency.
3. **M2M reconciliation**: `ApiClientController` stops answering `{"error":"no_client_selected"}` (409) on create
   and an empty collection on list. Both go through the middleware and answer `{"message":"organization_context_required"}`.
   **This changes an error code and the list behaviour of a non-public route**; the only consumer found is the
   generated TypeScript client (`no_client_selected` appears in `types/api.ts` of both Nuxt apps and in no hand-written
   code).
4. **Ability suppression (Part B)** in `UserAbilities::for()`: for a caller with no organization context, the
   org-scoped groups `organization`, `apiClients`, `projects` and `participants` answer `false`; the platform-scope
   groups are untouched. The organization is the effective one (own column first, then the resolver), so a
   superadmin acting as a client gets exactly the answers an admin of that client gets.
5. **Arch guard** (`tests/Arch/Tenancy`): no read of `->organization_id` on a user receiver under `app/Http`
   except an explicit, justified allowlist with an occurrence budget.
6. **Contracts**: re-export `openapi.json` (Postgres), sync both consumers (`frontend`, `backoffice`: the wrapper
   parity gate requires the three copies to be identical) and regenerate their typed clients. The public
   `openapi.v1.json` must not change; this is asserted, not assumed.

### Deviation from the archived design (read this)

The archived change `superadmin-acting-organization-context` proposed suppressing SEVEN groups
(`organization`, `apiClients`, `users`, `llmCredentials`, `projects`, `participants`, `avatarTemplates`). Against the
code as it is today that would be wrong for three of them, so this change suppresses FOUR:

| Group | Decision | Evidence |
|---|---|---|
| `organization`, `apiClients`, `projects`, `participants` | suppress | org-scoped data; the backoffice already hides every consumer in this state (`nav-visibility.ts` `scope: 'client'`, settings tabs `needsOrganization` / `requiresTenant`) |
| `users` | keep | `/settings` is guarded by `users.viewAny` (`03.abilities.global.ts`, `nav-items.ts`) and, with no client selected, hosts the PLATFORM user list (`usersVariant = 'platform'`) plus the platform tabs; suppressing it would lock the superadmin out of Settings entirely |
| `llmCredentials` | keep | credentials are platform rows (RATIFIED 2026-09-14); the settings tab is deliberately not `requiresTenant` ("the all-clients view is exactly where a superadmin manages them") |
| `avatarTemplates` | keep | `/avatar-templates` and `/platform-templates` are `scope: 'platform'` nav entries; the page already states "pick a client first" for its create action; `manageGlobal` is platform-scope |

The `EffectiveOrganization` accessor of the archived design is NOT built. The codebase pattern is the resolver plus
the `org.context` middleware, and a second accessor would be a second source of truth.

### Out of scope

- Scoping `ApiClientController::destroy` route binding for acting superadmins and restricting
  `AvatarTemplatePolicy::viewAny`/`view` (carried over by the archive report, separate permission decisions).
- Releases, tags, SDK regeneration for the public spec (the public spec must not change).

## Capabilities

### Modified Capabilities

- `tenancy`: organization-required writes refuse legibly; arch guard against ambient `organization_id` reads.
- `organization-settings`: the organization route resolves from the resolver; the no-context behaviour per verb.
- `project-config`: project creation requires an organization context.
- `m2m-auth`: credential management requires an organization context; error-code reconciliation.
- `superadmin-clients-console`: org-scoped abilities are suppressed with no acting organization.
- `admin-backoffice`: documents that navigation and route guards need no client change (platform sections stay reachable).

`user-management` is unchanged: `UserController::requireOrgId()` already answers 409 `organization_context_required`
from the resolver and that behaviour is already in the canonical spec.

## Approach

Tests first for every route (RED: today's 422/404/403/empty list), then add `org.context` to the routes (GREEN), prove
each test with a mutation (remove the middleware from one route, see its test fail). Then the ability map, then the
arch guard (proved RED with a temporary violation), then the contract regeneration.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| A backoffice screen relied on the empty list from `GET /api/m2m/clients` | Low | the API-keys tab is dropped in this state (`requiresTenant`); the unit suite and `codegen:check` run |
| Suppression hides a platform surface | Med | only four groups, each with evidence above; per-group assertion that `users`, `llmCredentials`, `avatarTemplates`, `clients`, `platformSettings`, `catalogue` are unchanged |
| The arch regex misses a receiver spelling | Med | matcher self-test with positive and negative fixtures; occurrence-budget allowlist |
| A generated client drifts | Low | `codegen:check`, `scripts/verify-openapi-parity.sh`, fresh export diff |

## Rollback Plan

Revert the merge of the feature branches (api, backoffice, frontend, wrapper). No migration, no data change. The 409
is a new response on paths that answered 422/404/403/empty; reverting restores them.

## Success Criteria

- [ ] With no acting organization, the eight operations answer 409 `organization_context_required` and write nothing.
- [ ] `GET /api/organization` still answers `200 {"data": null}`.
- [ ] With an acting organization, a superadmin behaves exactly as an admin of that organization; org A's operator can
      never see or act on org B (tests for both).
- [ ] `/auth/me` for a superadmin with no acting organization has `organization`, `apiClients`, `projects`,
      `participants` all `false`, and every other group exactly as before.
- [ ] The arch guard fails on a new violation (observed RED) and passes on the tree.
- [ ] `openapi.json` is fresh, the three copies are identical, `openapi.v1.json` is unchanged.
