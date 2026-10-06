# Design: Potential Assessment Interview

## Technical Approach

The change is an unlock, not new machinery (proposal, Approach 1, ADAPTIVE). Every layer after
composition is already potential-aware; the interview engine has two blockers:

1. `InterviewController::start()` answers `422 assessment_type_not_supported` for anything that
   is not the literal `'standard'` (`api/app/Http/Controllers/Candidate/InterviewController.php:175`).
2. `composePromptForCompetency()` resolves a `Role` from `project.role_code` unconditionally
   (`:883-890`), which is null by rule for `potential`, and `SystemPromptComposer::compose()`
   requires `int $roleId` (`api/app/Services/Conversation/SystemPromptComposer.php:103`).

The fix replaces the literal guard with enum default-deny, branches the role resolution with an
exhaustive `match` on `App\Enums\AssessmentType`, and widens the composer to `?int $roleId`. The
composer forwards the value unchanged to `BarsIndicatorLoader::forRoleCompetency()`, which already
emits `whereNull('role_id')` for `null` (`BarsIndicatorLoader.php:83-97`). No template, section,
clamp, budget, question, scoring, webhook, migration, `prompt_version` or OpenAPI change.

Verified facts that make this safe:

| Fact | Evidence |
|---|---|
| Loader is role-less aware and Postgres-correct (`whereNull`, not `= NULL`) | `BarsIndicatorLoader.php:90-94` |
| Composer template text never mentions the role; `$roleId` is used only for the loader call and the exception message | `SystemPromptComposer.php:114`, `:118` (only two uses) |
| Scoring already resolves `roleId = null` when `role_code` is null | `ScoreEvaluationJob.php:310-343`, covered by `tests/Feature/Jobs/RoleScopedIndicatorsTest.php` (b) |
| Potential projects carry `role_code = null` by write-time validation and ingress | `ValidatesProjectComposition.php:186-190`, `EnrolCandidate.php:112`, `RedeemReusableInterviewLink.php:256`, `SsoExchangeController.php:442` |
| Interviewability and primaries are type-agnostic | no `assessment_type`/`role_code` branch in the interviewability support class; `primaryQuestionsFor()` reads `project_questions` per competency |
| `projects.assessment_type` is an unconstrained `string` column, not an enum cast | `2026_07_17_200001_create_projects_table.php:36`; `Project.php:40` docblock `'standard'\|'potential'` |
| Only one production caller of `compose()` | `InterviewController::composePromptForCompetency()`; other references are tests and `OpeningTextComposer` (docblock only) |

## Architecture Decisions

### D1: Guard becomes enum default-deny, resolved once in `start()`

**Choice**: replace `if ($project->assessment_type !== 'standard')` at `:175` with a resolution of
the stored value to `AssessmentType` (`tryFrom`). `null` (a value outside the enum) answers
`422 assessment_type_not_supported`, in the same position, so it still precedes the template
preflight, the interviewability gate, the transcript harvest, any session write and any provider
call, on both the fresh-start and resume (`in_corso`) paths. The resolved enum is passed into
`composePromptForCompetency()` as a new parameter; it is never re-parsed.
**Alternatives considered**: (a) keep a string allow-list `in_array(..., ['standard','potential'])`
— duplicates the enum, the exact drift `AssessmentType` exists to stop; (b) cast the model
attribute to the enum — an unknown stored value would throw `ValueError` on hydration (500)
everywhere the project is read, far outside this change.
**Rationale**: the enum is the single source of truth for the value set; default-deny keeps the
existing error code and its "before any state change" property for corrupt or legacy rows.

**PHPStan note (must be verified in apply)**: `Project::$assessment_type` is documented as the
literal union `'standard'|'potential'`. PHPStan's backed-enum `tryFrom()` return-type extension may
narrow `tryFrom()` of that union to non-null and report the `=== null` branch as
`identical.alwaysFalse` at level 8. If it does, read the raw stored attribute
(`$project->getAttributes()['assessment_type'] ?? null`), narrow with `is_string()`, then
`tryFrom()`. That is honest: the column is an unconstrained string. Do NOT add `@phpstan-ignore`
and do NOT widen the model docblock (serializers rely on the literal union for their shapes).

### D2: Role resolution is an exhaustive `match` with no `default`

**Choice**: in `composePromptForCompetency()`:

```php
$roleId = match ($assessmentType) {
    AssessmentType::Standard => Role::where('code', $project->role_code)
        ->where('revision_id', $revisionId)
        ->first()?->id,
    AssessmentType::Potential => null,
};

if ($assessmentType === AssessmentType::Standard && $roleId === null) {
    return response()->json(['error' => 'composition_error'], Response::HTTP_UNPROCESSABLE_ENTITY);
}
```

The `standard` arm runs the identical revision-scoped query (`code`, `revision_id`, `first()`), and
a miss is still `composition_error`. The `potential` arm passes `null` and ignores `role_code`.
**Alternatives considered**: (a) `if ($type === Standard) {...} else { null }` — a future enum case
silently lands in the role-less branch; (b) a `match` with `default => throw` — equivalent at
runtime but hides the gap from static analysis; (c) branching on `role_code !== null` like
`ScoreEvaluationJob` — the composition semantic is the assessment type, and a `standard` project
with a null `role_code` must stay `composition_error`, never fall into the role-less set.
**Rationale**: a `match` over an enum with no `default` is checked by PHPStan (`match.unhandled`)
when a case is added, and throws `UnhandledMatchError` at runtime if analysis is bypassed. Adding a
third `AssessmentType` case therefore fails loudly here instead of composing against the wrong
indicator set. This answers the proposal's open risk ("a NEW enum case would pass the guard").

### D3: Composer signature is `?int $roleId`, not a `RoleScope` value object

**Choice**: widen `compose(string $competencyCode, int $roleId, ...)` to `?int $roleId`. Parameter
order, names and defaults are unchanged, so every existing positional and named call compiles
unchanged. The docblock documents `null` as the role-less (`potential`) lookup. The empty-indicator
`CompositionException` message renders `role [none]` for `null` instead of an empty `role []`.
**Alternatives considered**: a `RoleScope` value object (`RoleScope::role(int)`/`RoleScope::roleLess()`)
— more explicit, but `BarsIndicatorLoader::forRoleCompetency(?int ...)` and `ScoreEvaluationJob`
already speak `?int` with the documented null semantics, so a value object would either stop at the
composer boundary (two vocabularies for one concept) or ripple into the loader and scoring, which
are out of scope and already tested.
**Rationale**: follow the existing pattern; the nullable already has one owner (the loader) and one
documented meaning.

### D4: The null-role branch lives in the controller only

**Choice**: the decision "which role, or none" is made once, in
`InterviewController::composePromptForCompetency()` (D2). The composer and loader stay mechanical:
they forward/apply whatever `?int` they receive and never inspect the assessment type.
**Alternatives considered**: deciding inside the composer from a passed `AssessmentType` — couples a
pure prompt builder to project semantics and would make its unit tests carry project state.
**Rationale**: the controller already owns every other per-project resolution (revision, competency
row, primaries, budget); this keeps the composer a pure function of its inputs.

### D5: Missing MTG/LAT BARS rows stay an explicit `composition_error`

**Choice**: no new code. A `potential` competency with zero role-less rows in the project's pinned
revision makes the loader return an empty collection, the composer throws `CompositionException`
(`:116-121`), and the controller's existing catch (`:923-924`) answers `422 composition_error`. This
happens before `createOrResumeSession()` and `issue()`, so no session row and no provider call; on
resume the outgoing provider session is released by the existing branch (`:399-401`). A role-scoped
decoy row for the same competency is never picked up, because `role_id IS NULL` excludes it.
**Alternatives considered**: a dedicated `potential_catalog_incomplete` code — a new machine code is
an OpenAPI change and duplicates `POTENTIAL_CATALOG_INCOMPLETE`, which already blocks creation.
**Rationale**: same failure, same code, same guarantees as a standard role with no BARS rows.

### D6: The standard path is proven byte-identical by a characterization hash captured first

**Choice**: a new Pest test composes a `standard` prompt from fully fixed inputs (fixed role code,
fixed competency code, three fixed indicators with `en` and `it` text, two fixed primaries, budget
4, nudge 120, fixed advance phrase, `SpokenOpening::primary(1)`, explicit
`config(['conversation.min_questions' => 4])`) for `en` and `it`, and asserts
`hash('sha256', $prompt->text)` and `strlen($prompt->text)` against constants. It is committed as
the FIRST commit of the slice, before any production edit: written with placeholder constants, run
RED to read the actual values off the failing expectation on pre-change code, constants filled in,
run GREEN, committed. The same constants must hold, unchanged, after the controller and composer
edits. The capture commit hash is recorded as evidence in tasks.
**Alternatives considered**: (a) a golden `.txt` fixture — readable diffs, but ~150-250 lines per
locale against a 400-line slice budget; (b) a Pest snapshot plugin — not installed
(`composer.json`), and adding a dependency is out of scope; (c) relying on existing C8 tests — they
assert substrings, not bytes.
**Rationale**: a two-line tripwire per locale with zero dependency cost. On a future mismatch the
test author dumps the text locally to diff; a deliberate prompt change updates the constants in the
same commit as its `prompt_version` bump. Note: this pins composer output; the controller change is
covered by every existing C8 `standard` test passing unmodified.

### D7: `AdminEvaluationSerializer::indicatorCatalogue()` role-less enrichment is deferred

**Choice**: no change. For a null `role_code` it returns `[]` (`:339-343`) and the report renders the
stored `indicator_text` from `indicator_scores`, which is the exact verbatim text scored.
**Alternatives considered**: a role-less branch (`whereNull('role_id')`, same revision) — ~10 lines
plus a test, cosmetic only (indicator names), and it touches the admin report schema surface.
**Rationale**: proposal scope; correctness is unaffected. Recorded as a follow-up.

## Data Flow

```
POST /api/candidate/interview/start  (api-candidate JWT, tenant = participant.organization_id)
  │
  ├─ resolveNextCompetency(pid, project)            (tenant-scoped: participant/sessions)
  ├─ D1  AssessmentType::tryFrom(stored type) ── null ──> 422 assessment_type_not_supported
  │                                                         (no write, no provider call, fresh+resume)
  ├─ preflight template ─> interviewability gate (fresh only)
  ├─ revisionId = tryForProject(project)            (project pin; never latest)
  ├─ competency row (code, revisionId) ─> primaryQuestionsFor(project, competencyId)
  ├─ resume? harvest outgoing transcript
  └─ composePromptForCompetency(project, type, ...)
        ├─ revisionId null ─────────────────────────> 422 composition_error
        ├─ D2  match(type)
        │      Standard  ─> Role(code, revisionId)?->id ── miss ──> 422 composition_error
        │      Potential ─> null
        ├─ competency null ─────────────────────────> 422 composition_error
        └─ SystemPromptComposer::compose(roleId: ?int, ...)
              └─ BarsIndicatorLoader::forRoleCompetency(?int, competencyId, revisionId)
                    null ─> WHERE role_id IS NULL     (global catalogue table, no tenant scope)
                    int  ─> WHERE role_id = ?
              empty ─> CompositionException ─────────> 422 composition_error (+ release outgoing on resume)
              ok    ─> ComposedPrompt(text, version)  ─> session row + provider issue ─> 201

... interview turns (unchanged) ... sessions terminal ─> ScoreEvaluationJob (unchanged)
  role_code null ─> roleId null ─> same loader ─> BARS {1..5,-1} ─> reliability ─> 90% gate
  ─> completato | pending (+1 retry) ─> evaluation webhook (unchanged shape)
```

Multi-tenancy (explicit scopes): `participants`, `projects`, `interview_sessions`,
`project_questions` reads stay under the existing `TenantContext`/global scope for the candidate's
organization. `framework_roles`, `framework_competencies`, `framework_bars_indicators` are global
catalogue tables scoped by `revision_id` (the project's own pin), never by organization — unchanged
by this design. No new query crosses tenants.

## File Changes

| File | Action | Description | ~Authored lines |
|------|--------|-------------|-----------------|
| `api/app/Http/Controllers/Candidate/InterviewController.php` | Modify | D1 guard via `AssessmentType`; pass enum to `composePromptForCompetency()`; D2 exhaustive `match`; update W1 comment (`:170-174`), gate-ordering comment (`:198-200`), role comment (`:877-882`), failure-codes docblock | 35-45 |
| `api/app/Services/Conversation/SystemPromptComposer.php` | Modify | `?int $roleId`; docblock; exception message renders `none` for null | 6-10 |
| `api/tests/Unit/C8/StandardPromptCharacterizationTest.php` | Create | D6 hash+length pins for `en` and `it`; committed FIRST, before production edits | 50-60 |
| `api/tests/Unit/C8/SystemPromptComposerTest.php` | Modify | role-less compose returns the role-less rows only (role-scoped decoy excluded); role-less empty set throws `CompositionException` naming `role [none]` | 35-45 |
| `api/tests/Feature/C8/InterviewStartCompositionTest.php` | Modify | invert W1 tests (`:632`, `:675`) into "potential starts" / "potential resumes" (201, provider body carries role-less indicator text and authored primary); unknown-type default-deny on fresh and resume (dataset, raw `DB::table('projects')` update to a bogus value); potential no-BARS (with role-scoped decoy) -> `composition_error`, zero sessions, nothing sent; small `c8SeedPotentialScenario()` helper | 110-140 |
| `api/tests/Feature/Interview/PotentialInterviewEndToEndTest.php` | Create | `/start` on potential (2 competencies, MTG/LAT-typed, role-less 3 indicators each) -> sessions completed with utterances -> `ScoreEvaluationJob` with faked `LLMProvider` -> evaluation completed, participant `completato`, reliability assessed/3, evaluation webhook queued with the standard payload keys; own file-local helpers (no cross-file test functions) | 110-140 |
| `openspec/changes/potential-assessment-interview/specs/interview-conversation/spec.md` | Create | owned by the parallel sdd-spec phase | (wrapper) |
| `docs/app_description/02-domain/03-assessment-types.md`, `06-acceptance-criteria/01-acceptance-scenarios.md`, `01-product-and-journeys/01-product-overview.md` | Modify | A7 wording: "up to N, a platform-configured maximum"; flow no longer "more rigid" | (wrapper) |

api slice total: ~350-440 authored lines (production ~45-55). This sits at the 400-line delivery
budget. Under `auto-chain`, if the running count exceeds ~400, the E2E test file becomes a second
api slice (it depends only on the first slice being merged). The wrapper docs/spec commit is
separate and small.

Not changed (verified): `BarsIndicatorLoader`, `ScoreEvaluationJob`, `AdminEvaluationSerializer`,
`OpeningTextComposer`, conversation templates/lang files, `config/conversation.php`, migrations,
`openapi.json`, frontend, backoffice.

## Interfaces / Contracts

```php
// SystemPromptComposer (only $roleId changes)
public function compose(
    string $competencyCode,
    ?int $roleId,               // null = role-less (potential) lookup, forwarded to the loader
    int $competencyId,
    string $projectLocale,
    int $followUpBudget,
    ?int $nudgeMinChars,
    ?string $advancePhrase = null,
    ?int $minQuestions = null,
    array $primaryQuestions = [],
    ?SpokenOpening $spokenOpening = null,
    ?int $revisionId = null,
): ComposedPrompt;

// InterviewController (private; single call site in start())
private function composePromptForCompetency(
    Project $project,
    AssessmentType $assessmentType,   // new, resolved by the D1 guard
    string $competencyCode,
    ?int $revisionId,
    ?Competency $competency,
    array $primaryQuestions,
    int $followUpBudget,
    SpokenOpening $spokenOpening,
    ?string $advancePhrase = null,
): ComposedPrompt|JsonResponse;
```

HTTP contract: unchanged. Error codes on `/start` remain the existing set
(`assessment_type_not_supported`, `composition_error`, `anchor_translation_missing`, ...). The only
observable change is that a `potential` project now answers 201 instead of
`assessment_type_not_supported`. `question_context.prompt_version` is the same config value.

## Testing Strategy

Strict TDD: RED before GREEN for every behavior; D6 is a characterization pin captured before any
production edit (its first run is RED only because the constants are placeholders).

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Characterization (Unit dir, DB-backed) | `standard` composed text byte-identical for `en` and `it` | D6 sha256 + length constants from pre-change code; first commit of the slice |
| Unit (composer + loader through Postgres) | `compose(roleId: null)` injects only role-less rows; role-scoped decoy for the same competency excluded; empty role-less set -> `CompositionException` with `role [none]` | extend `tests/Unit/C8/SystemPromptComposerTest.php`; real `BarsIndicatorLoader` against Postgres (a double cannot prove `IS NULL` vs `= NULL`) |
| Feature `/start` fresh | potential -> 201, one session, provider body `system_prompt` contains role-less indicator text and the authored primary; stated minimum clamped with 1 primary (A2) | inverted W1 test `:632`; `Http::fake(c8HeygenFake())` |
| Feature `/start` resume | potential `in_corso` -> 201, outgoing ref harvested and released, fresh session issued with composed prompt | inverted W1 test `:675` |
| Feature default-deny | stored type outside the enum -> 422 `assessment_type_not_supported`, zero new sessions, `Http::assertNothingSent()`, on fresh and resume | dataset over both paths; raw `DB::table` update to bypass model validation |
| Feature no-BARS | potential competency with only a role-scoped decoy row -> 422 `composition_error`, zero sessions, nothing sent | new test in the same file |
| Feature regression | all existing C8/C7a `standard` tests | run unmodified; any edit to them is a design violation |
| End-to-end (api) | potential `/start` -> completed sessions -> `ScoreEvaluationJob` -> evaluation completed via the 90% gate, `completato`, reliability, evaluation webhook queued with the standard payload keys | `tests/Feature/Interview/PotentialInterviewEndToEndTest.php`; `LLMProvider` faked; `Queue::fake()` for the webhook job, scoring run synchronously |
| Static | exhaustive `match`, D1 null branch | `phpstan analyse --memory-limit=1G` (level 8) must be clean without ignores |
| Browser E2E | none | no frontend/backoffice change; candidate app has no `assessment_type` branch |

Commands (apply/verify): `php artisan test --compact <files>` per task, then the CI sequence
(`pint --test`, `phpstan`, `test --parallel`, coverage `--min=85`, OpenAPI export diff must be empty).

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or
process-integration boundary. (The `/start` route is unchanged; only its handler's branch logic
changes, and tenant scoping is unchanged.)

## Migration / Rollout

No migration required. No data change, no config change, no `prompt_version` bump, no OpenAPI
change (the export diff must be empty; if it is not, stop and investigate before shipping).

Rollout: one api slice (possibly two under `auto-chain`, see File Changes) released through Git
Flow, api first; frontend/backoffice untouched. Wrapper commit carries the spec delta and docs.

Rollback: revert the api slice(s) and the wrapper docs/spec commit. The W1 guard returns, so
`potential` projects answer `assessment_type_not_supported` again. Sessions created meanwhile are
ordinary `interview_sessions` rows; evaluations produced meanwhile stay valid because scoring was
already potential-aware. A participant left `in_corso` on a potential project after rollback gets
`assessment_type_not_supported` on resume, which is the pre-change behavior.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| PHPStan narrows `tryFrom()` of the literal union and flags the null branch | Med | D1 note: read the raw attribute and narrow with `is_string()`; no ignore, no docblock widening |
| Characterization hash depends on env-overridable config or lang files | Low | pin every config key the composer reads inside the test; a lang/template edit is a prompt change and must update the constants deliberately |
| Controller branches on type, scoring branches on `role_code`; a corrupt potential row with a `role_code` would compose role-less but score role-scoped (`role_no_bars`) | Low | invariant enforced at write time (validation, ingress, immutability once active); not defended at `/start` by design; noted for verify |
| Slice exceeds the 400-line budget | Med | split the E2E file into a second slice under `auto-chain` |
| Role-less report shows no indicator names | Low | D7 follow-up; stored `indicator_text` is still rendered |

## Open Questions

- [ ] None blocking. Follow-up candidate: D7 role-less `indicatorCatalogue()` enrichment.

## Key Learnings

1. `SystemPromptComposer::compose()` uses `$roleId` only for the BARS loader call and the empty-indicator exception message, so widening it to nullable cannot change composed `standard` text.
2. `ScoreEvaluationJob` decides role-less scoring from `role_code !== null`, while the interview controller will decide it from `AssessmentType`, and the two agree only through the write-time invariant that potential projects carry a null `role_code`.
3. `projects.assessment_type` is an unconstrained string column documented as a literal union, so enum default-deny must read the stored value and may need raw-attribute narrowing to satisfy PHPStan level 8.
4. The api has no Pest snapshot plugin, so byte-identical prompt proofs use sha256 and length constants captured from pre-change code.
5. A `match` over `AssessmentType` with no `default` arm makes a future enum case fail both PHPStan analysis and runtime instead of silently composing role-less.
