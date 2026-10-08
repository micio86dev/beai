# M2M API Authentication Specification

## Purpose

Opaque API-key authentication for external machine clients (HR/LMS/ATS systems).
Delivers the `ApiClient` model, custom guard, org resolution, ability model, and
admin credential-management API that later business endpoints (C6/C10) sit behind.

## Non-Goals

- Backoffice user JWT auth (C2, done)
- Candidate magic-link SSO (C6)
- Webhook delivery, HMAC signing, retry (C10)
- Participant and business endpoints (C6/C10)
- Rate-limiting delivery (C13)
- Backoffice credential management UI (C11)

---

## Requirements

### Requirement: ApiClient Model and Schema

The system MUST provide an `ApiClient` Eloquent model that implements
`Illuminate\Contracts\Auth\Authenticatable` DIRECTLY via the
`Illuminate\Auth\Authenticatable` trait. It MUST NOT extend
`Illuminate\Foundation\Auth\User` (which imports `Authorizable::can()`, clashing
with the custom `can(string $ability): bool` ability helper). `ApiClient` is NOT a
`User` and NOT a `TenantModel`. The `api_clients` table MUST contain: `id`,
`organization_id` (FK → `organizations.id`, indexed), `name`, `key_hash` (unique),
`abilities` (JSONB), `is_active` (default `true`), `expires_at` (nullable,
`timestampTz`), `last_used_at` (nullable, `timestampTz`), `timestamps`. App and DB
both run UTC; `expires_at` comparison uses Carbon `now()` PHP-side via Eloquent.
All composite indexes MUST lead with `organization_id` (D22). The model MUST NOT
carry any global tenant scope so the auth guard can resolve it unscoped. `key_hash`
MUST be in `$hidden` and NOT mass-assignable. `abilities` MUST be cast to `array`.

#### Scenario: Schema — table structure

- GIVEN the `api_clients` migration is applied
- WHEN the table structure is inspected
- THEN it contains all required columns with the correct types
- AND `key_hash` has a unique index
- AND all composite indexes lead with `organization_id`
- AND `is_active` defaults to `true`

#### Scenario: Schema — ApiClient is not a TenantModel

- GIVEN an `ApiClient` record exists for Org A
- WHEN the guard queries `ApiClient` without any active tenant context
- THEN the record is returned (no global scope blocks the unscoped lookup)
- AND no `organization_id` filter is auto-applied by a global scope

---

### Requirement: Opaque API-Key Issuance

The system MUST generate API keys as 48-byte random values prefixed with `beai_live_`.
The raw key MUST be returned to the caller exactly once at creation time, as the field
`api_key` in the 201 response body. This is a transient injection in the `store`
response — the persistent `ApiClientResource` MUST NEVER include `api_key`, `key_hash`,
or any raw key value. The system MUST store only `hash('sha256', $rawKey)` in
`key_hash`. The raw key MUST NEVER be stored in the database, logged, or retrievable
through any API endpoint after creation.

#### Scenario: Key creation — raw key returned once as `api_key` in 201 envelope

- GIVEN an admin sends `POST /api/m2m/clients` with valid name and abilities
- WHEN the response is received
- THEN HTTP 201 is returned with the following envelope shape:
  ```json
  {
    "data": { "<ApiClientResource fields>" },
    "api_key": "beai_live_..."
  }
  ```
- AND `api_key` is a top-level sibling of the `data` wrapper (NOT nested inside `data`)
- AND the raw key starts with `beai_live_`
- AND the `key_hash` stored in DB equals `hash('sha256', rawKey)`
- AND `api_key` is ABSENT from the `index` response and all other endpoint responses
- AND subsequent `GET /api/m2m/clients` does NOT include `api_key`, `key_hash`, or any key value in its output

#### Scenario: Key creation — raw key never retrievable after creation

- GIVEN an `ApiClient` record exists in the database
- WHEN `GET /api/m2m/clients` is called
- THEN neither the raw key nor `key_hash` appear in any response item
- NOTE: There is no `GET /api/m2m/clients/{id}` show endpoint — the absence of a
  retrievable key is proven by `index` never returning the key, and `store` being
  the only moment it is exposed

#### Scenario: Key creation — raw key never logged

- GIVEN a valid `POST /api/m2m/clients` request is processed
- WHEN application logs are inspected (stdout, file, Redis)
- THEN no entry contains the raw key value

---

### Requirement: `api-m2m` Guard via `Auth::viaRequest`

The system MUST register the `api-m2m` guard via `Auth::viaRequest('api-m2m', fn(Request $r) => ...)`
in `AppServiceProvider::boot()`. This requires BOTH:

1. The `Auth::viaRequest('api-m2m', fn(Request $r) => ...)` call in `AppServiceProvider::boot()`.
2. A minimal entry in `config/auth.php` under `guards`: `'api-m2m' => ['driver' => 'api-m2m']`.

The config entry is required because `AuthManager::resolve()` reads
`config('auth.guards.api-m2m')` and throws `InvalidArgumentException` if null —
BEFORE it consults `customCreators`. The minimal entry satisfies this check; the
`driver` value `'api-m2m'` matches the key registered in `customCreators` by
`viaRequest`. No `provider` key is needed (RequestGuard takes a null provider).
No `api-clients` provider entry. No separate `Auth::extend` call. The
`auth:api-m2m` middleware alias resolves this guard by name once both the config
entry and the viaRequest registration are present.

The guard MUST authenticate requests by extracting the bearer token from
`Authorization: Bearer {rawKey}`, computing `hash('sha256', $rawKey)`, looking up
`ApiClient` by `key_hash` on the unique index (filtered active + non-expired via the
`active()` scope). The unique index lookup proves an exact hash match — no secondary
`hash_equals()` comparison is performed. The guard MUST check the Redis
`client_revoked:{id}` denylist after a successful DB lookup. The Redis check MUST be
exception-guarded: on Redis outage, it falls back to the DB `is_active` filter (which
the `active()` scope already applies) — NEVER fail-open. The raw key MUST NOT be logged.

#### Scenario: Guard registered via viaRequest — minimal config/auth.php entry present

- GIVEN `AppServiceProvider::boot()` has been executed
- WHEN `config('auth.guards')` is inspected
- THEN a minimal `api-m2m` entry EXISTS in `config/auth.php` under `guards`:
  `'api-m2m' => ['driver' => 'api-m2m']`
- AND the entry contains NO `provider` key and NO `api-clients` provider exists in
  `config('auth.providers')`
- AND `Auth::guard('api-m2m')` resolves correctly to the `RequestGuard` instance
  created by the `viaRequest` closure (the minimal config entry passes the
  `AuthManager::resolve()` null-check, and `customCreators['api-m2m']` dispatches
  to the registered closure)

#### Scenario: Valid key — successful authentication

- GIVEN an active, non-expired `ApiClient` exists with `key_hash = hash('sha256', K)`
- WHEN a request arrives with `Authorization: Bearer K`
- THEN the guard resolves the client to `$request->user('api-m2m')`
- AND the request proceeds to the next middleware

#### Scenario: Unknown key — 401

- GIVEN no `ApiClient` record matches `hash('sha256', presented_key)`
- WHEN the request reaches the `auth:api-m2m` guard
- THEN the response is HTTP 401
- AND no `ApiClient` is set on the request

#### Scenario: Inactive client — 401

- GIVEN an `ApiClient` exists with `is_active = false`
- WHEN a request is made with that client's valid key
- THEN the response is HTTP 401

#### Scenario: Expired client — 401

- GIVEN an `ApiClient` has `expires_at` in the past
- WHEN a request is made with that client's valid key
- THEN the response is HTTP 401

#### Scenario: Missing Authorization header — 401

- GIVEN a request to any M2M route arrives with no `Authorization` header
- WHEN the `auth:api-m2m` guard processes it
- THEN the response is HTTP 401

#### Scenario: Revoked client (Redis denylist) — 401

- GIVEN `ApiClient` with `id=X` has been revoked (key `client_revoked:X` set in Redis)
- WHEN a request is made with that client's raw key
- THEN the response is HTTP 401 (denylist checked before passing auth)

---

### Requirement: TenantContextM2m Middleware — Org Resolution (Fail-Closed)

A `TenantContextM2m` middleware MUST exist as a sibling to `TenantContext` (NOT a
subclass, NOT composed from it). It MUST read the resolved `ApiClient` from
`$request->user('api-m2m')`, then execute in order:
1. `$resolver->setBypass(false)` — clears any stale bypass flag BEFORE setting org context. This is an **intentional reversal** of C2 `TenantContext`'s ordering (C2 calls `setOrgId()` at line 48 THEN `setBypass(false)` at line 49). M2M deliberately reverses the sequence as a belt-and-suspenders hardening, NOT a mirror of C2.
2. `$resolver->setOrgId($orgId)` — establishes org context from the client record.
3. `setPermissionsTeamId($orgId)` — scopes Spatie checks (harmless: M2M clients have NO Spatie roles).

If the resolved client is `null`, or `organization_id` is `null`, the middleware MUST
return HTTP 401 immediately (fail-closed) without setting any resolver state. The org
MUST be resolved exclusively from the `ApiClient` record — never from any request
header, query parameter, or body field.

#### Scenario: Org resolved from client record

- GIVEN an authenticated `ApiClient` with `organization_id = 42`
- WHEN `TenantContextM2m` processes the request
- THEN `TenantResolver->getOrgId()` returns `42`
- AND `getPermissionsTeamId()` is `42`
- AND the request proceeds

#### Scenario: Tampered org input ignored

- GIVEN an authenticated `ApiClient` with `organization_id = 42`
- AND the request body contains `organization_id: 99`
- WHEN `TenantContextM2m` processes the request
- THEN `TenantResolver->getOrgId()` is still `42`
- AND no query sees org 99

#### Scenario: Null client — fail-closed 401

- GIVEN no `ApiClient` could be resolved (e.g. guard failed but middleware still runs)
- WHEN `TenantContextM2m` processes the request
- THEN HTTP 401 is returned
- AND no business logic executes

---

### Requirement: M2M Route Group Isolation — No Global TenantContext

M2M routes MUST call `->withoutMiddleware(TenantContext::class)` to explicitly strip
the globally-appended `TenantContext` (from `bootstrap/app.php` `appendToGroup('api',
TenantContext::class)`). The inline middleware stack for these routes MUST be
(in order): `auth:api-m2m` → `TenantContextM2m` → `SubstituteBindings`. The global
`TenantContext` MUST NOT be applied to M2M routes under any code path. This MUST be
proven by a test that verifies `TenantContext` is NOT invoked and org context is set
exclusively by `TenantContextM2m`. Admin credential-management routes (`/api/m2m/clients`)
rely on the global `api` group `TenantContext` only — `TenantContext` is NOT added
inline on them (no double-execution).

#### Scenario: M2M route does not use human TenantContext

- GIVEN a request arrives on `GET /api/m2m/whoami` with a valid M2M bearer key
- WHEN the middleware stack executes
- THEN `TenantContext` (human path) is NOT invoked
- AND `TenantContextM2m` IS invoked and sets the org context
- AND the response is HTTP 200 with correct org

#### Scenario: No silent org bypass via human TenantContext

- GIVEN an M2M route with the correct middleware stack
- AND `TenantContext` would receive `$request->user() = null` (machine caller)
- WHEN only the M2M group stack executes (not the global TenantContext)
- THEN org context is set by `TenantContextM2m` from the client record
- AND there is no code path where M2M business logic runs without org context set

#### Scenario: SubstituteBindings is last in the M2M stack

- GIVEN an M2M route with a route model binding
- WHEN the middleware stack executes
- THEN `auth:api-m2m` runs first, then `TenantContextM2m`, then `SubstituteBindings`
- AND route model binding resolves only after org context is established

---

### Requirement: Ability Model

`ApiClient` MUST carry a flat JSONB `abilities` array. Abilities MUST be stored
**lowercase-canonical** and MUST be validated at creation against the allowed base set:
`participants:create`, `participants:read`, `participants:retry`, `evaluations:read`,
`progress:read`, `projects:read`, `sso_link:generate`. Abilities outside this set MUST be rejected with
HTTP 422 at the controller/service layer. The system MUST provide a
`$client->can($ability)` helper that returns `true` if `$ability` is present using
strict `in_array` on the canonical `abilities` array. Abilities MUST be strictly
separate from Spatie human roles (`admin`/`operator`/`viewer`) and BEAI domain roles
(`ICO`/`FLL`/`MLL`/`BUL`/`SRX`). M2M clients MUST NOT have Spatie roles and MUST NOT
interact with the Spatie permission tables. The `CheckAbility` (`ability:{name}`)
middleware MUST sit BEFORE `SubstituteBindings` in the M2M stack to prevent a missing
ability from triggering a resource-existence lookup before the 403 is returned.
`CheckAbility` MUST be inserted into the application middleware priority list in
`bootstrap/app.php` IMMEDIATELY BEFORE `SubstituteBindings` via
`$middleware->prependToPriorityList(SubstituteBindings::class, CheckAbility::class)`,
so that per-route `ability:{name}` is guaranteed to run before route-model binding
regardless of declaration order. **Do NOT use `priority([...])`** — that method REPLACES
the entire default priority list and requires reproducing it in full to preserve all
other ordering guarantees. The `ability` alias MUST also be registered via
`$middleware->alias(['ability' => \App\Http\Middleware\CheckAbility::class])` in the
same `withMiddleware` closure — without it, per-route `ability:{name}` middleware
declarations will fail with "middleware not found" at runtime. `CheckAbility` is applied
PER-ROUTE on individual M2M business routes; `GET /api/m2m/whoami` requires NO ability.
(Previously: the base set did not include `participants:retry`.)

#### Scenario: Ability present — allowed

- GIVEN an `ApiClient` with `abilities = ["participants:read", "projects:read"]`
- WHEN the controller checks `$client->can('participants:read')`
- THEN it returns `true` and the request proceeds

#### Scenario: Ability absent — 403

- GIVEN an `ApiClient` with `abilities = ["participants:read"]` (does NOT have `participants:create`)
- WHEN a route protected by `ability:participants:create` is requested
- THEN the controller checks `$client->can('participants:create')` returns `false`
- AND the response is HTTP 403

#### Scenario: Unknown ability rejected at creation — 422

- GIVEN an admin sends `POST /api/m2m/clients` with `abilities: ["webhooks:send"]`
- WHEN the request is processed
- THEN HTTP 422 is returned
- AND no `ApiClient` record is created

#### Scenario: participants:retry is an accepted ability

- GIVEN an admin sends `POST /api/m2m/clients` with `abilities: ["participants:retry"]`
- WHEN the request is processed
- THEN the client is created with that ability stored lowercase-canonical

### Requirement: Revocation

Revocation MUST be immediate with no grace window. Revoking a client MUST set
`is_active = false` in DB (durable, authoritative) AND write the key
`client_revoked:{id}` to Redis (fast path). The guard MUST check the Redis denylist
after a successful DB lookup. The Redis check MUST be exception-guarded:
on Redis error or outage, the guard MUST fall back to the DB `is_active` check —
NEVER fail-open. A revoked client MUST receive HTTP 401 on its next request under
all conditions including Redis unavailability.

#### Scenario: Revoke — next request gets 401

- GIVEN an `ApiClient` is active and a valid key `K` is in use
- WHEN `DELETE /api/m2m/clients/{id}` is called by an admin
- THEN `is_active` is set to `false` in DB
- AND `client_revoked:{id}` is written to Redis
- AND the next request with key `K` returns HTTP 401

#### Scenario: Redis denylist checked at every request (fast path)

- GIVEN `client_revoked:{id}` exists in Redis
- WHEN a request with the corresponding key arrives
- THEN the guard returns 401 without needing to consult `is_active` in DB
- AND no business logic executes

#### Scenario: Redis-down fail-safe — revoked key still rejected

- GIVEN an `ApiClient` has been revoked (`is_active = false` in DB, `client_revoked:{id}` in Redis)
- AND the Redis connection is unavailable (connection error or timeout)
- WHEN a request with the revoked client's key arrives
- THEN the guard catches the Redis exception
- AND falls back to a FRESH DB re-query using the FULL `active()` scope
  (`is_active = true AND (expires_at IS NULL OR expires_at > now())`) — not merely
  `is_active`, and NOT the in-memory model instance loaded at guard init (which may be
  stale if revocation or expiry occurred concurrently after the initial `key_hash` lookup)
- AND the fresh DB query does NOT satisfy the `active()` scope (client is revoked)
- AND the response is HTTP 401
- AND the system NEVER authenticates a revoked or concurrently-expired client due to Redis being down

#### Scenario: Redis-down fail-safe — concurrently expired key still rejected

- GIVEN an `ApiClient` was active at the initial `key_hash` lookup but its `expires_at`
  passed concurrently between the DB lookup and the Redis check
- AND the Redis connection is unavailable
- WHEN the guard performs the Redis-down fallback re-query with the full `active()` scope
- THEN the re-query returns no matching record (the `expires_at > now()` condition fails)
- AND the response is HTTP 401
- NOTE: Using the full `active()` scope (not merely `is_active`) is what prevents
  a concurrently-expired key from slipping through the Redis-down window

#### Scenario: Revocation write ordering — DB committed before Redis

- GIVEN an admin calls `DELETE /api/m2m/clients/{id}` to revoke a client
- WHEN the revocation is processed
- THEN the DB write (`is_active = false`) is committed to PostgreSQL BEFORE the
  Redis denylist key `client_revoked:{id}` is written
- AND if the process crashes between the DB commit and the Redis write, the client
  is still rejected on the next request (DB `is_active = false` is authoritative,
  and the Redis-down fallback re-queries it fresh)

---

### Requirement: Credential Management Endpoints (Admin Only)

The system MUST expose exactly three credential management endpoints under
`/api/m2m/clients`, guarded by `auth:api` (human JWT) + `TenantContext` (via the
global `api` group — NOT added inline) + admin-only policy. `POST` and `GET`
additionally carry the `org.context` middleware:

| Endpoint | Description |
|---|---|
| `POST /api/m2m/clients` | Create client; returns `api_key` ONCE in 201 body |
| `GET /api/m2m/clients` | List org's clients; `api_key`/`key_hash` NEVER in output |
| `DELETE /api/m2m/clients/{id}` | Revoke; sets `is_active=false` + Redis denylist |

There is NO `GET /api/m2m/clients/{id}` show endpoint. The "key never retrievable
after creation" invariant is proven by the fact that `index` never returns the key
and no show endpoint exists.

An admin MUST only manage clients belonging to their own organization. A superadmin
acting as an organization manages that organization's clients exactly as its admin
would. Non-admin authenticated users (operator/viewer) MUST receive HTTP 403. An
admin from Org A MUST NOT be able to list or revoke clients from Org B.

With no organization context (a superadmin with no acting organization), `POST` and
`GET` MUST answer HTTP 409 `{"message": "organization_context_required"}` like every
other organization-required operation, and nothing is written. The
`no_client_selected` error code MUST NOT be returned by any endpoint.

#### Scenario: Admin creates client

- GIVEN a user with `admin` role in Org A sends `POST /api/m2m/clients`
- WHEN the request is processed
- THEN HTTP 201 is returned with the raw key in the response body (once only)
- AND an `ApiClient` record is created in DB with `organization_id = OrgA`

#### Scenario: Operator/viewer cannot create client — 403

- GIVEN a user with `operator` or `viewer` role sends `POST /api/m2m/clients`
- WHEN the request is processed
- THEN HTTP 403 is returned
- AND no `ApiClient` record is created

#### Scenario: List does not expose key or hash

- GIVEN an admin calls `GET /api/m2m/clients`
- WHEN the response is received
- THEN the response body contains client metadata (id, name, abilities, is_active, expires_at)
- AND neither `key_hash` nor any raw key value is present in any list item

#### Scenario: Cross-org — admin A cannot list Org B clients

- GIVEN admin user belongs to Org A
- AND `ApiClient` records exist for both Org A and Org B
- WHEN admin calls `GET /api/m2m/clients`
- THEN only Org A clients are returned
- AND Org B clients are not visible

#### Scenario: Cross-org — admin A cannot revoke Org B client

- GIVEN admin user belongs to Org A
- AND an `ApiClient` with `id=99` belongs to Org B
- WHEN admin calls `DELETE /api/m2m/clients/99`
- THEN HTTP 404 is returned (record not visible in org A scope)
- AND the Org B client is not revoked

#### Scenario: No show endpoint — GET /api/m2m/clients/{id} returns 404

- GIVEN a registered `ApiClient` with a known `id`
- WHEN a request is made to `GET /api/m2m/clients/{id}`
- THEN the response is HTTP 404 (no show route is registered)
- NOTE: This scenario catches any accidentally-added show route during the apply
  phase. The absence of a show endpoint is an intentional security property — the
  raw key is never retrievable after the initial 201 response.

#### Scenario: A superadmin acting as an organization lists and creates that organization's clients

- GIVEN a superadmin has organization A as their acting organization, and A has 2 clients while B has 3
- WHEN they call `GET /api/m2m/clients`, then `POST /api/m2m/clients` with a valid name and abilities
- THEN exactly A's 2 clients are listed, and the created client's `organization_id` is A

#### Scenario: A superadmin with no acting organization is refused on list and create

- GIVEN a superadmin with no acting organization
- WHEN they call `GET /api/m2m/clients` or `POST /api/m2m/clients`
- THEN the response is HTTP 409 `organization_context_required`
- AND no `ApiClient` row is created, and no other organization's clients are listed

---

### Requirement: Machine `whoami` Endpoint

The system MUST expose `GET /api/m2m/whoami` under the M2M route group (guarded by
`auth:api-m2m` + `TenantContextM2m`). The response MUST return
`{ client_id, organization_id, abilities }` and nothing else sensitive.

#### Scenario: Valid key — whoami returns correct payload

- GIVEN an authenticated `ApiClient` with `organization_id = 42` and `abilities = ["participants:read"]`
- WHEN `GET /api/m2m/whoami` is called
- THEN HTTP 200 is returned
- AND the body contains `client_id`, `organization_id: 42`, and `abilities: ["participants:read"]`
- AND no key, key_hash, or internal secret is in the response

#### Scenario: Invalid key on whoami — 401

- GIVEN a request to `GET /api/m2m/whoami` with an unknown bearer token
- WHEN the `auth:api-m2m` guard runs
- THEN HTTP 401 is returned
- AND no response body with client data is sent

---

### Requirement: Cross-Org Isolation for M2M Clients

An `ApiClient` belonging to Org A MUST NEVER read or act on data belonging to Org B.
All data queries executed in the context of a resolved M2M client MUST be scoped to
`organization_id = client.organization_id`. This isolation MUST be covered by
dedicated tests as part of the ~95% correctness zone.

#### Scenario: M2M client cannot access other org's data

- GIVEN `ApiClient` of Org A is authenticated and org context is set to Org A
- WHEN the client issues a request that queries a tenant-scoped resource
- THEN only Org A records are returned
- AND Org B records are not visible, not returned, and not modified

#### Scenario: Org always from client record, never from input

- GIVEN an authenticated `ApiClient` of Org A
- AND the request includes any field claiming a different org (header, body, query param)
- WHEN the request is processed
- THEN the effective `organization_id` is always Org A (from the client record)
- AND data from any other org is not accessible

---

### Requirement: Guard Non-Interchangeability

The `api-m2m` and `api` (human JWT) guards MUST be structurally incompatible — a token
valid for one guard MUST be rejected by the other with HTTP 401. A machine `api_key`
bearer token (`beai_live_...`) MUST be rejected by the human `auth:api` guard because it
is not a valid JWT. A human JWT bearer token MUST be rejected by the `auth:api-m2m`
guard because the SHA-256 hash of a JWT string will not match any stored `key_hash`.
Guard confusion MUST be proven by dedicated test scenarios.

#### Scenario: Machine api_key rejected by human auth:api guard

- GIVEN a valid machine `ApiClient` bearer token (`beai_live_...`) for Org A
- WHEN that token is presented to a human `auth:api`-protected route
  (e.g. `POST /api/m2m/clients`)
- THEN the JWT `api` guard cannot parse the opaque token as a JWT
- AND the response is HTTP 401
- AND no admin action is performed

#### Scenario: Human JWT rejected by auth:api-m2m guard

- GIVEN a valid human user JWT for an admin in Org A
- WHEN that JWT is presented as the bearer token to an `auth:api-m2m`-protected route
  (e.g. `GET /api/m2m/whoami`)
- THEN the `api-m2m` RequestGuard computes `hash('sha256', jwtString)` and finds no
  matching `ApiClient` record in the DB
- AND the response is HTTP 401
- AND no client data is returned
### Requirement: M2M Evaluation Retry Endpoint

`POST /api/m2m/participants/{id}/retry` MUST be reachable only by M2M clients authenticated on
the `api-m2m` guard and holding the `participants:retry` ability, enforced per-route by
`ability:participants:retry` BEFORE route-model binding (a client without the ability gets
HTTP 403 regardless of whether the id exists). The participant MUST be resolved scoped to the
client's own organization; an id belonging to another organization MUST return HTTP 404. The
endpoint MUST be a thin controller over the shared evaluation-retry authorization action
(`participant-sso`: Requirement: Evaluation Retry Authorization Action), so it shares every
refusal guard (409 `retry_already_consumed`, `not_completed`, `test_mode_participant`,
`evaluation_not_pending`, `project_inaccessible`, evaluated in that order), the link lifetime
rule (24 hours only when BEAI emails the retry link, 30 minutes when the link is only returned,
as for a placeholder address or a reusable-link visitor), the candidate email and the response
shape `{status, entry_url, expires_at, email_sent, competencies_reset}`. The request body MAY
carry an optional `reason` (max 500 characters; surrounding whitespace is trimmed and an empty
value is treated as absent), recorded in the interim `participant.retry_authorized` log and in
the `evaluation.retry_authorized` audit row with the client as actor. The audit row's `actor_id`
column is null for an M2M caller (the authenticated principal is an API client, not a user);
the client id travels in the row's payload.

The operation documents HTTP 403 (missing ability) in the exported OpenAPI contract.

This is the INTERNAL `/api/m2m` surface only. A public `/v1` retry endpoint, its SPEC entry,
its `ExposureCatalogue` (`T-EXPOSE-001`) entry and its SDK are explicitly DEFERRED to a
follow-up change; this change MUST NOT add any public or export field.

#### Scenario: Client with the ability authorizes a retry

- GIVEN an `ApiClient` with `participants:retry` and an eligible participant of its organization
- WHEN `POST /api/m2m/participants/{id}/retry` is called
- THEN HTTP 200 is returned with `status`, `entry_url`, `expires_at`, `email_sent` and
  `competencies_reset`
- AND the participant is `in_attesa` with `retry_attempt = true` on its Evaluation
- AND one `evaluation.retry_authorized` audit row names the client in its payload

#### Scenario: Client without the ability is denied before resolution

- GIVEN an `ApiClient` whose abilities do not include `participants:retry`
- WHEN the endpoint is called with an id that belongs to another organization
- THEN HTTP 403 is returned, not 404

#### Scenario: Cross-organization id is not found

- GIVEN an `ApiClient` of Org A with `participants:retry`
- WHEN the endpoint is called with a participant id belonging to Org B
- THEN HTTP 404 is returned

#### Scenario: Refusals surface as 409 with the shared reasons

- GIVEN an `ApiClient` with `participants:retry` and a participant whose Evaluation is `completed`
- WHEN the endpoint is called
- THEN HTTP 409 `reason: "evaluation_not_pending"` is returned

#### Scenario: Test-mode participant is refused

- GIVEN an `ApiClient` with `participants:retry` and a test-mode participant at `completato`
- WHEN the endpoint is called
- THEN HTTP 409 `reason: "test_mode_participant"` is returned

#### Scenario: Racing the backoffice operator

- GIVEN an operator and an M2M client authorize the same eligible participant simultaneously
- WHEN both are processed
- THEN exactly one succeeds and the other gets 409 `retry_already_consumed`

#### Scenario: No public exposure change

- GIVEN the OpenAPI export and the `ExposureCatalogue` after this change
- WHEN the exposure test (`T-EXPOSE-001`) runs
- THEN it passes without a new catalogue entry and no `/v1` retry path exists
