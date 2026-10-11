# Proposal: Organization Currencies

> **STATUS: Proposed 2026-10-11.** Docs-only: nothing is implemented. Grounded in the wrapper `develop` at `e539957` and
> the `api`/`backoffice` submodule commits it pins. Decisions marked **RATIFIED** come from the owner (2026-10-11);
> decisions marked **PROPOSED** are the orchestrator's and stand unless the owner vetoes them (see `design.md`, "Decisions").

## Intent

Every monetary amount the backoffice shows (interview and session cost estimates) is rendered in US dollars, and the
dollar sign is hardcoded in two i18n strings (`review.costValue` = `≈ $ {usd}`, `avatar_templates.llmForecast` =
`≈ $ {amount} ...`) while the dashboard takes a `{currency}` parameter the API always sets to `USD`. The owner wants
amounts shown in **USD or EUR, USD by default**, wants to **add more currencies later without a code change**, and wants
to **assign a currency to each organization**. Currencies therefore become a managed platform catalogue, and the
organization's currency drives display only.

## Goals

1. A platform currency catalogue (code, symbol, minor-unit decimals, rate per USD, `rate_as_of`, active flag) maintained
   by the superadmin. Adding a currency is adding a row.
2. Every organization carries a currency (default `USD`), chosen by its admin in Settings and by the superadmin when
   creating or editing a tenant.
3. Backoffice cost surfaces display amounts in the organization's currency, labelled approximate, with the original USD
   amount and the rate (and its date) available so an operator can reconcile against a USD invoice.
4. One money formatter for every cost figure; no currency symbol left in i18n copy.

## Non-goals

- **No change to how cost is computed or stored.** Every `*_usd` column, `SessionCostEstimator`, the scoring and
  conversation LLM rates, `ai_requests`, `interview_session_llm_usage` and `indicator_score_audit_runs` stay USD.
- **No change to `/v1`.** `cost_usd` and `currency: "USD"` in `/v1/usage` stay; `openapi.v1.json` stays byte-identical.
  The public organization resource does not gain `currency_code`.
- **No conversion in** `GET /api/llm-models` (a provider price list, USD), webhooks, or the candidate `frontend` (shows
  no money).
- **No FX feed, no per-organization rates, no rate history table** (the audit log records every rate change).
- **No cross-organization cost totals** for the superadmin.
- **No invoicing.** Amounts remain estimates ("an estimate, never an invoice", `DashboardController::costs`).

## Decisions

| # | Decision | Status |
|---|---|---|
| R1 | FX source is a platform currency table maintained by the superadmin (code ISO 4217, symbol, decimals, rate per USD, `rate_as_of`, active). No external feed, no per-organization rates. | **RATIFIED** |
| R2 | Amounts stay canonical in USD everywhere they are computed and stored; conversion happens only at display time. | **RATIFIED** |
| P1 | `organizations.currency_code` `char(3)`, NOT NULL, default `'USD'`, foreign key to the catalogue; set by the org admin (Settings) and the superadmin (tenant create/edit); read by all roles. | PROPOSED |
| P2 | No `*_usd` field is renamed or removed; `/v1` unchanged. The org currency travels on the admin `OrganizationResource`; rates come from `GET /api/currencies`; the backoffice converts. | PROPOSED |
| P3 | Converted amounts are always marked approximate (`≈`) and show the USD original, the rate and `rate_as_of`. Missing or inactive currency falls back to USD display. | PROPOSED |
| P4 | Stored costs are never re-denominated; display uses the current rate (documented limitation, surfaced by `rate_as_of`). | PROPOSED |
| P5 | Conversion applies only to backoffice cost surfaces (dashboard KPI, participant detail, session review, avatar-template forecast). Superadmin: acting organization's currency, else USD. | PROPOSED |
| P6 | Display rounds to the currency's minor units. Seed `USD` (active, rate 1) and `EUR` **inactive with no rate**: the database refuses to activate a currency without a rate, so no invented quote can ever render. | PROPOSED |
| P7 | Validation: rate `> 0`, `< 1,000,000`, at most 6 decimals; code `^[A-Z]{3}$`, unique, immutable; `USD` immutable; an assigned currency cannot be deleted or deactivated (`409`); every write audited. | PROPOSED |
| P8 | Only the superadmin manages the catalogue; org admins choose among active currencies for their own organization; operators and viewers read. | PROPOSED |
| P9 | `currency_code` and the currency resource fields are classified admin-only in `ExposureCatalogue` (`T-EXPOSE-001`). | PROPOSED |
| P10 | `Intl.NumberFormat` with `style: 'currency'`; the existing sub-minor-unit significant-digits rule is kept; the hardcoded `$` and the `{currency}` prefix leave the copy; i18n `it`/`en` for new strings. | PROPOSED |

## Impact

| Area | Change |
|---|---|
| `api` | One migration (`currencies` table with seed, `organizations.currency_code` with FK), `Currency` model, read and superadmin write endpoints, policy and ability, audit, admin `OrganizationResource` and three requests, `ExposureCatalogue`, OpenAPI export. |
| `backoffice` | `formatMoney` util, `useCurrencies` and `useMoney` composables, a currency control in Settings and in the superadmin client form, a superadmin catalogue section in Settings, four cost surfaces, i18n `it`/`en`. |
| `frontend` | OpenAPI snapshot sync only (the wrapper parity gate requires identical `openapi.json` in the three repos). |
| wrapper | This change, `DESIGN.md` note for the approximate-amount pattern, one submodule pointer bump at release. |

## Risks

| Risk | Mitigation |
|---|---|
| **FX staleness.** A rate set months ago misstates converted amounts. | `rate_as_of` is mandatory with a rate and is shown next to every converted amount; amounts are labelled `≈`; the USD original is always available. |
| **Cross-tenant read surface.** | The catalogue is platform data with no tenant column and no tenant data; `GET /api/currencies` reveals nothing about any organization (not even which currencies are in use). `organizations.currency_code` is read only through the existing org-scoped resources. The `409` on deleting an assigned currency says "in use", never by whom. |
| **An invented EUR rate reaching a screen.** | EUR is seeded inactive with a NULL rate; a CHECK makes `is_active` imply a rate. |
| **Silent zero.** A tiny converted cost rounding to `0,00 €`. | The significant-digits rule below one minor unit is kept and tested per currency. |
| **Contract drift across the three repos.** | One OpenAPI export and one sync after all `api` slices; the parity gate enforces identical snapshots; `openapi.v1.json` diff must be empty. |
| **Org currency points at a deactivated row** (race). | Deactivation of an assigned currency is refused; the backoffice falls back to USD for any non-active or rate-less currency. |

## Rollback

Each slice is a revertible commit. Reverting the `backoffice` slices restores USD-only display with no data impact.
Reverting the `api` migration drops `organizations.currency_code` and `currencies` (the down migration drops the FK and
column first); no cost data is touched, because no cost column changes. The `/v1` surface is unaffected at every step.
