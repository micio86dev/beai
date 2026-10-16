# followups-answer-range-background-color

## Objective
Close the three follow-ups left after the 2026-10-16 release (api 0.76.0, backoffice 0.55.0, frontend 0.28.0).

## Scope and tasks
- [x] T1 backoffice (c9166e7, PR #96, released as backoffice 0.55.1) (branch feature/client-form-background-color): `ClientForm.vue` (superadmin client form) gets the organization background colour, with the same picker, hex field, Clear and `#rrggbb` validation as the primary colour; loads `background_color` on edit, sends it on create and update (the managed-organization API already accepts and returns it); i18n it/en; tests. Also fix the overclaiming comment in `pages/avatar-templates/index.vue` and `pages/platform-templates/index.vue` ("and edit-to-new" is false: the old `id ?? 'new'` key already remounted on edit-to-new).
- [x] T2 api: DROPPED, nothing to add (verified 2026-10-16). Over HTTP an OMITTED key takes the default by design (`TemplateDocument::flatten()`, older exports); only an explicit null, a wrong type or out-of-range values are refused, and `tests/Feature/AvatarTemplates/AnswerTimeRangeTest.php` already covers those through `POST /api/avatar-templates/import`. The missing-key guard is only reachable by calling `reject()` directly, which the reflection test (line 286) covers. The earlier note that import refuses a missing key was imprecise.

## Constraints
Strict TDD (RED observed, GREEN, REFACTOR). Runners: Vitest via bun (backoffice), Pest serial (api). Repo language English; i18n it/en only for copy. Conventional commits, no AI attribution. Exposure rule T-EXPOSE-001 unaffected (no new field). Advisory ~400 changed lines per task.

## Route
Delegated direct, one writer per repo, in parallel.

## Delivery
Strategy ask-on-risk. Forecast well under 400 lines per repo. Owner standing order: merge and release through Git Flow after verification.

## Progress
T1 committed, natively reviewed (approved, no findings), merged and released as backoffice 0.55.1 (wrapper 0.59.1 pins it). T2 dropped as redundant. Feature closed 2026-10-16.

## Next step
None.
