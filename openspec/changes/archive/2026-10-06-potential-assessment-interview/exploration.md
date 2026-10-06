# Exploration: potential-assessment-interview

> Mirrored from Engram `sdd/potential-assessment-interview/explore` (observation #3525) by the
> sdd-propose phase, because the explore executor had no file-write tool. Key claims were
> re-verified against the code on 2026-10-05; see "Verification" at the end.

## Current State

Most of the `potential` stack already exists; the ONLY runtime blocker is the `/start` guard plus a
non-null role dependency in the composer path.

- Guard: `api/app/Http/Controllers/Candidate/InterviewController.php:175-177`
  (`assessment_type !== 'standard'` -> 422 `assessment_type_not_supported`). The comment at
  :198-200 orders the interviewability gate after it.
- Role lookup: `InterviewController.php:883-890` `Role::where('code', $project->role_code)` -> null
  for potential -> `composition_error` 422. Comment :881-882 "null for potential (deferred)".
- Composer: `SystemPromptComposer::compose()` signature `int $roleId` (:103); the error text names
  the role (:116-121); it calls `loader->forRoleCompetency($roleId, ...)` (:114).
- Loader is already role-less aware: `BarsIndicatorLoader.php:83-94` (`null` -> `whereNull('role_id')`).
- Scoring is already potential-aware: `ScoreEvaluationJob.php:289-343` (`$roleId` null when
  `role_code` null), :423 loader call (change `scoring-role-scoped-indicators`).
- Data exists: `api/database/framework/bars/POTENTIAL.json` (MTG, LAT), `competencies.json:182,192`,
  `default-questions.json:166,196` (4 questions each, en/it); docs mirror in
  `docs/app_description/02-domain/framework/`. `FrameworkCatalogSeeder` handles potential (:586-615).
- Project config: `ValidatesProjectComposition.php:152-231` (role_code null, competencies subset
  MTG/LAT, `POTENTIAL_CATALOG_INCOMPLETE`), `StoreProjectQuestionRequest.php:174-203` +
  `PlatformSettings.php:39` (default cap standard=1, potential=4), `ApplyCompetencySelection.php:191,244-281`
  copies catalogue defaults capped per type. `GET /api/framework/potential-competencies`
  `FrameworkController.php:156-185`.
- Primary questions: `InterviewController::primaryQuestionsFor` (:1752) reads `project_questions`
  per project+competency, type-agnostic. The composer already supports N primaries + follow-up
  budget + clamp (`effectiveMinimum` :216-221; `config/conversation.php` followup_budget=4,
  min_questions=4).
- Interviewability predicate (`ProjectInterviewability.php:61-127`) is type-agnostic.
- SSO/ingress: `EntryLinkMinter.php:188`, `SsoExchangeController.php:437`, `SsoLinkController`,
  `EnrolCandidate.php:110` already treat potential (role_code null).
- Spec: `openspec/specs/interview-conversation/spec.md:24-28` (Out of Scope: potential/SA-08, "no
  framework_potential_questions model, no fixed-sequence block"), :729-780 (cap is a maximum;
  zero-primary never reaches interview). Domain docs: `assessment-types.md:23-24` ("up to 4
  predefined questions ... then AI follow-ups", "more rigid structure"), acceptance SA-08
  (`01-acceptance-scenarios.md:75-80` says "4 predefined questions are asked").
- Tests encoding the guard: `api/tests/Feature/C8/InterviewStartCompositionTest.php:632-725` (two
  W1 tests) must be inverted/replaced.

## Hard-coded / assumed standard

1. `InterviewController.php:175` guard.
2. `:883` role lookup (+ `composePromptForCompetency` passes `$role->id`).
3. `SystemPromptComposer` `int $roleId` + exception message.
4. `AdminEvaluationSerializer.php:339-368` `indicatorCatalogue` returns `[]` when no role (falls back
   to stored `indicator_text`; cosmetic degrade for potential reports; also uses a role_id filter at :376).
5. Prompt template: coverage and STAR sections are type-neutral; any template edit requires a
   `conversation.prompt_version` bump (`config/conversation.php:49`) and prompt tests.
6. `DemoSeedCommand.php:186-197` states no potential demo project is seeded.
7. Frontend candidate app: no runtime branch on `assessment_type` (only generated types); no
   `assessment_type_not_supported` mapping outside api. Backoffice already authors potential projects.

## Approaches

1. **Minimal unlock (adaptive, reuse the standard engine)** — remove the guard, make role nullable in
   controller + composer, reuse `project_questions` as primaries (up to 4) + follow-up budget.
   Effort: Low (api ~150-250 lines incl. tests).
2. **Unlock + potential-specific prompt variant** (fixed order, verbatim, tighter follow-ups).
   Effort: Medium (api ~300-450); prompt_version bump; risk to standard byte-identity.
3. **Server-driven fixed sequence** — contradicts the spec Non-Goal "per-turn server LLM inference".
   Not recommended.

## Recommendation

Approach 1 (unlock + nullable role, proven with Pest end-to-end incl. scoring and completion gate).
Keep the guard default-deny for unknown future types (match on the `AssessmentType` enum) and keep
the standard path byte-identical (assert the composed standard prompt is unchanged).

## Open product decisions (at explore time)

Rigidity; follow-up policy; minimum floor; MTG/LAT question authorship; scoring/report semantics;
pause/nudge/proctoring parity; demo seed; docs wording. All were subsequently SETTLED by the owner
(Approach 1, adaptive; defaults recorded in `proposal.md`).

## Size estimate (authored changed lines)

- api: ~200-350. frontend: ~0-30. backoffice: ~0. Well under one 400-line slice for Approach 1.

## Risks

- Composer signature change touches the standard path (guard with a byte-identical prompt test).
- Zero BARS rows for MTG/LAT in a pinned revision -> `CompositionException` / `composition_error`.
- `min_questions` > primaries + budget (already clamped).
- Stale W1 tests and spec Out-of-Scope text must be updated.
- Wrapper docs say "4 predefined" vs spec "maximum".

## Verification (sdd-propose, 2026-10-05)

Confirmed against the code: guard at `InterviewController.php:175`; role lookup at :883-890 with the
"deferred" comment at :881-882; `SystemPromptComposer::compose(int $roleId, ...)` at :101-121 and the
clamp at :216-221; `BarsIndicatorLoader::forRoleCompetency(?int $roleId, ...)` with `whereNull('role_id')`
at :83-94; W1 tests at `InterviewStartCompositionTest.php:632` and :675; spec lines 24-28 and 729-781.
`App\Enums\AssessmentType` exists (`api/app/Enums/AssessmentType.php`). Additional docs drift found:
`docs/app_description/01-product-and-journeys/01-product-overview.md:93` ("4 predefined questions per
competency").
