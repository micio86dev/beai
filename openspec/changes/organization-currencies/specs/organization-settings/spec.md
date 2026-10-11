# Delta for Organization Settings

> Proposed 2026-10-11. The MODIFIED requirement keeps its main-spec title and carries its full new text with the change
> marked "(Previously: ...)". Nothing is REMOVED.

## MODIFIED Requirements

### Requirement: Organization Profile Is Name-Only

The editable profile MUST expose `name` and `currency_code`. `slug` MUST be read-only (tenancy identifier, never
editable). Branding (`primary_color` through this route, the logo through `POST /api/organization/logo`) is specified by
its own requirements. No `default_locale` or domain field exists on this resource. `currency_code` selects how money is
DISPLAYED for the organization; it never changes how any amount is computed or stored.
(Previously: "MUST expose exactly `name`" and "No ... white-label field (logo, colour, domain) exists on this
resource". Branding had already been added by the white-label reopening (CLAUDE.md ruling 9) without amending this text;
this change adds `currency_code` and records the branding fields that already exist.)

#### Scenario: Admin updates the organization name

- GIVEN an authenticated `admin` of org A
- WHEN they `PATCH /api/organization` with `{"name": "New Name"}`
- THEN the response is `200` and `name` is updated
- AND `slug` is unchanged even if included in the request body

#### Scenario: Non-admin cannot write

- GIVEN an authenticated `operator` or `viewer` of org A
- WHEN they `PATCH /api/organization`
- THEN the response is `403`

## ADDED Requirements

### Requirement: Every Organization Has A Display Currency, USD By Default

`organizations.currency_code` MUST be NOT NULL, default `USD`, and reference `currencies.code` through a foreign key that
restricts deletion. Organizations existing before this change MUST read `USD` with no backfill step. The admin
`OrganizationResource` MUST return `currency_code` to every role that can read the organization.

#### Scenario: An existing organization defaults to USD

- GIVEN an organization created before the migration
- WHEN any member of it `GET /api/organization`
- THEN `data.currency_code` is `USD`

#### Scenario: The database refuses an unknown code

- GIVEN any writer, including the portability import or the provisioning command
- WHEN an organization row is written with `currency_code` `XYZ` absent from `currencies`
- THEN the write fails on the foreign key

### Requirement: The Org Admin Chooses Among Active Currencies

An `admin` (or a superadmin acting for the organization) MUST be able to set `currency_code` through
`PATCH /api/organization` to any ACTIVE catalogue code. An inactive or unknown code MUST be refused with `422
currency_unavailable`. `operator` and `viewer` MUST receive `403`. A change MUST write an organization audit entry
`organization.currency_changed` with the code before and after.

#### Scenario: Admin switches to EUR

- GIVEN `EUR` is active with a rate and an `admin` of org A
- WHEN they `PATCH /api/organization` with `{"currency_code":"EUR"}`
- THEN the response is `200` with `data.currency_code` `EUR`
- AND an audit entry `organization.currency_changed` records `USD` before and `EUR` after

#### Scenario: Inactive currency is refused

- GIVEN `EUR` is inactive
- WHEN an `admin` of org A `PATCH /api/organization` with `{"currency_code":"EUR"}`
- THEN the response is `422` with `currency_unavailable` and the organization still reads `USD`

#### Scenario: Operator cannot change the currency

- GIVEN an authenticated `operator` of org A
- WHEN they `PATCH /api/organization` with `{"currency_code":"EUR"}`
- THEN the response is `403`

### Requirement: The Superadmin Sets The Currency On Tenant Create And Edit

`POST /api/admin/organizations` and `PATCH /api/admin/organizations/{id}` MUST accept `currency_code` under the same
active-only rule; create without it MUST store `USD`. The edit MUST be covered by the existing `organization.updated`
platform audit entry.

#### Scenario: Superadmin creates a tenant in EUR

- GIVEN `EUR` is active and a superadmin
- WHEN they `POST /api/admin/organizations` with `currency_code` `EUR`
- THEN the new organization reads `EUR`

### Requirement: The Organization Currency Never Crosses Tenants

`currency_code` MUST be readable only through the caller's own (or acting) organization and the superadmin organization
endpoints. No endpoint MAY reveal which organizations use a given currency, including the `409 currency_in_use`
response. `currency_code` MUST be classified admin-only in `ExposureCatalogue` and MUST NOT appear on
`/v1/organization`.

#### Scenario: Another tenant's currency is not reachable

- GIVEN org A uses `EUR` and an `admin` of org B
- WHEN they call every organization and currency endpoint available to them
- THEN no response contains org A's `currency_code`

#### Scenario: The public organization resource is unchanged

- GIVEN an M2M client of org A
- WHEN it `GET /v1/organization`
- THEN the body carries no `currency_code` and `openapi.v1.json` is byte-identical to before the change
