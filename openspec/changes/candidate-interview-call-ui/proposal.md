# Proposal: The Candidate Interview Screen Becomes A Work Video Call

> **STATUS: Proposed 2026-10-09.** Docs-only: nothing is implemented. Grounded in `frontend` `f1769a7`
> (release 0.24.0, the commit the wrapper's `develop` pins) and in the main specs and `DESIGN.md` as they stand on
> `develop` (`4c5b72e`). The Italian strings quoted below are the proposed `it` copy; every one has an `en` pair in
> `design.md` (section "i18n keys"). Two tester findings are folded in as reserved slots (`T-BUG-1`, `T-BUG-2`); their
> root-cause analysis and fix design run separately and are appended by the orchestrator to `design.md` Appendix A.

## Intent

Testers described the live interview as unlike anything they use at work. The owner's direction (2026-10-09) is a
"video-call di lavoro" look: the candidate should feel they are in a call with an interviewer, not in a kiosk with a
video and a caption. Two AI-proposed variants were reviewed against a reference demo
(`https://extra.quint.org/demo/demo-845d5/`, fetched 2026-10-09): **A = work video call** (full-screen interviewer, own
camera bottom right, illuminated border on the speaker, side progress panel, red "Esci") and **B = interview studio**
(question always written under the avatar, explicit turn frame, "Esci, riprenderai dopo", fixed help link, hidden
participant transcript, explicit "Ho finito di rispondere" button). The owner chose a **mix**, aspect by aspect (table
below), and the demo's three timer widgets (bar, counter, ring) are mapped to the existing per-question timer.

Today's live screen (`InterviewSession.vue`, `connecting`/`live` branch) is a centred dark avatar panel, a white
"live dock" with a caption and a Pause button, and a header status pill (question label, progress bar, timer). That is
the baseline this change replaces, behind a flag.

Two tester findings ride along because they hit the same moment of the screen, the boundary between two competencies:

- **(a)** "at the end of the first question the audio/video stopped unexpectedly and the move to the second question was
  jerky" (slot `T-BUG-1`);
- **(b)** "at the start of the second question the avatar greeted me again" (slot `T-BUG-2`).

## Decisions (binding, from the owner)

| # | Aspect | Decision | Source variant | Where it is specified |
|---|---|---|---|---|
| 1 | Question | **Always written below the avatar** | B | Spec "The Written Question Is Always Shown Under The Avatar" |
| 2 | Whose turn | **Glowing border on the speaker's tile** | A | Spec "Whose Turn It Is Shows As A Glowing Border On The Speaker's Tile" |
| 3 | End of the answer | **Silence only**: the avatar understands the candidate has finished. **No "I have finished" button** | A | Spec "An Answer Ends By Silence Only" |
| 4 | Participant transcript | **Not shown**, to avoid distraction | B | Spec "The Candidate's Own Words Are Never Displayed" |
| 5 | Path / progress | **Not chosen explicitly; synthesis by the orchestrator**: a right-hand side panel, always visible, showing ONLY progress ("Domanda 2 di 5", never a competency name), elapsed time and total duration | A+B | Spec "The Side Panel Shows Progress And Time, Never A Competency Name" |
| 6 | Own camera | **Tile at the bottom right**, like a call | A | Spec "The Candidate's Own Camera Is A Bottom-Right Tile" |
| 7 | Exit | Button **«Esci, riprenderai dopo»**, stating the interview can be resumed; uses the **existing suspend/resume mechanism** | B | Spec "Exit Suspends The Interview And Says It Can Be Resumed" |
| 8 | Help | Fixed link **«Problemi con audio o video?»** to the support page | B | Spec "A Fixed Help Link Leads To Support" |
| 9 | Timer widget | **Counter** (derived here, see below), keeping the 300 s limit and its colour threshold | derived | Spec "The Per-Question Timer Is A Counter" |

**Why the counter (decision 9).** The demo's bar and ring both draw the *shape* of the time budget and the bar draws
three bands (minimum, ideal, maximum). In a work call nobody watches a progress shape while talking; a clock is the only
time device people recognise. More importantly, BEAI defines no "ideal answer length": a banded widget would invent one
and nudge candidates toward an answer length the scoring does not reward, which is a fairness and assessment-integrity
question the product has not ruled on. The counter is also the least distracting of the three, which is the stated reason
for hiding the transcript (decision 4). Its single threshold stays exactly what ships today: the label turns
`--color-recording` in the last 10 seconds (measured 4.83:1 on white). The demo's minimum/ideal/maximum bands are **not**
adopted; they are listed under "Open questions".

## Scope

### In scope

| # | Deliverable |
|---|---|
| 1 | A **call stage** for the live interview: avatar tile (the existing mounted player layer, never re-parented), a written-question band under it, the candidate's own camera tile bottom right, and a right-hand side panel (progress, elapsed and total time, per-question counter, Exit, help link). |
| 2 | A provider-neutral **speaker signal** (`avatar`, `candidate` or `none`) driving a glowing ring on the matching tile. |
| 3 | **Exit** that suspends through the existing `session.pause()` / `/candidate/interview/suspend` and resumes through the existing `/start` re-issue, with an honest confirmation and a "suspended" screen. |
| 4 | **Help link** whose target is configurable (`runtimeConfig.public.supportUrl`), defaulting to the support address the app already ships. |
| 5 | **Feature flag** `candidateCallUi` (default off) so the old screen stays until the owner flips it; later removal of the old screen. |
| 6 | **Only-avatar captions**: the candidate's own transcript stops reaching the displayed text. |
| 7 | **Layout** for 1024-1919+ px desktop widths, including the embed (`/embed/{token}`) which shares `InterviewSession.vue`. |
| 8 | Accessibility, i18n (`it` and `en`, every string), white-label, proctoring continuity, tests (Vitest, Playwright chromium+webkit, visual regression). |
| 9 | Reserved slots `T-BUG-1` (smooth handover) and `T-BUG-2` (no second greeting) with behavioural acceptance criteria. |
| 10 | `DESIGN.md` amendments, landing **before** any code (DESIGN.md forbids implementing a decision it does not describe). |

### Out of scope / non-goals

- **API and backoffice changes.** Nothing in `api/` changes. Where the screen would benefit from a server field
  (interviewer display name, planned or elapsed duration), the proposal records a client-side derivation and an open
  question instead of a backend change.
- **Per-tenant layout or copy.** Branding stays logo plus primary colour (CLAUDE.md ruling 9). The FR-006 portal stays parked.
- **A "finished answering" control, a typed answer, chat, mute/unmute or camera on/off buttons.** Call chrome that does
  not map to an existing capability is not added.
- **Showing the candidate's own words** (decision 4) or the competency name (decision 5).
- **The demo's minimum/ideal/maximum answer bands** and the bar/ring timer variants.
- **Changing proctoring, snapshot cadence, the 300 s limit, the end-phrase completion mechanism or the `/end`
  directives.** They must keep working; the UI only changes how they are presented.
- **Changing Tavus or HeyGen handover internals.** `tavus-single-session-interview` owns the Tavus single-conversation
  work and the main spec owns the HeyGen crossfade. This change adds acceptance criteria for what the candidate
  perceives (T-BUG-1/2) and consumes whichever fix the root-cause appendix selects.
- **Mobile or tablet.** The SA-11 gate (below 1024 px) is unchanged.

## Capabilities

### New Capabilities

None. Everything belongs to `interview-frontend`, which already owns the live screen, the timer, the flow screens and the
embed behaviour.

### Modified Capabilities

- **`interview-frontend`**: MODIFIED `Flow screens — localized states` (the live and pause rows; the pause row also
  corrects text that no longer matches shipped behaviour, see design "Verified facts" V3),
  `Progress indicator reflects the server-reported competency total`, and
  `Live per-question timer suspends and resumes across a mute-pause`. ADDED requirements for the call stage, the written
  question, the speaker ring, silence-only completion, the hidden candidate transcript, the side panel, the self-view
  tile, exit, help, the counter timer, the flag, accessibility, white-label and proctoring continuity, embed and responsive
  behaviour, and the two tester findings. The exact delta is in `specs/interview-frontend/spec.md`.

## Approach (summary; the reasoning is in `design.md`)

1. **Amend `DESIGN.md` first** (a wide canvas option, one spacing token, one shadow composite, the new §7.3 layout).
2. **Add the flag and a wider canvas option**, no visible change.
3. **Build the pieces in isolation, each with its own tests**: speaker signal, tile ring, written-question band, self
   view, side panel with the elapsed clock, exit dialog and suspended screen, help link.
4. **Assemble them in `InterviewSession.vue` under the flag**, keeping the single keyed `AvatarPlayer` mount layer in
   place (its exactly-once teardown guarantee is the reason the layout is a CSS grid around it and not a re-parenting).
5. **Prove it**: a second server instance with the flag on, a dedicated Playwright spec (chromium and webkit, axe, keyboard,
   no-scroll viewports, screenshots for light and dark brands), the existing specs untouched while the flag is off.
6. **Flip, migrate the old specs, delete the old screen** in three later slices, after the owner approves.

## Rollout

**Ship dark behind `runtimeConfig.public.candidateCallUi` (env `NUXT_PUBLIC_CANDIDATE_CALL_UI`, default off).** Decided,
not deferred, for four reasons:

1. **The screen cannot be fully proven offline.** Speaker cues from a real avatar, real camera framing at the bottom-right
   tile, and screen-reader behaviour need a real session. The owner needs to see it with testers before it reaches candidates.
2. **The 1542-line `interview-flow.spec.ts` and several other specs (listed in `design.md` "Existing tests affected") target today's DOM** (`/^pause$/` button, header
   `timer`, live dock). Leaving them on the old path until the flip keeps CI green slice by slice instead of one big-bang
   migration.
3. **Rollback is a variable change and a restart, not a code revert.** (Railway applying a variable change with a redeploy is the expected behaviour; it was not verified for this change.)
4. **Precedent**: the in-flight `tavus-single-session-interview` ships dark the same way.

The cost is two screens coexisting for a bounded time. It is bounded by tasks `UI-12` (flip and migrate specs) and `UI-13`
(delete the old screen), which are scheduled as soon as the owner approves the flip, and by the rule that no new feature
may land on the old screen in the meantime. The flag is per deployment (it covers the hosted route and the embed), not per
tenant or per project. A canary list is not proposed; see open question 7.

**Rollback.** Before the flip: nothing to roll back, the flag is off. After the flip and before `UI-13`: set the variable
to false and restart; the old screen is still in the bundle. After `UI-13`: a normal Git Flow revert of the removal slice,
which is why the removal is a separate, deletion-only slice.

## Risks

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | **The avatar player is re-parented**, which unmounts it and breaks the exactly-once teardown guarantee and the HeyGen crossfade. | Medium / severe | The layout is a grid around the existing single mount layer; only classes toggle on it. A unit test asserts one mount and one stop across `connecting`, `live`, `paused` and a handover. |
| R2 | **"Riprenderai dopo" promises more than the system gives.** The candidate JWT lives 120 minutes (`CandidateTokenFactory`), resuming needs the same browser (`localStorage`), and a spent link cannot rescue an expired session (`Honest failure states...`). | High / high | The exit dialog and the suspended screen state the deadline derived from the stored token `exp` and "from this browser". Open question 1 asks the owner whether a longer window is wanted (an `api` change, out of scope here). |
| R3 | **Exit via the exit redirect would destroy the session.** `useExitRedirect.redirect()` clears the stored candidate session, so wiring Exit to it would make "resume" impossible. | Medium / high | Exit never calls `redirect()`; it uses `session.pause()`. A test asserts the stored session survives an exit. |
| R4 | **Speaker detection differs per provider.** HeyGen emits `speaking`/`listening`; Tavus emits neither (`tavus.ts` emits only `connecting`, `ready`, `complete`, `stopped`). | High / medium | One signal built from provider state OR audio level on the avatar's remote audio, and a mic-level gate for the candidate. Audio-level detection is provider-neutral and unit-testable with a fake analyser. Real-provider behaviour is flagged as unverified until a manual pass. |
| R5 | **The written question lags the voice.** Both providers deliver the avatar's text as a finished utterance, not word by word. | Medium / medium | The hint ("Ascolta la domanda...") fills the band until text arrives. Stated honestly in the spec; no promise that text precedes speech. |
| R6 | **Embed height feedback loop.** The embed page posts `document.documentElement.scrollHeight` as the iframe height; a layout sized with `100dvh` inside an auto-sized iframe grows without bound. | Medium / high | The embedded stage is width-driven only (no viewport-height units); a source test and an embed E2E assert a stable posted height. |
| R7 | **Glow is invisible on some brands, or the only cue.** Brand colours are arbitrary; box-shadows vanish in forced-colours mode. | Medium / medium | The ring is a white band between two `--color-avatar-bg` bands (measured 17.8:1 against the dark side, independent of the brand), plus an icon and screen-reader text, plus a `forced-colors` outline. |
| R8 | **Two screens double the test surface** until the flag is removed. | Certain / low | Specs are split by flag; the old screen is frozen; removal slices are scheduled. |
| R9 | **Dense page at 1280 x 800** (the DESIGN minimum): header, avatar, question band and a panel must fit without scrolling. | Medium / medium | Width-bound avatar sizing with a height cap in hosted mode; viewport matrix test (1280x800, 1440x900, 1920x1080). Below 1280 px the panel becomes a strip under the stage. |
| R10 | **Overlap with in-flight work** on the same files: `tavus-single-session-interview` changes `useInterviewSession.ts` and the same `interview-frontend` requirements. | High / medium | This change adds a presentation layer and touches `useInterviewSession` only through the existing `pause()`; its spec delta MODIFIES different requirements. Slice order below says who rebases onto whom. |
| R11 | **Screen-reader double announcement** if focus moves to a live region. | Medium / low | Focus moves to the question element only at a competency boundary, never per utterance; a manual NVDA and VoiceOver pass is a listed, unverified step. |

## Open questions (for the owner)

Each has a safe default that the slices implement unless told otherwise.

1. **How long should "Esci, riprenderai dopo" really last?** Today the candidate session is 120 minutes
   (`CandidateTokenFactory::mintCandidateToken`, `setTTL(120)`) and resumes only in the same browser. A longer window needs
   an `api` change and a retention/GDPR view. *Default:* keep 120 minutes and show the real deadline in the dialog.
2. **What is the real support page URL for «Problemi con audio o video?»** No support page or URL exists in `frontend`;
   the only support affordance is `mailto:support@beai.app`, hardcoded in four places (`InterviewSession.vue` x3,
   `pages/interview/terminal.vue`). *Default:* `runtimeConfig.public.supportUrl` (`NUXT_PUBLIC_SUPPORT_URL`), accepting only
   `https:` or `mailto:`, defaulting to `mailto:support@beai.app`. The four hardcoded sites move to the same setting.
3. **Interviewer display name.** The demo shows "Giulia · Intervistatrice AI". No avatar-template field carries a name
   that is safe to show (and the provider must stay anonymous). *Default:* the generic label "Intervistatore AI" /
   "AI interviewer".
4. **Should the screen show a recording indicator?** `DESIGN.md` §7.3.1 lists a pulsing red dot "always visible", but the
   shipped live screen renders none (verified: the only `recording` uses are the timer colour and a consent comment).
   *Default:* none added; this is a consent and legal question, not a styling one.
5. **Elapsed and total duration source.** There is no planned or elapsed duration in the candidate API. *Default:*
   elapsed = live seconds counted in this page session; total = `total_competencies x 300 s`, labelled as a maximum. After
   a full reload the elapsed counter restarts. A server-supplied elapsed value would need an `api` field.
6. **Demo thresholds (minimum 1:00, ideal 1:30-3:00, maximum 4:00).** *Default:* not adopted (see decision 9). Adopting them
   needs a product ruling on whether BEAI should coach answer length.
7. **Do testers need a per-session opt-in** (for example a query parameter) while the flag is off in production?
   *Default:* no; use a staging deployment with the flag on.
8. **A QA question label** ("D1", "Q1.2" today) is dropped from the call screen. *Default:* dropped. If testers still
   need it for bug reports, it can return as a small mono label shown only when `appEnv` is not `production`.

## Assumptions and what was not verified

- Verified by reading source at the pinned commits: component structure, provider state emission, the pause/suspend/resume
  path, the stored-session behaviour, the embed resize reporting, the current tests and fixtures, `DESIGN.md`, the main spec.
- **Not verified:** how each real provider behaves in a live session (speaker cue timing, whether Tavus would emit
  speaking events on its data channel, camera framing), screen-reader behaviour, and the root causes of the two tester
  findings. Anything in this change that depends on those is marked as such and covered by a manual pass or by the appendix.
- The reference demo describes variants A and B in prose; this proposal follows the owner's per-aspect decisions, not
  the demo's markup.

## Dependencies and coordination

- `tavus-single-session-interview` (in flight): also edits `useInterviewSession.ts`, `AvatarPlayer`, and the
  `interview-frontend` requirements `Interview session loop — endpoint call order` and
  `Provider abstraction — provider-neutral behavior`. This change does not modify those requirements. Whoever merges second
  rebases; `UI-02` and `UI-09` are the slices that touch shared files.
- `db-driven-conversation-prompts`: unrelated to the frontend, but it is the likely home of anything the root-cause
  appendix finds in prompt composition (the second greeting).
- The root-cause appendix for `T-BUG-1` and `T-BUG-2` gates only those two slots, never the rest of the change.

## Success criteria

1. With the flag on, the live screen is the call stage described above in Chromium and WebKit at 1280x800, 1440x900 and
   1920x1080, with no page scroll, for a light and a dark brand colour and for no brand colour.
2. Axe reports zero WCAG 2.1 AA violations on the live call screen, the exit dialog and the suspended screen; the exit
   control and the help link are keyboard operable; the self-view never takes focus.
3. Exit suspends through `/suspend`, leaves the stored session intact, and a reopened invitation link resumes the same
   competency.
4. The candidate's own transcript never appears on screen, and no competency name appears anywhere in the panel.
5. With the flag off, every existing test passes unchanged.
6. `T-BUG-1` and `T-BUG-2` acceptance criteria are met in an end-to-end run across a competency boundary.
