# Archive Report: organization-currencies

**Change**: organization-currencies
**Archived to**: `openspec/changes/archive/2026-10-11-organization-currencies/`
**Archive date**: 2026-10-11
**Status**: CLOSED and RATIFIED, with one deferred item. Every slice OC-01 to OC-08 is merged into the `develop`
branches of api, backoffice and frontend; the docs and the submodule pin are merged in wrapper #105. The owner ratified
R1, R2 and P1-P10 on 2026-10-11 and confirmed the EUR rate (OWNER-1). `tasks.md` has every box ticked except OC-09.2
(pin to release tags: no release was cut). No verify-report existed and this archive ran no test suite: the evidence is
the merged pull requests (`gh pr list --state merged`, 2026-10-11) and their CI.

## Delivered

| Slice | PR | Merge commit |
|---|---|---|
| OC-01 catalogue schema, model, seed | api #170 | `21ad35f` |
| OC-02 catalogue endpoints, audit, ability | api #171 | `2a8d4cf` |
| OC-03 organization currency, exposure | api #172 | `63658ed` |
| not in the plan: contract and PATCH guards | api #173 | `e5ae567` |
| OWNER-1: confirmed EUR rate seeder | api #174 | `a7a5d10` |
| OC-04 OpenAPI export and sync | api #171-#173 (`openapi.json`), backoffice #86, frontend #91 | `4e51fd5`, `73ac4c6` |
| OC-05 `formatMoney` | backoffice #85 | `5947894` |
| OC-07a Settings and client form select | backoffice #87 | `aac678c` |
| OC-07b superadmin catalogue panel | backoffice #88 | `1b9a0a6` |
| OC-06 composables and cost surfaces | backoffice #89 | `0193152` |
| OC-08 end to end | backoffice #90 | `699cc03` |
| not in the plan: USD fallback on an unusable code | backoffice #91 | `53b0656` |
| OC-09.1, OC-09.3 docs and pin | wrapper #105 | `1ce1949` |

## Owner decisions (2026-10-11)

- R1, R2 and P1-P10 RATIFIED (`CLAUDE.md`, product decision 11).
- EUR rate CONFIRMED: 1 EUR = 1.1206 USD (ECB reference file published for 2026-10-09), `rate_per_usd` 0.892379,
  applied locally and in production by `CurrencyRatesSeeder` (`beai:sync-currency-rates`, run by `beai:deploy`). It
  sets the rate and activates EUR only while the stored rate is NULL and never overwrites a superadmin edit. This
  supersedes P6 / D8 ("EUR stays inactive with no rate until the owner decides"); the migration still seeds EUR inactive
  with no rate.

## Specs merged

| Capability | Requirements before -> after | Delta applied |
|---|---|---|
| currency-catalogue (NEW) | none -> 7 | delta body copied verbatim under a Purpose header (requirement body `diff`: empty) |
| organization-settings | +4, 1 MODIFIED | "Organization Profile Is Name-Only" replaced by the delta text (`name` and `currency_code`; branding recorded, stale "no white-label field" sentence gone); 4 ADDED |
| admin-backoffice | +5 | 5 ADDED |

The two existing specs were composed with `gentle-ai sdd-archive-compose` (exit 0 each). Before composing, the
currency-catalogue delta was amended to the delivered behaviour: the confirmed EUR rate and the seeder rule, plus the
scenario "The deploy applies the confirmed EUR rate once".

## Deferred and open items

1. **OC-09.2, pin to release tags.** Wrapper `ded4800` pins `develop` merges (api `e5ae567`, backoffice `699cc03`,
   frontend `73ac4c6`); api #174 and backoffice #91 are not in that pin. The next Git Flow release closes it.
2. **Owner questions still open:** whether `/v1` should ever expose the organization currency; whether a dated rate
   history is wanted; the audit of the other organization settings fields (`name`, webhook defaults, `primary_color`).
