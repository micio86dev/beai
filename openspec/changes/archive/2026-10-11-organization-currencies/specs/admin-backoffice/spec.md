# Delta for Admin Backoffice

> Proposed 2026-10-11. Only ADDED requirements. The existing cost requirements ("Participant Detail Interview Status,
> Progress, Elapsed Time, And Cost" and "Conversation-LLM cost renders as a labelled estimate ...") keep their meaning:
> what changes is the unit amounts are displayed in, specified once below and applying to every cost surface.

## ADDED Requirements

### Requirement: Cost Amounts Display In The Organization Currency, Converted From USD At Display Time

Every cost amount on the dashboard cost KPI and its breakdown, the participant detail interview cost, the session review
cost lines and the avatar template LLM forecast MUST be displayed in the acting organization's currency, computed in the
browser as `usd * rate_per_usd` from `GET /api/currencies`. The API values (`*_usd`) MUST be the only input; the
backoffice MUST NOT persist or send a converted amount. Surfaces outside this list (provider price lists, `/v1`, the
candidate app) MUST NOT convert.

#### Scenario: EUR organization sees euros

- GIVEN org A uses `EUR` at rate `0.920000` and a session's avatar cost is `1.00` USD
- WHEN an `operator` of org A opens the session review
- THEN the avatar cost line reads the `Intl` EUR rendering of `0.92` in the UI locale, prefixed by `≈`

#### Scenario: USD organization is unchanged in value

- GIVEN org A uses `USD`
- WHEN the dashboard renders `total_usd = 2.34567`
- THEN the KPI shows the `Intl` USD rendering of `2.35` with no converted-from note

### Requirement: A Converted Amount Is Marked Approximate And Shows Its Source

When the display currency is not USD, every converted amount MUST carry `≈`, and each cost surface MUST show, as visible
text (not only a tooltip), the original USD amount, the rate (`1 USD = {rate} {code}`) and `rate_as_of`. When the
display currency is USD no converted-from note MUST appear.

#### Scenario: The operator can reconcile against a USD invoice

- GIVEN org A uses `EUR` at rate `0.920000` as of `2026-10-01`
- WHEN the participant detail shows an interview cost of `0.42` USD
- THEN the cost reads `≈` plus the EUR amount
- AND a visible note states the USD amount, `1 USD = 0.92 EUR` and the date `2026-10-01` in the UI locale

### Requirement: Display Falls Back To USD, Never To A Guess Or Zero

The backoffice MUST display USD when the organization currency is missing from the active catalogue, has no rate, the
catalogue request fails, or there is no acting organization (superadmin with no client selected). It MUST NOT display a
converted amount computed from a missing or zero rate.

#### Scenario: Catalogue request fails

- GIVEN org A uses `EUR` and `GET /api/currencies` returns `500`
- WHEN the dashboard renders
- THEN amounts render in USD with no `≈` conversion and no note

#### Scenario: Superadmin with no acting organization

- GIVEN a superadmin with no client selected
- WHEN a page showing a cost renders
- THEN amounts render in USD

### Requirement: One Money Formatter With Minor-Unit Rounding And No Silent Zero

All cost amounts MUST be formatted by one `formatMoney(usd, currency, locale)` utility using `Intl.NumberFormat` with
`style: 'currency'`. At or above one minor unit (`10^-decimals`) the amount MUST round to the currency's `decimals`.
Below one minor unit and non-zero it MUST render with at most 2 significant digits, never as zero. No i18n string MAY
contain a currency symbol or a `{currency}` parameter for a cost amount.

#### Scenario: Sub-cent conversation cost in EUR

- GIVEN a conversation LLM cost of `0.0034` USD and `EUR` at `0.920000`
- WHEN it is formatted for `it`
- THEN the result is the `Intl` EUR rendering of `0.0031` (2 significant digits), not `0,00 €`

#### Scenario: Zero-decimal currency

- GIVEN a currency with `decimals = 0` and rate `150`
- WHEN `2.34` USD is formatted
- THEN the result has no fraction digits (`351`)

#### Scenario: No symbol left in copy

- GIVEN the `en` and `it` locale files
- WHEN they are scanned
- THEN no cost key contains `$`, `€` or `{currency}`

### Requirement: Currency Is Chosen In Settings And Managed By The Superadmin

The Settings `organization` section MUST offer a currency select listing active catalogue currencies, writable by
`admin` and read-only for `operator` and `viewer`. The superadmin client form MUST offer the same select on create and
edit. A Settings section for the catalogue MUST be visible only when the `currencies.manage` ability is true, and MUST
list every currency (active or not) with create, edit, activate, deactivate and delete, rendering `409` refusals
(`currency_in_use`, `currency_usd_immutable`) as localized messages. All new copy MUST exist in `it` and `en`.

#### Scenario: Admin changes the currency

- GIVEN an `admin` of org A and `EUR` active
- WHEN they select `EUR` and save
- THEN `PATCH /api/organization` is sent with `currency_code: "EUR"` and the dashboard then shows euros

#### Scenario: Catalogue section hidden from tenant roles

- GIVEN an `admin` of org A (`currencies.manage` false)
- WHEN Settings renders
- THEN no currency catalogue section is shown

#### Scenario: Deactivating an assigned currency

- GIVEN a superadmin and `EUR` assigned to an organization
- WHEN they deactivate `EUR`
- THEN the API answers `409 currency_in_use` and the panel shows the localized in-use message
