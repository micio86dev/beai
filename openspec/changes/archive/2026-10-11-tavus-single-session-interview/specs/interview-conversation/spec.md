# Delta for Interview Conversation

> Rescoped 2026-10-08, rebased and amended 2026-10-09. The two MODIFIED requirements are rebuilt from the CURRENT
> main spec, which changed on 2026-10-09 when `db-driven-conversation-prompts` was archived (fragment sets, the
> durable prompt stamp, per-code overrides, "a later competency does not greet again"): archiving this delta must
> not revert any of that, so each MODIFIED block below carries the full current main text plus the multi-competency
> additions. The previous (2026-10-08) block text predated that merge and is superseded. Nothing is REMOVED.

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
| **fragment set** (32 prose fragments, plus an optional per-code override) | Resolved at the CALL SITE from the active `conversation-prompt-templates` prompt set for `project_language` and passed into `compose()` as an immutable value object; absent (`null`) means the baseline text |

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

**Multi-competency mode (single-session, Tavus only).** When the single-session gate of `interview-session`
applies, the system MUST ALSO compose a CONVERSATION PLAN through the action
`App\Actions\Interview\ComposeConversationPlan`, which takes the ordered list of the competencies that remain
(from the one being started through the end of the project's ordered list) and returns ONE combined context
string, the per-competency snapshot list, the combined length and the prompt-set reference. The plan MUST be
built from the same per-competency resolution `/start` performs for a single competency, sharing one
implementation with it: the pinned catalogue revision, the role (null for `potential`, by rule), the
competency, the operator-authored primary questions, the spoken opening, the advance phrase (the LAST
competency of the project receives the final phrase, every other the intermediate one) and the STORED PROMPT
SET: for each competency the call site resolves the active set exactly as it does for a single competency
(`PromptSetResolver::resolveActive(locale, competency code, role code)` when the prompt source is `db`; the
baseline fragments and no override for the `baseline` source) and the competency's own override, if any, renders
inside that competency's segment only. It is therefore NOT a plain map of the single-competency composer over
the codes. `SystemPromptComposer::composeMany` is a PURE assembler over those already-resolved inputs (templates
and override included, no DB, no HTTP, no time, no randomness): it composes each entry with `compose()` and wraps
the results in the global rules and segment markers. The combined string MUST:
- be produced with no LLM call and be byte-identical for the same ordered, resolved inputs;
- contain, for every competency, a segment that is byte-identical to what the single-competency composition
  produces for that competency with the same inputs (so the fragment goldens keep pinning every segment);
- be composed from ONE stored prompt set: every entry's set reference MUST be identical, and a plan whose entries
  resolve to different sets (the active set changed between two resolutions) MUST fail closed with the existing
  HTTP 422 `composition_error` before any session is created or provider called;
- carry exactly ONE `prompt_version` (the configured string) and ONE set reference for the whole conversation,
  stamped like a single competency's (`{prompt_version}+s{id}.{sha12}`, the bare string for the baseline source);
- open with global rules ("do not begin any topic until told to begin it by topic code") and delimit each
  competency's segment with stable machine markers (`=== TOPIC CODE: <code> ===` ... `=== END TOPIC <code> ===`),
  each segment holding that competency's OWN coverage topics, anchors and override and nothing of another's; the
  global rules and the markers are code constants (machine-facing, English), not operator-editable fragments;
- carry, per segment, the "later competency does not greet again" clause by the competency's ordinal in the
  project, exactly as the single-competency path does;
- be bounded by `conversation.max_context_chars` (default 40 000, env-overridable), measured on the final
  combined string: when the full remaining list exceeds the bound, the plan covers a PREFIX of the list that fits,
  and the conversation is expected to be followed by a fresh one for the rest;
- never be built for a single remaining competency (that path stays on the single-competency composer).
A composition failure for any covered competency, and any `PromptTemplateUnresolvableException`, MUST answer
exactly as it does today (HTTP 422 `composition_error` / `anchor_translation_missing`, with the existing error
report for an unresolvable set), with no session created and no provider call made.

(Previously: the prose was hardcoded in the composer, `prompt_template_version` was a config string
"bumped on any template change", and the requirement said the composer emits "a stable `prompt_version`
string that uniquely identifies the template and its version". The prose is now stored fragments; the
config string keeps its role for PHP structure and for `OpeningTextComposer`; the identity of the stored
fragments is the prompt-set reference. Earlier history, unchanged: `assessment_type` was `standard` only —
C8 and `role_code` / `role_id` was unconditional; `follow_up_budget` was `default N=2 [PROVISIONAL —
OQ-1]` until it was RATIFIED at 4 on 2026-08-25, with a nullable per-project override to follow as
`project-followup-budget`. Before single-session, composition assumed exactly one competency per invocation and no multi-competency input shape existed.)

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

#### Scenario: Multi-competency composition is deterministic for the same ordered list

- GIVEN competencies [CSF, INN] for role FLL, framework version V, language `it`, prompt set S
- WHEN the plan is composed twice from the ordered list [CSF, INN]
- THEN both calls return the identical combined string, the identical snapshot list and the same single `prompt_version`

#### Scenario: Each segment is the single-competency composition of its competency

- GIVEN a plan for [CSF, INN] composed from set S
- WHEN each segment is extracted between its markers
- THEN each equals what the single-competency path composes for that competency with the same inputs and set

#### Scenario: Each segment holds only its own anchors

- GIVEN a plan for [CSF, INN] where each competency's anchor text carries a distinct sentinel
- WHEN the combined string is split on the segment markers
- THEN the CSF segment contains CSF's sentinel and not INN's, and the INN segment the reverse

#### Scenario: An override renders inside its own segment only

- GIVEN set S carries an override for INN and none for CSF
- WHEN the plan for [CSF, INN] is composed
- THEN the override text appears inside the INN segment at the fixed position after COVERAGE TOPICS, and the CSF segment is byte-identical to the composition without any override step

#### Scenario: A plan whose entries resolve to different sets fails closed

- GIVEN the active set changes between the resolution of CSF and the resolution of INN
- WHEN `ComposeConversationPlan` runs
- THEN HTTP 422 `composition_error` is returned, no session row is created and no provider call is made

#### Scenario: The baseline source composes a plan without a set or override

- GIVEN `CONVERSATION_PROMPT_SOURCE=baseline`
- WHEN a plan for [CSF, INN] is composed
- THEN the baseline text is used for every segment, no override renders, and the set reference is null

#### Scenario: The last competency of the project receives the final phrase

- GIVEN a plan whose last entry is the last competency of the project
- WHEN the plan is composed
- THEN that segment carries the final advance phrase and every other segment the intermediate one

#### Scenario: A role-less potential plan composes

- GIVEN a `potential` project with competencies [MTG, LAT]
- WHEN the plan is composed
- THEN the BARS rows are read with `role_id IS NULL` for each segment, exactly as the single-competency path does

#### Scenario: Later segments carry the no-greeting clause by ordinal

- GIVEN a plan for the second and third competencies of a project (a conversation created mid-interview)
- WHEN the plan is composed
- THEN each segment's OPENING ends with the `opening.continuation` clause, as the single-competency path does for a competency whose ordinal is greater than 1

#### Scenario: A plan over the size bound is truncated to a prefix

- GIVEN a remaining list whose combined length exceeds `max_context_chars`
- WHEN the plan is composed
- THEN it covers the longest prefix that fits, its `chars` is within the bound, and the uncovered competencies are not in the context

#### Scenario: A single-competency project never reaches the multi mode

- GIVEN a project with exactly one competency left to cover
- WHEN `/start` composes its context
- THEN the single-competency composition path runs unchanged and `ComposeConversationPlan` is not invoked

#### Scenario: A failure in any covered competency fails the whole create with the existing error

- GIVEN a plan in which one covered competency has no BARS indicators for the role
- WHEN `/start` composes the plan
- THEN HTTP 422 `composition_error` is returned, no session row is created and no provider call is made


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

When the single-session gate applies and the conversation covers several competencies,
`QuestionContext.system_prompt` MUST carry the plan's FULL combined context, composed ONCE at the `/start`
that creates the conversation, and `QuestionContext.promptSetRef` MUST carry the ONE set reference of the plan. A
later `/start` that is granted a continuation (`interview-session`) MUST NOT compose or carry a `system_prompt`
destined for a provider create-call; its `question_context` is built from the stored plan entry (end/final
phrase, ordinal, total, `prompt_version` of the conversation). `question_context.prompt_version` on a
continuation MUST equal the `prompt_version` stamped when the conversation was created, and MUST NOT include the
prompt-set reference.

(Previously: the requirement carried `system_prompt` and `prompt_version` only. The prompt-set reference is
added so the stamp site can record which set composed the prompt. Composition assumed one competency per `/start`; a multi-competency conversation composes once and later `/start` calls carry no prompt.)

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

#### Scenario: The combined context is composed once at conversation creation

- GIVEN a live Tavus conversation covering [CSF, INN, DRV]
- WHEN the conversation is created at the first `/start`
- THEN `QuestionContext.system_prompt` carries all three competencies' content at that single call; the
  second and third `/start` calls are continuations and compose no new context

#### Scenario: A continuation reports the conversation's prompt_version

- GIVEN a continuation for INN in a conversation created with `prompt_version` P under set S
- WHEN `/start` returns
- THEN `question_context.prompt_version` equals P, is non-null and non-empty, and contains no `+s` suffix


---

## ADDED Requirements

### Requirement: Multi-Competency Coverage Topics Are Never Revealed Verbatim To The Client

The "internal; not revealed verbatim" property already required of a single competency's coverage topics
extends unchanged to every competency's topics inside a combined context: no coverage topic, indicator
name or anchor text for ANY covered competency MUST appear in any response the candidate's browser can read,
in any persisted plan, or in any client-to-Tavus message, at any point in the conversation, including for
competencies not yet reached and competencies already completed.

#### Scenario: An unreached competency's anchors are as protected as the current one's

- GIVEN a live conversation whose combined context already holds INN's anchors, currently on CSF
- WHEN any candidate-facing response is inspected while CSF is active
- THEN no fragment of INN's anchor or indicator text appears in it

#### Scenario: A completed competency's anchors remain protected

- GIVEN a conversation that has advanced past CSF onto INN
- WHEN any candidate-facing response is inspected
- THEN no fragment of CSF's anchor or indicator text appears in it either

#### Scenario: The stored plan holds no anchors

- GIVEN a created plan
- WHEN `interview_sessions.conversation_plan` is inspected
- THEN it holds only codes, authored primary questions, follow-up budgets and a length

### Requirement: A Continuation Row Carries The Conversation's Prompt Stamp

A row created by a granted continuation composes nothing, so it MUST NOT call the composer to obtain a stamp.
Its `interview_sessions.conversation_prompt_version` MUST be copied from the row that created the conversation
(the value `InterviewSessionLlmSnapshot::stamp()` wrote there: `{conversation.prompt_version}+s{set id}.{sha12}`,
or the bare configured string for the baseline source), together with the rest of that row's LLM snapshot. Every
row sharing one provider conversation therefore names the one prompt set the conversation was composed from, and
activating another set mid-interview MUST NOT change the stamp of any row on a conversation already created. A
conversation created later (after a ceiling handover) composes against the then-active set and stamps its own
creating row, which is the documented mixed record of the durable-stamp requirement.

#### Scenario: A continuation row copies the stamp

- GIVEN a conversation created under set S1 and a granted continuation for INN
- WHEN the INN row is read
- THEN its `conversation_prompt_version` equals the creating row's value

#### Scenario: A set activated mid-interview does not alter a shared conversation's stamps

- GIVEN a live shared conversation stamped under S1 and set S2 activated before the next boundary
- WHEN the next competency is granted a continuation
- THEN the new row's stamp still names S1, and a fresh conversation created later stamps S2 on its own creating row
