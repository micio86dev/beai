# Apply progress: hr-avatar-adapter

> Mode: Strict TDD. Store: hybrid (this file + Engram `sdd/hr-avatar-adapter/apply-progress`). Delivery: auto-chain, feature-branch-chain,
> local commits only on `api` branch `feature/extract-avatar-service` (no push, no PR). Wrapper files are committed by the orchestrator.

## Batch 1 (api): A1a, A1b, A2a, A2b - DONE (tasks 1.1-4.9, 33/33)

Phase 0 (branch setup) was done by the orchestrator and is not re-marked here. Tasks 5.x onward (A3a, A3b, A4, A5) and the
frontend/backoffice/wrapper units are pending.

### Commits (api, in order, parent `076da7d` = develop)

| Unit | SHA | Message | Authored lines (generated excluded) |
|---|---|---|---|
| A1a c1 | `8f0a10a` | `test(api): record golden start fixtures for default-path invariance` | +185 -1 = 186 (two golden JSON fixtures, 38 lines, excluded) |
| A1a c2 | `3009330` | `feat(api): add hr_avatar connection settings and template config id column` | +374 = 374 |
| A1b | `4c3b7a5` | `feat(api): add HrAvatarProvider session service` | +635 = 635 (`size:exception` recommended: 230 production + 330 test + 50 helper; no cohesive split exists) |
| A2a | `a35a91d` | `feat(api): select hr_avatar from pinned templates and fail closed when unavailable` | +293 -1 = 294 |
| A2b | `de0ca87` | `feat(api): return hr_avatar join inputs and release hr_avatar conversations` | +404 -1 = 405 (`openapi.json` +15 generated, excluded) |

A1a as a whole is 560 authored lines over two commits (186 + 374); each commit is under the 400 budget.

### TDD Cycle Evidence

| Unit / task | RED (observed) | GREEN | REFACTOR |
|---|---|---|---|
| A1a 1.1-1.3 golden | `HrAvatarDefaultPathInvarianceTest`: 4 failed ("golden fixture missing"), 4 passed (no-HR-Avatar-traffic cases); exit 1 | Recorded on the unmodified base (`git diff --stat develop -- app config database routes` empty, exit 0), then 8/8 green, stable over 3 reruns; mutating a fixture byte makes 2 tests fail | pint, phpstan; helper switched to `Participant::factory()->forProject()` after gga |
| A1a 1.4 connection | `HrAvatarConnectionTest`: 17 tests, 0 passed (class missing) | 17/17 | pint/phpstan clean |
| A1a 1.5 migration | `HrAvatarMigrationTest`: 4 tests, 0 passed (column missing; FK/index test made non-vacuous first) | 4/4 | - |
| A1b 2.2-2.3 provider | 56 tests, 0 passed, all "Target class HrAvatarProvider does not exist" | 56/56. NOTE: the implementation was drafted while the A1a full suite was running and the RED run was taken by moving the file out and back; mutation checks then failed the suite as expected (metadata `[]`, status check removed, ref validation removed) | extracted `classify()`, log vocabulary unified (gga finding), 73/73 with connection tests |
| A2a 3.2-3.5 | `HrAvatarSelectionTest` + `HrAvatarFailClosedTest`: 12 tests, 9 failed (502/500 instead of 422/201, `hr_avatar` stored as the provider), 3 passed (existing mock/tavus precedence, test mode) | 12/12 | extracted `ProviderPreflight::logged()` (behaviour-identical) |
| A2b 4.1-4.5 | 21 tests, 5 failed (3 release tests, missing `hr_avatar` member, release-at-once), 16 characterization cases passed against the untouched controller (4.6: no fix needed) | 21/21; mutations (secret key added to body, client secret logged) each fail the suite | - |

### Work Unit Evidence

| Unit | Focused test command and result | Runtime harness | Rollback boundary |
|---|---|---|---|
| A1a | `php artisan test --filter='HrAvatarConnectionTest\|HrAvatarMigrationTest\|HrAvatarDefaultPathInvarianceTest'` exit 0, 29 passed / 82 assertions | `POST /candidate/interview/start` for Tavus and HeyGen under `Http::preventStrayRequests()` compared byte for byte to the golden fixtures, HR-Avatar settings unset and fully set | `config/hr_avatar.php`, `HrAvatarConnection.php`, the migration, the `AvatarTemplate` fillable/property lines, `.env.example`, `tests/*/HrAvatar*`, `tests/Fixtures/hr_avatar/`, `tests/Helpers/HrAvatarFixtures.php`, the `composer.json` autoload-dev line |
| A1b | `php artisan test tests/Unit/HrAvatar/HrAvatarProviderTest.php` exit 0, 56 passed / 122 assertions | `Http::fake` against the HR-Avatar contract with `assertSent`/`assertSentCount` and captured log records | `HrAvatarProvider.php`, its test, the A1b additions to `HrAvatarFixtures.php`; unreferenced until A2a |
| A2a | `--filter='HrAvatarSelectionTest\|HrAvatarFailClosedTest'` exit 0, 12 passed / 42 assertions | real `POST /candidate/interview/start` requests, container spies prove `HeygenProvider`/`TavusProvider` are never constructed | the `providerNameFor`/`resolveProvider` hunks in `InterviewController.php` and the `hr_avatar` arm + `logged()` in `ProviderPreflight.php` |
| A2b | `--filter='HrAvatarReleaseTest\|HrAvatarInterviewFlowTest'` exit 0, 21 passed / 108 assertions | `/start` -> `/utterance` -> `/end`, resume, suspend, sweep, release job, admin review read, all on `Http::fake`d HR-Avatar | `ReleaseProviderSession.php` arm, `BuildInterviewSessionResponse.php` block, the `@scramble-return` suffix, the 15 `openapi.json` lines |

### Verification results (per unit, run directly, exit codes read from the shell)

| Unit | Full suite `php artisan test --parallel` | pint `--test` | phpstan | Scramble |
|---|---|---|---|---|
| A1a | exit 0, 9826 tests, 9817 passed, 9 skipped (none of them new), 37956 assertions, 365 s | exit 0 | exit 0, 0 errors | n/a (no HTTP surface) |
| A1b | exit 0, 9882 tests (+56), 9873 passed, 9 skipped, 38078 assertions, 300 s. The gga-driven log-vocabulary refactor landed after this run; the unit's 73 focused tests and phpstan were re-run on the final tree and A2a's full suite covers it | exit 0 | exit 0 | n/a |
| A2a | exit 0, 9894 tests (+12), 9885 passed, 9 skipped, 38120 assertions, 342 s | exit 0 | exit 0 | export + `git diff --exit-code openapi.json openapi.v1.json` clean (exit 0), as expected |
| A2b | exit 0, 9915 tests (+21), 9906 passed, 9 skipped, 38228 assertions, 234 s | exit 0 | exit 0 | `openapi.v1.json` unchanged (exit 0); `openapi.json` +15 lines, purely additive: optional `hr_avatar` object (`base_url`, `publishable_key`, both required inside it, not in the response `required` list) on the start 201 |

Coverage line of the A2b full run: the run is not a `--coverage --min=98` run; the 98 gate is task 8.6.

### Task 2.6 measurement (design open question 2, no code change)

Method: `FrameworkCatalogSeeder` inside a transaction on `beai_test` (rolled back, `framework_roles` count 0 afterwards), then the real
`ComposeCompetencyPrompt` (stored `db` prompt set, `SpokenOpening::primary(1, continuation, introSpoken)`, follow-up budget 4, the longest
advance phrase) and `OpeningTextComposer` for every role x competency x locale: 170 compositions (ICO, FLL, MLL, BUL, SRX plus the role-less
`potential` pair, x `it`/`en`), 0 errors.

| Quantity | Max observed | Limit | Where |
|---|---|---|---|
| `system_prompt` chars | **7,589** | 32,000 | `it`, ICO, SLF |
| `opening_text` chars | **387** | 4,000 | `it`, ICO, PRS, variant `first` |

Caveat: no framework default questions are seeded (0 rows), so the authored primaries were a stand-in of four ~300-character lines; operator
authored primaries and a prompt override add to the prompt. The headroom is about 4x, so the live-wiring claim stands and no truncation exists.

### Default-path invariance statement

With `HR_AVATAR_*` unset behaviour is unchanged, evidenced by:

1. No existing test file was edited, deleted, skipped or weakened: `git diff --name-status develop...HEAD -- tests` lists only `A` entries
   (11 new files; two fixtures, nine PHP files). The only modified non-app support file is `composer.json` (one `autoload-dev.files` line for the
   new helper).
2. The golden `/start` fixtures for Tavus and HeyGen were recorded on the unmodified base (empty `git diff develop -- app config database routes`)
   and still match byte for byte after every unit, both with the settings unset and fully set, and neither response has an `hr_avatar` member.
3. Every full-suite run above (exit 0) includes all pre-existing suites unedited; 9 tests are skipped in every run, and none of them is a new test (no new test uses a skip).
4. `git diff --exit-code develop -- openapi.v1.json` is clean; `openapi.json` differs only by the additive optional `hr_avatar` member.
5. No request to an HR-Avatar host is ever sent on the default path (`Http::preventStrayRequests()` + `assertNotSent` over both providers).

### Deviations from design / spec

- `HrAvatarFixtures.php` registered in `composer.json` `autoload-dev.files` (repository rule for helpers shared by more than one test file;
  the Pest `uses()` of the new directories is declared per file, `tests/Pest.php` is untouched).
- Teardown logs use the `ProviderFailureClass` vocabulary for `class` (design D-TEARDOWN said "exception class"); changed after gga flagged the
  mixed vocabulary and the leaked library class name. No behavioural difference.
- `ProviderPreflight::check()`: the existing trailing log block was extracted into `logged()` and reused by the new arm (behaviour-identical,
  proven by the existing suites).
- `issue()` requires the conversation id to match `^conv_[0-9A-Za-z]+$` (same pattern as teardown), a tightening of "starts with `conv_`".
- Pre-request refusals (`integration_unavailable`, `config_id_missing`, `system_prompt_invalid`, `opening_text_invalid`, `language_invalid`) are
  also logged with a fixed reason slug as the `code`.
- The A2a test for the "stored `provider_override` is ignored" case stamps `deleted_at` on the pinned template directly: the model refuses to
  delete a pinned template, and an unresolvable pin is the only state in which override and env default are consulted.

### Issues and gotchas found

- gga (Claude reviewer) is non-deterministic on whole-file reviews: three commits were first refused for findings in untouched code
  (`withoutGlobalScopes()` in `AvatarTemplate` deleted-hook; `$e->getMessage()` in four pre-existing controller log calls) and passed unchanged on
  the retry. Two findings were genuine and fixed (helper used `new Participant` instead of the factory and `fresh()` nullability; mixed `class`
  log vocabulary). Never used `--no-verify`.
- `php artisan scramble:export` dies on its first run after code changes with `Allowed memory size of 134217728 bytes exhausted`
  (`ExportDocumentation.php:26`, writes nothing); a second run or `php -d memory_limit=1G artisan scramble:export` succeeds. Every diff reviewed
  above came from a successful export; the final post-commit export is drift-free (exit 0 for both documents).
- A faked queue captures `dispatchSync`: `ReleaseEndedProviderSessionJob` tests must not call `Queue::fake()`.
- Test-support helper names `hra*` are global functions; keep them unique across files (only `tests/Helpers/HrAvatarFixtures.php` is shared).

### Remaining (as of batch 1)

- A3a (5.x), A3b (6.x), A4 (7.x), A5 (8.x) in `api`; B1 backoffice; F1-F3 frontend (blocked on HR-Avatar SDK slice); W1 wrapper.
- The api branch currently has 5 commits ahead of `develop` and a clean working tree.

## Batch 2 (api): A3a (committed earlier), A3b, A4, A5 - DONE (tasks 5.x-8.7)

Resumed after an interrupted writer; the uncommitted A3b tree was reviewed against phase 6, verified, and committed.

| Unit | SHA | Message | Authored lines (generated excluded) |
|---|---|---|---|
| A3a | `131c33e` | `feat(api): accept hr_avatar templates with a config id when available` | (committed by the interrupted writer) |
| A3b | `9e18a96` | `feat(api): export, import and duplicate the hr_avatar config id and classify its exposure` | +315 -28 = 343, minus 9 generated `openapi.json` lines = 334 |
| A4 | `0b1b773` | `feat(api): proxy organization-scoped HR-Avatar configs through the catalogue` | +425 -21 = 446, minus 12 generated lines = 434 (322 are tests; 112 production). Over the 400 budget: the proxy, its cache-key/TTL change and the controller arm have no cohesive split; `size:exception` recommended |
| A5 | `8ec96fa` | `feat(api): add hr-avatar:export-templates dry-run command` | +454 (172 production, 282 test). `size:exception` recommended: one command and its 20 tests |

### TDD Cycle Evidence (batch 2)

| Unit / task | RED (observed) | GREEN | REFACTOR |
|---|---|---|---|
| A3b 6.1-6.6 (code written by the interrupted writer) | Mutation RED: the production hunks of `app/` were reverted with `git apply -R` and `HrAvatarTemplatePortabilityTest` + `HrAvatarExposureTest` re-run: 21 tests, 10 failed + 1 error (hr_avatar import reported `Unknown provider`, heygen id not validated, duplicate dropped the id, export lacked the member, `AvatarTemplateExport` classification gain empty); production restored with `git apply` | 21/21; 684/684 over `AvatarTemplate\|HrAvatar\|Exposure` after the refactor | gga: the id regex and length were repeated in three places, now `HrAvatarConnection::CONFIG_ID_REGEX`, `CONFIG_ID_MAX_LENGTH`, `isConfigId()`; the `conditionalExclusions()` docblock now says the `InterviewStart` entry is the candidate's own response, not admin-only |
| A4 7.1-7.2 | Mutation RED on the committed unit (the A4 `app/` hunks reverted with `git apply -R`, then restored): `HrAvatarCatalogueProxyTest` + `HrAvatarDefaultPathInvarianceTest` 37 tests, 17 passed, 17 failed, 3 errors (422 for `hr_avatar`/`avatar_config`, `array_column(null)`); the 17 passing are the pre-existing golden cases and the unavailable-path cases | 23/23 proxy tests, then 607/607 over the catalogue, template and invariance suites | mutations each failed the suite: row `external_ref` check removed (1 test), `external_ref` dropped from the query (2 tests), TTL back to 24 h (1 test). gga-driven: `request()` gained an `authScheme` argument so the empty-key guard sees the raw key; the `catalogue()` docblock said `unavailable` where the code returns `provider_error` (see deviations) |
| A5 8.2-8.3 | `ExportTemplatesToHrAvatarTest`: 20 tests, 0 passed (command missing) | 20/20 | mutations each failed the suite: `whereNull` predicate removed (concurrent test), provider filter removed (dry run lists native templates), template `config` sent raw (tts keys leak); gga-driven: array shape on `body()`, outcome parsing without `strtok`, orphaned upstream config id printed on `write_conflict` |

### Work Unit Evidence (batch 2)

| Unit | Focused test command and result | Runtime harness | Rollback boundary |
|---|---|---|---|
| A3b | `--filter='HrAvatarTemplatePortabilityTest\|HrAvatarExposureTest'` exit 0, 21 passed / 68 assertions | real `GET /export`, `POST /import`, `POST /{id}/duplicate` with `Http::preventStrayRequests()` | the A3b hunks of `TemplateDocument.php`, `AvatarTemplatePortabilityController.php`, `DuplicateAvatarTemplate.php`, `HrAvatarConnection` id constants, the `AvatarTemplateExport` entry of `ExposureCatalogue.php`, 8 `openapi.json` lines |
| A4 | `--filter='HrAvatarCatalogueProxyTest\|HrAvatarDefaultPathInvarianceTest\|AvatarProviderCatalogue\|TavusPal\|AvatarTemplate'` exit 0, 607 passed | real `GET /api/avatar-templates/catalogue?provider=hr_avatar&resource=avatar_config` over `Http::fake` incl. cursor paging, TTL via `travel()` | `cacheKey()`/`fetch()`/`fetchLive()` parameters, `hrAvatarConfigs()`, `request()` `authScheme`, the controller arm and docblock, the query enums in `openapi.json` |
| A5 | `--filter=ExportTemplatesToHrAvatarTest` exit 0, 20 passed / 109 assertions | `Artisan::call('hr-avatar:export-templates')` against the real schema, `Http::fake` for HR-Avatar | the command file and its test (unreferenced elsewhere) |

### Verification results (batch 2)

| Unit | Full suite `php artisan test --parallel` | pint | phpstan | Scramble |
|---|---|---|---|---|
| A3b | exit 0, 9963 tests, 9954 passed, 9 skipped, 38397 assertions, 226 s | exit 0 | exit 0, 0 errors | `openapi.v1.json` unchanged (exit 0); `openapi.json` +8 -1 lines, additive: `hr_avatar_config_id` (string\|null) on the export document item |
| A4 | exit 0, 9990 tests, 9981 passed, 9 skipped, 38495 assertions, 267 s (run before three gga-driven tweaks, covered by A5's full run) | exit 0 | exit 0 | `openapi.v1.json` unchanged (exit 0); `openapi.json`: `hr_avatar` added to the `provider` enum, `avatar_config` to the `resource` enum, one description line corrected (see deviations) |
| A5 | exit 0, 10010 tests, 10001 passed, 9 skipped, 38604 assertions, 243 s | exit 0 | exit 0 | n/a (no HTTP surface) |

### Task 8.1 parity check (read-only)

Compared the config keys the command sends (template config minus `ttsEngine`/`ttsExternalVoiceId`, plus `voice {engine, voice_id}`) with
`hr-avatar/service/app/AvatarProviders/{LiveAvatar/LiveAvatarFieldSpecs,Tavus/TavusFieldSpecs}.php`. **They do NOT match.**

- `heygen`: HR-Avatar `config` keys are `avatarId, interactivityType, videoQuality, voiceSpeed, voiceStability, voiceSimilarityBoost, voiceStyle,
  voiceUseSpeakerBoost, ttsModelName`. BEAI keys with no HR-Avatar counterpart: `voiceId` (HR-Avatar models the voice as the `voice` binding),
  `maxSessionDurationSec`, `videoEncoding`.
- `tavus`: HR-Avatar uses snake_case and splits config and persona: config `replica_id, persona_id, participant_left_timeout, tts_model_name`; persona
  `llm_temperature, llm_speculative_inference, turn_taking_patience, interruptibility, voice_isolation, idle_engagement`. BEAI keys `faceId`, `palId`,
  `audioOnly`, `maxCallDurationSec`, `participantAbsentTimeoutSec`, `enableRecording`, `enableClosedCaptions`, `llmTemperature`,
  `llmSpeculativeInference`, `turnTakingPatience`, `voiceIsolation`, `idleEngagement` and `ttsModelName` do not exist there as sent; only
  `interruptibility` is identical.

Consequence (fails safely): any real Tavus template, and any HeyGen template carrying `voiceId`, `maxSessionDurationSec` or `videoEncoding`, will be
rejected by HR-Avatar (`provider_rejected`), keep a null id and exit non-zero. **A non-local `--apply` claim is blocked** until a key mapping
(BEAI to HR-Avatar names, and the Tavus persona split) is specified; the design says the command sends the config as stored, so that mapping is a
spec/design change and was NOT improvised here.

### Deviations and decisions (batch 2)

- **Export document is documented as required.** Scramble infers `hr_avatar_config_id` as a required nullable member of the export item, while the
  document omits it when null. A precise `#[ResponseDoc]` shape makes it optional but rewrites other existing schema lines (`schema` const,
  `config`/`persona` array vs object, two descriptions), which breaks "`openapi.json` additive except A6", so the inferred (additive) schema was kept.
  The runtime behaviour (omission when null) is proven by tests. Decision for the orchestrator: accept, or approve the larger `ResponseDoc` diff.
- **One existing description line changed** in `openapi.json` (A4): the `catalogue()` docblock promised `{status: "unavailable", items: []}` but the code has
  always returned `{status: "provider_error", items: [], code}`; gga failed the commit twice on it, so the prose now matches the behaviour and names the
  organization configs. No schema change.
- `fetch()` returns `{status: empty}` for `hr_avatar` with a null organization inside the catalogue class (not only in the controller) so Scramble keeps
  inferring the 200 body from the single `fetch()` call (a ternary of two calls collapsed it to `string`).
- `request()` gained an optional trailing `authScheme` argument (`'Bearer '`), default empty: existing callers are untouched.
- `isConfigId()`, `CONFIG_ID_REGEX`, `CONFIG_ID_MAX_LENGTH` live on `HrAvatarConnection` (one definition for the store/update rules, the import check and the
  export command's returned-id check).
- `write_conflict` (an id set concurrently) prints `orphaned_config=<avc_...>` so the config left upstream can be linked or deleted. Not in the design.
- `mb_substr(name, 0, 120)` is a no-op for current data (the column is `varchar(120)`); kept because the design and spec require it.
- The 24 h cache of a partially failed optional HeyGen sub-list, the non-transactional import and the voice bind before the name check are pre-existing and were
  reported by gga against untouched code; not changed.

### Issues and gotchas (batch 2)

- **`scramble:export` must run against Postgres** (`DB_CONNECTION=pgsql ... DB_URL=`); the default `.env` produces integer ids typed `string`, dropped nullability
  and rewritten unrelated schemas. In zsh `E="A=1 B=2"; env $E cmd` does NOT split: build the environment in a `bash` script. A silent failed export leaves the
  previous file and looks like "no drift"; read the exit/tail.
- **The CI coverage command is `php -d memory_limit=4G artisan test --parallel --coverage --min=98`**; without `-d memory_limit` the merge dies (`Coverage.php:90`, 128M) after
  all tests passed (exit 255).
- `SentryScrubberTest` "linear time" (threshold 200 ms) failed once at 200.79 ms under the 13-minute coverage run; it passes alone and in the plain parallel run (flaky under load, pre-existing).
- gga kept failing on whole-file findings in untouched code (import atomicity, bind-before-name-check, partial HeyGen lists, `answeringAnswerRangeRace` naming); only findings
  on the new/changed lines were fixed.

### Task 8.6 api final verification (tracker head `8ec96fa`, run alone)

`cd api && php -d memory_limit=4G artisan test --parallel --coverage --min=98` -> **exit 0**, 10010 tests, 10001 passed, 9 skipped (none new), 38604 assertions,
284 s; coverage **Total 98.3 %** (lines 19307/19641) against the 98 floor. Per-file line coverage of every new or changed production class:

| Class | Lines | Methods |
|---|---|---|
| `HrAvatarConnection` | 100.00% (28/28) | 100.00% |
| `HrAvatarProvider` | 100.00% (76/76) | 100.00% |
| `ExportTemplatesToHrAvatar` | 100.00% (67/67) | 100.00% |
| `AvatarTemplateController` | 100.00% (225/225) | 100.00% |
| `DuplicateAvatarTemplate` | 100.00% (46/46) | 100.00% |
| `AvatarTemplatePortabilityController` | 96.77% (120/124) | 62.50% (pre-existing private methods) |
| `AvatarProviderCatalogue` | 97.58% (323/331) | 91.30% |
| `TemplateDocument` | 97.06% (66/68) | 50.00% |

Every one is above 85%; no extra test was needed. Running `--coverage` without `-d memory_limit=4G` exits 255 after the tests pass (see gotchas); a first
coverage run of A5 also failed one timing assertion (flaky `SentryScrubberTest`), the rerun above is green.

### Task 8.7 api invariance evidence

- `git -C api diff --name-status develop...HEAD -- tests`: every entry is `A` (16 files: 11 Feature tests, 2 golden fixtures, `HrAvatarFixtures.php`, the two
  `Unit/HrAvatar` tests), plus ONE `M`: `tests/Helpers/PublicApi/ExposureCatalogue.php`, the single support-file edit (the new `conditionalExclusions()` method, four entries, no
  `exclusions()` entry touched, no test file edited). The A3b `HrAvatarExposureTest.php` and the invariance file were created in this change, so extending them is not an edit of an
  existing test.
- `git -C api diff --exit-code develop -- openapi.v1.json`: exit 0 (clean).
- Whole branch: +3931 -59 lines vs `develop` (generated `openapi.json` and fixtures included).
- pint `--test` and phpstan (`--memory-limit=1G`) exit 0 over the tracker head; all existing suites ran unedited in every full run above.

### Default-path invariance (batch 2)

With `HR_AVATAR_*` unset: field specs are exactly the pre-change object (A3a test), the catalogue answers 422 for `hr_avatar` with no request (A4 invariance extension),
every pre-existing catalogue call and `cacheKey()` string is unchanged (`TavusPalEditableCatalogueTest` and the catalogue suites pass unedited), the template resource and export
document of heygen/tavus templates keep exactly their members (null id omitted, A3b), the export command is a dry run that works without configuration, and the golden `/start`
fixtures still match byte for byte in every full run.

## Batch 3 (api): A6 - export key mapping and review findings - DONE (tasks 8.8-8.13)

Parity task 8.1 failed in batch 2; this unit resolves it. HR-Avatar was read only (field specs, create request rules, list endpoint).

| Commit | SHA | Message | Authored lines |
|---|---|---|---|
| A6 c1 | `f06b3b2` | `fix(api): end the HR-Avatar conversation when the create response is malformed` | +56 (2 files; 3 tests) |
| A6 c2 | `b0b0beb` | `fix(api): map template keys for the HR-Avatar export and report dropped data` | +383 -32 = 415 (3 files: command, new mapping class 131, test +198). Marginally over 400; the mapping, the findings and their tests share one command, no cohesive split |

### TDD Cycle Evidence (batch 3)

| Item | RED (observed) | GREEN | Mutation checks |
|---|---|---|---|
| Orphan conversation (coordinator add-on) | `HrAvatarProviderTest`: 60 tests, 57 passed, 3 failed (no end request sent, 1 request instead of 2; no log) | 60/60 | n/a |
| Mapping, parity, R3-001/2/3 | `ExportTemplatesToHrAvatarTest`: 32 tests, 10 failed + errors (mapping class missing; raw keys sent; no `voice_missing`; 0 retries counted as `provider_unreachable`; unguarded write) | 32/32 (184 assertions) | unmapping `idleEngagement`: 2 fail (parity + split); engine gate removed: 1 fails; link write catch narrowed: fails; `voice_missing` branch disabled: 3 fail |

Existing tests of the extended file adjusted (it is part of this change): the "config sent" test now expects the translated keys (`replica_id`/`persona_id`, no `voiceId` beside an external voice) and the privacy check looks for the `"persona"` member (the BEAI persona column) instead of the substring `persona` (now legitimately inside `persona_id`). No pre-existing test file elsewhere was touched.

### Work Unit Evidence (batch 3)

| Unit | Focused test command and result | Runtime harness | Rollback boundary |
|---|---|---|---|
| A6 c1 | `php artisan test tests/Unit/HrAvatar/HrAvatarProviderTest.php` exit 0, 60 passed / 132 assertions | `Http::fake` of create + end with `assertSent`, 503 on end with captured logs | `issue()` guard + `endUnusable()` + two docblock lines in `HrAvatarProvider.php`, the 3 new tests |
| A6 c2 | `php artisan test tests/Feature/HrAvatar/ExportTemplatesToHrAvatarTest.php` exit 0, 32 passed / 184 assertions | `Artisan::call('hr-avatar:export-templates')` against the real schema, `Http::fake`, `DB::beforeExecuting` fault injection | `HrAvatarTemplateMapping.php`, the command file, the test file |

### Verification (batch 3)

- Full `php artisan test --parallel`: exit 0, 10026 tests, 10017 passed, 9 skipped (none new), 38689 assertions, 271 s.
- `php -d memory_limit=4G artisan test --parallel --coverage --min=98`: exit 0, total 98.3 % (lines 19350/19684); `HrAvatarTemplateMapping` 100 % (26/26), `ExportTemplatesToHrAvatar` 100 % (80/80), `HrAvatarProvider` 100 % (80/80).
- pint exit 0, phpstan exit 0 (0 errors; one `arrayValues.list` finding fixed by restructuring, no ignore).
- Scramble (`DB_CONNECTION=pgsql`, `memory_limit=1G`): export exit 0, `git diff --exit-code openapi.json openapi.v1.json` exit 0 (unchanged; no endpoint change).
- gga passed on both commits (no `--no-verify`).

### Key mapping table (BEAI template config to HR-Avatar create body)

Source of truth in code: `app/Services/Provider/HrAvatarTemplateMapping.php` (`KEYS`, `VOICE_KEYS`, `DROPPED`). Reference: HR-Avatar `TavusFieldSpecs`, `LiveAvatarFieldSpecs`, `AvatarConfigRequest` (create accepts `name, provider, config, persona, llm_model_id, voice{engine,voice_id}, external_ref`).

| Provider | BEAI key | HR-Avatar | Note |
|---|---|---|---|
| tavus | `faceId` | `config.replica_id` | |
| tavus | `palId` | `config.persona_id` | |
| tavus | `ttsModelName` | `config.tts_model_name` | only with an external voice (cartesia/elevenlabs); else `dropped_key` |
| tavus | `llmTemperature`, `llmSpeculativeInference`, `turnTakingPatience`, `interruptibility`, `voiceIsolation`, `idleEngagement` | `persona.llm_temperature`, `llm_speculative_inference`, `turn_taking_patience`, `interruptibility`, `voice_isolation`, `idle_engagement` | persona member sent only when non-empty |
| tavus | `ttsEngine` + `ttsExternalVoiceId` | `voice {engine, voice_id}` | cartesia/elevenlabs; `tavus-auto` = no voice; `azure` = `dropped_key=ttsEngine[,ttsExternalVoiceId]` (HR-Avatar has no azure engine) |
| tavus | `audioOnly`, `maxCallDurationSec`, `enableRecording`, `enableClosedCaptions` | none | `dropped_key` (HR-Avatar does not send them; duration is per conversation) |
| tavus | `participantAbsentTimeoutSec` | none | `dropped_key`: Tavus `participant_absent_timeout` (never joined) differs from HR-Avatar `participant_left_timeout` |
| heygen | `avatarId`, `interactivityType`, `videoQuality` | same names under `config` | |
| heygen | `voiceSpeed`, `ttsModelName` | same names | only with cartesia/elevenlabs voice |
| heygen | `voiceStability`, `voiceSimilarityBoost`, `voiceStyle`, `voiceUseSpeakerBoost` | same names | only with an elevenlabs voice |
| heygen | `voiceId` | `voice {engine: provider, voice_id}` | stock voice; when an external engine is bound it is not sent and is reported `dropped_key=voiceId` (A7) |
| heygen | `ttsEngine` + `ttsExternalVoiceId` | `voice {engine, voice_id}` | |
| heygen | `maxSessionDurationSec`, `videoEncoding` | none | `dropped_key` |

Unknown keys are reported as `dropped_key` and never sent. The parity test fails when a key of `ProviderFieldSpecs::for($provider)` is not in `KEYS`, `VOICE_KEYS` or `DROPPED`, or when a mapped target is not in the HR-Avatar key list copied into the test (stale-copy risk: update the test list if HR-Avatar changes its specs). `participant_left_timeout` is the one HR-Avatar key no BEAI key reaches (asserted).

### Findings

- **R3-001**: external engine without a voice id prints `failed voice_missing`, counted under `failed`, no POST, exit 1; the dry run reports it too (and exits 1) so an operator sees it before `--apply`.
- **R3-002, option taken: report, not pre-check.** HR-Avatar's create body has no per-template marker: `external_ref` is the organization (the A4 proxy filters on it), `metadata` is not accepted, and `name` is neither unique upstream nor stable (renames, collisions), so matching on it could link a stranger's config. A timed-out POST is `failed provider_unreachable_ambiguous`, followed by a line with the `GET /v1/avatar-configs?external_ref=org_<id>` check and the config name; no automatic retry. Limitation documented in the command docblock. Future option: an HR-Avatar change that stores a client-supplied idempotency key or `metadata` on configs.
- **R3-003**: the link write is in a `try/catch (Throwable)`; failure prints `failed link_write_failed orphaned_config=<id>` (exception text never printed) and the loop continues.
- **Orphan conversation** (`f06b3b2`): `issue()` ends a created conversation whose `client_secret` is missing/empty; failures of that call are swallowed (`teardown()` already logged the status class). A response without a valid `conv_` id sends nothing.

### Open decisions

- `participantAbsentTimeoutSec` is dropped rather than mapped to `participant_left_timeout` (different Tavus semantics); say if the operator prefers the approximate mapping.
- Voice-dependent HeyGen knobs and the Tavus `ttsModelName` are dropped when no external voice is bound (HR-Avatar refuses them, `requires_voice_engine`); a stock-voice template therefore loses `voiceSpeed`.
- The dry-run exit code is 1 when a template would be `voice_missing`.
- The template `llm_*` binding and the BEAI persona column are still not exported (unchanged from A5).


## A7 - review follow-ups (api, commit `7f565a2`)

Mode: Strict TDD. Branch `feature/extract-avatar-service`, HEAD before `b0b0beb`.

### TDD Cycle Evidence

| Item | Test file | RED observed | GREEN | Notes |
|---|---|---|---|---|
| 1 docblock | none | N/A | N/A | documentation only |
| 2 `voiceId` dropped | `ExportTemplatesToHrAvatarTest.php` | 2 failures (output lacked `dropped_key=voiceId`; mapping returned `[]`) | pass | gga then found the external-engine-without-id case: second RED (`dropped` `[]` instead of `['voiceId']`) then GREEN |
| 3 parity vs source | same | N/A (new guard, passes on a faithful copy) | pass | mutation: removing `participant_left_timeout` from the copied list fails the tavus case, restored |
| 4 preflight | `HrAvatarFailClosedTest.php` | `RuntimeException not thrown` (fault swallowed) | pass | not-found cases (deleted pin, other-provider pin) stay `avatar_missing` |
| 5 env default on 2nd start | `HrAvatarSelectionTest.php` | characterization (already correct) | pass | mutation: dropping the `hr_avatar -> heygen` fallback in `providerNameFor()` fails it, restored |
| 6 connect retry | `HrAvatarInterviewFlowTest.php` | rename + stronger asserts, passes | pass | no server-side connect-failure signal exists (`ended_reason` accepts only completed/timeout/skipped) |
| 7 `cost.avatar` | same | passes (key present, null) | pass | |
| 8 create 422 body | `HrAvatarTemplateTest.php` | N/A | pass | body identical to `develop`; no controller change needed |
| 9 activation | same | characterization | pass | |
| gga: trailing newline | `HrAvatarProviderTest.php`, `HrAvatarConnectionTest.php`, `ExportTemplatesToHrAvatarTest.php` | 3 + 1 + 2 failures (`$` matched before `\n`) | pass | `D` modifier on 5 patterns |

### Gates

- `php artisan test --parallel`: exit 0 (10049 tests, 10040 passed, 9 pre-existing skips).
- `php -d memory_limit=4G artisan test --parallel --coverage --min=98`: exit 0, total 98.3 %; `HrAvatarConnection`, `HrAvatarProvider`, `HrAvatarTemplateMapping`, `ProviderPreflight`, `ExportTemplatesToHrAvatar` all 100 %.
- pint exit 0, phpstan exit 0. Scramble export (Postgres; the default 128 MB CLI limit fatals, run with `php -d memory_limit=2G`) exit 0, `git diff --exit-code openapi.json openapi.v1.json` exit 0.
- Item 8 evidence: temporary detached worktree of `develop` (076da7d) under `/Users/alessandromicelli/Desktop/beai-worktrees/api-develop-422` (vendor copied, stub fixtures file), request captured, worktree removed (`git worktree list` clean). Body: `{"message":"The name field is required. (and 3 more errors)","errors":{"name":[...],"config":["The config field is required."],"answer_min_seconds":[...]}}`, identical on HEAD.
- First commit attempt failed gga (valid findings: trailing-newline regexes, voiceId in the voice-missing case); fixed and re-run, second attempt passed. No `--no-verify`.
- Test invariance: `git diff --name-status develop...HEAD -- tests` still lists only `A` entries plus the one `ExposureCatalogue.php` method addition.

### Deviations

- Item 4: the task said to narrow the catch to "the specific not-found exception the resolver throws"; the resolver throws none (it returns null), so the catch was removed instead of narrowed.
- Item 6: renamed rather than simulated a failure, for the reason above.
- Items 5, 7, 8, 9 needed no production change; their tests are characterization (mutation-checked for 5).
- Extra (gga-driven): `D` modifier on `HrAvatarConnection::isConfigId()` and the export `sync_status` pattern, not only the provider patterns.


## A8 - review follow-ups (api, commits `fb87863`, `e99f5fb`)

Mode: Strict TDD. Branch `feature/extract-avatar-service`, HEAD before `7f565a2`.

### TDD Cycle Evidence

| Item | Test file | RED observed | GREEN | Notes |
|---|---|---|---|---|
| 1 export schema optional | `HrAvatarExportDocumentedTest.php` | `required` contained `hr_avatar_config_id`; required list had 9 members vs 8 emitted | pass after `#[ResponseDoc]` + re-export | `config` and `persona` typed `array<mixed>` to keep their schema lines; the `persona` and `llm` descriptions are lost (PHPDoc shapes carry none) |
| 2 catalogue truncation | `HrAvatarCatalogueProxyTest.php` | `warning` expected once, called 0 times | pass | exact-cap case (cursor null on page 10) is complete: no warning, cached |
| 3 `D` in the constant | `HrAvatarConnectionTest.php` | `preg_match(CONFIG_ID_REGEX, "avc_x\n")` returned 1 | pass | |
| gga: import atomicity | `HrAvatarTemplatePortabilityTest.php` | 1 template left after the second save threw | pass | `DB::transaction` |
| gga: every refusal | same | `templates.0` had 1 error, expected 2 | pass | append instead of overwrite |
| gga: shared client | `HrAvatarCatalogueProxyTest.php` | no request with bearer + `Accept: application/json` | pass | |
| 4 typed catalogue item | `AvatarCatalogueItemDocumentedTest.php` | item schema undefined; entries failed validation | pass after `ITEM_DOC_SHAPE` | |

### Gates

- `php artisan test --parallel`: exit 0 (10059 tests, 10050 passed).
- `php -d memory_limit=4G artisan test --parallel --coverage --min=98`: exit 0, total 98.3 %.
- pint exit 0, phpstan exit 0. Scramble export (Postgres, `memory_limit=2G`): `git diff --stat openapi.json openapi.v1.json` -> `openapi.json | 83 +- (82 insertions, 1 deletion)` after both commits; `openapi.v1.json` untouched. Commit 1 alone: 2 insertions, 8 deletions.
- gga: three attempts on commit 1. The reviewer is not deterministic; it raised pre-existing issues each run. Fixed the real ones (import transaction, error overwrite, shared client, wrong comments); a `tavusPals` docblock was clarified (behaviour pinned by `TavusPalEditableCatalogueTest`). Not changed: inline-comment density (repo-wide style), `catch CatalogueFetchException` only in the persona-type helpers, ElevenLabs `accent` array cast. Never `--no-verify`.

### Deviations

- Item 1 uses `#[ResponseDoc]` for the whole export response because Scramble reads a conditionally added array member as required and ignores `@return` here.
- The coordinator asked for item 4 as its own commit; done as `e99f5fb`.
- Extra (gga-driven): import transaction, error append, shared HR-Avatar client for the catalogue.


## A9 - closed value sets as OpenAPI enums (api, commit `06ac648`)

Mode: Strict TDD. Branch `feature/extract-avatar-service`, HEAD before `e99f5fb`. Documentation only; no runtime change.

### TDD Cycle Evidence

| Item | Test | RED observed | GREEN | Notes |
|---|---|---|---|---|
| pal sync status / code | `AvatarTemplateClosedSetsDocumentedTest.php` | `Failed asserting that an array has the key 'enum'` (both resources) | pass after `@scramble-return` unions | resource `@return` (PHPStan) stays `string\|null`; only `@scramble-return` is narrowed |
| catalogue status / code / italian | same | same message | pass after `STATUS_UNION`, `ERROR_CODE_UNION`, `ITEM_DOC_SHAPE` | `code` stays optional |
| field spec `type` | same | same message on all 5 field-spec lists | pass after `FieldSpec::DOC_SHAPE` names `FieldType` | Scramble publishes a `FieldType` component and `$ref`s it |
| constants vs runtime (3 tests) | same | undefined constants (error) | pass | drive `TavusPalSync::sync()` and `AvatarProviderCatalogue::fetch()` through every branch; the emitted set equals the constant |

### Sets emitted

- `pal_sync.status`: skipped, synced, warning (+ null).
- `pal_sync.code`: tavus_key_missing, pal_id_missing, pal_not_editable, pal_sync_rejected, pal_sync_unauthorized, pal_not_found, pal_sync_failed, pal_sync_unreachable (+ null).
- catalogue `status`: ok, empty, provider_error.
- catalogue `code` (optional): provider_key_missing, provider_unauthorized, provider_rate_limited, provider_unavailable, provider_unreachable, provider_rejected, provider_bad_response, unsupported_catalogue.
- catalogue item `italian`: native, multilingual (+ null).
- field spec `type`: text, number, select, checkbox (component `FieldType`).
- Not emitted: external TTS engines (no response schema carries a closed set; runtime `options` data). The top-level `warning` on template write responses is not documented in the spec at all, so it has no schema to carry an enum.

### Gates

- Targeted: `tests/Feature/Contract`, `HrAvatarExportDocumentedTest`, `tests/Feature/C14` exit 0 (684 tests).
- `php artisan test --parallel`: exit 0 (10068 tests, 10059 passed).
- `php -d memory_limit=4G artisan test --parallel --coverage --min=98`: exit 0, total 98.3 %.
- pint exit 0, phpstan exit 0. Scramble export (Postgres, `memory_limit=2G`): `openapi.json | 79 +- (72 insertions, 7 deletions)`; `openapi.v1.json` unchanged.
- gga: first run failed on pre-existing, out-of-scope items (inline-comment density, `store()`/`update()` bind-before-name-check ordering, paged fetches not flagging truncation, `index()` N+1, a hard-coded English message, 429 mapped to `pal_sync_failed`); two claims were unfounded (`answeringAnswerRangeRace` exists in `ValidatesAvatarTemplateWrites`; `AvatarTemplatePolicy::delete` returns false). The second run passed. Never `--no-verify`.

### Deviations and open items

- `FieldType` class prose moved from a docblock to a `//` note: it became the public `description` of the new `FieldType` component and was internal history.
- Pre-existing runtime items raised by gga are NOT fixed here (scope: no runtime change); candidates for a follow-up: truncation flag for the Tavus, HeyGen, Cartesia and ElevenLabs paged fetches, `store()`/`update()` ordering of the HeyGen bind versus the name check.
- Backoffice follow-up (other repo): sync `openapi.json`, then derive `CatalogueStatus`, `CatalogueErrorCode`, `PalSync`, `PAL_SYNC_CODES`, `FieldType` and the `italian` narrowing from the generated client.


## A10 - pre-existing defects surfaced by gga during A9 (api, commits `bad81c5`, `8d44cc8`, `24c546b`, `dfebbfa`, `9fa94c4`)

Mode: Strict TDD. Branch `feature/extract-avatar-service`, HEAD before `06ac648`.

### TDD Cycle Evidence

| Item | Test | RED observed | GREEN |
|---|---|---|---|
| paged catalogue truncation | `AvatarProviderCatalogueTruncationTest.php` | 14 of 21 failed (cached despite the cap; no refetch); 7 boundary cases passed | 21/21 after `noteTruncated()` threaded through the paged fetchers |
| failed secondary list / ElevenLabs accent | same file | 4 failed (cached true; `provider_error`) | pass after `$truncated = true` in the optional catches and `stringOrEmpty()` |
| name before voice bind | `AvatarTemplateNameCheckedBeforeVoiceBindTest.php` | 4 failed (`2 is identical to 0` LiveAvatar writes; the 422 body already matched) | 6/6 after reordering (4 sites, 2 controllers) |
| list N+1 | `AvatarTemplateIndexQueryCountTest.php` | `6 is identical to 2` `llm_models` queries | pass after `with('llmModel')` + relation in the resource |
| closed-set test hardening | `AvatarTemplateClosedSetsDocumentedTest.php` | mutation `message`->`code`: "Expecting [] not to be empty"; mutation dropping the `$ref`: "null is identical to '#/components/schemas/FieldType'" | 9/9 |
| `warning` enum | `AvatarTemplateWarningDocumentedTest.php` | `Undefined array key "warning"` on the committed spec | 8/8 after `#[ResponseDoc]` + export |

### Gates

- `php artisan test --parallel` exit 0 (10109 tests, 10100 passed, 9 skipped).
- `php -d memory_limit=4G artisan test --parallel --coverage --min=98` exit 0, total 98.32 % (lines 19379/19710).
- pint exit 0, phpstan exit 0. Scramble export (Postgres): `git diff --exit-code openapi.json openapi.v1.json` exit 0 after commit 9fa94c4; `openapi.json` +85 insertions over A9, `openapi.v1.json` unchanged.
- gga: pass on all five commits, after retries on three (findings: a heavy cached partial-list case that was real and fixed; a tenancy claim that is unfounded, a second global scope `exclude_platform_rows` applies under bypass and `GlobalAvatarTemplateOrgRoutesTest` covers `bare`; a hard-coded English provider-immutability message, pre-existing). Never `--no-verify`.

### Deviations and open items

- The platform controller has the same bind-before-name ordering; fixed there too (same trait, same defect).
- The Tavus-only `warning` enum requested would have been wrong: HeyGen templates emit `llm_*` codes.
- Not fixed (out of scope, reported): LLM-binding checks run in the model `saving` hook after the voice bind; the hard-coded English "provider cannot be changed" 422 (changing it alters the 422 body); organization audit rows outside the write transaction; `HeygenLlmRegistrar::forget()` before the DB delete in the two `destroy()` methods.
- Backoffice follow-up (other repo): sync `openapi.json`; `warning` is now typed (12 codes).

## A11 - remaining pre-existing defects surfaced by gga (api, commits `0e6f5a5`, `adf9b79`)

Mode: Strict TDD. Branch `feature/extract-avatar-service`, HEAD before `9fa94c4`.

### TDD Cycle Evidence

| Item | Test | RED observed | GREEN |
|---|---|---|---|
| teardown and audit after the delete | `AvatarTemplateDestroyOrderTest.php` | 2 of 4 failed (`1 is identical to 0` provider DELETEs on a refused delete, both routes); the organization audit order proven separately by mutation (audit before delete: `1 is identical to 0` on the organization case) | 4/4 after moving `forget()` (and the organization audit) after the delete |
| LLM binding before the voice bind | `AvatarTemplateLlmBindingCheckedBeforeVoiceBindTest.php` | 20 of 22 failed (`2 is identical to 0` LiveAvatar writes; the 422 body assertion before it already matched in every case); the 2 valid-binding cases passed | 22/22 after `assertLlmBindingValid()` + the two calls per controller |

### Gates

- `php artisan test --parallel` exit 0 (10135 tests, 10126 passed, 9 skipped).
- `php -d memory_limit=4G artisan test --parallel --coverage --min=98` exit 0, total 98.3 %.
- pint `--test` exit 0, phpstan exit 0. Scramble export (Postgres, `memory_limit=2G`): `git diff --exit-code openapi.json openapi.v1.json` exit 0.
- gga: pass on both commits after retries. Findings seen across the attempts: forget-before-delete (real, this unit), inline comment density (style; trimmed my own), the hard-coded English immutability message (known, left), `@throws AuthorizationException` on `abort_unless` (the tag feeds Scramble; left), audit atomicity differing between the two controllers (see below), org `store()` not auditing a binding set at create, org `destroy()` 409 without `#[ResponseDoc]`, `options()` without `#[ResponseDoc]`.

### Deviations and open items

- Audit "inside the write transaction" NOT done for the organization routes: tenant `AuditRecorder` is contained by design (class docblock) and the established pattern is audit AFTER commit (three actions say so in their docblocks). The one real defect found there was `destroy()` auditing before the delete, fixed. A failed audit write still does not roll the change back; that needs a throwing tenant writer (owner decision).
- Unfixed gga risks (not in the A11 brief): (a) `AvatarTemplateController::store()` writes `avatar_template.created` but no `avatar_template.llm_bound` row when the template is created already bound (platform `store()` likewise); (b) org `destroy()` 409 bodies and `options()` have no `#[ResponseDoc]`, and the org in-use 409 omits `organization_count`; (c) `@throws AuthorizationException` on platform actions that refuse with `abort_unless`; (d) the English provider-immutability message (still unchanged by instruction).
- The `update()` check runs on a clone filled with the validated fields; the real `$template` is only filled by the later `update()`.

## A12 - api cleanup of the remaining A11 risks (api, commits `101a016`, `80271a7`, `2bd711f`, `645226a`)

Mode: Strict TDD. Branch `feature/extract-avatar-service`, HEAD before `adf9b79`.

### TDD Cycle Evidence

| Item | Test | RED observed | GREEN |
|---|---|---|---|
| L-1 by-reference flag | existing suites only (pure refactor) | n/a, behaviour unchanged | `tests/Feature/C14`, `tests/Unit/Support/AvatarTemplates`, `tests/Feature/HrAvatar`, `tests/Feature/Contract`: 971/971 |
| llm_bound audit on create | `AvatarTemplateCreateAuditTest.php` | 2 of 4 failed (`No query results for model [AuditLog]`, org and platform); the 2 unbound cases passed | 4/4 after the audit row in both `store()` |
| organization in-use 409 | `OrganizationAvatarTemplateInUseCountsTest.php` | body test: `organization_count` missing from the 409; spec test (run against the old `openapi.json`): `Undefined array key "properties"` | 2/2 after the exception and `#[ResponseDoc]`, then the re-export |
| M-2 comment, deleted-hook strip | `AvatarTemplateDeletedHookScopeTest.php`, `AvatarTemplateModelScopeStripArchTest.php` | characterization (behaviour already held); mutation dropping `whereKey` fails the hook test (`two arrays are identical`) | 2/2 and the arch test pass after narrowing the strip |

### Gates

- `php artisan test --parallel` exit 0 (10141 tests, 10132 passed, 9 skipped).
- `php -d memory_limit=4G artisan test --parallel --coverage --min=98` exit 0, total 98.32 %.
- pint `--test` exit 0, phpstan exit 0. `git diff --exit-code develop -- openapi.v1.json` exit 0. `openapi.json` CHANGED (organization `DELETE /avatar-templates/{id}` 204 and 409): frontend and backoffice must re-copy it.
- gga: `101a016` on the 2nd attempt (low findings on the whole file: array shapes, inline comment density, all fixed), `80271a7` on the 1st, `2bd711f` on the 2nd (it asked for the hardcoded `1` to be justified: verified, the organization routes exclude platform rows through `SCOPE_EXCLUDE_PLATFORM_ROWS`, also under bypass, and the comment now says so; it also repeated the English immutability message, left by instruction).

### Deviations and open items

- The platform `store()` had the same missing `llm_bound` row and got the same fix (the brief named only the organization one).
- M-2 landed in `645226a` after the coordinator decision: no edit to `AdminTenancySafetyArchTest.php`, no teardown move out of the model. gga kept flagging the model's scope strips (outside that test's guard roots), so the `deleted` hook strip was narrowed to `SCOPE_EXCLUDE_PLATFORM_ROWS` + `withTrashed()` (tenant scope stays on) and the model's strips are pinned by new tests. gga also reported a latent `saveQuietly()` create without the tenant stamp (no caller today; left, out of A12).
- `options()` left as is (see 8.33).

## A13 - api: strip the tenant scope in the soft-delete unbind (api, UNCOMMITTED)

Mode: Strict TDD. Branch `feature/extract-avatar-service`, HEAD `645226a`. Status: implemented and green, NOT committed (gga blocks it three times with the same finding).

### TDD Cycle Evidence

| Item | Test | RED observed | GREEN |
|---|---|---|---|
| R3-001 tenant scope in the deleted hook | `AvatarTemplateDeletedHookScopeTest.php`, 4 new cases | org template deleted under ANOTHER organization context: `Failed asserting that 5 is null`; org template deleted with NO tenant context: `6 is null`; platform template deleted under another organization context (through `PlatformTemplateContext::run`): `3 is null`. The platform template deleted with no tenant context was ALREADY GREEN: with a null org id the tenant scope compiles to `organization_id IS NULL`, which happens to match platform rows | 6/6 after `withoutGlobalScopes(['tenant', SCOPE_EXCLUDE_PLATFORM_ROWS])`; `tests/Arch` 141/141 with the updated allowlist key |
| R3-002 | `OrganizationAvatarTemplateInUseCountsTest` | none needed | Confirmed: the test calls `DELETE /api/avatar-templates/{id}`, the controller throws `AvatarTemplateInUseException`, `bootstrap/app.php` renders it through `->render()`, and `assertExactJson` pins the body. End to end, no change |

### Gates

- `php artisan test --parallel` exit 0 (10148 tests, 10139 passed, 9 skipped).
- `php -d memory_limit=4G artisan test --parallel --coverage --min=98` exit 0, total 98.3 %.
- pint `--test` exit 0. `phpstan analyse --memory-limit=1G` exit 0 (the bare command crashes at the 128M default; CI passes the flag).
- `git diff --exit-code develop -- openapi.v1.json` exit 0. `git diff develop --numstat -- tests`: additions only (no deletions in any develop test).
- gga: FAILED 3 of 3 attempts, the same finding each time: the model's `withoutGlobalScopes` call sites (this one plus the two untouched `scopeAvailableToTenant` / `scopePlatformOnly`) are not in the `AdminTenancySafetyArchTest` allowlist, and `app/Models` is not among its guarded roots. Fixing it needs an edit to `tests/Arch/C11/AdminTenancySafetyArchTest.php`, which exists on develop (forbidden by this unit's brief and by the earlier coordinator decision recorded in A12). The model's strips are pinned by the branch-added `AvatarTemplateModelScopeStripArchTest.php`.

### Open decision for the coordinator

Either approve an allowlist entry (or a `Models` guarded root) in `AdminTenancySafetyArchTest.php`, or commit with the gga bypass the owner authorizes. Nothing was committed with `--no-verify`.

### A13 coordinator route (query builder), result

The deleted hook now writes through `$template->getConnection()->table(...)->where(pk, key)->update(...)`: no scope stripped, the allowlist entry removed, a new arch assertion (the hook body has no `withoutGlobalScope`/`withTrashed` and uses the base builder). Gates re-run green: full suite 10149 tests / 10140 passed / 9 skipped; coverage 98.3 %; pint, phpstan (`--memory-limit=1G`), `openapi.v1.json` identical to develop, no develop test modified. gga no longer flags the hook; it still FAILS on the model's two PRE-EXISTING, untouched strips (`scopeAvailableToTenant()`, `scopePlatformOnly()`) with the same AdminTenancySafetyArchTest-allowlist finding. Left staged, uncommitted, per the coordinator's instruction.

### A13 final (owner decision: allowlist the two)

Commits: `51839c7` (test: `Models` guarded + allowlist entry `Models/AvatarTemplate.php`, mutation checked: renaming the entry fails the guard with `Unlisted: Models/AvatarTemplate.php`) and `8bc022a` (fix). `app/Models` holds no other scope strip, so guarding the whole directory surfaced nothing else and no broadening was needed. gga: `51839c7` passed (only test files); `8bc022a` took 4 attempts. Findings addressed: undocumented superadmin bypass of `scopeAvailableToTenant()` (docblock), half-bound comment contradicting the code (comment). Findings left: inline `//` comments in `booted()` (soft style preference, pre-existing, repeated); `saveQuietly()` not checking the binding when a quiet write dirties it (latent, no caller writes `llm_model_id` quietly; already noted in A12); gga passed on the last attempt.
Gates: `php artisan test --parallel` exit 0 (10149 / 10140 passed / 9 skipped); coverage `--min=98` exit 0, 98.3 %; pint exit 0; phpstan exit 0; `openapi.v1.json` identical to develop; develop-test changes: only `AdminTenancySafetyArchTest.php` (+13 -1, one array line extended).
