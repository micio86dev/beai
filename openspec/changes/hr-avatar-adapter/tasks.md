# Tasks: HR-Avatar adapter (BEAI side, additive and opt-in)

> Change `hr-avatar-adapter`. Inputs: `proposal.md`, `specs/{hr-avatar-integration,interview-session,avatar-templates,interview-frontend}/spec.md`,
> `design.md` (D-* decisions, slices A1-A5 / F1-F2 / B1 / W1), `openspec/config.yaml` (strict TDD), `CLAUDE.md`.
> Strict TDD: every behavior starts with a RED test task; GREEN and REFACTOR follow. No existing test file is
> edited, deleted, skipped or weakened (the unedited suites are the default-path invariance proof).

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~3,500 authored (additions + deletions, tests included; generated `openapi*.json`, `types/api.ts`, `bun.lock` and the vendored tarball excluded). Range 3,200-3,800. Re-forecast after the 2026-10-19 design correction (+~200: single-422 merge, terminal latch, connect-retry spec, default-path Playwright spec, backoffice type split) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | 14 work units: A1a -> A1b -> A2a -> A2b -> A3a -> A3b -> A4 -> A5 (api), B1 (backoffice), F1 -> F2a -> F2b -> F3 (frontend, blocked), W1 (wrapper). Each <= ~400 authored lines |
| Delivery strategy | auto-chain |
| Chain strategy | feature-branch-chain |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

Re-forecast vs `design.md`: the design sized slices A1, A2, A3 and F2 at 360-400 lines each, but its own test plan
(about 25 provider scenarios, about 35 template scenarios, about 30 adapter scenarios) puts them at roughly
500-600 once tests are counted. They are split into `a`/`b` work units below; no code or test is dropped to fit a number.

### Branch plan (feature-branch-chain, local commits only, no push, no PR)

- Tracker branch `feature/extract-avatar-service` in `api`, `frontend`, `backoffice` (created from `develop`, task 0.1-0.3) and in the wrapper (already current).
- Commits land sequentially on the tracker in the order of the work-unit table. Each work unit is one commit (A1a, A2b, A3a, F2a ... and the small golden-baseline commit) so a slice branch can be cut at its commit boundary when PRs are opened later: PR 1 base = tracker, every later PR base = the previous slice branch. Opening PRs is out of scope for this apply.
- Wrapper commits stage explicit paths only (never `git add -A`): `hr-avatar/` and `odd/tasks/seamless-primary-transition.md` are untracked and unrelated, and the `api`/`frontend`/`backoffice` gitlinks are not bumped by this change.

### Suggested Work Units

| Unit | Goal | Likely PR (base) | Focused test command | Runtime harness | Rollback boundary |
|------|------|------------------|----------------------|-----------------|-------------------|
| A1a | Golden `/start` baseline (recorded on the unmodified base) + `hr_avatar` config, `HrAvatarConnection`, nullable `hr_avatar_config_id` column | PR 1 (base: api tracker) | `php artisan test --filter='HrAvatarConnectionTest\|HrAvatarMigrationTest\|HrAvatarDefaultPathInvarianceTest'` | Feature test hits `POST /candidate/interview/start` for Tavus and HeyGen under `Http::preventStrayRequests()` and compares to the golden fixtures | Delete `config/hr_avatar.php`, `HrAvatarConnection.php`, the migration (its `down()` drops the column), the `AvatarTemplate` fillable/property lines, `tests/*/HrAvatar*`, `tests/Fixtures/hr_avatar/`; nothing else reads them |
| A1b | `HrAvatarProvider` (issue, teardown, reconcileTranscript) with failure classification | PR 2 (base: A1a) | `php artisan test tests/Unit/HrAvatar/HrAvatarProviderTest.php` | `Http::fake` against the HR-Avatar contract (`POST /v1/conversations`, `/end`), `Http::assertSent` / `assertSentCount`, `Log::spy` | Delete `HrAvatarProvider.php` and its test; unreferenced until A2a |
| A2a | Selection arms (`providerNameFor`, `resolveProvider`) + pre-flight fail-closed arm | PR 3 (base: A1b) | `php artisan test --filter='HrAvatarSelectionTest\|HrAvatarFailClosedTest'` | Real `POST /candidate/interview/start` feature requests, container spies prove `HeygenProvider`/`TavusProvider` are never constructed | Revert the three arms in `InterviewController.php` and `ProviderPreflight.php`; `hr_avatar` becomes unreachable again |
| A2b | Release arm, `hr_avatar` start-response object, flow tests, Scramble re-export | PR 4 (base: A2a) | `php artisan test --filter='HrAvatarReleaseTest\|HrAvatarInterviewFlowTest'` | `/start` -> `/utterance` -> `/end` flow for three competencies on `Http::fake`d HR-Avatar, resume, sweep | Revert `ReleaseProviderSession.php`, `BuildInterviewSessionResponse.php`, `InterviewController.php` docblock and `openapi.json` |
| A3a | Template writes: store/update/activate rules, field-spec capability key, `ConfigValidator` arm, resource member, Scramble re-export | PR 5 (base: A2b) | `php artisan test tests/Feature/HrAvatar/HrAvatarTemplateTest.php` | Admin HTTP calls to the template endpoints under `Http::preventStrayRequests()` | Revert `AvatarTemplateController.php`, `ConfigValidator.php`, `AvatarTemplateResource.php`, `openapi.json` |
| A3b | Portability (export/import), duplicate, `T-EXPOSE-001` conditional section, Scramble re-export | PR 6 (base: A3a) | `php artisan test --filter='HrAvatarTemplatePortabilityTest\|HrAvatarExposureTest'` | Export -> import round trip over HTTP; `/v1` document scanned for the new names | Revert `TemplateDocument.php`, `AvatarTemplatePortabilityController.php`, `DuplicateAvatarTemplate.php`, `ExposureCatalogue.php`, `openapi.json` |
| A4 | Catalogue proxy arm with per-organization cache, Scramble re-export | PR 7 (base: A3b) | `php artisan test tests/Feature/HrAvatar/HrAvatarCatalogueProxyTest.php` | Admin HTTP call to the catalogue endpoint against `Http::fake`d `GET /v1/avatar-configs` pages | Revert `AvatarProviderCatalogue.php`, the `catalogue()` arm, `openapi.json` |
| A5 | `hr-avatar:export-templates` command (dry run by default) | PR 8 (base: A4) | `php artisan test tests/Feature/HrAvatar/ExportTemplatesToHrAvatarTest.php` | `Artisan::call` dry run and `--apply` against `Http::fake`d `POST /v1/avatar-configs`, row compared column by column | Delete `ExportTemplatesToHrAvatar.php` and its test; `--apply` effects are undone by setting the column to NULL |
| B1 | Backoffice: openapi sync, D-BO-TYPES (`ProviderName` unchanged; `TemplateProvider`, `FieldSpecMap`), form option + picker, combobox prop and preview narrowing, page forwarding, i18n incl. `projects.avatarProvider.hr_avatar` | PR 9 (base: backoffice tracker) | `bun run test:unit tests/unit/avatar-template-form-hr-avatar.spec.ts` then `bun run typecheck` | Vue Test Utils mounting `AvatarTemplateForm.vue` and `ProjectTable.vue` with stubbed field specs and catalogue; `nuxi typecheck` | Revert the listed backoffice files; flag-free, hidden unless field specs contain `hr_avatar` |
| F1 | Frontend (BLOCKED): vendored SDK tarball, `file:` dependency, Dockerfile, runtime flag, openapi sync, types, start-config mapping; **plus the wrapper `docs/version-catalog.md` row in the same unit** | PR 10 (base: frontend tracker) + wrapper commit | `bun run test:unit tests/unit/hr-avatar-start-config.spec.ts` | Bare-clone `bun install --frozen-lockfile` + `bun run build` in a scratch clone | Revert `package.json`, `bun.lock`, `vendor/`, `Dockerfile`, `nuxt.config.ts`, generated types, `useInterviewSession.ts` lines, and the catalog row |
| F2a | Frontend (BLOCKED): `HrAvatarProvider` core (guards, lazy SDK, connect options, states, transcripts, mic, silence, stop, error codes) | PR 11 (base: F1) | `bun run test:unit tests/unit/hr-avatar-provider.spec.ts` | Fake SDK through the injected loader | Delete `app/providers/hr-avatar.ts` and its spec; unreferenced until F3 |
| F2b | Frontend (BLOCKED): adapter completion logic (end/final phrase match, settle race, SDK `ended` reasons, single-`complete` latch) | PR 12 (base: F2a) | `bun run test:unit tests/unit/hr-avatar-provider-completion.spec.ts` | Fake SDK emitting transcript and `ended` events with fake timers | Revert the completion section of `hr-avatar.ts` and delete its spec |
| F3 | Frontend (BLOCKED): flag-gated deferred `hr_avatar` arm in `createProvider`, connect-failure retry spec, default-path Playwright spec, anonymity and SSR-bundle checks | PR 13 (base: F2b) | `bun run test:unit tests/unit/hr-avatar-factory.spec.ts tests/unit/hr-avatar-connect-retry.spec.ts` then `bun run test:e2e tests/e2e/interview-default-provider-path.spec.ts` | `bun run build` then `! rg -l '@hr-avatar/sdk' .output/server`; Playwright (chromium + webkit) against the production build with the flag unset | Revert `factory.ts` and delete the two new specs; adapter and SDK become unreachable |
| W1 | Wrapper: re-verify the catalog row written in F1; SDD artifacts committed; final cross-repo verification | PR 14 (base: wrapper tracker) | `rg -n 'hr-avatar/sdk' docs/version-catalog.md` | Local wiring smoke (manual, blocked on HR-Avatar S2-S8) | Revert the openspec change folder |

### Parallelism and ordering

- Sequential, api chain: 0.1 -> A1a -> A1b -> A2a -> A2b -> A3a -> A3b -> A4 -> A5. Never run two api Pest suites (or a Scramble export) at once: they share one test database.
- Parallel-capable (different repo, different runtime, no shared database): B1 needs only A3a + A4 and can run beside A3b/A5; recommended order for a single writer is the api chain, then B1.
- BLOCKED chain: F1 -> F2a -> F2b -> F3 -> W1 waits on HR-Avatar SDK slice 39 (design: "S8") producing a packable tarball. `hr-avatar/sdk/package.json` does not exist at planning time. F1 also needs A2b (start-response schema) before its openapi sync. F1 writes the wrapper catalog row (D-SDK: a dependency never exists without its D25 row), so the wrapper gets one commit during F1, before W1.
- Do not run a Docker image build beside a test run (4 GB Docker Desktop limit).

### Verification conventions (apply to every slice)

- Run each command directly and print its exit code on the next line (`...; echo "exit=$?"`). Never pipe a test or build command into `tail`/`head` (hides the real exit code).
- Every slice ends: focused tests -> FULL suite of that repo with exit code 0 shown -> static checks -> gga pre-commit pass -> one Conventional Commit, no AI attribution, no `Co-Authored-By`.
- api full suite: `php artisan test --parallel` (zsh does not word-split `$VAR`; use literal commands). Static checks: `vendor/bin/pint --test` and `vendor/bin/phpstan analyse --memory-limit=1G`.
- Scramble check for api slices that touch a documented HTTP surface (D-SCRAMBLE): export, then `git diff --exit-code openapi.v1.json` (clean) and review `git diff openapi.json` (additive only).
- frontend/backoffice full suite: `bun run test:unit` (coverage via `bun run test:unit --coverage` at the repo's final task). Bun only; never npm/pnpm/yarn/npx.
- Stage by explicit path. A failed `git commit` must stop the slice (check the exit code; do not continue to the next task).

---

## Phase 0: Branch setup (sequential, first task in each repo)

- [ ] 0.1 api: create the tracker branch `feature/extract-avatar-service` from `develop`
  - Before: `git -C api status --short` is empty (if dirty, STOP and report; do not stash or discard) and `git -C api log develop..HEAD --oneline` is empty after checking out `develop`.
  - Then `git -C api checkout -b feature/extract-avatar-service develop`; show the empty `git log develop..HEAD`.
- [ ] 0.2 frontend: same procedure for the `frontend` submodule (clean tree check, `git log develop..HEAD` empty, create the tracker branch from `develop`).
- [ ] 0.3 backoffice: same procedure for the `backoffice` submodule. Known risk: a previous change left stashed WIP in backoffice; do not pop or drop any stash, only report if the tree is dirty.
- [ ] 0.4 wrapper: confirm the current branch is `feature/extract-avatar-service` and that `git status --short` lists only the expected untracked/modified paths (`hr-avatar/`, `odd/tasks/seamless-primary-transition.md`, `openspec/changes/hr-avatar-adapter/`, the three gitlinks). Record the list; stage nothing.

---

## Phase 1: A1a - golden baseline, config, connection, column (api)

Spec: `hr-avatar-integration` (availability, secret confinement, default path invariance), `avatar-templates` (config id column).
Commit c1 = golden baseline; commit c2 = connection + config + migration + model.

- [ ] 1.1 RED (baseline): create `api/tests/Feature/HrAvatar/HrAvatarDefaultPathInvarianceTest.php`
  - Reuse the existing `/start` feature scaffolding (locate with `rg -l "candidate/interview/start" api/tests`) to start one live-mode Tavus session and one live-mode HeyGen session, with the same `Http::fake` bodies the existing tests use and `Http::preventStrayRequests()`.
  - Normalize volatile members (ids, tokens, timestamps, random URLs) to fixed placeholders, then compare to `api/tests/Fixtures/hr_avatar/start-tavus.json` and `api/tests/Fixtures/hr_avatar/start-heygen.json`.
  - Run each comparison twice: once with the HR-Avatar settings unset and once with `config()->set('hr_avatar.*')` fully set (a harmless no-op on the base).
  - Add a record mode (`HR_AVATAR_RECORD_GOLDEN=1` writes the fixtures instead of asserting). With no fixtures present the test fails ("fixture missing"): that is the RED state.
  - Spec scenarios: "Tavus and HeyGen start responses are byte-identical", "No outbound HR-Avatar traffic on the default path".
- [ ] 1.2 Record the golden fixtures on the UNMODIFIED base
  - Evidence required first: `git -C api diff --stat develop -- app config database routes` prints nothing.
  - Run once with `HR_AVATAR_RECORD_GOLDEN=1`, then show `git -C api status --short` lists only the new test and the two fixture files (generated, excluded from the authored count).
- [ ] 1.3 GREEN (characterization): run `php artisan test --filter=HrAvatarDefaultPathInvarianceTest` without the record flag; show exit 0. Commit c1 (staged paths: the test and `api/tests/Fixtures/hr_avatar/`): `test(api): record golden start fixtures for default-path invariance`. Full suite is deferred to the end of this unit.
- [ ] 1.4 RED: create `api/tests/Unit/HrAvatar/HrAvatarConnectionTest.php`
  - Availability: all three present -> available with no HTTP (`Http::assertNothingSent()`); each single missing value -> unavailable; whitespace-only secret -> unavailable; base URL `not a url` and `ftp://x` -> unavailable; none set -> unavailable and no request.
  - `missingVariables()` returns variable names only, never values; `baseUrl()` strips a trailing slash; `organizationRef(7)` is `org_7`.
  - `client()` sends `Authorization: Bearer <secret>`, `Accept: application/json` and a 15 s timeout (assert through `Http::fake` + `Http::assertSent`).
  - `unavailableProviderRule()` fails `hr_avatar` with the `validation.in` message while unavailable and passes it when available; other values are untouched.
  - Spec scenarios: "All three settings present", "Any single missing setting...", "Blank or malformed values count as missing", "Nothing set is the default state".
- [ ] 1.5 RED: create `api/tests/Feature/HrAvatar/HrAvatarMigrationTest.php`: `avatar_templates.hr_avatar_config_id` exists, is `varchar(64)`, nullable, has no foreign key and no index; the model accepts it through mass assignment; `down()` drops it. Spec: "An hr_avatar template stores an opaque HR-Avatar config id".
- [ ] 1.6 GREEN: create `api/config/hr_avatar.php` (three keys from `HR_AVATAR_BASE_URL`, `HR_AVATAR_SECRET_KEY`, `HR_AVATAR_PUBLISHABLE_KEY`), add three blank entries with a one-line comment to `api/.env.example`, and create `api/app/Services/Provider/HrAvatarConnection.php` exactly per the D-CONN interface (static methods, no I/O in `isAvailable()`, `secretKey()` documented server-side only).
- [ ] 1.7 GREEN: create `api/database/migrations/2026_10_19_100000_add_hr_avatar_config_id_to_avatar_templates.php` (nullable `string(64)`, `down()` drops it, no FK, no index) and add `hr_avatar_config_id` to `$fillable` and the `@property string|null` docblock in `api/app/Models/AvatarTemplate.php`.
- [ ] 1.8 REFACTOR + static checks: `vendor/bin/pint --test` and `vendor/bin/phpstan analyse --memory-limit=1G`, both exit 0 shown.
- [ ] 1.9 Close A1a: focused command (see work-unit table) exit 0; FULL `php artisan test --parallel` exit 0 shown (including the unedited existing suites); gga pre-commit pass; commit c2 `feat(api): add hr_avatar connection settings and template config id column`. No Scramble step (no HTTP surface).

---

## Phase 2: A1b - HrAvatarProvider (api)

Spec: `hr-avatar-integration` (issuing, failure classes, teardown, transcript of record). Design: D-ISSUE, D-TEARDOWN.

- [ ] 2.1 Read (read-only) the contracts the provider must match: `api/app/Services/Provider/ProviderSessionService.php` (read-only), `api/app/Services/Provider/TavusProvider.php` (read-only), the `ProviderToken`, `ProviderFailureClass` and `ProviderException` types they use (read-only), `api/app/Services/Conversation/ActiveTemplateResolver.php` if that is where `resolve()` lives (read-only) and `SessionLiveClock::resolveMaxSeconds()` (read-only). Record the exact signatures used in the test and class.
- [ ] 2.2 RED: create `api/tests/Unit/HrAvatar/HrAvatarProviderTest.php`, part 1 `issue()` (all under `Http::fake`, `Http::preventStrayRequests()`)
  - Exactly one POST to `/v1/conversations` with a bearer secret key; body has exactly seven members (avatar_config_id, system_prompt, opening_text, language, max_duration_seconds, external_ref, metadata); `metadata` serializes as `{}` not `[]`; no `display_name` ("Giulia") anywhere in body, headers or query.
  - `max_duration_seconds` clamp: derived 10 -> 30, derived 99999 -> 3600; `external_ref` is `session_{id}` and contains no candidate name, email or `candidate_ref`.
  - Token mapping: 201 `{id: conv_01ABC, client_secret: CS_VALUE}` -> token, ref, provider `hr_avatar`.
  - Pre-request ClientError with `Http::assertNothingSent()`: integration unavailable, null template or null config id, null system prompt or opening text, prompt > 32000 chars, opening > 4000 chars (not truncated), language not matching `^[a-z]{2}$`.
  - Malformed success -> Upstream and no token: missing `client_secret`, id without `conv_`, status 200 instead of 201, non-JSON body.
  - Classification: 429 Throttle; 400/401/403/404/409/422 ClientError; 500/503, `ConnectionException`, timeout -> Upstream.
  - Operator faults (design D-ISSUE, validation findings 5 and 6): 403 `insufficient_scope` (key without `conversations:write`) -> ClientError with `code insufficient_scope` in the log context; 409 `config_not_synced` (pinned config still `pending`) -> ClientError with `code config_not_synced`. Neither retries, neither leaks the secret.
  - Diagnostics: message and `Log::spy` context carry the status class and the Problem+JSON `code` only when it matches `^[a-z_]{1,64}$`; a 409 `config_not_synced` whose body echoes the prompt and the sentinel secret `hra_sk_live_SECRETVALUE` never leaks either, and a hostile `code` (spaces, uppercase, 80 chars) is dropped.
- [ ] 2.3 RED: same file, part 2 `teardown()` and `reconcileTranscript()`: one POST `/v1/conversations/conv_01ABC/end` -> true; 404 then 503 then timeout never throw, return false and log without the secret; null ref and `abc` and `conv_x/../y` send nothing and return true; integration unavailable -> no request, false, logged; `reconcileTranscript()` returns `[]` and sends nothing; no request ever lists conversations or ends another one.
- [ ] 2.4 GREEN: create `api/app/Services/Provider/HrAvatarProvider.php` implementing `ProviderSessionService` per D-ISSUE / D-TEARDOWN, using `HrAvatarConnection::client()`; never read `detail` or the body into messages; log context only `operation`, `status_class`, `code`, `class`.
- [ ] 2.5 REFACTOR + static checks: pint and phpstan, exit 0 shown.
- [ ] 2.6 Measure (design open question 2, no code change): in tinker/scratchpad compose the real system prompt and opening text for every seeded role x competency x locale with `SystemPromptComposer` and `OpeningTextComposer` and record `max(system_prompt_chars)` and `max(opening_text_chars)` in the apply-progress note. If either exceeds 32000 / 4000, STOP the live-wiring claim and return it to the orchestrator as a product decision; never add truncation.
- [ ] 2.7 Close A1b: focused command exit 0; FULL `php artisan test --parallel` exit 0 shown; pint/phpstan; gga pass; commit `feat(api): add HrAvatarProvider session service`. No Scramble step.

---

## Phase 3: A2a - provider selection and pre-flight arms (api)

Spec: `interview-session` (selection, fail closed, neither Tavus nor HeyGen). Design: D-SELECT, resolved item 1.

- [ ] 3.1 Audit (read-only analysis, no edit): re-verify the provider-name branch table in `design.md` (D-SELECT, corrected 2026-10-19) against `api/app/Http/Controllers/Candidate/InterviewController.php` with `rg -n "'tavus'|'heygen'|provider ===|provider !==|resolveProvider\(" api/app`; confirm every branch is a no-op for `hr_avatar` and that line numbers still match: :290, :348, :437, :480 (`start` resolveProvider), :506, :593 (`suspend` resolveProvider -> harvest + release), :700 (`end` resolveProvider), :717 (`end` HeyGen transcript REPLACE), :801 (`handsOverToNextCompetency` HeyGen-completed handover / plan check), :815 (`planCoversLaterCompetency` Tavus guard), :1154, :1176, :1642, and that every `resolveProvider()` call site reaches the new explicit arm. Record any drift; if a branch would treat `hr_avatar` as HeyGen or Tavus, STOP and report before coding.
- [ ] 3.2 RED: create `api/tests/Feature/HrAvatar/HrAvatarSelectionTest.php`
  - Pinned `hr_avatar` template + available -> session provider `hr_avatar` and exactly one `/v1/conversations` request.
  - Test-mode participant (`beai_test_...`) with the same pin -> `mock`, no HR-Avatar request (T-TEST-006 unchanged).
  - Stored `provider_override = hr_avatar` with no pin -> ignored, env default applies (write the value directly to the row: no validation of `provider_override` exists, so the spec bullet about refusing it in validation is N/A per design D-SELECT; this "ignored" test is the enforced guarantee); env `INTERVIEW_PROVIDER=hr_avatar` with no pin -> `heygen`.
  - Pinned `tavus` + override `heygen` -> `tavus` (existing precedence).
  - Container spies: rebinding `HeygenProvider` and `TavusProvider` to failing closures proves neither is constructed for an `hr_avatar` session and no HeyGen/Tavus host is called.
- [ ] 3.3 RED: create `api/tests/Feature/HrAvatar/HrAvatarFailClosedTest.php`
  - Unavailable + pinned `hr_avatar` template: HTTP 422 `interview_configuration_invalid`, reason `{key: credentials, code: provider_key_missing}`, no session row created, participant status unchanged, `Http::assertNothingSent()`.
  - Same project with override `tavus` and env default `heygen`: still 422, neither provider called (no fallback).
  - Pinned `hr_avatar` template with null config id (available): 422 reason `{key: hr_avatar_config_id, code: avatar_missing}`, no session row.
  - Test-mode participant with the unavailable pin -> `mock` and succeeds.
- [ ] 3.4 GREEN: edit `api/app/Http/Controllers/Candidate/InterviewController.php`: `providerNameFor()` (pinned template provider returned as is; `hr_avatar` from override or env treated as absent: override -> env default, env -> `heygen`; test mode first) and `resolveProvider()` (`'hr_avatar' => app(HrAvatarProvider::class)` before `default`). Do not touch any `'tavus'`/`'heygen'` branch.
- [ ] 3.5 GREEN: edit `api/app/Services/Provider/ProviderPreflight.php`: new `hr_avatar` arm in `check()` (unavailable -> `credentials`/`provider_key_missing`; pinned template without config id -> `hr_avatar_config_id`/`avatar_missing`); existing codes only, no new error code or status.
- [ ] 3.6 REFACTOR + static checks: pint, phpstan exit 0 shown.
- [ ] 3.7 Scramble check (expect NO openapi diff, the 422 already exists): run the D-SCRAMBLE export, `git diff --exit-code openapi.v1.json openapi.json` clean, shown.
- [ ] 3.8 Close A2a: focused command exit 0; FULL `php artisan test --parallel` exit 0 shown (golden invariance test still green); gga pass; commit `feat(api): select hr_avatar from pinned templates and fail closed when unavailable`.

---

## Phase 4: A2b - release arm, start response, flow tests (api)

Spec: `interview-session` (start response, branches, resume, snapshot/cost), `hr-avatar-integration` (client secret, transcript of record, secret confinement). Design: D-SELECT release arm, D-START, D-SCRAMBLE.

- [ ] 4.1 RED: create `api/tests/Feature/HrAvatar/HrAvatarReleaseTest.php`: `ReleaseProviderSession::forRefs()` with provider `hr_avatar` posts one `/end` per ref and never constructs `HeygenProvider`; `ReleaseEndedProviderSessionJob` and the `ReapStaleInterviews` sweep on a stale `in_corso` `hr_avatar` session end its conversation and never hand a `conv_` ref to HeyGen. (Expected RED: the release switch has no `hr_avatar` arm.)
- [ ] 4.2 RED: create `api/tests/Feature/HrAvatar/HrAvatarInterviewFlowTest.php`, cases expected to fail first
  - 201 body for `hr_avatar`: `provider`, `provider_token` = client secret, `hr_avatar` = exactly `{base_url, publishable_key}`, `conversation_url` null/absent, no `conversation_id`, `conversation_ttl_seconds` or `continuation`; other providers' bodies contain no `hr_avatar` member.
  - Inbound `live_conversation_id` is ignored (fresh conversation, no `continuation`); secret key, composed prompt and `client_secret` handling per "Secret key absent from every response" (body AND headers).
- [ ] 4.3 RED: same file, characterization cases that should already pass once 4.2 is green (write them first; any that fail are treated as defects to fix minimally)
  - `client_secret` appears in no `interview_sessions` column, `Log::spy` call, cache entry or queued job payload; `provider_session_ref` = `conv_01ABC`.
  - Three competencies -> three distinct `/v1/conversations` requests, three distinct refs, no `conversation_plan`, only the HR-Avatar host contacted.
  - Resume of an `in_corso` session: new conversation, `/end` of the old ref, ref replaced; a 503 on that `/end` still returns 201.
  - `/end` with `ended_reason = completed` keeps the 6 live utterance rows (same ids) and sends no transcript request.
  - Snapshot: `llm_binding_status = unbound`, null `llm_model_key`, pinned `avatar_template_id`; exactly one live period opened at `in_corso` and closed at end; review without a configured rate has no cost estimate and responds 200.
  - Failure matrix: 429 -> 429 `provider_busy`, session `pending`; 422 -> 500, participant unchanged; 409 `config_not_synced` -> 500, participant unchanged (a `pending` config cannot start); 503 -> 502, session `error`, participant `errore`.
  - `POST /suspend` on a live `hr_avatar` session: exactly one `/end` for its ref, no transcript request, no HeyGen/Tavus construction (D-SELECT :593).
  - `/end` with `ended_reason = completed` and `next_action = continue`: the conversation is released at once (no handover deferral, D-SELECT :801).
  - Resume after a browser connect failure (the server half of the retry path, D-ADAPTER step 4): a second `/start` on the `in_corso` row issues a new conversation and ends the old one.
- [ ] 4.4 GREEN: edit `api/app/Actions/Interview/ReleaseProviderSession.php`: explicit `'hr_avatar'` arm in `forRefs()` before the default.
- [ ] 4.5 GREEN: edit `api/app/Actions/Interview/BuildInterviewSessionResponse.php`: inside `if ($token->provider === 'hr_avatar')` after `continuation`, add `$body['hr_avatar'] = ['base_url' => ..., 'publishable_key' => ...]` from `HrAvatarConnection`; update the `@scramble-return` of `start()` in `api/app/Http/Controllers/Candidate/InterviewController.php` with `hr_avatar?: array{base_url: string, publishable_key: string}`.
- [ ] 4.6 Verify the 4.3 cases against the untouched controller; where one fails, apply the smallest fix, add a note to this task, and keep existing arms untouched. Do not edit any existing test.
- [ ] 4.7 Scramble re-export (D-SCRAMBLE): run the export command; `git diff --exit-code openapi.v1.json` clean; review `git diff openapi.json`: additive only (the `hr_avatar?` member on the start 201). Show both outputs.
- [ ] 4.8 REFACTOR + static checks: pint, phpstan exit 0 shown.
- [ ] 4.9 Close A2b: focused command exit 0; FULL `php artisan test --parallel` exit 0 shown; gga pass; commit `feat(api): return hr_avatar join inputs and release hr_avatar conversations`. If the unit exceeds ~400 authored lines, report the count; do not trim tests.

---

## Phase 5: A3a - template writes, capability key, resource (api)

Spec: `avatar-templates` (provider gating, field specs, config id rules, immutability, LLM refusal, tenant scope, no outbound). Design: D-TEMPLATES (first half).

- [ ] 5.1 RED: create `api/tests/Feature/HrAvatar/HrAvatarTemplateTest.php` (`Http::preventStrayRequests()` everywhere)
  - Create: available + valid `avc_01HXYZ` -> 201, inactive, resource carries the id; unavailable -> 422 on `provider`, no row; `config` may be omitted (stored `{}`) or `{}` for `hr_avatar`.
  - A6 runtime guard: a `tavus` and a `heygen` create without `config` -> 422 on `config` whose message equals `__('validation.required', ['attribute' => 'config'])` (the pre-change text).
  - Single 422 (validation finding 1): malformed id `cfg_1` plus unknown config key `nonsense` in ONE request -> exactly one 422 response whose `errors` object carries both `hr_avatar_config_id` and `config.nonsense`; missing id on `hr_avatar` -> 422 on `hr_avatar_config_id`; `config {avatarId, nonsense}` -> separate `config.avatarId` and `config.nonsense` `unknown` entries; non-null `llm_model_id`/`llm_credential_id` on `hr_avatar` -> 422 on that field.
  - Update: PATCH id to null -> 422 and stored id unchanged; PATCH LLM field on an `hr_avatar` template -> 422; PATCH provider to `hr_avatar` from tavus and from `hr_avatar` to tavus -> 422 and providers unchanged; heygen -> tavus still 422.
  - Activation refused (422, `is_active` false) while unavailable; rename while unavailable succeeds; no outbound request on create, update, activate, delete (no PAL sync, voice or LLM registration).
  - Field specs: keys `heygen`, `tavus`, `hr_avatar` (empty list) when available; exactly `heygen`, `tavus` when unavailable.
  - Resource: tavus/heygen template with null id has no `hr_avatar_config_id` member; a tavus template carrying an id issues a Tavus request body identical to the same template without it.
  - Platform store (`PlatformAvatarTemplateController`) still refuses `hr_avatar`.
  - Cross-tenant: organization B's `avc_B` is absent from A's list and show; B's template by id is 404.
- [ ] 5.2 RED: extend `api/tests/Feature/HrAvatar/HrAvatarDefaultPathInvarianceTest.php` (a file created in this change): field-specs response with HR-Avatar unset equals the exact pre-change object (`heygen`, `tavus` only).
- [ ] 5.3 GREEN: edit `api/app/Http/Controllers/AvatarTemplateController.php`: private `organizationTemplateStoreRules()` overriding `provider`, `config` (`['required_unless:provider,hr_avatar','array']`, spec amendment A6, with the custom message `['config.required_unless' => __('validation.required', ['attribute' => 'config'])]` passed to `validate()` so heygen/tavus keep today's text), `hr_avatar_config_id`, `llm_model_id`/`llm_credential_id` (`prohibited_if:provider,hr_avatar`); `$validated['config'] ??= []`; update rules plus the two post-validation checks (null id refused, non-null LLM field refused for `hr_avatar`); `activate()` refusal while unavailable; `fieldSpecs()` key only when available with its `#[ResponseDoc]` update. Closures read the request only at validation time (Scramble trap). Do not edit the shared validation trait.
- [ ] 5.3a GREEN (validation finding 1, design D-TEMPLATES "One 422"): in `store()` (today `$request->validate()` at :228 and `assertConfigValid()` at :233 throw separately), for `provider = 'hr_avatar'` only: compute `$configErrors` from `ConfigValidator::validate('hr_avatar', $config)` (when `config` is an array) mapped `config.{key} => code` exactly as `assertConfigValid()` maps them; call `$request->validate(...)` inside a `try`; on `ValidationException $e` rethrow `ValidationException::withMessages(array_merge($e->errors(), $configErrors))`; on success throw `$configErrors` if non-empty. Same merge in `update()` for an `hr_avatar` row. Keep `$request->validate()` as the call Scramble reads. For heygen/tavus `$configErrors` is `[]` and the existing two-step order with reference checks is untouched.
- [ ] 5.4 GREEN: edit `api/app/Support/AvatarTemplates/ConfigValidator.php`: `hr_avatar` arm before the empty-spec early return reporting every key as `unknown` (with every error at once).
- [ ] 5.5 GREEN: edit `api/app/Http/Resources/AvatarTemplateResource.php`: `'hr_avatar_config_id' => $this->when(... !== null, ...)` plus `@scramble-return`/`@return` docblocks.
- [ ] 5.6 Regression guard: run the existing avatar-template suites unedited (`php artisan test --filter=AvatarTemplate`), exit 0 shown, confirming heygen/tavus error texts and ordering are unchanged. This is the stated proof of spec amendment A6 (runtime for heygen/tavus unchanged); record it in the apply-progress note.
- [ ] 5.7 Scramble re-export (D-SCRAMBLE): export; `git diff --exit-code openapi.v1.json` clean; review `git diff openapi.json`: additive (provider enum, `hr_avatar_config_id?` on BOTH `AvatarTemplateResource` and the inherited `PlatformAvatarTemplateResource`, `hr_avatar?` field spec) plus exactly ONE disclosed non-additive line set: store-body `config` leaving the `required` list (A6). Any other non-additive change is a defect: stop and fix. If the store or update body schema collapses to an empty object, inline the literal rule array in the controller method and re-export; never ship an empty schema.
- [ ] 5.8 Close A3a: pint/phpstan; focused command exit 0; FULL `php artisan test --parallel` exit 0 shown; gga pass; commit `feat(api): accept hr_avatar templates with a config id when available`.

---

## Phase 6: A3b - portability, duplicate, exposure classification (api)

Spec: `avatar-templates` (export/import, duplicate, null omission), `hr-avatar-integration` (T-EXPOSE-001). Design: D-TEMPLATES (second half), D-EXPOSE.

- [ ] 6.1 RED: create `api/tests/Feature/HrAvatar/HrAvatarTemplatePortabilityTest.php`
  - Null id omitted from the export document for heygen/tavus templates (document byte-identical to before).
  - Export -> import round trip of an `hr_avatar` template while available: the imported copy is inactive and carries the same id.
  - Import of an `hr_avatar` block while unavailable fails with a validation error and creates no template; import requires the id for `hr_avatar`, validates the format whenever non-null, and refuses an `llm` block for `hr_avatar`.
  - Superadmin duplicate copies the id and leaves the original unchanged; the manageable-while-unavailable sequence (admin renames, superadmin duplicates, copy deleted) all succeed.
  - Cross-tenant: organization B's id never appears in A's export, duplicate or listing.
  - No outbound request on any of these.
- [ ] 6.2 RED: create `api/tests/Feature/PublicApi/Exposure/HrAvatarExposureTest.php` per D-EXPOSE: for `AvatarTemplate`, `PlatformAvatarTemplate` (value forced onto a platform row through the query builder, since no endpoint can set it), `AvatarTemplateExport` and `InterviewStart` the key set with the value present minus the key set with it absent equals the classified list; none of the keys appears in `ProjectSerializer`/`InterviewSerializer` output; `api/openapi.v1.json` (read-only) contains neither `hr_avatar_config_id` nor `hr_avatar`.
- [ ] 6.3 GREEN: edit `api/app/Support/AvatarTemplates/TemplateDocument.php`: `export()` adds `hr_avatar_config_id` only when non-null; `flatten()` carries the raw value or null.
- [ ] 6.4 GREEN: edit `api/app/Http/Controllers/AvatarTemplatePortabilityController.php`: `reject()` replaces `ProviderFieldSpecs::for(...) === []` with an explicit provider check (heygen, tavus, or `hr_avatar` while available), validates the id format when non-null, requires it for `hr_avatar`, refuses an `llm` block for `hr_avatar`; `create()` force-fills the id.
- [ ] 6.5 GREEN: edit `api/app/Actions/AvatarTemplates/DuplicateAvatarTemplate.php`: copy `hr_avatar_config_id`.
- [ ] 6.6 GREEN: edit `api/tests/Helpers/PublicApi/ExposureCatalogue.php`: add the new `conditionalExclusions()` method only (the four entries from D-EXPOSE, including `PlatformAvatarTemplate`); do not edit `exclusions()` or any existing entry. Run the existing exposure suite to prove it stays green unedited.
- [ ] 6.7 Scramble re-export (D-SCRAMBLE) if any documented import/export schema changed; `git diff --exit-code openapi.v1.json` clean; additive-only review of `git diff openapi.json`. Show outputs.
- [ ] 6.8 Close A3b: pint/phpstan; focused command exit 0; FULL `php artisan test --parallel` exit 0 shown; gga pass; commit `feat(api): export, import and duplicate the hr_avatar config id and classify its exposure`.

---

## Phase 7: A4 - avatar-config catalogue proxy (api)

Spec: `hr-avatar-integration` (proxy requirement and scenarios). Design: D-PROXY, resolved item 4.

- [ ] 7.1 RED: create `api/tests/Feature/HrAvatar/HrAvatarCatalogueProxyTest.php`
  - Server-side filter (validation finding 9, HR-Avatar reconciliation item 38): every request to `GET /v1/avatar-configs` carries `external_ref=org_<A>` and `limit=100` in its query (`Http::assertSent`), on the first page and on every cursor page.
  - Three attributed (`external_ref = org_<A>`) synced configs -> 200, `status ok`, three items in the existing entry shape (`id` starts `avc_`, `provider hr_avatar`, `label`=`name`=config name, `preview_audio_via_api` false, the rest null).
  - Cross-tenant: a faked upstream that IGNORES the filter and returns B's config alongside A's -> B's id and label appear nowhere in A's response (defence in depth); unattributed configs never returned to any tenant; `pending` and `failed` configs filtered, `synced` and `not_required` kept.
  - Pagination: first page with `next_cursor`, second without -> both requested, merged; page bound of 10 respected.
  - Upstream 503 with the secret key in the body -> 200 `provider_error`, `items []`, `code provider_unavailable`, body free of the secret and of HR-Avatar error text; 401 and 403 `insufficient_scope` (key without `avatar_configs:read`) -> `provider_unauthorized`, 429 -> `provider_rate_limited`, malformed -> `provider_bad_response`; empty result -> `status empty`.
  - Second call within TTL sends no request; the TTL is 5 minutes; failures are not cached. `AvatarProviderCatalogue::cacheKey('hr_avatar', 'avatar_config', <A>)` ends with `:org<A>` and is what the cache holds; `cacheKey('tavus', 'pal')` and `cacheKey('tavus', 'pal', null)` both equal the pre-change string (the existing `TavusPalEditableCatalogueTest` stays green unedited).
  - Operator and viewer -> 403; unavailable -> 422 and no request; bare superadmin (null organization) -> `empty` without a request.
- [ ] 7.2 RED: extend `api/tests/Feature/HrAvatar/HrAvatarDefaultPathInvarianceTest.php`: with HR-Avatar unset, `provider=hr_avatar&resource=avatar_config` -> 422 and no request; existing provider/resource catalogue calls unchanged (existing catalogue suites stay green unedited).
- [ ] 7.3 GREEN: edit `api/app/Support/AvatarTemplates/AvatarProviderCatalogue.php`: extend `cacheKey()` (:168) to `cacheKey(string $provider, string $resource, ?int $organizationId = null)` (unchanged string when null, `:org{id}` suffix otherwise; it stays the one place keys are built); `fetch(..., bool $fresh = false, ?int $organizationId = null)` passing the id to `cacheKey()` and using a 5 min TTL only when non-null (existing keys, TTL and behaviour unchanged when null); `fetchLive()` gains the same trailing parameter and the arm `'hr_avatar:avatar_config' => self::hrAvatarConfigs($organizationId)`, which requests `GET /v1/avatar-configs?limit=100&external_ref=org_{id}[&cursor=]`, follows `next_cursor` for at most 10 pages through the existing `request()`, keeps `sync_status ∈ {synced, not_required}`, drops any row whose `external_ref` is not exactly `HrAvatarConnection::organizationRef($id)`, and maps through `entry(...)`.
- [ ] 7.4 GREEN: edit `api/app/Http/Controllers/AvatarTemplateController.php` `catalogue()`: accept `hr_avatar` (with `HrAvatarConnection::unavailableProviderRule()`) and resource `avatar_config`, `CATALOGUE_RESOURCES['hr_avatar'] = ['avatar_config']`, org id from `TenantResolver::getOrgId()`, null org -> `{status: empty}`.
- [ ] 7.5 Scramble re-export (D-SCRAMBLE): `git diff --exit-code openapi.v1.json` clean; `git diff openapi.json` additive (query enums only). Show outputs.
- [ ] 7.6 Close A4: pint/phpstan; focused command exit 0; FULL `php artisan test --parallel` exit 0 shown; gga pass; commit `feat(api): proxy organization-scoped HR-Avatar configs through the catalogue`.

---

## Phase 8: A5 - export command, then api final verification

Spec: `hr-avatar-integration` (export requirement). Design: D-EXPORT, open question 1.

- [ ] 8.1 Parity check (read-only, no code): compare the `config` keys the command will send (template config minus `ttsEngine`/`ttsExternalVoiceId`, plus `voice {engine, voice_id}`) against the avatar-config field specs in `hr-avatar/openspec/changes/hr-avatar-engine/` (read-only) and, if present, `hr-avatar/service` (read-only). Record the result in the apply-progress note: match, or the list of mismatching keys. A mismatch does not block coding (it fails safely as `provider_rejected`) but it blocks any non-local `--apply` claim.
- [ ] 8.2 RED: create `api/tests/Feature/HrAvatar/ExportTemplatesToHrAvatarTest.php`
  - Dry run: three eligible templates -> no HTTP (`Http::preventStrayRequests()`), no row change, three `would_create` lines and a count, exit 0, works while unavailable; `already_linked` reported for a linked row; platform template (null organization) and soft-deleted rows skipped.
  - `--apply` while unavailable: exit 1, output names the missing variable names only (never values), no request, no write.
  - `--apply`: two templates and 201 `avc_A` / `avc_B` -> ids written; every other column byte-identical (`updated_at`, `is_active`, `provider`, compared column by column); each POST carries its own organization's `external_ref` (`org_<id>`); name is `mb_substr(name, 0, 120)`.
  - `sync_status` per row (validation finding 6): 201 bodies with `sync_status` `synced` and `pending` -> output lines `created avc_A sync_status=synced` and `created avc_B sync_status=pending`; a hostile value (`"PENDING; rm"`) prints `sync_status=unknown`; the summary counts rows by `sync_status` and the closing line states that `pending` configs cannot start a conversation until synced; the `pending` id is still written.
  - 403 `insufficient_scope` (key without `avatar_configs:write`) -> `failed provider_unauthorized`, no write, exit non-zero.
  - Idempotent re-run: no second create for a linked row. One 422 + one 201 -> first `failed provider_rejected` with null id, second linked, exit non-zero.
  - Body hygiene: no provider API key, LLM credential or binding, `llm_model_id`, or `persona.display_name` in any request body; the returned id must match `^avc_[0-9A-Za-z]+$` (<= 64) or the row is `failed provider_bad_response` and not written; a concurrent already-set id is never overwritten (`whereNull` predicate).
- [ ] 8.3 GREEN: create `api/app/Console/Commands/ExportTemplatesToHrAvatar.php` (signature `hr-avatar:export-templates {--apply}`) per D-EXPORT: cross-tenant read with `withoutGlobalScopes()->whereNotNull('organization_id')->whereNull('deleted_at')->orderBy('id')`, failure codes reusing the catalogue vocabulary, write via `DB::table('avatar_templates')->where('id')->where('organization_id')->whereNull('hr_avatar_config_id')->update(...)`; print `created avc_… sync_status=<value>` (value allowlisted `^[a-z_]{1,32}$`, else `unknown`), a per-`sync_status` summary, and the closing `pending` reminder (D-EXPORT).
- [ ] 8.4 REFACTOR + static checks: pint, phpstan exit 0 shown.
- [ ] 8.5 Close A5: focused command exit 0; FULL `php artisan test --parallel` exit 0 shown; gga pass; commit `feat(api): add hr-avatar:export-templates dry-run command`.
- [ ] 8.6 api final verification (alone, no other api run in parallel): `php artisan test --coverage --min=98` exit 0 shown with the coverage figure; confirm per-file coverage of every new production class is above 85% (`HrAvatarConnection`, `HrAvatarProvider`, `ExportTemplatesToHrAvatar`, the new catalogue and controller branches) and add missing tests (as new files only) if not.
- [ ] 8.7 api invariance evidence: `git -C api diff --name-status develop...HEAD -- tests` lists only `A` (added) entries, plus the single method addition in `ExposureCatalogue.php` helper (state it explicitly: it is the one modified test-support file; no test file and no existing entry edited); `git -C api diff --exit-code develop -- openapi.v1.json` clean; pint and phpstan exit 0 once more over the tracker head.

---

## Phase 9: B1 - backoffice option and picker (needs A3a + A4; independent of F*)

Spec: `avatar-templates` (backoffice form requirement). Design: File Changes (backoffice), Testing Strategy.

- [ ] 9.1 Sync the contract: copy `api/openapi.json` (read-only) to `backoffice/openapi.json`, run `bun run codegen` to regenerate `backoffice/types/api.ts` (generated, excluded from the authored count). Show the repo's codegen drift check exit 0 if one exists.
- [ ] 9.2 RED: create `backoffice/tests/unit/avatar-template-form-hr-avatar.spec.ts`
  - Field specs without an `hr_avatar` key: provider options are exactly heygen, tavus (that order) and no picker; with the key: the option appears and selecting it renders the picker listing catalogue items; selecting one sets the id.
  - Payload for `hr_avatar` carries `provider`, `name`, `hr_avatar_config_id` and `config: {}` only (no label/settings copy, no LLM fields, no knob controls); heygen/tavus payloads byte-identical to today.
  - Proxy `provider_error` and `empty` -> manual text input accepting an `avc_...` id and submission possible; client check `^avc_[0-9A-Za-z]+$`; a 422 keyed `hr_avatar_config_id` renders under the picker through `applyServerFieldErrors`.
  - Edit mode shows the provider but locked; the LLM block is hidden for `hr_avatar`; it/en parity for every new key; no hard-coded copy.
  - The combobox mounted with `provider: 'hr_avatar'` and `catalogue_resource: 'avatar_config'` renders no listen/sample control (D-BO-TYPES).
  - `ProjectTable.vue` with a project whose `avatar_template.provider` is `hr_avatar` renders the translated `projects.avatarProvider.hr_avatar` value in `it` and `en`, never the raw key (validation finding 11, `ProjectTable.vue:65`).
- [ ] 9.3 GREEN (D-BO-TYPES, validation finding 10): edit `backoffice/app/types/avatar-template.ts`: leave `ProviderName` (:50) as `'heygen' | 'tavus'`; add `TemplateProvider = ProviderName | 'hr_avatar'` and `FieldSpecMap = Record<ProviderName, FieldSpec[]> & { hr_avatar?: FieldSpec[] }`; `FieldSpecsResponse.data` (:193) becomes `FieldSpecMap`; `AvatarTemplate.provider` (:232) becomes `TemplateProvider` (leave `PlatformTemplate.provider` at :295 as `ProviderName`); `AvatarTemplate.hr_avatar_config_id?`; submit type. `CatalogueProvider`/`CatalogueResource` widen by themselves from the regenerated client (no hand edit). Edit `backoffice/app/composables/useAvatarTemplates.ts` (`hr_avatar_config_id?` in create/update payload types).
- [ ] 9.4 GREEN: edit `backoffice/app/components/organisms/AvatarTemplateProviderCombobox.vue`: optional prop `manualOnEmpty` (default false) rendering the manual input in the `empty` state; `previewProvider` (:473) returns `null` for `hr_avatar` as it does for `tavus`; `blockPreview` (:476) yields no preview for `hr_avatar`; the `preview` prop type (:452) and `useVoicePreview` are not changed; no sample control for `hr_avatar`.
- [ ] 9.5 GREEN: edit `backoffice/app/components/organisms/AvatarTemplateForm.vue`: `fieldSpecs` prop (:521) typed `FieldSpecMap`; provider state (:556) typed `TemplateProvider`; `providers` computed from field-spec keys (`heygen`, `tavus`, plus `hr_avatar` iff `fieldSpecs.hr_avatar !== undefined`), picker block via the combobox with the synthetic `hr_avatar_config_id` field, LLM block hidden, client id check, server error mapping, submit adds `hr_avatar_config_id` and `config: {}` only for `hr_avatar`.
- [ ] 9.6 GREEN: edit `backoffice/app/pages/avatar-templates/index.vue` (forward `hr_avatar_config_id` only when present, around :567 and :577) and add `avatar_templates.provider.hr_avatar`, picker label and hint, **and `projects.avatarProvider.hr_avatar`** (next to the existing `heygen`/`tavus` entries at `projects.avatarProvider`, line ~537) to `backoffice/i18n/locales/it.json` and `backoffice/i18n/locales/en.json`. The backoffice is admin-facing, so the provider label may name the product (the frontend neutrality rule does not apply here).
- [ ] 9.6a GREEN (types only): `backoffice/app/pages/avatar-templates/index.vue` `fieldSpecs` ref (:400) and `backoffice/app/pages/platform-templates/index.vue` `fieldSpecs` ref (:259) typed `FieldSpecMap` (their `{ heygen: [], tavus: [] }` initialisers stay); the create-payload cast at `avatar-templates/index.vue:580` uses `TemplateProvider`. No runtime change on the platform page.
- [ ] 9.7 Close B1: focused spec exit 0; FULL `bun run test:unit` exit 0 shown (existing specs unedited); `bun run lint` exit 0 and **`bun run typecheck` (`nuxi typecheck` + `typecheck:e2e`) exit 0 shown** (the D-BO-TYPES gate: `ProviderName` unchanged, the `CatalogueProvider` widening absorbed by the combobox); gga pass; commit `feat(backoffice): offer hr_avatar templates and a config picker when the api reports it`. No browser or viewport gate is introduced (backoffice rule).
- [ ] 9.8 backoffice final verification: `bun run test:unit --coverage` exit 0 shown with the report; new files above 85%; `git -C backoffice diff --name-status develop...HEAD -- tests` shows only `A`; run `bun run test:e2e` only if the stack is up, otherwise record it as not run (CI runs it unchanged).

---

## Phase 10: F1 - SDK dependency, flag, types, start mapping (frontend) - BLOCKED

Dependency: BLOCKED until HR-Avatar SDK slice 39 (design "S8") produces a packable `@hr-avatar/sdk` tarball with its `./mock` export; also needs A2b done (start schema). Dependency Resolution Policy applies: if the tarball does not resolve, STOP and report the exact package, version and error; never substitute a library or loosen a constraint.

- [ ] 10.1 Gate: confirm `hr-avatar/sdk/package.json` (read-only) exists and `cd hr-avatar/sdk && bun run build` exits 0 shown. If it does not, mark F1-F3 BLOCKED in the apply report and stop this phase; do not scaffold a fake SDK.
- [ ] 10.2 Vendor: `cd hr-avatar/sdk && bun pm pack --destination ../../frontend/vendor` to produce `frontend/vendor/hr-avatar-sdk-<ver>.tgz` (the SDK sources under `hr-avatar/sdk` are read-only); then `cd frontend && bun add ./vendor/hr-avatar-sdk-<ver>.tgz` updating `frontend/package.json` and `frontend/bun.lock` (integrity recorded). Record the exact version string and the integrity behaviour (design open question 3).
- [ ] 10.3 Edit `frontend/Dockerfile`: `COPY vendor ./vendor` next to `COPY package.json bun.lock ./`, before `bun install --frozen-lockfile`.
- [ ] 10.4 Sync the contract: copy `api/openapi.json` (read-only) to `frontend/openapi.json`, run `bun run codegen` to regenerate `frontend/types/api.ts` (generated).
- [ ] 10.5 RED: create `frontend/tests/unit/hr-avatar-start-config.spec.ts`: a `/start` body with `provider: hr_avatar`, `provider_token: CS`, `hr_avatar {base_url, publishable_key}` yields `StartConfig.hrAvatar {baseUrl, publishableKey}` plus `sessionToken` CS and the phrases; the key is absent for heygen/tavus/mock bodies; `StartConfig` keeps a closed shape (no index signature); no `live_conversation_id` is sent for an `hr_avatar` handle. Use the stubbed-fetch pattern of the existing session specs.
- [ ] 10.6 GREEN: edit `frontend/app/types/interview-provider.ts` (`ProviderName` + `'hr_avatar'`, `StartConfig.hrAvatar?: { baseUrl: string; publishableKey: string }`), `frontend/nuxt.config.ts` (`runtimeConfig.public.hrAvatarEnabled: ''`, env `NUXT_PUBLIC_HR_AVATAR_ENABLED`), and `frontend/app/composables/useInterviewSession.ts` (`...(response.hr_avatar ? { hrAvatar: { baseUrl, publishableKey } } : {})` near :2025; keep the `hr_avatar` handle out of the continuation path and the `live_conversation_id` send).
- [ ] 10.7 Existing-suite guard: run `frontend/tests/unit/interview-provider-types.spec.ts` and `frontend/tests/unit/provider-factory.spec.ts` (read-only, unedited) first. If adding the union member breaks an existing assertion, STOP and report; do not edit existing tests.
- [ ] 10.8 Bare-clone check: after the commit, clone the repo into the scratchpad (`git clone <path to frontend> <scratchpad>/frontend-clone`), run `bun install --frozen-lockfile` and `bun run build` there, both exit 0 shown, proving `@hr-avatar/sdk` resolves from the vendored tarball with no sibling repository.
- [ ] 10.8a Version catalog in F1 (validation finding 17, design D-SDK; moved here from W1): edit wrapper `docs/version-catalog.md`: add the `@hr-avatar/sdk` row under "Runtimes and frameworks" (vendored, the exact version recorded in 10.2; optional peers `@daily-co/daily-js` `^0.91` and `@heygen/liveavatar-web-sdk` `^0.0.18`, already direct dependencies of `frontend`). Verify with `rg -n 'hr-avatar/sdk' docs/version-catalog.md`; commit in the wrapper, staging only that path: `docs(version-catalog): record the vendored @hr-avatar/sdk`. Done in the same work unit as 10.2 so the dependency never exists without its D25 row.
- [ ] 10.9 Close F1: focused spec exit 0; FULL `bun run test:unit` exit 0 shown; lint/typecheck scripts exit 0; gga pass; commit `feat(frontend): vendor the HR-Avatar SDK and map the hr_avatar start response`. (The tarball, `bun.lock` and generated types are excluded from the authored count but included in the commit.) Confirm the 10.8a wrapper commit exists before closing the unit.

---

## Phase 11: F2a - adapter core (frontend) - BLOCKED on F1

Spec: `interview-frontend` (adapter contract, states and transcripts, opacity). Design: D-ADAPTER (steps 1-4 except completion).

- [ ] 11.1 RED: create `frontend/tests/unit/hr-avatar-provider.spec.ts` using a fake SDK through the injected `sdkLoader`
  - Lazy import: constructing the adapter never loads the SDK; the first `start()` does. Missing `cfg.hrAvatar` or empty `cfg.sessionToken` -> `error` code `sdk_error` and the SDK loader is never called; empty `endPhrase` or `finalPhrase` -> `error` code `absent_phrase` and no SDK load.
  - Connect options: exactly `baseUrl`, `publishableKey`, `clientSecret`, `mount` (the page video element), `audioDeviceId` (when selected), `completionPhrases` `[endPhrase, finalPhrase]`, and `forwardTranscript === HR_AVATAR_FORWARD_TRANSCRIPT === false`.
  - State mapping (validation finding 2): SDK states `connecting`, `live`, `ended` -> provider `connecting`, `ready`, `stopped` in order (the `stopped` emission is deferred one macrotask, so advance fake timers); SDK `error` state -> `error` event. Transcripts: only final lines emitted with `{role, text, ts: occurredAt}`; interim dropped. (Latch precedence over `complete`/`error` is covered in 12.1.)
  - Mic: `setMicMuted(true)` twice then `toggleMic()` -> muted (second call a no-op), then unmuted. `whenAvatarSilent(2000)` with a never-resolving SDK promise resolves at <= 2000 ms (fake timers) and never rejects; the SDK silence call receives `AVATAR_SETTLE_MS` imported from `~/app/providers/tavus` (500). `stop()` twice with a rejecting SDK `end()` -> neither rejects and `end()` attempted once.
  - Opacity: a rejected connect whose message names HR-Avatar and the base URL -> `sdk_error` and no serialization of the payload contains `hr-avatar` or the host; origin refusal -> `origin_not_allowed`; a rejected dynamic import -> `sdk_error` without leaking the rejection text; no event payload, console output or DOM contains the client secret or publishable key.
  - Connect-time refusals after `/start` (validation finding 7): `connect()` rejecting with an SDK error whose code is `provider_concurrency_limited` (status 429), `provider_credential_missing` or `provider_error` -> one `error` event `{code: 'sdk_error', message: 'provider_unavailable'}` each (never `origin_not_allowed`, never `absent_phrase`), with no vendor text.
  - Static scans: `app/providers/hr-avatar.ts` has no static `@hr-avatar` import line; `it.json` and `en.json` and the DOM the adapter creates contain no `hr-avatar|hr_avatar|hravatar|hr avatar` (case-insensitive).
- [ ] 11.2 GREEN: create `frontend/app/providers/hr-avatar.ts` per D-ADAPTER: `export const HR_AVATAR_FORWARD_TRANSCRIPT = false` with a one-line comment citing HR-Avatar reconciliation item 39 (the flag suppresses utterance forwarding only; lifecycle events are always forwarded); `HrAvatarProvider implements InterviewProvider` with the injectable `sdkLoader` (dynamic `import('@hr-avatar/sdk')` behind `import.meta.client`, SDK types via `typeof import(...)` only), guards, connect, state and transcript mapping (SDK `state ended` -> deferred `stopped`), mic controls, bounded `whenAvatarSilent` using `import { AVATAR_SETTLE_MS } from '~/app/providers/tavus'` (do NOT move or copy the constant; `tavus.ts` stays unedited), idempotent quiet `stop`, error-code mapping with scrubbed message (every non-origin SDK code -> `sdk_error`); `nudgeWrapUp` omitted. Completion handling and the full terminal latch are added in F2b.
- [ ] 11.3 REFACTOR + checks: lint/typecheck exit 0; run `frontend/tests/unit/provider-anonymity.spec.ts` (read-only, unedited) and confirm it stays green (the adapter is not referenced from the default path yet).
- [ ] 11.4 Close F2a: focused spec exit 0; FULL `bun run test:unit` exit 0 shown; gga pass; commit `feat(frontend): add HrAvatarProvider adapter core`.

---

## Phase 12: F2b - completion logic (frontend) - BLOCKED on F2a

Spec: `interview-frontend` (completion rules). Design: D-COMPLETE, resolved item 6.

- [ ] 12.1 RED: create `frontend/tests/unit/hr-avatar-provider-completion.spec.ts` (fake SDK, fake timers)
  - Avatar final line "passiamo alla prossima domanda" with `endPhrase = 'Passiamo alla prossima domanda.'` -> exactly one `complete` after `whenAvatarSilent(COMPLETION_SETTLE_MS)` raced with `closingFallbackMs(text)`; accent, case and punctuation differences tolerated (`matchesEndPhrase`); the candidate's line containing the phrase never completes.
  - SDK `ended` with reason `completion_phrase` -> `complete`; reasons `user`, `server`, `provider` -> `stopped` without `complete`; reason `error` -> `error`.
  - Both triggers firing (BEAI match then SDK `completion_phrase`) emit `complete` exactly once; the latch resets only on a new `start()`.
  - Terminal latch precedence (design D-COMPLETE table, validation finding 2): SDK `state ended` then `ended{completion_phrase}` in the same tick -> `complete`, no `stopped`; `ended{completion_phrase}` then `state ended` -> `complete`, no `stopped`; `ended{provider}` while a BEAI match is still settling -> `complete` at once, no `stopped`; SDK `error` then `state ended` -> `error`, no `stopped`; `ended{user}` then `state ended` -> exactly one `stopped`.
- [ ] 12.2 GREEN: edit `frontend/app/providers/hr-avatar.ts`: add the avatar-line `matchesEndPhrase()` trigger (from `frontend/app/utils/proctor-config.ts`, read-only), the settle race (`completing` flag), the SDK `ended` reason mapping and the per-start `terminal` latch (`null | 'complete' | 'error' | 'stopped'`) per the D-COMPLETE table, with `state ended` handled by a `setTimeout(0)`-deferred re-check.
- [ ] 12.3 REFACTOR + checks: lint/typecheck exit 0.
- [ ] 12.4 Close F2b: focused spec exit 0; FULL `bun run test:unit` exit 0 shown; gga pass; commit `feat(frontend): complete hr_avatar interviews on the end and final phrases`.

---

## Phase 13: F3 - flag-gated factory arm, then frontend final verification - BLOCKED on F2b

Spec: `interview-frontend` (flag requirement, SSR exclusion). Design: D-FACTORY, resolved item 2.

- [ ] 13.1 RED: create `frontend/tests/unit/hr-avatar-factory.spec.ts` (`vi.stubGlobal('useRuntimeConfig', ...)` like the existing specs)
  - Runtime flag value (after Nuxt's `destr` coercion, design D-FACTORY, spec amendment A7) `undefined`, `''`, `1`, `'1'`, `'yes'`, `false` -> `createProvider('hr_avatar', false)` throws the existing unknown-provider error (same text) and the adapter module is not evaluated (a `vi.doMock` factory sets a flag when evaluated) and the SDK is never imported. Do NOT assert that `'TRUE'` stays off: env `TRUE` reaches the runtime as boolean `true`.
  - Runtime flag `true` and `'true'` -> an `InterviewProvider` is returned synchronously and the SDK is not yet imported; `mock === true` wins for any name; `heygen`/`tavus` unchanged; `factory.ts` contains no static `hr-avatar` import line.
  - One `destr` check (no Nuxt boot): `destr('TRUE') === true`, `destr('1') === 1`, `destr('') === ''`, documenting the env-to-runtime mapping the flag relies on.
  - Deferred handle: `on()` subscriptions buffered and replayed after the lazy load; `start()` imports the adapter then delegates; `stop`, `toggleMic`, `setMicMuted` before load are no-ops; `whenAvatarSilent` before load resolves; a rejected adapter import emits `error {code: 'sdk_error', message: 'provider_unavailable'}` and resolves `{}`.
- [ ] 13.1a RED/characterization (validation finding 7): create `frontend/tests/unit/hr-avatar-connect-retry.spec.ts`: through `useInterviewSession` with a stubbed fetch (pattern of the existing session specs) and a stubbed factory whose provider emits `error {code: 'sdk_error', message: 'provider_unavailable'}` after a 201 `/start` with `provider: 'hr_avatar'`: the session moves to the retryable `error` state (not `terminal`), no automatic 429 backoff runs, and the candidate retry issues a second `/start` whose body has no `live_conversation_id`, then builds a fresh provider instance. Expected to pass once 13.2 lands (the retry path is existing code, `useInterviewSession.ts:1604`, `:1612-1618`); any failure is a defect to fix minimally, never by editing an existing test.
- [ ] 13.2 GREEN: edit `frontend/app/providers/factory.ts`: `case 'hr_avatar'` returning the private `createDeferredHrAvatar()` only when the flag is `true`/`'true'` (flag read inside the arm via `useRuntimeConfig().public.hrAvatarEnabled`), otherwise `break` into the existing throw moved after the `switch` with identical text; `import.meta.client` guard so the branch drops out of the SSR bundle.
- [ ] 13.3 Build check: `bun run build` exit 0 shown, then `! rg -l '@hr-avatar/sdk' .output/server` prints nothing and exits 0 (run inside `frontend`). Also confirm the default-path client bundle for the interview page requests no chunk containing the SDK (inspect the build manifest or output chunks with `rg`).
- [ ] 13.3a E2E (validation finding 17, the "Playwright on both Nuxt apps" rule): create `frontend/tests/e2e/interview-default-provider-path.spec.ts`, run by the existing `chromium` and `webkit` projects (not `mobile`, which matches only `unsupported-gate.spec.ts`) against the production build `playwright.config.ts` already starts, with `NUXT_PUBLIC_HR_AVATAR_ENABLED` unset. Reuse the route mocks of `tests/e2e/interview-flow.spec.ts` (read-only): a `/start` answering `provider: 'heygen'` renders the existing call stage (assert the same selector the existing call specs assert), and, collecting every `response` whose `resource type` is script during the run, no body contains `forwardTranscript` or `completionPhrases` (adapter-only object keys that survive minification). Justification recorded in the spec header: the existing interview specs run with `NUXT_PUBLIC_INTERVIEW_PROVIDER_MOCK=true` (`playwright.config.ts:126,156`) and never inspect loaded chunks, so they cannot show the default page loads no HR-Avatar code; real HeyGen/Tavus construction with the flag off stays proved by the unedited `provider-factory.spec.ts`. Prove the spec can fail (mutation check, not committed): temporarily add a static `import '~/app/providers/hr-avatar'` to `factory.ts`, rebuild, observe the marker assertion fail, revert, and confirm `git -C frontend diff -- app/providers/factory.ts` shows only the 13.2 change; record the observed failure. Run `bun run test:e2e tests/e2e/interview-default-provider-path.spec.ts`, exit 0 shown for both projects.
- [ ] 13.4 Close F3: focused specs exit 0 (factory, connect-retry, and the 13.3a Playwright spec); existing `provider-factory.spec.ts`, `provider-anonymity.spec.ts` unedited and green; FULL `bun run test:unit` exit 0 shown; lint/typecheck; gga pass; commit `feat(frontend): gate the hr_avatar provider behind a default-off runtime flag`.
- [ ] 13.5 frontend final verification: `bun run test:unit --coverage` exit 0 shown with the report; new files above 85%; `git -C frontend diff --name-status develop...HEAD -- tests` shows only `A`; run the FULL `bun run test:e2e` (the config builds and serves the app itself; do not run it beside a Docker build), exit 0 shown; if browsers cannot run in this environment, record it as not run with the reason, never as passed (CI runs it with the flag off).

---

## Phase 14: W1 - wrapper docs and cross-repo verification

- [ ] 14.1 Re-verify (no edit; the row was written in F1 task 10.8a): `rg -n 'hr-avatar/sdk' docs/version-catalog.md` shows the row, and its version equals the `@hr-avatar/sdk` version in `frontend/package.json` (read-only). A mismatch is a defect: fix the row, never the lockfile.
- [ ] 14.2 Commit the SDD artifacts of this change in the wrapper: stage explicit paths `openspec/changes/hr-avatar-adapter/` (proposal, specs, design, tasks with ticked boxes) and commit `docs(openspec): add hr-avatar-adapter change artifacts`. Nothing else is staged (not `hr-avatar/`, not `odd/`, not the gitlinks).
- [ ] 14.3 Cross-repo invariance evidence: `@beai/embed` unchanged (`git diff --exit-code develop -- embed` clean, `embed/` read-only); `api/openapi.v1.json` unchanged; no pnpm/npm/yarn artifacts introduced; no `hr-avatar`/`hr_avatar` string in `frontend/i18n/locales/*` or `backoffice/i18n/locales/*` outside the backoffice keys that name the provider (`avatar_templates.provider.hr_avatar`, the picker label/hint, `projects.avatarProvider.hr_avatar`); the frontend locale scan must be empty. Also confirm the OpenAPI diff of `api/openapi.json` against `develop` contains exactly one non-additive change (A6, store `config` leaving `required`).
- [ ] 14.4 Local wiring smoke (manual, outside the unit runners; BLOCKED on HR-Avatar S2-S8 being implemented and a human running the stack), following design Rollout steps 1-6 in order: HR-Avatar compose plus a mock-provider config attributed `org_<id>`; a secret key carrying exactly `conversations:write`, `avatar_configs:read` and `avatar_configs:write`; the publishable key's `allowed_origins` listing the BEAI frontend origin; flip both switches together (frontend `NUXT_PUBLIC_HR_AVATAR_ENABLED=true` first, then the three `HR_AVATAR_*` values on api); run `hr-avatar:export-templates` dry run then `--apply` and record each row's printed `sync_status`; pin a project to an `hr_avatar` template only once its config shows `synced` or `not_required` (it appears in the picker); complete a candidate interview; confirm a Tavus/HeyGen template on the same stack behaves as before. Optional negative checks if time allows: a key without `avatar_configs:read` makes the picker degrade to manual entry (`provider_unauthorized`); the flag off with api available shows the retryable error screen (design D-FACTORY "Both switches"). Record the result; verify the local schema first (`php artisan migrate:status` or the ready endpoint) and that containers were rebuilt, never assume stale images are current. If it cannot run, report it as pending, not passed.
- [ ] 14.5 Final report to the orchestrator: for each repo the focused/full/coverage exit codes, line counts per work unit (flag any unit above ~400 authored lines with the reason, per the chained-pr bounded-slicing rule), open items (prompt-size measurement, config key parity, SDK version/integrity, GDPR sign-off before enabling outside local) and the list of commits per tracker branch.
