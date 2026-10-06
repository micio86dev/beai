# Proposal: Potential Assessment Interview

## Intent

A `potential` project (MTG/LAT only) can be created, configured, published and entered by a
candidate today, but the interview itself cannot start: `POST /start` answers
`422 assessment_type_not_supported` (`api/app/Http/Controllers/Candidate/InterviewController.php:175`).
Even without that guard, composition would fail, because the controller resolves a `Role` from
`project.role_code` (`:883-890`), which is null by rule for `potential`, and
`SystemPromptComposer::compose()` requires `int $roleId` (`:103`).

So the product sells two assessment types and delivers one. Every other layer is already
potential-aware: catalogue data (`POTENTIAL.json`, MTG/LAT defaults), project composition and
question caps, the interviewability predicate, SSO/M2M ingress, the role-less
`BarsIndicatorLoader` predicate, and role-less scoring in `ScoreEvaluationJob`. The interview
engine is the only missing link.

Success: a candidate on a `potential` project completes an adaptive interview over MTG/LAT, the
evaluation is scored, gated and delivered exactly like `standard`, and the `standard` path is
provably unchanged.

## Owner Decisions (settled)

- **Approach 1, ADAPTIVE.** `potential` reuses the existing adaptive engine. The project's
  `project_questions` per competency are a MAXIMUM, never a fixed count. No fixed-sequence block,
  no potential-specific prompt variant. The `standard` composed prompt and code path MUST remain
  byte-identical.

### Explicit assumptions (assumed same as standard; the owner may override)

| # | Assumption |
|---|---|
| A1 | Follow-up budget for `potential` equals the standard one (`conversation.followup_budget`). |
| A2 | Minimum-questions floor uses the same existing clamp (`effectiveMinimum`, `min(configured, primaries + budget)`, floor 1). |
| A3 | The catalogue default MTG/LAT question text is treated as final. Expert translation review stays under open decision #6 and is out of scope. |
| A4 | Same BARS 1-5 (+ `-1`) scoring, same `reliability`, same 90% completion gate, same exactly-one-retry rule, same webhook payload shape. |
| A5 | Pause, nudge and proctoring behave identically to `standard`. |
| A6 | No `potential` demo seed in this change. |
| A7 | Drifting wording in `docs/app_description` is aligned with the spec: "up to N, a platform-configured maximum". |

## Scope

### In Scope

- Replace the W1 guard with **default-deny for UNKNOWN types only**: `standard` and `potential`
  (the `App\Enums\AssessmentType` cases) proceed; any other value still answers
  `422 assessment_type_not_supported`, on both fresh-start and resume paths, before any state
  change or provider call.
- Make the role **nullable along the composition path**: the controller resolves a `Role` only for
  `standard` (a missing role on `standard` remains `composition_error`) and passes `null` for
  `potential`; `SystemPromptComposer::compose()` accepts `?int $roleId` and forwards it to the
  already role-less-aware `BarsIndicatorLoader::forRoleCompetency()`.
- Keep the no-indicators failure explicit: zero MTG/LAT BARS rows in the project's pinned revision
  raise `CompositionException` and surface as `422 composition_error`, no session, no provider call.
- Pest coverage (strict TDD): invert the two W1 tests in
  `api/tests/Feature/C8/InterviewStartCompositionTest.php` (:632, :675) into "potential starts" /
  "potential resumes"; add an unknown-type default-deny test; a composer unit test for the
  role-less path; a byte-identical snapshot assertion of the composed `standard` prompt; a
  potential end-to-end test through scoring and the completion gate.
- Spec delta to `interview-conversation`.
- Docs alignment (A7): `docs/app_description/02-domain/03-assessment-types.md:23-24`,
  `06-acceptance-criteria/01-acceptance-scenarios.md` SA-08 (:75-80),
  `01-product-and-journeys/01-product-overview.md:93`.

### Out of Scope

- A potential-specific prompt variant, fixed-order/verbatim enforcement, or any template edit
  (and therefore no `conversation.prompt_version` bump).
- A per-type follow-up budget or minimum floor (A1, A2).
- Server-driven per-turn sequencing or a `framework_potential_questions` model.
- Expert review or translation of MTG/LAT questions and anchors (open decision #6).
- Potential demo seed (A6) and any frontend/backoffice change (none required; backoffice already
  authors potential projects; the candidate app has no branch on `assessment_type`).
- Enriching `AdminEvaluationSerializer::indicatorCatalogue()` for role-less reports (it already
  degrades to the stored `indicator_text`; cosmetic follow-up only).
- Retry semantics (open decision #4) and any webhook or report schema change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `interview-conversation`:
  - REMOVE the Out of Scope entry "`potential` / SA-08 flow — deferred" (spec lines 24-28),
    including "No `potential`, no `framework_potential_questions` model, no fixed-sequence block"
    as a deferral; the "no fixed-sequence block" constraint becomes a positive requirement.
  - Update the Purpose so the adaptive path covers `standard` AND `potential`.
  - ADD a requirement: `potential` composes through the same adaptive engine and template, with
    BARS indicators resolved role-less (`role_id IS NULL`) from the project's pinned revision.
  - REPLACE the W1 behavior: `assessment_type_not_supported` is returned only for a type outside
    the `AssessmentType` enum (default-deny for unknown types), on fresh-start and resume.
  - ADD a requirement: the composed `standard` prompt is byte-identical before and after this change.
  - ADD a scenario: a potential competency with no BARS rows in the pinned revision fails with
    `composition_error`, no session, no provider call.
  - KEEP "Potential Question Cap Is A Maximum" and "A Zero-Primary Competency Never Reaches
    Interview" (lines 729-781) unchanged; update the Coverage Note so `ConversationService::composePrompt()`
    input combinations include `potential`.

No requirement change in `scoring`, `project-config`, `framework-catalog`, or webhook capabilities:
they are already potential-aware (A4).

## Approach

Exploration Approach 1. The change is an unlock, not new machinery:

1. **Guard**: replace `$project->assessment_type !== 'standard'` with a check that the value maps to
   an `AssessmentType` case (`AssessmentType::tryFrom(...) === null` -> 422). Same position, same
   error code, same "before any state change" property. The interviewability gate ordering comment
   (:198-200) is updated accordingly.
2. **Role resolution**: in `composePromptForCompetency`, branch on the type: `standard` keeps the
   exact current `Role::where(code, revision)` lookup and its `composition_error` on miss;
   `potential` passes `roleId: null`. No other code path changes.
3. **Composer**: widen `int $roleId` to `?int $roleId`; the exception message renders a role-less
   lookup readably. No template, section, or clamp code is touched, which is what keeps the
   `standard` prompt byte-identical by construction (and a snapshot test proves it).
4. **Questions**: unchanged. `primaryQuestionsFor()` already reads `project_questions` per
   competency type-agnostically, and the existing clamp caps the stated minimum at
   `primaries + budget`.
5. **Scoring/delivery**: unchanged; covered by an end-to-end Pest test only.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `api/app/Http/Controllers/Candidate/InterviewController.php` | Modified | Guard -> enum default-deny; role lookup only for `standard`, `null` for `potential`; comments updated |
| `api/app/Services/Conversation/SystemPromptComposer.php` | Modified | `?int $roleId`; exception message |
| `api/tests/Feature/C8/InterviewStartCompositionTest.php` | Modified | Invert two W1 tests; unknown-type default-deny test; potential no-BARS test |
| `api/tests/...` (composer unit + potential E2E + standard snapshot) | New | Role-less compose, byte-identical standard prompt, potential through scoring and completion gate |
| `openspec/changes/potential-assessment-interview/specs/interview-conversation/spec.md` | New (delta) | See Capabilities |
| `docs/app_description/02-domain/03-assessment-types.md` | Modified | "Up to N ... maximum"; "Flow" row no longer claims a more rigid structure |
| `docs/app_description/06-acceptance-criteria/01-acceptance-scenarios.md` | Modified | SA-08 "up to N predefined questions (maximum)" |
| `docs/app_description/01-product-and-journeys/01-product-overview.md` | Modified | Same wording alignment |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Standard path regression from the signature widening or the role-lookup branch | Low | Byte-identical snapshot test of the composed `standard` prompt captured before the change (RED-first); all existing C8 tests stay green unchanged |
| A pinned revision with missing MTG/LAT BARS rows | Low | `CompositionException` -> `422 composition_error`, no session, no provider call; dedicated test. `POTENTIAL_CATALOG_INCOMPLETE` already blocks creation on an incomplete catalogue |
| Configured minimum exceeds primaries + budget (HeyGen `MAX_DURATION_REACHED`) | Low | Existing `effectiveMinimum` clamp applies unchanged; potential test asserts the stated minimum is clamped with 1 primary |
| "Adaptive" does not match the domain doc's "more rigid structure" | Med | Owner chose adaptive; docs aligned (A7). Rigidity would be a later Approach 2 change |
| Unknown future `AssessmentType` case silently reaching composition | Low | Default-deny matches the enum; adding a case requires an explicit decision here. Note: a NEW enum case would pass the guard, so the role branch must treat any non-`standard` case deliberately (design phase to decide: explicit `match` with no default) |
| Assumptions A1-A6 overridden later by the owner | Med | Each is isolated (config or follow-up change); none is baked into a template |

## Rollback Plan

Revert the single api PR (controller, composer, tests) and the wrapper docs/spec commit. Reverting
restores the W1 guard, so `potential` projects answer `assessment_type_not_supported` again. No
migration, no data change, no prompt version bump, so no persisted session or evaluation needs
repair; any potential evaluation produced meanwhile stays valid (scoring was already potential-aware).

## Dependencies

- Published catalogue revision containing role-less MTG/LAT BARS rows (already seeded by
  `FrameworkCatalogSeeder`).
- No new package, no migration, no openapi change expected (error code set is unchanged).

## Size Forecast

- api: ~200-350 authored changed lines (production ~40-60; tests ~150-250; spec delta and docs in
  the wrapper ~40-60).
- frontend / backoffice: 0.
- One slice under the 400-line budget. Delivery strategy `auto-chain` will not need to chain unless
  the forecast is exceeded during apply.

## Success Criteria

- [ ] `POST /start` on a `potential` project (fresh and resume) returns 201 and the provider body
      carries a prompt composed from role-less MTG/LAT BARS indicators and the project's authored
      primaries.
- [ ] Any value outside `AssessmentType` returns `422 assessment_type_not_supported` with no
      session and no provider call.
- [ ] The composed `standard` prompt is byte-identical to the pre-change snapshot; all existing C8
      tests pass unmodified.
- [ ] A potential competency with no BARS rows in the pinned revision returns `422 composition_error`.
- [ ] A potential interview reaches `completato` through the same scoring, reliability and 90%
      completion gate, and the evaluation webhook has the standard shape.
- [ ] `interview-conversation` spec no longer lists `potential` as out of scope; docs say "up to N,
      a maximum".
- [ ] Coverage stays >= 85% overall and ~95% on the composer/loader paths.
