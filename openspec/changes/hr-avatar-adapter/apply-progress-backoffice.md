# Apply progress: backoffice (work unit B1)

Change `hr-avatar-adapter`. Repo `backoffice`, branch `feature/extract-avatar-service`. Mode: Strict TDD.
Status: **DONE (B1 committed; see 'Eighth attempt'). Earlier status: PARTIAL. 9.1 DONE (openapi synced from api 8ec96fa, INTERIM members removed). Code, tests and all local gates are done and STAGED; the commit is STILL BLOCKED by the gga pre-commit review (see 'Second attempt'). No commit exists.**

## Task state

| Task | State | Note |
|------|-------|------|
| 9.1 sync openapi + codegen | done | `cp ../api/openapi.json openapi.json && bun run codegen` (api `8ec96fa`); the two INTERIM members deleted, so `CatalogueResource`/`CatalogueProvider` are now `CatalogueQuery['resource'|'provider']`. RED first: after the sync the guard spec failed 2/3 until the members were removed; then 3/3. `bun run codegen:check` exit 0 |
| 9.2 RED spec | done | see TDD evidence |
| 9.3 types | done | `ProviderName` unchanged; `TemplateProvider`, `FieldSpecMap`, `hr_avatar_config_id?`; INTERIM catalogue union members (deviation 1) |
| 9.4 combobox | done | `manualOnEmpty`, `previewProvider`/`blockPreview` narrowing, no image preview for `avatar_config`, `aria-controls` only while the panel exists |
| 9.5 form | done | |
| 9.6 page + i18n | done | |
| 9.6a types only | PARTIAL | `avatar-templates/index.vue` done. `platform-templates/index.vue` deliberately NOT touched (deviation 3) |
| 9.7 close (focused, full, lint, typecheck, gga, commit) | BLOCKED at gga | focused/full/lint/typecheck green; gga rejects (see below); no commit |
| 9.8 final verification | partly done | coverage green (below); `tests` diff is only `A`; e2e not run (stack not up, CI runs it unchanged) |

## TDD cycle evidence

| Unit | RED (observed) | GREEN | REFACTOR |
|------|----------------|-------|----------|
| `tests/unit/avatar-template-form-hr-avatar.spec.ts` (form, picker, manual entry, 422, edit, combobox, copy, ProjectTable, a11y wiring, LLM-leftover) | first run before any production change: 26 failed, 2 passed (the 2 are the default-path invariance cases, which must already pass) | 28/28 after the change; later additions 45/45 | prettier + eslint clean |
| `tests/unit/avatar-templates-page-hr-avatar.spec.ts` | mutation: page file restored to base, 2/2 fail; then patch re-applied | 2/2 | |
| `tests/nuxt/avatar-template-provider-types-contract.ts` | mutation: `TemplateProvider = ProviderName` makes nuxi typecheck exit 2 with TS2322 at contract line 25 | typecheck exit 0 | |
| `tests/unit/avatar-template-catalogue-types-sync.spec.ts` | mutation: dropping the hand `\| 'hr_avatar'` fails it | 3/3 | |
| LLM-leftover case (gga finding, real bug in this change) | mutation: removing the `hr_avatar \|\|` guard fails the new test | passes | |

## Work Unit Evidence

| Evidence | Value |
|----------|-------|
| Focused test | `node node_modules/.bin/vitest run tests/unit/avatar-template-form-hr-avatar.spec.ts` exit 0, 45 tests; with the other avatar-template form/page specs 352 passed |
| Full suite with coverage | `bun run test:unit:coverage` exit 0: 243 files, 4231 tests (baseline before the change: 240 files, 4190 tests); lines 99.45 / branches 95.67 / functions 96.43 (baseline 99.45 / 95.62 / 96.42; thresholds 99 / 95 / 96) |
| lint | `bun run lint` exit 0 |
| typecheck | `bun run typecheck` (nuxi typecheck + typecheck:e2e) exit 0 |
| drift check | `bun run codegen:check` exit 0 (snapshot matches api, generated client matches) |
| Runtime harness | Vue Test Utils mounts of `AvatarTemplateForm` (real combobox), `ProjectTable`, and the real page module with doubled composables; e2e not run (stack not up) |
| Rollback boundary | the 9 production files listed below + 4 new test files; nothing outside `backoffice/` |

## Files (staged, uncommitted)

Production: `app/types/avatar-template.ts`, `app/components/organisms/AvatarTemplateForm.vue`, `app/components/organisms/AvatarTemplateProviderCombobox.vue`, `app/composables/useAvatarTemplates.ts`, `app/pages/avatar-templates/index.vue`, `app/components/molecules/PalSyncStatus.vue` (prop type only), `app/components/molecules/LlmModelPicker.vue` (optional `invalid`/`describedby` props), `i18n/locales/{en,it}.json`.
Tests (all new): `tests/unit/avatar-template-form-hr-avatar.spec.ts`, `tests/unit/avatar-templates-page-hr-avatar.spec.ts`, `tests/unit/avatar-template-catalogue-types-sync.spec.ts`, `tests/nuxt/avatar-template-provider-types-contract.ts`.
Authored lines: 1051 insertions + 53 deletions = 1104 (tests 840, production 211 added / 53 deleted). Generated files: none. Well above the 400 budget: `size:exception` recommended; the unit cannot shrink without dropping tests (design forecast of ~360 under-counted the test plan, as the tasks forecast already warned for A1/A2/A3).

## Deviations

1. INTERIM hand-widening of `CatalogueResource` (`| 'avatar_config'`) and `CatalogueProvider` (`| 'hr_avatar'`) in `app/types/avatar-template.ts`, because 9.1 cannot run yet. Design says these widen by themselves from the regenerated client. A self-expiring guard spec forces their removal once the snapshot is synced.
2. Extra files vs the task list: `PalSyncStatus.vue` (its `provider` prop was `'heygen' | 'tavus'`; `nuxi typecheck` failed on `avatar-templates/index.vue` without widening it to `TemplateProvider`) and `LlmModelPicker.vue` (a11y wiring requested by gga).
3. `platform-templates/index.vue` not edited: `Record<ProviderName, FieldSpec[]>` is assignable to `FieldSpecMap`, so typecheck needs nothing, and touching that file pulled its unrelated review backlog into gga. Edit it later if the owner wants the type spelled out.
4. The form keeps its existing `watch(submitError)` mapping instead of calling `applyServerFieldErrors`: that watcher already reads `getErrorFields` for every field, and a second walk would duplicate it. A 422 keyed `hr_avatar_config_id` is placed under the picker through it.
5. For `hr_avatar` the page sends `hr_avatar_config_id` and omits `llm_model_id`/`llm_credential_id`; every other body is unchanged.
6. The catalogue-membership refusal (`validateReferences`) is skipped for the hr_avatar id: the proxy lists only startable configs and caches 5 minutes, so absence is not proof the api refuses it.
7. Client-side `^avc_[0-9A-Za-z]+$` check and a "required" check are on the picker; the api stays authoritative.
8. Real defect fixed during gga iteration: a half-set LLM binding left over from heygen blocked an `hr_avatar` submit with no visible error (the LLM fieldset is hidden). Guarded and tested.

## Default-path invariance

- No existing test file was edited, deleted, skipped or weakened: `git diff --cached --name-status -- tests` lists only `A`.
- All 240 pre-existing spec files still pass unedited (243 total = 240 + 3 new unit specs; the nuxt contract is compiled by typecheck).
- Same mount with and without the `hr_avatar` field-specs key: provider options `[heygen, tavus]` vs `[heygen, tavus, hr_avatar]`; heygen payload deep-equal and key order `name, description, provider, config, llm_model_id, llm_credential_id, answer_min_seconds, answer_max_seconds` (no `hr_avatar_config_id`); LLM block still rendered for heygen/tavus.
- `manualOnEmpty` defaults to false: the empty state of every other list is DOM-identical (a `<template>` wrapper, no extra element).

## BLOCKER: gga pre-commit (9 runs, never --no-verify)

gga reviews every whole touched file and returns a different slice of that file's pre-existing backlog on each run. Findings that were mine were fixed (LLM leftover bug, aria-controls on a closed panel, redundant img alt, hand-typed platform list response, a11y wiring of LLM errors, INTERIM drift guard). What still fails on the final tree, none of it introduced by B1:

1. Hand-maintained API types (`FieldSpec`, `CatalogueEntry`, `PalSync`, ...): the standard has no exception clause; gga says amending it "is a decision for the owner".
2. Combobox `load()` collapses every failure to `provider_unreachable`; `<ul role="listbox">` owns non-option controls in the voice list.
3. Form `submitError` watcher shows nothing for a codeless 403/404/409. An existing test (`tests/unit/components/organisms/AvatarTemplateForm.spec.ts`, "ignores a framework prose message (not a bare code)") REQUIRES that silence, so it cannot be fixed without editing an existing test (forbidden). I tried a resource-state banner, the existing test failed, and I reverted it.
4. Form `onMounted` swallows model/credential load failures; name/description server prose is shown raw (an existing test pins that too).

Decision needed from the owner/orchestrator: (a) record the hand-typed-API-types exception and schedule the pre-existing backlog as its own unit before B1, then recommit this staged tree as-is; or (b) authorise editing the two existing tests that pin current behaviour. The tree is staged and ready: `git -C backoffice commit -m "feat(backoffice): offer hr_avatar templates and a config picker when the api reports it"`.

## Open items

- Backoffice e2e not run (stack not up); CI runs it unchanged. No new e2e is needed (design).

## Second attempt (contract sync + recommit)

- Sync done (above). RED for the whole unit re-shown by stashing `app/` + `i18n/` (tests kept): 32 failed / 9 passed across the 3 new unit specs; restored via `git checkout stash -- app i18n`, stash dropped, tree identical.
- Extra fix on lines I touched: `createTemplate`/`updateTemplate` payloads are now `TemplateCreatePayload`/`TemplateUpdatePayload` derived from the generated store/update bodies (same pattern as the platform payloads, `config` re-narrowed to a map; the existing `avatar-template-config-contract.ts` still holds).
- Verification after the sync: `bun run codegen:check` 0; `bun run typecheck` 0; `bun run lint` 0; `bun run test:unit:coverage` 0 (243 files, 4231 tests; lines 99.45 / branches 95.67 / functions 96.43). Per changed file (stmts/branches): LlmModelPicker 100/100, PalSyncStatus 100/95.2, AvatarTemplateForm 99.5/95.6, AvatarTemplateProviderCombobox 98.7/94.0, useAvatarTemplates 98.4/93.2, avatar-templates/index.vue 99.3/91.8, avatar-template.ts 100/-.
- e2e not run (stack not up; docker untouched). `typecheck:e2e` is green.
- gga (2 more runs, never --no-verify) still fails, only on lines B1 did not author: (1) `save()` catch + form `submitError` watcher drop a codeless 403/404/409/network failure silently (an existing test pins silence for a 503 prose message; a narrow 403/404/409 fallback is possible without editing that test but changes default-path behaviour, so it was NOT done); (2) hand-written catalogue/field-spec response types (`CatalogueEntry`, `FieldSpec`, `PalSync`, the `fetchCatalogue` envelope), a documented Scramble limitation. It also lists a "not verified" ARIA risk in the combobox listbox (pre-existing structure). The reported slice changes run to run.
- Tree is staged and ready: `git -C backoffice commit -m "feat(backoffice): offer hr_avatar templates with an HR-Avatar config picker"`.

## Third attempt (authorized gga fixes)

Orchestrator authorized fixing the gga findings. Done, each with a NEW test written first:
1. Silent save errors: the form `submitError` watcher now shows `avatar_templates.error.save.{forbidden,not_found,conflict,network}` (new en/it keys; no generic save-failed key existed) for a codeless 403/404/409 or a failure with no HTTP status. A 503 prose message stays silent (existing test unedited), a coded refusal and a 422 field error are unchanged. The page `save()` catch needed no change: it already forwards the rejection verbatim. RED `tests/unit/avatar-template-form-save-failure.spec.ts`: 7 failed / 3 passed (the 3 are invariance cases), then 10/10.
2. Types: `FieldSpec`, `FieldSpecsResponse`, `CatalogueResponse` and the new `CatalogueEnvelope` (used by `fetchCatalogue`) are now derived from the generated client (the field-specs and catalogue responses are generated now). `PalSync` was already derived. `CatalogueEntry` stays hand-written (Scramble: `items: unknown[]`), with a comment naming `AvatarProviderCatalogue::entry()`; pinned by `tests/nuxt/avatar-template-catalogue-shape-contract.ts` (key exhaustiveness + derived key sets) and `tests/unit/avatar-template-catalogue-api-shape.spec.ts` (compares with the api PHP source when the sibling checkout exists, skips otherwise). Mutation RED: dropping a key from the list fails the unit spec; dropping `preview_video_url` from the interface fails typecheck (TS2322).
3. ARIA: gga did flag it as blocking in one run. Each combobox row is now `<li role="group" aria-label>` (was `role="none"`), so the listbox owns only groups/options. RED `tests/unit/avatar-template-combobox-listbox-aria.spec.ts`: 3 failed / 1 passed, then 4/4. The later gga run reported the listbox structure as compliant.

Verification: lint 0; `bun run typecheck` 0; `bun run codegen:check` 0; `bun run test:unit:coverage` 0 (246 files, 4248 tests; 99.45 / 95.68 / 96.43). One run showed a transient unrelated failure in `tests/unit/pages/settings/index.spec.ts` (`tabsListVariants is not a function`, passes alone 33/33 and on rerun).

Still BLOCKED: gga keeps surfacing NEW findings on lines B1 did not author, a different set every run: raw server prose for `name`/`description` 422 messages and `hasTranslation ? t : message` fallbacks in the form watcher (existing test pins the prose), the page load-error copy for 403/404, hard-coded `*` and parentheses, `HR_AVATAR_FIELD`/`EXTERNAL_TTS_ENGINES` constants, `importTemplates` hand-typed return (the generated import response is `unknown[]`), `PAL_SYNC_CODES` mirroring a PHP enum. None is on a changed line; fixing them edits default-path behaviour or existing tests. Tree is staged (19 files); no commit.

## Fourth attempt (separate cleanup commit before B1) — STOPPED at the gga cap

B1 is NOT in the working tree: it is saved as `git stash@{0}` ("b1-staged") in `backoffice` and as a patch at `/private/tmp/claude-501/-Users-alessandromicelli-Desktop-beai/1704da6a-e9c8-4671-9564-13765d8dbdb1/scratchpad/b1.patch`. The cleanup (base `e540d54`) is STAGED, not committed; gga raised new findings on all three passes (first full pass plus the two allowed rounds). Cleanup content: form 422 messages and fallbacks localized (`avatar_templates.error.{invalid_name,invalid_description,invalid_value,save.*}`), page load error by failure class (`resourceErrorKey`), required marker via CSS and the withdrawn suffix via i18n, one `EXTERNAL_TTS_ENGINES` list, `importTemplates` and `PlatformTemplateListResponse` derived from the generated client, `PAL_SYNC_CODES` pinned to the api source, LLM error aria wiring, codeless 403/404/409/network save failures. Existing tests edited: `tests/unit/avatar-template-form.spec.ts` (2 tests), `tests/unit/components/organisms/AvatarTemplateForm.spec.ts` (1 test). Gates before the last attempt: lint 0, typecheck 0, test:unit:coverage 0 (246 files, 4223 tests). Last gga list: (1) FieldSpec/CatalogueEntry/CatalogueResponse hand-written (resolved by B1's sync, the base spec cannot type them), (2) `fetchCatalogue` envelope, same cause, (3) `refuse()` in `validateReferences` calls `t(error.config.<code>)` directly instead of `configCopy()`.

## Fifth attempt (commit order: sync, cleanup, B1) — STOPPED at the gga cap on commit 1

State in `backoffice` (branch `feature/extract-avatar-service`, HEAD still `e540d54`): `stash@{0}` = "cleanup-staged" (the localization cleanup, intact), `stash@{1}` = "b1-staged" (B1, intact; patch copy in the scratchpad). Neither stash was dropped. The working tree holds commit 1 (`chore(backoffice): sync the api contract`) STAGED, not committed: `openapi.json` + `types/api.ts` re-synced from api HEAD `7f565a2`, `FieldSpec`/`CatalogueResponse`/`CatalogueEnvelope`/`FieldSpecsResponse` derived from the generated client, `TemplateCreatePayload`/`TemplateUpdatePayload`/`ImportTemplatesResponse`/`PlatformTemplateListResponse` derived, the combobox preview narrowing the sync forces (typecheck fails without it), plus new tests (`tests/nuxt/avatar-template-catalogue-shape-contract.ts`, `tests/nuxt/avatar-template-import-response-contract.ts`, `tests/unit/avatar-template-catalogue-api-shape.spec.ts`, `tests/unit/components/organisms/AvatarTemplateProviderCombobox.spec.ts`). Gates: lint 0, typecheck 0, test:unit:coverage 0 (242 files, 4197 tests), codegen:check 0 against api HEAD (a dirty `api/openapi.json` working tree makes the plain script exit 1). gga: three passes (first plus two extra); the last reports ONE violation, the hand-written `CatalogueEntry` (documented Scramble exception, key set pinned by two tests; the standard has no exception clause). Needs an owner decision: accept the exception or annotate the api so Scramble emits an item schema.

## Sixth attempt (api `e99f5fb` typed catalogue items) — STOPPED at the gga cap on commit 1

`CatalogueEntry` is now derived from the generated client (the blocking finding's root cause is gone); `TemplateResponse` and `PlatformTemplateResponse` are derived too (new `tests/nuxt/avatar-template-single-response-contract.ts`, RED first); the combobox rows are `role="group"` with a conditional `aria-controls` (new `avatar-template-combobox-listbox-aria.spec.ts`, RED first) and its loading status region is a sibling of the trigger button (new `avatar-template-combobox-status-region.spec.ts`, RED first). Commit 1 (`chore(backoffice): sync the api contract`) is STAGED, not committed: lint 0, typecheck 0, codegen:check 0 (plain script), test:unit:coverage 0 (244 files, 4203 tests; 99.45 / 95.66 / 96.42). gga ran three times (first plus two extra); the last pass reports ONE violation: the closed sets `CatalogueEntry.italian`, `PalSync.status`, `CatalogueErrorCode` and `PAL_SYNC_CODES` are hand-written unions with no check against the api source (the `italianIsNarrowed` contract compares a union with itself; the code check in `avatar-template-catalogue-api-shape.spec.ts` only greps docblocks). Proposed fix (needs a further gga attempt): extend the api-shape spec to read the literal sets from `AvatarProviderCatalogue.php` / `TavusPalSync.php` and the status enum. `stash@{0}` cleanup-staged and `stash@{1}` b1-staged are intact.

## Seventh attempt (cap lifted; sync and cleanup committed, B1 blocked on a repeated finding)

Commits in `backoffice` (branch `feature/extract-avatar-service`): `99d28e9` chore(backoffice): sync the api contract; `579b149` fix(backoffice): localize template form errors and tighten template types. B1 is restored on top (10 files staged, merged with both commits; `tests/unit/avatar-template-catalogue-types-sync.spec.ts` dropped because the hand-widening it guarded never reached a commit) but NOT committed. `stash@{0}` "b1-staged" is kept until B1 lands. B1 gates: lint 0, typecheck 0, codegen:check 0, test:unit:coverage 0 (253 files, 4281 tests; 99.45 / 95.85 / 96.43). The gga round on B1 repeats an already-fixed finding: the closed sets (`PAL_SYNC_CODES`, `CatalogueErrorCode`, `CatalogueStatus`, `italian`, `FieldType`, `EXTERNAL_TTS_ENGINES`) are hand-written. Each is pinned to the api source by `avatar-template-catalogue-api-shape.spec.ts`; gga asks to accept the exception or have the api emit enums (an api-side change, to be routed). It also notes `<button role="combobox">` (select-only pattern) as low severity, pre-existing.


## Eighth attempt — B1 COMMITTED (all backoffice work done)

Commits in `backoffice` (branch `feature/extract-avatar-service`, base `e540d54`), in order:
1. `99d28e9` chore(backoffice): sync the api contract
2. `579b149` fix(backoffice): localize template form errors and tighten template types
3. `06eea64` chore(backoffice): sync api enums (api `06ac648`: `CatalogueStatus`, `CatalogueErrorCode`, `PalSync.status/code`, `FieldType`, `italian` now derive from generated enums; `PAL_SYNC_CODES` is a const checked in both directions against the generated union and against `TavusPalSync.php`; `EXTERNAL_TTS_ENGINES` stays hand-written with a comment saying the api exposes it only as runtime `options` data, pinned to `ProviderFieldSpecs.php`; `TemplateResponse.warning` typed `PalSyncCode`; `ProviderName` pinned to the generated field-specs keys)
4. `b11edae` feat(backoffice): offer hr_avatar templates with an HR-Avatar config picker (`OmitStrict` so a narrowing of a dropped field stops compiling; `hr_avatar_config_id` is the generated member; combobox `aria-controls` targets the listbox only while one is rendered)

gga review counts on the final content of each commit (failures before the passing one): sync 5 reviews, cleanup 2, enums 2, B1 3. Gates before the last commit: lint 0, typecheck 0, codegen:check 0, test:unit:coverage 0 (253 files, 4288 tests; 99.45 / 95.85 / 96.43). Existing tests edited (cleanup only): `tests/unit/avatar-template-form.spec.ts` (2), `tests/unit/components/organisms/AvatarTemplateForm.spec.ts` (1). e2e not run (stack not up). Tasks 9.1-9.8 ticked in tasks.md; `platform-templates/index.vue` was deliberately not edited (9.6a deviation 3). The B1 stashes were dropped after their content was committed.

## Ninth attempt (unit B2, review follow-ups) - DONE

Commits in `backoffice` (HEAD was `b11edae`): `80c0332` fix(backoffice): link the manual id input to its error and tell network failures apart (9 files, +277/-17); `f9bf141` test(backoffice): make the avatar template review tests able to fail (5 files, +77/-22). Both passed gga on the first attempt.

| Item | RED / mutation (observed) | GREEN |
|------|---------------------------|-------|
| 1 manual input aria | new spec: 2 failed (one per state), 2 invariance passed | 5/5 (includes a host that flips the error after mount, which a `computed` over non-reactive `attrs` would miss) |
| 2 page load error | mutation `case 500: return 'forbidden'` in error-state.ts: old spec 3/3 pass (defect shown); restructured spec fails the 500 case | 4/4, mutation reverted |
| 3 `te` guard | guard exists in `resolveKey`; mutation removing it: `translator.te is not a function` | t-only double test passes with the guard |
| 4 network copy | 3 generic-copy cases failed (got `save.network`), locale-key test failed | 25/25 with `isNetworkError` spec |
| 5 name refusal | n/a | unchanged: api answers prose only, no codes |
| 6 engine list | mutation (hard-coded `['cartesia','elevenlabs']` in the form) fails the behavioural test; the old source regex would not | 6/6 |
| 7 PalSyncCode guard | hand-written union passed the old regex (13/13); new regex fails it | 13/13 after revert |
| 8 combobox spec | status 'empty' mutation: old spec 3/4 pass vacuously, new spec 0/4 | 4/4 |
| 9 contract | hand union dropping codes: TS2322 at contract lines 40 and 44 (old tautology passed) | typecheck 0 |
| 10 live region | new order test failed (text present at mount) | 2/2; develop spec `avatar-template-provider-combobox.spec.ts` (unedited) forced the panel loading line to lose `role="status"` so exactly one region exists |

Gates (before commit 1 and again at the end): lint 0, typecheck 0, `bun run test:unit:coverage` 0 (255 files, 4308 tests; 99.45 / 95.88 / 96.45), client drift stage 2 0. `bun run codegen:check` plain exits 1 because `../api/openapi.json` has an uncommitted working-tree change (A10 in progress; it matched at the start of this unit); stage 2 was run with `API_OPENAPI_SNAPSHOT=/nonexistent`.

Open: A10 contract sync (`warning` from the generated enum, `hr_avatar_config_id` nullability) once api commits it; gga non-blocking notes: any raw `TypeError` counts as a network failure, a codeless 5xx stays silent (pinned by an existing test), the combobox `preview` prop repeats a provider union. No existing test edited; develop tests untouched.

## Tenth attempt (unit B3: contract sync A10 and review fixes) - DONE

Commits in `backoffice` (HEAD was `f9bf141`): `df073cb` chore(backoffice): sync api contract (5 files, +193/-26, `openapi.json` and `types/api.ts` generated); `1dae127` fix(backoffice): treat only a response-less FetchError as a network failure (4 files).

| Item | RED / mutation (observed) | GREEN |
|------|---------------------------|-------|
| Sync + `warning` derived | after the sync the `generatedEnvelopesDoNotCarryWarningYet` sentinel failed typecheck (TS2322); contract rewritten to derived checks: 4 TS2322 against the old hand-written `warning?: PalSyncCode` | typecheck 0 after deriving `TemplateResponse`/`PlatformTemplateResponse` from the generated envelope |
| gga round 1 finding | "wider than PalSyncCode" was a subset check; mutation re-adding `warning?: PalSyncCode` now fails line 73 (plus 31, 43) | typecheck 0 |
| 4 HeyGen copy | copy for all 12 codes already existed in en/it; the pages gate on `te()` with a generic fallback. New `template-warning-copy.spec.ts` reads the enum from the snapshot: no RED possible (nothing was missing); mutation dropping `it` `llm_config_failed` fails 1 of 13 | 13/13 |
| a `isNetworkError` | 3 failed (bare TypeError, fetch-shaped TypeError, FetchError with a response) | 10/10 |
| b page load-error label | label-only fix to a network-shaped FetchError; passes before and after (the page classifies by status only) | 4/4 |
| c useI18n leak | trailing leak-check test failed without the hooks | 18/18 with `afterEach` restoring the baseline stub |

Deviation: (c) restores only `useI18n` to the `tests/unit/setup.ts` baseline instead of `vi.unstubAllGlobals()`, which would wipe that once-per-file baseline (documented in `useAuth.spec.ts` and `useApi.spec.ts`). The form save-failure spec's bare-TypeError network case was moved to the generic-copy list (the behaviour change in (a)).

Gates: lint 0, typecheck 0, `codegen:check` 0 (plain, api openapi.json clean at `9fa94c4`), `test:unit:coverage` 0 (256 files, 4324 tests; 99.45 / 95.88 / 96.45). gga: commit 1 FAILED once (the subset-check finding, real) then passed; commit 2 passed on the first run. Non-blocking gga note, not fixed: `getErrorFields` casts `errors` to `Record<string, string[]>` without an `Array.isArray` check (pre-existing, unrelated line). No existing develop test edited; e2e not run (stack not up).

## Eleventh attempt (unit B4: cleanup and contract sync) - DONE

Commits in `backoffice` (HEAD was `1dae127`): `fcf738d` fix(backoffice): ignore malformed per-field errors instead of casting them; `a0b646d` test(backoffice): cover a plain Error and a non-Error on the template load failure; `b74b1cf` chore(backoffice): sync the api contract (api `2bd711f`).

| Item | RED / mutation (observed) | GREEN |
|------|---------------------------|-------|
| 1 `getErrorFields` guard | new `tests/unit/http-error-fields-guard.spec.ts`: 5 of 6 failed (string value, non-string member, all-malformed, array body, `applyServerFieldErrors` assigned `"b"` from `"boom"`) | 6/6; guard drops non-`string[]` fields, null for an array body or when nothing usable remains, `{}` stays `{}` |
| 2 BO6-3 plain Error | behaviour already present, no RED possible; mutation `default: return 'forbidden'` in `error-state.ts` failed 4 of 6 incl. both new cases (plain `Error`, non-Error string) | 6/6, mutation reverted (`git checkout`) |
| 3 org delete 409 | n/a | left as is: the org path always reports `organization_count` 1 (a project pins a template of its own organization), so it adds nothing; the platform page already renders it |
| sync | `codegen:check` stage 1 was green against `../api/openapi.json` (clean at HEAD) after the copy; stage 2 green after `bun run codegen` | `types/api.ts` +/-27 lines, typecheck 0 |

Gates on the final tree: lint 0, typecheck 0, `codegen:check` 0, `test:unit:coverage` 0 (257 files, 4332 tests; 99.45 / 95.89 / 96.45). `git diff develop --name-status -- tests`: all `A` except `tests/unit/avatar-template-form.spec.ts` and `tests/unit/components/organisms/AvatarTemplateForm.spec.ts` (the two owner-authorized `M`, not touched in this unit). gga passed on the fix commit (it reviewed `http-error.ts`; it noted the new spec was outside its review set). e2e not run. This closes the earlier non-blocking gga note about `getErrorFields`.
