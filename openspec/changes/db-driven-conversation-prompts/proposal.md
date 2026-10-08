# Proposal: Database-Driven Conversation Prompts

> **STATUS (2026-10-08): RESCOPED, READY FOR APPLY.** Rewritten against `develop` (wrapper `321db94`; api
> `origin/develop` `e215c43`, whose `SystemPromptComposer` is byte-identical to the one pinned by the wrapper).
> Nothing is implemented yet: no `conversation_prompt_*` table, resolver or golden test exists. The 2026-09-11 version
> of this change was stale in eleven places, listed with evidence in `design.md` (section "Amendments 2026-10-08");
> the old design is kept below that section as history, with every superseded decision marked. This change is a
> living SDD change delivered as ten numbered slices, twelve PRs because PR4 and PR6 are each split in two (PR0 to PR9, see `tasks.md`); PR0 is this documentation slice.

## Intent

The competency-agnostic half of the interviewer system prompt is hardcoded PHP inside `SystemPromptComposer`
(a nowdoc, string concatenations and `match` arms). Changing one word of how the avatar conducts an interview is a
code change, a review and a release, so the fastest lever on interview quality is the slowest thing in the product to
move.

There is also no way to say anything per competency. `framework_bars_indicators` says WHAT to assess (indicator and
anchors), never HOW to probe it. A competency that needs a specific instruction ("for INN, insist on what was
abandoned") has nowhere to put it.

Success: the prompt text is data, loaded verbatim from today's PHP, publishable and activatable without a deploy,
layerable per role and competency, and every interview records durably which prompt set composed it. A one-byte
drift in the live prompt changes avatar behaviour and scoring inputs, so byte identity through the move is the
change's gate, not a nicety.

## Scope

### In scope

1. **Durable stamp, shipped before any stored data is read (PR3).** `interview_sessions.conversation_prompt_version`
   (nullable `varchar(255)`), written once through `InterviewSessionLlmSnapshot::stamp()` at its two call sites.
   Nothing else in this change is traceable without it, and it has no dependency on the rest.
2. **Byte-identity goldens, captured on the pre-change tree** before any text moves: 17 composer cases through
   `compose()` directly and 3 HTTP cases through `POST /api/candidate/interview/start`.
3. **A fragment vocabulary** of 31 leaf keys (`PromptFragmentKey`), a `{{token}}` placeholder contract, and a
   single-pass renderer. Branch selection, the minimum clamp, joins, numbering and the coverage line format stay in
   PHP; only prose moves.
4. **The composer reads fragments** through a trailing nullable `?PromptTemplateSet $templates = null`; `null`
   means the baseline literals (which become `BaselinePromptFragments`, moved verbatim).
5. **Three global tables** with the naming `prompt_set` everywhere: `conversation_prompt_sets`,
   `conversation_prompt_fragments`, `conversation_prompt_overrides`; a Postgres immutability trigger and a SHA-256
   content seal verified by the resolver.
6. **Resolver, publish and activate.** `PromptSetResolver`, `PublishPromptSet`, `ActivatePromptSet`, and the artisan
   commands `beai:prompt-set:publish` and `beai:prompt-set:activate`.
7. **Bootstrap by data migration.** One migration inserts and activates the baseline set (also giving every
   `RefreshDatabase` test database an active set). Production never runs `DatabaseSeeder`; `beai:deploy` runs
   migrations plus a few explicitly named seeders.
8. **Cut-over, isolated.** `/start` resolves the active set inside the existing `try` of
   `composePromptForCompetency()`. A missing or unusable active set is a hard failure: the existing 422
   `composition_error`, no new API code, no OpenAPI change. A break-glass switch
   `CONVERSATION_PROMPT_SOURCE=baseline` recomposes from the baseline PHP without a code revert.
9. **Per-role and per-competency overrides, keyed by CODE** (`role_code` nullable, `competency_code`), APPEND-only,
   rendered after COVERAGE TOPICS and before the STAR protocol.
10. Spec deltas for `conversation-prompt-templates` (new), `interview-conversation` and `framework-catalog`;
    Pint, PHPStan and coverage as usual (about 95% on the composition path).

### Out of scope

- `framework_bars_indicators`: already database-driven and untouched.
- `api/lang/{en,it}/interview.php`: `end_phrase` and `final_phrase` are the frontend's sole source for
  `matchesEndPhrase()`; moving them is a three-repo change around a live completion-detection contract.
  `OpeningTextComposer` keeps its own anti-leak guarantee and is untouched.
- **Italian re-authoring.** The composer emits English interviewer directives for every locale by documented
  decision (`interview-conversation`, requirement "i18n - Composed Prompt in Project Language"). The `it` fragment
  rows are verbatim copies of the `en` rows. Localising the directives is a later, deliberate change that must
  localise them as a set.
- Backoffice authoring UI (publishing is console-only in this change), per-tenant prompt sets, REPLACE-mode
  overrides, an activation ledger or any use of `audit_logs` (a platform audit capability is its own change).
- `PromptBuilder` and scoring: untouched. Fixing the pre-existing gap that `framework_bars_indicators` carries no
  framework version (ruling 3 is weaker in schema than in prose) is its own change.
- Pinning a prompt set to a participant across competencies (see "Owner defaults taken").

## Capabilities

### New Capabilities

- `conversation-prompt-templates`: global, immutable, locale-keyed prompt sets of 31 fragments, per-code overrides,
  the placeholder contract, resolution, activation, the hash seal and bootstrap.

### Modified Capabilities

- `interview-conversation`: "System-Prompt Composition - Pure Function" takes a passed-in fragment set;
  "QuestionContext Carries Composed Prompt" carries a separate prompt-set reference; new requirements for byte
  identity, the placeholder contract at composition, hard failure, the break-glass source and the durable stamp.
- `framework-catalog`: records that prompt overrides are keyed by role and competency CODE and therefore do not
  depend on, copy with, or invalidate a catalogue revision.

## Approach

**One composition, two layers.** Layer 1 is the global prompt set: one row per (`prompt_set`, `fragment_key`,
`locale`). Layer 2 is the optional override: one row per (`prompt_set`, `role_code`, `competency_code`, `locale`),
role OPTIONAL. APPEND-only was chosen over REPLACE because a row able to replace an advance fragment can delete a
safety invariant per competency, which is the failure mode below.

**The composer stays pure.** `InterviewController::composePromptForCompetency()` (the ONLY caller of `compose()`;
`RunMockInterviewJob` does not compose) resolves a `PromptTemplateSet` value object and passes it as the trailing
nullable argument. Injecting a repository into the composer was rejected: its purity is an asserted correctness
invariant.

**Naming.** "Revision" already means `FrameworkCatalogRevision` in this repository, and catalogue roles and
competencies are cloned per revision with new ids (`OpenDraftRevision`). Everything here is a `prompt_set`, and
overrides are keyed by code, never by foreign-key id.

**Placeholders.** Delimiter `{{token}}`, rendered by one `strtr()` pass, so a value that itself contains `{{budget}}`
(an operator question, an advance phrase) is rendered literally. The contract validates TEMPLATES (required tokens
present, no unknown `{{x}}`, no stray `{{`) at publish and again at composition. There is no post-interpolation
sweep: it would reject legitimate operator text such as a primary question containing `:budget` or `Re:think`.

**Versioning.** `ComposedPrompt::version` stays the `conversation.prompt_version` config string: it is returned to
the client as `question_context.prompt_version` and `OpeningTextComposer` stamps the same string. The prompt-set
reference travels separately, and the durable stamp becomes `{config}+s{set id}.{sha12}` at cut-over (PR8); until
then it stores today's config string. A set is immutable (trigger plus seal), so a stamp names exact bytes.

**Activation.** `is_active` on the set (partial unique index, the `avatar_templates` idiom), one transaction that
deactivates the incumbent then activates the new set. This replaces the config-pointer alternative floated in the
2026-09-11 proposal.

**Rollout order.** Stamp (PR3), goldens (PR1, PR2) and vocabulary (PR4a) change nothing observable; the composer
refactor (PR4b) is gated by the goldens; schema, resolver and bootstrap (PR5 to PR7) are additive and nothing reads
them; PR8 is the only slice that changes what the live system does.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `api/database/migrations/` | New | Stamp column; three tables, triggers, partial indexes; bootstrap data migration |
| `api/app/Enums/PromptFragmentKey.php` | New | The 31 keys |
| `api/app/DTOs/Conversation/PromptTemplateSet.php` | New | Immutable value object; `render()` |
| `api/app/Support/Conversation/` | New | `PromptFragmentContract`, `PromptSetSeal`, `BaselinePromptFragments` |
| `api/app/Services/Conversation/SystemPromptComposer.php` | Modified | Builders read `$templates`; trailing nullable parameter |
| `api/app/Services/Conversation/PromptSetResolver.php` | New | Active-set read, completeness, hash check, cache |
| `api/app/Actions/Conversation/` | New | `PublishPromptSet`, `ActivatePromptSet` |
| `api/app/Console/Commands/` | New / Modified | `beai:prompt-set:publish`, `:activate`, `:dump-baseline`; active-set check in `DeployCommand` |
| `api/app/Services/ConversationLlm/InterviewSessionLlmSnapshot.php` | Modified | `stamp()` gains the prompt-version argument |
| `api/app/Http/Controllers/Candidate/InterviewController.php` | Modified | Resolves the set; passes the version to `stamp()` at both call sites |
| `api/app/Models/` | New | Three global models (added to the `$excluded` list of `TenantModelArchTest`) |
| `api/config/conversation.php` | Modified | `prompt_source` switch; corrected `prompt_version` docblock |
| `api/tests/` | New / Modified | Goldens, fixtures, schema, resolver, cut-over and override tests |
| `openspec/specs/{interview-conversation,framework-catalog,conversation-prompt-templates}/` | Modified / New | Delta specs |

## Risks

| Risk | Likelihood | Severity | Mitigation |
|---|---|---|---|
| Live prompt byte drift (whitespace, nowdoc newlines, `implode("\n")` joins, the em dash, the 6-space STAR indent) silently changes avatar behaviour and scoring inputs | High | Critical | PR1 and PR2 goldens captured on the pre-change tree, fixtures pinned by a directory hash, capture refuses to overwrite; the existing `StandardPromptCharacterizationTest` (4323 bytes for `it`) stays as a second pin; from PR3 on CI asserts the fixtures directory is unchanged against `origin/develop` |
| The `end_phrase` defect returns: an editable advance fragment omits the closing phrase, the avatar never speaks it, `matchesEndPhrase()` never matches and the session dies with `MAX_DURATION_REACHED` (this has already shipped once) | Medium | Critical | Required tokens enforced at publish AND at composition; `EndPhraseInPromptTest` stays green; the composed text never contains the literal `end_phrase`; G02, G03 and G13 assert the quoted phrase and the floor |
| Avatar behaviour at the last competency: the final phrase must not be replaced by the intermediate one | Medium | High | Fragment-coverage assertion across G01 to G17 and the HTTP case H3 (final versus intermediate phrase) |
| A tampered or half-published set reaches a live interview | Low | Critical | Immutability trigger plus SHA-256 seal recomputed by the resolver on cache fill; completeness check against `PromptFragmentKey::cases()` (missing OR unknown key throws) |
| No active set in an environment (fresh database, wiped table) turns every `/start` into a 422 | Medium | High | Bootstrap data migration; fatal active-set check in `DeployCommand`; break-glass `CONVERSATION_PROMPT_SOURCE=baseline` |
| Tests or environments that reset the database outside `RefreshDatabase` lose the migrated set | Low | Medium | PR8 runs the full suite to expose them; the answer is an idempotent re-run of the bootstrap logic, never a seeder |
| Hot-path cost on `/start` | Low | Low | One indexed query for the active set; fragments cached by (set id, locale) with no invalidation, since a set is immutable |
| A set activated mid-interview yields a mixed record | Certain | Low | Accepted and documented: the stamp holds the FIRST set composed for the session |
| Scoring inputs change | Low | High | `PromptBuilder` untouched; `tests/Feature/C9` and `tests/Unit/C8` run in PR8 |

## Rollback Plan

- **PR1 to PR7:** revert the PR. All additive; nothing reads the new data; the stamp column is nullable.
- **PR8:** set `CONVERSATION_PROMPT_SOURCE=baseline`. The API recomposes from the baseline PHP without a code revert
  (the stamp then carries the bare config string, so the source of every interview stays distinguishable).
- **PR9:** revert the PR; overrides are optional and none ships by default.
- The baseline PHP stays for one release as the seed source, the test default and the break-glass target, and is
  deleted in a later cleanup PR after a soak. No interview, transcript or evaluation data is rewritten; no
  re-scoring.

## Dependencies

- None external. `framework_roles`, `framework_competencies` and `framework_bars_indicators` are not modified.
- The Italian fragment rows need no human author: they are verbatim copies of `en` (see "Out of scope"). This
  retires the old human-blocking task 4.2.

## Success Criteria

- [ ] Every golden (G01 to G17 and H1 to H3) passes against the database-resolved set with ZERO diff to the
      fixtures directory, and the pinned directory hash is unchanged.
- [ ] `SystemPromptComposerTest`, `StandardPromptCharacterizationTest` and `EndPhraseInPromptTest` pass without any
      assertion weakened.
- [ ] A fragment missing a required token is refused at publish AND at composition; a test proves both.
- [ ] All 31 keys except `label.override` are rendered across G01 to G17 (recording `PromptTemplateSet` double).
- [ ] An UPDATE or DELETE on a fragment or override, and any UPDATE of a set other than its activation columns, is
      refused by the database; two active sets, a duplicate fragment and a duplicate override each raise `23505`.
- [ ] No active set, a missing or unknown key, a missing locale or a tampered hash each make `/start` answer 422
      `composition_error` with no `InterviewSession` row created and no new provider session issued.
- [ ] Activating a new set does not alter an already-stamped session; the stamp holds the first set.
- [ ] `CONVERSATION_PROMPT_SOURCE=baseline` composes the baseline text and stamps the bare config string.
- [ ] With no override the prompt is byte-identical; with one, only the override section differs and the ADVANCE
      RULE bytes are unchanged.
- [ ] Coverage at least 85% overall, about 95% on the composition path; Pint and PHPStan clean; each slice at most
      about 400 authored changed lines (generated fixtures and JSON excluded and stated).

## Owner defaults taken (2026-10-08)

Taken on the owner's behalf because they preserve today's behaviour and are reversible by a later change; reopen any
of them by amending this section.

1. **English instructions for every locale, byte-identical.** `it` fragment rows are verbatim copies of `en`. The
   composer emits English directives today and `StandardPromptCharacterizationTest` pins the `it` output.
2. **A new set takes effect at the next `/start` or resume.** A switch in the middle of an interview is a
   documented mixed record; the stamp holds the first set composed for the session, overrides included.
3. **Overrides ship (PR9); no activation ledger.** `activated_at` on the set plus the per-session stamp are the
   activation trail. Who activated a set is deliberately not recorded; a platform audit capability, if ever built, is
   its own change.
