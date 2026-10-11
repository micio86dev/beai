# Delta for Currency Catalogue

> Proposed 2026-10-11. New capability: there is no main spec yet; on archive this file becomes
> `openspec/specs/currency-catalogue/spec.md`. Decisions referenced as D-numbers live in `design.md`.

## ADDED Requirements

### Requirement: The Platform Currency Catalogue Is The Only Exchange-Rate Source

The system MUST hold a platform-wide `currencies` table with `code` (ISO 4217, `^[A-Z]{3}$`, primary key), `symbol`,
`decimals` (0-4), `rate_per_usd` (units of the currency per 1 USD, `> 0` and `< 1000000`, at most 6 decimals),
`rate_as_of` (date) and `is_active`. The table MUST NOT carry an `organization_id`. Adding a currency MUST require only a
new row, never a code change. The system MUST NOT fetch rates from an external service and MUST NOT hold per-organization
rates.

#### Scenario: A new currency is added without a deploy

- GIVEN a superadmin
- WHEN they `POST /api/admin/currencies` with `{"code":"GBP","symbol":"£","decimals":2,"rate_per_usd":"0.790000","rate_as_of":"2026-10-10","is_active":true}`
- THEN the response is `201` and `GBP` is returned by `GET /api/currencies`

#### Scenario: The database refuses a malformed code

- GIVEN any writer, including one that bypasses validation
- WHEN a row with code `eur` or `EURO` is inserted
- THEN the insert fails on a CHECK constraint

### Requirement: A Currency Can Be Active Only With A Rate

`rate_per_usd` and `rate_as_of` MUST be both present or both absent. A currency MUST NOT be active without a rate; this
MUST be enforced by a database CHECK, not only by validation. The catalogue MUST be seeded with `USD` (`$`, 2 decimals,
rate 1, active) and `EUR` (`€`, 2 decimals, no rate, inactive), so no invented rate can ever render.

#### Scenario: Fresh database seed

- GIVEN a freshly migrated database
- WHEN `currencies` is read
- THEN it holds `USD` active with rate `1.000000` and `EUR` inactive with a NULL rate and NULL `rate_as_of`

#### Scenario: Activation without a rate is refused

- GIVEN `EUR` has no rate
- WHEN a superadmin `PATCH /api/admin/currencies/EUR` with `{"is_active": true}`
- THEN the response is `422` with `currency_activation_requires_rate` and the row is unchanged

#### Scenario: Rate and date travel together

- GIVEN a superadmin
- WHEN they set `rate_per_usd` without `rate_as_of`
- THEN the response is `422` with `currency_rate_as_of_invalid`

### Requirement: USD Is The Immutable Anchor

The `USD` row MUST keep rate 1, MUST stay active and MUST NOT be deleted. Any request changing its rate, deactivating or
deleting it MUST be refused with `409 currency_usd_immutable`; a database CHECK MUST also hold the rate and the active
flag.

#### Scenario: Deactivating USD

- GIVEN a superadmin
- WHEN they `PATCH /api/admin/currencies/USD` with `{"is_active": false}`
- THEN the response is `409` with `currency_usd_immutable`

### Requirement: An Assigned Currency Cannot Be Removed Or Deactivated

A currency assigned to at least one organization MUST NOT be deleted or deactivated; the request MUST be refused with
`409 currency_in_use`, and the response MUST NOT name or count the organizations using it. Rate and symbol edits MUST be
allowed. A currency's `code` MUST be immutable after creation.

#### Scenario: Deleting an assigned currency

- GIVEN organization A uses `EUR`
- WHEN a superadmin `DELETE /api/admin/currencies/EUR`
- THEN the response is `409` with body `{"message":"currency_in_use"}` and the row remains

#### Scenario: Editing the rate of an assigned currency

- GIVEN organization A uses `EUR`
- WHEN a superadmin `PATCH /api/admin/currencies/EUR` with a new `rate_per_usd` and `rate_as_of`
- THEN the response is `200` and the new rate is returned by `GET /api/currencies`

#### Scenario: Renaming a code is refused

- GIVEN a superadmin
- WHEN they `PATCH /api/admin/currencies/EUR` with `{"code":"EUX"}`
- THEN the response is `422` and the row is unchanged

### Requirement: Only The Superadmin Manages The Catalogue; Every Role Reads Active Rows

`GET /api/currencies` MUST return only active rows (`code`, `symbol`, `decimals`, `rate_per_usd` as a decimal string,
`rate_as_of`, `is_active`) to every authenticated role. `GET/POST/PATCH/DELETE /api/admin/currencies` MUST be
superadmin-only; every tenant role MUST receive `403`. The ability `currencies.manage` MUST be published in the user
abilities, true only for a superadmin.

#### Scenario: A viewer reads the active catalogue

- GIVEN an authenticated `viewer` of org A and `EUR` inactive
- WHEN they `GET /api/currencies`
- THEN the response is `200` and lists `USD` only

#### Scenario: An admin cannot write the catalogue

- GIVEN an authenticated `admin` of org A
- WHEN they `POST /api/admin/currencies`
- THEN the response is `403`

#### Scenario: Unauthenticated read

- GIVEN no bearer token
- WHEN `GET /api/currencies` is called
- THEN the response is `401`

### Requirement: Every Catalogue Write Is Audited

Every create, update and delete of a currency MUST write a platform audit entry (`currency.created`,
`currency.updated`, `currency.deleted`) carrying the actor and the changed fields before and after, so every rate change
is recoverable from the audit log.

#### Scenario: A rate edit leaves a history entry

- GIVEN a superadmin changes `EUR` from `0.920000` to `0.930000`
- WHEN the audit log is read
- THEN one `currency.updated` entry records `rate_per_usd` `0.920000` before and `0.930000` after

### Requirement: Currency Fields Are Admin-Only Under T-EXPOSE-001

The currency resource keys MUST be classified in `ExposureCatalogue` as admin-only exclusions in the same change, and no
`/v1` serializer, export or webhook payload MAY carry them. `openapi.v1.json` MUST be unchanged by this capability.

#### Scenario: The exposure test freezes the currency keys

- GIVEN `CurrencyResource`
- WHEN `ExposureTest` runs
- THEN its keys equal the frozen `Currency` exclusion list and none appears in a public resource
