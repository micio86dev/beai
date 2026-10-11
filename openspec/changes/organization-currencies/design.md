# Design: Organization Currencies

> Proposed 2026-10-11. Inputs: `proposal.md`, the delta specs under `specs/`. Grounded in wrapper `develop` `e539957`.
> File references are to the submodules as pinned there.

## Decisions

Each PROPOSED decision names the rejected alternative so the owner can veto it with one line.

### D1 (RATIFIED R1). A platform currency table is the only FX source

Superadmin-maintained rows; adding a currency is inserting a row. Rejected by the owner: an external FX feed (a runtime
dependency and a moving number on an estimate) and per-organization rates.

### D2 (RATIFIED R2). USD is the stored and computed truth; conversion is display-only

No cost column, estimator, rate config or aggregate changes. `DashboardCostsTest` and every `*_usd` assertion stay as
they are.

### D3 (PROPOSED P1). `organizations.currency_code` with a real foreign key

`char(3) NOT NULL DEFAULT 'USD' REFERENCES currencies(code) ON DELETE RESTRICT ON UPDATE RESTRICT`. The database, not
only a FormRequest, guarantees an organization never points at a missing row; this also holds for the portability
import path and `ProvisionOrganizationCommand` (same reasoning as `organizations_primary_color_hex`). Existing rows get
`USD` from the column default; no backfill.
**Rejected:** a CHECK listing codes (needs a migration per currency, contradicting R1); a nullable column meaning "USD"
(two spellings of one state).

### D4 (PROPOSED P2). Display conversion in the backoffice; the API contract keeps its USD fields

`OrganizationResource` (admin) gains `currency_code`. `GET /api/currencies` returns the active rows. The backoffice
computes `usd * rate_per_usd`. No `*_usd` field is renamed; `/v1` (`cost_usd`, `currency: "USD"` in `UsageAggregator`)
and `openapi.v1.json` are unchanged; the internal `currency: "USD"` keys on `/api/dashboard` and the participant cost
block (`ParticipantInterviewAggregator`) stay and keep meaning "the unit of the `*_usd` numbers".
**Rejected:** server-side conversion adding `*_display` fields to every cost payload: it breaks the `*_usd` naming
doctrine, duplicates the conversion in four serializers, and makes the API pick a rate on the operator's behalf.

### D5 (PROPOSED P3). A converted amount is always approximate and reconcilable

When the display currency is not USD the amount renders with `≈` and a visible secondary line
"US$0.42 at 1 USD = 0.92 EUR, rate of 1 Oct 2026" (`money.convertedNote`). A missing, inactive or rate-less org
currency, a failed `GET /api/currencies`, or no acting organization renders USD (never a guess, never `0`).
**Rejected:** a `title` tooltip only (invisible to keyboard and touch users and to screen readers in practice).

### D6 (PROPOSED P4). No re-denomination, current rate only

Changing an organization's currency changes display only. Historical amounts convert at today's rate; `rate_as_of` in
the note makes that visible. Rate history is recoverable from the audit log (`before`/`after` of every rate edit).
**Rejected:** storing the rate per cost row (a schema change on four tables for a display concern).

### D7 (PROPOSED P5). Scope of conversion

Converted: dashboard cost KPI and its breakdown, participant detail interview cost, session review cost lines, avatar
template LLM forecast. Not converted: `/v1`, `GET /api/llm-models`, webhooks, the candidate `frontend`. Superadmin:
the acting organization's currency applies (it is what `GET /api/organization` returns); with no acting organization
`data` is `null` and amounts render in USD. No cross-organization totals are added.

### D8 (PROPOSED P6). EUR is seeded inactive with no rate

`rate_per_usd` and `rate_as_of` are nullable, and `CHECK (NOT is_active OR (rate_per_usd IS NOT NULL AND rate_as_of IS
NOT NULL))` makes "active" imply a rate. The migration seeds `USD` (`$`, 2, rate 1, active) and `EUR` (`€`, 2, NULL,
inactive). EUR cannot be selected by any organization until the superadmin enters a rate and activates it.
**Rejected:** seeding a market quote (invented, stale on day one); seeding a placeholder rate with a "set me" flag
(one forgotten flag and a fake number renders as money).

### D9 (PROPOSED P7). Validation and invariants

| Field | Rule | Enforced by |
|---|---|---|
| `code` | `^[A-Z]{3}$`, unique, immutable after create | CHECK + PK; request rejects `code` on update |
| `symbol` | 1-8 chars | request; `varchar(8)` |
| `decimals` | integer 0-4 (ISO 4217 minor units) | CHECK + request |
| `rate_per_usd` | `> 0`, `< 1000000`, at most 6 decimals | CHECK + `numeric(18,6)` + request (`decimal:0,6`) |
| `rate_as_of` | date, not in the future; required with a rate | request; CHECK pairs it with the rate |
| `USD` row | rate 1, active, never deleted | CHECK `code <> 'USD' OR (rate_per_usd = 1 AND is_active)`; delete refused `409` |
| assigned row | not deactivatable, not deletable; rate and symbol editable | action checks `organizations` (and the FK `RESTRICT` as backstop) → `409 currency_in_use` |

`currency_in_use` names no organization (D11).

### D10 (PROPOSED P8). Authorization

| Action | superadmin | admin | operator | viewer |
|---|---|---|---|---|
| `GET /api/currencies` (active) | yes | yes | yes | yes |
| `GET/POST/PATCH/DELETE /api/admin/currencies` | yes | 403 | 403 | 403 |
| set own org `currency_code` (`PATCH /api/organization`) | when acting | yes (active codes only) | 403 | 403 |
| set any org `currency_code` (`POST/PATCH /api/admin/organizations`) | yes | 403 | 403 | 403 |

Superadmin checks follow `PlatformAvatarTemplateController` (`abort_unless` per action). A new ability
`currencies.manage` is published in `UserAbilities` beside `platformSettings.viewAny`, so the backoffice gates the
catalogue section on the ability, never on `is_superadmin`.
**Rejected:** org-level currency management (rates are platform truth, R1).

### D11 (PROPOSED). Tenant isolation

`currencies` has no `organization_id` and holds no tenant data; it is global like `llm_models`. No endpoint answers
which organizations use a currency (the admin list carries no usage count). `currency_code` is read only through
`GET /api/organization` (own or acting org) and `GET /api/admin/organizations/{id}` (superadmin).

### D12 (PROPOSED P9). Exposure

`ExposureCatalogue::exclusions()['Organization']` gains `currency_code` (admin-only; the public
`PublicApi\OrganizationResource` does not add it). A new `'Currency'` exclusion entry freezes the `CurrencyResource`
keys as admin-only, with an `ExposureTest` case like `PlatformAvatarTemplate`'s.

### D13 (PROPOSED P10). One formatter, no symbol in copy

`formatMoney` uses `Intl.NumberFormat(locale, { style: 'currency', currency, minimumFractionDigits: d,
maximumFractionDigits: d })` at or above one minor unit (`10^-d`); below it (and non-zero) it uses
`maximumSignificantDigits: 2` with `style: 'currency'`, the rule `formatUsdAmount` applies today. `review.costValue` and
`dashboard.kpi.costValue` are deleted; `dashboard.kpi.costBreakdown` and `avatar_templates.llmForecast` take a formatted
`{amount}` instead of a symbol.
**Rejected:** keeping a `{currency}` copy parameter (symbol placement and spacing differ per locale; `Intl` owns them).

## Data model

One migration, `api/database/migrations/2026_10_12_100000_create_currencies_and_organization_currency.php`, modelled on
`2026_09_01_140000_add_branding_to_organizations.php` (docblock stating the why, raw `DB::statement` CHECKs).

```sql
CREATE TABLE currencies (
  code          char(3)       PRIMARY KEY,
  symbol        varchar(8)    NOT NULL,
  decimals      smallint      NOT NULL,
  rate_per_usd  numeric(18,6) NULL,
  rate_as_of    date          NULL,
  is_active     boolean       NOT NULL DEFAULT false,
  created_at    timestamp(0)  NULL,
  updated_at    timestamp(0)  NULL,
  CONSTRAINT currencies_code_iso      CHECK (code ~ '^[A-Z]{3}$'),
  CONSTRAINT currencies_decimals      CHECK (decimals BETWEEN 0 AND 4),
  CONSTRAINT currencies_rate_range    CHECK (rate_per_usd IS NULL OR (rate_per_usd > 0 AND rate_per_usd < 1000000)),
  CONSTRAINT currencies_rate_pair     CHECK ((rate_per_usd IS NULL) = (rate_as_of IS NULL)),
  CONSTRAINT currencies_active_rated  CHECK (NOT is_active OR rate_per_usd IS NOT NULL),
  CONSTRAINT currencies_usd_anchor    CHECK (code <> 'USD' OR (rate_per_usd = 1 AND is_active))
);
INSERT INTO currencies (code, symbol, decimals, rate_per_usd, rate_as_of, is_active, created_at, updated_at) VALUES
  ('USD', '$', 2, 1, CURRENT_DATE, true,  now(), now()),
  ('EUR', '€', 2, NULL, NULL,      false, now(), now());
ALTER TABLE organizations ADD COLUMN currency_code char(3) NOT NULL DEFAULT 'USD'
  REFERENCES currencies(code) ON DELETE RESTRICT ON UPDATE RESTRICT;
```

The seed lives in the migration, not a seeder: `USD` is structural (the column default references it), so every
environment, including `RefreshDatabase` tests and a fresh Railway database, has it without a seeding step. `down()`
drops the column, then the table. `App\Models\Currency` (`$primaryKey = 'code'`, `$incrementing = false`, `$keyType =
'string'`, casts `rate_per_usd` to `decimal:6`, `rate_as_of` to `date`, `is_active` to bool, scope `active()`).
`Organization` adds `currency_code` to `$fillable` and a `currency()` `BelongsTo`.

## API

### Routes (`api/routes/api.php`)

```php
// Beside GET /api/llm-models: global, readable by every authenticated role.
Route::middleware(['auth:api', TenantContext::class])->group(function (): void {
    Route::get('/currencies', [CurrencyController::class, 'index']);
});
// Inside the existing superadmin group (no org.context, like admin/avatar-templates).
Route::get('admin/currencies', [PlatformCurrencyController::class, 'index']);
Route::post('admin/currencies', [PlatformCurrencyController::class, 'store']);
Route::patch('admin/currencies/{code}', [PlatformCurrencyController::class, 'update'])->where('code', '[A-Z]{3}');
Route::delete('admin/currencies/{code}', [PlatformCurrencyController::class, 'destroy'])->where('code', '[A-Z]{3}');
```

### Resources and requests

- `App\Http\Resources\CurrencyResource`: `code`, `symbol`, `decimals`, `rate_per_usd` (string, 6 decimals, or `null`),
  `rate_as_of` (`Y-m-d` or `null`), `is_active`. Same shape for both lists; the public list only returns active rows.
  `rate_per_usd` is a decimal string so no float rounding enters the contract.
- `StoreCurrencyRequest` / `UpdateCurrencyRequest`: D9 rules; error codes as message keys in the repo style
  (`currency_code_invalid`, `currency_code_taken`, `currency_rate_invalid`, `currency_rate_as_of_invalid`,
  `currency_decimals_invalid`, `currency_activation_requires_rate`). `UpdateCurrencyRequest` prohibits `code`.
- `PlatformCurrencyController::update` and `destroy` run inside a transaction with `lockForUpdate` on the row and refuse
  with `409 {"message":"currency_in_use"}` when `is_active` would turn false or the row would be deleted while
  `Organization::withoutGlobalScopes()->where('currency_code', $code)->exists()`, and `409 currency_usd_immutable` for
  any USD rate, activation or delete change.
- `UpdateOrganizationRequest`, `UpdateManagedOrganizationRequest`, `StoreOrganizationRequest`: `currency_code` =>
  `['sometimes', 'string', Rule::exists('currencies', 'code')->where('is_active', true)]` (`required` defaults to `USD`
  on store), message `currency_unavailable`. `OrganizationController::update` and
  `AdminOrganizationController::store/update` add `currency_code` to their `only([...])` lists;
  `CreateOrganization` passes it through.
- `Admin\OrganizationResource` adds `'currency_code' => $organization->currency_code`.

### Audit

- Catalogue writes: `PlatformAuditWriter::record` with `currency.created`, `currency.updated` (dirty `before`/`after`,
  so every rate change is a history entry), `currency.deleted`, subject `Currency`, subject id `null` (string PK; the
  code goes in `before`/`after`).
- Superadmin org edits: already audited as `organization.updated` (dirty fields), so `currency_code` is covered by
  adding it to the fill list.
- Org-admin change: `OrganizationController::update` records `organization.currency_changed` through `AuditRecorder`
  when `currency_code` is dirty. (The other settings fields on that route are not audited today; that pre-existing gap is
  listed in the open questions, not widened here.)

### OpenAPI

Scramble picks up the routes and resources. Export once after the last `api` slice, against Postgres (`api/AGENTS.md`),
then `task openapi:sync` copies it into `frontend` and `backoffice`. `openapi.v1.json` must show no diff.

## Backoffice

| File | Change |
|---|---|
| `app/utils/format.ts` | Add `formatMoney(usd, currency, locale)` and the `Currency` type (`code`, `symbol`, `decimals`, `rate_per_usd: number`, `rate_as_of`). Delete `formatUsdAmount` once its four callers move (its docblock rationale moves to `formatMoney`). |
| `app/composables/useCurrencies.ts` (new) | Fetch `GET /api/currencies` once into `useState('currencies')`; `displayCurrency(orgCode)` returns the active row with a rate, else the built-in `USD` constant. A failed fetch yields `USD`. |
| `app/composables/useMoney.ts` (new) | Binds `useOrganization` + `useCurrencies` + `useI18n`; exposes `money(usd)` (string, `≈` via `money.approximate` when converted) and `moneyNote(usd)` (`money.convertedNote` or `null` for USD). The only entry point surfaces use. |
| `app/composables/useOrganization.ts` | Types come from the regenerated OpenAPI client, so `currency_code` appears with the sync; `UpdateOrganizationPayload` accepts it. |
| `app/components/organisms/CurrencyForm.vue` (new) | Modelled on `BrandingForm.vue`: one select of active currencies (label `EUR — €`), Save, success and error toasts; read-only text for operator/viewer. |
| `app/pages/settings/index.vue` | Currency control added to the existing `organization` section (no new tab); new section `currencies` (`CurrencyCatalogPanel`) with `requires: 'currencies.manage'`, `needsOrganization: false`. |
| `app/components/organisms/CurrencyCatalogPanel.vue` (new) | Table of all rows (code, symbol, decimals, rate, `rate_as_of`, active) with add/edit dialog, activate/deactivate, delete; surfaces `409` codes as localized messages. |
| `app/components/organisms/ClientForm.vue` | Currency select on tenant create/edit (superadmin), same options. |
| `app/pages/index.vue` | `costLabel`/`costBreakdown` use `money()`; `moneyNote` appended to the KPI `detail`. |
| `app/pages/participants/[id].vue` | `costLabel` uses `money()`; note under the cost metric. |
| `app/components/organisms/SessionReviewPanel.vue` | `costLabel(usd)` uses `money()`; one note under the cost section (same rate for every line). Receives the currency through `useMoney`, not a new prop. |
| `app/pages/avatar-templates/index.vue` | Forecast `amount` uses `money()`. |
| `i18n/locales/{en,it}.json` | Delete `review.costValue`, `dashboard.kpi.costValue`; change `dashboard.kpi.costBreakdown` and `avatar_templates.llmForecast` to take a formatted amount; add `money.*`, `settings.currency.*`, `settings.tabs.currencies`, `settings.sectionDescription.currencies`, `currencies.*` (form labels, `409` messages). |

### i18n keys (new or changed)

| Key | en | it |
|---|---|---|
| `money.approximate` | `≈ {amount}` | `≈ {amount}` |
| `money.convertedNote` | `Converted from {usd} at 1 USD = {rate} {code}, rate of {date}` | `Convertito da {usd} a 1 USD = {rate} {code}, tasso del {date}` |
| `dashboard.kpi.costBreakdown` | `Scoring {scoring} · Interview {conversation}` | `Valutazione {scoring} · Intervista {conversation}` |
| `avatar_templates.llmForecast` | `{amount} in LLM tokens for a typical ...` (rest unchanged) | `{amount} in token LLM per ...` (rest unchanged) |
| `settings.currency.label` | `Display currency` | `Valuta di visualizzazione` |
| `settings.currency.help` | `Costs are computed in US dollars and shown converted at the platform rate.` | `I costi sono calcolati in dollari USA e mostrati convertiti al tasso della piattaforma.` |
| `currencies.errors.inUse` | `This currency is assigned to an organization and cannot be removed or deactivated.` | `Questa valuta è assegnata a un'organizzazione e non può essere rimossa o disattivata.` |

The forecast keeps its leading `≈` through `money.approximate` even in USD (it is a forecast); other USD surfaces keep
their existing wording ("estimate" labels).

## Tests

### New

| Repo | Test | Proves |
|---|---|---|
| api | `tests/Feature/Currencies/CurrenciesMigrationTest.php` | Seed rows; each CHECK refuses its bad row; FK refuses an unknown org code; existing orgs read `USD`; rollback. |
| api | `tests/Feature/Currencies/CurrencyReadTest.php` | Every role reads active rows only; shape; unauthenticated `401`. |
| api | `tests/Feature/Currencies/PlatformCurrencyManagementTest.php` | Superadmin CRUD, validation codes, `409` in-use and USD-immutable, audit rows; tenant roles `403`. |
| api | `tests/Feature/OrganizationSettings/OrganizationCurrencyTest.php` | Admin sets an active code; inactive/unknown `422`; operator/viewer `403`; audit entry; cross-tenant isolation (like `OrganizationCrossTenantIsolationTest`). |
| api | `tests/Feature/Superadmin/OrganizationManagementTest.php` (extend) | Create/edit with `currency_code`; default `USD`. |
| api | `tests/Feature/PublicApi/Exposure/ExposureTest.php` (extend) | `Currency` frozen admin-only keys; `currency_code` excluded from public. |
| backoffice | `tests/unit/utils/format.spec.ts` (extend) | `formatMoney` for USD, EUR, a 0-decimal currency, sub-minor-unit amounts (never `0`), zero, both locales. |
| backoffice | `tests/unit/composables/useCurrencies.spec.ts`, `useMoney.spec.ts` | Fallbacks (inactive, rate-less, fetch failure, null org), `≈` and note only when converted. |
| backoffice | `tests/unit/components/organisms/CurrencyForm.spec.ts`, `CurrencyCatalogPanel.spec.ts` | Options, save payload, read-only roles, `409` messages. |
| backoffice | `tests/e2e/organization-currency.spec.ts` | Admin switches to EUR; dashboard, participant detail and session review show `≈ … €` with the note; superadmin catalogue edit; axe clean. |

### Existing tests that change

| Test | Why |
|---|---|
| `backoffice/tests/unit/utils/format.spec.ts` | `formatUsdAmount` cases move to `formatMoney` (USD output now carries the symbol from `Intl`). |
| `backoffice/tests/unit/components/organisms/SessionReviewPanel.spec.ts` | Expected strings come from `Intl` currency formatting instead of `≈ $ x`. |
| `backoffice/tests/unit/pages/participants/detail.spec.ts` | Same. |
| `backoffice/tests/e2e/session-review-cost.spec.ts`, `dashboard.spec.ts`, `avatar-templates-forecast.spec.ts` | Asserted `$` text; mocks add `GET /api/currencies` and `currency_code`. |
| `api/tests/Feature/.../DashboardCostsTest.php` | **Must not change**: USD fields are untouched (a diff here means D2 was broken). |

## Open questions for the owner

1. **Initial EUR rate and who maintains it.** EUR stays unselectable until a rate is entered. Who sets it, from which
   source (e.g. ECB reference rate), and how often?
2. **Should `/v1` ever expose the organization currency** (e.g. on `/v1/organization`)? Proposed: no, until a calling
   system asks; it would be a `T-EXPOSE-001` addition.
3. **Rate history.** Is the audit log enough, or is a dated rate table wanted later so historical costs convert at the
   rate of their day?
4. **Audit of the other org settings fields.** `PATCH /api/organization` does not audit `name`, webhook defaults or
   `primary_color` today. Fix in a separate change?
5. **Superadmin catalogue location.** Proposed as a Settings section beside "Platform"; a dedicated page is possible.
