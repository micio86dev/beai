# Delta for M2M API Authentication

## MODIFIED Requirements

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
other organization-required operation, and nothing is written. Previously `POST`
answered `{"error": "no_client_selected"}` and `GET` an empty list; **the
`no_client_selected` error code is removed** (an error-code change on a
non-public route; the only consumer was the generated TypeScript client).

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
