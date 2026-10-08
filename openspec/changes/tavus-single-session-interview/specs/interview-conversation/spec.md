# Delta for Interview Conversation

> Rescoped 2026-10-08. The two MODIFIED requirements are rebuilt from the CURRENT main spec (it has
> drifted since 2026-08-21: `potential`, the ratified follow-up budget, `min_questions`). Nothing is REMOVED.

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
| `prompt_template_version` | `config/conversation.php`; bumped on any template change |

The composition MUST:
- Require NO LLM inference call.
- Produce identical output for identical inputs (deterministic).
- Emit a stable `prompt_version` string that uniquely identifies the template and its version.
- Contain NO hardcoded per-tenant text; all anchor text flows from the versioned framework catalog at the pinned `framework_version_id`.
- Select the correct language (it/en binding) for all catalogue-derived text (see the i18n requirement for the exact scope).

Purity is defined as: no LLM call, no HTTP, no time, no randomness, no IO. Reading
`config/conversation.php` is NOT a purity violation — the composer already reads
`prompt_version` from it. Identical inputs MUST still produce an identical prompt.

(Previously: `assessment_type` was `standard` only — C8 and `role_code` / `role_id` was
unconditional; the BARS source was always role-scoped. Earlier history, unchanged: `follow_up_budget`
was `default N=2 [PROVISIONAL — OQ-1]`, awaiting product ratification, and no minimum-question
input existed. OQ-1 was RATIFIED on 2026-08-25 at a platform default of 4; a nullable per-project
override follows as `project-followup-budget` and is NOT part of this capability yet.)

**Multi-competency mode (single-session, Tavus only).** When the single-session gate of
`interview-session` applies, the system MUST ALSO compose a CONVERSATION PLAN through the action
`App\Actions\Interview\ComposeConversationPlan`, which takes the ordered list of the competencies that
remain (from the one being started through the end of the project's ordered list) and returns ONE
combined context string, the per-competency snapshot list and the combined length. The plan MUST be built
from the same per-competency resolution `/start` performs for a single competency: the pinned catalogue
revision, the role (null for `potential`, by rule), the competency, the operator-authored primary
questions, the spoken opening, and the advance phrase (the LAST competency of the project receives the
final phrase, every other the intermediate one). It is therefore NOT a plain map of the single-competency
composer over the codes. The combined string MUST:
- be produced with no LLM call and be byte-identical for the same ordered inputs;
- carry exactly ONE `prompt_version` for the whole conversation;
- open with global rules ("do not begin any topic until told to begin it by topic code") and delimit each
  competency's segment with stable machine markers (`=== TOPIC CODE: <code> ===` ... `=== END TOPIC <code> ===`),
  each segment holding that competency's OWN coverage topics and anchors and nothing of another's;
- be bounded by `conversation.max_context_chars` (default 40 000, env-overridable): when the full remaining
  list exceeds the bound, the plan covers a PREFIX of the list that fits, and the conversation is expected to
  be followed by a fresh one for the rest;
- never be built for a single remaining competency (that path stays on the single-competency composer).
A composition failure for any covered competency MUST answer exactly as it does today (HTTP 422
`composition_error` / `anchor_translation_missing`), with no session created and no provider call made.
(Previously: composition assumed exactly one competency per invocation; no multi-competency input shape
existed.)

#### Scenario: Deterministic composition — same inputs yield same output

- GIVEN competency PRS, framework version V, role FLL, language `it`, N=2, nudge_min_chars=80, template v1
- WHEN `ConversationService::composePrompt()` is called twice with identical inputs
- THEN both calls return the identical prompt string and the same `prompt_version` value

#### Scenario: Deterministic composition for a role-less potential competency

- GIVEN competency MTG, framework version V, no role, language `en`, N=4, nudge_min_chars=80
- WHEN the prompt is composed twice with identical inputs
- THEN both calls return the identical prompt string and the same `prompt_version` value

#### Scenario: prompt_version is non-null and version-stamped

- GIVEN any valid set of composition inputs
- WHEN the prompt is composed
- THEN `prompt_version` is a non-null, non-empty string reflecting the active template version from `config/conversation.php`

#### Scenario: No LLM call during composition

- GIVEN the composition service is invoked at `/start`
- WHEN `composePrompt()` runs
- THEN no HTTP call is made to any LLM or external provider; the result is produced purely from in-memory template + catalog data

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

- GIVEN competencies [CSF, INN] for role FLL, framework version V, language `it`
- WHEN the plan is composed twice from the ordered list [CSF, INN]
- THEN both calls return the identical combined string, the identical snapshot list and the same single `prompt_version`

#### Scenario: Each segment holds only its own anchors

- GIVEN a plan for [CSF, INN] where each competency's anchor text carries a distinct sentinel
- WHEN the combined string is split on the segment markers
- THEN the CSF segment contains CSF's sentinel and not INN's, and the INN segment the reverse

#### Scenario: The last competency of the project receives the final phrase

- GIVEN a plan whose last entry is the last competency of the project
- WHEN the plan is composed
- THEN that segment carries the final advance phrase and every other segment the intermediate one

#### Scenario: A role-less potential plan composes

- GIVEN a `potential` project with competencies [MTG, LAT]
- WHEN the plan is composed
- THEN the BARS rows are read with `role_id IS NULL` for each segment, exactly as the single-competency path does

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
as additive fields. The extended `QuestionContext` flows through
`ProviderSessionService::issue()` to the provider adapters (HeyGen, Tavus).

The C7a `/start` control flow (create-or-resume, provider-outside-txn, failure matrix)
is UNCHANGED. This is a purely additive widening.

The `/start` response body MUST include `prompt_version` in the `question_context` object
as a non-null, non-empty string (audit and traceability). This field is additive to the
existing `question_context` shape (C7a addendum: `end_phrase`, `final_phrase`).

When the single-session gate applies and the conversation covers several competencies,
`QuestionContext.system_prompt` MUST carry the plan's FULL combined context, composed ONCE at the `/start`
that creates the conversation. A later `/start` that is granted a continuation (`interview-session`) MUST NOT
compose or carry a `system_prompt` destined for a provider create-call; its `question_context` is built from
the stored plan entry (end/final phrase, ordinal, total, `prompt_version` of the conversation).
`question_context.prompt_version` on a continuation MUST equal the `prompt_version` stamped when the
conversation was created.

#### Scenario: /start response contains prompt_version

- GIVEN a valid candidate JWT and a project with a configured `standard` competency
- WHEN `POST /api/candidate/interview/start` returns HTTP 201
- THEN `question_context.prompt_version` is a non-null, non-empty string in the response body

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

- GIVEN a continuation for INN in a conversation created with `prompt_version` P
- WHEN `/start` returns
- THEN `question_context.prompt_version` equals P and is non-null and non-empty


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
