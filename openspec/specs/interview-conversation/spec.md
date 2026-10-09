# Interview Conversation Specification

## Purpose

Defines the adaptive conversation layer (C8): server-side system-prompt composition from
BARS indicator data, coverage-driven adaptive follow-up questioning for `standard` AND `potential` sessions
(SA-02), the STAR coverage protocol and same-episode constraint that govern HOW the avatar
interviews, the clamped minimum-question floor on the advance rule, nudge enforcement on
short answers (SA-03), and a PR-gated payload-shape contract for the provider session. All
behavior is injected at `/start` via the extended `QuestionContext`; no per-turn server
round-trip is introduced. Additive to C7a's five-endpoint contract.

**The composed prompt is an INSTRUCTION, not a control loop.** `compose()` runs once per
competency at `/start`; the provider's own LLM then conducts the conversation autonomously,
with no turn-by-turn server round-trip. Every requirement in this capability is therefore a
property of the composed STRING, and is verified by asserting on that string. Whether the
avatar actually obeys is observable only in a live provider interview (`@ai` suite or a
manual smoke), never in a unit test.

---

## Non-Goals

- BARS scoring or `Evaluation` persistence (C9)
- Outbound webhook delivery (C10)
- Provider token issuance, session lifecycle, teardown, transcript reconcile (C7a)
- Admin dashboards or interview monitoring UI (C11)
- Time-limit/deadline logic (open product decision #5); the domain retry (RT-B, ratified decision #4) is specified in `scoring-engine`, `participant-sso` and the re-interview opening requirement below
- Per-turn server LLM inference (Option B)
- Hardcoded per-tenant question or anchor text
- Refactoring `ScoreEvaluationJob` (C9) beyond calling the shared `BarsIndicatorLoader`

---

## Requirements

### Requirement: BARS Indicator Loading — BarsIndicatorLoader

`BarsIndicatorLoader` MUST be the SINGLE shared implementation of
role-and-competency-scoped BARS indicator lookup, consumed by BOTH the
conversation (C8) prompt composer and the scoring (C9) `ScoreEvaluationJob`.
The prior RV-2 carve-out — permitting C9 to keep an independent,
competency-only inline query — is REVERSED: that duplicated, unscoped query
was the root cause of cross-role indicator contamination in scoring. The
loader MUST additionally support the `potential` assessment type via an
explicit `whereNull('role_id')` branch when no role is pinned.

The loader MUST prevent cross-role indicator contamination: indicators
belonging to the same competency code but a different role MUST NOT be
returned.
(Previously: C9's inline competency-only query was explicitly carved out as
untouched, non-refactorable code (RV-2), and the loader had no
`potential`/null-role branch.)

#### Scenario: Indicators filtered by both role and competency

- GIVEN competency COL exists for roles FLL (3 indicators) and MLL (2 different indicators)
- WHEN `BarsIndicatorLoader::forRoleCompetency(role_id: FLL, competency_id: COL)` is called
- THEN only the 3 FLL-COL indicators are returned; no MLL-COL indicators appear in the result

#### Scenario: Cross-role contamination is impossible

- GIVEN roles FLL and MLL share competency code COL with disjoint indicator sets
- WHEN `BarsIndicatorLoader` is called for each role independently
- THEN the two returned indicator sets are disjoint; no indicator from MLL appears in the FLL result and vice versa

#### Scenario: C9 scoring consumes the same loader as C8 conversation

- GIVEN `ScoreEvaluationJob` needs indicators for a role×competency pair
- WHEN it requests them
- THEN it calls the shared `BarsIndicatorLoader`, not an independent inline query
- AND the result is identical to what C8's prompt composer would receive for the same pair

#### Scenario: Null-role branch serves potential competencies

- GIVEN competency MTG has 3 indicators with `role_id = null`
- WHEN `BarsIndicatorLoader` is called with no role (potential path)
- THEN it issues `whereNull('role_id')`, not `where('role_id', null)`, and returns the 3 MTG indicators

---

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

### Requirement: OpeningTextComposer re-offer variant (Decision 6)

When a competency session is re-offered after a bounded single re-offer
(`interview-session`'s "Bounded single re-offer of an `error` competency", Decisions 4 &
5), `OpeningTextComposer` MUST compose the opening greeting using a NEW `retry` variant,
alongside the existing `first` / `next` / `resume` variants. The `retry` variant MUST
tell the candidate they are re-attempting this competency — it MUST NOT read as a
first-time greeting. Locale keys MUST exist for at least `it` and `en`
(`api/lang/{it,en}/interview.php`, alongside `opening.first` / `.next` / `.resume`).
`opening_text` composed under the `retry` variant MUST still respect the existing
anti-leak rule (no BARS anchor or indicator text) and MUST carry a `prompt_version`.

#### Scenario: A re-offered competency composes the retry variant

- GIVEN a competency session reset to `pending` by the bounded single re-offer
- WHEN `InterviewController` calls `OpeningTextComposer.compose()` for the next `/start`
- THEN the `retry` variant is selected, not `first`/`next`/`resume`

#### Scenario: retry copy exists in it and en

- GIVEN the `retry` variant is selected for a project with `language = 'it'` and,
  separately, `language = 'en'`
- WHEN `opening_text` is composed
- THEN a non-empty, language-correct string is produced for both locales

#### Scenario: retry copy still leaks no BARS content

- GIVEN a competency with BARS indicators, re-offered
- WHEN `opening_text` is composed under the `retry` variant
- THEN it contains no indicator or anchor text — the same guarantee already required of
  the `first`/`next`/`resume` variants

#### Scenario: A never-attempted competency never uses the retry variant

- GIVEN a competency with no prior `error` session
- WHEN its opening is composed
- THEN the variant is `first` (or `next`/`resume` per existing rules) — never `retry`

---

### Requirement: Adaptive Standard Follow-Up Questioning (SA-02)

For `assessment_type = 'standard'`, the composed system prompt MUST instruct the avatar
to conduct coverage-driven follow-up questioning within each competency:

1. Ask at most N follow-up questions per competency, where N = `follow_up_budget` (default N=4, RATIFIED 2026-08-25).
2. The avatar MUST be instructed to speak `end_phrase` only when
   `(all BARS coverage topics addressed OR the follow-up budget is exhausted) AND the
   effective minimum question count has been reached` — never on the first candidate answer.
   The minimum term is normative and its arithmetic is owned by **Requirement: Advance Rule
   and Minimum Question Count** below; that requirement's clamp is what keeps the
   `OR budget exhausted` escape reachable.
3. The system prompt MUST explicitly name the BARS indicators to be covered so the avatar LLM can evaluate coverage.
4. Follow-up slots are consumed only by coverage-driven turns, not by nudge re-prompts.
5. The budget is an INSTRUCTION, not a server-side control loop: `compose()` is called once
   per competency at `/start` and the provider's own LLM then conducts the conversation
   autonomously. An overshoot of roughly one question is expected behaviour, not a defect.
   Observed live on 2026-08-25: a competency ran six questions against a budget of 4.

(Previously: item 1 gave N=2 as a provisional default pending OQ-1, and item 2 stated the
advance condition as `all BARS indicators addressed OR the follow-up budget is exhausted`
with no minimum-question term. That two-term condition was the source of truth and is now
superseded — coverage alone no longer permits closing.)

> **Known stale literal — owned by `project-followup-budget`, not a defect here.**
> `api/app/Http/Controllers/.../InterviewController.php:503` resolves the budget as
> `config('conversation.followup_budget', 2)`. The `2` is only the missing-key fallback,
> reachable solely if `config/conversation.php` ceased to exist, so it does not affect the
> ratified default of 4 that actually ships. It is nonetheless a misleading leftover of the
> pre-ratification value, and it is the exact line the `project-followup-budget` change will
> edit (`config(...)` → `$project->followup_budget ?? config(...)`). Deliberately out of
> scope for `star-interviewer-protocol`; recorded here so it is not rediscovered as a bug.

#### Scenario: follow_up_budget injected into composed prompt

- GIVEN N=4, assessment_type='standard', competency STG with 3 BARS indicators for role BUL
- WHEN the prompt is composed
- THEN the resulting prompt string contains language instructing the avatar to ask at most 4 follow-up questions
- AND it instructs the avatar to advance (end_phrase) only after coverage or budget exhaustion AND the effective minimum question count is reached

#### Scenario: Budget exhaustion triggers end_phrase — integration assertion

- GIVEN a HeyGen session initialized with a standard prompt capping N=2 follow-ups
- WHEN the avatar has asked the initial question plus 2 follow-up questions
- THEN the avatar speaks `end_phrase` at the next turn — PROVIDER INTEGRATION TEST ONLY (@ai suite)
- AND this holds because the effective minimum is clamped to `budget + 1 = 3`, which those
  three questions satisfy; budget exhaustion can never be blocked by an unmet minimum

#### Scenario: Coverage achieved before budget — end_phrase fires early — integration assertion

- GIVEN a HeyGen session and candidate answers that address all BARS indicators in fewer than N turns
- AND the effective minimum question count has ALSO been reached
- WHEN the avatar determines coverage is complete
- THEN the avatar speaks `end_phrase` before consuming the full N budget — PROVIDER INTEGRATION TEST ONLY (@ai suite)

#### Scenario: Coverage alone does not permit closing below the minimum

- GIVEN coverage of every BARS topic is complete after 2 questions
- AND the effective minimum question count is 4
- WHEN the avatar evaluates whether it may close
- THEN it MUST continue questioning until the minimum is reached — coverage is necessary but
  no longer sufficient — PROVIDER INTEGRATION TEST ONLY (@ai suite)

---

### Requirement: STAR Coverage Protocol and Same-Episode Constraint

The composed system prompt MUST carry a **STAR coverage protocol** instructing the avatar
that, after each candidate answer, it determines which of **Situation, Task, Context, Action
and Result** is least covered *for the episode under discussion*, and makes its next question
close that gap.

STAR is an ORTHOGONAL layer over the BARS coverage topics, not a replacement for them. The
BARS indicators answer *which behaviours am I assessing* — competency-specific, authored,
versioned. STAR answers *is this episode described completely enough to assess anything at
all* — competency-agnostic and fixed. Both MUST be present in the prompt.

The protocol MUST name Action and Result explicitly as the elements candidates most often
leave implicit, and MUST distinguish what the candidate personally did from what their team
did. This exists because the scoring prompt's EVALUATION STANDARDS
(`PromptBuilder::EVALUATION_STANDARDS`, owned by `specs/scoring-engine`) requires a specific
situation described with concrete detail, concrete actions the candidate personally took, and
a measurable outcome — **all three — before an indicator may score 5**. (A 4 does not require
all three; it requires evidence that CLEARLY exceeds the Score 3 anchor.) The interviewer must
ask for what the evaluator is required to find.

**These two prompts are a matched pair. An edit to either MUST check the other.**

A STAR element that genuinely does not apply to the episode, or that the candidate states
they cannot recall, MUST be treated as covered and MUST NOT be re-asked. Without this, an
inapplicable element becomes an unreachable coverage condition and the competency cannot
advance — the same deadlock class the advance-rule clamp exists to prevent.

The prompt MUST carry a **same-episode constraint**: every follow-up deepens the single
episode the candidate has already begun describing, and the avatar MUST NOT ask for a second
or different example. The single exception is an episode containing no assessable behaviour
at all, which the avatar MAY replace — otherwise a candidate who opens with a poor example is
locked into it for the whole competency.

The same-episode constraint MUST be stated ONCE, forcefully, and MUST live inside the STAR
section rather than in a section of its own: it is meaningless except in reference to the
episode STAR describes, and separating them would let a future editor delete one without
noticing the other stopped making sense. Repetition competes with the other rules in the same
prompt for the model's attention; if one statement is ever shown insufficient by a live
interview, repetition MAY be added WITH THAT EVIDENCE.

Section order MUST be: role/style → BARS coverage topics → **STAR protocol** → follow-up
rules → nudge → advance rule. STAR precedes the follow-up rules because it tells the model
what a follow-up is FOR; a budget stated before any notion of what to spend it on is a number
without a purpose.

(Previously: the prompt listed BARS indicators as coverage topics, stated a follow-up budget,
optionally a nudge rule, and an advance rule. It carried no model of what a complete answer
looks like, nothing preventing the avatar from collecting several shallow episodes instead of
one deep one, and no floor on the number of questions beyond a bare "Do NOT close after the
first answer".)

#### Scenario: The STAR protocol is present and names all five elements

- GIVEN a competency with indicators and a valid locale
- WHEN the system prompt is composed
- THEN it contains a STAR section naming Situation, Task, Context, Action and Result
- AND it instructs the avatar to target the least-covered element with its next question

#### Scenario: Action and Result are named as the elements the evaluator demands

- WHEN the system prompt is composed
- THEN it states that concrete personal actions and a measurable outcome are required
- AND it distinguishes what the candidate personally did from what their team did

#### Scenario: An inapplicable STAR element does not block advancement

- WHEN the system prompt is composed
- THEN it states that an element which does not apply, or which the candidate cannot recall, counts as covered and is not re-asked

#### Scenario: The same-episode constraint is present

- WHEN the system prompt is composed
- THEN it instructs the avatar to deepen the episode already under discussion
- AND it forbids asking for a second or different example
- AND it permits replacing an episode that contains no assessable behaviour at all

#### Scenario: The same-episode constraint is stated exactly once

- WHEN the system prompt is composed
- THEN the key phrase of the constraint occurs exactly one time in the composed string

#### Scenario: STAR precedes the follow-up rules

- WHEN the system prompt is composed
- THEN the STAR section appears before the follow-up budget section, and after the BARS coverage topics

---

### Requirement: Advance Rule and Minimum Question Count

The prompt MUST carry a **minimum question count**: the avatar MUST NOT speak the closing
phrase before it has asked at least that many questions in the competency, counting the
opening question.

The effective minimum question count MUST be `max(1, min(configuredMinimum, budget + 1))`,
computed by the composer. The `+ 1` is the opening question, which is not a follow-up and
does not consume budget. The `max(1, …)` floor prevents a configured `0` or negative value
from stating a minimum of zero questions, which would read as permission to close before
asking anything.

This clamp is **mandatory, not defensive**. Without it, a configuration where the minimum
exceeds what the budget permits instructs the avatar to ask at least M questions and at most
B follow-ups with `M > B + 1` — an unsatisfiable instruction. The avatar then never speaks
the closing phrase, the client's end-phrase match never fires, the competency runs to its
session cap, and on HeyGen the session terminates with `MAX_DURATION_REACHED`, which the
candidate experiences as an error at the end of a question they answered completely. **That is
a defect this system has already shipped once**, and a minimum question count is by
construction a new way to reach it.

The composer MUST NOT throw on a minimum that exceeds the budget. A failed composition at
`/start` is a candidate facing a broken interview because two operator-supplied numbers
disagreed; clamping degrades to the pre-existing behaviour, which is the correct direction to
fail in.

The advance condition MUST be: speak the closing phrase when
`(all coverage topics addressed OR the follow-up budget is exhausted) AND the effective
minimum question count has been reached`. Because the minimum is clamped to at most
`budget + 1`, **budget exhaustion always satisfies the minimum**, so the `OR budget exhausted`
escape hatch remains reachable under every possible configuration. That reachability is the
whole safety argument and MUST be proven by walking a `(budget, minimum)` grid, not by
inspecting the arithmetic.

The minimum MUST appear as a conjunct in BOTH branches of the advance rule — the branch where
an advance phrase is supplied and the fallback branch where it is not.

The advance phrase itself MUST continue to be quoted VERBATIM in the prompt when supplied,
with the instruction to say it word for word as the final sentence, and the existing
no-phrase fallback text MUST continue to work. That text is load-bearing: it was added
because the avatar had previously been told to utter a placeholder whose value it was never
given, which is how the `MAX_DURATION_REACHED` incident above occurred.

(Previously: the advance condition was `all coverage topics addressed OR the follow-up budget
is exhausted`, with no minimum-question term and therefore no clamp.)

> **Observation, not a normative demand — the advance condition is stated twice.**
> `SystemPromptComposer::buildBudgetSection()` closes with *"Advance (speak end_phrase) only
> after all coverage topics are addressed OR the follow-up budget of N is exhausted"* — the
> old two-term form, WITHOUT the minimum conjunct — while `buildAdvanceSection()` states the
> full three-term condition. The authoritative statement is the ADVANCE RULE section, and the
> 2026-08-25 live smoke closed cleanly on all five competencies, so no harm is demonstrated.
> It is recorded because a prompt that states the same rule twice at two different strengths
> is a plausible source of early closing, and because the weaker sentence is what made the
> original budget-exhaustion test pass without observing the advance section at all.

#### Scenario: Minimum below the budget ceiling is used as configured

- GIVEN a budget of 4 and a configured minimum of 4
- WHEN the system prompt is composed
- THEN the effective minimum stated in the prompt is 4

#### Scenario: Minimum exceeding the budget is clamped, not thrown

- GIVEN a budget of 2 and a configured minimum of 6
- WHEN the system prompt is composed
- THEN no exception is thrown
- AND the effective minimum stated in the prompt is 3
- AND the prompt never states a minimum greater than the number of questions the budget permits

#### Scenario: Budget exhaustion always permits advancing

- GIVEN any budget and any configured minimum
- WHEN the system prompt is composed
- THEN the advance rule states that an exhausted follow-up budget permits closing
- AND the stated effective minimum is never greater than `budget + 1`, so it cannot contradict that

#### Scenario: A budget of zero still yields a satisfiable prompt

- GIVEN a budget of 0 and a configured minimum of 4
- WHEN the system prompt is composed
- THEN the effective minimum is 1
- AND the prompt remains internally consistent

#### Scenario: A zero or negative configured minimum floors at 1

- GIVEN a configured minimum of 0 or a negative value
- WHEN the system prompt is composed
- THEN the effective minimum stated is 1, never 0

#### Scenario: The advance phrase is still quoted verbatim

- GIVEN an advance phrase is supplied
- WHEN the system prompt is composed
- THEN the phrase appears verbatim in the prompt
- AND the avatar is instructed to say it word for word as its final sentence

#### Scenario: The no-phrase fallback still applies and carries the minimum

- GIVEN no advance phrase is supplied
- WHEN the system prompt is composed
- THEN the prompt still forbids closing after the first answer
- AND the fallback branch also states the effective minimum question count

---

### Requirement: Nudge Enforcement (SA-03)

The composed system prompt MUST inject the `nudge_min_chars` value from `Project` and
instruct the avatar to re-prompt the candidate when an answer is below the minimum length
threshold before counting it toward BARS coverage.

A nudge MUST NOT consume a follow-up budget slot (provisional OQ-3).

#### Scenario: nudge_min_chars from Project injected into prompt

- GIVEN `Project.nudge_min_chars = 100` and any valid competency
- WHEN the prompt is composed
- THEN the prompt string contains a character-length threshold instruction (100 chars) directing the avatar to re-prompt when the answer is too short

#### Scenario: nudge_min_chars = 0 — no nudge instruction injected

- GIVEN `Project.nudge_min_chars = 0`
- WHEN the prompt is composed
- THEN no nudge length threshold instruction is injected (nudge disabled)

#### Scenario: Nudge does not consume a follow-up slot — integration assertion

- GIVEN N=2, a candidate who gives a too-short first answer (nudge fires), then a sufficient answer
- WHEN the avatar re-prompts once (nudge) and the candidate responds adequately
- THEN the avatar proceeds to use its 2 follow-up budget slots for coverage (nudge did not consume one) — PROVIDER INTEGRATION TEST ONLY (@ai suite)

---

### Requirement: Provider Payload Contract — PR-Gated Shape Assertion (C-1)

The provider create-call body MUST include the composed `system_prompt` (and the
`conversational_context` envelope if required by the provider) at session creation.

A unit/feature-tier `Http::fake` payload-shape assertion MUST verify the system prompt
field is present and non-empty in the provider REST call body. This test MUST run on
every PR (not only in the `@ai` suite). A missing or renamed provider field MUST fail
the PR test suite.

Avatar behavioral compliance (≤N follow-ups, nudge non-slot-consumption, `end_phrase`
advance signal) belongs exclusively to the `@ai` integration suite.

#### Scenario: Provider create-call body contains system_prompt — feature test

- GIVEN `Http::fake` intercepts the provider session-creation request
- WHEN `/start` is called with a valid candidate JWT and a composed `system_prompt`
- THEN the intercepted request body contains a non-empty `system_prompt` (or provider-mapped equivalent field); missing or null fails the assertion — UNIT/FEATURE TEST, PR-gated

#### Scenario: Provider call omits system_prompt — feature test catches it

- GIVEN `Http::fake` intercepts the provider session-creation request
- WHEN `QuestionContext::system_prompt` is null or empty (composition failure bypassed)
- THEN the `Http::fake` payload-shape assertion fails; no provider session is created — UNIT/FEATURE TEST, PR-gated

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

### Requirement: QuestionContext Carries a Composed Opening Greeting

The `QuestionContext` DTO MUST carry a composed `opening_text` alongside `system_prompt`
and `prompt_version`. `opening_text` MUST be produced from a locale-keyed template built on
`competency.name`, versioned together with `prompt_version` (sourced from
`config/conversation.php`).

This greeting is an INTERIM default: every demonstrated-working LiveAvatar call includes
`opening_text`, and a neutral, versioned greeting is the smallest change that stays inside
the only proven wire shape. Replacing its wording with a richer opener is a
data/prompt-version change, not a contract change — it MUST NOT require touching
`HeygenProvider` or `TavusProvider`.

`opening_text` MUST NOT contain BARS anchor or indicator text — the same anti-leak rule
already imposed on `system_prompt` (see the `interview-session` delta). `opening_text`
MUST respect the project's language (`it`/`en` mandatory).

#### Scenario: opening_text is generated for a fresh session
- GIVEN a project with language='it' and a competency named 'Comunicazione'
- WHEN `QuestionContext` is composed for a fresh `/start` call
- THEN `opening_text` is a non-empty Italian string built from the competency name and
  carries the same `prompt_version` as `system_prompt`

#### Scenario: opening_text never leaks BARS content
- GIVEN a competency with BARS indicators
- WHEN `opening_text` is composed
- THEN it contains no indicator or anchor text — only the interim greeting template
  rendered with `competency.name`

#### Scenario: Changing the greeting wording is a prompt_version bump, not a code change
- GIVEN the interim greeting template is edited in `config/conversation.php`
- WHEN a new session is composed
- THEN `opening_text` reflects the new wording and `prompt_version` changes;
  `HeygenProvider`/`TavusProvider` request-building code is untouched

---

### Requirement: i18n — Composed Prompt in Project Language

All **catalogue-derived** content injected into the composed system prompt — indicator
descriptions and the anchor texts `{5,3,1}` — MUST be in the project language for the
`it`/`en` binding. Mixing project-language and English CATALOGUE content in one prompt is
PROHIBITED: an EN indicator description alongside localised anchors is an incoherent rubric.

The **fixed interviewer directives** are a different category and are authored in English by
decision: the role/style header, the STAR coverage protocol, the follow-up budget rule, the
nudge rule and the advance rule are hardcoded English in every locale. They are instructions
addressed to the model, not text spoken to or read by the candidate, and they are never
uttered verbatim. Localising them is a deliberate future decision, not an accidental gap —
whoever takes it MUST localise them as a set, because localising one directive section and
not its neighbours is the precise failure this scope statement exists to prevent.

> **Why this is stated so explicitly.** The composer's own class docblock claimed "Template
> sections (all in the project language)" and was FALSE when written: only the coverage
> section was ever localised. `star-interviewer-protocol` corrected that docblock and settled
> the question (its OQ-3 / D-5) while adding one more hardcoded-English section, STAR. This
> spec previously repeated the same false claim; leaving it would have left the source of
> truth asserting the opposite of shipped, tested behaviour.

(Previously: "The composed system prompt (instructions, indicator descriptions, anchor texts,
nudge instruction, follow-up guidance) MUST be entirely in the project language … Mixed-language
prompts are PROHIBITED." That sentence covered the interviewer directives, which have never
been localised in any shipped version of the composer. The normative hard-fail below is
UNCHANGED — only the scope claim above is corrected.)

If any required anchor or indicator translation is missing for the project locale, the
engine MUST NOT silently fall back to English. Composition MUST fail with the
`anchor_translation_missing` signal; `/start` MUST return HTTP 422 and MUST NOT create
any `InterviewSession` row or make any provider call.

This hard-fail is evaluated per project, against that project's pinned
role and its configured competencies — a project whose role is fully
translated MUST NOT be affected by another role remaining untranslated, and
a project whose role is only partially translated MUST still hard-fail on
the first untranslated pair it encounters, exactly as it would if no
translation existed at all.

> **Coverage note**: Composition scenarios for a fully-translated role (see
> `framework-catalog-it-translations`) MUST be exercised against real seeded
> IT catalogue data for that role, not only factory-authored fixtures. The
> HTTP 422 hard-fail path remains covered by factory fixtures for any role
> or pair still outside the translated scope.
(Previously: stated that no seeded IT translation exists anywhere in the
catalogue, so all `it`-locale composition scenarios were necessarily
fixture-only; this is no longer true for translated scope.)

#### Scenario: Project language selects `en` anchor texts

- GIVEN project language = `en` and competency COL has English anchor translations
- WHEN the prompt is composed
- THEN all injected indicator descriptions and anchor texts are in English

#### Scenario: Project language selects `it` anchor texts (factory-seeded)

- GIVEN project language = `it` and competency COL has Italian anchor translations (factory-authored)
- WHEN the prompt is composed
- THEN all injected strings are in Italian; no English anchor string appears

#### Scenario: Missing project-locale translation blocks composition — HTTP 422

- GIVEN project language = `it` and competency INN has no Italian translation for one indicator's anchor text
- WHEN `POST /api/candidate/interview/start` is called
- THEN HTTP 422 is returned; no `InterviewSession` row is created; no provider call is made; the error carries the `anchor_translation_missing` signal

#### Scenario: A project pinned to a fully-translated role composes and starts normally (real catalogue)

- GIVEN project language = `it`, the project is pinned to role ICO, and
  ICO's full scope is translated per `framework-catalog-it-translations`
- WHEN `POST /api/candidate/interview/start` is called
- THEN HTTP 201 is returned, an `InterviewSession` row is created, and the
  composed prompt contains only Italian indicator and anchor text — no HTTP
  422 and no `anchor_translation_missing` signal

#### Scenario: Partial coverage — a project on an untranslated role still hard-fails

- GIVEN project language = `it`, the project is pinned to role FLL, and
  FLL is not yet in the translated scope (ICO is translated, FLL is not)
- WHEN `POST /api/candidate/interview/start` is called
- THEN HTTP 422 `anchor_translation_missing` is returned exactly as before
  this change; ICO's translated state has no bearing on FLL's outcome

---

### Requirement: Testability Split — Server-Asserted vs Provider-Delegated

Requirements marked **"PROVIDER INTEGRATION TEST ONLY"** MUST NOT be verified in unit or
feature tests; they belong in the `@ai` group run on `workflow_dispatch` / `release/*`,
never on PR.

All other requirements MUST be verifiable via unit tests with zero HTTP and zero avatar
dependency (deterministic assertions on the composed prompt string, indicator content,
versioning, language, budget, nudge value).

#### Scenario: Unit test asserts BARS indicators appear in composed prompt

- GIVEN competency COL with 3 FLL BARS indicators I1, I2, I3 and their English anchor texts
- WHEN the prompt composition unit test runs with no HTTP fixtures
- THEN the returned prompt string contains all 3 indicator names/descriptions and all anchor texts

#### Scenario: @ai integration test asserts end_phrase compliance

- GIVEN a live HeyGen session initialized with a standard prompt
- WHEN the `@ai` test group runs on workflow_dispatch
- THEN the test verifies the avatar speaks `end_phrase` only after coverage/budget exhaustion — NOT run on PR

---

### Requirement: Authored Primary Questions Are The Complete Primary Set (No Hidden Questions)

Every primary question the avatar asks for a competency MUST come from that
competency's `project_questions` rows, in `position` order, and MUST be the
COMPLETE set of primaries — the LLM MUST NOT introduce, substitute, or
reorder in a primary question of its own. The model's only generative
latitude is follow-up questions on a primary already asked.

This corrects the current dual-channel wiring: `InterviewController`'s first
authored question of a competency IS `OpeningTextComposer`'s opening
question — not a separate, additional one — and the competency's remaining
authored questions ARE `SystemPromptComposer`'s primaries, not an addition
on top of a model-driven budget. There is no initial-question-plus-separate-
questions structure.

#### Scenario: All and only the authored questions are the primaries

- GIVEN a competency with 2 authored primary questions in `project_questions`
- WHEN the interview composes for that competency
- THEN exactly those 2 questions, in position order, are the primaries asked
- AND `OpeningTextComposer`'s opening question IS the first of them, not a
  third, separate question

#### Scenario: The composed prompt grants no latitude to invent a primary

- GIVEN any competency with at least one authored primary
- WHEN the composed system prompt is inspected
- THEN it does not authorize the model to introduce an additional primary
  question for that competency — its stated latitude is follow-ups only

### Requirement: Follow-Up Budget Applies Only On Top Of Authored Primaries

`SystemPromptComposer`'s effective per-competency budget MUST be the
competency's primary count (its `project_questions` row count) plus the
follow-up cap (`follow_up_budget`) — never `budget + count(authoredQuestions)`
as an addition on top of a model-driven count. Authored questions ARE the
primaries; they are not additive to a separately-sized budget.

(Previously: unspecified in this capability; `SystemPromptComposer` computed
`effectiveBudget = budget + count(authoredQuestions)`, treating authored
questions as additive to the follow-up budget rather than as the primaries.)

#### Scenario: Total question count reflects primaries plus follow-ups, not double-counting

- GIVEN a competency with 1 authored primary and `follow_up_budget = 4`
- WHEN the prompt is composed
- THEN it instructs at most 1 primary + 4 follow-ups = 5 total questions —
  never a budget inflated by counting the primary a second time

### Requirement: Primary And Follow-Up Turns Are Distinguishable In Transcript/Telemetry

Every recorded interview turn MUST carry a marker distinguishing a
primary-question turn from a follow-up turn, so "no hidden questions" is
auditable after the fact, not only asserted in the prompt.

#### Scenario: A transcript audit separates primaries from follow-ups

- GIVEN a completed session transcript
- WHEN it is inspected
- THEN each turn is marked primary or follow-up
- AND the primary-marked turns match that competency's `project_questions`
  rows 1:1, in order

### Requirement: Potential Question Cap Is A Maximum, Never A Fixed Count

The `potential` assessment type's per-competency question count is a
platform-configured MAXIMUM (`PlatformSettings::maxQuestionsPerCompetency()`,
default 4), never a fixed number of questions the avatar must ask. This
corrects the earlier "4 fixed questions" phrasing (in `CLAUDE.md` and
`docs/app_description/02-domain/03-assessment-types.md:23`).

#### Scenario: A potential competency configured with 1 question asks only 1 primary

- GIVEN a `potential` competency with exactly 1 `project_questions` row
- WHEN the interview composes for that competency
- THEN 1 primary question is asked, plus at most the follow-up budget — not
  4

### Requirement: A Zero-Primary Competency Never Reaches Interview

Because the cap is a maximum, an operator MAY delete every question for a
selected competency, and `StoreProjectQuestionRequest` deliberately permits
saving that state (the per-competency count is a ceiling, not a floor — see
`project-config`). Under "no hidden questions" the model MUST NOT invent a
primary to fill that gap, so this state cannot be allowed to reach a live
interview turn.

It never does: `project-config`'s single interviewability predicate
(`A Single Interviewability Predicate Gates Every Interview Entry Point`,
PO-ratified) already defines a project as interviewable only while EVERY
selected competency has at least one live question, and that predicate gates
every route capable of starting or continuing an interview — entry-link
mint, SSO exchange, and M2M enrolment alike. A competency with zero live
questions therefore makes its whole project non-interviewable, and no route
reaches `/start` for it. There is no separate zero-primary rule to design
here; it is the same predicate, applied to the same fact, at an earlier
door.

#### Scenario: A competency emptied of its questions blocks the whole project, not just itself

- GIVEN a `potential` competency whose operator deleted its only
  `project_questions` row, leaving it at zero
- WHEN any of the three interview entry points (entry-link mint, SSO
  exchange, M2M enrolment) is attempted for that project
- THEN it is refused by `project-config`'s interviewability predicate — the
  interview never starts, so the composer never has to decide whether to
  invent a primary or skip the competency

#### Scenario: Restoring a question makes the competency, and the project, interviewable again

- GIVEN the same project, with a question added back to the emptied
  competency
- WHEN an interview entry point is attempted again
- THEN the project is interviewable and the composer proceeds normally for
  that competency, asking the restored question as its sole primary

### Requirement: Potential Composes And Starts Through The Same Adaptive Engine

A project whose `assessment_type` is `potential` MUST compose and start its interview through the
same adaptive engine, the same prompt template, and the same `POST /start` flow as `standard`.
There MUST be NO potential-specific prompt variant, NO fixed-sequence or verbatim-order block, NO
`framework_potential_questions` model, and NO template edit; therefore the `prompt_version`
(`conversation.prompt_version`) MUST NOT change because of this capability.

For `potential`, the BARS indicators and anchor texts `{5,3,1}` of each competency (MTG, LAT)
MUST be resolved role-less (`role_id IS NULL`) from the project's pinned framework revision. A
`potential` project has no role (`role_code` is null by rule); composition MUST NOT require one,
and the system MUST NOT fabricate, infer, or default a role for it.

The authored `project_questions` per competency MUST be injected as the primary questions exactly
as for `standard`; their count is a maximum (see "Potential Question Cap Is A Maximum, Never A
Fixed Count"; that requirement is not restated here). The follow-up budget
(`conversation.followup_budget`) and the clamped minimum-question floor (`effectiveMinimum`,
`min(configured, primaries + budget)`, floor 1) MUST be the same values and rules as for
`standard`. STAR coverage, same-episode constraint, advance rule, nudge enforcement, language
selection and the opening greeting MUST behave as for `standard`.

#### Scenario: A potential project starts and the provider receives a composed prompt

- GIVEN a published, interviewable `potential` project (no role) whose pinned revision holds
  role-less MTG and LAT BARS indicators, and a candidate with a valid session
- WHEN the candidate calls `POST /start`
- THEN the response is `201`
- AND the provider payload carries a `system_prompt` composed from the role-less MTG/LAT
  indicators and anchor texts of the pinned revision and from the project's authored primaries
- AND `question_context.prompt_version` equals the same non-null version string `standard` uses

#### Scenario: Potential resumes an in-progress interview

- GIVEN a `potential` candidate whose status is `in_corso` with an existing interview session
- WHEN the candidate calls `POST /start` again (resume path)
- THEN the resume succeeds through the same flow as `standard`, composing from the role-less
  indicators, and no `assessment_type_not_supported` or `composition_error` is returned

#### Scenario: Composition for potential needs no role

- GIVEN a `potential` project with `role_code = null`
- WHEN `SystemPromptComposer::compose()` is invoked for competency MTG with no role identifier
- THEN indicators are loaded with `role_id IS NULL` for the pinned revision and MTG
- AND no role lookup is performed and no exception about a missing role is raised

#### Scenario: Role-less lookup never returns role-scoped indicators

- GIVEN the pinned revision holds an MTG indicator set with `role_id IS NULL` and no
  role-scoped MTG rows are relevant to the project
- WHEN the potential prompt is composed for MTG
- THEN only rows with `role_id IS NULL` appear in the prompt; no indicator of any role appears

#### Scenario: Potential question count and minimum follow the shared rules

- GIVEN a `potential` competency with 1 authored primary question, follow-up budget 4 and a
  configured minimum of 6
- WHEN the prompt is composed
- THEN the stated minimum is clamped to `min(6, 1 + 4) = 5`
- AND no number higher than 5 appears as a minimum anywhere in the prompt

#### Scenario: No potential-specific template content

- GIVEN a `standard` and a `potential` prompt composed from equivalent inputs
- WHEN their template sections (STAR, advance rule, nudge, follow-up budget) are compared
- THEN the sections are textually identical; only catalogue-derived content (competency,
  indicators, anchors, questions, language) differs

### Requirement: Assessment Type Default-Deny Applies Only To Unknown Types

`POST /start` MUST answer `422` with error code `assessment_type_not_supported` if and only if
the project's `assessment_type` is not a case of the `AssessmentType` enum (currently `standard`
and `potential`). Both enum cases MUST proceed. The check MUST be an exhaustive match against the
enum with no permissive default: a value outside the enum is denied, and adding an enum case in
the future MUST require an explicit decision about its composition path (it MUST NOT silently
inherit the `standard` or the `potential` behavior).

The check MUST apply on BOTH the fresh-start path and the resume (`in_corso`) path, and MUST run
before any state change (no session created, no status transition, no counter incremented) and
before any provider call. The error code set of the endpoint is otherwise unchanged and no
OpenAPI change is introduced.

(Replaces the previous behavior, outside this spec's live text, where every `assessment_type`
other than `standard` answered `assessment_type_not_supported`, including `potential`.)

#### Scenario: Unknown assessment type is denied on fresh start

- GIVEN a project whose stored `assessment_type` is a value outside the `AssessmentType` enum
- WHEN the candidate calls `POST /start`
- THEN the response is `422` with code `assessment_type_not_supported`
- AND no interview session exists, the candidate status is unchanged, and no provider call was made

#### Scenario: Unknown assessment type is denied on resume

- GIVEN a candidate with status `in_corso` on a project whose `assessment_type` is outside the enum
- WHEN the candidate calls `POST /start`
- THEN the response is `422` with code `assessment_type_not_supported`
- AND no state changed and no provider call was made

#### Scenario: Both enum cases pass the guard

- GIVEN one `standard` and one `potential` interviewable project
- WHEN each candidate calls `POST /start`
- THEN neither response is `assessment_type_not_supported`

#### Scenario: Standard without a role remains a composition error

- GIVEN a `standard` project whose role cannot be resolved in the pinned revision
- WHEN the candidate calls `POST /start`
- THEN the response is `422` with code `composition_error`
- AND no session is created and no provider call is made

### Requirement: Potential Competency Without BARS Rows Fails Explicitly

If the project's pinned revision holds zero role-less BARS indicator rows for any competency the
`potential` interview must compose (MTG or LAT), composition MUST fail with `CompositionException`
and `POST /start` MUST answer `422` with code `composition_error`. The system MUST NOT create an
interview session, MUST NOT call the provider, and MUST NOT compose a prompt that carries an empty
indicator or anchor section.

#### Scenario: Missing MTG rows in the pinned revision

- GIVEN a `potential` project whose pinned revision has no role-less MTG BARS rows
- WHEN the candidate calls `POST /start`
- THEN the response is `422` with code `composition_error`
- AND no session exists and no provider call was made

#### Scenario: Missing LAT rows fail even when MTG is complete

- GIVEN a `potential` project whose pinned revision has MTG rows but no role-less LAT rows
- WHEN the candidate starts the interview and composition reaches LAT
- THEN the response is `422` with code `composition_error`
- AND no provider call was made for the failing competency

#### Scenario: The failure message is readable for a role-less lookup

- GIVEN the same missing-rows condition
- WHEN the exception message is produced
- THEN it names the competency and the pinned revision and states that the lookup was role-less,
  without printing a null or empty role identifier

### Requirement: Standard Prompt Is Byte-Identical Across This Change

The composed system prompt and `prompt_version` for every `standard` input combination MUST be
byte-for-byte identical before and after this change. Widening composition to accept a role-less
lookup MUST NOT alter any character of the `standard` output, any template section, the clamp,
or the logic that reads `project_questions`.

#### Scenario: Standard snapshot is unchanged

- GIVEN a snapshot of the composed `standard` prompt captured before the change for a fixed input
  set (role, competency, revision, language, budget, minimum, nudge_min_chars)
- WHEN the same inputs are composed after the change
- THEN the prompt string equals the snapshot byte for byte
- AND `prompt_version` equals the snapshot value

#### Scenario: Existing standard tests pass unmodified

- GIVEN the pre-existing C8 test suite for `standard`
- WHEN it runs against the changed code
- THEN every pre-existing `standard` test passes without edits to its assertions

### Requirement: Potential Scoring And Completion Parity

A `potential` interview MUST flow through the same scoring, reliability, completion gate, retry
and delivery rules as `standard`: BARS scores on the discrete set `{1,2,3,4,5,-1}` with `-1`
excluded from the competency mean, `reliability = assessed / total` indicators, completion gate at
>= 90% valid competencies (`completato` at or above, `pending` below, exactly one retry, then
definitive `completato`), and a webhook payload of the same shape as `standard`. This capability
introduces no `potential`-specific scoring, threshold, retry, or payload rule; the normative text
lives in the `scoring` and webhook capabilities and is not duplicated here.

#### Scenario: A potential interview reaches completato through the shared gate

- GIVEN a `potential` interview over MTG and LAT whose transcript yields valid scores for both
- WHEN the interview ends and the scoring job runs
- THEN the candidate reaches `completato` through the same completion gate used by `standard`
- AND the evaluation webhook is delivered with the standard payload shape and records
  `framework_version`, `model_version`, `prompt_version` and timestamp

#### Scenario: A potential evaluation below the gate follows the standard retry rule

- GIVEN a `potential` evaluation where fewer than 90% of competencies are valid
- WHEN the scoring job completes
- THEN the candidate is `pending` and the webhook carries partial data
- AND exactly one retry is performed, after which the candidate is `completato` (definitive)

### Requirement: Docs Alignment For Adaptive Potential (Documentation)

The binding domain documents MUST be aligned with the adaptive decision so they no longer
describe `potential` as a fixed or more rigid flow. The wording "up to N questions (a
platform-configured maximum, default 4)" MUST replace every "4 fixed questions"-style claim, and
the Flow description MUST NOT claim a more rigid structure than `standard`. The edits are:

| File | Location | Required change |
|---|---|---|
| `docs/app_description/02-domain/03-assessment-types.md` | lines 23-24 | Question count reads "up to N, a platform-configured maximum"; the "Flow" row no longer says "more rigid structure" and states that `potential` uses the same adaptive flow |
| `docs/app_description/06-acceptance-criteria/01-acceptance-scenarios.md` | SA-08, lines 75-80 | "up to N predefined questions (maximum)", with no fixed-count or fixed-order assertion |
| `docs/app_description/01-product-and-journeys/01-product-overview.md` | line 93 | Same "up to N, a maximum" wording |

These are documentation edits only: no behavior beyond this delta is introduced by them.

#### Scenario: No document claims a fixed or rigid potential flow

- GIVEN the three files above after the change
- WHEN they are searched for "4 fixed", "fixed questions", and "more rigid structure" in the
  context of `potential`
- THEN no match remains and each file states the count as a maximum

### Requirement: OpeningTextComposer Re-Interview Variant (Neutral)

When a competency is asked again because an evaluation retry (RT-B) reset its session, the
`OpeningTextComposer` MUST compose the opening greeting under a NEW neutral `reinterview`
variant, distinct from the existing `retry` variant. The existing `retry` variant (bounded
single re-offer after a provider error) apologizes for a technical failure and MUST NOT be
used for an evaluation retry: the candidate did nothing wrong and nothing broke. The
`reinterview` variant MUST tell the candidate, neutrally, that they are continuing the interview
with the remaining topics, MUST NOT apologize, MUST NOT mention scores, evaluation results,
"invalid" or "failed" competencies, and MUST NOT read as a first-time greeting. Locale keys MUST
exist for at least `it` and `en` alongside `opening.first` / `.next` / `.resume` / `.retry`.
It MUST respect the existing anti-leak rule (no BARS anchor or indicator text) and MUST carry a
`prompt_version`.

Variant precedence, highest first: `resume` > `retry` > `reinterview` > `first` > `next`. A
session that is being resumed mid-conversation (a live `in_corso` session, which re-issues the
provider session) keeps `resume`; a session that ALSO qualifies for the bounded provider-error
re-offer (it ended in `error` during the re-interview and was re-offered) keeps the existing
`retry` variant; otherwise, whenever the participant's Evaluation has `retry_attempt = true`
(read org-scoped, through the ambient tenant scope), the `reinterview` variant applies. Sessions
of the first interview, and every participant without an authorized retry, MUST keep the
`first` / `next` / `resume` / `retry` selection exactly as before.

This variant needed production code (an additional opening key and a controller arm), which
supersedes the design's earlier claim that the neutral re-interview opening needed none: a
session reset to `pending` otherwise resolves to `next`, the authored primary verbatim with no
greeting. The variant is wording only: it does not change the composed system prompt, and
`conversation.prompt_version` is NOT bumped for it.

#### Scenario: A retry-reset competency composes the reinterview variant

- GIVEN a competency session reset to `pending` by an evaluation retry authorization
- WHEN `OpeningTextComposer.compose()` runs for its `/start`
- THEN the `reinterview` variant is selected, not `first`, `next`, `resume` or `retry`

#### Scenario: The reinterview copy exists in it and en and does not apologize

- GIVEN the `reinterview` variant for a project with `language = 'it'` and, separately, `'en'`
- WHEN `opening_text` is composed
- THEN a non-empty, language-correct string is produced for both locales
- AND it contains no apology wording and no reference to scores, results or failed competencies

#### Scenario: The reinterview copy leaks no BARS content

- GIVEN a competency with BARS indicators, reset by a retry
- WHEN `opening_text` is composed under the `reinterview` variant
- THEN it contains no indicator or anchor text

#### Scenario: A mid-conversation resume inside a retry keeps the resume variant

- GIVEN a competency reset by an evaluation retry whose re-interview session is `in_corso` and is resumed
- WHEN its opening is composed
- THEN the existing `resume` variant is selected, not `reinterview`

#### Scenario: A provider-error re-offer inside a retry keeps the retry variant

- GIVEN a competency reset by an evaluation retry whose session then ended in `error` and was re-offered by the bounded single re-offer
- WHEN its opening is composed
- THEN the existing `retry` variant is selected

#### Scenario: First-interview competencies are unaffected

- GIVEN a participant with no evaluation retry
- WHEN any opening is composed
- THEN the variant is selected exactly as before and is never `reinterview`

### Requirement: Composed Prompt Is Byte-Identical Across The Move To Stored Fragments

For every input combination covered by the golden set, the prompt composed from the database-resolved baseline prompt
set MUST be byte-for-byte identical to the prompt composed by the pre-change composer. The golden set is: 17
composer-level cases (G01 to G17: budget, nudge and phrase variants, the clamp at 0, authored primaries from 0 to 6,
resumed openings, the fallback opening, a role-less `potential` case with the final phrase, an injection case, and
configured minimums of 99 and -3) and 3 HTTP-level cases (H1 standard `en` fresh, H2 standard `it` resume, H3
`potential` `it` on the last competency), captured on the pre-change tree; later additions are new fixtures and never
change an existing one: G18 and G19 (the continuation clause, `en` and `it`) and H4 (the second competency over HTTP)
for "A Later Competency Does Not Greet Again", and G20 (a prompt with an override). Fixtures MUST be captured once, MUST
NOT be overwritten by the capture tool, and MUST be pinned by a directory hash in the test; adding a fixture re-pins
that hash in one place and changes no existing fixture. The goldens MUST pass against both prompt sources. The harness MUST prove it can
fail: mutating one byte of a fixture makes the comparison fail. Across the template test matrix, every fragment key except
`label.override` MUST be rendered at least once, and `label.override` MUST be rendered only when an override is composed.

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

When the fragment set cannot be resolved (no active set, more than one active set, a missing or unknown key, a missing
locale, a seal mismatch, or a template or override that violates its contract), `/start` MUST answer HTTP 422 with the existing
`composition_error` code. Resolution MUST run inside the existing composition `try`, before the session row is
created and before any new provider session is issued, so a failure creates no `InterviewSession` row and issues no
new provider session. The `db` source MUST NOT fall back to the baseline text, another set or another locale. The failure MUST be reported
(it affects every candidate). A failure of the infrastructure while resolving, such as a database error, is not a
resolution failure: it MUST surface as a server error (500), never as a 422 and never as the baseline text. No new API
error code and no OpenAPI change are introduced. On the resume path the existing
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

#### Scenario: Two active sets block composition

- GIVEN two prompt sets are active because the one-active index was bypassed
- WHEN `/start` is called
- THEN HTTP 422 `composition_error` is returned and neither set is used

#### Scenario: A failing database is not a composition error

- GIVEN the database fails while the active set is being resolved
- WHEN `/start` is called
- THEN the response is a server error (500) and no baseline text is composed

#### Scenario: A resumed interview that fails composition releases the outgoing session once

- GIVEN a live `in_corso` session and an unresolvable active set
- WHEN `/start` resumes it
- THEN 422 is returned and the outgoing provider session is torn down exactly once, as for any composition failure

---

### Requirement: Prompt Source Switch

`config('conversation.prompt_source')` (environment variable `CONVERSATION_PROMPT_SOURCE`) MUST accept `db` and
`baseline`. With `db` the active prompt set composes the prompt. With `baseline` the call site MUST pass no fragment
set and the composer MUST render the baseline text, without a code change or a database read of the prompt set. Any other value, including an empty value and a
differently-cased `db` or `baseline`, MUST fail composition with the same 422 `composition_error` rather than silently
choosing a source. The default MUST be `db`.

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
role-specific row wins over the role-less row). The override MUST be appended verbatim after every other section is
rendered, so no token in it is ever substituted. A body with no visible character (only whitespace or zero-width
spaces), or whose bytes are not valid UTF-8, MUST count as no override. The `baseline` source MUST NOT print an
override.

#### Scenario: An override appears at the specified position only

- GIVEN a competency with an override body
- WHEN the prompt is composed
- THEN the override text appears after COVERAGE TOPICS and before STAR COVERAGE PROTOCOL and every other section is unchanged

#### Scenario: A competency with no override composes exactly the default

- GIVEN a competency with no override row
- WHEN the prompt is composed
- THEN the output is identical to the golden fixture for the same inputs

#### Scenario: A blank override is no override

- GIVEN an override body that contains only whitespace or zero-width spaces
- WHEN the prompt is composed
- THEN the output is identical to the output composed without an override and no `label.override` heading appears

#### Scenario: The baseline source never prints an override

- GIVEN `CONVERSATION_PROMPT_SOURCE=baseline` and an active set carrying an override for the competency
- WHEN `/start` composes
- THEN the prompt contains no override section

#### Scenario: The advance rule is unaffected by an override

- GIVEN a competency with an override
- WHEN the prompt is composed
- THEN the text from `ADVANCE RULE:` to the end equals the text composed without the override

---

### Requirement: A Later Competency Does Not Greet Again

Every `/start` opens a NEW provider session whose model has no memory of an earlier welcome. For a FRESH start of a
competency whose ordinal in the project's order is greater than 1, the OPENING paragraph MUST end with the
`opening.continuation` fragment (no tokens) as its last sentence, joined to the preceding text by one space, telling the
avatar that the candidate has already been welcomed and must not be greeted, welcomed or introduced to again. The flag
MUST be keyed on the competency's ordinal, not on whether the participant has started before (a candidate redoing
competency 1 after an error is not on a later competency). A resumed opening, the fallback opening and every opening of
competency 1 MUST be byte-identical to what they were before the clause existed. The spoken opening (the authored
primary question) MUST NOT be modified.

#### Scenario: The second competency carries the clause

- GIVEN a standard project with two competencies and a fresh start of the second
- WHEN `/start` composes
- THEN the OPENING paragraph ends with the `opening.continuation` text and nothing else in the prompt moves

#### Scenario: The first competency never carries the clause

- GIVEN a fresh start of the first competency, including for a candidate recovered from an error
- WHEN `/start` composes
- THEN the prompt contains no continuation clause

#### Scenario: A resume of a later competency never carries the clause

- GIVEN a resumed session of the second competency
- WHEN `/start` composes
- THEN the prompt contains no continuation clause
## Coverage Note

The following paths MUST be held to ~95% test coverage (unit / Pest feature tests, no HTTP):

- `BarsIndicatorLoader::load()` — filters by both `role_id` and `competency_id`; cross-role contamination impossible
- `ConversationService::composePrompt()` — all input combinations: `standard` and role-less `potential`, it/en, N=0/1/2/4, nudge_min_chars=0/N, missing translation hard-fail (HTTP 422)
- `SystemPromptComposer::effectiveMinimum()` — the clamp, exercised as a GRID over
  `budget ∈ {0,1,2,4,8}` × `configuredMinimum ∈ {1,2,4,6,10}`, asserting for every pair that
  the stated minimum is `≤ budget + 1` AND that no higher value appears anywhere in the
  prompt. A negative-space assertion is required here: proving the correct number is present
  does not prove a wrong one is absent.
- STAR section — five elements named, Action/Result emphasis, the inapplicable-element
  escape, the same-episode constraint asserted at exactly one occurrence
- Advance rule — the minimum present as a conjunct in BOTH branches (phrase supplied and
  phrase absent), asserted against the ADVANCE RULE section specifically. An assertion
  satisfied by the follow-up budget sentence alone does NOT cover this: both sections mention
  the follow-up budget, so a substring test for `follow-up budget` passes even if the advance
  section lost its clause entirely.
- `prompt_version` non-null and changes when template version changes
- `.env.example` ↔ `config/conversation.php` parity for all `CONVERSATION_*` keys, and the
  config-sanity invariant `min_questions ≤ followup_budget + 1`. A parity guard MUST be
  observed to fail at least once against a deliberately desynchronised value; a guard never
  seen to fail is not a guard.
- `SystemPromptComposer::compose()` role-less path (`role_id IS NULL`, `potential`) — the same grid discipline as the role-scoped path
- The controller's assessment-type default-deny branch — exercised on BOTH the fresh-start and the resume (`in_corso`) paths
- `QuestionContext` widening — `system_prompt` and `prompt_version` non-null after composition
- `/start` response includes `question_context.prompt_version`
- Provider payload shape (`Http::fake` assertion) — PR-gated
- `anchor_translation_missing` hard-fail blocks session creation (HTTP 422)

Provider-compliance scenarios (avatar follow-up count, nudge slot non-consumption, end_phrase timing) MUST be in the `@ai` integration suite, NOT in the Pest feature suite.
