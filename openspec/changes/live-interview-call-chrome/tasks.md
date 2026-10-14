# Tasks: Live Interview Call Chrome (Header, Interview Panel, Captions)

Inputs: `proposal.md`, `specs/{interview-session,interview-frontend,avatar-templates,admin-backoffice}/spec.md`,
`design.md` (corrective revision 2026-10-14). The SPEC wins over the design where they disagree (see "Spec and design
mismatches"). Strict TDD is on: every implementation task is RED (observed failing test) -> GREEN -> REFACTOR, closed by
ONE work-unit commit holding tests and code together. English only (i18n locale files excepted).

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~3,170 authored lines across 12 slices (generated `openapi.json`, `types/api.ts`, Playwright snapshots excluded) |
| 400-line budget risk | High as one change; Low-Medium per slice (tightest: C1a, C1b, A.iii) |
| Chained PRs recommended | Yes |
| Suggested split | 0 -> A.i -> A.ii -> A.iii -> (A2 ‖ B.i) -> B.ii -> C1a -> C1b -> C2a.1 -> C2a.2 -> C2b |
| Delivery strategy | auto-chain |
| Chain strategy | feature-branch-chain |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

Per-slice estimate (authored additions + deletions, tests included):

| Slice | Repo | ~Lines | Note |
|---|---|---|---|
| 0 | wrapper | ~170 | `DESIGN.md` only. The SDD artifacts are a separate docs-only commit (T0.0), not counted |
| A.i | api | ~200 | |
| A.ii | api | ~330 | |
| A.iii | api | ~380 | Tightest api slice. Split trigger: if T-A3.3 to T-A3.5 push the diff over 400, move T-A3.4 (import) to `feature/licc-a4-persona-import` based on A.iii |
| A2 | backoffice | ~140 | |
| B.i | frontend | ~300 | design said ~260; +40 for the `/start` (read-only) total seeding (M1) |
| B.ii | frontend | ~330 | |
| C1a | frontend | ~350 | includes removing the `exit` slot from `CallPanel` (Exit would otherwise be duplicated) |
| C1b | frontend | ~330 | |
| C2a.1 | frontend | ~230 | NEW: C2a split (storyboard + Percorso + Durata) |
| C2a.2 | frontend | ~230 | NEW: C2a split (answer timer + bands + chip + arch panel rules) |
| C2b | frontend | ~200 | |

### Suggested Work Units

Branch bases follow `feature-branch-chain`: the first child of a repo targets that repo's tracker
`feature/live-interview-call-chrome`; each later child targets the immediately previous slice branch. Only the four
trackers merge to `develop`.

| Unit | Goal | Likely PR (branch -> base) | Focused test command | Runtime harness | Rollback boundary |
|------|------|----------------------------|----------------------|-----------------|-------------------|
| 0 | UX source of truth amended before any UI | `feature/licc-0-design-docs` -> wrapper tracker | `rg -n "22rem\|primary-caption\|captions overlay" DESIGN.md` (doc-only) | N/A: documentation, no runtime | Revert with C1a-C2b |
| A.i | One owner of competency order and "open" | `feature/licc-a1-competency-progress` -> api tracker | `php artisan test --parallel --filter='CompetencyProgress\|QuestionIndexZeroBased\|CompletionCas\|RecoverFailedParticipant\|DraftContentIsolation'` | `POST /api/candidate/interview/start` on the local stack returns the same competency as before | Revert one PR; behaviour byte-identical |
| A.ii | Outline endpoint | `feature/licc-a2-outline` -> `feature/licc-a1-competency-progress` | `php artisan test --parallel --filter=InterviewOutline` | `curl -H "Authorization: Bearer <candidate jwt>" /api/candidate/interview/outline` on the local stack | Revert; additive, no consumer yet |
| A.iii | `primary_index` + persona display name | `feature/licc-a3-utterance-persona` -> `feature/licc-a2-outline` | `php artisan test --parallel --filter='Utterance\|PersonaDisplayName\|AvatarTemplate\|Exposure'` | `POST /utterance` returns `primary_index`; admin PATCH of a template with a bad `persona.display_name` returns 422 | Revert; additive, no migration |
| A2 | Backoffice persona input | `feature/licc-bo-persona-name` -> backoffice tracker | `node node_modules/.bin/vitest run tests/unit/avatar-template-form` | Backoffice dev server: save and reopen a template with a name | Revert; saved names stay in JSON |
| B.i | Outline + budget + `primaryIndex` + `/start` (read-only) totals | `feature/licc-b1-outline-data` -> frontend tracker | `node node_modules/.bin/vitest run tests/unit/answer-budget.spec.ts tests/unit/use-interview-outline.spec.ts tests/unit/use-interview-session.spec.ts` | Mock-provider interview: network tab shows `GET /outline` once on live | Revert; nothing renders it yet |
| B.ii | Mic intent, answer timer, captions pref | `feature/licc-b2-mic-answer-timer` -> `feature/licc-b1-outline-data` | `node node_modules/.bin/vitest run tests/unit/use-interview-session-mic.spec.ts tests/unit/use-answer-timer.spec.ts tests/unit/avatar-player-mic.spec.ts tests/unit/use-captions-preference.spec.ts` | Mock-provider interview, mute then force a boundary | Revert; inert without UI |
| C1a | Live header | `feature/licc-c1a-call-header` -> `feature/licc-b2-mic-answer-timer` | `node node_modules/.bin/vitest run tests/unit/call-header.spec.ts tests/unit/brand-canvas.spec.ts tests/unit/call-exit.spec.ts tests/unit/arch/call-ui-arch.spec.ts` | `bun run dev` mock interview: header controls render in `#ffd400` and `#771aaf` | Revert; previous header returns |
| C1b | Captions overlay, caption token, chips | `feature/licc-c1b-captions-overlay` -> `feature/licc-c1a-call-header` | `node node_modules/.bin/vitest run tests/unit/call-question.spec.ts tests/unit/brand-theme.spec.ts tests/unit/call-tile-contrast.spec.ts tests/unit/call-stage.spec.ts tests/unit/arch/` | Playwright `interview-call.spec.ts` captions-off + tab order + axe | Revert; band returns |
| C2a.1 | Storyboard + Percorso + Durata | `feature/licc-c2a1-storyboard` -> `feature/licc-c1b-captions-overlay` | `node node_modules/.bin/vitest run tests/unit/call-storyboard.spec.ts tests/unit/call-panel.spec.ts` | Mock interview: storyboard names, "Competenza 1 di N" on the first competency | Revert; old panel returns |
| C2a.2 | Answer timer, chip, bands | `feature/licc-c2a2-answer-timer` -> `feature/licc-c2a1-storyboard` | `node node_modules/.bin/vitest run tests/unit/call-answer-timer.spec.ts tests/unit/call-panel.spec.ts tests/unit/arch/call-ui-arch.spec.ts` | Mock interview: timer reads 00:12 after 12 s of silence; chip follows speaker | Revert; section 1 disappears |
| C2b | Stage grid, 22 rem, e2e, snapshots | `feature/licc-c2b-stage-sizing` -> `feature/licc-c2a2-answer-timer` | `node node_modules/.bin/vitest run tests/unit/call-stage.spec.ts` then `bun run test:e2e -- interview-call.spec.ts browser-gate-middleware.spec.ts` | Playwright at 1280x800, 1440x900, 1920x1080, 1024 | Revert; single-column stage returns |

Parallelism: slice 0 runs in parallel with A.i-A.iii. After A.iii exports `openapi.json`, A2 and B.i run in parallel
(different repos). B.i -> B.ii -> C1a -> C1b -> C2a.1 -> C2a.2 -> C2b are strictly sequential (same files). C1a needs
slice 0 merged into the wrapper tracker.

## Spec and design mismatches found (SPEC followed; do not guess further)

| # | Spec says | Design says | Resolution used in these tasks |
|---|---|---|---|
| M1 | "Competenza n di N" with the `/start` (read-only) total; scenario "Progress reads N/N" and "never x/0" | Hidden during the first competency; total only from `/end` (read-only) (Open Question 2) | T-B1.5 stores `total_competencies` and `competency_ordinal` from `/start` (read-only). `endedCompetencies` stays `/end` (read-only)-only (it feeds `hasRunACompetency` and the embed page). Panel numerator = `ended ?? (ordinal - 1)`, clamped. Embed page gets a regression test (`pages/embed/[token].vue:281-282`). Risk: in an evaluation-retry run `ordinal` can exceed the `/end` (read-only) tally; the spec numerator is `question_index + 1`, so the ordinal is the closer source. |
| M2 | Forced mutes (boundary AND handover) disable the toggle and show muted ("during the boundary the control is present, disabled and shows muted") | D9 rule 5: toggle stays enabled during a boundary | Code already agrees with the spec: `handoverInFlight = handoverActive \|\| boundaryInFlight` (`useInterviewSession.ts:638`). `micDisabled = session.handoverInFlight`, visual = `micMuted \|\| handoverInFlight`. T-C1a.4 pins it; T0.1 corrects the D9 wording in `design.md`. |
| M3 | Duration (bar, "{elapsed} / {max}", remaining sentence, visible countdown) hidden until the SERVER states `interview_max_seconds`; the 300 s fallback is never a maximum; `InterviewTimer` stays mounted | "Shown under the existing condition" (today `hasTotal`, with a `total x secondsPerQuestion` fallback, `CallPanel.vue:28`) | T-C2a1.3 gates the duration on `maxSeconds` only, removes the `secondsPerQuestion` fallback, and hides the visible countdown with `v-show` (stays mounted, still ticks, enforces `timeout`). |
| M4 | Backoffice: clearing sends NO `persona.display_name` key and no empty string | D7: clear = `display_name` null/empty; "persona absent -> column untouched" | A key that is simply absent cannot clear. T-A3.3 defines: `persona` PRESENT without a `display_name` (or with null) UNSETS it; `persona` ABSENT leaves the column untouched. T-A2.3 sends `persona: {}` on clear in update (no key, no empty string). The RED test pins both. |
| M5 | Backoffice payload carries "the other persona fields unchanged" | Resource returns only `display_name`; server rule `array:display_name`; other keys survive by server merge | Payload carries `persona.display_name` only; imported keys are preserved server-side (T-A3.3 merge test). Spec wording should read "does not discard". |
| M6 | Caption prefix is `--color-primary-light` | Dedicated `--color-primary-caption` (4.5:1) because `--color-primary-light` is the 3:1 ribbon token | Follow the design token; the scenario (brand light variant, >= 4.5:1) is satisfied. Spec text should name `--color-primary-caption`; flagged for archive-time spec sync. |
| M7 | Captions preference stored in the browser, unreadable storage defaults to on and still toggles | D17: inline `useLocalStorage` in `InterviewSession.vue` | Wrapped in `app/composables/useCaptionsPreference.ts` (with `onError` swallowed) so the unreadable-storage scenario is unit-testable. Same dependency, no new library. |
| M8 | n/a | Open Question 2 (design.md) becomes obsolete after M1 | T0.1 closes it in `design.md`. |

## Phase 0: Trackers and wrapper docs (slice 0)

- [x] T0.0 Trackers and artifacts (wrapper; docs-only, outside the review budget)
  - Slice 0, repo wrapper. Files: create branch `feature/live-interview-call-chrome` from `develop` in the wrapper, `api`, `backoffice`; in `frontend` create it from `feature/seamless-primary-transition` (R8) or from `develop` once frontend PR #95 is merged. `openspec/changes/live-interview-call-chrome/{proposal,design,tasks}.md`, `specs/**/spec.md` (existing, uncommitted).
  - Test-first: N/A (branching and docs). Acceptance: `git -C frontend merge-base --is-ancestor <#95 tip> HEAD` is true; `rg -n "boundaryInFlight" frontend/app/composables/useInterviewSession.ts` matches; the frontend tracker PR is never merged before #95.
  - Commit (wrapper tracker): `docs(openspec): add live-interview-call-chrome change artifacts`

- [x] T0.1 Amend `DESIGN.md` and fix `design.md` drift
  - Slice 0, repo wrapper, branch `feature/licc-0-design-docs` -> wrapper tracker. Files: `DESIGN.md` (§3.1 `--color-primary-caption` 4.5:1 on avatar-bg; §3.3 `--spacing-call-panel` 22rem; §7.0.1 bare logo while live, `header-end` spans the row, `CallHeader`, clock with accessible name and no live region, tab order; §7.3 diagram and bullets: header controls and title, captions overlay replaces the question band, "Intervista" panel sections, bands as guidance only, answer timer counts from the end of the question, approximate plus exact remaining time, storyboard names competencies (reversal recorded), competency progress kept, persona name with generic fallback, `bg-black/60` chips, mute is silence to the provider, mute persists across boundaries and resets on reload, forced mutes disable the toggle (M2), Exit visible "Esci" with the resume hint as accessible name); `openspec/changes/live-interview-call-chrome/design.md` (D9 rule 5 -> spec wording per M2; Open Question 2 closed per M1/M8; D14 section 3 gate per M3).
  - Test-first: RED = `rg -n "never a competency name|no status pill|min/ideal/max" DESIGN.md` still matches the old rules; GREEN = it no longer matches and `rg -n "22rem" DESIGN.md` matches §3.3.
  - Acceptance: the five old rules (empty live header, no status pill, no band, no competency name, 18rem) are gone; every new rule cites D-number or spec requirement; no UI file is touched.
  - Commit: `docs(design): describe the live call chrome, panel and captions overlay`

## Phase 1: api (slices A.i, A.ii, A.iii). Runner: `php artisan test --parallel`, `composer analyse`, `vendor/bin/pint --test`

### Slice A.i: `feature/licc-a1-competency-progress` -> api tracker

- [x] T-A1.1 RED: `CompetencyProgress` tests
  - Files: `api/tests/Unit/Support/Interview/CompetencyProgressTest.php` (create).
  - Test-first: `isOpen()` truth table: null session, `pending`, `in_corso`, `error` with attempts left (`< InterviewSession::MAX_ERROR_ATTEMPTS`), `error` exhausted, `completed`, `timeout`, `skipped`; `ordered($projectId)` returns rows by `pc.position` and only that project's rows (two projects, same codes); `resolveNext()` equals the current controller output on the fixtures of the four existing tests (including `reoffer` flag, `competency_ordinal`, `total_competencies`). Observe RED (class missing).
  - Acceptance: fails for the right reason only. No commit yet (committed with T-A1.2).

- [x] T-A1.2 GREEN + REFACTOR: extract `CompetencyProgress`, rewire the controller
  - Files: `api/app/Support/Interview/CompetencyProgress.php` (create: `ordered()`, static `isOpen()`, `resolveNext()`); `api/app/Http/Controllers/Candidate/InterviewController.php` (move `resolveNextCompetency` / `competencyPayload` `:1003-1068` into the helper; call site `:241` uses `$this->competencyProgress->resolveNext(...)`; `freshRemainingCompetencies` `:897-920` uses `ordered()`; inject via constructor).
  - Acceptance: T-A1.1 green; `QuestionIndexZeroBasedTest`, `CompletionCasTest`, `RecoverFailedParticipantTest`, `DraftContentIsolationTest` pass UNMODIFIED (`git diff --stat` shows no edit to them); `composer analyse` and Pint clean; full `php artisan test --parallel` green. Run one Pest invocation at a time (shared test DB).
  - Commit: `refactor(interview): extract competency order and open rule into CompetencyProgress`

### Slice A.ii: `feature/licc-a2-outline` -> `feature/licc-a1-competency-progress`

- [x] T-A2.1 RED: outline feature tests
  - Files: `api/tests/Feature/Candidate/InterviewOutlineTest.php` (create).
  - Test-first (each is a spec scenario): standard shape (6 top-level keys, no `code`, `candidate_name` trimmed, `primary_total_all = 6`); potential -> `role_name` null; unset and invalid stored `avatar_name` (61 chars, `<`) -> null; blank participant name -> null; statuses `done,current,upcoming`; errored-with-attempts-left next -> `current`; evaluation-retry reset `done,current,done,retry`; exhausted attempts -> `done` then `current`; all closed while `in_corso` -> no `current`; terminal participant refused by `ParticipantStatusGuard`; unsupported `assessment_type` -> `422 assessment_type_not_supported`; frozen `primary_questions` snapshot beats live count; competency without primaries -> 0; English project + Italian `Accept-Language` -> English names; blank project-language translation falls back to `en`, both blank -> `null` name, never the code; cross-tenant (two orgs, same codes, org A sees only A); no token and expired token -> same status as `/candidate/session` (read-only); foreign `participant_id` / `session_id` query ignored and tables unchanged. Observe RED (404 route).
  - Acceptance: all fail for the right reason. No commit yet.

- [x] T-A2.2 GREEN: `BuildInterviewOutline`
  - Files: `api/app/Actions/Interview/BuildInterviewOutline.php` (create, D3/D4/D5; private name rule helper; one sessions query keyed by `competency_code`; `ResolvePrimaryQuestions` for rows without a snapshot, with the `// ponytail:` (read-only) comment from D4).
  - Acceptance: the status and field tests of T-A2.1 pass.

- [x] T-A2.3 GREEN: controller, route, contract
  - Files: `api/app/Http/Controllers/Candidate/OutlineController.php` (create, `show()`, `@scramble-return` per D4, `@internal` notes); `api/routes/api.php` (`Route::get('/outline', ...)` inside the nested `interview` group, `:930-953`).
  - Acceptance: all of T-A2.1 green including 401/terminal/422; `composer analyse`, Pint clean.
  - Commit (T-A2.1 to T-A2.3): `feat(interview): add the candidate interview outline endpoint`

- [x] T-A2.4 Contract export
  - Files: `api/openapi.json` (generated), plus the second api spec file named in the release recipe if the repo keeps one.
  - Command: `DB_CONNECTION=pgsql DB_HOST=127.0.0.1 DB_PORT=5432 DB_DATABASE=beai_test DB_USERNAME=postgres DB_PASSWORD=postgres DB_URL= php artisan scramble:export`; then run `ResourceMatchesSpecTest`.
  - Acceptance: spec diff contains only `outline.show`; `ResourceMatchesSpecTest` green. Never export against SQLite.
  - Commit: `chore(api): export openapi for the interview outline`

### Slice A.iii: `feature/licc-a3-utterance-persona` -> `feature/licc-a2-outline`

- [x] T-A3.1 `/utterance` (read-only) returns `primary_index`
  - Files: `api/tests/Feature/C7a/` utterance test (modify or create `UtterancePrimaryIndexTest.php`); `api/app/Http/Controllers/Candidate/UtteranceController.php` (D6: compute `matchedCount()` once after commit, pass to `recordUtteranceEvent()` as `max(0, $primaryIndex - 1)`, return `['boundary_due' => ..., 'primary_index' => ...]`, `#[Response(202, type: 'array{boundary_due: bool, primary_index: int}')]` at `:95`).
  - Test-first (RED first): 1 after the first primary; unchanged after a follow-up and a candidate turn; unchanged after a verbatim re-ask, next distinct primary yields 3; 0 before any primary; always 0 with no primaries; restarts at 1 after a re-offer; scoped to its own session; 409 body unchanged; `question_asked` event index unchanged; locked section still three statements (existing test).
  - Acceptance: tests green; existing utterance suite unmodified and green.
  - Commit: `feat(interview): return primary_index from the utterance endpoint`

- [x] T-A3.2 `PersonaDisplayName` rule
  - Files: `api/app/Rules/PersonaDisplayName.php` (create: `MAX = 60`, `problem()`, provider denylist regex from D7); `api/tests/Unit/Rules/PersonaDisplayNameTest.php` (create).
  - Test-first: 60 ok / 61 refused (`mb_strlen` after trim); `<`, `>`, `\n`, a format character refused; "HeyGen", "Hey Gen", "LiveAvatar", "live avatar", "Tavus Coach", "daily", "My LiveKit agent", "live kit" refused case-insensitively; a non-vendor word that merely contains none of them accepted; non-string refused; the message never contains the matched word.
  - Acceptance: truth table green. Commit: `feat(avatar-templates): add the PersonaDisplayName validation rule`

- [x] T-A3.3 Form rules, `mergePersona`, four write paths
  - Files: `api/app/Http/Controllers/Concerns/ValidatesAvatarTemplateWrites.php` (rules on store AND update: `'persona' => ['sometimes','nullable','array:display_name']`, `'persona.display_name' => ['nullable', new PersonaDisplayName]`; widen both docblocks to `list<string|ValidationRule>`; add `mergePersona()` per D7 and M4); `api/app/Http/Controllers/AvatarTemplateController.php` (`store` / `update` `:224`, `:256`); `api/app/Http/Controllers/Api/PlatformAvatarTemplateController.php` (`:145`, `:188`); tests under `api/tests/Feature/AvatarTemplates/` (create `PersonaDisplayNameWriteTest.php`).
  - Test-first (RED): 422 on create AND update for 61 chars, `<`, control char, provider name, unknown persona key; 422 body never contains the vendor name; error listed together with another invalid field; `"  Giulia  "` stored as `Giulia`; persona absent -> column untouched; `persona: {}` or `display_name: null` -> key UNSET (no stored `null`, no empty string) and the column becomes `null` when nothing is left; imported extra keys kept on update; platform controller behaves identically.
  - Acceptance: green; existing avatar template tests unmodified. Commit: `feat(avatar-templates): validate and merge persona.display_name on every write`

- [x] T-A3.4 Import validation (delivered on `feature/licc-a4-persona-import`, split from A.iii: the slice forecast exceeded 400 lines)
  - Files: `api/app/Support/AvatarTemplates/TemplateDocument.php` (`flatten()` `:74` trims a string `display_name`, unsets a blank one); `api/app/Http/Controllers/AvatarTemplatePortabilityController.php` (`reject()` `:117` returns `"persona.display_name: {problem}"`); test `api/tests/Feature/AvatarTemplates/PersonaImportTest.php` (create).
  - Test-first (RED): import with `Tavus`, 61 chars, `<b>` each fails with a `persona.display_name` error and creates no template; blank is dropped; export then import round-trips `Giulia` (inactive template); duplicate keeps the name and leaves the original unchanged.
  - Acceptance: green. Commit: `feat(avatar-templates): refuse an invalid persona display name on import`

- [x] T-A3.5 Accessor, resource, exposure
  - Files: `api/app/Models/AvatarTemplate.php` (`personaDisplayName()` returns trimmed value or `null` when `PersonaDisplayName::problem()` refuses it); `api/app/Http/Resources/AvatarTemplateResource.php` (`'persona' => ['display_name' => ...]` in `toArray()` and `@scramble-return`; inherited by `PlatformAvatarTemplateResource`); `api/tests/Helpers/PublicApi/ExposureCatalogue.php` (add `avatar_template.persona.display_name` to `exclusions()['Project']`, admin-only); tests `PersonaResourceTest.php`.
  - Test-first (RED): resource returns `persona.display_name` and no other persona key; a stored invalid legacy value degrades to `null`; `/v1` (read-only) project payloads never contain it; `ExposureTest` red until the catalogue entry exists, then green; no provider request body or header contains the name (existing avatar session issue tests extended).
  - Acceptance: `ExposureTest`, `ParticipantArchTest`, `ResourceMatchesSpecTest` green. Commit: `feat(avatar-templates): expose persona.display_name to admins and classify it`

- [x] T-A3.6 Contract export
  - Files: `api/openapi.json` (generated), then copy into `frontend/openapi.json` and `backoffice/openapi.json` (done in A2 and B.i, not here).
  - Command: the PostgreSQL `scramble:export` above. Acceptance: diff contains `primary_index` and `persona.display_name` only; `ResourceMatchesSpecTest` green.
  - Commit: `chore(api): export openapi for primary_index and persona display name`

- [ ] T-A3.7 api release gate (not a code task)
  - api tracker PR -> `develop`, then `release/*` per the release recipe BEFORE the consumers merge; A2 ships in the same release window (owner point O3).

## Phase 2: backoffice (slice A2). Runner: `node node_modules/.bin/vitest run`, `bun run lint`, `bun run typecheck`, `bun run test:e2e`

### Slice A2: `feature/licc-bo-persona-name` -> backoffice tracker

- [x] T-A2.1b Sync contract
  - Files: `backoffice/openapi.json` (copy from api), `backoffice/types/api.ts` (`bun run codegen`).
  - Acceptance: `check-client-drift.sh` clean. Commit: `chore(backoffice): sync openapi for persona display name`

- [x] T-A2.2b RED: form tests
  - Files: `backoffice/tests/unit/` avatar template form spec (modify the existing one or create `avatar-template-form-persona.spec.ts`).
  - Test-first: input labelled "Nome dell'intervistatore" / "Interviewer display name" with associated label, helper text, `maxlength=60` (80 typed chars hold 60); stored value loads on edit; editing an unrelated field submits the same `persona.display_name`; clearing submits `persona: {}` on update and NO `persona` on create (no empty string, M4); a 422 keyed `persona.display_name` renders next to the input, linked by `aria-describedby`, keeps the typed value and resets nothing else; no literal strings outside `it` / `en` locale files (existing locale-parity test).
  - Acceptance: red for the right reason.

- [x] T-A2.3 GREEN + REFACTOR: form field
  - Files: `backoffice/app/components/organisms/AvatarTemplateForm.vue` (draft field, input, `persona` in `submit` near `:1124-1132`, 422 key mapping); `backoffice/app/types/avatar-template.ts`; `backoffice/i18n/locales/{it,en}.json` (`avatar_templates.form.persona_display_name`, `_hint`, `errors.personaDisplayNameInvalid`, generic copy that names no vendor).
  - Acceptance: T-A2.2b green; `bun run lint`, `bun run typecheck`, full vitest green; `bun run test:e2e` avatar-template specs green (Chromium and WebKit); coverage not below 85%.
  - Commit: `feat(avatar-templates): add the interviewer display name to the template form`

## Phase 3: frontend data (slices B.i, B.ii). Runner: `node node_modules/.bin/vitest run`, `bun run lint`, `bun run typecheck`

### Slice B.i: `feature/licc-b1-outline-data` -> frontend tracker (stacked on #95, R8)

- [ ] T-B1.1 Sync contract
  - Files: `frontend/openapi.json`, `frontend/types/api.ts` (`bun run codegen`). Acceptance: types expose `operations['outline.show']` and `primary_index`; `check-client-drift.sh` clean.
  - Commit: `chore(frontend): sync openapi for the interview outline`

- [ ] T-B1.2 `answerBudget()`
  - Files: `frontend/tests/unit/answer-budget.spec.ts` (create, RED first); `frontend/app/utils/answer-budget.ts` (create, D11, `ANSWER_BUDGET_FRACTIONS`).
  - Test-first: `(1200, 6)` -> max 200, min 50, ideal 75-150; `(1210, 6)` -> max 201, min 50, ideal 75-151 (floor then round); `(1200, 0)`, `(null, 6)`, `(1200, undefined)`, `NaN`, negative -> `null`; `(5, 10)` (max < 1) -> `null`; the 300 s countdown fallback is not an input (guard documented in the test name).
  - Commit: `feat(interview): add the answer budget arithmetic`

- [ ] T-B1.3 `useInterviewOutline`
  - Files: `frontend/tests/unit/use-interview-outline.spec.ts` (create); `frontend/app/composables/useInterviewOutline.ts` (create, D12; type from `operations['outline.show']`).
  - Test-first: single-flight (second call while in flight issues no second request); trailing re-run once when marked dirty; failure keeps the previous value and never throws; failure on first call leaves `null`; per-instance state (two instances do not share).
  - Commit: `feat(interview): add the single-flight interview outline composable`

- [ ] T-B1.4 `primaryIndex` in `useInterviewSession`
  - Files: `frontend/tests/unit/use-interview-session.spec.ts` (modify); `frontend/app/composables/useInterviewSession.ts` (`primaryIndex` ref; set from the 202 body in `sendUtterance` `:988-992` and `deliverUtterance` `:889-896` only when the line's `dbSessionId` equals the current `sessionId`; reset to `null` on a successful `/start` (read-only) and on `sessionId` change; export read-only).
  - Test-first: set from 202; stale-session line ignored; reset on new `/start` (read-only); a 409 leaves it unchanged; a response without the field (older API) leaves `null`.
  - Commit: `feat(interview): track primary_index from utterance responses`

- [ ] T-B1.5 Seed the competency total from `/start` (read-only) (M1)
  - Files: `frontend/tests/unit/use-interview-session.spec.ts` (modify), `frontend/tests/unit/embed-progress.spec.ts` (create or extend the existing embed spec); `frontend/app/composables/useInterviewSession.ts` (near `:1780`: read `question_context.total_competencies` and `competency_ordinal`; set `totalCompetencies` when a positive number; add read-only `competencyOrdinal`; DO NOT touch `endedCompetencies`; update the "deliberately NOT stored" comment at `:1783-1788` to say the ordinal is the field now stored).
  - Test-first: after `/start` (read-only) with `total_competencies = 5`, `competency_ordinal = 3`, `totalCompetencies = 5` and `competencyOrdinal = 3` while `endedCompetencies` is still `null`; `/end` (read-only) later overwrites the total without flicker; a non-number total is ignored; total stable across competencies; the embed page posts `question:changed` with `total: 5` from the first competency and `index` unchanged (still `endedCompetencies ?? 0`); `hasRunACompetency` stays false until the first `/end` (read-only).
  - Acceptance: spec scenarios "Progress reads N/N with the real total, never x/0" and "Progress total is stable" have a unit counterpart; the existing `interview-session` and embed specs stay green.
  - Commit: `feat(interview): seed the competency total and ordinal from /start`

### Slice B.ii: `feature/licc-b2-mic-answer-timer` -> `feature/licc-b1-outline-data`

- [ ] T-B2.1 RED: microphone intent tests
  - Files: `frontend/tests/unit/use-interview-session-mic.spec.ts` (create).
  - Test-first (provider fakes): default `micMuted = false`; `setMicMuted(true)` calls the active provider; with `handoverInFlight` or `boundaryInFlight` set, `setMicMuted` records the intent and touches NO provider; intent survives a `noop` boundary AND a `sessionId` change AND a continuation; `restoreMic` re-applies the intent at each re-open site (incoming promotion `:1280`, handover directives `:1506` / `:1518`, `assertBoundary` finally `:1582`, `applyContinuation` `:1616` / `:1620`); a muted candidate stays muted after a handover; an unmuted candidate returns to unmuted; reload (new instance) starts unmuted; mute never calls `/end` (read-only).
  - Acceptance: red for the right reason.

- [ ] T-B2.2 GREEN: `setMicMuted`, `restoreMic`
  - Files: `frontend/app/composables/useInterviewSession.ts` (`micMuted` ref, `setMicMuted`, internal `restoreMic(handle)`, six call sites; forced mutes at `:1182` and `:1566` untouched; export `micMuted` read-only and `setMicMuted`).
  - Acceptance: T-B2.1 green; all existing `use-interview-session-*.spec.ts` unmodified and green.

- [ ] T-B2.3 `AvatarPlayer` seed
  - Files: `frontend/tests/unit/avatar-player-mic.spec.ts` (create); `frontend/app/components/AvatarPlayer.client.vue` (`micMuted?: boolean`, default `false`; seed at `:258` becomes `setMicMuted(props.muted || props.micMuted)`; keep the doc rule that `muted` is never bound to the candidate mic); `frontend/app/components/InterviewSession.vue` (bind `:mic-muted="session.micMuted.value"` on the live and incoming players).
  - Test-first: seeds `true` when `micMuted` true and `muted` false; `true` when `muted` true and `micMuted` false; `false` when both false; the prop is read once after `start()` resolves.
  - Commit (T-B2.1 to T-B2.3): `feat(interview): keep the candidate's microphone choice across boundaries`

- [ ] T-B2.4 `useAnswerTimer`
  - Files: `frontend/tests/unit/use-answer-timer.spec.ts` (create); `frontend/app/composables/useAnswerTimer.ts` (create, D10).
  - Test-first (`vi.useFakeTimers`): every row of the D10 table; 12 s of silence after `avatar -> none` reads 12 in `waiting`; candidate speech continues the count without reset; a 3 s pause in speech does not stop it; `avatar` resets to `listening` 0; `candidate` while `idle` starts from 0; `sessionId` change or `live() === false` -> `idle` 0 and the interval cleared; suspended: no advance; exactly one interval at most; unmount clears the interval.
  - Commit: `feat(interview): add the answer timer driven by the speaker signal`

- [ ] T-B2.5 Captions preference
  - Files: `frontend/tests/unit/use-captions-preference.spec.ts` (create); `frontend/app/composables/useCaptionsPreference.ts` (create, `useLocalStorage('beai:interview:captions', true, { onError: () => {} })`, M7).
  - Test-first: default on; off survives a re-instantiation; storage that throws on read and write -> starts on, still toggles in memory, no error thrown; value never sent to the network (no `$fetch` call).
  - Commit: `feat(interview): persist the captions preference`
  - Slice acceptance: `bun run lint`, `bun run typecheck`, full vitest green.

## Phase 4: frontend UI (slices C1a, C1b, C2a.1, C2a.2, C2b)

### Slice C1a: `feature/licc-c1a-call-header` -> `feature/licc-b2-mic-answer-timer` (needs slice 0 merged)

- [ ] T-C1a.1 `BrandCanvas` plate opt-out
  - Files: `frontend/tests/unit/brand-canvas.spec.ts` (extend `:286-301`, do not replace); `frontend/app/components/organisms/BrandCanvas.vue` (`plate?: boolean` default `true`; `header-end` wrapper `ml-auto flex min-w-0 flex-1 items-center justify-end gap-3`).
  - Test-first: `plate=false` renders the `<img>` with no plate element; default keeps the plate; same-colour logo still bare (no compensation); pre-interview `InterviewSteps` stays at the right edge; `brand-canvas-contrast.spec.ts` and the existing pre-interview screenshots unchanged.
  - Commit: `feat(canvas): let a screen render the logo without the white plate`

- [ ] T-C1a.2 `CallHeader` organism
  - Files: `frontend/tests/unit/call-header.spec.ts` (create); `frontend/app/components/organisms/CallHeader.vue` (create, D13); `frontend/i18n/locales/{it,en}.json` (`interview.call.header.*`, `exit.short`).
  - Test-first: title variants (`standard` with role, `potential` -> Potenziale/Potential, standard without role -> bare title, no `·`, no `null` / `undefined`); DOM order title, clock, Sottotitoli, Microfono, Esci slot; no Camera, "Ripeti domanda" or Pausa control; clock has the `sr-only` "Tempo trascorso" prefix, uses `<time>`, has no `aria-live` and no `role`; `aria-pressed` toggles with constant visible labels and swapping icons; mic shows unpressed + slashed icon when `micMuted`; mic is `aria-disabled` (still focusable) when `micDisabled`; events `toggle-captions` and `toggle-mic`; each target >= 44 px class; it/en key parity.
  - Commit: `feat(interview): add the live call header`

- [ ] T-C1a.3 Exit moves to the header
  - Files: `frontend/tests/unit/call-exit.spec.ts` (modify), `frontend/tests/unit/call-panel.spec.ts` (modify); `frontend/app/components/molecules/CallExitDialog.vue` (trigger shows `exit.short`, `aria-label` = `exit.label`); `frontend/app/components/organisms/CallPanel.vue` (remove the `exit` slot only; the rest of the panel is untouched until C2a).
  - Test-first: visible text "Esci", accessible name contains "Esci" and the resume hint; dialog body, focus return to the trigger, loading/disabled state during a handover unchanged; the panel has no Exit button.
  - Commit: `feat(interview): move Exit into the call header with a visible label`

- [ ] T-C1a.4 Wire header, outline and mic in the page
  - Files: `frontend/tests/unit/interview-session.spec.ts` and `interview-session-page.spec.ts` (modify); `frontend/app/components/InterviewSession.vue` (`:plate="!callStageLive"`; `<CallHeader>` in `#header-end` when `callStageLive`, `v-if="preInterviewStep"` branch untouched; call `outline.refresh()` when `callStageLive` first becomes true and on every `sessionId` change while live; `title` from outline `role_name` / `assessment_type`; `captions-enabled` from `useCaptionsPreference`; `mic-muted = session.micMuted.value || session.handoverInFlight.value`; `mic-disabled = session.handoverInFlight.value` (covers boundary too, M2); `CallExitDialog` into the `exit` slot).
  - Test-first: during a boundary AND during a handover the mic control is present, disabled and shows muted; afterwards it returns to the candidate's own choice (spec "forced mute wins" and "mute survives a boundary"); toggling captions or mic never calls `/end` (read-only); outline fetched once on live and again on `sessionId` change, not per utterance; outline failure shows the bare title and no error; embed page still mounts.
  - Interim state (documented, not released): the Sottotitoli control toggles the preference but has no visible effect until C1b.
  - Commit: `feat(interview): compose the live header, outline refresh and microphone control`

- [ ] T-C1a.5 Arch rules, first stricter step
  - Files: `frontend/tests/unit/arch/call-ui-arch.spec.ts`.
  - Test-first (RED): inventory expects 8 `Call*.vue` incl. `organisms/CallHeader.vue`; exact binding list on `<CallHeader>` (`title`, `elapsed-seconds`, `captions-enabled`, `mic-muted`, `mic-disabled`, `toggle-captions`, `toggle-mic`); exactly ONE `role="timer"` under `app/components/**` (in `InterviewTimer.vue`); the `<CallPanel>` binding list is updated to drop the `exit` slot; viewport-unit rule unchanged; literal-word rule now covers `CallHeader`.
  - Acceptance: no rule removed or loosened; `bun run lint`, `bun run typecheck`, full vitest, and `bun run test:e2e -- interview-call.spec.ts` green in Chromium and WebKit (tab order Sottotitoli, Microfono, Esci, question, help; axe at `#ffd400` and `#771aaf`).
  - Commit: `test(arch): guard the call header inventory, bindings and the single timer role`

### Slice C1b: `feature/licc-c1b-captions-overlay` -> `feature/licc-c1a-call-header`

- [ ] T-C1b.1 `--color-primary-caption` token
  - Files: `frontend/tests/unit/brand-theme.spec.ts` (extend), `frontend/tests/unit/arch/canvas-brand-fallbacks.spec.ts` (picks the token via the list); `frontend/app/composables/useBrandTheme.ts` (`BRAND_DERIVED_TOKENS` `:96` + `DERIVE['--color-primary-caption']` = `ensureContrast(mix(color,'#ffffff',0.7), AVATAR_PANEL, 4.5)`); `frontend/app/assets/css/main.css` (Quint default beside `--color-primary-light` `:37`, equal to `ensureContrast('#c222d3','#0f172a',4.5)`).
  - Test-first: >= 4.5:1 on `#0f172a` for the fixture colours and the Quint default; the hex is pinned with its ratio; `--color-primary-light` value unchanged (assert the old value).
  - Commit: `feat(theme): add the caption prefix colour token held to 4.5:1`

- [ ] T-C1b.2 Captions overlay (`CallQuestion`) and stage
  - Files: `frontend/tests/unit/call-question.spec.ts` (modify), `frontend/tests/unit/call-stage.spec.ts` (modify); `frontend/app/components/molecules/CallQuestion.vue` (props `speakerName`, `visible=true`; overlay classes of D8; `text-primary-caption` prefix; off -> `sr-only`, no `tabindex`, `focusOnBoundary()` returns early, text still written); `frontend/app/components/organisms/CallStage.vue` (remove the `#question` slot and grid area); `frontend/app/components/InterviewSession.vue` (render `CallQuestion` inside the `avatar-layer` after `CallTile`, `v-if="live"`; name = `outline.avatar_name ?? t('interview.call.interviewer_name')`; `:visible="captionsEnabled"`).
  - Test-first: prefix shows the name, text interpolated (markup `<img onerror>` inert); off keeps the live-region text and drops `tabindex`; exactly one `aria-live` question region on screen (announced once); turning captions on shows the latest text immediately; hint shown (and carried by the region) before the first utterance and at each competency start, not the previous closing phrase; off + boundary moves no focus, on + boundary focuses the caption surface; the keyed player layer is the same DOM node across `connecting -> live` (no re-parent); overlay never overlaps the name chip or self tile (class assertion on the `right-[calc(...)]` offset).
  - Commit: `feat(interview): show the question as captions over the interviewer video`

- [ ] T-C1b.3 Tile chips and candidate name
  - Files: `frontend/tests/unit/call-tile-contrast.spec.ts`, `call-tile.spec.ts`, `call-self-view.spec.ts` (modify); `frontend/app/components/molecules/CallTile.vue` (chip `bg-black/60 text-white`); `frontend/app/components/molecules/CallSelfView.client.vue` (`name?: string`, default `t('interview.call.you')`); page passes `outline.candidate_name`.
  - Test-first: chip contrast >= 4.5:1 against a white frame at the composited `#666`; name shown, blank or missing or failed outline -> "Tu"/"You"; `<b>x</b>` inert; chip not focusable and not interactive; the speaking ring is lit only when `speaker === 'candidate' && !micMuted`.
  - Commit: `feat(interview): show names on the call tiles with a legible chip`

- [ ] T-C1b.4 Arch captions rule and e2e
  - Files: `frontend/tests/unit/arch/call-ui-arch.spec.ts`; `frontend/tests/e2e/interview-call.spec.ts`.
  - Test-first: arch: `CallQuestion` is rendered inside the `avatar-layer` element and nowhere else; no `#question` slot remains. e2e (Chromium + WebKit): captions off hides the overlay and keeps the region; preference survives a reload; tab order unchanged; axe zero violations on live at `#ffd400` and `#771aaf`.
  - Acceptance: `bun run lint`, `bun run typecheck`, full vitest, `bun run test:e2e -- interview-call.spec.ts` green.
  - Commit: `test(interview): guard captions placement and cover captions off end to end`

### Slice C2a.1: `feature/licc-c2a1-storyboard` -> `feature/licc-c1b-captions-overlay`

- [ ] T-C2a1.1 `CallStoryboard` molecule
  - Files: `frontend/tests/unit/call-storyboard.spec.ts` (create); `frontend/app/components/molecules/CallStoryboard.vue` (create, D14 section 2); `frontend/i18n/locales/{it,en}.json` (`storyboard.*`).
  - Test-first: `<ol>` in outline order; `aria-current="step"` on the current item only; done = check + sr "completata"; upcoming = ordinal numeral; retry = icon + "Da ripetere" (differs from upcoming by text in forced colours); `k` clamp table: `null` -> "In corso", `0` -> "domanda 1 di 3", `5` of 3 -> "domanda 3 di 3", `n = 0` -> "In corso"; verbatim re-ask keeps "domanda 2 di 3"; markup in a name inert; no `code` / `competency_code` in the file or DOM; internal scroll with `tabindex="0"` only when overflowing.
  - Commit: `feat(interview): add the named competency storyboard`

- [ ] T-C2a1.2 Panel restructure: Percorso
  - Files: `frontend/tests/unit/call-panel.spec.ts` (modify); `frontend/app/components/organisms/CallPanel.vue` (three `<section aria-labelledby>` with `<p>` labels; Percorso = competency progress text "Competenza {n} di {total}" + `ProgressBar` + `CallStoryboard`; props `storyboard`, `primary-index`; numerator `min(max(ended ?? (ordinal-1), 0) + 1, total)` per M1; panel title key value "Intervista"; remove `progress` key, label "Domanda n di total").
  - Test-first: "Competenza 2 di 5" from `ended=1,total=5` with `aria-valuenow=1`, `aria-valuemax=5`, valuetext of position 2 of 5; first competency shows "Competenza 1 di 5" from the `/start` (read-only) total (M1); outline with 4 entries never changes the denominator 5; hidden while total is null or 0; storyboard omitted (no empty frame) when the outline is missing and the rest renders; panel has no Exit and the help link is the LAST focusable element.
  - Commit: `feat(interview): restructure the call panel around the named path`

- [ ] T-C2a1.3 Panel Durata section (M3)
  - Files: `frontend/tests/unit/call-panel.spec.ts`; `frontend/app/components/organisms/CallPanel.vue` (duration gate = `maxSeconds` only; drop the `secondsPerQuestion` fallback; `ProgressBar` elapsed/max clamped; "03:12 / 20:00" with sr "03:12 trascorsi su un massimo di 20:00"; sentence "Restano circa {N} minuti" with `N = ceil(remaining/60)` as a vue-i18n plural, hidden when `remaining <= 0`, never "0 minutes"; `InterviewTimer` labelled `remaining_label` beside it, wrapped in `v-show` so it stays mounted and enforcing while `maxSeconds` is unknown); `frontend/i18n/locales/{it,en}.json` (`duration.*`, `remaining_label`; remove `duration_label`, `question_timer_label`).
  - Test-first: `1200 s` + 3:12 elapsed -> "03:12 / 20:00", "Restano circa 17 minuti", "Tempo rimanente 16:48"; `5400` -> "90:00"; no `maxSeconds` -> no bar, maximum, sentence or visible countdown and "05:00" appears nowhere as a maximum, but the `InterviewTimer` is still mounted and `expired` still reaches the page; past max -> full bar, clamped text, no error styling; elapsed equals the header clock; boundary does not restart the countdown (keyed on session in the page, existing); exactly one `role="timer"` (arch test from C1a stays green).
  - Commit: `feat(interview): show the interview duration against the server maximum`

- [ ] T-C2a1.4 Page bindings and arch (panel, part 1)
  - Files: `frontend/app/components/InterviewSession.vue` (build `storyboard` items `{name: outline.name ?? t('interview.call.storyboard.unnamed',{ordinal}), ordinal, status, primaryTotal}`; pass `primary-index`, `ended`, `total`); `frontend/tests/unit/arch/call-ui-arch.spec.ts`.
  - Test-first (RED): inventory 9 files (adds `molecules/CallStoryboard.vue`); `CallPanel` and `CallStoryboard` contain no `/\bcode\b/` (read-only) and no `competency_code`; no `Call*.vue` imports `useInterviewSession`, `useInterviewOutline` or `useCandidateSession`; `CallPanel` imports exactly `vue`, `InterviewTimer`, `ProgressBar`, `useInterviewClock`, `CallStoryboard` (tightened again in C2a.2); `<CallPanel>` binding list is the exact current list; the old "panel names no competency" rule is REPLACED by "panel names competencies, never a code" (never simply deleted). Unit: a session store holding code `COL` renders no `COL` anywhere on the live screen.
  - Acceptance: lint, typecheck, vitest green. Commit: `test(arch): replace the no-competency rule with a no-code rule for the panel`

### Slice C2a.2: `feature/licc-c2a2-answer-timer` -> `feature/licc-c2a1-storyboard`

- [ ] T-C2a2.1 `CallAnswerTimer` molecule
  - Files: `frontend/tests/unit/call-answer-timer.spec.ts` (create); `frontend/app/components/molecules/CallAnswerTimer.vue` (create, D14 section 1); `frontend/i18n/locales/{it,en}.json` (`answer.*`).
  - Test-first: `<time>` shows `formatClock(seconds)`; no `role` and no `aria-live` anywhere in the component; chip text for `listening` / `waiting` / `answering`, no chip while `idle`; muted hint (plain text, icon `aria-hidden`) only while `micMuted` (intent); with `budget === null` neither bar nor labels render; with a budget: track `aria-hidden`, zone widths for `[0,min)`, `[min,idealFrom)`, `[idealFrom,idealTo]`, `(idealTo,max]`, text "Min 0:50 · Ideale 1:15–2:30 · Max 3:20" (spec example values), "Tempi suggeriti, non vincolanti" note; fill clamped at max with no error treatment; `prefers-reduced-motion` -> no transition on the fill.
  - Commit: `feat(interview): add the answer timer with the suggested length bar`

- [ ] T-C2a2.2 Panel section 1 and page wiring
  - Files: `frontend/tests/unit/call-panel.spec.ts`, `frontend/tests/unit/interview-session.spec.ts`; `frontend/app/components/organisms/CallPanel.vue` (section "Tempo di risposta" first; props `answer-seconds`, `answer-phase`, `mic-muted`, `budget`); `frontend/app/components/InterviewSession.vue` (`useAnswerTimer({ speaker, sessionId, live })`; `answerBudget(session.interviewMaxSeconds, outline.primary_total_all)`; `:mic-muted="session.micMuted.value"` — the INTENT, not the visual state).
  - Test-first: panel DOM order is Tempo di risposta, Percorso, Durata, help link; budget hidden until both inputs exist; timer past the max sends no `/end` (read-only) and leaves the countdown unaffected; muting 10 s leaves the timer advancing (20 s -> 30 s) and the countdown advancing; suspend stops the timer; chip follows candidate then avatar and resets on avatar.
  - Commit: `feat(interview): show the answer time section in the interview panel`

- [ ] T-C2a2.3 Arch rules (panel, part 2)
  - Files: `frontend/tests/unit/arch/call-ui-arch.spec.ts`.
  - Test-first (RED): inventory 10 files (adds `molecules/CallAnswerTimer.vue`); `CallPanel` imports exactly `vue`, `InterviewTimer`, `ProgressBar`, `useInterviewClock`, `CallAnswerTimer`, `CallStoryboard`; `<CallPanel>` bindings are exactly `ended, total, elapsed-seconds, max-seconds, question-seconds, timer-key, tick, expired, answer-seconds, answer-phase, mic-muted, budget, storyboard, primary-index`; `CallAnswerTimer` has no `role="timer"`; literal-word rule covers all 10 files.
  - Acceptance: lint, typecheck, vitest green. Commit: `test(arch): finish the call panel inventory and binding guards`

### Slice C2b: `feature/licc-c2b-stage-sizing` -> `feature/licc-c2a2-answer-timer`

- [ ] T-C2b.1 Stage grid and panel width
  - Files: `frontend/tests/unit/call-stage.spec.ts` (modify); `frontend/app/components/organisms/CallStage.vue` (single row `grid-cols-[minmax(0,1fr)_var(--spacing-call-panel)]` at `xl`, `[grid-template-areas:'layer_panel']`, panel cell `xl:h-0 xl:min-h-full`; `HOSTED_HEIGHT_CAP` chrome term `9rem` beside the panel / `22rem` as a strip, plus `xl:min-h-[calc(100dvh_-_9rem)]` inside the same array; embedded: no viewport unit); `frontend/app/assets/css/main.css` (`--spacing-call-panel: 22rem` at `:121`).
  - Test-first: class assertions for the `xl` single row, `< xl` one column `'layer' 'panel'`; embedded variant contains no `vh` / `dvh` / `svh`; viewport-unit arch rule (single use inside `HOSTED_HEIGHT_CAP`) stays green and unchanged.
  - Commit: `feat(interview): size the call stage for the wider interview panel`

- [ ] T-C2b.2 E2E fit, width, boundary mute, snapshots
  - Files: `frontend/tests/e2e/interview-call.spec.ts`, `frontend/tests/e2e/browser-gate-middleware.spec.ts` and the 1440x900 snapshot images (regenerated on purpose, excluded from the line count).
  - Test-first (RED then calibrate the `9rem` / `22rem` knob in T-C2b.1): no vertical scroll at 1280x800, 1440x900, 1920x1080 in Chromium and WebKit; panel is 352 px at 1440; layout valid at 1024 and the mobile gate unchanged; mute persists across a competency boundary with the mock provider (control still pressed afterwards); panel strip below 1280 shows the same sections; axe zero violations on live, exit dialog and suspended at `#ffd400` and `#771aaf`; pre-interview pages pixel-unchanged (plate present); embed resize heights equal twice.
  - Commit: `test(e2e): cover the live call layout, width and mute persistence`

- [ ] T-C2b.3 Final guard audit and gates (no new code unless a gap is found)
  - Files: `frontend/tests/unit/arch/call-ui-arch.spec.ts` (read-only audit; edit only to close a gap).
  - Acceptance: a rule-by-rule table in the PR description maps every D18 row to a passing assertion and shows no row of the original spec was removed or weakened (diff reviewed against `develop`); `bun run lint`, `bun run typecheck`, `node node_modules/.bin/vitest run --coverage` (>= 85% overall), `bun run test:e2e` (Chromium + WebKit, plus the mobile-gate project) all green; manual check at 1440x900 and 1024x768 against the owner screenshot; timeout, pause/resume, `next_action`, proctoring and snapshot suites pass unmodified in intent.
  - Commit (only if a gap is closed): `test(arch): close the remaining call ui guard gaps`

## Phase 5: Delivery and release (orchestrator-owned, not apply tasks)

- [ ] R.1 Tracker PRs, in order: api tracker -> `develop`; api release (A.i-A.iii); then backoffice tracker (A2) and frontend tracker (B.i-C2b) in parallel, each folding the `openapi.json` sync into its own release; wrapper tracker last (slice 0 + submodule pins). The frontend tracker PR is never merged before frontend PR #95.
- [ ] R.2 Verify on the local stack after rebuilding api, backoffice and frontend images; check `/api/health/ready` (read-only) and `migrate:status` before declaring it ready.
- [ ] R.3 Open items for the owner: (a) legal sign-off if the persona name is considered new candidate-facing personal data (it is operator text, not candidate data); (b) the evaluation-retry budget note (Open Question 1) stays non-blocking.

## Spec scenario coverage map (RED traceability)

| Spec requirement | Tasks |
|---|---|
| interview-session: outline (all scenarios) | T-A1.1, T-A2.1 |
| interview-session: `primary_index` (all scenarios) | T-A3.1 |
| avatar-templates: persona display name | T-A3.2 to T-A3.5 |
| admin-backoffice: persona input | T-A2.2b, T-A2.3 |
| interview-frontend: top bar | T-C1a.1 to T-C1a.4 |
| interview-frontend: microphone toggle | T-B2.1 to T-B2.3, T-C1a.4, T-C1b.3, T-C2b.2 |
| interview-frontend: captions toggle and overlay | T-B2.5, T-C1b.2, T-C1b.4 |
| interview-frontend: answer budget | T-B1.2, T-C2a2.1 |
| interview-frontend: storyboard | T-C2a1.1, T-C2a1.4 |
| interview-frontend: interviewer name fallback | T-C1b.2 |
| interview-frontend: stage composition, player not re-parented | T-C1b.2, T-C2b.1 |
| interview-frontend: interview panel and duration | T-C2a1.2, T-C2a1.3, T-C2b.1 |
| interview-frontend: countdown vs answer timer | T-B2.4, T-C2a1.3, T-C2a2.2 |
| interview-frontend: own camera tile and chip | T-C1b.3 |
| interview-frontend: Exit, help link, branding, accessibility | T-C1a.3, T-C1a.5, T-C1b.4, T-C2b.2 |
| interview-frontend: progress denominator | T-B1.5, T-C2a1.2 |
