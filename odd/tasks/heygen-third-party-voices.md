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
