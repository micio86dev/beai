# Apply Progress: live-interview-call-chrome

Mode: Strict TDD. Delivery: auto-chain, feature-branch-chain. Nothing pushed, no PR opened.

## Cumulative status

Completed: T0.0, T0.1, T-A1.1, T-A1.2 (batch 1); T-A2.1 to T-A2.4, T-A3.1 to T-A3.6 (batch 2). The whole api phase
(slices A.i, A.ii, A.iii and the split A.iv) is done except T-A3.7 (release gate, orchestrator-owned).
Batch 3 (backoffice slice A2): T-A2.1b, T-A2.2b, T-A2.3 complete.
Batch 4 (frontend slice B.i): T-B1.1 to T-B1.5 complete.
Batch 5 (frontend slice B.ii, partial): T-B2.1, T-B2.2, T-B2.3 complete; T-B2.4 and T-B2.5 pending (size split requested).
Batch 6 (frontend): T-B2.4, T-B2.5, T-C1a.1 to T-C1a.5, T-C1b.1 to T-C1b.4 complete (slices B.ii part 2, C1a, C1b).
Remaining: C2a.1, C2a.2, C2b (T-C2a1.*, T-C2a2.*, T-C2b.*), plus T-A3.7 (orchestrator-owned). Nothing pushed, no PR opened.

## Batch 1 (Phase 0 + Slice A.i): complete

Completed: T0.0, T0.1, T-A1.1, T-A1.2.

### Branches and commits

| Repo | Branch | Base | Commit |
|---|---|---|---|
| wrapper | `feature/live-interview-call-chrome` (tracker) | `develop` 6756c1e | b3d6404 `docs(openspec): add live-interview-call-chrome change artifacts` |
| wrapper | `feature/licc-0-design-docs` | wrapper tracker | 4c9286a `docs(design): describe the live call chrome, panel and captions overlay` |
| api | `feature/live-interview-call-chrome` (tracker) | `develop` 8b2f5ed | none (branch only) |
| api | `feature/licc-a1-competency-progress` | api tracker | 56417e5 `refactor(interview): extract competency order and open rule into CompetencyProgress` |
| backoffice | `feature/live-interview-call-chrome` (tracker) | `develop` | none (branch only) |
| frontend | `feature/live-interview-call-chrome` (tracker) | `feature/seamless-primary-transition` 61246c9 | none (branch only) |

### TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| T0.1 (doc-only) | `rg -n "never a competency name\|no status pill\|min/ideal/max\|minimum/ideal/maximum\|22rem\|primary-caption" DESIGN.md` matched the old rules (lines 721 "no status pill", 788 "minimum/ideal/maximum band") and `22rem` / `primary-caption` did not match | same pattern (old-rule alternatives only) exits 1 (no match); `22rem` matches §3.3 and the §4 CSS block; `primary-caption` matches §3.1 and §7.3 | stale `question band` references (component tree, §7.3.1, §9.2) updated to the captions overlay |
| T-A1.1 | `php artisan test --parallel --filter=CompetencyProgress`: 8 failed / 0 passed, `Class "App\Support\Interview\CompetencyProgress" not found` | see T-A1.2 | n/a |
| T-A1.2 | see T-A1.1 | same filter: 8/8 passed; with the four regression suites: 44/44 passed (baseline before the change: those four suites 36/36) | `resolveNextCompetency`/`competencyPayload` removed from the controller; `freshRemainingCompetencies` uses `ordered()`; docblock references updated; phpstan return type narrowed to `\stdClass` rows; full suite green |

### Work Unit Evidence (A.i)

| Evidence | Value |
|---|---|
| Focused test command | `php artisan test --parallel --filter='CompetencyProgress\|QuestionIndexZeroBased\|CompletionCas\|RecoverFailedParticipant\|DraftContentIsolation'`: 44 passed |
| Other gates | `composer analyse`: passed; `vendor/bin/pint --test`: passed; full `php artisan test --parallel`: 9536 tests, 9524 passed, 12 skipped, 0 failed (218 s) |
| Runtime harness | N/A against the local stack (not started in this batch); `/start` is exercised through the real endpoint by `QuestionIndexZeroBasedTest` and `CompletionCasTest` (feature tests), unmodified and green |
| Rollback boundary | revert commit 56417e5; behaviour is byte-identical |

### Notes

- The four existing suites are untouched (`git diff --stat` shows only 3 app files modified, 2 files created).
- A.i diff is 305 insertions + 106 deletions = 411 lines (about 270 of them are the new test file and the moved code); marginally over the 400 budget, a pure extraction that cannot shrink further without dropping tests or comments. Recommend `size:exception` or accept as the ~200-line estimate was low.
- Stale `resolveNextCompetency()` mentions remain only in test comments (tests deliberately unmodified) and in the new class docblock (historical note).
- Wrapper slice-0 branch also carries this file and the `tasks.md` ticks.
- The wrapper working tree still has `M frontend` / `M api` / `M backoffice` (submodule pointers moved by branch switches): never staged. `odd/tasks/seamless-primary-transition.md` is untracked and not committed.

## Batch 2 (Slices A.ii, A.iii, A.iv): complete

Completed: T-A2.1, T-A2.2, T-A2.3, T-A2.4, T-A3.1, T-A3.2, T-A3.3, T-A3.4, T-A3.5, T-A3.6. Skipped by design: T-A3.7 (orchestrator-owned).
Mode: Strict TDD. Delivery: auto-chain, feature-branch-chain. Nothing pushed, no PR opened. frontend/ and backoffice/ untouched.

### Branches and commits (api)

| Branch | Base | Commit | Task |
|---|---|---|---|
| `feature/licc-a2-outline` | `feature/licc-a1-competency-progress` | 62c3888 `feat(interview): add the candidate interview outline endpoint` | T-A2.1 to T-A2.3 |
| `feature/licc-a2-outline` | | 95f9a3c `chore(api): export openapi for the interview outline` | T-A2.4 |
| `feature/licc-a3-utterance-persona` | `feature/licc-a2-outline` | aa2b12a `feat(interview): return primary_index from the utterance endpoint` | T-A3.1 |
| `feature/licc-a3-utterance-persona` | | 284a295 `feat(avatar-templates): add the PersonaDisplayName validation rule` | T-A3.2 |
| `feature/licc-a3-utterance-persona` | | 9792059 `feat(avatar-templates): validate and merge persona.display_name on every write` | T-A3.3 |
| `feature/licc-a3-utterance-persona` | | be7f0f1 `feat(avatar-templates): expose persona.display_name to admins and classify it` | T-A3.5 (+ T-A3.6, see below) |
| `feature/licc-a4-persona-import` | `feature/licc-a3-utterance-persona` | d001fdb `feat(avatar-templates): refuse an invalid persona display name on import` | T-A3.4 (split out) |
| wrapper `feature/licc-0-design-docs` | | this file and `tasks.md` ticks | |

### TDD Cycle Evidence

| Task | RED (observed) | GREEN | REFACTOR / triangulation |
|---|---|---|---|
| T-A2.1/T-A2.2/T-A2.3 | `php artisan test --parallel --filter=InterviewOutline`: 23 failed / 0 passed, all `404` (route missing); first run also exposed that `framework_*_name_nonblank_check` forbids a name blank in `en` (two tests dropped, see Deviations) | 24 passed (76 assertions); `AuthMatrix` filter: coverage guard red ("no entry for GET api/candidate/interview/outline", 1 failed of 1871) then 1889 tests green after catalogue/fixtures/lifecycle entries | triangulated: 5 status shapes, 3 persona shapes, 2 tenants, 2 terminal statuses. Test-helper fix: `forgetGuards()` (the candidate guard caches the first request's user inside one test) |
| T-A2.4 | `InterviewOutlineDocumentedTest` with the spec stashed: 2 failed (no operation) | export (PostgreSQL) adds only `outline.show`; 2 passed; `ResourceMatchesSpec`, `OpenApi`, `Contract` filters: 283 passed | n/a |
| T-A3.1 | `UtterancePrimaryIndexTest`: 10 tests, 9 failed (field `null`), 1 passed (409 regression guard, passes at birth by design) | 10/10; `BoundaryDue`, `Utterance*`, `Tally`, `CrossParticipant`, `ResolvesOwned`: 50 passed | `matchedCount()` computed once and shared with `recordUtteranceEvent()` (event index test: `[0, 1]` unchanged). `UtterancePrimaryIndexDocumentedTest` RED with the spec stashed (1 error), GREEN after export |
| T-A3.2 | `PersonaDisplayNameTest`: 33 errors, class missing | 32 passed (one data row dropped, see below) | 11 provider rows, 6 markup/control rows, 6 look-alike rows, message never echoes the word |
| T-A3.3 | `PersonaDisplayNameWriteTest`: 36 tests, 34 failed (201/200 instead of 422; persona not stored/merged), 2 passed (create without persona) | 36/36; `AvatarTemplate\|C14\|OpenApi\|ResourceMatchesSpec`: 860 passed | two surfaces x create/update x 5 refusals, merge (kept import key), clear (`{}`, null, blank) unsets, absent leaves column. `PersonaDisplayNameDocumentedTest` (request bodies) RED with spec stashed (4 errors) |
| T-A3.5 | `PersonaResourceTest`: 19 tests, 6 failed + 4 errors (accessor missing); `ExposureTest` red with the catalogue entry stashed (1 failed of 25); `PersonaDisplayNameDocumented` RED for the Platform resource (2 errors) | `PersonaResource\|InterviewOutline\|Exposure\|ParticipantArch\|ResourceMatchesSpec`: 89 passed; documented + OpenApi: 151 passed | interim `BuildInterviewOutline::avatarName()` deleted in favour of `AvatarTemplate::personaDisplayName()` |
| T-A3.6 | covered by the per-commit exports above | final PostgreSQL export after T-A3.5: `git status` clean (no drift) | n/a |
| T-A3.4 | `PersonaImportTest`: 11 tests, 8 failed (201 instead of 422; blank stored as `null` key), 3 passed (padded trim by middleware, round trip, duplicate: guards that pass at birth) | 11/11; `PersonaImport\|Portability\|AvatarTemplate\|C14`: 770 passed | n/a |

### Work Unit Evidence

| Evidence | A.ii | A.iii | A.iv |
|---|---|---|---|
| Focused test command | `php artisan test --parallel --filter=InterviewOutline`: 24 passed | `--filter='UtterancePrimaryIndex\|PersonaDisplayName\|PersonaResource\|AvatarTemplate\|Exposure'`: all green | `--filter=PersonaImport`: 11 passed |
| Full suite (once per slice) | `php artisan test --parallel`: 9580 tests, 9568 passed, 12 skipped, 0 failed (334 s) | 9684 tests, 9672 passed, 12 skipped, 0 failed | 9695 tests, 9683 passed, 12 skipped, 0 failed |
| Gates | `composer analyse`: 0 errors; `vendor/bin/pint --test`: passed | same | same |
| Runtime harness | feature tests drive the real route with real candidate JWTs; no local stack started (api images not rebuilt in this batch) | same (real `/utterance`, admin endpoints) | same (real import/export/duplicate endpoints) |
| Rollback boundary | revert 95f9a3c + 62c3888; additive, no consumer | revert the four commits; additive, no migration (the 202 gains a field, `BoundaryDueTest` assertions updated) | revert d001fdb |

### Authored size (git diff --numstat vs the slice base; insertions + deletions)

| Slice | With `openapi.json` | Excluding generated `openapi.json` | Note |
|---|---|---|---|
| A.ii | 759 | 661 | forecast ~330; about 425 lines are tests, 162 the action (Pint expands braces) |
| A.iii | 952 | 868 | forecast ~380 before the T-A3.4 split; four commits, each a coherent work unit |
| A.iv | 163 | 163 | T-A3.4 split out as tasks.md prescribes |

A.ii and A.iii exceed the 400 budget; neither can shrink without dropping tests (strict TDD) or comments. Recommend `size:exception` for both,
or accept that the per-slice estimates were low (tests were ~60% of the diff).

### Deviations from design/tasks (all behaviour-preserving)

1. **Interim persona check in A.ii.** `PersonaDisplayName` (T-A3.2) lands in A.iii, but A.ii's outline must already return `null` for an invalid stored name. `BuildInterviewOutline::avatarName()` applied length and angle-bracket/control checks only, and was replaced by `AvatarTemplate::personaDisplayName()` in T-A3.5. Nothing consumed the endpoint in between.
2. **Blank-everywhere names are unreachable.** `framework_roles_name_nonblank_check` and `framework_competencies_name_nonblank_check` require a non-blank `en`, so "both translations blank -> null" cannot be stored. The two tests that needed it were dropped; the fallback chain (project language, then `en`) is tested with a blank project-language value. The `null` return stays in the code as a defensive branch.
3. **`primary_index` changed an existing contract test.** `BoundaryDueTest` used `assertExactJson(['boundary_due' => x])` (9 assertions); they now include `'primary_index' => 0`. Behaviour of the tests is otherwise unchanged. tasks.md said "existing utterance suite unmodified"; the spec itself changes the 202 body.
4. **`openapi.json` exported in every contract-touching commit, not only T-A3.6.** The pre-commit review gate (gga) refuses a commit that changes a Scramble-visible signature without the re-export (it failed the first T-A3.1 commit for exactly that). T-A3.6 therefore has no commit of its own: its acceptance (diff holds `primary_index` and `persona.display_name` only, `ResourceMatchesSpecTest` green, no drift on a final export) is met by the three exports plus a clean final export.
5. **Persona rule is a closure plus `personaWrite()`, not `array:display_name` plus `mergePersona()`.** Two defects found while verifying the export: Scramble publishes every key of `array:display_name` as REQUIRED (the generated client would refuse `persona: {}`, the payload that clears the name, M4), and Laravel drops an EMPTY array from `validate()`'s result, so `persona: {}` never reached the merge. `personaRules()` now uses `array` plus a closure refusing any key but `display_name`, and `personaWrite(Request, ?array)` reads `persona` from the request. The contract now documents `persona.display_name` as optional and nullable (guarded by `PersonaDisplayNameDocumentedTest`).
6. **`PlatformAvatarTemplateResource` does not inherit the new field in the contract.** Its own `@scramble-return` replaces the parent's, so the field was missing from the published schema until that docblock was updated (caught by the contract test, not by a feature test).
7. **The organization avatar-template surface needs a superadmin acting as the organization**, not an admin (managing templates stopped being a client action on 2026-09-02); the new tests use `TemplateActors::token('acting', ...)`.
8. **Message wording.** `PersonaDisplayName` messages are literal English sentences (the avatar-template surface returns Laravel validation messages; the backoffice maps the `persona.display_name` key to its own i18n copy). None repeats the vendor word.

### Issues found / for the orchestrator

- **gga (pre-commit review) is flaky.** The first commit attempt of 62c3888 and aa2b12a failed ("ambiguous response" / a legitimate openapi finding); a retry passed. No hook was bypassed.
- **Backoffice contract note for A2.** The persona payload to clear the name is `persona: {}` (or `persona: {display_name: null}`); both unset the key. Do not send an empty string.
- Spec wording to fix at archive time: avatar-templates says the resource inherits; in fact both resource docblocks carry the field.
- Denylist note: `daily` in the provider denylist also refuses a name like "Daily Coach" (word-bounded, per D7); accepted by the design.

## Batch 3 (Slice A2, backoffice): complete

Completed: T-A2.1b, T-A2.2b, T-A2.3. Mode: Strict TDD. Delivery: auto-chain, feature-branch-chain. Nothing pushed, no PR opened. api/ and frontend/ untouched.

### Branch and commits (backoffice)

| Branch | Base | Commit | Task |
|---|---|---|---|
| `feature/licc-bo-persona-name` | backoffice tracker `feature/live-interview-call-chrome` | 048d5c3 `chore(backoffice): sync openapi for persona display name` | T-A2.1b |
| `feature/licc-bo-persona-name` | | efe46e7 `feat(avatar-templates): add the interviewer display name to the template form` | T-A2.2b + T-A2.3 |

The contract came from `git show feature/licc-a4-persona-import:openapi.json` (never the api working tree), then `bun run codegen`.

### TDD Cycle Evidence

| Task | RED (observed) | GREEN | REFACTOR / triangulation |
|---|---|---|---|
| T-A2.1b | n/a (generated contract) | `check-client-drift.sh` stage 2 OK ("generated client matches committed snapshot"); `openapi.json` is byte-identical to the api branch file (`cmp`) | stage 1 compares with the api WORKING TREE, which a concurrent process switches between branches, so it reports drift against whatever branch is checked out there; run with the api snapshot disabled and verified with `cmp` against the branch instead |
| T-A2.2b | `vitest run tests/unit/avatar-template-form-persona.spec.ts`: 12 failed / 2 passed (the two that pass at birth: no `persona` on create when empty, and the no-vendor-in-copy guard that is vacuous until the keys exist) | see T-A2.3 | one weak test dropped after the review gate: "holds at most 60 of 80 typed characters" only re-asserted the `maxlength` attribute (jsdom does not truncate programmatic input) |
| T-A2.3 | page wiring: `avatar-templates-page.spec.ts -t "forwards the persona payload"` RED with the page change stashed (1 failed) | persona spec 13/13 (after dropping the weak one); `avatar-template*` + page specs: 343 passed; full vitest 237 files, 4092 passed | create-with-name, create-empty (no key), edit-unrelated-field (same name), clear (`{}`, never an empty string), whitespace-only (`{}`), untouched-without-name (`{}`), 422 mapped to i18n copy with `aria-describedby`/`aria-invalid`, it/en key parity, no vendor word in the copy. Payload type `PersonaWrite` derived from the generated store body (review gate rejected a hand-written copy) |

### Work Unit Evidence (A2)

| Evidence | Value |
|---|---|
| Focused test command | `node node_modules/.bin/vitest run tests/unit/avatar-template-form-persona.spec.ts tests/unit/avatar-templates-page.spec.ts`: green; full `node node_modules/.bin/vitest run`: 237 files, 4092 tests passed |
| Other gates | `bun run lint`: clean; `bun run typecheck`: no errors; `prettier --check`: clean; Playwright `avatar-templates-forecast`, `avatar-templates-heygen-voice`, `platform-templates` specs (Chromium and WebKit): 38 passed |
| Runtime harness | Playwright against the dev server with mocked API routes (above); no local stack started, so a real round trip against the api validator was not exercised |
| Rollback boundary | revert efe46e7 (form, two pages, composable types, locale keys) and 048d5c3 (contract); saved names stay in the template JSON |

### Authored size (git diff --numstat; insertions + deletions)

| Commit | Lines | Note |
|---|---|---|
| 048d5c3 | 262 + 80 | generated `openapi.json` and `types/api.ts`, excluded from the count |
| efe46e7 | 295 | 113 app and locale lines, 182 tests; forecast ~140 |

### Deviations from design/tasks

1. **Pages and composable were touched.** tasks.md lists only the form, the type file and the locales, but both template pages build the API payload field by field, so `persona` would never have reached the api. `app/pages/avatar-templates/index.vue`, `app/pages/platform-templates/index.vue` and `useAvatarTemplates.ts` forward it (platform: superadmin surface, same form).
2. **Update with no name sends `persona: {}`** (M4), including for a template that never had a name; harmless, the api unsets nothing. Create sends no `persona` when empty.
3. **Refusal copy.** A `persona.display_name` 422 shows the form's own i18n sentence (`errors.personaDisplayNameInvalid`), never the api's English sentence, which keeps the vendor-free promise in both languages.
4. **`maxlength=60` is native only.** The review gate noted the form's other fields validate in JS; the spec scenario ("holds at most 60 characters") is met by the attribute. A JS length check is a possible follow-up.
5. **No new Playwright spec** for the form: the existing avatar-template e2e specs pass, and the new behaviour is covered by component and page specs. Coverage was not re-measured in this batch.

### Issues found

- gga reviewed the first feat commit and refused it for a hand-maintained write type; fixed by deriving `PersonaWrite` from `paths`. The second pass was accepted. No hook bypassed.
- The wrapper working tree still has `M api` / `M backoffice` / `M frontend` pointer changes and the untracked `odd/tasks/seamless-primary-transition.md`: not staged.

## Batch 4 (Slice B.i, frontend): complete

Completed: T-B1.1, T-B1.2, T-B1.3, T-B1.4, T-B1.5. Mode: Strict TDD. Delivery: auto-chain, feature-branch-chain. Nothing pushed, no PR opened. api/ and backoffice/ untouched.

### Branch and commits (frontend)

| Branch | Base | Commit | Task |
|---|---|---|---|
| `feature/licc-b1-outline-data` | frontend tracker `feature/live-interview-call-chrome` (61246c9) | a0bf72d `chore(frontend): sync openapi for the interview outline` | T-B1.1 |
| `feature/licc-b1-outline-data` | | 0b45f39 `feat(interview): add the answer budget arithmetic` | T-B1.2 |
| `feature/licc-b1-outline-data` | | 90db42e `feat(interview): add the single-flight interview outline composable` | T-B1.3 |
| `feature/licc-b1-outline-data` | | b9f63af `feat(interview): track primary_index from utterance responses` | T-B1.4 |
| `feature/licc-b1-outline-data` | | 023d43e `feat(interview): seed the competency total and ordinal from /start` | T-B1.5 |

The contract came from `git show feature/licc-a4-persona-import:openapi.json` (never the api working tree; `cmp` confirms byte identity), then `bun run codegen`.

### TDD Cycle Evidence

| Task | Test file | Safety net | RED (observed) | GREEN | Triangulation / refactor |
|---|---|---|---|---|---|
| T-B1.1 | n/a (generated) | n/a | n/a | `API_OPENAPI_SNAPSHOT=/nonexistent bash scripts/check-client-drift.sh`: "generated client matches committed snapshot" (stage 1 compares with the api WORKING TREE, so it was disabled and `cmp` used instead); `types/api.ts` exposes `operations['outline.show']` and `primary_index` | n/a |
| T-B1.2 | `tests/unit/answer-budget.spec.ts` | n/a (new) | module not found, "no tests" (1 file failed) | 18/18 | O1 values (1200/6, 1210/6), 1 s boundary (6/6), 13 invalid-input rows (0, negative, null, undefined, NaN, Infinity, max < 1), 300 s seed guard |
| T-B1.3 | `tests/unit/use-interview-outline.spec.ts` | n/a (new) | module not found, "no tests" | 7/7 | single-flight (3 calls, 2 requests), no phantom re-run, failure keeps value, first failure leaves null then recovers, trailing run after a failed first, two instances independent |
| T-B1.4 | `tests/unit/use-interview-session.spec.ts` (+9) | 115/115 | 9 failed (`primaryIndex` undefined) | 124/124 | set from direct send, latest wins (2 then 3), outbox path, absent field, 409 keeps value, stale-session line ignored, current-session line applied then cleared on swap, cleared on /start. Mutation: dropping the `dbSessionId === sessionId.value` guard fails the stale-session test only |
| T-B1.5 | `tests/unit/use-interview-session.spec.ts` (+9), `tests/unit/embed-token-page.spec.ts` (+1) | 124/124 + embed 33 | 9 failed (`competencyOrdinal` undefined); the /end-overwrite and the embed test pass at birth by design (existing behaviour pinned) | 168/168 for both files | total/ordinal seeded with `ended` null, in place when `sessionId` first appears, 5 invalid values for both fields, absent fields, /end overwrites with no flicker, total stable and ordinal moves across competencies |

### Work Unit Evidence (B.i)

| Evidence | Value |
|---|---|
| Focused test command | `node node_modules/.bin/vitest run tests/unit/answer-budget.spec.ts tests/unit/use-interview-outline.spec.ts tests/unit/use-interview-session.spec.ts tests/unit/embed-token-page.spec.ts`: green |
| Full suite (once) | `node node_modules/.bin/vitest run`: 132 files, 3164 tests passed |
| Other gates | `bun run lint`: exit 0; `bun run typecheck`: exit 0; pre-commit review gate (gga) passed on all four code commits |
| Runtime harness | N/A: nothing renders the outline, budget or ordinal yet (B.ii and C-slices consume them). The 202 and /start shapes are exercised through the real composable with a mocked `candidateFetch`; no local stack started |
| Rollback boundary | revert the four code commits (023d43e, b9f63af, 90db42e, 0b45f39) and a0bf72d; nothing consumes the new fields |

### Authored size (git diff --numstat; insertions + deletions, excluding `openapi.json` and `types/api.ts`)

| Commit | Lines |
|---|---|
| a0bf72d | 262 (generated, excluded) |
| 0b45f39 | 92 |
| 90db42e | 201 |
| b9f63af | 196 |
| 023d43e | 151 |
| Total authored | 638 (forecast ~300; about 420 of them are tests) |

Over the 400 budget; it cannot shrink without dropping tests (strict TDD). Recommend `size:exception` for B.i, or accept that the estimate was low (tests were ~65% of the diff).

### Deviations from design/tasks

1. **`useInterviewSession` reset on `sessionId` change uses a `flush: 'sync'` watcher.** A default (pre) watcher could wipe a 202 that lands right after the swap.
2. **`recordPrimaryIndex` / `isPositiveNumber` helpers** shared by both utterance paths and the /start seeding; `Outline` type is exported from `useInterviewOutline`.
3. **`makeStartResponse` fixture extended** (`competency_ordinal`, `total_competencies`, sent only when named) so absent fields stay representable. Existing fixtures are unchanged.
4. **Embed test passes at birth.** The page already reads `endedCompetencies ?? 0` and `totalCompetencies ?? 0`; the test pins it. The real coupling (total present when `sessionId` first changes) is tested at composable level.
5. **Crossfade side effect.** During a handover, the incoming `/start` seeds `competencyOrdinal` (and `primaryIndex` reset to null) while the outgoing competency still plays, until the swap. Harmless today (nothing renders them); C-slices should be aware.

### Issues found

- Existing UI behaviour changes slightly by design (M1): `InterviewSession.vue` progress now reads `0 / N` from the first competency instead of `0 / 0`. The full suite stayed green, so no existing test pinned the old value.
- gga flagged two unrelated pre-existing comment inaccuracies in `useInterviewSession.ts` (the "D5" block above `UTTERANCE_DRAIN_CEILING_MS`); left alone as separate cleanup.
- The wrapper working tree still has `M api` / `M backoffice` / `M frontend` pointer changes and the untracked `odd/tasks/seamless-primary-transition.md`: not staged.

## Review follow-ups (A.v, api)

Branch `feature/licc-a5-review-followups` (base `feature/licc-a4-persona-import`), commits `811f68d` and `16201bd`. 69 authored lines excluding `openapi.json` (103 added / 8 deleted including it). Strict TDD.

| # | Finding | RED | GREEN |
|---|---|---|---|
| 1 | Outline session pick not deterministic | Not reproducible: `interview_sessions` has `unique(participant_id, competency_code)`, so duplicate rows cannot exist (the seeding insert hit SQLSTATE 23505). Nothing changed, test dropped. | n/a |
| 2 | Outline documents only 200/401 | `InterviewOutlineDocumentedTest` 1 failed | 3/3; `#[Response]` 200/403/422 replace `@scramble-return`; export against PostgreSQL now lists 200, 401, 403, 422 |
| 3 | `persona: null` accepted | `PersonaDisplayNameWriteTest` 2 failed (one per surface) | passes; `nullable` removed from the persona rule, `persona: {}` still clears |
| 4 | Non-string imported display_name | Passed at birth (characterization): `isset` + `PersonaDisplayName::problem` already yield a clean 422 | 3 dataset cases pass |
| 5 | Unicode-space-only name | `PersonaDisplayNameTest` 3 failed | passes; length check trims `[\s\p{Z}]` |
| 6 | Separator-split provider names | `PersonaDisplayNameTest` 4 failed | passes; `LiveKitBot`, `Dailyn`, `Heygenie`, `Taverna`, `Live Aviator` stay accepted (documented in the rule docblock) |

Verification: `php artisan test --parallel` 9716 tests, 9704 passed, 12 skipped, lines 98.24%; `vendor/bin/pint --test` and `composer analyse` clean.

Open: `InterviewController` re-offer path reads the session with an unordered `first()`, and `CompetencyProgress::resolveNext` uses an unordered `keyBy`; both are unreachable duplicates for the same DB-constraint reason, left untouched.

## Batch 5 (Slice B.ii, frontend, part 1): T-B2.1 to T-B2.3 complete; T-B2.4, T-B2.5 pending

Mode: Strict TDD. Delivery: auto-chain, feature-branch-chain. Nothing pushed, no PR opened. api/ and backoffice/ untouched.
Stopped at a clean task boundary: this commit alone is 474 authored lines (about 415 tests), over the 400 budget, so the orchestrator splits the rest (timer, captions preference) into its own unit.

### Branch and commit (frontend)

| Branch | Base | Commit | Task |
|---|---|---|---|
| `feature/licc-b2-mic-answer-timer` | `feature/licc-b1-outline-data` (023d43e) | 8584d60 `feat(interview): keep the candidate's microphone choice across boundaries` | T-B2.1 to T-B2.3 |

### TDD Cycle Evidence

| Task | Test file | Safety net | RED (observed) | GREEN | Triangulation / refactor |
|---|---|---|---|---|---|
| T-B2.1/T-B2.2 | `tests/unit/use-interview-session-mic.spec.ts` (14 tests) | the 5 `use-interview-session*` specs: 237/237 | 15 failed (`session.setMicMuted is not a function`; the rest of the 252 passed) | same files: 252/252 | muted and unmuted at each of: lost `/end` race (boundary and handover), steering ack, promotion; plus failed steering, pause directive at boundary and handover, choice made mid-boundary and mid-handover, reload. Mutation: promotion reverted to an unconditional `setMicMuted(false)` fails the muted-promotion test |
| T-B2.3 | `tests/unit/avatar-player-mic.spec.ts` (7 tests) | `avatar-player.spec.ts` 28/28 | 2 failed (`micMuted only`, `reads the prop once`); the other rows pass at birth by design (existing `muted` seed) | 35/35 | 5 seed rows, prop read once after a pending `start()` resolves and later flips ignored, video never muted by `micMuted` |

### Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused test command | `node node_modules/.bin/vitest run tests/unit/avatar-player tests/unit/use-interview-session tests/unit/interview-session tests/unit/interview-handover`: 12 files, 430 passed |
| Full suite (once) | `node node_modules/.bin/vitest run`: 134 files, 3186 tests passed |
| Other gates | `bun run lint`: exit 0; `bun run typecheck`: exit 0; `prettier --check`: clean; pre-commit review gate (gga) passed |
| Runtime harness | N/A: no UI toggles the choice yet (C1a). The mock providers drive the real composable through boundary, continuation and handover paths; no local stack started |
| Rollback boundary | revert 8584d60; inert without UI |

### Authored size (git show --numstat; insertions + deletions)

8584d60: 474 (app 49: composable 36, player 12, page 1; tests 425: new mic specs 408, edited existing specs 17). Over the 400 budget; it cannot shrink without dropping tests. Recommend `size:exception` for this unit or accept the ~330 B.ii forecast was low.

### Deviations from design/tasks

1. **Line numbers moved** (B.i shifted them); the six re-open sites were found by search: promotion, handover `noop` and `pause/done` branches, `assertBoundary` finally, and both `applyContinuation` reopen points.
2. **Existing specs touched.** `avatar-player.spec.ts` asserted the exact prop list and `not.toContain('micMuted')`; it now lists `micMuted` (uplink-only prop, D9 rule 3). The three page specs that stub the session (`interview-session.spec.ts`, `-guards`, `-page`) gained `micMuted: ref(false)` because `InterviewSession.vue` now reads `session.micMuted.value`. No assertion was weakened.
3. **No test for the unreachable "restore failure" rejection path.** `restoreMic` swallows a provider rejection like every other call site.

### Issues found

- The mute toggle is not rendered yet (C1a), so `setMicMuted` has no UI caller; the gate review noted it and accepted it.
- The wrapper working tree still has pointer changes and the untracked `odd/tasks/seamless-primary-transition.md`: not staged.

## Batch 6 (frontend: B.ii part 2, C1a, C1b): complete

Completed: T-B2.4, T-B2.5, T-C1a.1 to T-C1a.5, T-C1b.1 to T-C1b.4. Mode: Strict TDD. Delivery: auto-chain, feature-branch-chain. Nothing pushed, no PR opened. api/ and backoffice/ untouched.
Each slice branch is stacked on the previous one; five slices were cut so no branch is far above the ~400 budget (every commit is a whole task unit, so none was cut mid-commit).

### Branches, bases and authored size (insertions + deletions, excluding regenerated Playwright snapshots and the regenerated `theme.spec.ts.snap`)

| Branch | Base | Commits | Authored lines |
|---|---|---|---|
| `feature/licc-b2b-answer-timer-captions` | `feature/licc-b2-mic-answer-timer` (8584d60, untouched) | 92d4476 `feat(interview): add the answer timer driven by the speaker signal` (T-B2.4, 323), 96f77bf `feat(interview): persist the captions preference` (T-B2.5, 103) | 426 |
| `feature/licc-c1a-call-header` | `feature/licc-b2b-answer-timer-captions` | 1b29f3d `feat(canvas): let a screen render the logo without the white plate` (T-C1a.1, 99), 817314b `feat(interview): add the live call header` (T-C1a.2, 350) | 449 |
| `feature/licc-c1a-call-header-2` | `feature/licc-c1a-call-header` | f72d5cb `feat(interview): move Exit into the call header with a visible label` (T-C1a.3 + T-C1a.4, 401), 4f92fac `test(arch): guard the call header inventory, bindings and the single timer role` (T-C1a.5, 61), 0d22332 `test(e2e): cover the live call header, tab order and the outline route` (64) | 526 |
| `feature/licc-c1b-captions-overlay` | `feature/licc-c1a-call-header-2` | 2f5d2b2 `feat(theme): add the caption prefix colour token held to 4.5:1` (T-C1b.1, 79), b25c2a5 `feat(interview): show the question as captions over the interviewer video` (T-C1b.2, 404) | 483 |
| `feature/licc-c1b-captions-overlay-2` | `feature/licc-c1b-captions-overlay` | d6da524 `feat(interview): show names on the call tiles with a legible chip` (T-C1b.3, 200), 4ddeb36 `fix(interview): keep the third caption line from being clipped` (8), d5aaa07 `test(interview): guard captions placement and cover captions off end to end` (T-C1b.4, 176) | 384 |

Every slice is over or near 400 because tests are about 60% of each diff (strict TDD); none can shrink without dropping tests. Recommend `size:exception` for c1a-2 (526) and c1b (483), or accept the 350/330 forecasts were low.

### TDD Cycle Evidence

| Task | Test file(s) | Safety net | RED (observed) | GREEN | Triangulation / refactor |
|---|---|---|---|---|---|
| T-B2.4 | `tests/unit/use-answer-timer.spec.ts` (15) | n/a (new) | module not found, "no tests" | 15/15 | every D10 row, 12 s silence reads 12, no reset on candidate speech, 3 s pause, avatar resets to listening, candidate while idle and while listening, session change, `live()` false, speaker already talking after a session change, one interval, scope disposal. Mutations: `seconds = 0` on every candidate transition fails 2 tests; a redundant reset the first mutation exposed was deleted (listening always holds 0) |
| T-B2.5 | `tests/unit/use-captions-preference.spec.ts` (5) | n/a (new) | module not found | 5/5 | default on, off survives a re-instantiation, back on, storage throwing on read and write (console.error spy proves the error is swallowed; mutation: dropping `onError` fails it), no network. The throwing storage is spied on the `localStorage` instance: a `Storage.prototype` spy stops applying once the instance has been used |
| T-C1a.1 | `brand-canvas.spec.ts` (+5) | 38 tests green | 2 failed (no bare logo, `header-end` class) | 38/38, `brand-canvas-contrast` 106 | bare logo, default and explicit `plate: true` keep the plate, same-colour logo gets no compensation, wordmark untouched. Mutation: `v-if="logoUrl"` fails the parent-is-HEADER test |
| T-C1a.2 | `call-header.spec.ts` (22) | n/a (new) | module not found | 22/22 | order, three buttons only, EN labels, clock (sr-only prefix, `<time>`, no live region or role), pressed/unpressed and icon swap, `aria-disabled` stays focusable and inert, 44 px, it/en keys. Mutation: dropping the click guard fails the inert test |
| T-C1a.3 | `call-exit.spec.ts`, `call-panel.spec.ts` | 51 | 2 failed (short label and aria-label; panel still had Exit) | 53/53 | it/en "name starts with the visible word" check; help link is the last focusable of the panel |
| T-C1a.4 | `interview-session.spec.ts` (+17) | 63 | 30 failed (no header, plate, title, outline, mic) | 63/63 | bare logo while live and plate on the consent screen, title (standard, potential, null, blank, failed, empty outline), outline once on live / on `advanceAttribution` / not per utterance / not on a same-session resume, captions toggle, mic toggle, boundary and handover disable and show muted then restore, a candidate's own mute survives both. Mutation: dropping `&& !session.micMuted.value` (later task) fails its test |
| T-C1a.5 | `arch/call-ui-arch.spec.ts` (+6) | 21 | rules pass at birth (the implementation already conforms); each rule proven with a mutation: `role="timer"` in the header fails 2, an extra `<CallHeader>` binding fails 1, an `#exit` slot back on the panel fails 1 | 27/27 | exact binding list, VISUAL mic state and forced-mute disable, one `role="timer"` in `InterviewTimer.vue`, plain `<time>` clock, no exit slot |
| T-C1b.1 | `brand-theme.spec.ts` (+10), `token-parity.spec.ts` (+1) | 49 | 11 failed (token missing) | 62/62; `theme.spec.ts.snap` regenerated, diff is the new token only | 7 brand colours at >= 4.5:1, hue kept (#771aaf gives #ae77cf), differs from the ribbon edge, `--color-primary-light` unchanged, Quint default `#cb43da` (4.55:1) equals `ensureContrast('#c222d3', '#0f172a', 4.5)`. Mutation: floor 4.5 to 3 fails 4 |
| T-C1b.2 | `call-question.spec.ts` (+14), `call-stage.spec.ts`, `interview-session.spec.ts` (+9) | 31, 63 | 14 failed + 17 failed | 31/31, 73/73 | prefix (4.5:1 token, markup inert, none on the hint), opaque overlay classes and insets, off (`sr-only`, no tabindex, region still written, hint carried, back on shows latest, no focus), page wiring (inside the avatar layer after the tile, persona name or generic, off persists, off + boundary moves no focus) |
| T-C1b.3 | `call-tile-contrast.spec.ts`, `call-tile.spec.ts`, `call-self-view.spec.ts`, `interview-session.spec.ts` | 130 | 7 failed | 130/130 | chip `bg-black/60 text-white` composites to #666666 (5.74:1) over white, name shown, blank/missing/failed -> "Tu"/"You", markup inert, chip not focusable, ring only for `candidate && !micMuted`. Mutation: dropping `!micMuted` fails the ring test. The markup-inert and "missing name" rows pass at birth (existing behaviour pinned) |
| T-C1b.4 | `arch/call-ui-arch.spec.ts` (+4), `e2e/interview-call.spec.ts` | 27 | arch rules pass at birth, proven with a mutation (a second `<CallQuestion>` outside the layer fails); e2e failed on the old band assumptions (single-column geometry, snapshots) | 31/31; e2e 56 passed | captions e2e (overlay clear of chip and own tile, off hides every visible word but keeps the region, choice remembered in a fresh page of the same context, off + boundary moves no focus), axe with a caption and with captions off at `#ffd400` and `#771aaf` |

### Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused test commands | `node node_modules/.bin/vitest run tests/unit/use-answer-timer.spec.ts tests/unit/use-captions-preference.spec.ts` (20); C1a: `brand-canvas`, `call-header`, `call-exit`, `call-panel`, `interview-session`, `arch` specs; C1b: `brand-theme`, `token-parity`, `call-question`, `call-stage`, `call-tile*`, `call-self-view`, `interview-session`, `arch` specs. All green |
| Full vitest (once per slice) | b2b: 136 files, 3206 tests; c1a-2: 137 files, 3274; c1b-2: 137 files, 3333; all passed |
| Other gates | `bun run lint` exit 0 and `bun run typecheck` exit 0 at every commit boundary; `prettier --check` clean; pre-commit review gate (gga) PASSED on every commit |
| Playwright (Chromium and WebKit, local) | `interview-call.spec.ts`: 50 passed after c1a, 56 passed after c1b. Full `bun run test:e2e` run twice: 381 passed + 1 flaky failure (`root-landing` webkit), then 391 passed + 1 flaky failure (`unsupported-gate` webkit mobile redirect); each passed alone on re-run. The 1440x900 pixel baselines (4 PNGs, darwin) were regenerated in c1a-2 and again in c1b-2 on purpose; the pinned-container (linux) baselines were NOT regenerated and must be refreshed with `task e2e:update` before CI |
| Runtime harness | Playwright against the dev server with mocked API routes (the new `outline` route lives in `tests/e2e/fixtures/branded-interview.ts`); no local docker stack started |
| Rollback boundary | per branch: revert the branch commits; b2b is inert without UI, c1a restores the previous header and the panel Exit, c1b restores the question band |

### Deviations from design/tasks

1. **T-C1a.3 and T-C1a.4 share one commit** (f72d5cb). The page specs cannot be green with Exit in neither the panel nor the header, so the panel change and the page wiring land together.
2. **The arch inventory gained `CallHeader.vue` in T-C1a.2's commit**, not in T-C1a.5, so no commit leaves the arch spec red. T-C1a.5 still adds the binding, timer-role and exit-slot rules; no rule was loosened.
3. **Header buttons use the card pair** (`bg-card text-card-foreground`) instead of the outline variant's `bg-background`: the existing page guard ("nothing on the bare canvas assumes a white page") forbids `bg-background`, and the card tokens are the design's "white outline buttons". The guard was not edited. The same two classes were added to the `CallExitDialog` trigger.
4. **T-C1b.1**: `canvas-brand-fallbacks.spec.ts` was not extended. `VoiceVisualizer` has no canvas fallback for the caption token (it is not read there), so the parametrized fallback check would assert a fallback that does not exist. The binding is instead `token-parity.spec.ts` (authored hex) plus `brand-theme.spec.ts` (authored hex equals `ensureContrast('#c222d3', '#0f172a', 4.5)`), and the `theme.spec.ts` snapshot of the `@theme` block was regenerated.
5. **Caption prefix colon** is rendered as `{{ `${speakerName}:` }}`: the arch rule bans literal text nodes in `Call*.vue`, so the separator is an expression instead of the rule being relaxed. The space between prefix and text is `{{ ' ' }}` for the same reason (and for Prettier, which otherwise removes it).
6. **Overlay padding**: `py-0` (committed as a fix). At the capped 6 rem height, vertical padding clipped the third line of `leading-8` text instead of letting it scroll.
7. **`useAnswerTimer` re-applies the current speaker after a session change or `live` returning**: a crossfade that keeps the interviewer speaking would otherwise lose the whole answer timer for the next competency (`avatar -> none` while `idle` is not a transition in the D10 table).
8. **Outline refresh rule**: the page refetches when the live screen shows with a session id it has not fetched yet, so a resume of the same session after a pause does not refetch; a boundary through `connecting` (live to not live to live with a new id) does.
9. **Existing page-spec stub changes**: `interview-session.spec.ts` no longer stubs `micMuted` (the header toggles the real one), derives the stubbed `handoverInFlight` as `handover || boundary` (the real definition), and its `useI18n` stub echoes params so the title composition is readable. No assertion was weakened.
10. **DESIGN.md drift (not fixed here)**: DESIGN.md section 7.3 still says the title is "Colloquio . {role}"; the spec and tasks say "Colloquio di assessment . {role}" and the page follows the spec. Fix in the slice-0 branch.

### Issues found

- **An unrouted `GET /candidate/interview/outline` hijacks the interview in e2e**: the Nuxt server answers 401 and `candidateFetch` treats that as an expired session, so the embed specs stalled after the first end phrase. Real 401s from the outline therefore behave like any other candidate call; other failures keep the bare title. The fixture now routes it. Any other e2e spec that stubs the candidate API without `mockBrandedInterview` will need the same route.
- The `unsupported-gate` and `root-landing` WebKit failures in the full run are load-related flakes (pass alone), unrelated to this change.
- gga flagged nothing blocking; it suggested typing the e2e outline fixture with `satisfies` against the generated contract (optional, not done).
- The wrapper working tree still has `M api` / `M backoffice` / `M frontend` pointer changes and the untracked `odd/tasks/seamless-primary-transition.md`: not staged. Last commit of the previous batch (b2 branch, 8584d60) was left untouched.
