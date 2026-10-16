# answer-time-range

## Objective
The answer-time bar in the call panel must tell the candidate, at a glance, that a "good" answer lasts between a minimum and a maximum number of seconds. Default: 90 s to 150 s (1:30 to 2:30). The range is configurable per avatar template.

## Problem
`frontend/app/utils/answer-budget.ts` derives the bar from `interview_max_seconds / primary_total_all` with fixed fractions (25 % / 37.5 % / 75 %). At 20 min and 6 questions it shows `0:50 min · ideal 1:15–2:30 · 3:20 max`, which is unrelated to the intended 1:30 to 2:30 guidance. No answer range exists anywhere in the API (verified: no `answer_min`/`answer_max`/`ideal_*` column, resource field or config).

## Decision (feasibility)
Not feasible with the existing data, so it becomes configurable per avatar template: two NOT NULL integer columns on `avatar_templates`, `answer_min_seconds` default 90 and `answer_max_seconds` default 150 (migration default fills existing rows, platform rows included). The candidate session response carries both, resolved through `ActiveTemplateResolver` exactly like `interview_max_seconds`, falling back to 90/150 when no template resolves.

## Bar semantics
Three zones: below min (too short, neutral), min to max (good answer, highlighted), above max (long, calm warning). Bar scale ends at `max * 4/3` so the overshoot zone is visible. Labels state the range. Guidance only: nothing ends or shortens an answer.

## Scope and tasks
- [x] T1 api (0ab93f7 + 8e9c546, pushed) (branch feature/answer-time-range): migration, model, validation (min >= 10, max <= 600, min < max), duplicate and portability, resources + Scramble annotations, `T-EXPOSE-001` classification, session response + controller annotation, tests, export both openapi specs (Postgres), sync copies into backoffice and frontend.
- [x] T2 backoffice (25f81b4, pushed) (branch feature/answer-time-range): regenerate types, two number fields in `AvatarTemplateForm`, payload pass-through in both pages and composables, i18n it/en, tests.
- [x] T3 frontend (a23d2a0, pushed; icons at min/max included) (branch feature/answer-time-range): regenerate types, store `answerMinSeconds`/`answerMaxSeconds` in `useInterviewSession`, rewrite `answer-budget.ts` to the three-zone model, update `CallAnswerTimer` zones and copy, remove the fractions, update tests and baselines.

## Constraints
- TDD strict (RED observed, GREEN, REFACTOR). Runners: Pest (api), Vitest via bun (backoffice, frontend), Playwright e2e on frontend.
- Repo language English; i18n it/en only for copy. Conventional commits, no AI attribution; one work-unit commit per task with tests.
- Exposure rule: no new public/export field without a `T-EXPOSE-001` entry classified in the same change.
- ~400 changed lines per task is a planning heuristic only.
- No push, PR or deploy without the user's request.

## Route declaration
Delegated direct, one writer per repo (mapping already done by one explorer: 4+ files per repo, 2+ non-trivial files per writer). T1 first (contract), then T2 and T3 in parallel.

## Delivery
Strategy: ask-on-risk. Forecast: well under 400 changed lines per repo except generated files.

## Progress
All three tasks and the review follow-ups are committed, reviewed and merged to develop through the per-repo PRs (api #198, backoffice #95, frontend #115, 2026-10-16). Released as api 0.76.0, backoffice 0.55.0, frontend 0.28.0.

## Next step
None for this feature. Optional: an HTTP-level import test for the missing-key case.
