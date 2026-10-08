# Delta for Interview Conversation

## MODIFIED Requirements

### Requirement: System-Prompt Composition — Pure Function

The system MUST compose a system-prompt string server-side at `/start` time as a
deterministic, side-effect-free function of the following inputs:

| Input | Source |
|---|---|
| `competency_code` + BARS indicators + anchor texts `{5,3,1}` | `BarsIndicatorLoader` scoped by `role_id` + `competency_id` (for `potential`: `role_id IS NULL` + `competency_id`), pinned `framework_version_id` |
| `assessment_type` | Project configuration (`standard` or `potential`, the `AssessmentType` enum cases) |
| `role_code` / `role_id` | Project configuration (required for `standard`; null by rule for `potential`) |
| `project_language` | Project configuration (`it` / `en` binding) |
| `follow_up_budget` (max N per competency) | Platform config `conversation.followup_budget`; default **N=4**, RATIFIED 2026-08-25 |
| `min_questions` (floor, opening question included) | Platform config `conversation.min_questions`; default 4, CLAMPED by the composer |
| `nudge_min_chars` | `Project.nudge_min_chars` |
| `prompt_version` | `config/conversation.php`; unchanged, returned as `question_context.prompt_version` |
| **fragment set** (31 prose fragments, plus an optional per-code override) | Resolved at the CALL SITE from the active `conversation-prompt-templates` prompt set for `project_language` and passed into `compose()` as an immutable value object; absent (`null`) means the baseline text |

The composition MUST:
- Require NO LLM inference call.
- Perform NO DB, HTTP, time, or random access inside the composer — the fragment set arrives as a
  passed-in value and the composer is a pure function of its arguments.
- Produce identical output for identical inputs (deterministic), including an identical fragment set.
- Emit the `conversation.prompt_version` config string as `ComposedPrompt::version`. The identity of the
  fragment set travels separately (see "Durable Conversation Prompt Stamp") and MUST NOT change `version`.
- Contain NO hardcoded per-tenant text; all anchor text flows from the versioned framework catalog at the pinned `framework_version_id`.
- Select the correct language (it/en binding) for all catalogue-derived text (see the i18n requirement for the exact scope).

Purity is defined as: no LLM call, no HTTP, no time, no randomness, no IO, evaluated ON THE COMPOSER
ITSELF. Template resolution happens at the call site (`InterviewController::composePromptForCompetency()`);
`compose()` receives an already-resolved value object. Reading `config/conversation.php` is NOT a purity
violation — the composer already reads `prompt_version` from it. Branch selection, the clamped minimum,
joins, numbering and the coverage line format remain in code; only prose is stored.

(Previously: the prose was hardcoded in the composer, `prompt_template_version` was a config string
"bumped on any template change", and the requirement said the composer emits "a stable `prompt_version`
string that uniquely identifies the template and its version". The prose is now stored fragments; the
config string keeps its role for PHP structure and for `OpeningTextComposer`; the identity of the stored
fragments is the prompt-set reference. Earlier history, unchanged: `assessment_type` was `standard` only —
C8 and `role_code` / `role_id` was unconditional; `follow_up_budget` was `default N=2 [PROVISIONAL —
OQ-1]` until it was RATIFIED at 4 on 2026-08-25, with a nullable per-project override to follow as
`project-followup-budget`.)

#### Scenario: Deterministic composition — same inputs yield same output

- GIVEN competency PRS, framework version V, role FLL, language `it`, N=2, nudge_min_chars=80, and a fragment set from prompt set S
- WHEN `compose()` is called twice with identical inputs
- THEN both calls return the identical prompt string and the same `prompt_version` value

#### Scenario: Deterministic composition for a role-less potential competency

- GIVEN competency MTG, framework version V, no role, language `en`, N=4, nudge_min_chars=80
- WHEN the prompt is composed twice with identical inputs
- THEN both calls return the identical prompt string and the same `prompt_version` value

#### Scenario: prompt_version is non-null and version-stamped

- GIVEN any valid set of composition inputs
- WHEN the prompt is composed
- THEN `prompt_version` is a non-null, non-empty string equal to the value in `config/conversation.php`, whichever fragment set was used

#### Scenario: Two fragment sets compose different text under the same prompt_version

- GIVEN two prompt sets whose `budget` fragments differ
- WHEN the same inputs are composed against each
- THEN the prompt strings differ and `ComposedPrompt::version` is identical for both

#### Scenario: No LLM call during composition

- GIVEN the composition service is invoked at `/start`
- WHEN `compose()` runs
- THEN no HTTP call is made to any LLM or external provider; the result is produced purely from in-memory fragment and catalog data

#### Scenario: Composer performs no DB, HTTP, time, or random access

- GIVEN the composer's implementation
- WHEN its call graph is inspected
- THEN it contains no query, no HTTP call, no time call, and no random-number call — all fragment content arrives via its parameters

#### Scenario: Composition uses pinned framework_version_id, never live draft

- GIVEN `project.framework_version_id = V` and a newer live catalog draft V+1 exists
- WHEN the prompt is composed
- THEN BARS indicators and anchors are read from version V; no data from V+1 is injected

> **⚠️ KNOWN GAP (pre-existing, deferred — do NOT treat as covered by C8).** This scenario is
> currently **unenforceable**: `framework_bars_indicators` has no `framework_version_id` column,
> and neither the C8 `BarsIndicatorLoader` nor the merged C9 `ScoreEvaluationJob` filters
> indicators by framework version — both scope by `role_id`/`competency_id` only. This is a
> data-model divergence that **predates C8** and cannot be closed here (C8 design forbids a new
> migration, RV-1/RV-4). Closing it requires a dedicated **framework-versioning slice** that adds
> the column + backfill and updates BOTH C8 and C9 loaders under their own tests. Until then this
> scenario is aspirational, not verified.

---

### Requirement: QuestionContext Carries Composed Prompt

The `QuestionContext` DTO MUST carry the composed `system_prompt` and `prompt_version`
as additive fields, and a nullable prompt-set reference (`s{set id}.{sha12}`; null when the baseline text
composed the prompt) that the durable stamp is built from. The extended `QuestionContext` flows through
`ProviderSessionService::issue()` to the provider adapters (HeyGen, Tavus).

The C7a `/start` control flow (create-or-resume, provider-outside-txn, failure matrix)
is UNCHANGED. This is a purely additive widening.

The `/start` response body MUST include `prompt_version` in the `question_context` object
as a non-null, non-empty string (audit and traceability). This field is additive to the
existing `question_context` shape (C7a addendum: `end_phrase`, `final_phrase`). Its value is the
`conversation.prompt_version` config string and does NOT include the prompt-set reference; the response shape
and the OpenAPI contract are unchanged.

(Previously: the requirement carried `system_prompt` and `prompt_version` only. The prompt-set reference is
added so the stamp site can record which set composed the prompt.)

#### Scenario: /start response contains prompt_version

- GIVEN a valid candidate JWT and a project with a configured `standard` competency
- WHEN `POST /api/candidate/interview/start` returns HTTP 201
- THEN `question_context.prompt_version` is a non-null, non-empty string in the response body

#### Scenario: The response prompt_version excludes the prompt-set reference

- GIVEN `/start` composed from a database-resolved prompt set
- WHEN the response is inspected
- THEN `question_context.prompt_version` equals the config string and contains no `+s` suffix

#### Scenario: C7a failure matrix is unchanged after QuestionContext widening

- GIVEN a provider 5xx/timeout hard-failure at `/start`
- WHEN `ProviderSessionService::issue()` is invoked with the extended `QuestionContext`
- THEN the failure matrix (session → error, participant → errore, HTTP 502) behaves identically to pre-C8 behavior

---

## ADDED Requirements

### Requirement: Composed Prompt Is Byte-Identical Across The Move To Stored Fragments

For every input combination covered by the golden set, the prompt composed from the database-resolved baseline prompt
set MUST be byte-for-byte identical to the prompt composed by the pre-change composer. The golden set is: 17
composer-level cases (G01 to G17: budget, nudge and phrase variants, the clamp at 0, authored primaries from 0 to 6,
resumed openings, the fallback opening, a role-less `potential` case with the final phrase, an injection case, and
configured minimums of 99 and -3) and 3 HTTP-level cases (H1 standard `en` fresh, H2 standard `it` resume, H3
`potential` `it` on the last competency). Fixtures MUST be captured once on the pre-change tree, MUST NOT be
overwritten by the capture tool, and MUST be pinned by a directory hash in the test. The harness MUST prove it can
fail: mutating one byte of a fixture makes the comparison fail. Across the cases, every fragment key except
`label.override` MUST be rendered at least once.

#### Scenario: Every golden case matches its fixture

- GIVEN the fixtures captured on the pre-change tree
- WHEN each case is composed against the baseline set (and against the database-resolved baseline set after cut-over)
- THEN the output equals the fixture byte for byte

#### Scenario: A one-byte mutation is detected

- GIVEN a fixture with one byte changed
- WHEN the comparison runs
- THEN it fails

#### Scenario: Capture never overwrites

- GIVEN a fixture already exists
- WHEN capture mode runs
- THEN it refuses and leaves the file unchanged

#### Scenario: The fixtures directory is pinned

- GIVEN any later slice
- WHEN `git diff origin/develop -- api/tests/Fixtures/Conversation/prompts` is taken
- THEN it is empty

#### Scenario: Existing characterization and phrase tests pass unmodified

- GIVEN `StandardPromptCharacterizationTest` (the `it` output at 4323 bytes), `SystemPromptComposerTest` and `EndPhraseInPromptTest`
- WHEN they run against the changed code
- THEN every one passes without an edited assertion

---

### Requirement: Placeholder Contract Enforced At Composition

In addition to the publish-time guard (`conversation-prompt-templates`), composition MUST independently refuse —
throwing `CompositionException` — any resolved fragment that lacks a required token, contains an unknown `{{x}}`
or a stray `{{`. Rendering MUST be a single pass over templates; the composer MUST NOT scan rendered text for
`:token` shapes, because rendered text includes operator-authored questions and phrases that may legitimately
contain colons and words such as `budget`. The composed text MUST NOT contain the literal `end_phrase`, and an
advance fragment MUST always yield the quoted closing phrase and the question floor.

#### Scenario: A resolved advance fragment missing its phrase token fails composition

- GIVEN an `advance.with_phrase` body without `{{advance_phrase}}` that bypassed publish (seeder or raw SQL)
- WHEN composition runs
- THEN `CompositionException` is thrown and no prompt is returned

#### Scenario: Operator text containing token-like characters composes unchanged

- GIVEN a primary question `Why did you say Re:think the :budget?` and an advance phrase containing `{{budget}}`
- WHEN the prompt is composed
- THEN both strings appear verbatim and composition succeeds

#### Scenario: The closing phrase and floor are present

- GIVEN a non-blank advance phrase and a minimum of 4 with no primaries
- WHEN the prompt is composed
- THEN the ADVANCE RULE section quotes the phrase and states the floor, and the text contains no literal `end_phrase`

---

### Requirement: An Unresolvable Prompt Set Fails Composition With The Existing 422

When the fragment set cannot be resolved (no active set, a missing or unknown key, a missing locale, a seal
mismatch, or a template that violates the placeholder contract), `/start` MUST answer HTTP 422 with the existing
`composition_error` code. Resolution MUST run inside the existing composition `try`, before the session row is
created and before any new provider session is issued, so a failure creates no `InterviewSession` row and issues no
new provider session. No new API error code and no OpenAPI change are introduced. On the resume path the existing
behaviour for any composition failure is unchanged: the outgoing provider session is released exactly once.

#### Scenario: No active set

- GIVEN no prompt set is active and `CONVERSATION_PROMPT_SOURCE=db`
- WHEN `POST /api/candidate/interview/start` is called
- THEN HTTP 422 with `error = composition_error` is returned, no `InterviewSession` row is created and no new provider session is issued

#### Scenario: A missing project-locale fragment row blocks composition

- GIVEN the active set has no `it` rows and the project language is `it`
- WHEN composition is attempted
- THEN it fails with 422 `composition_error`; no prompt mixing `it` and `en` fragments is produced

#### Scenario: A tampered set blocks composition

- GIVEN the active set's seal does not match its rows
- WHEN `/start` is called
- THEN HTTP 422 `composition_error` is returned

#### Scenario: A resumed interview that fails composition releases the outgoing session once

- GIVEN a live `in_corso` session and an unresolvable active set
- WHEN `/start` resumes it
- THEN 422 is returned and the outgoing provider session is torn down exactly once, as for any composition failure

---

### Requirement: Prompt Source Switch

`config('conversation.prompt_source')` (environment variable `CONVERSATION_PROMPT_SOURCE`) MUST accept `db` and
`baseline`. With `db` the active prompt set composes the prompt. With `baseline` the call site MUST pass no fragment
set and the composer MUST render the baseline text, without a code change or a database read of the prompt set. Any other value MUST fail composition with the same 422
`composition_error` rather than silently choosing a source. The default MUST be `db` once the cut-over lands.

#### Scenario: baseline source composes the baseline text

- GIVEN `CONVERSATION_PROMPT_SOURCE=baseline` and an active set whose `budget` fragment differs from the baseline
- WHEN `/start` composes
- THEN the baseline `budget` text is used

#### Scenario: An unknown source value fails composition

- GIVEN `CONVERSATION_PROMPT_SOURCE=nonsense`
- WHEN `POST /api/candidate/interview/start` is called
- THEN HTTP 422 `composition_error` is returned and no `InterviewSession` row is created

#### Scenario: db source composes the active set

- GIVEN `CONVERSATION_PROMPT_SOURCE=db` and the same active set
- WHEN `/start` composes
- THEN the active set's `budget` text is used (proving the database path is live)

---

### Requirement: Durable Conversation Prompt Stamp

`interview_sessions.conversation_prompt_version` (nullable `varchar(255)`) MUST be written through
`InterviewSessionLlmSnapshot::stamp()` at both of its call sites (plain issue and resume), write-once and never
overwritten from a null, like `system_prompt_chars`. For a database-resolved set the value MUST be
`{conversation.prompt_version}+s{set id}.{first 12 hex of the set seal}`; for the baseline source it MUST be the bare
config string. A new set takes effect at the next `/start` or resume; activating a set MUST NOT alter the stamp of a
session that already has one, so an interview whose composition spans an activation is a documented mixed record
whose stamp names the FIRST set composed for the session, overrides included. The column MUST NOT be exposed through
the public or admin API.

#### Scenario: The stamp is written once

- GIVEN a session stamped under set S1
- WHEN set S2 is activated and the session is resumed
- THEN `conversation_prompt_version` still names S1

#### Scenario: A null never overwrites a stamp

- GIVEN a session with a stamp
- WHEN `stamp()` is called with no version
- THEN the stored value is unchanged

#### Scenario: The stamp names the set and the baseline source is distinguishable

- GIVEN one session composed from set S and one composed with `CONVERSATION_PROMPT_SOURCE=baseline`
- WHEN both stamps are read
- THEN the first matches `{config}+s{id}.{sha12}` and the second equals the bare config string

---

### Requirement: Per-Code Override Rendered At A Fixed Position

When an override exists for the resolved (role code, competency code, locale), it MUST render as one additional
section headed by `label.override`, placed after COVERAGE TOPICS and before the STAR COVERAGE PROTOCOL section, and
MUST change nothing else in the composed prompt. With no override the output MUST be byte-identical to composing
without the override step; with one, the ADVANCE RULE bytes MUST be unchanged. At most one override applies (the
role-specific row wins over the role-less row).

#### Scenario: An override appears at the specified position only

- GIVEN a competency with an override body
- WHEN the prompt is composed
- THEN the override text appears after COVERAGE TOPICS and before STAR COVERAGE PROTOCOL and every other section is unchanged

#### Scenario: A competency with no override composes exactly the default

- GIVEN a competency with no override row
- WHEN the prompt is composed
- THEN the output is identical to the golden fixture for the same inputs

#### Scenario: The advance rule is unaffected by an override

- GIVEN a competency with an override
- WHEN the prompt is composed
- THEN the text from `ADVANCE RULE:` to the end equals the text composed without the override
