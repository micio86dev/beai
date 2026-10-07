# HeyGen third-party voices (Cartesia / ElevenLabs)

## Objective
A superadmin can pick a Cartesia or ElevenLabs voice on a HeyGen avatar template of the PLATFORM
(`/platform-templates`), the same way Tavus templates already do with `ttsEngine` + `ttsExternalVoiceId`.

## Problem
Owner report 2026-10-03: with HeyGen there is no selector for a Cartesia (or other provider) voice, neither
creating nor editing a template. Only Tavus has it. HeyGen only has `voiceId`, validated against LiveAvatar's own
catalogue, which is 100% English (diagnosis 2026-09-22). No code calls LiveAvatar `POST /v1/voices/third_party`.

## Decisions (owner, 2026-10-03)
- First cut: PLATFORM templates only (superadmin). Org-admin editing of this field comes later.
- BEAI platform keys only (the ones the catalogue and previews already use). No per-tenant keys.
- A bound voice and its secret are KEPT after a template is deleted (shared across templates); orphan sweep later.

## Design (A)
- HeyGen config gains `ttsEngine` (cartesia | elevenlabs | none) + `ttsExternalVoiceId`, reusing the Tavus field specs,
  catalogue pickers and Cartesia/ElevenLabs voice catalogues.
- On save a new `HeygenVoiceRegistrar` (modelled on `HeygenLlmRegistrar`, never throws) does
  `POST /v1/secrets {secret_type: CARTESIA_API_KEY|ELEVENLABS_API_KEY}` once (memoised), then
  `POST /v1/voices/third_party {provider_voice_id, secret_id, name}`; the returned `voice_id` becomes
  `avatar_persona.voice_id`. A ledger keyed `(engine, provider_voice_id)` makes the bind idempotent.
- `voice_settings.*` must use the provider-discriminated shape LiveAvatar documents (cartesia / elevenLabs).

## Must be verified LIVE before relying on it
Language tag of a bound voice (`VoiceSchema.language`), repeat-bind idempotency (duplicates?), org-wide reuse,
what `GET /v1/voices?voice_type=private` returns. Any test bind is cleaned up (DELETE) afterwards.

## Constraints
- Repo language English; strict TDD (api: `vendor/bin/pest --parallel --no-coverage`; backoffice/frontend: Vitest via bun).
- AuthMatrix catalogue + fixtures for any new route; OpenAPI export + typed clients regenerated; exposure guard.
- Spoken language still follows the project (never overridden by the template).
- Branches `feature/heygen-third-party-voices` in api/backoffice/frontend/wrapper. Work-unit commits. Delivery: ask-on-risk.
- Route: delegated writer (writer trigger: 2+ non-trivial files across repos). Tests/builds per task; native review per slice.

## Tasks
- [x] H1 Live verification against LiveAvatar (bind, list, language, duplicates, delete) with the local key; report facts
- [x] H2 API: field specs, validator, payload, `HeygenVoiceRegistrar` + ledger migration, platform-template save hook, tests
- [x] H3 Backoffice: platform HeyGen form shows the engine + voice picker (and previews), i18n it/en, unit + Playwright
- [ ] H4 OpenAPI sync (frontend/backoffice), full suites (done); rebuild local images and owner check of the selector: PENDING (owner)
      2026-10-05 owner: the HeyGen engine/model/voice fields are now visible on create/edit (Template avatar and Template piattaforma). Still unverified: a real bind on save, a real interview with the bound voice, ElevenLabs.

- [x] H5 Scope change (owner, 2026-10-04): SUPERADMIN only on BOTH pages (`/avatar-templates` and `/platform-templates`), plus the `ttsModelName` ("Modello vocale") selector
- [x] H6 Owner report (2026-10-05): with Cartesia, the "Voice stability / similarity / emphasis / expressiveness" knobs are not supported by HeyGen, so they must be visible only when settable (create and edit).
      Route: inline (small, 2 api files + 1 test file, 1 spec file; understood). TDD: strict, runner `php artisan test` (api) / `bun run vitest` (backoffice).
      Fix: the four knobs are declared superseded by `ttsEngine=cartesia` (derived from `HEYGEN_ENGINE_UNSUPPORTED_KNOBS`, one source), so the existing form mechanism hides them and drops their value; a knob sent anyway keeps `tts_setting_unsupported`.
      RED seen (api), mutation seen (backoffice: breaking the declared engine turned 3 tests red). api C14 582 passed; pint, phpstan clean; backoffice spec 34 passed, eslint, prettier, typecheck clean.
      Commits: api 07dfa06, backoffice 0f4a365. Assessed medium, 53 lines, review_due=false (under_budget): stays pending in the slice.
- [ ] H7 Native review follow-up (2026-10-06): the api candidate (9 commits, 29 files, 2585 lines, base 63e1f3f) was APPROVED and acknowledged with 3 advisory findings, none blocking.
      R3-001 (WARNING, do first) `app/Actions/AvatarTemplates/BindHeygenTemplateVoice.php:65-67`: every `HeygenVoiceRegistrar` failure code is surfaced under the `config.ttsExternalVoiceId` validation key, including platform misconfiguration (`tts_provider_unconfigured`, `tts_vendor_key_missing`) and transient lock contention (`tts_bind_busy`), so the user sees an error on a field that is not at fault. Fix: only per-voice codes map to the field; the others become a non-field error (server/transient) with the right HTTP class.
      R3-002 (SUGGESTION) `tests/Feature/C14/HeygenExternalVoiceTemplateTest.php:111-123`: add the case of `ttsModelName` alone refused with `superadmin_only` for a non-superadmin.
      R3-003 (SUGGESTION) `app/Http/Controllers/AvatarTemplatePortabilityController.php:131-141`: on import, the catch collapses the field-keyed errors into one imploded string and loses the field key; keep the key.
      Route: delegated writer (api, 3 files + tests) after the owner confirms the order. TDD: strict, runner `php artisan test`/Pest. Findings alone do not widen scope: R3-002 and R3-003 are optional until accepted.
      DONE 2026-10-06 (owner started H7 immediately): api 0ab739b (R3-001: `tts_provider_unconfigured`, `tts_vendor_key_missing`, `tts_bind_busy` answer 503 `{message: code}`, `tts_secret_failed` 502; per-voice codes stay 422 on `config.ttsExternalVoiceId`), 46cf63b (R3-002, mutation proven), 5218987 (R3-003). Pest C14+Arch 713 passed, AuthMatrix+PublicApi 2203 passed, pint and phpstan clean, openapi.json byte-identical (no client sync). Parent spot check: HeygenExternalVoiceTemplateTest 43 passed.
- [x] H8 (done 2026-10-06, backoffice 3f19c1a; RED 6 failed then GREEN 29 passed; full unit 217 files / 3611 tests; typecheck, lint 0 errors; Playwright chromium+webkit on both pages 28 passed; parent spot check of the form spec 29 passed; 164 lines added; assessed with H7: medium, under budget) Consequence of H7 found by the parent: the backoffice `AvatarTemplateForm` watcher only reads field errors (`getErrorFields` returns null for a `{message: code}` 502/503 body), so `tts_bind_busy`, `tts_provider_unconfigured`, `tts_vendor_key_missing` and `tts_secret_failed` would now be silent. The existing copy `avatar_templates.error.config.<code>` (it/en) must reach the operator (summary list or banner) on both `/avatar-templates` and `/platform-templates`. Route: delegated writer (backoffice: form + page wiring + spec). TDD strict, runner Vitest; Playwright only if quick.

- [x] H9 (done 2026-10-06, backoffice 7c5c15b R3-001, b742b19 R3-002, 628d249 R3-003; RED 1 failed then GREEN 100 passed; mutation proofs recorded; full unit 217 files / 3619 tests; typecheck, lint 0 errors, Playwright chromium+webkit 28 passed; parent spot check 77 passed; 102 lines from the reviewed boundary, medium, under budget). Note: `sentry-scrub.spec.ts` (timing ratios) is flaky under load, passes alone. Native review follow-up for the backoffice candidate (2026-10-06; base 1fed2ea, 9 commits, 17 files, 2106 lines, medium): APPROVED and acknowledged, 3 advisory findings, none blocking.
      R3-001 (WARNING) `AvatarTemplateForm.vue` ~141: the render loop uses `visibleFields` but the submit-error watcher builds `activeKeys` from the unfiltered `activeFields`, so a 422 for a hidden superseded field is claimed onto a control that is not rendered and vanishes. Fix: build `activeKeys` from `visibleFields` so it falls to the summary.
      R3-002 (SUGGESTION) `configFieldsClass` ~502 counts `visibleFields` instead of `activeFields` for the two-column layout: pin the intended count with a test.
      R3-003 (SUGGESTION) `app/utils/superseded-fields.ts` ~23: `isSuperseded` honours string governing values only; pin and document the string-only contract.
      Route: delegated writer (backoffice: 1 component + 1 util + specs). TDD strict, Vitest.

## Acceptance
On `/platform-templates` a HeyGen template shows an engine selector and a Cartesia/ElevenLabs voice picker; saving binds the
voice on LiveAvatar and sends the bound voice id; saving twice does not duplicate; no key reaches the browser.

## Progress / evidence
2026-10-03 exploration done (read-only mapper). No code written yet.

- H1 (live, 2026-10-03, platform Cartesia key, Italian voice "Elena"; owner-authorized, all created ids deleted, GET 404 verified):
  bind works (secret `data.id`, bind `data.voice_id`); bound voice `language` is always `en` (gender unknown, tags Cartesia/Imported);
  the bind is NOT idempotent (3 identical binds = 3 voice ids); bound voices are listed under `voice_type=private`;
  LiveAvatar accepts ANY provider voice id with 200 (bogus uuid and a garbage string both created voices); an unknown
  `secret_id` answers 400 `code 4000`. Side effect to know: the pre-existing private test voice `beai-test-it-fabio`
  (57e177c7, 2026-09-29, no local template referenced it) was gone after the cleanup; cause not determined (no further live calls).
  Owner: no further LiveAvatar calls from development; the owner exercises the real bind from the UI.
- H2 (api, branch `feature/heygen-third-party-voices`): 64f112f registrar + ledger, 115752a platform HeyGen `ttsEngine` +
  `ttsExternalVoiceId` (platform-only), strict catalogue check before bind, bound id derived from the ledger at session start
  (config stores only the vendor voice id: one source of truth, no drift, no dead `voiceId`), discriminated `voice_settings`
  (UNVERIFIED on a live session), native-voice payloads byte-identical. Mutation checks: ledger short-circuit (4 red), superadmin
  gate (6 red), platform_only refusal (3 red), strict catalogue check (2 red). Serial CI-equivalent run (pest --coverage --min=85): 7982 tests, 7964 passed, 18 skipped, 0 failed, exit 0; pint and phpstan clean.

- H3 (backoffice): 563ce4c form + platform page on the platform field-specs route, 38c796d spec sync. Vitest 3518 passed; Playwright
  `Platform templates` 28 passed (chromium + webkit); typecheck clean. frontend 4d89692 spec sync: typecheck ok, Vitest 2081 passed.
  `verify-openapi-parity.sh`: identical across the 3 repos.
- UNVERIFIED (no live calls allowed): the discriminated `voice_settings` and a bound `voice_id` in a real LiveAvatar session.

- H5: api 4db3078 (org routes accept/bind for a superadmin, refuse others with `superadmin_only`, org field-specs list the fields for a superadmin
  only, `ttsModelName` added), spec sync frontend 6c681e7 / backoffice a8e903b, backoffice 1e5420c (always-visible engine/model/voice fields like Tavus,
  Playwright on /avatar-templates as superadmin and org admin, create + provider switch on /platform-templates). Mutations: gate open to all (1 red),
  specs leaked to org admin (1 red), gate closed to superadmin (15 red). api parallel 7986 tests 0 failed; serial `--coverage --min=85` exit 0, 95.7%;
  backoffice Vitest 3525, typecheck, Playwright 32+4 passed; frontend Vitest 2081.
- R3-SUPERADMIN-FIELD-LOCKOUT (native review warning) is not reachable today: an organization admin cannot create or edit templates at all (policy 403), so a non-superadmin never resubmits these fields; revisit if org-admin editing is ever opened.

## Next step
Owner: rebuild api + backoffice images, bind a voice from the UI, run one interview and listen.
