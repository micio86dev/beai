# Tasks: Organization Currencies

Strict TDD: every behaviour task is a RED step (a failing test, observed failing for the stated reason) followed by a
GREEN step (the smallest change that makes it pass), then REFACTOR with the suite green. A box is ticked only for an
observed outcome, with the commit sha next to it. Inputs: `proposal.md`, `design.md`, `specs/currency-catalogue/spec.md`,
`specs/organization-settings/spec.md`, `specs/admin-backoffice/spec.md`. Created 2026-10-11 from wrapper `develop`
`e539957`. Nothing is implemented yet.

**Delivery record (2026-10-11).** Ticks below cite the merged PR and merge commit (read with `gh pr list --state merged`
on 2026-10-11); the RED/GREEN evidence is in each PR description and its CI, not re-observed here. Not in the plan:
api #173 (contract and PATCH guards), api #174 (the confirmed EUR rate seeder, OWNER-1), backoffice #91 (USD fallback
on an unusable code).

## Rules for every slice

- **Review budget.** About **400 authored changed lines per slice, tests and docs included** (additions plus deletions).
  A planning heuristic, not a hard cap: if the correct solution is larger, say why in the PR and continue; never delete
  blank lines or comments, omit tests, minify or split artificially to fit. **Excluded and stated in each PR:** generated
  `openapi.json` snapshots, the regenerated typed client, Playwright baselines, `bun.lock`.
- **Commits.** One Conventional Commit per work unit on a `feature/*` branch of the submodule (Git Flow), tests and docs
  alongside the behaviour, no AI attribution, never `--no-verify`, never a push from a worker. Push, PR, merge and
  release stay with the owner. The wrapper pointer is bumped once (`OC-09`).
- **api commands.** Pest by exact file path: `cd api && ./vendor/bin/pest <file>`. Then `./vendor/bin/pint --test` and
  `./vendor/bin/phpstan analyse --memory-limit=1G`. Full suite (`--parallel`, coverage `--min=85`) once per slice, never
  beside another Pest run (the test DB is shared) or a Docker build (4 GB VM).
- **backoffice commands (Bun only).** Per file: `cd backoffice && bun run test:unit -- tests/unit/<file>.spec.ts`. Before
  a PR: `bun run typecheck`, `bun run lint`, `bun run format:check`, `bun run test:unit:coverage`. Playwright only through
  `task e2e:backoffice` (chromium and webkit). Never `npm`, `npx`, `pnpm` or `yarn`.
- **No new dependency.** `Intl` covers formatting. A slice that believes it needs a package stops and reports.
- **Contract guards.** `DashboardCostsTest` and every `*_usd` assertion stay unchanged; `openapi.v1.json` diff stays empty.
  A slice that needs to edit either is wrong.
- **Delegation route.** Each slice is delegated-direct work: one writer per slice. No SDD phase workers.
- **Review gate.** When the owner has receipt-driven development enabled, the review candidate is a work-unit commit or
  a PR slice.

## Ordering and dependencies

```
OC-01 api catalogue schema + model + seed
  -> OC-02 api catalogue endpoints + audit + ability        \
  -> OC-03 api org currency column wiring + exposure          } OC-02 and OC-03 in parallel after OC-01
        -> OC-04 OpenAPI export + sync (one export, after OC-02 and OC-03)
OC-05 backoffice formatMoney (pure util)                     -- parallel with OC-01..OC-04
  -> OC-06 backoffice useCurrencies + useMoney + cost surfaces (needs OC-04, OC-05)
  -> OC-07a backoffice Settings + client form currency select (needs OC-04, OC-05)
  -> OC-07b backoffice superadmin catalogue panel (needs OC-04)
        -> OC-08 e2e (needs OC-06, OC-07a, OC-07b)
             -> OC-09 docs + wrapper pointer bump
```

`OC-06`, `OC-07a` and `OC-07b` touch different files and may run in parallel; `OC-06` and `OC-07a` both read
`useOrganization.ts` but only `OC-07a` writes it.

## Owner action (blocks nothing in code)

- [x] OWNER-1 Decide the initial EUR rate, its source and who maintains it (design open question 1). Until then EUR stays
      seeded inactive with no rate and cannot be selected; the e2e slice creates its own rate in a fixture.
  - **Proposed initial value (2026-10-11, read from the ECB daily reference file, published for 2026-10-09; not a quote of record):** 1 EUR = 1.1206 USD, therefore `rate_per_usd` = 0.892379 EUR per 1 USD (`1 / 1.1206`, six decimals). Source: https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml. The owner confirms it, sets it from the superadmin page before activating EUR, and keeps it updated by hand (R1: no external feed). The seed and migrations MUST NOT carry this number: EUR stays inactive with no rate (P6).
  - **RESOLVED 2026-10-11 by the owner:** the rate above is CONFIRMED and applied by the owner-authorized
    `CurrencyRatesSeeder` (api `beai:sync-currency-rates`, run by `beai:deploy`, api #174 `a7a5d10`), which sets it and
    activates EUR only while the stored rate is NULL, never overwriting a superadmin edit. The migration still seeds EUR
    inactive with no rate. Supersedes P6 (design D8); recorded in `CLAUDE.md`, product decision 11.

## OC-01: Currency catalogue schema, model and seed (api, about 260 lines)

Depends on: nothing. Files: `database/migrations/2026_10_12_100000_create_currencies_and_organization_currency.php`,
`app/Models/Currency.php`, `app/Models/Organization.php`.

- [x] OC-01.1 RED `tests/Feature/Currencies/CurrenciesMigrationTest.php`: seed rows (`USD` active rate 1, `EUR` inactive Merged: api #170 `21ad35f`.
      NULL rate); each CHECK of design "Data model" refuses its bad row (lowercase code, decimals 5, rate 0, rate
      1000000, rate without date, active without rate, USD rate 2, USD inactive); FK refuses an organization with `XYZ`;
      an organization created before reads `USD`; rollback drops both.
- [x] OC-01.2 RED `tests/Unit/Models/CurrencyTest.php`: string primary key, casts, `active()` scope; Merged: api #170 `21ad35f`.
      `Organization::currency()` resolves.
- [x] OC-01.3 GREEN the migration (docblock stating D3/D8), the model, `Organization` `$fillable` and relation. Merged: api #170 `21ad35f`.
- [x] OC-01.4 Verify: both files green; `migrate:fresh` and rollback on Postgres; Pint; PHPStan; Merged: api #170 `21ad35f`.
      `tests/Feature/C2/Schema/OrganizationsMigrationTest.php` unchanged and green.
- [x] OC-01.5 Commit: `feat(api): add the platform currency catalogue and organization currency column`. Merged: api #170 `21ad35f`.

## OC-02: Catalogue endpoints, audit and ability (api, about 380 lines)

Depends on: OC-01. Parallel with OC-03. Files: `routes/api.php`, `app/Http/Controllers/Api/CurrencyController.php`,
`app/Http/Controllers/Api/PlatformCurrencyController.php`, `app/Http/Resources/CurrencyResource.php`,
`app/Http/Requests/{Store,Update}CurrencyRequest.php`, `app/Support/Authorization/UserAbilities.php`.

- [x] OC-02.1 RED `tests/Feature/Currencies/CurrencyReadTest.php`: admin, operator, viewer and superadmin read active rows Merged: api #171 `2a8d4cf`.
      only, decimal-string rate; `401` unauthenticated.
- [x] OC-02.2 RED `tests/Feature/Currencies/PlatformCurrencyManagementTest.php`: create, edit rate, activate with rate, Merged: api #171 `2a8d4cf`.
      delete unassigned; each validation code of design D9; `409 currency_in_use` for delete and deactivate of an assigned
      code with a body naming no organization; `409 currency_usd_immutable`; code rename `422`; tenant roles `403` on all
      four verbs; one platform audit entry per write with before/after.
- [x] OC-02.3 RED abilities test (extend the existing `UserAbilities` test): `currencies.manage` true for superadmin only. Merged: api #171 `2a8d4cf`.
- [x] OC-02.4 GREEN routes, controllers (`abort_unless` superadmin per action, transaction + `lockForUpdate` for the in-use Merged: api #171 `2a8d4cf`.
      check), resource, requests, ability.
- [x] OC-02.5 Verify: the three files green; Pint; PHPStan; full suite once. Merged: api #171 `2a8d4cf`.
- [x] OC-02.6 Commit: `feat(api): let the superadmin manage the currency catalogue`. Merged: api #171 `2a8d4cf`.

## OC-03: Organization currency through settings, superadmin and exposure (api, about 300 lines)

Depends on: OC-01. Parallel with OC-02. Files: `UpdateOrganizationRequest`, `UpdateManagedOrganizationRequest`,
`StoreOrganizationRequest`, `OrganizationController`, `AdminOrganizationController`, `Actions/Organizations/CreateOrganization`,
`Resources/Admin/OrganizationResource`, `tests/Helpers/PublicApi/ExposureCatalogue.php`.

- [x] OC-03.1 RED `tests/Feature/OrganizationSettings/OrganizationCurrencyTest.php`: admin sets active `EUR`; inactive and Merged: api #172 `63658ed` (contract tightened by api #173 `e5ae567`).
      unknown `422 currency_unavailable`; operator and viewer `403`; `organization.currency_changed` audit entry; an admin
      of org B never sees org A's code (pattern of `OrganizationCrossTenantIsolationTest`).
- [x] OC-03.2 RED extend `tests/Feature/Superadmin/OrganizationManagementTest.php`: create without code stores `USD`, with Merged: api #172 `63658ed` (contract tightened by api #173 `e5ae567`).
      active `EUR` stores it, inactive `422`; edit covered by `organization.updated`.
- [x] OC-03.3 RED extend `tests/Feature/PublicApi/Exposure/ExposureTest.php`: `currency_code` in the admin resource and Merged: api #172 `63658ed` (contract tightened by api #173 `e5ae567`).
      the `Organization` exclusions, absent from the public resource; a `Currency` case freezing `CurrencyResource` keys
      (lands GREEN with OC-02's resource; if OC-02 is not merged yet, this case moves to OC-02).
- [x] OC-03.4 GREEN request rules, fill lists, resource key, audit call, catalogue entries (reviewed decision P9). Merged: api #172 `63658ed` (contract tightened by api #173 `e5ae567`).
- [x] OC-03.5 Verify: the three files green; `tests/Feature/PublicApi/OrganizationTest.php` and Merged: api #172 `63658ed` (contract tightened by api #173 `e5ae567`).
      `OrganizationSettings/BrandingTest.php` unchanged and green; Pint; PHPStan; full suite once.
- [x] OC-03.6 Commit: `feat(api): assign a display currency to each organization`. Merged: api #172 `63658ed` (contract tightened by api #173 `e5ae567`).

## OC-04: OpenAPI export and sync (api + consumers, generated)

Depends on: OC-02, OC-03.

- [x] OC-04.1 Export against Postgres (`api/AGENTS.md`), commit `api/openapi.json`; `git diff --exit-code api/openapi.v1.json` Merged: api #171, #172, #173 (each carries `openapi.json`).
      is empty. Commit: `chore(api): export the OpenAPI spec with currencies`.
- [x] OC-04.2 `task openapi:sync`; regenerate the typed clients; commit in `backoffice` and `frontend`: Merged: backoffice #86 `4e51fd5`, frontend #91 `73ac4c6`.
      `chore(backoffice): sync the OpenAPI client with currencies`, `chore(frontend): sync the OpenAPI snapshot`.
- [x] OC-04.3 Verify: the wrapper parity check (`scripts/tests/verify-openapi-parity.test.sh`) green; both apps typecheck. Merged: backoffice #86, frontend #91 (CI green).

## OC-05: formatMoney (backoffice, about 200 lines)

Depends on: nothing (pure util, its own input type `{ code, decimals, rate_per_usd }`). Parallel with OC-01..OC-04.
Files: `app/utils/format.ts`, `tests/unit/utils/format.spec.ts`.

- [x] OC-05.1 RED `format.spec.ts`: `formatMoney` for USD and EUR in `it` and `en` (output equals `Intl` with Merged: backoffice #85 `5947894`.
      `style: 'currency'`), zero, a 0-decimal currency (`2.34` USD at 150 → `351`), sub-minor-unit (`0.0034` USD at 0.92
      → 2 significant digits, never zero), negative not expected but not crashing.
- [x] OC-05.2 GREEN `formatMoney`, moving the `formatUsdAmount` docblock rationale onto it. `formatUsdAmount` stays until Merged: backoffice #85 `5947894`.
      OC-06 removes its last caller.
- [x] OC-05.3 Verify: spec green; typecheck; lint. Commit: `feat(backoffice): add a currency-aware money formatter`. Merged: backoffice #85 `5947894`.

## OC-06: Currency composables and cost surfaces (backoffice, about 400 lines)

Depends on: OC-04, OC-05. Files: `app/composables/useCurrencies.ts`, `app/composables/useMoney.ts`, `app/pages/index.vue`,
`app/pages/participants/[id].vue`, `app/components/organisms/SessionReviewPanel.vue`,
`app/pages/avatar-templates/index.vue`, `app/utils/format.ts`, `i18n/locales/{en,it}.json`.

- [x] OC-06.1 RED `tests/unit/composables/useCurrencies.spec.ts` and `useMoney.spec.ts`: USD fallback for inactive, Merged: backoffice #89 `0193152`.
      rate-less, failed fetch and null organization; `≈` and `money.convertedNote` only when converted; one fetch per app
      load.
- [x] OC-06.2 RED update `SessionReviewPanel.spec.ts` and `participants/detail.spec.ts` to the `Intl` USD strings, and add Merged: backoffice #89 `0193152`.
      one EUR case each (amount, `≈`, note).
- [x] OC-06.3 RED a locale-file test (extend the existing i18n key spec): no cost key contains `$`, `€` or `{currency}`; Merged: backoffice #89 `0193152`.
      every new key exists in `it` and `en`.
- [x] OC-06.4 GREEN composables, the four surfaces, i18n (delete `review.costValue`, `dashboard.kpi.costValue`; change Merged: backoffice #89 `0193152`.
      `dashboard.kpi.costBreakdown`, `avatar_templates.llmForecast`; add `money.*`); delete `formatUsdAmount` and its spec
      cases.
- [x] OC-06.5 Verify: unit specs green; coverage thresholds; typecheck; lint; format. Commit: Merged: backoffice #89 `0193152`.
      `feat(backoffice): display cost amounts in the organization currency`.

## OC-07a: Currency select in Settings and the client form (backoffice, about 300 lines)

Depends on: OC-04, OC-05. Files: `app/components/organisms/CurrencyForm.vue`, `app/pages/settings/index.vue`,
`app/components/organisms/ClientForm.vue`, `app/composables/useOrganization.ts`, i18n.

- [x] OC-07a.1 RED `tests/unit/components/organisms/CurrencyForm.spec.ts` (modelled on `BrandingForm.spec.ts`): lists active Merged: backoffice #87 `aac678c`.
      currencies, saves `currency_code`, read-only for operator and viewer, shows `currency_unavailable` localized.
- [x] OC-07a.2 RED extend the `ClientForm` spec: the select appears on create and edit, default `USD`. Merged: backoffice #87 `aac678c`.
- [x] OC-07a.3 GREEN the form inside the `organization` section, the client form field, i18n `settings.currency.*`. Merged: backoffice #87 `aac678c`.
- [x] OC-07a.4 Verify as OC-06.5. Commit: `feat(backoffice): let admins choose the organization display currency`. Merged: backoffice #87 `aac678c`.

## OC-07b: Superadmin currency catalogue panel (backoffice, about 380 lines)

Depends on: OC-04. Files: `app/components/organisms/CurrencyCatalogPanel.vue`, `app/composables/useCurrencyCatalogue.ts`,
`app/pages/settings/index.vue` (one section entry), i18n `currencies.*`.

- [x] OC-07b.1 RED `tests/unit/components/organisms/CurrencyCatalogPanel.spec.ts`: lists all rows; create and edit dialog Merged: backoffice #88 `1b9a0a6`.
      payloads (rate as decimal string, date); activate, deactivate, delete; `409 currency_in_use` and
      `currency_usd_immutable` render localized messages; USD row shows no destructive actions.
- [x] OC-07b.2 RED extend the settings page spec: section visible only with `currencies.manage`. Merged: backoffice #88 `1b9a0a6`.
- [x] OC-07b.3 GREEN panel, composable, section entry, i18n. Merged: backoffice #88 `1b9a0a6`.
- [x] OC-07b.4 Verify as OC-06.5. Commit: `feat(backoffice): let the superadmin manage currencies and rates`. Merged: backoffice #88 `1b9a0a6`.

## OC-08: End to end (backoffice, about 350 lines)

Depends on: OC-06, OC-07a, OC-07b.

- [x] OC-08.1 Update `tests/e2e/session-review-cost.spec.ts`, `dashboard.spec.ts`, `avatar-templates-forecast.spec.ts`: Merged: backoffice #90 `699cc03` (USD fallback on an unusable code: backoffice #91 `53b0656`).
      mocks gain `GET /api/currencies` and `currency_code: "USD"`; assertions use the `Intl` USD text.
- [x] OC-08.2 RED then GREEN `tests/e2e/organization-currency.spec.ts`: admin switches to an EUR fixture with a rate; Merged: backoffice #90 `699cc03` (USD fallback on an unusable code: backoffice #91 `53b0656`).
      dashboard, participant detail and session review show `≈` euro amounts with the note; catalogue `500` falls back
      to USD; superadmin edits a rate and sees the in-use refusal on deactivate; axe clean.
- [x] OC-08.3 Verify: `task e2e:backoffice` green on chromium and webkit. Commit: Merged: backoffice #90 `699cc03` (USD fallback on an unusable code: backoffice #91 `53b0656`).
      `test(backoffice): cover organization currency display end to end`.

## OC-09: Docs and wrapper pointer (wrapper, about 120 lines)

Depends on: OC-08 and the owner's submodule releases (api first, then backoffice and frontend, each folding in its sync).

- [x] OC-09.1 `DESIGN.md`: document the approximate converted amount (`≈` plus the visible converted-from note) and the Merged: wrapper #105 `2c51a3e`; ratification recorded by `docs/close-currencies-and-tavus`.
      currency select; `CLAUDE.md` product decisions: record the currency ruling (R1, R2 and whichever of P1-P10 the owner
      ratifies).
- [ ] OC-09.2 Bump the three submodule pointers to their release tags in one wrapper commit; parity guards green.
      NOT DONE as written: wrapper `ded4800` (#105) pins the `develop` merges api `e5ae567`, backoffice `699cc03`,
      frontend `73ac4c6`, which are not release tags (no release was cut), and api #174 and backoffice #91 are not in
      that pin. Left open for the next Git Flow release.
- [x] OC-09.3 Commit: `docs: record organization currencies` and `chore: pin submodules with organization currencies`. Merged: wrapper #105 `2c51a3e`, `ded4800`.
- [x] OC-09.4 Archive this change (merge the deltas into `openspec/specs/`). Archived 2026-10-11 to `openspec/changes/archive/2026-10-11-organization-currencies/` (see `archive-report.md`).
