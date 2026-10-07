# Integrity toasts, "Prontezza" naming and e2e stability

Feature: three owner requests of 2026-10-07 after the 0.67.1 / 0.48.1 / 0.23.1 / 0.52.1 release.

## Objective
1. The proctoring integrity toasts finally reach the candidate (a `<Toaster>` is mounted), localized, accessible and legible on the brand canvas.
2. The assessment type previously shown as "Standard" is named "Prontezza" (English "Readiness") everywhere a person reads it, across the submodules.
3. The WebKit e2e instability that makes a CI run fail is removed at its cause, shipped as a Git Flow hotfix.

## Problem
- `IntegrityToast` fires vue-sonner toasts but no `<Toaster>` exists anywhere (confirmed pre-existing on origin/develop), so a candidate never sees an integrity warning; mounting one naively would show raw event types.
- "Standard" appears as a visible label in the backoffice i18n (17 lines per language), in api `lang/*/messages.php` sentences and in documents; the machine value `standard` also exists in api (39 occurrences in 25 files in app, 17 database files, 86 test files), in both OpenAPI specs (15 occurrences), 4 SDK files and 7 backoffice files, and the same value names the competency `type` (`standard|potential`).
- With `failOnFlakyTests` one random WebKit timeout fails a CI run (seen: `locator.click` on the "Ruolo" option of `projects-crud`, "element not stable" for 30 s, passing on retry; earlier `page.goto` timeouts under load).

## Decisions (owner, 2026-10-07)
- Toaster: mandatory.
- Naming: "Standard" becomes "Prontezza" everywhere, with English translations where needed, in every submodule: IT "Prontezza", EN "Readiness" (the BEAI brief already calls the standard type "readiness"). DECIDED by the owner 2026-10-07: the machine value stays `standard` (DB, enums, API payloads, both OpenAPI specs, SDKs, i18n keys); "Prontezza" is a display name only, so the public API v1 contract and the SDKs do not change.
- CI stability: a dedicated hotfix via Git Flow (cut from main, merged to main with a patch tag and back to develop).

## Constraints
- Strict TDD; Vitest/Playwright for the Nuxt apps, Pest for api; coverage stays above the 85% gates (measured 2026-10-07: api 95.8%, frontend lines 95.5%, backoffice lines 96.8%).
- DESIGN.md is authoritative (toast motion in section 10, contrast in 9.1, brand canvas 7.0.1); amend it first if a rule changes.
- Machine-facing values are not localized; every visible string goes through i18n (it, en).
- Native review is offered per candidate; consent is relayed, never answered for the owner.
- Releases follow `api-first-release-order` (both api specs, consumer sync, SDK regeneration in the wrapper).

## Tasks
- [x] T1 e2e stability hotfix (backoffice, from main): reproduce the flake with a measured rate, remove the cause, prove it with a repeat run, hotfix release.
- [x] T2 Toaster (frontend): mount a localized, accessible Toaster, map every integrity event type to copy, test and verify on the brand canvas.
- [x] T3 "Prontezza" labels: backoffice i18n and app strings, api `lang` sentences, wrapper documents, tests and e2e text; English "Readiness".
- [x] T4 Machine-value rename of `standard`: DECIDED NOT to rename (owner, 2026-10-07). No code change; the display-name mapping is documented in the wrapper docs by T3.

## Acceptance
- T1: the repeat run of the flaky specs under load shows 0 flakes where the baseline showed some, and one full CI run is green first time.
- T2: an integrity event shows a localized toast in it and en, readable on yellow, violet, blue and no brand colour, announced to assistive technology, with no raw event keys.
- T3: no visible "Standard" for the assessment type remains in it or en in backoffice, api messages and documents.

## Progress
Created 2026-10-07.

## Route declaration
Delegated writers in isolated worktrees, one per task; the api writer is the only one running Pest at a time.

## Next step
All tasks closed. Released 2026-10-07: api 0.68.0, frontend 0.24.0, backoffice 0.49.0 (hotfix 0.48.2 for the WebKit flake: backdrop-blur overlays), wrapper 0.53.0; production health 200 on all five Railway services. Open optional items: reduced-motion gating of vendored popovers (DESIGN.md §10), Lighthouse tooling, e2e sharding.
