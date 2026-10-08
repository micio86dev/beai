# Delta for Tenancy & Multi-Org Isolation

## ADDED Requirements

### Requirement: Organization-Required Operations Refuse Legibly Without An Organization Context

An HTTP operation that needs an organization to read from or write into, and that is reachable by a caller who may
have none (a superadmin with no acting organization), MUST answer HTTP 409 with the machine-readable body
`{"message": "organization_context_required"}` through the `org.context` route middleware
(`RequireOrganizationContext`). The middleware MUST decide from `TenantResolver::getOrgId()` and never from
`$user->organization_id`, and it MUST run before validation, authorization and any query. A refusal MUST NOT write
anything and MUST NOT be reported as 404, 403, 422 or 500, and a list endpoint MUST NOT answer an empty list for
this state, because an empty list reads as "this client has none".

The operations covered today are `POST /api/projects`, `PATCH /api/organization`, `POST /api/organization/logo`,
`DELETE /api/organization/logo`, `POST /api/m2m/clients` and `GET /api/m2m/clients`, in addition to those that
already carried the middleware.

#### Scenario: A superadmin with no acting organization is refused before anything is written

- GIVEN a superadmin (`organization_id = null`, `is_superadmin = true`) with no acting organization
- WHEN they call any operation listed above
- THEN the response is HTTP 409 with `message = organization_context_required`
- AND no row is created, updated or deleted

#### Scenario: A superadmin acting as an organization is served like that organization's admin

- GIVEN the same superadmin has organization A as their acting organization
- WHEN they call the same operation
- THEN it is served against organization A exactly as for an admin of organization A

#### Scenario: Another organization's member can never reach the acting organization's data

- GIVEN an operator of organization B and a superadmin acting as organization A
- WHEN the operator calls the same operations
- THEN every row read or written belongs to organization B, and nothing of organization A is visible or modifiable

### Requirement: No New Ambient organization_id Reads Under App\Http

An architecture test MUST fail when a class under `app/Http` reads `->organization_id` from a user receiver
(a variable whose name contains `user`, `$request->user()`, `auth()->user()`, `Auth::user()`), except for a named
allowlist in which every entry states why the read is legitimate and carries an occurrence budget, so an extra read
in an allowlisted file also fails. The matcher MUST be proved by a self-test with positive and negative fixtures.

The allowlist is limited to the reads that are not a request-tenant decision: `TenantContext` (the resolver's own
source of truth), `ResetPasswordController` (unauthenticated; the organization of the SUBJECT of the reset) and
`PlatformUserController` (a write of `organization_id = null` that defines a platform user).

#### Scenario: A new violation is caught

- GIVEN a class under `app/Http` that reads `$user->organization_id` to scope a query, validate or create
- WHEN the architecture suite runs
- THEN it fails and names the file and the line

#### Scenario: The allowlist stays narrow

- GIVEN the allowlisted files
- WHEN one of them gains an additional read beyond its budget
- THEN the suite fails

#### Scenario: Reads outside app/Http are not in scope

- GIVEN `AppServiceProvider`, the queued jobs and the Console commands read the column
- WHEN the suite runs
- THEN they are not inspected (they run outside the request tenant path)
