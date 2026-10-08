# Organization Settings Specification

## Purpose

Org-level administrative settings: organization profile (display identity) and
org-level webhook defaults used to prefill new Projects at creation time. Both
resolve implicitly from `TenantContext` — no organization id ever appears in a
request path, which removes the IDOR surface entirely.

**Assumption (product decision 2, resolved conservative):** `default_locale`
is DROPPED from scope. It was speculative (no confirmed project-creation
prefill requirement). Ship the profile name-only. Reversible: add the column
in a future change if a written requirement lands.

**Assumption (product decision 3, resolved conservative):** webhook defaults
are copy-on-create ONLY, never a runtime fallback. Changing an org default
NEVER retroactively affects existing projects. `webhooks-integration` →
"Secret resolution — Eloquent-only, never exposed" is untouched by this
change.

## Requirements

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

### Requirement: Organization Profile Is Name-Only

The editable profile MUST expose exactly `name`. `slug` MUST be read-only
(tenancy identifier, never editable). No `default_locale` or white-label
field (logo, colour, domain) exists on this resource.

#### Scenario: Admin updates the organization name

- GIVEN an authenticated `admin` of org A
- WHEN they `PATCH /api/organization` with `{"name": "New Name"}`
- THEN the response is `200` and `name` is updated
- AND `slug` is unchanged even if included in the request body

#### Scenario: Non-admin cannot write

- GIVEN an authenticated `operator` or `viewer` of org A
- WHEN they `PATCH /api/organization`
- THEN the response is `403`

### Requirement: Organization Webhook Defaults Are Copy-On-Create

`GET /api/organization` MUST include `default_webhook_url` and
`default_webhook_events`, never `default_webhook_secret` (hidden). A new
Project created after a default is set MUST copy the org's current defaults
into its own `webhook_url`/`webhook_secret`/`webhook_events` at creation time
only.

#### Scenario: New project copies org defaults at creation

- GIVEN org A has `default_webhook_url` and `default_webhook_events` set
- WHEN a new Project is created without explicit webhook fields
- THEN the Project's `webhook_url`/`webhook_events` equal the org defaults at
  that moment

#### Scenario: Changing the org default does not retarget existing projects

- GIVEN Project P was created when org A's default webhook URL was `X`
- WHEN org A's default is later changed to `Y`
- THEN Project P's `webhook_url` remains `X`
- AND C10 delivery resolution for P is unaffected

### Requirement: Webhook Secret Is Write-Only

`default_webhook_secret` MUST never be serialized in any response. `PATCH`
accepts a `default_webhook_secret` field to set a new value; omitting it
leaves the stored value unchanged; the field is never prefilled client-side.

#### Scenario: GET never returns the secret

- GIVEN org A has a `default_webhook_secret` set
- WHEN `GET /api/organization` is called
- THEN the response body contains no `default_webhook_secret` key

### Requirement: Cross-Tenant Isolation

An org can only ever read or write its own profile and webhook defaults; the
self-resolving route design makes cross-tenant access structurally
impossible rather than merely filtered.

#### Scenario: Two organizations never observe each other's data

- GIVEN org A and org B each have distinct `name` and webhook defaults
- WHEN org A calls `GET /api/organization`
- THEN the response contains only org A's values, never any field from org B

### Requirement: The organization logo is chosen through a framed, previewed upload field

The Appearance section MUST present the logo as a single upload field carrying an explicit
call to action, the required shape, and the accepted formats — not a bare file input.

Choosing a file MUST open a crop dialog before anything is queued for upload. The operator
MUST be able to pan and zoom within a fixed-ratio frame, and MUST confirm or cancel. Only a
confirmed crop becomes the file that is uploaded; cancelling MUST leave the previously
stored logo untouched.

The logo frame MUST be square (`1:1`) and MUST fit the whole source image inside that
square at minimum zoom rather than filling it. A wide logotype MUST NOT lose its ends to a
default framing.

After a confirmed crop the field MUST show the cropped result immediately, before any
network request, so that choosing a file always produces a visible change.

The client-side format filter on the file picker remains a convenience only. The server's
magic-byte verification, byte cap and dimension ceiling MUST be unchanged by this
requirement.

#### Scenario: Choosing a file opens the crop dialog

- GIVEN an admin in Settings → Appearance
- WHEN they choose an image file
- THEN a crop dialog opens showing that image inside a square frame
- AND nothing has been uploaded

#### Scenario: Cancelling the crop keeps the stored logo

- GIVEN an organization with a stored logo, and an open crop dialog over a newly chosen file
- WHEN the operator cancels
- THEN no upload is made and the stored logo is still shown

#### Scenario: A confirmed crop previews before it is saved

- GIVEN an open crop dialog
- WHEN the operator confirms
- THEN the field shows the cropped image immediately
- AND the file is uploaded when the form is submitted

#### Scenario: A wide logotype is padded, never trimmed

- GIVEN a source image far wider than it is tall
- WHEN the crop dialog opens at minimum zoom
- THEN the whole image is visible inside the square frame, padded rather than cropped

### Requirement: `logo_url` is resolvable from every app that renders it

Every API response carrying a logo URL MUST return an absolute URL. The backoffice, the
candidate frontend and email clients are all separate origins from the API, so a
root-relative path resolves against the wrong host and yields a broken image in all three.

This applies to the organization settings resource and to the participant resource's
`branding.logo_url`.

The field's type is unchanged: a nullable string, `null` when no logo is configured.

#### Scenario: The settings resource returns an absolute URL

- GIVEN an organization with a stored logo on the local disk
- WHEN the backoffice reads the organization
- THEN `logo_url` begins with the configured application URL and is fetchable from another origin

#### Scenario: No logo still means null

- GIVEN an organization with no logo configured
- WHEN the resource is serialised
- THEN `logo_url` is null, not an empty or partial URL
