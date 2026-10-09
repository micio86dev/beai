# Archive Report: db-driven-conversation-prompts

**Change**: db-driven-conversation-prompts
**Archived to**: `openspec/changes/archive/2026-10-09-db-driven-conversation-prompts/`
**Archive date**: 2026-10-09
**Status**: CLOSED, with deferred items. Every slice of the plan (PR0 to PR9) is merged into the api `develop` branch,
plus one slice that was not in the plan (api #155, the 32nd fragment key). The release, the deploy and the cleanup PR
that deletes the baseline PHP are NOT done (see "Deferred and open items"). `tasks.md` has 71 boxes ticked and 2
unticked (AFTER.2 and AFTER.3). No verify-report existed; verification was not run as an SDD phase, and this archive
did not run any test suite: the evidence below is the pull request descriptions, the source and test files on api
`origin/develop` `cf1d82a`, and the CI result of each pull request.

## Summary

The competency-agnostic half of the interviewer system prompt used to be hardcoded PHP in `SystemPromptComposer`. It is
now data: global, immutable, sealed prompt sets (`conversation_prompt_sets`, `conversation_prompt_fragments`,
`conversation_prompt_overrides`), published and activated from the console, resolved at `/start`, with per-competency
overrides, a durable per-session stamp, a hard failure with no fallback, a break-glass source flag and a deploy gate.
The composed bytes did not change: 20 composer goldens and 4 HTTP goldens pin them and pass on both sources.

## Delivered (api repository `micio86dev/backend`, merged into `develop`)

PR numbers and merge commits were read from `gh pr view` and `git log --merges origin/develop` on 2026-10-09; every
sha below exists. The `Lint · Analyse · Test · OpenAPI · Docker` check concluded `SUCCESS` on every pull request.

| Slice | api PR | Merge commit | What |
|---|---|---|---|
| PR0 (wrapper) | wrapper #90 | `852ec65` | rescoped proposal, design, spec deltas and tasks |
| PR1 + PR2 | #146 | `c494d31` | unit golden G01 to G17, HTTP golden H1 to H3, `PromptGolden` capture helper that refuses to overwrite, pinned directory hash |
| PR3 | #147 | `77150ca` | `interview_sessions.conversation_prompt_version` (nullable, write-once through `InterviewSessionLlmSnapshot::stamp()`) |
| PR4a | #148 | `203e673` | `PromptFragmentKey`, `PromptTemplateSet`, `PromptFragmentContract`; nothing wired |
| PR4b-i | #149 | `396c34d` | `BaselinePromptFragments`; the composer reads the static sections from a template set; `compose(..., ?PromptTemplateSet $templates = null)` |
| PR4b-ii | #150 | `37e5b7f` | the opening and primary-question sections read from a template set |
| PR5 | #151 | `291a20b` | the three global tables, partial unique indexes, immutability triggers, global models |
| PR6a | #152 | `f06ef06` | `PromptSetSeal`, `PromptSetResolver`, `PromptTemplateUnresolvableException` |
| PR6b | #153 | `616d465` | `PublishPromptSet`, `ActivatePromptSet`, `beai:prompt-set:publish`, `beai:prompt-set:activate` |
| not a slice | #155 | `2cb0d03` | the 32nd key `opening.continuation` (no second greeting after the first competency); goldens G18, G19, H4 |
| PR7 | #156 | `61aac71` | `beai:prompt-set:dump-baseline`, `database/prompt-sets/baseline-1.json`, data migration `2026_10_09_100000_bootstrap_baseline_conversation_prompt_set` |
| PR8 | #157 | `70def97` | cut-over: `CONVERSATION_PROMPT_SOURCE=db|baseline`, `App\Enums\PromptSource`, stamp `{config}+s{id}.{sha12}`, deploy gate in `beai:deploy` |
| PR9 | #158 | `cf1d82a` | overrides: `compose(..., ?string $override)`, section between COVERAGE TOPICS and STAR, golden G20 |

api #154 (`00f728f`) merged inside the chain and is unrelated. The full mapping and the per-task evidence are in
`tasks.md` ("Delivery record").

## Specs merged

Composition used `gentle-ai sdd-archive-compose` (version 3.7.0, exit 0 for both composed files). The new capability was
copied mechanically with `cp` and read back with `diff` (empty).

| Capability | Requirements before -> after | Delta applied |
|---|---|---|
| conversation-prompt-templates (NEW) | none -> 11 | whole delta copied (`cp`, then `diff`: empty). The delta had been extended during this closure with the delivered behaviour: 32 keys (64 fragment rows), verify-before-activate, ambiguous/duplicate/empty-set failures, publish stores inactive and reads back, dump-baseline never overwrites a differing file, the bootstrap activates only when no set is active and refuses an override-bearing file, and a new requirement "A Deploy Is Refused Without An Intact Active Prompt Set" |
| interview-conversation | 24 -> 31 | 2 MODIFIED ("System-Prompt Composition — Pure Function", "QuestionContext Carries Composed Prompt"), 7 ADDED (byte identity across the move; placeholder contract at composition; an unresolvable prompt set fails with the existing 422; prompt source switch; durable conversation prompt stamp; per-code override at a fixed position; "A Later Competency Does Not Greet Again" for `opening.continuation`) |
| framework-catalog | 17 -> 18 | 1 ADDED (prompt overrides are keyed by role and competency code, not by catalogue row) |

`git diff --stat` of `openspec/specs` before the archive commit: 331 insertions and 19 deletions in the two modified
files, plus the new `conversation-prompt-templates/spec.md`.

Notes for a reviewer:

- The two MODIFIED blocks matched canonical requirement names, so the composer needed no rename workaround. The MODIFIED
  text replaced the old requirement text; the old "(Previously: ...)" paragraph was not kept verbatim, because the
  delta's own "(Previously: ...)" paragraph already folds in the earlier history (the `assessment_type` and
  `follow_up_budget` notes). The old scenario that named `ConversationService::composePrompt()` now names `compose()`.
- The old row `prompt_template_version | config/conversation.php; bumped on any template change` is gone from the input
  table; the delta's `prompt_version` row says the config string is unchanged and returned as
  `question_context.prompt_version`.
- Other specs were not touched. `interview-conversation` still holds "Standard Prompt Is Byte-Identical Across This
  Change" from an earlier change; it is a different requirement from the byte-identity one added here.

## Verification evidence (what was observed, and what was not)

Observed on 2026-10-09:

- Each of the 12 api pull requests is `MERGED`; the merge commits above exist on `origin/develop`; the combined
  `Lint · Analyse · Test · OpenAPI · Docker` check of each PR was `SUCCESS` (from `gh pr view --json statusCheckRollup`).
- The source and test files named in `tasks.md` exist on `origin/develop` `cf1d82a`: the enums, DTOs, services,
  actions, commands, migrations, `baseline-1.json`, `PromptSource`, the 24 golden fixtures plus `manifest.json`, and the
  tests (`SystemPromptGoldenTest`, `InterviewStartPromptGoldenTest`, `SystemPromptComposerTemplatesTest`,
  `ConversationPrompt*Test`, `PromptSetResolverTest`, `PublishPromptSetTest`, `ActivatePromptSetTest`,
  `PromptSetCommandsTest`, `DumpBaselineCommandTest`, `BaselinePromptSetMigrationTest`, `PromptCutoverTest`,
  `DeployCommandTest`, `PromptOverrideRenderingTest`, `PromptOverrideStartTest`).
- `PromptFragmentKey` has 32 cases; `config/conversation.php` defaults `prompt_source` to `db`;
  `DeployCommand::verifyActivePromptSet()` and `SystemPromptComposer::assemblePrompt()` behave as the specs now state
  (read in the source).

Reported by the pull request descriptions and NOT re-observed by this archive: RED before GREEN, the mutation proofs
(for example #149: one changed character in a baseline body turns the goldens red; #157: six proofs; #158: four), the
test counts (#157: 1219 tests, 1218 passed, 1 skipped on the targeted groups; #158: 1277 tests, 1276 passed, 1 skipped),
Pint and PHPStan clean, `scramble:export` diff empty, `ExposureTest` unaffected, and the independent differential
probes of #149 (406 input combinations) and #150 (403,914 cases on the two migrated builders).

Not available:

- The `Lint · Analyse · Test · OpenAPI · Docker` run on `develop` for the merge `cf1d82a` (api #158) was `in_progress`
  when this report was written; its own PR check was green. Earlier merges on `develop` (#155, #156, #157) completed
  `success`.
- No coverage percentage is recorded in any PR description, so the 85% / 95% criterion is not evidenced numerically.
- No live-provider check of the avatar's behaviour is recorded for the continuation clause (#155) or for any stored set.

Native review (receipt-driven development) record, as written in the PR descriptions: #149 ended with the native
lineage answering `stop: corrupted_or_unverifiable_authority`, so no native approval exists for that slice (compensated
by an independent read-only differential review, the golden gate and `gga`); #147 and #150 were assessed medium and under
the review budget, so no native review was due; the other descriptions record no native review outcome.

## Decisions taken (the delivered shape; full detail in `design.md`, "Amendments 2026-10-08" and "Amendments 2026-10-09")

- Everything is a `prompt_set`; "revision" stays reserved for `FrameworkCatalogRevision`. Overrides are keyed by CODE.
- One row per (set, key, locale); 32 fragment keys; a `{{token}}` contract validated on templates only, rendered by one
  `strtr` pass; the `it` rows are verbatim copies of `en`.
- Immutable by trigger (`23514`), sealed by SHA-256, one active set by partial unique index; the resolver recomputes the
  seal over all rows, and the failure reasons are machine-readable.
- Hard failure with no fallback: 422 `composition_error` for an unresolvable set, 500 for an infrastructure failure.
  Break-glass `CONVERSATION_PROMPT_SOURCE=baseline`; the flag defaults to `db` and is validated strictly.
- The durable stamp is `{conversation.prompt_version}+s{id}.{sha12}` (bare config string for `baseline`), write-once,
  holding the FIRST set composed for the session; `question_context.prompt_version` stays the bare config string.
- Baseline label `baseline-1`, a frozen artefact: a changed baseline gets a new label.
- `beai:deploy` refuses to deploy with `db` unless exactly one active set verifies for every supported locale.
- Overrides are APPEND-only, one section between COVERAGE TOPICS and the STAR protocol; a blank or non-UTF-8 body counts
  as no override.

## Deferred and open items

1. **No release and no deploy.** AFTER.2 is NOT DONE: no release was requested. The wrapper still pins api `30a18b6`
   (release 0.68.0), which contains none of this chain. The first release that includes it will run the three schema
   migrations and the bootstrap migration, and `beai:deploy` will then require an intact active set (the bootstrap
   provides `baseline-1`). Nothing was deployed to Railway; production has no stored prompt set yet.
2. **Cleanup PR after a soak (AFTER.3), not done.** `BaselinePromptFragments`, `PromptSource::Baseline` and
   `CONVERSATION_PROMPT_SOURCE=baseline` are still in api `develop`, by design, for one release. A later PR deletes the
   baseline PHP and the flag and makes the tests compose from the migrated set. Until then the baseline PHP and
   `baseline-1.json` are two copies of the same text, kept equal by `DumpBaselineCommandTest` and
   `BaselinePromptSetMigrationTest`.
3. **The `it` fragments are not independently authored.** They are verbatim copies of `en`, because the composer speaks
   English directives in every locale by documented decision. Localising the directives is a future, deliberate change
   that must localise them as a set. Consequence recorded in the specs: a project language other than `en` and `it` is a
   422 on the `db` source, and adding a locale to `app.supported_locales` without publishing its fragments fails the
   deploy.
4. **Overrides are not exposed in the backoffice.** There is no authoring UI and no HTTP route; sets and overrides are
   published from the console (`beai:prompt-set:publish <file>`, then `beai:prompt-set:activate <label>`). No override
   ships by default; none has been published by an operator.
5. **No activation ledger and no audit trail.** `activated_at` on the set plus the per-session stamp are the trail; who
   activated a set is not recorded (owner default 3, unchanged).
6. **Out of scope, unchanged:** per-tenant prompt sets, REPLACE-mode overrides, pinning one set to a participant across
   competencies (a set activated mid-interview yields a documented mixed record whose stamp names the first set),
   `api/lang/{en,it}/interview.php` and `OpeningTextComposer`, and the pre-existing gap that
   `framework_bars_indicators` carries no framework version.
7. **Success criterion left open:** "Coverage at least 85% overall, about 95% on the composition path ... each slice at
   most about 400 authored changed lines". Pint and PHPStan are reported clean and CI is green, but no coverage figure
   and no per-slice size audit exist (reported sizes: PR3 178 lines, PR4b-ii 328).
8. **PR8.9 only partly met:** the PR records that the 37 test files containing the literal `/start` route pass; it does
   not list which of them needed the bootstrap set.
9. **Test-suite follow-ups from the PR descriptions:** `PromptOverrideStartTest` carries its own copies of the cut-over
   helpers (a later cleanup could share them through `tests/Helpers`); the `PromptTables::empty()` helper uses
   `ALTER TABLE ... DISABLE TRIGGER USER`, which needs table ownership (fine for the `postgres` user of `phpunit.xml` and
   CI); the `fr` language-fallback test of `InterviewStartPhrasesTest` now selects the `baseline` source.
10. **Greeting inside an authored question:** the continuation clause (#155) cannot remove a greeting that an operator
    wrote into an authored primary question; only the operator can change that.
11. **Stale statements in other open changes (not edited by this archive):** `tavus-single-session-interview`
    (`proposal.md`, `tasks.md`) still describes F3 as open and as merging first, and `candidate-interview-call-ui`
    (`proposal.md`) mentions this change as a possible home for a fix; both should be read with this report.

## Rollback

- **Runtime, no redeploy of code:** set `CONVERSATION_PROMPT_SOURCE=baseline`. `/start` then composes from the baseline
  PHP with no prompt-set database read, overrides are not printed, the stamp carries the bare config string, and
  `beai:deploy` skips the prompt set check with a warning. Remove the variable (or set `db`) to return to the stored set.
  Any other value fails every `/start` with a 422 and fails the deploy.
- **A bad stored set:** publish a corrected set under a NEW label and activate it (`beai:prompt-set:publish`,
  `beai:prompt-set:activate`); stored sets cannot be edited or deleted. Sessions already composed keep their stamp.
- **Code:** revert the pull request. PR1 to PR7 are additive (the stamp column is nullable and the tables are unread
  until PR8); PR8 is the only slice that changed live behaviour; PR9 is optional because no override ships. The schema
  migrations roll back (`migrate:rollback` drops the tables); the bootstrap migration's `down()` removes nothing
  because the triggers forbid it.
- No interview, transcript or evaluation data was rewritten and nothing was re-scored.

## Ambiguities resolved while archiving

- **Slice numbers versus PR numbers.** The plan's PR1 and PR2 shipped as one api PR (#146); PR4b shipped as two (#149,
  #150); #155 was added. The tasks were ticked by slice, with the PR number on each, and the mapping is in `tasks.md`.
- **"Fixtures directory unchanged".** The pinned directory hash was re-pinned twice (api #155 and #158), by additions
  only (G18, G19, H4, G20). The original 20 fixtures are untouched; the criterion is recorded as met with that note
  rather than as literally unchanged.
- **"Zero provider calls" (#157 description) versus the specs.** The specs keep the narrower guarantee from the design:
  no `InterviewSession` row and no NEW provider session; on resume the outgoing session is released once.
- **Where `PromptFragmentCoverageTest` went.** No file with that name exists; the coverage proof is in
  `SystemPromptComposerTemplatesTest` over a marker template set and its own case matrix (31 consumable keys), not over
  G01 to G17 with a recording double. Recorded as delivered differently, not as missing.
- **The deltas were edited before the merge.** The delta specs were corrected against the code (32 keys, 64 rows, the
  extra failure reasons, the deploy gate, the bootstrap rules, the continuation requirement) in a separate commit before
  composing, so the main specs carry the delivered behaviour. Archived `tasks.md` otherwise retains the bytes of the
  reconciled version; the only edit after the move is the AFTER.1 tick.

## Traceability

Mode openspec. Artifacts read from the filesystem: `proposal.md`, `design.md`, `tasks.md`, three delta specs. Absent:
`apply-progress.md`, `verify-report.md`, `exploration.md`. External evidence: `gh pr view` and `git log` on the api
repository, and the api source and tests on `origin/develop` `cf1d82a`.

## Copy verification

The folder was moved with `git mv` after a recursive snapshot. Verbatim readback, `diff -r <snapshot of the change
folder before the move> openspec/changes/archive/2026-10-09-db-driven-conversation-prompts`: empty output, exit 0. The
new capability spec was copied with `cp` and `diff` printed nothing. This report is additive and was not part of the
comparison. The two composed specs were produced by `gentle-ai sdd-archive-compose` (exit 0 each) through a
`.compose-tmp` file and `mv`.
