# Delta for Organization Settings

## MODIFIED Requirements

### Requirement: Singular Self-Resolving Organization Route

The system MUST expose `GET /api/organization` and `PATCH /api/organization`
under `auth:api` + `TenantContext`, with no id in the path. The org resolves
exclusively from the tenant context (`TenantResolver::getOrgId()`): the
caller's own organization, or, for a superadmin, the acting organization.
It never resolves from a request-supplied id.

With no organization context (a superadmin with no acting organization):

- `GET /api/organization` MUST answer HTTP 200 `{"data": null}`. This is a
  deliberate decision: the backoffice shell reads the endpoint on every
  authenticated page to paint the brand colour and the settings page degrades
  on `null`.
- `PATCH /api/organization`, `POST /api/organization/logo` and
  `DELETE /api/organization/logo` MUST answer HTTP 409
  `organization_context_required` through the `org.context` middleware, never
  HTTP 404 or HTTP 403.

#### Scenario: Route never accepts a foreign organization id

- GIVEN an authenticated user of org A
- WHEN they call `GET /api/organization` or `PATCH /api/organization`
- THEN the response always reflects org A's data, regardless of any id/query
  parameter supplied
- AND no route variant accepting an `{organization}` path parameter exists

#### Scenario: A superadmin acting as an organization reads and updates exactly that organization

- GIVEN a superadmin has organization A as their acting organization
- WHEN they call `GET /api/organization` and `PATCH /api/organization` with `{"name": "New Name"}`
- THEN the first answers organization A's profile and the second updates organization A

#### Scenario: A superadmin acting as an organization manages its logo

- GIVEN the same superadmin
- WHEN they call `POST /api/organization/logo` with a valid image, then `DELETE /api/organization/logo`
- THEN both succeed against organization A's record

#### Scenario: Reading with no acting organization answers null, not 409

- GIVEN a superadmin with no acting organization
- WHEN they call `GET /api/organization`
- THEN the response is HTTP 200 with `data: null`

#### Scenario: Writing with no acting organization is refused with 409

- GIVEN a superadmin with no acting organization
- WHEN they call `PATCH /api/organization`, `POST /api/organization/logo` or `DELETE /api/organization/logo`
- THEN the response is HTTP 409 `organization_context_required`
- AND no organization row and no stored logo is changed

#### Scenario: An organization's admin can never act on another organization

- GIVEN an admin of organization B and an organization A
- WHEN the admin calls `PATCH /api/organization` or the logo endpoints
- THEN only organization B is read or modified; organization A is untouched
