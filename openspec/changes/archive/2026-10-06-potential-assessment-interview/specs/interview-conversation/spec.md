# Delta for Interview Conversation

Change: `potential-assessment-interview`. Owner decision (settled): ADAPTIVE. The project's
`project_questions` per competency are a MAXIMUM; there is no fixed sequence and no
potential-specific prompt variant. The composed `standard` prompt stays byte-identical.
Assumptions A1-A7 of the proposal stand (same follow-up budget, same minimum clamp, same
scoring and completion gate, same pause/nudge/proctoring, no potential seed).

## Non-requirement edits to the live spec (applied at archive)

These sections of `openspec/specs/interview-conversation/spec.md` are not requirement blocks and
cannot be expressed as ADDED/MODIFIED entries. They MUST be edited when this delta is archived:

1. **Purpose** (lines 3-11): "coverage-driven adaptive follow-up questioning for `standard`
   sessions (SA-02)" becomes "... for `standard` AND `potential` sessions (SA-02)". The
   composed-prompt-is-an-instruction paragraph is unchanged.
2. **Out of Scope** (lines 22-28): the entry "`potential` / SA-08 flow — deferred to a future
   slice" is REMOVED in full, including the sentence "C8 delivers the `standard` adaptive path
   ONLY. No `potential`, no `framework_potential_questions` model, no fixed-sequence block."
   Its content is superseded by the requirements below. The constraint "no
   `framework_potential_questions` model and no fixed-sequence block" survives as the positive
   requirement "Potential Composes Through The Same Adaptive Engine", not as a deferral. The
   section then lists no entries (or is dropped, per archive convention).
3. **Coverage Note** (line 787): the `ConversationService::composePrompt()` input combinations
   gain `potential` (role-less) alongside `standard`. Two paths join the ~95% set: the
   role-less `SystemPromptComposer::compose()` path, and the controller's assessment-type
   default-deny branch on both the fresh-start and resume paths.
4. **Requirement "Potential Question Cap Is A Maximum, Never A Fixed Count"** (lines 729-743) and
   **"A Zero-Primary Competency Never Reaches Interview"** (lines 745-781) are KEPT UNCHANGED.
   The first still says it "corrects this capability's Out of Scope note"; after item 2 that
   note no longer exists, so the archive step MAY trim that clause, but MUST NOT alter the
   requirement's normative text or scenarios.

## ADDED Requirements

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

## REMOVED Requirements

None. (The deferral of `potential` lives in the non-requirement "Out of Scope" section; its
removal is specified under "Non-requirement edits to the live spec" above.)
