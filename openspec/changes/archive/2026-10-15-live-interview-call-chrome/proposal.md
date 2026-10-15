# Proposal: Live Interview Call Chrome (Header, Interview Panel, Captions)

> **STATUS: Proposed 2026-10-14.** Docs-only: nothing is implemented. Grounded in the exploration
> `sdd/live-interview-call-chrome/explore` (Engram) and the owner-approved plan of 2026-10-14. Scope is the candidate
> `live` state only. Italian strings quoted below are the proposed `it` copy; each gets an `en` pair in `design.md`.

## Intent

The live interview screen shipped by `candidate-interview-call-ui` (archived 2026-10-11) is a video, a question band and
a thin side panel (count, clock, Exit). The owner supplied a target screenshot and asked for a richer call chrome so the
candidate can see where they are, how long they have, and who is talking:

- a **top bar**: organization logo **without** the white plate, the title "Colloquio di assessment · {role name}",
  the elapsed clock, and the controls **Sottotitoli**, **Microfono**, **Esci**;
- a right **"Intervista" panel**: answer timer with a status chip and a min/ideal/max bar, a **competency storyboard**
  ("Percorso"), and an interview-duration bar;
- **captions** as an overlay at the bottom of the video, prefixed by the interviewer's name in the brand colour, which
  the candidate can turn off;
- the candidate's **name** on their own camera tile.

Success = a candidate in a live interview sees the screenshot's layout in the organization's own colours (not the
screenshot's dark theme), in `it` and `en`, with no accessibility regression and no change to how the interview is
conducted, timed out, proctored or scored.

## Decisions already taken by the owner (binding)

| # | Aspect | Decision |
|---|---|---|
| D1 | Scope | **Live state only.** Consent, device check and notice pages keep today's header, white logo plate included. |
| D2 | Theme | **Keep the brand-primary canvas and white surfaces.** Adopt the screenshot's layout, not its dark theme. Brand accents use `--color-primary`, `--color-primary-ink` (on white), `--color-primary-light` (on the dark video). |
| D3 | Answer budget | Per-answer budget = `interview_max_seconds / total primary questions`. Max = the budget; min and ideal band are fixed fractions of it (values open, see O1). |
| D4 | Interviewer name | A **dedicated persona field**, `AvatarTemplate.persona.display_name`, settable in the backoffice. Fallback label "Intervistatore AI" when unset. |
| D5 | Controls | **Sottotitoli toggle, Microfono toggle, Esci** only. **Camera** and **Ripeti domanda** are NOT rendered: no re-ask mechanism exists, and a camera toggle conflicts with proctoring snapshots (`useProctor.ts:539`). |
| D6 | Known trade-off | A brand-coloured logo on a transparent background can vanish on the same-colour canvas (`BrandCanvas.vue:27-40`). Accepted; flagged in the PR, not engineered around. |

Two of these **reverse statements of the archived change**, and the spec deltas must say so by name:

- The side panel was specified as **"never a competency name"**. That ban was an orchestrator synthesis, not an owner
  decision (`2026-10-11-candidate-interview-call-ui/proposal.md`, decision 5). The storyboard names competencies.
- Min/ideal/max answer bands were **refused** there as an unruled fairness question ("BEAI defines no ideal answer
  length"). D3 is the owner's ruling on that question. See risk R1.

## Scope

### In Scope

| # | Deliverable | Repo | Slice |
|---|---|---|---|
| 1 | `DESIGN.md` §7.0.1 and §7.3 amended **first** (they currently prescribe an empty live header, no status pill, no min/ideal/max band). | wrapper | 0 |
| 2 | New read-only candidate endpoint `GET /api/candidate/interview/outline` (action `BuildInterviewOutline`): `assessment_type`, `role_name` (nullable), `avatar_name` (nullable), `candidate_name` (nullable), `competencies[] {name, ordinal, status: done\|current\|upcoming\|retry, primary_total}` (no code), `primary_total_all`. Names localized to the **project** language. Registered in the nested `interview` route group (candidate JWT, tenant scope, `ParticipantStatusGuard`). | api | A |
| 3 | `POST /candidate/interview/utterance` 202 body gains `primary_index` (count of persisted primary-marked avatar turns, already queried). Additive. | api | A |
| 4 | `persona.display_name` validated in `ValidatesAvatarTemplateWrites`, preserved by `DuplicateAvatarTemplate`. | api | A |
| 5 | Contract: hand-written `@scramble-return`, `scramble:export` against PostgreSQL, `openapi.json` committed in `api/`, `frontend/`, `backoffice/`. | api + consumers | A |
| 6 | Backoffice avatar-template form: a persona display-name input, `it`/`en`. | backoffice | A2 |
| 7 | Frontend data: keep `display_name` from `/candidate/session`; `useInterviewOutline` (single-flight); store `primary_index`; pure `answerBudget()` util; answer timer and "waiting for your answer" status from speaker transitions; mic toggle exposed by `useInterviewSession` (boundary logic keeps ownership of forced mutes); `captionsEnabled` (default on, persisted). | frontend | B |
| 8 | Frontend UI (live only): `BrandCanvas` plate opt-out; live top bar; `CallPanel` reworked into the "Intervista" panel; `CallCaptions` overlay; self-view name chip (`bg-black/60`, white text); `IntegrityToaster` offsets re-checked; `interview.call.*` keys in `it.json`/`en.json`. | frontend | C |
| 9 | Tests consciously rewritten (never weakened): `call-ui-arch.spec.ts`, `call-panel`, `call-stage`, `call-tile*`, `call-self-view`, `brand-canvas`, `interview-session` unit specs; e2e `interview-call.spec.ts` (tab order, axe per brand colour, no vertical scroll) and `browser-gate-middleware.spec.ts`. | frontend | B, C |

### Out of Scope

- **Camera toggle and "Ripeti domanda"** (D5). No re-ask mechanism is built.
- **The screenshot's dark theme** (D2).
- **Pre-interview pages** (consent, device check, notices): unchanged, white logo plate stays (D1).
- **Interview mechanics**: the per-question timeout and its `POST /end` `timeout` path, the remaining-time preservation
  across pauses, the server-directed `next_action` flow, the silence-only end of an answer, proctoring and snapshots,
  scoring. Presentation changes only.
- **Displaying the candidate's own words** (still forbidden).
- **Streaming captions**: captions show the latest finished avatar utterance, as the question band does today.
- **Persisting elapsed time across a reload** (documented limitation, unchanged).
- **The backoffice and the `/v1` public API**: no new public field; T-EXPOSE-001 does not cover `/api/candidate/*`
  (verified in exploration).

## Capabilities

### New Capabilities

None. The outline endpoint is a candidate interview read that belongs to `interview-session`.

### Modified Capabilities

- `interview-session`: ADDED requirement for `GET /api/candidate/interview/outline` (shape, project-language names,
  `retry` status, nullable `role_name` for `potential`, nullable `avatar_name`, ownership via the candidate JWT and
  tenant scope); MODIFIED `POST /utterance` response to carry `primary_index`.
- `interview-frontend`: MODIFIED "The Live Interview Screen Is A Work Video Call Stage" (adds the top bar and the
  captions overlay), "The Written Question Is Always Shown Under The Avatar" (relationship with the captions overlay and
  the toggle, see O4), "An Answer Ends By Silence Only" (interactive elements now include the captions and microphone
  toggles), "The Side Panel Shows Progress And Time, Never A Competency Name" (becomes the "Intervista" panel with a
  named storyboard), "The Per-Question Timer Is A Counter" (answer timer with min/ideal/max bar; the timeout limit and
  its threshold are unchanged), "The Candidate's Own Camera Is A Bottom-Right Tile" (name chip), "Exit Suspends The
  Interview..." (Exit moves to the top bar, behaviour unchanged), "A Fixed Help Link Leads To Support" (placement),
  "The Call Screen Keeps Branding..." (bare logo while live), "The Call Screen Is Accessible" (new focus order),
  "Progress indicator reflects the server-reported competency total" (naming ban lifted, denominator rule kept).
  ADDED: microphone mute toggle; captions toggle with persisted preference.
- `avatar-templates`: ADDED `persona.display_name` (optional, validated plain text, duplicated, carried by export and
  import), candidate-facing and therefore subject to the provider-opacity rule.
- `admin-backoffice`: ADDED the persona display-name input on the avatar template form.

## Approach

**One read endpoint feeds a presentation-only rework; nothing about how the interview runs changes.**

1. **Design doc first.** `DESIGN.md` §7.0.1/§7.3 is amended before any UI code, because it forbids implementing a
   decision it does not describe.
2. **API (slice A).** `BuildInterviewOutline` resolves the role via `CatalogueRevisionResolver::tryForProject` and
   competencies via the `project_competencies.position` join already used by
   `InterviewController::resolveNextCompetency` / `freshRemainingCompetencies` (`:1003-1068`). That join is
   **extracted into a shared helper**, not duplicated. Names use `getTranslation('name', $project->language)`.
   `ParticipantResource` is **not** extended (it also feeds `ParticipantEnrolmentResource`). Response fields stay
   snake_case like every other candidate endpoint. `primary_index` reuses the turn count the utterance controller
   already computes (`UtteranceController.php:246-266`).
3. **Backoffice (slice A2).** One input; the form already round-trips `persona`.
4. **Frontend data (slice B).** Composables and a pure util, each unit-tested before the UI consumes them.
   `answerBudget()` returns `null` when inputs are missing, and the bar is then hidden rather than guessed.
5. **Frontend UI (slice C).** New organisms (`CallHeader`, `CallCaptions`) and a reworked `CallPanel`, reusing
   `InterviewTimer`, `ProgressBar`, `CallExitDialog`, `useInterviewClock`/`formatClock` and `currentCaption`
   (`InterviewSession.vue:849-897`). The single keyed player layer is never re-parented. The `aria-live` question
   region survives whatever the visual caption state is (screen-reader users must not lose the question when captions
   are hidden visually).

Strict TDD (`openspec/config.yaml`): RED before GREEN in every slice. Representative REDs: an outline request for
another tenant's participant is refused; a `potential` project returns `role_name: null`; a `pending`-retry competency
reports `retry`; `answerBudget(1200, 0)` returns `null`; captions-off hides the overlay but keeps the live region; the
arch test fails on a new `Call*.vue` literal string.

## Size and Delivery

- `Chained PRs recommended: Yes`
- `400-line budget risk: High`
- `Decision needed before apply: Yes` (O1 to O4 below)

Rough forecast (authored lines, generated `openapi.json`/`types/api.ts` excluded): wrapper `DESIGN.md` ~120; api
~300; backoffice ~80; frontend data ~350; frontend UI ~800 plus test rewrites. Slice C will likely split in two
(top bar + bare logo + captions + self-view chip; then the "Intervista" panel). Order: 0 → A → (A2 ∥ B) → C. Every
api slice is released before the frontend or backoffice slice that consumes it (api-first release recipe). Delivery
strategy for the session: `auto-chain`.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `DESIGN.md` §7.0.1, §7.3 | Modified | Live header, status chip, answer bands, storyboard, captions overlay |
| `api/routes/api.php:913-918` | Modified | New candidate route in the nested `interview` route group (candidate JWT, tenant scope and `ParticipantStatusGuard`) |
| `api/app/Actions/Interview/BuildInterviewOutline.php` | New | Outline builder |
| `api/app/Http/Controllers/.../InterviewController.php:1003-1068` | Modified | Competency-order join extracted to a shared helper |
| `api/app/Http/Controllers/.../UtteranceController.php:95,219,246-266` | Modified | `primary_index` in the 202 body and its `#[Response]` |
| `api/.../ValidatesAvatarTemplateWrites`, `DuplicateAvatarTemplate` | Modified | `persona.display_name` |
| `api/openapi.json`, `frontend/openapi.json`, `backoffice/openapi.json` | Regenerated | Scramble export against PostgreSQL |
| `backoffice/` avatar template form + `i18n/locales/{it,en}.json` | Modified | Persona display-name input |
| `frontend/app/composables/useExitRedirect.ts:94-101` | Modified | Keep `display_name` |
| `frontend/app/composables/useInterviewSession.ts:887-893,1348-1350` | Modified | `primary_index`, mic toggle |
| `frontend/app/composables/useInterviewOutline.ts`, `answerBudget` util | New | Outline fetch, budget arithmetic |
| `frontend/app/components/.../BrandCanvas.vue:41-51` | Modified | Plate opt-out prop |
| `frontend/app/components/.../CallPanel.vue`, `CallTile`, `CallSelfView` | Modified | "Intervista" panel, name chip |
| `frontend/app/components/.../CallHeader.vue`, `CallCaptions.vue` | New | Top bar, captions overlay |
| `frontend/app/components/.../InterviewSession.vue`, `IntegrityToaster.vue` | Modified | Composition, toast offsets |
| `frontend/i18n/locales/{it,en}.json` | Modified | `interview.call.*` keys |
| `frontend/tests/unit/**`, `frontend/tests/e2e/interview-call.spec.ts`, `browser-gate-middleware.spec.ts` | Modified | Rewritten to the new contract |
| `ParticipantResource`, `/v1` public API | **Unchanged** | No new public field |
| `api/tests/Helpers/PublicApi/ExposureCatalogue.php` | Modified | One admin-only entry, `avatar_template.persona.display_name` (`AvatarTemplateResource` is classified); `/v1` exposure stays none |

## Risks

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| R1 | The min/ideal/max bar nudges candidates toward an answer length BARS scoring does not reward (the fairness concern the archived change raised). | Med | D3 is the owner's ruling; the spec states the bands are guidance only and never end an answer. Fractions stay a single config point (O1). |
| R2 | The budget `interview_max_seconds / total primaries` ignores follow-ups, so a candidate can look "over max" while well within the real timeout. | Med | The bar never drives `POST /end`; the existing timeout stays the only enforcement. Copy says "suggested", design picks wording. |
| R3 | Showing competency names may change how candidates answer (they learn what is being assessed). | Low-Med | The ban was not an owner decision; the reversal is recorded in the delta so it is visible at archive. |
| R4 | Mic mute during an answer reads as silence and could end the answer early, or collide with the forced mutes owned by the boundary/handover logic (`assertBoundary`). | Med | Boundary logic remains the owner of forced mutes; design defines precedence and the timer behaviour while muted; unit tests on the mute state machine. |
| R5 | Captions toggle conflicts with the owner's earlier decision "the question is always written below the avatar" and with WCAG 1.2.4. | Med | The `aria-live` region always persists; the visual behaviour when captions are off is O4. |
| R6 | Brand logo vanishes on the same-colour canvas (D6). | Med | Accepted trade-off, called out in the PR; pre-interview pages keep the plate. |
| R7 | `persona.display_name` is operator free text shown to candidates: could name the vendor or carry markup. | Low | Validated length/plain text; rendered by interpolation only; opacity rule extended to it in the spec. |
| R8 | In-flight frontend branch `feature/seamless-primary-transition` (unpushed, touches `InterviewSession.vue` and `useInterviewSession.ts`) collides with slices B and C. | Med | Land or rebase it before slice B starts. |
| R9 | Layout no longer fits 1024 px or 1280x800 without vertical scroll once the top bar is added. | Med | Existing e2e no-scroll and 1024 px gates stay and must pass; manual check at 1440x900 and 1024x768. |
| R10 | Outline leaks another tenant's or another participant's data. | Low | Candidate JWT, tenant scope and `ParticipantStatusGuard` in the nested `interview` group; dedicated Pest cross-tenant test. |

## Rollback Plan

Each slice is an independent PR and reverts on its own:

- **C** (UI): revert the frontend PR(s); the previous call stage returns, data composables stay inert.
- **B** (data): revert; nothing renders it without C.
- **A2** (backoffice): revert; persona values already saved stay in the JSON and are simply not editable.
- **A** (api): the endpoint and `primary_index` are additive; revert after the consumers, or leave them unused. No
  migration (persona is existing JSON), so no data rollback.
- **0** (`DESIGN.md`): revert together with C so the doc and the UI never disagree.

Released versions roll back through Git Flow (`hotfix/*` reverting the slice), never by force-pushing `main`.

## Dependencies

- The api release containing slice A ships before the frontend and backoffice releases that consume it.
- `feature/seamless-primary-transition` (frontend) merged or rebased first (R8).
- A real avatar template and the local stack for the manual comparison against the screenshot (rebuild images, check
  `/api/health/ready` first).

## Open Points: RESOLVED by the owner (2026-10-14)

- **O1:** screenshot ratios. `min = 0.25 × max`, ideal band `0.375 × max` to `0.75 × max`, where `max = interview_max_seconds / primary_total_all`.
- **O2:** a `potential` assessment shows the title plus the assessment type: "Colloquio di assessment · Potenziale" (en: "Assessment interview · Potential"). A `standard` one shows "Colloquio di assessment · <role name>".
- **O3:** the backoffice persona field (A2) ships in the SAME release as the api (A).
- **O4:** captions off hides ALL visible question text (overlay and band); the screen-reader live region stays mounted, so accessibility does not regress. The archived "question always written below the avatar" requirement is modified accordingly.

Original questions, kept for the record:

| # | Question | Blocks |
|---|---|---|
| O1 | Min and ideal fractions of the answer budget. Inferred from the screenshot: min 0.25, ideal 0.375 to 0.75. | Slice B `answerBudget()` constants, spec scenario values |
| O2 | Title for a `potential` assessment (no role): "Colloquio di assessment" alone? | Slice C header copy, spec scenario |
| O3 | Does the backoffice persona field (A2) ship in the same release as the api (A)? | Release plan only |
| O4 | With captions off: is the written question hidden visually (screen-reader region kept), or does the question band remain? The archived owner decision 1 says the question is always written below the avatar. | Spec delta for "The Written Question Is Always Shown Under The Avatar", slice C |

## Success Criteria

- [ ] `DESIGN.md` describes the new live chrome before any UI slice merges.
- [ ] `GET /api/candidate/interview/outline` returns project-language names in `position` order, `retry` status, `role_name: null` for `potential`, and is refused across tenants (Pest).
- [ ] `/utterance` 202 carries `primary_index`; `openapi.json` is regenerated and identical in all three repos.
- [ ] The live screen shows the top bar (bare logo, title, clock, Sottotitoli, Microfono, Esci), the "Intervista" panel (answer timer and chip, bar when a budget exists, storyboard, duration bar), the captions overlay with the interviewer name, and the candidate name chip, in `it` and `en`.
- [ ] Pre-interview pages are pixel-unchanged (white logo plate present).
- [ ] Timeout, pause/resume, `next_action`, proctoring and snapshots behave exactly as before (existing tests green, unmodified in intent).
- [ ] axe reports zero violations on the live screen, the exit dialog and the suspended screen under `#ffd400` and `#771aaf`, in Chromium and WebKit.
- [ ] No vertical scroll at 1280x800, 1440x900, 1920x1080; layout valid at 1024 px; mobile gate unchanged.
- [ ] Coverage stays at or above 85% in all three repos.
