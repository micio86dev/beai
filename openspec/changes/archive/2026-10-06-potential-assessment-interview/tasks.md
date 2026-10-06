# Tasks: Potential Assessment Interview

Change: `potential-assessment-interview`. Strict TDD (api runner: `php artisan test --compact <files>`,
Pest; CI-equivalent serial: `pest --coverage --min=85`). All artifacts in English. The ~400-line figure
is an advisory planning heuristic (additions plus deletions), not a hard cap.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | api ~350-440 (production ~45-55, tests ~300-385); wrapper docs/spec ~60-100 |
| 400-line budget risk | Medium |
| Chained PRs recommended | Yes |
| Suggested split | api PR 1 (characterization + production + unit/feature tests, ~230-300) -> api PR 2 (potential end-to-end test, ~110-140) -> wrapper PR (docs, archive-time spec edits, submodule pointer) |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium

Notes:

- Under `auto-chain` no pre-apply question is required, but the chain strategy is not yet chosen. The
  orchestrator must obtain `stacked-to-main` or `feature-branch-chain` before opening the api PR 2.
  Recommendation: `stacked-to-main`. PR 2 depends only on PR 1 being merged and adds one new test file
  with no production change, so it has an independent revert boundary and stacking to `develop` is the
  lower-ceremony choice. PR 1 can be implemented and merged without the choice being made.
- The end-to-end test (`PotentialInterviewEndToEndTest.php`) MOVES to the second slice. The design
  total (~350-440) sits at the budget; keeping the E2E file in PR 1 would push PR 1 over it. If the
  running count of PR 1 is comfortably under ~400 at the end of phase 4, the E2E file MAY be folded
  back into PR 1 (advisory, no size-only rework).
- The wrapper PR (spec delta archival, docs alignment, submodule pointer) is separate and small. The
  archive-time live-spec edits (tasks 6.x) run only at the archive phase, not during apply.
- Git Flow: one `feature/potential-assessment-interview` branch per repo touched (`api`, wrapper).
  `frontend` and `backoffice` are untouched and keep their pointers. SemVer bumps happen only at
  release time per `docs/git-flow.md`. No deploy.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Characterization pin, enum default-deny guard, role `match`, nullable composer, unit + feature tests | api PR 1 (base: `develop`) | `php artisan test --compact tests/Unit/C8/StandardPromptCharacterizationTest.php tests/Unit/C8/SystemPromptComposerTest.php tests/Feature/C8/InterviewStartCompositionTest.php` | Pest feature tests drive real `POST /api/candidate/interview/start` against Postgres with `Http::fake(c8HeygenFake())`; `phpstan analyse --memory-limit=1G` level 8 | Revert the PR: restores the W1 guard and `int $roleId`; no migration or data to repair |
| 2 | Potential interview through scoring and the 90% completion gate | api PR 2 (base: PR 1 branch under `feature-branch-chain`, or `develop` under `stacked-to-main` after PR 1 merges) | `php artisan test --compact tests/Feature/Interview/PotentialInterviewEndToEndTest.php` | Pest end-to-end: `/start` -> completed sessions -> `ScoreEvaluationJob` run synchronously with faked `LLMProvider`, `Queue::fake()` for the webhook job | Delete the single new test file; no production change |
| 3 | Docs alignment + spec delta archival + wrapper submodule pointer | wrapper PR (after api PR 1 and 2 land) | `rg -n -i "4 fixed|fixed questions|more rigid structure" docs/app_description` returns no match in the three files | N/A: documentation and pointer change only, no runtime behavior | Revert the wrapper commit(s); api behavior is independent of docs |

## Phase 1: Characterization pin (api PR 1, FIRST commit, before any production edit)

Spec: "Standard Prompt Is Byte-Identical Across This Change" (design D6).

- [x] 1.1 Create branch `feature/potential-assessment-interview` from `develop` in the `api` submodule (`git -C /Users/alessandromicelli/Desktop/beai/api checkout -b feature/potential-assessment-interview develop`). Confirm a clean tree for `app/` before any edit.
  Evidence: worktree `/Users/alessandromicelli/Desktop/beai-worktrees/api-potential`, branch `feature/potential-assessment-interview` cut from `origin/develop` (226d30e); the api submodule checkout was not touched.
- [x] 1.2 RED: create `api/tests/Unit/C8/StandardPromptCharacterizationTest.php` composing a `standard` prompt via `SystemPromptComposer::compose()` from fully fixed inputs (fixed role code, fixed competency code, three fixed indicators with `en` and `it` text and anchors, two fixed primaries, budget 4, nudge 120, fixed advance phrase, `SpokenOpening::primary(1)`, explicit `config(['conversation.min_questions' => 4])` and every other config key the composer reads pinned inside the test) for locales `en` and `it`. Assert `hash('sha256', $prompt->text)` and `strlen($prompt->text)` against PLACEHOLDER constants. Run `php artisan test --compact tests/Unit/C8/StandardPromptCharacterizationTest.php` on UNMODIFIED production code and read the actual sha256 and length values off the failing expectation. Test: fails RED only because of the placeholders.
- [x] 1.3 GREEN: replace the placeholder constants with the observed values (pre-change code). Run the same command; expect green for `en` and `it`. Run it twice to confirm determinism.
- [x] 1.4 Commit alone, before any `app/` change: `test(api): pin the standard composed prompt before the potential unlock`. Record the commit hash here as evidence: `characterization commit = <hash>`. Gate: `git -C api diff --stat` between this commit and any later one must show the constants file unchanged.
  Evidence: `characterization commit = 8eb9bdd` (en sha256 `1b1aa512...a62ac` len 4320; it sha256 `ef778652...e11` len 4323). Constants unchanged after every later commit; green after 2.3 and 3.6.

## Phase 2: Composer accepts a role-less lookup (api PR 1)

Spec: "Potential Composes And Starts Through The Same Adaptive Engine" scenarios "Composition for potential needs no role" and "Role-less lookup never returns role-scoped indicators"; "Potential Competency Without BARS Rows Fails Explicitly" scenario "The failure message is readable for a role-less lookup"; design D3, D5.

- [x] 2.1 RED: in `api/tests/Unit/C8/SystemPromptComposerTest.php` add a test that composes with `roleId: null` for a competency having role-less rows AND a role-scoped decoy row for the same competency and revision, using the real `BarsIndicatorLoader` against Postgres; assert the prompt contains the role-less indicator and anchor text and does NOT contain the decoy text. Run `php artisan test --compact tests/Unit/C8/SystemPromptComposerTest.php --filter=role-less`; expect failure (`TypeError`, `int` required).
- [x] 2.2 RED: in the same file add a test that `compose(roleId: null)` with zero role-less rows throws `CompositionException` whose message names the competency and revision and contains `role [none]` (not `role []`). Run; expect failure.
- [x] 2.3 GREEN: in `api/app/Services/Conversation/SystemPromptComposer.php` change `int $roleId` to `?int $roleId`, update the docblock (`null` = role-less `potential` lookup, forwarded unchanged to `BarsIndicatorLoader::forRoleCompetency()`), and render `none` for `null` in the empty-indicator `CompositionException` message. Touch nothing else in the file (no template, section, clamp). Run the file; expect tests 2.1, 2.2 and all pre-existing tests green, and re-run `StandardPromptCharacterizationTest.php`: constants unchanged and green.
- [x] 2.4 Commit: `feat(api): let the prompt composer take a role-less lookup`.
  Evidence: commit 2027d19.

## Phase 3: Controller guard and role branch (api PR 1)

Spec: "Assessment Type Default-Deny Applies Only To Unknown Types", "Potential Composes And Starts ...", "Potential Competency Without BARS Rows Fails Explicitly"; design D1, D2, D4, D5. All feature tests run with `Http::fake(c8HeygenFake())`.

- [x] 3.1 RED (invert W1, fresh start): in `api/tests/Feature/C8/InterviewStartCompositionTest.php` (test at ~:632) rewrite the W1 `potential` test into "potential starts": add a small file-local `c8SeedPotentialScenario()` helper (potential project, `role_code` null, MTG/LAT competencies, role-less 3-indicator BARS rows, authored primary in `project_questions`). Assert `201`, exactly one `interview_sessions` row, the provider body `system_prompt` contains the role-less indicator text and the authored primary, and `question_context.prompt_version` equals the non-null config value `standard` uses. Run `--filter="potential starts"`; expect RED (`assessment_type_not_supported`).
- [x] 3.2 RED (invert W1, resume): rewrite the second W1 test (~:675) into "potential resumes": participant `in_corso` with an existing session; assert `201`, outgoing provider ref harvested and released, fresh session issued with the composed prompt, no `assessment_type_not_supported` and no `composition_error`. Run; expect RED.
- [x] 3.3 RED (minimum clamp A2): add a test with one authored primary, budget 4 and configured minimum 6; assert the provider `system_prompt` states a minimum of 5 (`min(6, 1 + 4)`) and no larger minimum appears. Run; expect RED until 3.6 lands.
- [x] 3.4 RED (default-deny): add a Pest dataset test over both paths (`fresh`, `resume`) that updates the stored type to a bogus value through raw `DB::table('projects')->update([...])` (bypassing model validation) and asserts `422` `assessment_type_not_supported`, zero new sessions, unchanged participant status, and `Http::assertNothingSent()`. Run; expect failure on the pre-change literal guard only for correct reasons (the bogus value currently also returns 422, so the test must additionally assert the guard runs before the template preflight and interviewability gate by seeding a project that would otherwise fail those with a different code; that stricter assertion is the RED).
  Evidence: on the pre-change literal guard this test passes on arrival (a bogus type was already refused), so RED was established by mutation instead: fallback to `AssessmentType::Standard` for unknown types -> both `fresh` and `resume` cases failed; restored and green.
- [x] 3.5 RED (standard without role + no BARS rows): add (a) a `standard` project whose role is unresolvable in the pinned revision -> `422` `composition_error`, zero sessions, nothing sent; (b) a `potential` project whose pinned revision has only a role-scoped decoy row for MTG -> `422` `composition_error`, zero sessions, nothing sent; (c) `potential` with complete MTG rows but no role-less LAT rows, reaching LAT -> `422` `composition_error`, no provider call for the failing competency. Run; (a) may already pass (characterization), (b) and (c) are RED until 3.6.
- [x] 3.6 GREEN: in `api/app/Http/Controllers/Candidate/InterviewController.php`: (1) replace `$project->assessment_type !== 'standard'` (~:175) with a once-resolved `AssessmentType` default-deny at the same position (same `assessment_type_not_supported` code, still before preflight, gate, harvest, session write and provider call, fresh and resume); (2) add `AssessmentType $assessmentType` to `composePromptForCompetency()` and pass the resolved enum at its single call site; (3) resolve the role with the exhaustive `match ($assessmentType)` from design D2 with NO `default` arm (`Standard` keeps the identical `Role::where('code', $project->role_code)->where('revision_id', $revisionId)->first()?->id`; `Potential` is `null`), keeping `composition_error` when `Standard` and the role is null; (4) update the W1 comment (~:170-174), gate-ordering comment (~:198-200), role comment (~:877-882) and failure-codes docblock. Run `php artisan test --compact tests/Feature/C8/InterviewStartCompositionTest.php`; expect 3.1-3.5 green and every pre-existing `standard` test green with no edit to its assertions.
- [x] 3.7 PHPStan contingency (design D1 note): run `vendor/bin/phpstan analyse --memory-limit=1G` (level 8). If it reports `identical.alwaysFalse` (or equivalent) on the `AssessmentType::tryFrom(...) === null` branch because `Project::$assessment_type` is documented as the literal union `'standard'|'potential'`, change the guard to read the raw stored attribute (`$project->getAttributes()['assessment_type'] ?? null`), narrow with `is_string()`, then `AssessmentType::tryFrom()`; re-run 3.4 and phpstan. Do NOT add `@phpstan-ignore` and do NOT widen the `Project` model docblock. If phpstan is already clean, record "no contingency needed" here. Also confirm there is no `match.unhandled` error on the exhaustive `match`.
  Evidence: contingency APPLIED. phpstan reported `identical.alwaysFalse` on the `tryFrom() === null` branch; guard now reads `getAttributes()['assessment_type']`, narrows with `is_string()`, no ignore, no docblock widening. No `match.unhandled`. Remaining 2 errors (`PasswordBroker::createToken()` in SendPasswordResetLinkJob / SendUserInvitationJob) are pre-existing and identical on the base.
- [x] 3.8 REFACTOR: with all tests green, tidy the controller branch and comments (no behavior change, no new abstraction); re-run the three PR 1 test files plus `StandardPromptCharacterizationTest.php` (constants still unchanged). Run `vendor/bin/pint --test`.
- [x] 3.9 Commit (conventional, split as needed): `feat(api): start potential interviews through the adaptive engine` and `test(api): cover unknown-type default-deny and potential composition errors`.
  Evidence: commit e073022 (production + tests in one commit, because the inverted W1 tests and the guard change cannot be green separately).

## Phase 4: PR 1 verification gate (api)

- [x] 4.1 Run the whole C8/C7a `standard` regression set unmodified: `php artisan test --compact tests/Feature/C8 tests/Unit/C8`; confirm `git -C api diff` shows no edit to any pre-existing `standard` assertion.
- [x] 4.2 Run the CI sequence for the api: `vendor/bin/pint --test`, `vendor/bin/phpstan analyse --memory-limit=1G`, `php artisan test --parallel`, `vendor/bin/pest --coverage --min=85` (serial, one run at a time; do not run beside container builds). Confirm composer and loader paths stay at or above ~95% coverage.
  Evidence: `pint --test` passed; phpstan 2 pre-existing errors only (see 3.7); serial `vendor/bin/pest --coverage --min=85` EXIT=0: 7938 tests, 7920 passed, 18 skipped, total coverage 95.7%, SystemPromptComposer 100%, BarsIndicatorLoader 100%, InterviewController 90.9% (uncovered lines are pre-existing). `php artisan test --parallel` was not run separately. The worktree lives outside the wrapper, so a `docs` symlink at `/Users/alessandromicelli/Desktop/beai-worktrees/docs` was needed for seeder/catalogue tests (first run: 33 failures, all missing `../docs`; green after the symlink).
- [x] 4.3 Verify no OpenAPI drift: run the project OpenAPI export task and confirm the diff against the committed `openapi.json` is empty (error code set unchanged). If not empty, stop and investigate before shipping.
  Evidence: `scramble:export` (APP_NAME=BEAI, Postgres) diff against committed `openapi.json` is empty.
- [x] 4.4 Count authored changed lines for PR 1 (`git -C api diff --shortstat develop...HEAD`) and record it here; if it leaves room for the E2E file under ~400, task 5.x MAY stay in PR 1, otherwise it proceeds as PR 2.
  Evidence: `git diff --shortstat origin/develop` = 5 files, 408 insertions, 78 deletions (486 authored lines; production 71, tests 415). Over the ~400 advisory heuristic, so the E2E file stays in PR 2.
- [ ] 4.5 Push `feature/potential-assessment-interview` of the `api` submodule and open api PR 1 targeting `develop` (conventional-commit title, no AI attribution lines in commits). Verify the push landed on the remote before touching the wrapper pointer.

## Phase 5: Potential end-to-end through scoring and the completion gate (api PR 2)

Spec: "Potential Scoring And Completion Parity" and the two scenarios in it; proposal success criterion on `completato` and webhook shape. Depends on PR 1 being merged (or stacked on its branch).

- [x] 5.1 Create `feature/potential-assessment-interview-e2e` in `api` from the merged `develop` (stacked-to-main) or from the PR 1 branch (feature-branch-chain). Record the chosen chain strategy in the forecast above and update `Chain strategy:`.
  Evidence: chain strategy `stacked-to-main`; branch cut from PR 1 HEAD e073022 in worktree `/Users/alessandromicelli/Desktop/beai-worktrees/api-potential` (the PR 1 branch is untouched).
- [x] 5.2 RED: create `api/tests/Feature/Interview/PotentialInterviewEndToEndTest.php` with its own file-local helpers (no cross-file test functions): seed a `potential` project with MTG and LAT, role-less 3 indicators each, authored primaries; call `/start` for each competency (`201`); mark sessions completed with utterances; run `ScoreEvaluationJob` synchronously with a faked `LLMProvider` returning valid `{1..5}` scores; `Queue::fake()` for the webhook job. Assert the evaluation is completed, the participant is `completato`, reliability equals assessed/total (e.g. 3/3), the evaluation record carries `framework_version`, `model_version`, `prompt_version` and a timestamp, and the queued evaluation webhook payload has the standard payload keys. Run `php artisan test --compact tests/Feature/Interview/PotentialInterviewEndToEndTest.php`; if PR 1 code is already present the test passes at once, so prove it is not vacuous by temporarily asserting a deliberately wrong key and observing RED, then restoring (mutation check; the mutation MUST be reverted and the revert observed green).
  Evidence: file created; passes on arrival (no production change). Mutations, each applied then restored and re-run green: (a) expected `event` `evaluation` -> `evaluationX` -> RED; (b) below-gate expected status `pending` -> `completed` -> RED; (c) production `$roleId = null` -> `999999999` in `ScoreEvaluationJob` -> both tests RED (`pending` instead of `completed`), restored via `git checkout` and `git diff` clean. Reliability asserted 1.0 (3/3 assessed) per competency. Webhook payload is asserted on the persisted `webhook_deliveries.payload` (jsonb: key order is not preserved, so competency keys are compared as a set) plus `Queue::assertPushed(DeliverWebhookJob)`.
- [x] 5.3 (closed by the batch 11 follow-up, see Evidence) RED/GREEN: add the below-gate scenario in the same file: LLM returns `-1` for all indicators of one of two competencies so valid competencies < 90%; assert participant `pending`, webhook carries partial data, and after exactly one retry the participant is `completato` (definitive). Observe RED on a deliberately wrong expectation first, then correct it; assert exactly one retry job is dispatched.
  Evidence: below-gate part DONE and mutation-checked (evaluation `pending`, 1 valid of 2, webhook `data.status` `pending` with both competencies and `0%` reliability for the unassessable one). The RETRY part is NOT implemented in production: `ScoreEvaluationJob` only logs `domain retry path - deferred to PR4` for `retryAttempt: true` on a pending evaluation, nothing dispatches a retry, and the participant already becomes `completato` on the first terminal resolution (not `pending`). This is identical for `standard` (roadmap product decision 4, retry semantics, is OPEN). Recorded as a Pest `->todo()` test; the spec scenario wording ("candidate is `pending`") does not match current standard behavior either and needs an owner decision.
  Follow-up (batch 11, api branch `feature/retry-followups-403-doc-and-potential-e2e`, commit f972484): the `->todo()` is replaced by a real test, `a below-gate potential evaluation is retried once through the real surfaces and ends definitive`: first run MTG valid / LAT all `-1` = `pending`; operator `POST /api/participants/{id}/retry` returns `competencies_reset` = only LAT; sso exchange, `/start` + `/end` re-interview LAT only (MTG session untouched, count 1), `FinalizeInterview` + `ScoreEvaluationJob(retryAttempt: true)`; evaluation `completed` with `retry_attempt`, both results valid, participant `completato`, two `evaluation` deliveries (`{id}` and `{id}:retry`, second `completed`), second retry 409 `retry_already_consumed`. Nothing specific to potential was broken in production. Mutations (each RED, restored by diff): reset every competency instead of only the invalid ones; drop the `:retry` dedupe suffix; skip the retry scoring branch. Two fixture notes, neither a production defect: the file's helper completes sessions by hand so it now also closes the open live period (as `/end` does), and the test calls `auth()->forgetGuards()` because one PHP process serves every request of a test and the candidate guard would keep the participant resolved during the first interview. 5.4 and 5.5 remain open (push and PR belong to the orchestrator).
- [ ] 5.4 Run `php artisan test --compact tests/Feature/Interview/PotentialInterviewEndToEndTest.php` and the existing `tests/Feature/Jobs/RoleScopedIndicatorsTest.php` (read-only reference, must stay green); then `vendor/bin/pint --test` and `vendor/bin/phpstan analyse --memory-limit=1G`.
- [ ] 5.5 Commit `test(api): cover a potential interview through scoring and the completion gate`, push, verify the push landed, open api PR 2 per the chosen chain strategy.

## Phase 6: Docs alignment and spec archival (wrapper PR)

Spec: "Docs Alignment For Adaptive Potential (Documentation)" and the "Non-requirement edits to the live spec" list at the top of the delta spec. Branch `feature/potential-assessment-interview` in the wrapper from `develop`. Tasks 6.1-6.3 happen during apply; 6.4-6.6 are archive-time edits.

- [x] 6.1 (done in batch 13, wrapper commit b5610a9; the `rg` returns no match) `docs/app_description/02-domain/03-assessment-types.md` (lines ~23-24): question count reads "up to N, a platform-configured maximum (default 4)"; the "Flow" row drops "more rigid structure" and states `potential` uses the same adaptive flow as `standard`. Test: `rg -n -i "4 fixed|fixed questions|more rigid" docs/app_description/02-domain/03-assessment-types.md` returns no match.
- [x] 6.2 (done in batch 13, wrapper commit b5610a9; SA-08 no longer asserts a fixed count) `docs/app_description/06-acceptance-criteria/01-acceptance-scenarios.md` (SA-08, lines ~75-80): "up to N predefined questions (maximum)", with no fixed-count or fixed-order assertion. Test: same `rg` pattern over the file returns no match in the SA-08 block.
- [x] 6.3 (done in batch 13, wrapper commit b5610a9) `docs/app_description/01-product-and-journeys/01-product-overview.md` (line ~93): same "up to N, a maximum" wording. Test: same `rg` pattern returns no match.
- [ ] 6.4 Archive-time, `openspec/specs/interview-conversation/spec.md` Purpose (lines ~3-11): change "coverage-driven adaptive follow-up questioning for `standard` sessions (SA-02)" to "... for `standard` AND `potential` sessions (SA-02)"; leave the composed-prompt-is-an-instruction paragraph unchanged.
- [ ] 6.5 Archive-time, same file, Out of Scope (lines ~22-28): remove in full the entry "`potential` / SA-08 flow — deferred to a future slice", including "C8 delivers the `standard` adaptive path ONLY. No `potential`, no `framework_potential_questions` model, no fixed-sequence block."; then drop the empty section or leave it empty per archive convention. Optionally trim the clause "corrects this capability's Out of Scope note" from "Potential Question Cap Is A Maximum, Never A Fixed Count" (lines ~729-743) without altering its normative text or scenarios; leave "A Zero-Primary Competency Never Reaches Interview" (lines ~745-781) byte-unchanged.
- [ ] 6.6 Archive-time, same file, Coverage Note (line ~787): add `potential` (role-less) to the `ConversationService::composePrompt()` input combinations, and add the two ~95% paths: the role-less `SystemPromptComposer::compose()` path and the controller's assessment-type default-deny branch on fresh-start and resume.
- [x] 6.7 (done: commit b5610a9 on wrapper branch `feature/retry-and-potential-docs`, not pushed) Commit docs: `docs: align the potential assessment wording with the adaptive decision` (6.1-6.3). Archive-time spec edits go in the archive commit (`docs(openspec): archive potential-assessment-interview`) after the delta is merged into the live spec by the archive phase.

## Phase 7: Wrapper submodule pointer and Git Flow mechanics

Spec/process: `docs/git-flow.md` (Wrapper Submodule Pointer Pinning, Cross-Repo Merge Order). No deploy.

- [ ] 7.1 After api PR 1 (and PR 2) have merged into the `api` `develop`, bump the wrapper pointer on the wrapper feature branch: `git -C /Users/alessandromicelli/Desktop/beai add api` and commit `chore: bump api to include potential interview start`. Verify with `git -C /Users/alessandromicelli/Desktop/beai submodule status api` that the pinned SHA exists on the api remote (a silent no-op push leaves the wrapper pinning an unpublished commit). `frontend` and `backoffice` pointers stay untouched.
- [ ] 7.2 Wrapper PR order: api PR(s) first, then the wrapper PR (docs + pointer) to `develop`. Conventional commits only; no Co-Authored-By or AI attribution lines in commits.
- [ ] 7.3 Do NOT bump `VERSION`/`composer.json`/OpenAPI `info.version` in these PRs. SemVer bumps (api minor, wrapper pin, `VERSION` vs manifest agreement) happen only in a later `release/*` branch per `docs/git-flow.md` and api-first release order. No Railway deploy unless explicitly requested.
- [ ] 7.4 Delete merged feature branches only after merge is verified; never delete unmerged branches.

## Dependency Order

1.x (pin) -> 2.x (composer) -> 3.x (controller) -> 4.x (gate, PR 1) -> 5.x (E2E, PR 2) -> 6.1-6.3 (docs, independent of api, may run in parallel with 2-5) -> 7.x (pointer, needs merged api) -> 6.4-6.6 (archive phase).
Parallelizable: 6.1-6.3 are independent of all api phases. 2.1 and 2.2 can be written together. Everything in 3.x depends on 2.3.

## Key Learnings

1. The characterization hash test must be committed green on unmodified code before any production edit, so a later composer change that alters a single standard-prompt byte fails immediately.
2. The default-deny RED test must seed a project that would fail a later gate with a different error code, because a bogus assessment type already returns the same 422 code on the literal guard.
3. The potential end-to-end test belongs in a second api slice because the design total of about 350 to 440 lines sits exactly at the 400-line review budget.
4. Archive-time live-spec edits to Purpose, Out of Scope and Coverage Note cannot be expressed as ADDED or MODIFIED entries, so they are tracked as explicit tasks that run only at archive.
5. The wrapper pointer bump must be preceded by a check that the api commit exists on the remote, since a silent no-op push would leave the wrapper pinning an unpublished SHA.
