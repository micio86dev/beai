# Interview closing greeting

## Objective
A platform-wide, per-locale closing greeting (max 3600 characters), set by the superadmin in the
backoffice global settings next to the intro phrase, that the avatar says only after the LAST
question, when the interview is complete. A generic, short, professional default is seeded.

## Problem / why
The interview ends on the server-owned `final_phrase` ("Thank you for your time."), with no
configurable closing. The owner wants a proper farewell, configurable like the intro phrase.

## Design decisions
- Storage mirrors the intro: `platform_settings` row `interview_closing_phrase`, value
  `{"en": "...", "it": "..."}`; typed accessor in `PlatformSettings`; PATCH `admin/settings`
  accepts `interview_closing_phrase` (nullable map, `en` required when set, max 3600 per locale).
- Delivery: on the LAST competency only, the advance phrase becomes
  `"<closing greeting> <final_phrase>"`. Completion detection (normalized contains-match on
  `final_phrase`, Tavus waits for `stopped_speaking`) is unchanged, so the frontend needs no
  change. Applies to both the per-competency prompt (`buildAdvanceSection`) and the Tavus
  single-session plan (`ComposeConversationPlan`).
- Validation: the closing text must contain neither completion phrase. An `end_phrase` would end a
  competency early; a `final_phrase` inside the greeting would end the interview before the greeting
  is over (the client contains-matches it). Same `NoCompletionPhrase` rule as the intro.
- Default: seeded by migration only when no row exists (never overwrites an admin edit).
- Backoffice: the intro and closing forms group their locales in Tabs (existing
  `components/ui/tabs`), one textarea per tab.

## Scope
api (setting, validation, audit, delivery, seed, OpenAPI), backoffice (form, tabs, i18n, tests,
codegen), wrapper (DESIGN.md if UI rules change, pins). Frontend: no change expected.

## TDD
Strict TDD on. Runners: api `vendor/bin/pest` (serialize: one Pest run at a time), backoffice
`bunx vitest run` + Playwright.

## Tasks
- [x] T1 api: setting + request validation + audit + response + default seed migration (delegated writer; `5c60db3`)
- [x] T2 api: deliver the closing greeting on the last competency (prompt + single-session plan) (delegated writer; `5c00545`, `1fafb1c`, `4da34a2`)
- [x] T3 api: OpenAPI re-export, release 0.75.0 (`984544e`; review fix `e66ed21` refuses the final
  phrase inside the closing too — HeyGen contains-matches it and would cut the greeting short)
- [x] T4 backoffice: closing form + locale tabs, i18n, tests, codegen, release 0.54.0 (delegated writer
  `5f77bca` `4ea143d` `e314ecd` `97038b4`; `b0b704b` clears a locale error on edit). Vitest 4125, e2e 26/26.
- frontend 0.27.4: api 0.75.0 spec sync only (`a79efb1`), required by the wrapper's identical-openapi gate.
- [x] T5 wrapper: pins + release, deploy, verify in prod (wrapper v0.58.0, PR #131; 4-lens review approved; all 5 Railway services SUCCESS, api ready ok, default closing row present in prod)

## Progress
- 2026-10-15: document created; exploration done (intro phrase mapped end to end).
- 2026-10-15: api T1+T2 done. Full Pest: 9734 passed, 12 skipped, lines 98.25%; pint + phpstan clean.
  Native review approved (lineage review-a36f79f7e55b6170, acknowledged). Kept the closing read on
  every /start (the Tavus single-session plan is built at the first start). Public v1 spec unchanged
  except the version.
- 2026-10-15: all native reviews approved and acknowledged (api, backoffice, frontend sync). DESIGN.md
  §8.2.1 gains the locale-tabs-in-a-form rule. Waiting on the three release CIs, then T5.
