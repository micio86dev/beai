# Tasks: Database-Driven Conversation Prompts

Rescoped 2026-10-08 (see `proposal.md` status and `design.md` "Amendments 2026-10-08"). Strict TDD (Pest): RED is
observed before GREEN, and a box is ticked only for an observed outcome. PR0 is the wrapper documentation slice;
PR1 to PR9 are `api` slices, each a pull request into the api `develop` branch.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated authored changed lines | about 3,100 across PR1 to PR9 (PR0 is docs); the 2026-09-11 estimate of about 1,600 predates the goldens, the trigger and seal, the bootstrap and the cut-over hardening |
| Review budget per slice | at most about 400 authored changed lines (additions plus deletions), tests and docs included |
| Excluded from the count (stated in each PR) | generated golden fixtures `api/tests/Fixtures/Conversation/prompts/*` and `manifest.json`; the generated `api/database/prompt-sets/*.json`. They stay in the snapshot and in review |
| Budget nature | a planning heuristic, not a hard cap. If the correct solution exceeds it, say why in the PR and continue; never delete blank lines or comments, drop tests, or split artificially to fit. PR4b has a pre-declared split |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main, merged strictly in order: each slice branches from `develop` after the previous slice merged on green CI |
| Risk concentration | PR4b (composer reads fragments) and PR8 (cut-over). Neither is combined with any other slice |

```text
Decision needed before apply: No
Chained PRs recommended: Yes (10 slices)
Chain strategy: stacked-to-main, sequential
400-line budget risk: Medium (PR4b, PR5)
```

## Dependencies

```text
PR0 -> PR1 -> PR2 -> PR3 -> PR4a -> PR4b -> PR5 -> PR6a -> PR6b -> PR7 -> PR8 -> PR9
```

| Slice | Needs | Why |
|---|---|---|
| PR1, PR2 | none | capture the pre-change tree before any text moves |
| PR3 | none technically | ships ahead of every slice that reads stored data; sits after the goldens so the fixtures are captured on an untouched composer |
| PR4a | none | vocabulary only, nothing wired |
| PR4b | PR1, PR2, PR4a | its GREEN gate is the goldens |
| PR5 | none technically | additive schema, nothing reads it |
| PR6a | PR4a, PR5 | `PromptTemplateSet`, the contract, the tables |
| PR6b | PR6a | uses `PromptSetSeal` and the resolver |
| PR7 | PR4b, PR5, PR6a | `BaselinePromptFragments`, the tables, the seal |
| PR8 | PR3, PR4b, PR6a, PR7 | the only slice that changes live behaviour |
| PR9 | PR8 | `label.override` and the override section |

## Rollback story

| Slice | Rollback |
|---|---|
| PR1, PR2 | delete the tests and fixtures; nothing else touched |
| PR3 | revert the PR; the nullable column is inert |
| PR4a, PR4b | revert the PR; `compose()` keeps its old behaviour when `$templates` is null, which is the only value any caller passes until PR8 |
| PR5, PR6a, PR6b, PR7 | revert the PR; additive, nothing reads the data (`migrate:rollback` drops the tables) |
| PR8 | set `CONVERSATION_PROMPT_SOURCE=baseline` (no code revert, no redeploy of code), or revert the PR |
| PR9 | revert the PR; no override ships by default |

The baseline PHP (`BaselinePromptFragments`) stays for one release as the seed source, the test default and the
break-glass target, and is deleted by a later cleanup PR after a soak.

## Verification Commands (run from `api/`, before each slice is marked done)

Run one Pest invocation at a time: parallel runs share one test database and produce schema errors, not real failures.

- Focused: `php artisan test --filter=<TestName>` (names are listed per slice).
- Full suite (the CI gate): `php artisan test --parallel`.
- Style, scoped to touched files: `./vendor/bin/pint --test --dirty`.
- Static analysis: `vendor/bin/phpstan analyse --memory-limit=1G`.
- Coverage: `php artisan test --parallel --coverage --min=85`; the composition path is held to about 95%.
- Byte-drift check, every slice from PR3 on:
  `git diff --stat origin/develop -- tests/Fixtures/Conversation/prompts` must print nothing.
- OpenAPI (PR3 and PR8, where a controller or DTO changes):
  `DB_CONNECTION=pgsql DB_HOST=127.0.0.1 DB_PORT=5432 DB_DATABASE=beai_test DB_USERNAME=postgres DB_PASSWORD=postgres DB_URL= php artisan scramble:export`
  followed by `git diff --stat -- openapi.json openapi.v1.json`, expected empty.
- Migrations (PR3, PR5, PR7): `php artisan migrate`, `php artisan migrate:rollback`, `php artisan migrate`.

---

## PR0 - SDD amendment (wrapper, documentation only)

Branch `feature/db-driven-prompts-sdd` in the wrapper, files under `openspec/changes/db-driven-conversation-prompts/`
only. Three commits: proposal and design; spec deltas; tasks.

- [x] PR0.1 Rewrite `proposal.md` to the rescoped plan (status, intent, scope, approach, risks, rollback, owner defaults).
- [x] PR0.2 Add "Amendments 2026-10-08" to `design.md` (eleven corrections, new decisions, verification notes) and mark every superseded decision, table and diagram of the 2026-09-11 text.
- [x] PR0.3 Rewrite the three spec deltas to the new reality (`prompt_set` naming, code-keyed overrides, 31 fragments, contract, hard failure, break-glass, immutability, seal, stamp, byte identity).
- [x] PR0.4 Replace `tasks.md` with these chained slices.
- [x] PR0.5 Verify: a search of this folder for the banned placeholder phrases finds nothing introduced by PR0; `git status --short` is clean in the worktree.

---

## PR1 - Unit golden harness (about 250 lines; fixtures generated)

Branch `feature/db-driven-prompts-pr1-unit-golden`. Captured on the PRE-change tree. Focused test: `SystemPromptGoldenTest`.

- [ ] PR1.1 RED: `tests/Unit/C8/SystemPromptGoldenTest.php` and `tests/Support/PromptGolden.php` (a class; PSR-4 `Tests\Support`, no `composer.json` change) for cases G01 to G17 of design N-11, calling `compose()` directly with a fixed competency code and three indicators in `en` and `it`. Observe it fail: no fixture exists.
- [ ] PR1.2 RED: harness self-tests. Mutating one byte of a copied fixture makes the comparison fail; capture mode refuses to overwrite an existing fixture; the pinned directory hash constant rejects an added, removed or changed file.
- [ ] PR1.3 GREEN: on the untouched composer, run once `PROMPT_GOLDEN_CAPTURE=1 php artisan test --filter=SystemPromptGoldenTest` to write `tests/Fixtures/Conversation/prompts/Gxx.txt` (raw bytes) and `manifest.json` (sha256, byte length, source commit). There is no update mode.
- [ ] PR1.4 GREEN: pin the SHA-256 of the whole fixtures directory as a constant; rerun without the flag: green, zero diff.
- [ ] PR1.5 Confirm G07 uses the `StandardPromptCharacterizationTest` inputs and that test (4323 bytes for `it`) stays green and untouched as a second pin.
- [ ] PR1.6 Docblock: the goldens are characterization tests (green when captured), capture never overwrites, and any later diff under `tests/Fixtures/Conversation/prompts/` is byte drift to be rejected in review.
- [ ] PR1.7 Verify: focused test, `StandardPromptCharacterizationTest`, `SystemPromptComposerTest`, Pint, PHPStan.

## PR2 - HTTP golden (about 170 lines; fixtures generated)

Branch `feature/db-driven-prompts-pr2-http-golden`. Focused test: `InterviewStartPromptGoldenTest`. This is the LAST slice
allowed to change the fixtures directory (it re-pins the directory hash).

- [ ] PR2.1 RED: `tests/Feature/C8/InterviewStartPromptGoldenTest.php` capturing the `prompt` field of the provider `/contexts` call (helper pattern of `EndPhraseInPromptTest`): H1 standard `en` fresh; H2 standard `it` resume; H3 `potential` `it` on the last competency (final phrase, not the intermediate one). Fails: no fixture.
- [ ] PR2.2 GREEN: capture `H01.txt` to `H03.txt` and extend `manifest.json` with the same capture-refuses-overwrite tool; re-pin the directory hash constant.
- [ ] PR2.3 Verify: `EndPhraseInPromptTest`, `InterviewStartCompositionTest`, `SystemPromptGoldenTest`, the full C8 and C9 directories, Pint, PHPStan.

## PR3 - Durable stamp (about 150 lines)

Branch `feature/db-driven-prompts-pr3-stamp`. Focused tests: `InterviewSessionLlmSnapshotResumeTest`, `ExposureTest`.

- [ ] PR3.1 RED: extend `tests/Feature/C7a/InterviewSessionLlmSnapshotResumeTest.php`: after `/start` the session's `conversation_prompt_version` equals the config string; a resume does not change it; `stamp()` with no version never overwrites a stamp; a re-offered competency (`ResetSessionForRetry`) keeps its first stamp. Fails: column absent.
- [ ] PR3.2 GREEN: migration adding `interview_sessions.conversation_prompt_version varchar(255) NULL`.
- [ ] PR3.3 GREEN: `InterviewSessionLlmSnapshot::stamp(InterviewSession, ?string $systemPrompt, ?string $promptVersion)`, write-once and never from null; pass `$ctx->promptVersion` at both call sites in `InterviewController` (about l.1216 and l.1292). Update the `InterviewSession` property annotation and the `stamp()` docblock table.
- [ ] PR3.4 Verify the column is not exposed: `ExposureTest` (T-EXPOSE-001) passes with `ExposureCatalogue` unedited, and no admin or public resource serialises the column.
- [ ] PR3.5 Verify: migrate, rollback, migrate; scramble export diff empty; byte-drift check empty; Pint, PHPStan.

## PR4a - Fragment vocabulary, nothing wired (about 300 lines)

Branch `feature/db-driven-prompts-pr4a-vocabulary`. Focused tests: `PromptFragmentKeyTest`, `PromptTemplateSetTest`, `PromptFragmentContractTest`.

- [ ] PR4a.1 RED: `PromptFragmentKeyTest`: exactly 31 cases with the exact dotted values of design N-1. Fails: enum absent.
- [ ] PR4a.2 GREEN: `app/Enums/PromptFragmentKey.php`.
- [ ] PR4a.3 RED: `PromptTemplateSetTest`: `render()` is a single `strtr` pass; a value containing `{{budget}}` renders literally; a missing token argument and an unknown token argument both throw.
- [ ] PR4a.4 GREEN: `app/DTOs/Conversation/PromptTemplateSet.php` (immutable; fragment map, set id, label, seal, optional override; `render(PromptFragmentKey, array $tokens)`).
- [ ] PR4a.5 RED: `PromptFragmentContractTest`: the required-token table of the spec, no unknown `{{x}}`, no stray `{{` or `}}`, no leading or trailing whitespace, override body with any placeholder refused, one assertion per rule and key family.
- [ ] PR4a.6 GREEN: `app/Support/Conversation/PromptFragmentContract.php` (validates templates only).
- [ ] PR4a.7 Verify: focused tests, Pint, PHPStan; nothing imported by the composer or the controller (a search confirms it).

## PR4b - Composer reads fragments (about 380 lines; split 4b-i / 4b-ii if over 400)

Branch `feature/db-driven-prompts-pr4b-composer` (or `...-4b-i-...` and `...-4b-ii-...`). Focused tests:
`SystemPromptGoldenTest`, `SystemPromptComposerTest`, `PromptFragmentCoverageTest`. Gate: PR1 and PR2 goldens.

- [ ] PR4b.1 GREEN: `app/Support/Conversation/BaselinePromptFragments.php`, today's literals moved verbatim (trimmed bodies, `{{token}}` placeholders; the `it` map is the `en` map). Joins, numbering, branch selection, the clamp and the coverage line format stay in the composer.
- [ ] PR4b.2 RED: `tests/Unit/C8/PromptFragmentCoverageTest.php` with a recording `PromptTemplateSet` double: across G01 to G17 every key except `label.override` is rendered at least once. Fails: the composer does not read `$templates`.
- [ ] PR4b.3 RED: a provided set whose `advance.with_phrase` lacks `{{advance_phrase}}` makes `compose()` throw `CompositionException` (the composition-time half of the contract).
- [ ] PR4b.4 GREEN (4b-i): `compose(..., ?int $revisionId = null, ?PromptTemplateSet $templates = null)`; `null` builds the baseline set; `header`, the labels, `star`, `budget`, `nudge` and the five `advance.*` fragments are read through `render()`. The raw budget is substituted, never inflated.
- [ ] PR4b.5 GREEN (4b-ii): the seven `opening.*` and seven `primary.*` fragments, with their branch selection unchanged.
- [ ] PR4b.6 GATE: `SystemPromptGoldenTest` (G01 to G17), `InterviewStartPromptGoldenTest` (H1 to H3), `StandardPromptCharacterizationTest`, `SystemPromptComposerTest`, `EndPhraseInPromptTest`, `tests/Unit/C8` and `tests/Feature/C9` all green with no assertion edited; byte-drift check empty. A red golden is byte drift: fix the code, never the fixture.
- [ ] PR4b.7 Verify: full suite, Pint, PHPStan, coverage on the composer.

## PR5 - Schema (about 380 lines)

Branch `feature/db-driven-prompts-pr5-schema`. Focused tests: `ConversationPromptSchemaTest`, `ConversationPromptImmutabilityTest`, `TenantModelArchTest`.

- [ ] PR5.1 RED: `tests/Feature/Database/ConversationPromptSchemaTest.php` using `assertPostgresConstraintViolation()`: a second `is_active = true` set raises `23505` on `conversation_prompt_sets_one_active`; a duplicate (set, key, locale) fragment raises `23505`; a duplicate role-specific override and a duplicate role-less override each raise `23505` on their own index; a malformed `content_sha256` raises `23514`. Fails: tables absent.
- [ ] PR5.2 GREEN: migrations for `conversation_prompt_sets`, `conversation_prompt_fragments`, `conversation_prompt_overrides` (design N-3), with the partial indexes and `restrictOnDelete` foreign keys.
- [ ] PR5.3 RED: `ConversationPromptImmutabilityTest`: UPDATE and DELETE on a fragment and on an override raise `23514` naming the table; an UPDATE of a set's `label` or `content_sha256` is refused; an UPDATE of only `is_active`, `activated_at` or `updated_at` succeeds; deleting a set that has fragments raises `23503`.
- [ ] PR5.4 GREEN: trigger migration (`CREATE OR REPLACE FUNCTION`, `ERRCODE = '23514'`, `down()` drops the triggers and the function), following `2026_09_15_201434_enforce_catalogue_published_content_immutability.php`.
- [ ] PR5.5 GREEN: three global Eloquent models; add them to the `$excluded` list of `tests/Arch/C2/TenantModelArchTest.php`; a test asserts none of the three tables has an `organization_id` column.
- [ ] PR5.6 Mutation proof: drop one trigger in a scratch run and observe its test fail, then restore.
- [ ] PR5.7 Verify: migrate, rollback, migrate; focused tests; arch tests; Pint, PHPStan; byte-drift check empty.

## PR6a - Read side (about 300 lines)

Branch `feature/db-driven-prompts-pr6a-resolver`. Focused tests: `PromptSetSealTest`, `PromptSetResolverTest`.

- [ ] PR6a.1 RED: `PromptSetSealTest`: a known-answer hash for a tiny payload; independence from input order; fragments and overrides both change the hash; NULL role sorts first.
- [ ] PR6a.2 GREEN: `app/Support/Conversation/PromptSetSeal.php` (canonical JSON, `JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR`).
- [ ] PR6a.3 RED: `PromptSetResolverTest`: no active set, a missing key, an unknown key, a missing locale and a tampered hash (trigger disabled inside the test transaction) each throw `PromptTemplateUnresolvableException`; a role-specific override beats a role-less one; a `potential` call (null role) resolves only role-less rows; no override resolves to null; activating another set is seen by the next resolution with no cache flush.
- [ ] PR6a.4 GREEN: `app/Exceptions/Conversation/PromptTemplateUnresolvableException.php extends CompositionException`; `app/Services/Conversation/PromptSetResolver.php::resolveActive(locale, competencyCode, roleCode)`: one query for the active set, completeness against `PromptFragmentKey::cases()`, locale check, contract validation, seal recomputed on cache fill, cache by (set id, locale) with no TTL and no invalidation.
- [ ] PR6a.5 Verify: focused tests, Pint, PHPStan; nothing wired into the controller (a search confirms it).

## PR6b - Write side (about 300 lines)

Branch `feature/db-driven-prompts-pr6b-publish-activate`. Focused tests: `PublishPromptSetTest`, `ActivatePromptSetTest`, `PromptSetCommandsTest`.

- [ ] PR6b.1 RED: `PublishPromptSetTest`: `advance.with_phrase` without `{{advance_phrase}}` is refused; a missing key, an unknown key and an override with a placeholder are refused; a refusal persists nothing; a valid payload inserts the set, its fragments, its overrides and a seal equal to `PromptSetSeal` in one transaction.
- [ ] PR6b.2 GREEN: `app/Actions/Conversation/PublishPromptSet.php` (validate, compute the seal from the validated payload, then insert the set with the seal and its children; the seal is never updated afterwards).
- [ ] PR6b.3 RED: `ActivatePromptSetTest`: activation swaps the active set and sets `activated_at`; a failure after the deactivation rolls the whole transaction back and leaves the incumbent active; activating an unknown set fails without side effects.
- [ ] PR6b.4 GREEN: `app/Actions/Conversation/ActivatePromptSet.php` (deactivate the incumbent, then activate; one transaction; the index is not deferrable).
- [ ] PR6b.5 RED then GREEN: `beai:prompt-set:publish --file=<json>` and `beai:prompt-set:activate <label>` exit non-zero with no side effects on invalid input and zero on success. The JSON shape is `{label, notes, fragments: {locale: {key: body}}, overrides: [{role_code, competency_code, locale, body}]}`.
- [ ] PR6b.6 Verify: focused tests, the whole `tests/Feature/Database` directory, Pint, PHPStan.

## PR7 - Bootstrap data (about 300 lines; generated JSON excluded)

Branch `feature/db-driven-prompts-pr7-bootstrap`. Focused tests: `DumpBaselineCommandTest`, `BaselinePromptSetMigrationTest`.

- [ ] PR7.1 RED: `DumpBaselineCommandTest`: `beai:prompt-set:dump-baseline` writes a JSON file that equals `BaselinePromptFragments` for `en` and `it` (the `it` map equal to the `en` map) in the publish format.
- [ ] PR7.2 GREEN: the command, and the generated `database/prompt-sets/<label>.json` committed (generated; size stated in the PR).
- [ ] PR7.3 RED: `BaselinePromptSetMigrationTest`: after `migrate` the baseline set is active, complete for `en` and `it`, equal to `BaselinePromptFragments`, and its stored seal verifies; running the migration logic again writes nothing and verifies the seal; the hash algorithm frozen inline in the migration equals `PromptSetSeal`.
- [ ] PR7.4 GREEN: one data migration with inline `DB::table` code (precedent `2026_09_15_090004_backfill_baseline_revision.php`), idempotent keyed on the unique label, inserting set, fragments and seal, then activating. Its `down()` removes nothing (the triggers forbid it; the schema migration's `down()` drops the tables).
- [ ] PR7.5 Verify: migrate, rollback, migrate on a clean database; every test database now has an active set, so run the full suite; byte-drift check empty; Pint, PHPStan.

## PR8 - Cut-over, isolated (about 320 lines)

Branch `feature/db-driven-prompts-pr8-cutover`. Focused tests: `PromptCutoverTest`, `DeployCommandTest`, then the full suite.

- [ ] PR8.1 RED: a test publishes and activates a set whose `budget` fragment is distinguishable and asserts the `/start` prompt contains it (proves the database path is live). Fails: the controller still composes from the baseline.
- [ ] PR8.2 RED: with no active set `/start` answers 422 `composition_error`, creates no `InterviewSession` row and issues no new provider session; a missing locale and a tampered seal do the same; the existing `ResumeCompositionFailureTeardownTest` still passes (outgoing session released once).
- [ ] PR8.3 RED: activating a second set does not alter an already-composed session's stamp; the stamp matches `{config}+s{id}.{sha12}`; `question_context.prompt_version` stays the bare config string.
- [ ] PR8.4 RED: `CONVERSATION_PROMPT_SOURCE=baseline` composes the baseline text and stamps the bare config string; any other value fails composition with 422.
- [ ] PR8.5 GREEN: `config('conversation.prompt_source')` (`db` | `baseline`, default `db`); `composePromptForCompetency()` resolves the set inside its existing `try` (so the existing `catch (CompositionException)` answers 422); `ComposedPrompt` and `QuestionContext` gain a trailing nullable `promptSetRef`; the controller builds the stamp and passes it to `stamp()`; no OpenAPI change.
- [ ] PR8.6 RED then GREEN: `DeployCommand` fails the deploy fatally when no active set exists or its seal does not verify (`DeployCommandTest`).
- [ ] PR8.7 GREEN: rewrite the `conversation.prompt_version` docblock (it no longer needs a bump for fragment text; it still versions PHP structure and `OpeningTextComposer`).
- [ ] PR8.8 GATE: all goldens (G01 to G17, H1 to H3) pass against the database-resolved baseline set with the fixtures directory unchanged; `tests/Feature/C9` and `tests/Unit/C8` green; full `php artisan test --parallel`; scramble export diff empty; Pint, PHPStan, coverage (about 95% on the composition path).
- [ ] PR8.9 Record in the PR which test files hit `/start` and needed the bootstrap set (the planning notes estimated about 46; a search found 37 files containing the literal route).

## PR9 - Overrides (about 250 lines)

Branch `feature/db-driven-prompts-pr9-overrides`. Focused tests: `PromptOverrideRenderingTest`, `PromptOverrideStartTest`.

- [ ] PR9.1 RED: `tests/Unit/C8/PromptOverrideRenderingTest.php`: an override renders after COVERAGE TOPICS and before the STAR protocol, headed by `label.override`, and changes nothing else; no override means output equal to the golden fixture; with an override the text from `ADVANCE RULE:` to the end is byte-identical; a role-specific override does not apply to another role; when both exist only the role-specific body appears.
- [ ] PR9.2 GREEN: wire `label.override` and the override section into `assemblePrompt()`; the resolver already returns at most one override; the body has no placeholders.
- [ ] PR9.3 RED then GREEN: `PublishPromptSet` accepts overrides and the seal covers them; `/start` for a competency with an override composes it, and the stamp names the first set.
- [ ] PR9.4 Verify: goldens unchanged (no competency ships an override), full suite, Pint, PHPStan, coverage.

---

## After PR9 (not slices)

- [ ] AFTER.1 Archive this change with the SDD archive flow: merge the three deltas into `openspec/specs/` (`conversation-prompt-templates` new; `interview-conversation` and `framework-catalog` modified).
- [ ] AFTER.2 Bump the wrapper's `api` pointer and run the Git Flow release only on explicit request; no deploy otherwise.
- [ ] AFTER.3 After a soak, one cleanup PR deletes the baseline PHP and the break-glass flag; the tests then compose from the migrated set.
