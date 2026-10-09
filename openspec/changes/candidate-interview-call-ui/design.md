# Design: The Candidate Interview Screen Becomes A Work Video Call

Inputs: `proposal.md` (decisions 1-9, risks R1-R11, open questions 1-8). Everything here is grounded in `frontend`
`f1769a7` (release 0.24.0, pinned by the wrapper's `develop`), `DESIGN.md` and the main specs on `develop` `4c5b72e`.
File and line references are to that frontend commit. Where a claim depends on live provider behaviour it is marked
**UNVERIFIED** and has a manual step in "Test strategy".

## 1. Verified facts that shape the design

| # | Fact | Evidence | Consequence |
|---|---|---|---|
| V1 | The live screen is the `v-else-if="avatarMounted"` branch of `InterviewSession.vue`: the white "live dock" (caption plus a Pause button) under the avatar, a header status pill (question label, compact progress bar, timer), and an invisible `ProctorOverlay`. | `InterviewSession.vue` 24-56, 261-328 | These are the elements the call stage replaces under the flag. |
| V2 | Every `AvatarPlayer` renders from ONE keyed `v-for` in a "player mount layer" that sits outside the screen chain and is never re-parented; it collapses to `sr-only` when no `live` player exists. Re-parenting would unmount a player and `stop()` the session that just won a handover. | `InterviewSession.vue` 65-109; `AvatarPlayer.client.vue` `onUnmounted` | The new layout must be a grid around that layer, toggling classes only (D3, R1). |
| V3 | `pause()` is not a mute: it sets `paused`, stops the provider, calls `POST /candidate/interview/suspend` (fire-and-forget, after draining in-flight utterances) and clears the active provider. `resume()` re-issues `/start`, which resumes the same `in_corso` competency and greets with the `resume` opening variant. The main spec's `Flow screens` table still says "mic muted, provider session kept alive", which is stale. | `useInterviewSession.ts` `pause`, `resume`, `callSuspend`; main spec lines 1017, 1085 | Exit is `session.pause()`. The MODIFIED `Flow screens` requirement corrects the pause row. |
| V4 | `useExitRedirect.redirect()` calls `useCandidateSession().clear()` before navigating. The stored candidate JWT (120 minutes, `CandidateTokenFactory`, `setTTL(120)`) is what makes a reopened invitation link resume without a new exchange: an unexpired stored session with matching claims means zero exchange calls (`interview-flow.spec.ts` "a stored, unexpired session with matching claims"). A spent link cannot rescue an expired session (main spec `Honest failure states...`). | `useExitRedirect.ts`; `useCandidateSession.ts`; main spec 1652-1676 | Exit must NOT use the exit redirect, and "resume later" has a real deadline and is browser-bound (R2, R3). |
| V5 | Provider state events: HeyGen emits `connecting`, `ready`, `listening`, `speaking` (avatar speak started), `ready` (speak ended), `complete`, `stopped`. Tavus emits only `connecting`, `ready`, `complete`, `stopped`. The E2E mock emits `connecting`, `ready`, `listening`. | `heygen.ts` 245-341; `tavus.ts` 91-241; `tests/e2e/fixtures/interview-provider.ts` | A speaker signal cannot rely on provider state alone (R4, D4). |
| V6 | `currentCaption` is overwritten by EVERY transcript entry of the live player, including `role: 'user'` entries (`onTranscriptFromPlayer` ignores `entry.role`). Both providers emit user-role entries. | `InterviewSession.vue` 795-808; `heygen.ts` 330; `tavus.ts` 197 | Today the candidate's own words can replace the caption. Decision 4 needs an explicit avatar-only filter. |
| V7 | `question_context` carries `end_phrase`, `final_phrase`, `question_index`, `competency_code` (in the E2E fixture) and totals; it carries no question text. The only text of the question is the avatar's own transcript. | `useInterviewSession.ts` 380-410; `branded-interview.ts` | "The written question" is the avatar's latest utterance (D6). A structured question field would be an `api` change (out of scope). |
| V8 | The per-question timer is owned by the page (`questionRemaining`, 300 s), counted by `InterviewTimer.vue` which emits `tick` and `expired`, goes `--color-recording` red and `aria-live="assertive"` in the last 10 s, and is re-armed per `sessionId`. `DESIGN.md` §7.3.1 mentions an amber state under 30 s that is not implemented. | `InterviewSession.vue` 706-775; `InterviewTimer.vue` | The counter keeps this behaviour exactly; no amber is introduced (D8). |
| V9 | There is no support page or URL. The only support affordance is the literal `mailto:support@beai.app`, repeated in `InterviewSession.vue` (3 times) and `pages/interview/terminal.vue`. `nuxt.config.ts` `runtimeConfig.public` has no support entry. | `rg support app nuxt.config.ts` | Configurable URL with a safe default (D10, open question 2). |
| V10 | The embed page reports `document.documentElement.scrollHeight` as the iframe height through a throttled `ResizeObserver`. Inside an iframe the SA-11 gate judges `screen.width`, not the iframe width, so a supported desktop can embed the interview in a container narrower than 1024 px. | `pages/embed/[token].vue` 350-383; `browser-gate.ts` `effectiveViewportWidth` | Embedded sizing must not depend on viewport height, and the layout must render in narrow containers (D13, R6). |
| V11 | `IntegrityToaster` is `position="top-right"` under the header, justified by "never a control or a reading" there (the right end held only the status pill). `integrity-toast.spec.ts` asserts the toast clears the Pause control. | `IntegrityToaster.vue`; `integrity-toast.spec.ts` 127-134 | A right-hand panel puts the progress readout exactly where the toast lands. The toaster moves to top-left under the call UI (D11). |
| V12 | `ProctorOverlay` renders nothing visible, mounts only inside the `live` block (so a pause unmounts it) and consumes the device-check `confirmedStream`; `useProctor` owns snapshots and integrity events. | `ProctorOverlay.client.vue`; `InterviewSession.vue` 319-326 | The self-view can show the same stream without a second `getUserMedia`; proctoring is untouched as long as the overlay stays mounted in the live state. |
| V13 | `MIC_SPEAK_THRESHOLD = 0.04` (RMS 0-1) is exported by `useDeviceCheck.ts`, and `VoiceVisualizer` already analyses the avatar's remote stream (`analysableStream`) through an `AnalyserNode`, but only in voice-only mode and only inside `AvatarPlayer`. | `useDeviceCheck.ts` 30-33; `AvatarPlayer.client.vue` | The candidate gate reuses the same threshold; the avatar stream must be surfaced by an emit (D4). |
| V14 | `useTabVisibilityGuard` pauses the interview after 60 s with the tab hidden; `useNetworkGuard` pauses on offline. Both reuse `session.pause()`. | `InterviewSession.vue` 883-919 | Opening the help link in a new tab for over a minute pauses the interview. This is existing, honest behaviour; the suspended screen explains it (D10). |
| V15 | The shipped live screen renders no recording indicator, although `DESIGN.md` §7.3.1 lists one. | `rg -i recording app --glob '*.vue'` | Not added; open question 4. |
| V16 | Playwright runs chromium, webkit and a mobile project against one server on 4174 (mock provider on), plus a second instance of the same build for the embed spec. `toHaveScreenshot` is configured (`maxDiffPixelRatio 0.02`); baselines exist for darwin and linux; `task e2e:frontend` runs the pinned container, `task e2e:update` regenerates baselines. | `playwright.config.ts`; `Taskfile.yml` 175-225 | A third instance with the flag on is the cheapest way to test the new screen without doubling the suite (D14). |

## 2. Decisions

### D1. One flag, one new subtree, the old screen frozen

`runtimeConfig.public.candidateCallUi` (string `'true'`, same convention as `interviewProviderMock`; env
`NUXT_PUBLIC_CANDIDATE_CALL_UI`; default `''`). A tiny composable `useCandidateCallUi()` returns a boolean. In
`InterviewSession.vue` the live branch becomes:

```
<section v-else-if="avatarMounted" ...>
  <CallStage v-if="callUi" ... />          // new
  <template v-else> ...today's live dock + pill... </template>   // frozen
```

and the header's status pill (`#header-end`, live) renders only when the flag is off. Everything new lives in new `Call*` files (table in section 3); the legacy markup is not edited except to be wrapped. No
shared piece is changed in a way that alters flag-off behaviour: `ProgressBar` and `IntegrityToaster` gain optional props
whose defaults reproduce today's output (tests pin this).

*Alternative rejected:* edit the live branch in place and rely on the flag only for CSS. That makes the old and new DOM
indistinguishable in review and makes rollback a revert.

### D2. Layout grid, tile hierarchy and sizes

Hierarchy (what the eye should find, in order): 1) the interviewer tile, 2) the written question, 3) the candidate's own
tile, 4) the side panel. The panel is white `bg-card` on the canvas so the existing card tokens keep their measured
contrast (DESIGN §3.1 rule 2); the tiles carry their own dark frames.

```
>= 1280 px  (xl): two columns, container max-w-[96rem], px-10, gap-6
+--------------------------------------------------------------+
| [logo plate] | Organization name                             |  header on canvas (BrandCanvas, wide)
|                                                              |
| +-------------------------------------+  +-----------------+ |
| |                                     |  | Domanda 2 di 5  | |
| |   INTERVIEWER TILE (16:9, dark)     |  | [===-----]      | |
| |                                     |  |                 | |
| |                     +-----------+   |  | 03:12 / 25:00   | |
| |                     | own camera|   |  | Tempo rimanente | |
| |                     +-----------+   |  |        04:12    | |
| +-------------------------------------+  |                 | |
| +-------------------------------------+  | [Esci, riprenderai| |
| | Question text (white band, live)    |  |  dopo]          | |
| +-------------------------------------+  | Problemi con    | |
|                                          |  audio o video? | |
|                                          +-----------------+ |
+--------------------------------------------------------------+

1024-1279 px (lg) and any narrower embed container: one column, the panel becomes a strip under the question
+--------------------------------------------------------------+
| tile (full width)            | question band                 |
| strip: Domanda 2 di 5 [==--] | 03:12 / 25:00 | 04:12 | [Esci...] | Problemi con audio o video? |
+--------------------------------------------------------------+
```

- **Columns.** `grid-template-columns: minmax(0, 1fr) var(--spacing-call-panel)` with `--spacing-call-panel: 18rem`
  (new token, section 6). Below `xl` the grid is one column and the panel is a flex-wrapped strip. DESIGN §6 already
  says `xl` is where "side-by-side layouts unlock".
- **Interviewer tile.** The existing player layer. `aspect-video`, `rounded-surface`, `shadow-avatar`, its dark
  `--color-avatar-bg` surface unchanged. In hosted mode its width is capped so the whole stage fits the viewport height:
  `max-w-[min(100%, calc((100dvh - var(--call-chrome)) * 16 / 9))]`, with `--call-chrome: 16rem` in two-column mode
  (header block 76 px + main padding 64 px + 16 px gap + a 96 px question band, rounded up) and `21rem` in strip mode.
  Worked numbers: at 1280x800 the left column is 888 px, so the tile is 888x500; the stack is 500 + 16 + 96 = 612 px
  against 660 px available, so a three-line question still fits. At 1440x900: 1048 px wide, no cap needed. At 1920x1080:
  the container tops out at 1536 px, the tile is 1144x643, and the stage is centred vertically with spare room.
- **Self-view tile** (D5): inside the tile's cell, bottom right, `width: clamp(9rem, 18%, 14rem)`, 16:9.
- **Question band.** White `bg-card` surface under the tile, `min-h-24`, `max-h-44`, `overflow-y-auto`, `tabindex="0"`
  (a scrollable region must be keyboard reachable; it doubles as the programmatic focus target, D6).
- **Embedded mode** (`embedded` prop, D13): no `dvh` anywhere; width-driven only.
- **Wide canvas.** `BrandCanvas` gains a boolean `wide`; when set, the header column and the main container widen from
  `max-w-6xl` to `max-w-[96rem]` so the logo plate stays aligned with the stage (DESIGN §7.0.1 amendment).

### D3. The avatar player layer is never re-parented

The existing wrapper (`v-if="session.players.value.length > 0"`, `data-slot="avatar-layer"`) stays the same element
across `connecting`, `live`, handover and fallback. Under the flag a stable parent, `data-slot="call-layout"`, wraps it
and is itself rendered whenever `players.length > 0`. The parent is a CSS grid in the live state and `display: contents`
otherwise; the avatar layer toggles classes only (grid placement in the live state, today's `sr-only` when there is no
`live` player). The question band, the panel and the self-view are siblings inside the same grid, mounted only while the
state is `live` and `avatarMounted`. Consequences, all tested in `UI-09`:

- one mount and one `stop()` per player across `connecting -> live -> paused` and across a HeyGen handover (the existing
  mount-count assertions in `interview-session-page.spec.ts` are reused against the flag-on tree);
- the `overlay` crossfade (`absolute inset-0` incoming player) still works because the layer keeps `relative overflow-hidden`;
- the bound-exceeded fallback (`transition-panel`) still hides the layer with `sr-only`.

*Alternative rejected:* `<Teleport>` of the avatar into a stage slot. It moves DOM without unmounting, but its target
must exist at mount, which couples the layer's lifetime to the stage's and is exactly the coupling V2 warns about.

### D4. Who is speaking: one signal from existing events plus audio level

A composable `useSpeakerTurn()` returns `speaker: Ref<'avatar' | 'candidate' | 'none'>`. Inputs, all already available:

| Input | Source | Used for |
|---|---|---|
| Provider state of the `live` role (`speaking`, `ready`, `listening`) | `onProviderState(role, state)` (already wired, `live` only) | Immediate avatar-on (HeyGen). |
| Avatar remote audio level | new `AvatarPlayer` emit `stream: MediaStream \| null`, fired with `painted` (it already holds `analysableStream`); analysed by an `AnalyserNode` | Avatar-on for providers that emit no speaking state (Tavus). |
| Candidate mic level | the device-check `confirmedStream` (already in `InterviewSession`), analysed locally, nothing sent anywhere | Candidate-on. |
| Session state | `session.state` | Forced `none` unless `live`. |

Rules (constants exported and unit-tested; fake timers and a fake analyser):

1. `avatar` when the provider state is `speaking`, OR the avatar audio RMS stays above `AVATAR_AUDIO_GATE` for 120 ms.
   Held for 600 ms after the last positive reading (no flicker between words).
2. `candidate` when not `avatar` AND the mic RMS stays above `MIC_SPEAK_THRESHOLD` (0.04, the same constant the device
   check uses, so a mic that passed the check lights the ring) for 200 ms. Held for 800 ms. Suppressed while `avatar` is
   active and for 500 ms after it ends, so a candidate with speakers is not "speaking" while the avatar talks.
3. `none` otherwise, including while the avatar is thinking between turns and in every non-`live` state.
4. A provider `speaking -> ready` transition does not end the avatar turn while the avatar audio gate is still active.

Reduced motion changes nothing here; the signal is state, not animation. Cost: a 60 ms `setInterval` reads two analysers; it starts
when the state becomes `live` and stops otherwise, so nothing runs while paused. **UNVERIFIED:** real HeyGen/Tavus audio reaching an `AnalyserNode` in WebKit (the existing `VoiceVisualizer`
proves it for the voice-only path in production, so the risk is low but not zero); a manual pass is a listed step.

*Alternative rejected:* inferring the turn from transcript roles. Transcripts arrive after the utterance, so the border
would light late and stay on while the other side has already started.

### D5. The glowing border and the self-view tile

A molecule `CallTile` renders a frame with a name chip and the ring; the interviewer tile and the self-view tile both use it.

- **Resting frame:** 2 px `--color-avatar-bg`.
- **Active ring** (`data-speaking="true"`): 2 px `--color-avatar-bg`, then a 3 px `--color-speaking-ring` (`#ffffff`, new
  frontend token), then a 2 px `--color-avatar-bg` keyline, then a soft 32 px white-30% halo. The halo is decoration; the
  measured indicator is the white band between two dark bands, so it holds against ANY brand colour and any video content.
  White on `#0f172a` is about 17.9:1 by WCAG relative luminance, asserted numerically in the unit test (not by this sentence).
- **Not colour alone:** the name chip shows a filled microphone icon when active, and the chip carries visually hidden
  text ("L'intervistatore sta parlando" / "Stai parlando"). The hidden text is NOT a live region: announcing every turn
  would bury the question, the same argument DESIGN §7.3.1 ("Accessibility") makes for the voice visualizer.
- **Motion:** `transition: box-shadow 150ms ease-out` under `motion-safe` only; nothing pulses or loops (DESIGN §7.0.1
  "nothing loops"; §10 "default: no animation"). Under `prefers-reduced-motion: reduce` the ring switches instantly.
- **Forced colours:** `@media (forced-colors: active)` replaces the box-shadow with `outline: 4px solid Highlight`
  (box-shadows are dropped in that mode).
- **Self-view** is a `.client.vue` molecule: a muted `<video playsinline>` bound to `confirmedStream` with
  `srcObject`, mirrored with `transform: scaleX(-1)` (a visual flip only, the proctoring stream is unchanged), no controls,
  `tabindex="-1"`, `disablePictureInPicture`, an `aria-label` from i18n, and `pointer-events: none` so it can never take
  focus or a click (the camera tile must not trap focus). If the stream has no live video track it shows a static
  camera-off placeholder and the same label. It adds no `getUserMedia` call.

### D6. The written question

`CallQuestion` is the old `InterviewCaption` idea made permanent: a white band under the tile, `text-xl` (20 px)
`leading-8` `font-medium` `text-card-foreground`, wrapped in one persistent `aria-live="polite"` `aria-atomic="true"`
region that stays mounted, with `aria-label` "Domanda corrente". Rules:

- **Source:** the latest transcript entry with `role === 'avatar'` for the `live` player. The filter lives in
  `onTranscriptFromPlayer` and is the implementation of decision 4 (V6): `role === 'user'` entries still reach
  `/candidate/interview/utterance` (the server needs them) but never reach the displayed text.
- **Persistence:** the text stays until the next avatar utterance replaces it. It never fades out.
- **Before text exists** (start of a competency, resume): the existing hint `interview.live.listen_hint` fills the band.
- **At a competency boundary** (new `sessionId` or a promoted handover) the text clears to the hint, so the previous
  closing phrase is not shown as the new question.
- **Focus:** at a competency boundary only, focus moves to the band (DESIGN §9.2: "after interview question transitions,
  focus MUST move to the new question element"), unless focus is inside an open dialog. Never per utterance.
- **Honest lag (R5):** both providers deliver the avatar's text as a finished utterance, so the text can appear after the
  voice has started. The hint covers the gap; the design does not promise text-before-speech. **UNVERIFIED** for real providers.

### D7. The side panel: progress and time, never a name

`CallPanel` (organism, `<aside aria-label="Avanzamento del colloquio">`). Top to bottom:

1. **Progress.** Text "Domanda {n} di {total}" with `n = min(endedCompetencies + 1, total)`; `total = totalCompetencies`.
   A thin bar (`ProgressBar`, new props `hideCounts` and `valueText`; defaults unchanged) with `aria-valuenow = ended`,
   `aria-valuemax = total` and `aria-valuetext` equal to the visible text. Both numbers come from the server fields
   already stored by `callEnd`; nothing is derived from a list, and the competency code and name are never read here
   (a unit test renders the panel with a store that contains a competency code and asserts the text does not).
   The heuristic QA label (`questionLabel`, "Q1.2") is not shown (open question 8).
2. **Duration.** "03:12 / 25:00": `elapsed` from a new `useInterviewClock()` (accumulates whole seconds only while
   `session.state === 'live'`, from monotonic timestamps so a throttled background tab does not drift) and
   `total = totalCompetencies x 300` seconds (the same `QUESTION_TIME_LIMIT`), labelled as a maximum. Minutes are not
   wrapped at 60. Hidden until the server states a total. Screen-reader text: "03:12 trascorsi su un massimo di 25:00".
   Reload restarts the elapsed counter (open question 5; documented limitation, not a silent inaccuracy).
3. **Question timer** (D8).
4. **Exit** (D9) and **help link** (D10), at the bottom, in that DOM order.

### D8. Timer widget: the counter

The demo offers a bar (three threshold bands), a counter and a ring. The counter is chosen (proposal decision 9). It is
`InterviewTimer.vue` restyled, not rewritten: same props, same `tick`/`expired` contract, same parent-owned
`questionRemaining`, so the pause/resume exemption and the per-`sessionId` re-arm keep working untouched (the existing
unit tests for those stay green because the contract is unchanged). In the panel it reads "Tempo rimanente per questa
domanda  04:12" in `font-mono` `tabular-nums` `text-base` `font-semibold`; `<time role="timer">` is kept. The only
threshold is today's: `--color-recording` and `aria-live="assertive"` at 10 s or less (4.83:1 on the white panel). No
amber, no bands, no minimum/ideal/maximum. Because it now sits on a white panel instead of a white pill, the contrast
claim in DESIGN §7.0.1 ("the urgent timer on the white status pill") is restated for "white panel".

### D9. Exit: suspend now, resume later, honestly

```
[Esci, riprenderai dopo] --click--> Dialog (focus trapped, Esc closes, focus returns to the button on cancel)
   title:  Vuoi uscire dal colloquio?
   body:   Il colloquio verrà sospeso e non viene registrato nulla. Potrai riprenderlo dalla stessa domanda
           riaprendo il link di invito da questo browser, entro le {HH:MM}.
   [Sospendi ed esci]   [Resta nel colloquio]
          |
          v  onExitConfirmed(): pauseReason = 'exit'; session.pause()
   state 'paused' -> "suspended" variant of the paused panel
          title: Colloquio sospeso
          body:  Hai sospeso il colloquio. Per riprendere, riapri il link di invito da questo browser entro le {HH:MM},
                 oppure premi Riprendi.
          [Riprendi]  -> onResumeClicked() -> session.resume() -> /start (same competency, 'resume' greeting)
```

- **Mechanism reuse, no new endpoint.** `session.pause()` already stops the provider, calls `/suspend` and unmounts the
  live block (so the proctor overlay and the camera tile unmount with it); `session.resume()` already re-issues `/start`.
  `PauseReason` gains `'exit'`, used only to choose the suspended wording.
- **The deadline** `{HH:MM}` is the stored token's `exp` formatted in the candidate's locale, read through
  `useCandidateSession().read()` (the only sanctioned reader). If `read()` returns null the sentence is dropped, not guessed.
- **Never** `useExitRedirect().redirect()` (V4): it clears the stored session, which would make "riprenderai" false.
  `exit_redirect_url` keeps its one meaning, "the interview is complete".
- **During a handover** the button is disabled and shows the loading state (never hidden), as the Pause button does today
  (`handoverInFlight`). `pause()` also refuses during a handover, so this is consistent.
- **Embedded mode:** the same flow; the host page sees the iframe stay on the suspended screen. No new postMessage event
  is added (the protocol is a separate package).
- **Focus:** on entering the suspended panel, focus moves to its heading (`tabindex="-1"`), because the Exit button that
  held focus has just unmounted.
- **Automatic pauses** (tab hidden, network) keep today's wording; only a deliberate exit shows the suspended variant.
- **Why a confirmation dialog.** The label says "Esci" and the action tears down a live conversation; an accidental click
  is expensive (reconnect plus a `resume` greeting). The dialog also carries the deadline. The owner's decision fixes the
  label, not the absence of a confirmation; if the owner prefers no dialog, only the dialog molecule is dropped.

### D10. Help link

`CallHelpLink` renders an `<a>` with the label «Problemi con audio o video?» pointing at `useSupportUrl()`, which reads
`runtimeConfig.public.supportUrl` (env `NUXT_PUBLIC_SUPPORT_URL`), validates it with a pure function (`https:` or
`mailto:` only; anything else, or empty, falls back to `mailto:support@beai.app`), and is the single source for the four
existing hardcoded `mailto:` sites (`InterviewSession.vue` x3, `terminal.vue`). `https:` links open with
`target="_blank" rel="noopener noreferrer"` and carry a visually hidden "(si apre in una nuova scheda)"; `mailto:` links
do neither. Styled `text-primary-ink` underline (DESIGN §7.3 "support links are `text-primary-ink`"), 44 px target
height (`--spacing-control`), visible 2 px ink focus ring. V14: opening the page in a new tab for over 60 s pauses the
interview through the existing tab guard; the suspended panel's existing `tab_hidden_warning` explains it. The real URL is
open question 2; the default makes the link work today.

### D11. Theming, tokens and the DESIGN.md amendments

No new colour is introduced except one frontend-only constant. Amendments to `DESIGN.md`, landing in `UI-00` before code:

| Section | Amendment |
|---|---|
| §3.1 Interview-specific | Add `--color-speaking-ring: #ffffff` (the speaking ring's white band; paired with `--color-avatar-bg`, measured by a unit test). |
| §3.3 Spacing | Add `--spacing-call-panel: 18rem` (side panel width). |
| §3.5 Shadows | Document the speaking-ring composite (resting 2 px, active 2+3+2 px bands plus halo) as the one "tile ring" elevation; it nests no raised card inside a raised card (the tiles are not cards). |
| §7.0.1 | `BrandCanvas` option `wide` (header and main column `max-w-[96rem]`) used by the live call only. |
| §7.3 | Replace the live diagram, header-chrome bullet, "Live dock" bullet with the call stage (tiles, question band, side panel, exit, help); state that the status pill is superseded; keep the flag-off description until `UI-13`. |
| §7.3 (end) | Restate the urgent-timer contrast pair for the white panel; the amber-under-30-s sentence is removed as it never shipped (V8). |
| §9.2 | Note that the question band is the focus target at a competency boundary. |
| §10 | Add the speaking ring: 150 ms box-shadow transition under `no-preference`, none under `reduce`, never looping. |
| §14 | No change; the interview route is `ssr: false` and behind auth, so Lighthouse targets are unchanged. CLS is guarded by reserved aspect ratios (D2). |

Brand behaviour: the logo plate and canvas colour come from `BrandCanvas` unchanged; the panel and the band are `bg-card`;
the progress fill is `bg-primary-ink` (≥ 3:1 on its track, existing guarantee); the ring does not use the brand colour at
all, which is deliberate (R7). The integrity toaster moves to `position="top-left"` under the call UI via a new optional
`position` prop (V11): top-left under the header overlaps only a corner of the avatar tile, never the panel.

### D12. Accessibility checklist (each item is a test or a manual step)

| # | Requirement | How it is met / verified |
|---|---|---|
| A1 | Live region for the question | One persistent `aria-live="polite"` `aria-atomic` region; unit test mounts it empty, then updates it; axe on the live screen. |
| A2 | Focus order | DOM order: question band (`tabindex=0`), Exit, help link. No positive `tabindex`. Playwright asserts Tab order. |
| A3 | Self-view does not trap focus | No interactive content, `tabindex=-1`, `pointer-events:none`; Playwright tabs through the screen and never lands on it. |
| A4 | Exit and help keyboard operable | Native `<button>` and `<a>`; Enter/Space; Esc closes the dialog; focus returns to Exit on cancel. |
| A5 | Dialog | Existing `ui/dialog` (focus trap, Esc, restore); axe on the open dialog. |
| A6 | Contrast of the glowing border | White band between two `--color-avatar-bg` bands; numeric unit test (≥ 3:1 required, about 17.9:1 expected) for light, dark and no brand colour; independent of the canvas colour. |
| A7 | Not colour alone | Icon plus hidden text on the name chip; forced-colours outline. |
| A8 | Reduced motion | No transition under `reduce`; nothing animates otherwise except the 150 ms ring change. Unit test on the class list; Playwright with `reducedMotion: 'reduce'`. |
| A9 | Timer announcements | Unchanged: `role="timer"`, `aria-live="assertive"` only in the last 10 s. |
| A10 | Progress | `role="progressbar"` with `aria-valuetext` equal to the visible text. |
| A11 | Page title and landmarks | `<main>` from `BrandCanvas`, `<aside aria-label>` for the panel; the existing document title test stays green. |
| A12 | Target size | Exit and help ≥ 44 px (`--spacing-control`). |
| A13 | Lighthouse accessibility 100 on the entry routes | Unchanged routes; the interview route is behind auth, so axe in Playwright is the gate. |
| A14 | Screen readers | **UNVERIFIED until run:** a manual NVDA (Windows, Chrome) and VoiceOver (macOS, Safari) pass over the question region, the boundary focus move, the dialog and the suspended screen. Recorded in the PR, not claimed here. |

### D13. Responsive behaviour, minimum size and the unsupported gate

- **Supported floor.** SA-11 is unchanged: below 1024 px the gate redirects, and a mid-session resize below 1024 px still
  flushes integrity and stops the provider first (`useInterviewSession`'s resize listener). The call screen adds no
  second gate.
- **1280 px and up:** two columns (D2). **1024-1279 px:** one column, panel as a strip, hosted height cap `21rem`.
- **Embedded container below 1024 px** (V10): the same single-column layout down to 480 px; the self-view clamps to 9 rem;
  nothing is guaranteed below 480 px, which is documented.
- **Embedded height rule (R6).** `InterviewSession` gets an `embedded` prop, set by `pages/embed/[token].vue`. When set, the
  stage uses no `vh`/`dvh`/`svh` unit; the tile is width-driven. A source test greps the call components for those units and
  an embed E2E asserts the last two posted `resize` heights are equal after the stage mounts.
- **No horizontal scroll** at any width ≥ 480 px; **no vertical scroll** at 1280x800, 1440x900, 1920x1080 in hosted mode.
  1366x768 is best effort (the tile shrinks through the height cap).

### D14. Test strategy

**Vitest (Vue Test Utils, happy-dom), one spec per unit, written RED first:**

| Spec | Proves |
|---|---|
| `use-speaker-turn.spec.ts` | Each rule of D4 with fake timers and a fake analyser: provider-only avatar, audio-only avatar, candidate gate at the shared threshold, suppression and tail while the avatar speaks, holds, forced `none` outside `live`. |
| `call-tile.spec.ts` | Resting and active class lists, hidden text, icon, forced-colours class, no transition class under the reduced-motion variant, **numeric contrast** of ring vs `--color-avatar-bg` for the brand matrix. |
| `call-question.spec.ts` | Avatar-only text (user entries ignored), persistence, hint, clear at a boundary, live-region attributes, `tabindex`, focus move at a boundary only. |
| `call-self-view.spec.ts` | Binds `confirmedStream`, muted, mirrored, no controls, not focusable, placeholder without a video track, no `getUserMedia` call. |
| `call-panel.spec.ts` | "Domanda n di total" arithmetic including `ended = total`, `aria-valuetext`, no competency text even when the store holds a code, duration format beyond 60 minutes, hidden until a total exists. |
| `use-interview-clock.spec.ts` | Accumulates only while live, survives pause/resume, drift-free with fake timers. |
| `call-exit.spec.ts` | Dialog open/cancel/confirm, focus return, deadline from `exp`, null session drops the sentence, `pause()` called once, `redirect()` and `clear()` never called, disabled during a handover. |
| `support-url.spec.ts` | `https:` and `mailto:` accepted, `javascript:`/`http:`/garbage/empty fall back, attributes per scheme. |
| `interview-session-call-ui.spec.ts` | Flag on: stage renders, no status pill, no Pause button, no `interview-status`; flag off: tree equals today's (the existing `interview-session-page.spec.ts` stays green untouched); one mount and one stop per player across `connecting`, `live`, `paused`, handover (R1). |
| `arch/call-ui-arch.spec.ts` | No `vh`/`dvh`/`svh` in the Call* components (embedded rule), no competency fields imported by the panel, no literal user-visible strings. |
| `i18n-interview-keys.spec.ts` (extended) | Every new key exists in `it.json` and `en.json`. |
| `integrity-toast.spec.ts` (extended) | Default position unchanged; `top-left` honoured. |

**Playwright (chromium AND webkit; mobile project unchanged):** a new `interview-call.spec.ts` runs against a **third
server instance** of the same build on port 4177 with `NUXT_PUBLIC_CANDIDATE_CALL_UI=true`, selected by two new projects
(`chromium-call`, `webkit-call`, `baseURL: 'http://127.0.0.1:4177'`, `testMatch: ['**/interview-call*.spec.ts']`) so the existing 4174 suite is untouched
while the flag is off. Cases: the stage renders with the mock provider; the question appears from an avatar transcript and
the candidate's `emitTranscript(text, 'user')` never appears; the ring follows mock speaking/listening and the self-view
ring follows a faked mic level; Exit opens the dialog, cancel returns focus, confirm calls `/suspend` once, shows the
suspended screen, keeps the stored session, and Resume re-issues `/start` for the same competency; the help link target
and attributes; axe on the live screen, the open dialog and the suspended screen under a light and a dark brand;
keyboard-only Tab order; `reducedMotion: 'reduce'`; no-scroll viewport matrix; embed route height stability. The mock
provider fixture gains `emitSpeaking()` / `emitListening()` helpers (additive).

**Visual regression.** The repo already uses `toHaveScreenshot` with `darwin` and `linux` baselines and the container
task. `UI-11` adds baselines for the live call screen at 1440x900 for the light `#ffd400` and dark `#771aaf` brands
(DESIGN's four-brand screenshot matrix is covered by the numeric contrast test for all four plus a reviewer pass on the
two screenshots), in both browsers, with the self-view video masked and the animation disabled. Baselines are generated by
`task e2e:update` (container) and reviewed in the PR; they are generated artifacts and excluded from the review budget.

**Existing tests affected (they stay on the old screen until the flip, then migrate in `UI-12`):** E2E
`interview-flow.spec.ts` (Pause and Resume, handover Pause-visible assertions, live dock), `interview-chrome.spec.ts`
(Pause button, timer), `integrity-toast.spec.ts` (toast clears the Pause control), `browser-gate-middleware.spec.ts` (Pause
as the "live" signal), `interview-exit-redirect.spec.ts`; unit `interview-session-page.spec.ts`,
`interview-session-guards.spec.ts`, `interview-components.spec.ts`, `interview-chrome.spec.ts`, `i18n-interview-keys.spec.ts`.

### D15. The two tester findings

Reserved slots `T-BUG-1` and `T-BUG-2` (tasks) with acceptance criteria already fixed as behaviour in the spec
(`A Competency Boundary Is A Smooth Handover`, `No Greeting Is Spoken At A Competency Boundary`). Nothing in D1-D14
assumes a root cause. Two things are already known from reading the code and are recorded without drawing a conclusion:
the `resume` opening variant is the greeting used by `/start` after `/suspend` (V3), and `tavus-single-session-interview`
is a separate, in-flight change aimed at the Tavus per-competency reconnect. Whether either explains the findings is for
Appendix A.

## 3. Components and files

All under `frontend/`. "New" files are created by the slice named in `tasks.md`.

| File | Kind | Slice | Notes |
|---|---|---|---|
| `app/composables/useCandidateCallUi.ts` | new | UI-01 | Reads `runtimeConfig.public.candidateCallUi`. |
| `nuxt.config.ts` | modify | UI-01, UI-08 | `public.candidateCallUi: ''`, `public.supportUrl: ''`. |
| `app/components/organisms/BrandCanvas.vue` | modify | UI-01 | `wide` prop, default false. |
| `app/composables/useSpeakerTurn.ts` | new | UI-02 | D4. |
| `app/components/AvatarPlayer.client.vue` | modify | UI-02 | New `stream` emit; nothing else. |
| `app/components/molecules/CallTile.vue` | new | UI-03 | Frame, ring, name chip. |
| `app/assets/css/main.css` | modify | UI-03 | Token and ring styles. |
| `app/components/molecules/CallQuestion.vue` | new | UI-04 | D6. |
| `app/components/molecules/CallSelfView.client.vue` | new | UI-05 | D5. |
| `app/composables/useInterviewClock.ts` | new | UI-06 | Elapsed live seconds. |
| `app/components/organisms/CallPanel.vue` | new | UI-06 | D7. |
| `app/components/ProgressBar.vue` | modify | UI-06 | `hideCounts`, `valueText`, defaults unchanged. |
| `app/components/InterviewTimer.vue` | modify | UI-06 | Counter styling and an optional `label` prop; contract unchanged. |
| `app/components/molecules/CallExitDialog.vue` | new | UI-07 | D9. |
| `app/components/InterviewSession.vue` | modify | UI-07, UI-09 | `pauseReason 'exit'`, suspended variant, flag wiring, `embedded` prop. |
| `app/utils/support-url.ts`, `app/composables/useSupportUrl.ts` | new | UI-08 | D10. |
| `app/components/molecules/CallHelpLink.vue` | new | UI-08 | D10. |
| `app/pages/interview/terminal.vue` | modify | UI-08 | Uses `useSupportUrl()`. |
| `app/components/organisms/CallStage.vue` | new | UI-09 | The grid that wraps the player layer. |
| `app/components/molecules/IntegrityToaster.vue` | modify | UI-09 | Optional `position`. |
| `app/pages/embed/[token].vue` | modify | UI-09 | Passes `embedded`. |
| `i18n/locales/it.json`, `en.json` | modify | each slice | Keys in section 4, added by the slice that uses them. |
| `tests/e2e/interview-call.spec.ts`, `tests/e2e/fixtures/interview-provider.ts`, `playwright.config.ts` | new/modify | UI-10, UI-11 | Section D14. |
| `DESIGN.md` (wrapper) | modify | UI-00 | Section D11. |

## 4. i18n keys (both locales, added by the slice that renders them)

| Key | it | en |
|---|---|---|
| `interview.call.interviewer_name` | Intervistatore AI | AI interviewer |
| `interview.call.you` | Tu | You |
| `interview.call.avatar_speaking` | L'intervistatore sta parlando | The interviewer is speaking |
| `interview.call.candidate_speaking` | Stai parlando | You are speaking |
| `interview.call.question_region` | Domanda corrente | Current question |
| `interview.call.self_view` | La tua fotocamera | Your camera |
| `interview.call.self_view_off` | Fotocamera non disponibile | Camera unavailable |
| `interview.call.panel_label` | Avanzamento del colloquio | Interview progress |
| `interview.call.progress` | Domanda {n} di {total} | Question {n} of {total} |
| `interview.call.duration_label` | Durata | Duration |
| `interview.call.duration_value` | {elapsed} / {total} | {elapsed} / {total} |
| `interview.call.duration_sr` | {elapsed} trascorsi su un massimo di {total} | {elapsed} elapsed out of a maximum of {total} |
| `interview.call.question_timer_label` | Tempo rimanente per questa domanda | Time left for this question |
| `interview.call.exit.label` | Esci, riprenderai dopo | Exit, you can resume later |
| `interview.call.exit.title` | Vuoi uscire dal colloquio? | Leave the interview? |
| `interview.call.exit.body` | Il colloquio verrà sospeso e non viene registrato nulla. Potrai riprenderlo dalla stessa domanda riaprendo il link di invito da questo browser, entro le {time}. | The interview will be suspended and nothing is recorded. You can resume at the same question by reopening your invitation link in this browser, until {time}. |
| `interview.call.exit.body_no_deadline` | Il colloquio verrà sospeso e non viene registrato nulla. Potrai riprenderlo dalla stessa domanda riaprendo il link di invito da questo browser. | The interview will be suspended and nothing is recorded. You can resume at the same question by reopening your invitation link in this browser. |
| `interview.call.exit.confirm` | Sospendi ed esci | Suspend and leave |
| `interview.call.exit.cancel` | Resta nel colloquio | Stay in the interview |
| `interview.call.suspended.title` | Colloquio sospeso | Interview suspended |
| `interview.call.suspended.body` | Hai sospeso il colloquio. Per riprendere, riapri il link di invito da questo browser entro le {time}, oppure premi Riprendi. | You suspended the interview. To resume, reopen your invitation link in this browser before {time}, or press Resume. |
| `interview.call.suspended.body_no_deadline` | Hai sospeso il colloquio. Per riprendere, riapri il link di invito da questo browser, oppure premi Riprendi. | You suspended the interview. To resume, reopen your invitation link in this browser, or press Resume. |
| `interview.call.help.label` | Problemi con audio o video? | Trouble with audio or video? |
| `interview.call.help.new_tab` | (si apre in una nuova scheda) | (opens in a new tab) |

`interview.live.listen_hint`, `interview.live.avatar_label`, `interview.live.region_label`, `interview.paused.resume`
and `interview.progress.label` are reused. The two `_no_deadline` rows exist because the deadline is dropped, not guessed, when the stored token cannot be read.

## 5. Risks carried into the design

R1 (D3, test), R2 (D9 wording, open question 1), R3 (D9, test), R4 (D4, manual pass), R5 (D6, manual pass), R6 (D13, source
test and E2E), R7 (D5, numeric test), R8 (flag split, D14), R9 (D2 numbers, viewport matrix), R10 (proposal
"Dependencies"), R11 (D6 focus rule, D12 A14).

## Appendix A. Tester findings: root cause and fix design

Filled 2026-10-09 from a read-only code investigation (evidence: file and line references below were read on
`develop`; nothing here was observed live except where stated).

### A.1 Finding (a): audio/video stop and a jerky move to question 2

**Root cause (HeyGen, confirmed in code): a regression introduced on 2026-10-08.** `InterviewController::end()` released the
provider session synchronously (`ReleaseProviderSession`, added by the HeyGen context cleanup). Before that day the
HeyGen `teardown()` used `DELETE /v1/sessions/{ref}`, which answers 405 and never stopped anything. The release now
really stops the outgoing HeyGen session (`POST /v1/sessions/stop`) while the frontend handover
(`useInterviewSession.ts`, archived change `invisible-competency-handover`, D5 "outgoing stays live") keeps the
outgoing stream alive until the INCOMING one has painted, then crossfades. The SDK reports a server stop as a
disconnect; with no incoming session yet the live handle's `error` branch went to the error state, nulled the active
session and turned the next start into a hard cut with the connecting panel. Candidate-visible result: the avatar
freezes or goes black at the end of question 1 and question 2 appears abruptly.

**Fix design (two parts, both merged as separate PRs):**
1. api: a HeyGen competency that ends `completed` with `next_action === 'continue'` queues a delayed
   `ReleaseEndedProviderSessionJob` (`interview.provider_release_delay_seconds`, default 45 s = handover bound 10 s +
   connecting ceiling 20 s + 15 s margin) instead of releasing at once; every other end still releases immediately.
2. frontend: an outgoing session that emits `error 'disconnected'` during a handover (`handoverActive`, no incoming yet)
   no longer moves the interview to `error`; the pending `/end` still reaches `startNextSession`.

**Tavus (not a regression, by design today):** there is no crossfade for Tavus (the handover is gated on HeyGen), so
every competency boundary is a hard cut with the connecting panel. It is removed only by the Tavus single-session
change (FE-06 of `tavus-single-session-interview`); until then the acceptance criterion of `T-BUG-1` is scoped to HeyGen.

**Tests that pin it:** Pest (`EndReleasesProviderContextTest`: deferred release for completed+continue, immediate for
every other end, the job releases exactly the refs captured at dispatch); Vitest (`use-interview-session.spec.ts`:
outgoing death during a handover does not reach `error`; the same error outside a handover still does; the mid-crossfade
race test stays unmodified). A Playwright frame-sampling test of the boundary remains part of `T-BUG-1.1`.

### A.2 Finding (b): the avatar greets again at the start of question 2

**Root cause (partly established).** For competency N > 1 the backend builds no greeting: `OpeningTextComposer` returns
the authored primary question verbatim for `first`, `next` and `resume`, and `lang/*/interview.php` has no greeting
string. But every `/start` creates a NEW provider session (a new conversation on Tavus) whose language model has no
memory of question 1, and the prompt's `OPENING` section never says this is a continuation or forbids a welcome. So a
greeting comes from (1) an operator-authored primary question that is itself a greeting (the composer comments cite
"Ciao! Come ti chiami?" as a legitimate primary), or (2) the provider model or persona adding a courtesy opening in a
fresh context. Which one the testers hit is not determined (it needs the second session's first avatar utterance rows,
the project's `project_questions`, and for Tavus the persona prompt).

**Fix design.** Add an explicit continuation clause to the `OPENING` section when the competency is not the first and
the opening is not a resume: "This is not the start of the interview. The candidate has already been welcomed and has
answered earlier questions. Do NOT greet, welcome or introduce yourself again." The spoken opening text stays verbatim.
Implementation: a continuation flag on `SpokenOpening::primary()`, set by `InterviewController` for `!$isFirst`, a new
optional prompt fragment key with an English baseline and a fallback so provided template sets lacking it stay valid,
rendered by `SystemPromptComposer::buildOpeningSection`. If the greeting is inside the authored question, only the
operator can change it; the backend must not strip text. The Tavus single-session change removes the per-competency
`custom_greeting` for Tavus once it ships, but not for HeyGen nor for the flag-off path, so the clause is needed anyway.
Tests: `SpokenOpeningTest`, `PromptFragmentKeyTest`, `BaselinePromptFragmentsTest`, `SystemPromptComposerTemplatesTest`,
`SystemPromptComposerTest` (clause present for competency 2, absent for competency 1 and on resume),
`InterviewStartCompositionTest` (the second `/start` prompt contains the clause, the first does not) and new goldens for
the continuation case; the existing goldens stay byte-identical (the flag defaults to false).

### A.3 Additional finding recorded here: Tavus `pal` duplicate utterances

A live Tavus test on 2026-10-09 showed every avatar utterance arriving twice (`role: "replica"` and `role: "pal"`,
same `inference_id`); the old provider code emitted each `pal` copy as candidate speech. Fixed separately in
`fix/tavus-pal-duplicate` (the `pal` role is the avatar and the duplicate is dropped). It affects the transcript the
call UI renders and the candidate's utterance rows, so the call UI must not re-introduce a role mapping of its own.
