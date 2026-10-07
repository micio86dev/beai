# Archive Report: scoring-role-scoped-indicators

**Change**: scoring-role-scoped-indicators
**Archived to**: `openspec/changes/archive/2026-10-08-scoring-role-scoped-indicators/`
**Archive date**: 2026-10-08
**Status**: CLOSED. THE PRODUCTION DEFECT IS FIXED; THE CHANGE AS DESIGNED IS ONLY PARTLY DELIVERED. No verify-report
existed; verification was not run as an SDD phase and no test suite was run by this archive. `tasks.md` was
corrected against the code (see "Checkbox corrections"); the observed-run claims in it were not re-run.

## Summary

Scoring loaded BARS indicators by competency only, so a competency shared by several roles leaked the other roles'
indicators into the prompt and the score (15 rows instead of 3; reliability denominators of 15). Observed on disk at
archive time:

- **Delivered (production fix)**: api commit `6087bbd` plus `api/tests/Feature/Jobs/RoleScopedIndicatorsTest.php`.
  `ScoreEvaluationJob` resolves `?int $roleId` from `project.role_code` (`api/app/Jobs/ScoreEvaluationJob.php:423-454`;
  an unresolvable `role_code` aborts instead of falling through to null) and loads indicators through
  `BarsIndicatorLoader::forRoleCompetency($roleId, $competencyId, ...)` (`:478`, `:527`). The loader
  (`api/app/Services/Conversation/BarsIndicatorLoader.php`) filters `competency_id`, `revision_id`, then
  `whereNull('role_id')` when `$roleId === null` and `where('role_id', $roleId)` otherwise, ordered by `position`.
  The test file covers: pinned role scores only its own indicators; potential project scores the role-less rows and
  never a role-scoped decoy; reliability over 3 indicators; unanchored pair is `role_no_bars`; unresolvable
  `role_code`; project pinning no catalogue revision.
- **Delivered (arch guard)**: `api/tests/Arch/C9/BarsIndicatorRoleScopeArchTest.php` on api branch
  `feature/scoring-bars-role-scope-arch-guard`, commit `26b4350`. **That commit is NOT yet on api `develop`.** It
  scans `app/Services/Conversation`, `app/Services/Scoring`, `app/Actions/Scoring`, `app/Jobs` and
  `AdminEvaluationSerializer.php` (not all of `app/`), with matcher self-tests (flags a competency-only read and a raw
  `framework_bars_indicators` table read; accepts `where`/`whereNull`/`whereIn`/array-key forms; does not borrow a
  constraint from the next method) and a liveness test (the scan reaches the scoring loader). Its pass was not
  re-run at archive time.

## Specs merged

Composition used `gentle-ai sdd-archive-compose` (exit 0).

| Capability | Requirements before -> after | Delta |
|---|---|---|
| interview-conversation | unchanged count | 1 modified ("BARS Indicator Loading — BarsIndicatorLoader") |

`git diff --stat`: 30 insertions, 8 deletions. The modified requirement reverses the RV-2 carve-out (single shared
loader consumed by both the C8 composer and `ScoreEvaluationJob`), adds the `whereNull('role_id')` branch for
`potential`, and two scenarios (shared loader, null-role). Every statement was confirmed in code: the loader is the
one class used by `ScoreEvaluationJob` and `SystemPromptComposer`, `forRoleCompetency` exists, the `whereNull` branch
exists, and `BarsIndicatorLoaderTest` plus the arch guard cover cross-role isolation.

Two hand edits to the composer output, both formatting only: the composer dropped the `---` separator and the blank
line after the modified requirement's last scenario; they were restored so the next requirement heading is not glued
to the previous scenario.

### Not merged - scoring-engine delta (1 ADDED requirement, ~14 scenarios)

"Role- and Assessment-Type-Scoped BARS Indicator Resolution" was NOT merged. It is a single requirement, so it cannot
be merged selectively without rewriting it, and it asserts two things that are not in code:

- "Returned indicators MUST form a reproducible TOTAL order (`position`, with an explicit secondary tiebreaker)" and
  its scenario: the loader orders by `position` only (`BarsIndicatorLoader.php:97`).
- "a placeholder/sentinel role id MUST NOT be passed" and its scenario "PromptBuilder receives the real pinned role,
  not a sentinel": `api/app/Actions/Scoring/ScoreCompetency.php:119` still passes `roleId: 0` and
  `PromptBuilder::build()` still takes `int $roleId` (`api/app/Services/Scoring/PromptBuilder.php:166`).

The remaining scenarios (role-scoped lookup per role, potential MTG/LAT via `whereNull`, shared implementation,
reliability denominator 3, `role_no_bars` reachable, arch guard and matcher self-test) are delivered. They are
preserved in this folder's `specs/scoring-engine/spec.md`. Re-submitting the requirement once the two gaps are
closed (or after a human trims the two statements) is the way to bring them into `openspec/specs/scoring-engine/`.

### Not merged - purge requirement

"Purge of Pre-Fix Role-Contaminated Evaluations (Remediation Command)" was in the same delta file and was NOT merged:
the command was never built (Phase 4 dropped, below).

## Checkbox corrections (tasks.md)

Only checkboxes and trailing notes were edited; line count unchanged (176 before and after).

Unchecked, with a `NOT DONE (verified 2026-10-08)` note: **1a.2, 1a.9, 1a.10** (the loader was never relocated to
`app/Services/FrameworkCatalog`; it is `App\Services\Conversation\BarsIndicatorLoader`), **1b.4, 1b.5** (`roleId: 0`
sentinel at `ScoreCompetency.php:119`; `PromptBuilder::build(int $roleId)`). Two further tasks were unchecked beyond
the brief because the code contradicts them: **1a.7** (no `orderBy('id')` tiebreaker) and **1b.8** (no job-level
`indicator_count_mismatch` scenario in `RoleScopedIndicatorsTest`; only parser-level coverage in
`EvaluationParserTest`, not verified end to end).

Checked: Phase 2 arch-guard tasks 2.1-2.5 and 2.9 (covered by the new test, see above); 2.7 and 2.8 as PARTIAL (the
liveness test asserts the scan reaches the loader, not an explicit file/occurrence count); 2.2 as DONE with narrower
scope. Left unchecked: 2.6, 2.10, 2.11 (not re-run). Phase 3: 3.1-3.4 annotated, none ticked (3.2 is partial, see
above). Phase 4 (every `4.x`, including the three "ALLOWLIST" amendment items): annotated `NOT DONE: dropped from this
change; open a new change only after checking current production data`.

## Not delivered / deferred

- **Phase 4 purge command (`beai:purge-miscored-evaluations`)**: dropped from this change. It is destructive and the
  production data must be re-checked first; open a new change only after that.
- **Spec edits**: scoring-engine not merged (above); `interview-conversation/spec.md` still has the Non-Goals line
  "Refactoring `ScoreEvaluationJob` (C9) — C8 introduces its own `BarsIndicatorLoader`" (line 31) and later
  `BarsIndicatorLoader::load()` mentions (around line 1053) that the merged requirement contradicts.
- **Tenancy follow-up recorded in tasks.md** (the `RoleScopedIndicatorsTest` calls `handle()` directly with the
  ambient resolver set, so the `TenantContextScope::runFor()` wrapper is never seen to fail): not addressed.
- **1b.12 follow-up** (`InterviewController` answers 422 `composition_error` for a `potential` project with no
  `Role`): not re-verified here.

## Optional follow-ups

1. Remove the `roleId: 0` sentinel: drop the `int $roleId` parameter of `PromptBuilder::build()` and its call site
   in `ScoreCompetency.php`, update `PromptBuilderTest`, then re-submit the scoring-engine requirement.
2. Add the `orderBy('id')` tiebreaker to `BarsIndicatorLoader` (a total order; unreachable today while the unique
   constraint on `(role_id, competency_id, position)` holds, so not load-bearing).
3. Relocate the loader to `App\Services\FrameworkCatalog` (pure move; touches `SystemPromptComposer`, which
   `db-driven-conversation-prompts` also owns, so land it after or with that change).
4. Update the two stale mentions in `openspec/specs/interview-conversation/spec.md` (Non-Goals line, `load()` name).
5. Land api `26b4350` (arch guard) on `develop` through Git Flow.

## Traceability

Mode openspec. Artifacts read from the filesystem: proposal.md, design.md, tasks.md, two delta specs. Absent:
verify-report, apply-progress, exploration.md.

## Copy verification

Moved with `git mv`. Original file counts and line counts are identical after the move (design.md 522, proposal.md
192, tasks.md 176, specs/interview-conversation/spec.md 46, specs/scoring-engine/spec.md 156). The only edits were the
`tasks.md` checkbox/notes described above. This report is additive.
