# Delta for Interview Frontend

> Proposed 2026-10-09. MODIFIED requirements keep their main-spec titles exactly and carry their full current text with
> the changes marked "(Previously: ...)". They describe the end state in which the call screen is the only live screen
> (after tasks `UI-12`/`UI-13`); while the `candidateCallUi` flag is off, the unmodified main-spec text still describes
> what ships. Nothing is REMOVED. Reserved: the root cause and fix design for the two tester findings are appended to
> `design.md` Appendix A, and the last two ADDED requirements state their acceptance criteria independently of the cause.

## MODIFIED Requirements

### Requirement: Flow screens — localized states

The system MUST present the following named screens, each with all copy i18n-keyed
(locale from the candidate JWT language claim, minimum it/en):

**State machine:** `idle → device_check → connecting → live ⇄ paused → end_of_question → done | error | terminal`
(Previously: this line omitted `paused` entirely, contradicting the claim elsewhere in
this delta that the ratified live mute-pause is unaffected — that pause **is** the
`paused` state in shipped code (`useInterviewSession.ts:573-595`, `frontend` v0.6.3).
Corrected per design decision **D13**: `paused` survives, with `live` as its sole entry
AND exit — `live → paused` (Pause) and `paused → live` (Resume, now unconditional). What
is actually removed is narrower than previously stated: only the
**between-competency, candidate-optional** pause — the `end_of_question → paused` edge
and the `paused → end_of_question` fallback (the `pausedFrom` bookkeeping it required) are
deleted, because `end_of_question` becomes the SA-04 scheduled-pause screen and a Pause
control on a pause screen is meaningless. The `live ⇄ paused` edges themselves are
untouched by this change.)

**`terminal` vs `error` distinction:**
- `terminal` (no exit, no retry): `403` from any endpoint; absent/empty `end_phrase` or `final_phrase` (version mismatch / ops error). Shows a static localized screen; no retry control.
- `error` (retryable): `502`, network failure, or 3× `provider_busy`. Shows an error+retry screen; retry resets the attempt counter.

| Screen | State machine state | Entry trigger | Exit trigger |
|---|---|---|---|
| Consent | `idle` | Page mount; consent not yet accepted | Candidate accepts consent → `device_check` |
| Device Check | `device_check` | Consent accepted | Both camera + mic confirmed → `connecting` |
| Live Interview | `live` | `/start` returns `201` and provider is `ready` | Avatar signals completion / timer expires → `next_action` decides the destination; `403` → `terminal`; `502` → `error`; candidate confirms Exit, or the tab-hidden or network guard fires → `paused` |
| Paused / Suspended | `paused` | Candidate confirms Exit during `live`, or the tab-hidden (> 60 s) or network guard fires; the provider session is ended and `POST /candidate/interview/suspend` is sent; the live block and its camera tile unmount | Candidate presses Resume → `connecting` via `POST /start` (the same `in_corso` competency, `resume` opening), then `live`; a reopened invitation link in the same browser resumes the same way |
| End of Question (SA-04 pause screen) | `end_of_question` | `/end` returns `200` with `next_action = 'pause'` — scheduled pause only, never candidate-optional | Candidate presses Resume → `connecting` (next `/start`) |
| Done | `done` | `/end` returns `200` with `next_action = 'done'` | Terminal (no exit) |
| Error + Retry | `error` | `502`, network failure, or 3× `provider_busy` | Candidate presses Retry → `connecting` (retry counter reset) |
| Terminal — 403 | `terminal` | `403` from any endpoint | No exit — terminal; localized message: session authorization expired / closed |
| Terminal — absent phrase | `terminal` | `end_phrase` or `final_phrase` absent from `/start` response | No exit — terminal; DISTINCT localized message: "service temporarily unavailable — contact support"; MUST include support-contact affordance |
| Unsupported | — | SSR/client browser gate fires (Firefox, mobile UA, or viewport < 1024 px) | — (existing `/unsupported` page) |

**`continue` produces no screen:** when `next_action = 'continue'`, the client does not
enter `end_of_question` at all — it calls `POST /start` immediately and transitions
straight to `connecting`.

(Previously: the table's `End of Question` row entry trigger was "`/end` returns `200`...
and competencies remain," i.e. every non-final competency, and this note claimed the
`Pause / Resume` row was removed outright. Corrected per **D13**: the interstitial is
conditional on the server's scheduled-pause directive, not on "competencies remain" — that
part still holds. But the row removal claim was too broad and is narrowed here: only the
**between-competency** Pause/Resume row (`end_of_question → paused → end_of_question`) is
removed. The live pause row (now `Paused / Suspended`, above) is retained, with a single
entry edge from `live` and Resume returning unconditionally to `live`.)

No literal strings MAY appear in Vue component templates or scripts. Every user-visible
string MUST be an i18n key resolved at runtime.

#### Scenario: Consent screen shown on first load

- GIVEN a candidate navigating to `/interview/[token]` for the first time
- WHEN the page mounts (consent not yet accepted)
- THEN the consent screen is displayed with localized copy; the device check is NOT initiated

#### Scenario: Done screen shown when the server directs done

- GIVEN `/end` returns `200` with `next_action = 'done'`
- WHEN the client processes the response
- THEN the done screen is displayed with localized copy; no further API calls are made
  (Previously: detection relied on client-side comparison against a competency list/total
  that was never delivered to the browser.)

#### Scenario: Error screen shown on 502

- GIVEN `POST /start` returns `502`
- WHEN the client processes the response
- THEN the error+retry screen is shown with a localized error message and a retry control

#### Scenario: All copy served in project language

- GIVEN a candidate JWT with `language = 'en'`
- WHEN any interview screen is rendered
- THEN all UI labels, button text, status messages, and captions are in English

#### Scenario: A project with pause_every_n_competencies=null runs fully continuous

- GIVEN a project with `pause_every_n_competencies = null`
- WHEN the candidate completes every competency end to end
- THEN `end_of_question` is never entered — every `/end` returns `next_action = 'continue'`
  until the last, which returns `'done'` — zero candidate clicks occur between competencies

#### Scenario: A project with pause_every_n_competencies=3 pauses exactly on schedule (SA-04)

- GIVEN a project with `pause_every_n_competencies = 3` and 8 competencies
- WHEN the candidate completes competencies 1 through 8 in order
- THEN `end_of_question` (the SA-04 pause screen) is entered after the 3rd and 6th
  competency, and at no other point

#### Scenario: Exiting suspends the interview and never passes through end_of_question

- GIVEN a candidate on a `live` question
- WHEN the candidate confirms Exit
- THEN the provider session is ended, `POST /candidate/interview/suspend` is sent, and the state
  transitions to `paused`, never through `end_of_question`; pressing Resume re-issues `POST /start`
  for the same competency and returns to `live`

(Previously: this scenario said the microphone is muted and the provider session stays alive,
and that Resume unmutes it. Shipped behaviour (`useInterviewSession.pause()`, which stops the
provider and calls `/suspend`) is the suspend described here.)

#### Scenario: Pause from end_of_question is a no-op (edge removed)

- GIVEN the candidate is on the `end_of_question` (SA-04 pause) screen
- WHEN any residual Pause affordance is invoked
- THEN nothing happens — the `end_of_question → paused` edge no longer exists; the only
  way to leave `end_of_question` is Resume → `connecting`

#### Scenario: paused is its own screen and its resume control is always reachable

- GIVEN the candidate is in the `paused` state
- WHEN the screen is inspected
- THEN no avatar player is mounted (the pause ended the provider session) and the paused screen
  is rendered as its own branch, ahead of the live branch, with a reachable Resume control; the
  candidate is never left on a blank screen

(Previously: this scenario required the avatar player to remain mounted with the resume
control inside it. Pausing now ends the provider session, so the player is gone by design;
the unit test "renders the paused screen with NO avatar mounted" already pins the shipped
behaviour.)

---

### Requirement: Progress indicator reflects the server-reported competency total

The progress indicator MUST source its denominator from `total_competencies`
(`question_context`, `POST /start` addendum), never from a client-side competency array
or list. The numerator MUST be the 1-based position of the current competency
(`question_index + 1`, equal to the server-reported ended count plus one) and MUST never
exceed the denominator. The indicator MUST NOT name a competency.
(Previously: no statement about naming, and the example text was a bare `3/5`; the call
screen reads "Question 3 of 5" / "Domanda 3 di 5".)

#### Scenario: Progress reads N/N with the real total, never x/0
- GIVEN `/start` returns `question_context.total_competencies = 5` and `question_index = 2`
- WHEN the interview screen renders the progress indicator
- THEN it displays "Question 3 of 5" (it: "Domanda 3 di 5"); the denominator is never `0`

#### Scenario: Progress total is stable across the whole session
- GIVEN `total_competencies = 4` established on the session's first `/start`
- WHEN later competencies are reached
- THEN the denominator stays `4` throughout, never recomputed from a client-side list

---

### Requirement: Live per-question timer suspends and resumes across a mute-pause

The per-question timer's remaining time MUST be preserved across any suspension of the
live state (`live → paused`: the candidate's Exit, the tab-hidden guard or the network
guard): suspending stops the countdown; resuming (`paused → live`) continues it from the
same remaining value, never re-arming the full 5-minute limit.
(Previously: the requirement named only the candidate-initiated mute-pause and a Pause button.) A new competency's timer always starts from the full limit, keyed on the
`InterviewSession` id, independent of any pause activity on a prior competency.

(This corrects a severe defect: with the countdown owned by a component the pause
unmounted, every resume re-armed a full five minutes, so a candidate who paused
repeatedly could extend a single question indefinitely. Fixed and released as `frontend`
v0.6.4.)

#### Scenario: Suspending stops the countdown
- GIVEN a live question with 3 minutes 12 seconds remaining
- WHEN the candidate confirms Exit (or a guard suspends the interview)
- THEN the countdown stops advancing and holds at 3:12

#### Scenario: Resuming continues from the same remaining value
- GIVEN the countdown was suspended at 3:12 by an Exit or a guard
- WHEN the candidate presses Resume
- THEN the countdown resumes counting down from 3:12, not from the full 5-minute limit

#### Scenario: A new competency always starts from the full limit
- GIVEN the previous competency's timer was paused and resumed one or more times
- WHEN the candidate advances to a new competency (a new `InterviewSession` id)
- THEN its timer starts fresh at the full 5-minute limit, independent of the prior
  competency's pause history

#### Scenario: Repeated suspending cannot extend a question indefinitely (regression)
- GIVEN a candidate suspends and resumes a live question multiple times
- WHEN the cumulative live time (excluding paused intervals) reaches 5 minutes
- THEN the question times out with `ended_reason = 'timeout'` — suspending never grants
  additional time beyond the original 5-minute limit

---

## ADDED Requirements

Vocabulary: the "call screen" is the live interview screen rendered when the `candidateCallUi` flag is on. The "stage"
is its layout: the interviewer tile, the question band, the candidate's own tile and the side panel. The "interviewer
tile" is the existing avatar player layer. The "own tile" is the candidate's self-view. The "side panel" is the
`<aside>` with progress, time, Exit and the help link; below `xl` it is a strip under the question band. The "ring" is
the glowing border on a speaking tile.

### Requirement: The Live Interview Screen Is A Work Video Call Stage

With the `candidateCallUi` flag on, the system MUST render the `live` interview as a video-call stage made of exactly:
the interviewer tile, a written-question band directly under it, the candidate's own tile at the bottom right of the
interviewer tile, and the side panel. It MUST NOT render, in the live state, the header status pill, the live dock, a
Pause button or the question label ("D1", "Q1.2"). The interviewer tile MUST be the existing single keyed player layer
and MUST NOT be re-parented: one mount and one `stop()` per player across `connecting`, `live`, `paused` and a
competency handover. The layer MAY change only its classes (grid placement, `sr-only` when no `live` player exists).

#### Scenario: The stage is composed of the four parts

- GIVEN the flag is on and the session is `live`
- WHEN the live screen is inspected
- THEN it contains the interviewer tile, a question band under it, the own tile inside the interviewer tile's
  bottom-right corner, and a side panel; and it contains no element with `data-testid="interview-status"`, no
  `live-dock`, and no button named "Pause"/"Pausa"

#### Scenario: The player is mounted once across the lifecycle

- GIVEN the flag is on
- WHEN the session goes `connecting -> live -> paused -> connecting -> live`
- THEN each provider session is rendered by exactly one `AvatarPlayer` instance for its whole lifetime and is stopped
  exactly once; the layer element is the same DOM node before and after each change of screen

#### Scenario: A HeyGen handover still crossfades inside the interviewer tile

- GIVEN the flag is on and a HeyGen competency ends with `next_action = 'continue'`
- WHEN the incoming session paints
- THEN the outgoing and incoming players overlap inside the interviewer tile exactly as without the flag, and no
  skeleton, empty or panel state is shown in between

---

### Requirement: The Written Question Is Always Shown Under The Avatar

The call screen MUST show the interviewer's current question as text in a band directly under the interviewer tile, at
all times while the state is `live`. The text MUST be the latest transcript entry whose role is the avatar's, for the
`live` player. It MUST persist after the avatar stops speaking and be replaced only by the next avatar utterance. The band
MUST be a persistent `aria-live="polite"` `aria-atomic="true"` region labelled "Current question"/"Domanda corrente".
Before any avatar text has arrived, and at the start of each competency, the band MUST show the existing listen hint
(`interview.live.listen_hint`). The text arrives when the provider delivers the finished utterance, so the system does not
promise that text precedes speech.

#### Scenario: The question stays visible after the avatar finishes

- GIVEN the avatar has said "Raccontami di una volta in cui hai guidato un cambiamento" and stopped speaking
- WHEN the candidate starts answering
- THEN the same sentence remains visible in the band under the avatar until the next avatar utterance

#### Scenario: A follow-up replaces the question

- GIVEN a question is shown in the band
- WHEN the avatar delivers a follow-up utterance
- THEN the band shows the follow-up text only

#### Scenario: A new competency starts from the hint

- GIVEN the previous competency ended and the next one has a new `session_id`
- WHEN the new competency becomes the live one
- THEN the band shows the listen hint, not the previous competency's closing phrase, until the new avatar utterance arrives

#### Scenario: Before any text exists the hint fills the band

- GIVEN the session just became `live` and the avatar has not yet delivered text
- WHEN the screen is inspected
- THEN the band shows "Ascolta la domanda, poi rispondi a voce. Prenditi il tuo tempo." (en: "Listen to the question, then
  answer out loud. Take your time.")

---

### Requirement: Whose Turn It Is Shows As A Glowing Border On The Speaker's Tile

The call screen MUST show whose turn it is by lighting a ring on exactly one tile, or none. The signal is `avatar`,
`candidate` or `none`, derived from existing inputs: the live player's provider state (`speaking`), the avatar's remote
audio level, and the candidate's microphone level against `MIC_SPEAK_THRESHOLD` (0.04). The ring MUST be a white band
between two `--color-avatar-bg` bands (so its contrast does not depend on the brand colour or the video content), MUST be
accompanied by a non-colour cue (a microphone icon and visually hidden text on the tile's name chip), MUST NOT animate in a
loop, MUST change with a transition of at most 150 ms only when `prefers-reduced-motion: no-preference`, and MUST fall
back to a `Highlight` outline in forced-colours mode. The candidate's ring MUST be suppressed while the avatar is speaking
and for 500 ms afterwards. The signal MUST be `none` in every state other than `live`. The hidden text MUST NOT be a live
region.

#### Scenario: The interviewer speaks

- GIVEN the session is `live`
- WHEN the live player reports state `speaking`
- THEN the interviewer tile shows the ring and the own tile does not

#### Scenario: A provider that reports no speaking state still lights the ring

- GIVEN the live provider never emits `speaking` (the Tavus path)
- WHEN the avatar's remote audio level stays above the gate for 120 ms
- THEN the interviewer tile shows the ring, and it clears 600 ms after the audio stops

#### Scenario: The candidate answers

- GIVEN the avatar is silent and has been for more than 500 ms
- WHEN the candidate's microphone level stays above `MIC_SPEAK_THRESHOLD` for 200 ms
- THEN the own tile shows the ring and the interviewer tile does not, and the ring clears 800 ms after the level drops

#### Scenario: Speaker echo does not light the candidate

- GIVEN the avatar is speaking and the candidate's microphone hears it through speakers
- WHEN the microphone level exceeds the threshold
- THEN the own tile shows no ring

#### Scenario: Nobody is speaking

- GIVEN the session is `live`, the avatar is silent and the microphone is below the threshold
- WHEN the screen is inspected
- THEN neither tile shows the ring

#### Scenario: The ring is legible on any brand and not colour alone

- GIVEN the brand colours `#ffd400`, `#771aaf`, `#2f6fed` and no colour
- WHEN a tile is lit
- THEN the contrast of the white band against `--color-avatar-bg` is at least 3:1 (measured numerically), the name chip
  shows the microphone icon, and a screen reader exploring the tile reads "L'intervistatore sta parlando" / "Stai parlando"

#### Scenario: Reduced motion and forced colours

- GIVEN `prefers-reduced-motion: reduce`
- WHEN the ring turns on or off
- THEN it changes instantly with no transition; and under `forced-colors: active` the lit tile shows a `Highlight` outline

---

### Requirement: An Answer Ends By Silence Only

The call screen MUST NOT render any control with which the candidate declares an answer finished (no "I have finished
answering" / "Ho finito di rispondere" button, and no such i18n key in `it.json` or `en.json`). The end of an answer
remains the avatar's decision, signalled by its end phrase or Tavus tool call, or the 300 s question timer (`timeout`),
exactly as the existing `POST /end` flow defines; the client MUST NOT call `POST /end` in response to any candidate click
on the call screen other than the existing `timeout` path.

#### Scenario: No finish control exists

- GIVEN the flag is on and the session is `live`
- WHEN the interactive elements of the screen are listed
- THEN they are only Exit, the help link, and (while open) the dialog's two buttons; none declares the answer finished

#### Scenario: The avatar still ends the question

- GIVEN the candidate stops speaking and the avatar speaks its end phrase
- WHEN the provider reports completion
- THEN the client sends `POST /end` with `ended_reason = 'completed'` and follows `next_action` as before

---

### Requirement: The Candidate's Own Words Are Never Displayed

The call screen MUST NOT display the candidate's transcript, interim or final, in any element. Transcript entries with
the candidate's role MUST still be sent to `POST /candidate/interview/utterance` (the server needs them) and MUST NOT
replace, append to or appear beside the displayed question text.

#### Scenario: A candidate transcript never reaches the screen

- GIVEN the question band shows the avatar's question
- WHEN the provider emits a transcript entry with role `user`
- THEN the displayed text is unchanged, no element contains the candidate's words, and `POST /utterance` is still sent
  with `speaker = 'candidate'`

---

### Requirement: The Side Panel Shows Progress And Time, Never A Competency Name

While the state is `live` the call screen MUST show the side panel, always visible, containing in order: the progress text
"Question {n} of {total}" ("Domanda {n} di {total}") with a progress bar, the duration "{elapsed} / {total time}", the
per-question timer, Exit and the help link. `n` MUST be the 1-based position of the current competency and never exceed
`total`; `total` MUST be the server's `total_competencies`. The panel MUST NOT contain a competency code or name, whatever
the session data holds. Elapsed MUST count whole seconds only while the state is `live`. The total time MUST be
`total_competencies x 300 s`, presented as a maximum, with minutes not wrapped at 60. The duration MUST be hidden until the
server has stated a total. Below `xl` the panel MUST become a strip under the question band with the same content.

#### Scenario: Progress reads Question 2 of 5

- GIVEN `endedCompetencies = 1` and `totalCompetencies = 5`
- WHEN the panel renders
- THEN it shows "Domanda 2 di 5" and the bar reports `aria-valuenow = 1`, `aria-valuemax = 5`,
  `aria-valuetext = "Domanda 2 di 5"`

#### Scenario: No competency name or code, ever

- GIVEN the session store holds the current competency's code
- WHEN the panel and the whole live screen render
- THEN no competency name or code appears in any element, attribute or accessible name

#### Scenario: Elapsed counts live time only

- GIVEN 3 minutes 12 seconds of live time have elapsed and the interview is suspended for 10 minutes
- WHEN the candidate resumes
- THEN the elapsed value reads 03:12 and continues from there

#### Scenario: Total is a stated maximum

- GIVEN `totalCompetencies = 5`
- WHEN the duration renders
- THEN it reads "03:12 / 25:00" with the screen-reader text "03:12 trascorsi su un massimo di 25:00"; with 18
  competencies the total reads 90:00

#### Scenario: Reload restarts the elapsed counter

- GIVEN the candidate reloads the page mid-interview
- WHEN the interview resumes
- THEN elapsed restarts from 00:00 (documented limitation) while progress and the question timer follow the server and the
  existing re-arm rules

---

### Requirement: The Per-Question Timer Is A Counter

The call screen MUST present the per-question timer as a counter ("Time left for this question  04:12") in the side panel.
The limit MUST remain 300 s per competency session, owned by the page, and the counter MUST emit `tick` and `expired`
exactly as today. Its only threshold MUST be today's: in the last 10 seconds the value uses `--color-recording` and the
element is `aria-live="assertive"`. The call screen MUST NOT render a bar or ring timer, threshold bands, an amber state,
or any minimum, ideal or maximum answer length.

#### Scenario: The counter keeps the limit and the threshold

- GIVEN a competency session starts
- WHEN the panel renders
- THEN the counter reads 05:00 and counts down; at 00:10 its colour becomes `--color-recording` (at least 4.5:1 on the
  white panel) and it becomes assertive; at 00:00 the client sends `POST /end` with `ended_reason = 'timeout'`

#### Scenario: No answer-length bands

- GIVEN the call screen is live
- WHEN its timer elements are inspected
- THEN there is one `role="timer"` element and no element encoding a minimum, ideal or maximum answer length

---

### Requirement: The Candidate's Own Camera Is A Bottom-Right Tile

The call screen MUST show the candidate's own camera as a tile inside the bottom-right corner of the interviewer tile,
mirrored horizontally for display only. It MUST reuse the device-check `MediaStream` and MUST NOT call `getUserMedia`. It
MUST be muted, MUST have no controls, MUST NOT be focusable, MUST NOT receive pointer events, and MUST carry an accessible
name ("La tua fotocamera" / "Your camera"). If the stream has no live video track it MUST show a static "camera
unavailable" placeholder with the same name. Proctoring and snapshots MUST be unaffected by the display flip.

#### Scenario: The self-view shows the confirmed stream

- GIVEN the device check handed over a stream
- WHEN the call screen is live
- THEN the own tile plays that stream muted at the bottom right, mirrored, and no new `getUserMedia` call is made

#### Scenario: The self-view never takes focus

- GIVEN the call screen is live
- WHEN the candidate tabs through the page
- THEN focus never lands on the own tile and it never intercepts a click

#### Scenario: No camera track shows a placeholder

- GIVEN the stream contains only an ended video track
- WHEN the tile renders
- THEN a static placeholder with the name "Fotocamera non disponibile" / "Camera unavailable" is shown

---

### Requirement: Exit Suspends The Interview And Says It Can Be Resumed

The call screen MUST provide a button labelled "Esci, riprenderai dopo" ("Exit, you can resume later"). Activating it MUST
open a confirmation dialog stating that the interview will be suspended and that it can be resumed from the same question by
reopening the invitation link in this browser until a stated time, derived from the stored candidate token's `exp`
(the sentence omits the time when the stored session cannot be read). Confirming MUST call the existing `session.pause()`
(provider stopped, `POST /candidate/interview/suspend`, state `paused`) and show the suspended screen; it MUST NOT call the
exit redirect and MUST NOT clear the stored candidate session. The suspended screen MUST offer Resume (the existing
`session.resume()`, which re-issues `POST /start` for the same competency). Cancelling MUST close the dialog and return
focus to the Exit button. The button MUST be disabled, never hidden, while a handover is in flight. No new endpoint, event or
state is introduced.

#### Scenario: Exit asks first and cancel changes nothing

- GIVEN the call screen is live
- WHEN the candidate activates Exit and then cancels
- THEN the dialog closes, focus returns to the Exit button, no request is sent and the interview continues

#### Scenario: Confirming suspends through the existing mechanism

- GIVEN the dialog is open
- WHEN the candidate confirms
- THEN the provider session is stopped, `POST /candidate/interview/suspend` is sent once with the current `session_id`, the
  state becomes `paused`, and the suspended screen titled "Colloquio sospeso" is shown with focus on its heading

#### Scenario: The stored session survives an exit

- GIVEN the candidate confirmed Exit
- WHEN the browser storage is inspected
- THEN the candidate session is still stored and `exit_redirect_url` was not followed

#### Scenario: The deadline is the real one

- GIVEN the stored token expires at 16:42 local time
- WHEN the dialog and the suspended screen render in Italian
- THEN both state "entro le 16:42"; and when the stored session cannot be read the sentence is shown without a time

#### Scenario: Resume continues the same competency

- GIVEN the interview is suspended
- WHEN the candidate presses Resume, or reopens the same invitation link in the same browser before the deadline
- THEN `POST /start` resumes the same `in_corso` competency and the interview returns to `live` with the question timer
  continuing from its remaining value

#### Scenario: Exit during a handover is disabled, not hidden

- GIVEN a handover is in flight
- WHEN the panel renders
- THEN the Exit button is present, disabled and shows its loading state

#### Scenario: An automatic pause keeps its own wording

- GIVEN the tab-hidden guard pauses the interview
- WHEN the paused screen renders
- THEN it shows the existing paused copy and the tab-hidden warning, not the suspended wording

---

### Requirement: A Fixed Help Link Leads To Support

The call screen MUST show a link labelled "Problemi con audio o video?" ("Trouble with audio or video?") in the side panel,
always, after the Exit button in DOM order. Its target MUST come from `runtimeConfig.public.supportUrl`
(`NUXT_PUBLIC_SUPPORT_URL`); only `https:` and `mailto:` values MUST be accepted; an empty or any other value MUST fall back to
`mailto:support@beai.app`. An `https:` link MUST open in a new tab with `rel="noopener noreferrer"` and visually hidden text
"(opens in a new tab)"; a `mailto:` link MUST do neither. The same setting MUST feed every other support link in the
candidate app (the three in `InterviewSession.vue` and the one in `pages/interview/terminal.vue`).

#### Scenario: Default target

- GIVEN no support URL is configured
- WHEN the help link renders
- THEN it is a `mailto:support@beai.app` link without `target`

#### Scenario: A configured page opens safely

- GIVEN `supportUrl = "https://help.example.com/av"`
- WHEN the help link renders
- THEN it links there with `target="_blank"` and `rel="noopener noreferrer"`

#### Scenario: An unsafe value is ignored

- GIVEN `supportUrl = "javascript:alert(1)"` or `"http://insecure.example"`
- WHEN the help link renders
- THEN it falls back to `mailto:support@beai.app`

#### Scenario: Leaving the tab for more than a minute pauses, as it already does

- GIVEN the candidate opens the support page in another tab
- WHEN the interview tab stays hidden for more than 60 seconds
- THEN the existing tab-visibility guard pauses the interview and the paused screen explains why

---

### Requirement: The Call Screen Keeps Branding, Proctoring And The Embed Working

With the flag on, the organization's logo and primary colour MUST still apply through the existing canvas; the side panel and
the question band MUST be `bg-card` surfaces with card text tokens; no brand colour MUST be used for the ring. The proctoring
overlay MUST remain mounted exactly while the state is `live` and unmounted when paused, so snapshots and integrity events
behave as today. The integrity toast MUST appear at the top left under the header so it never covers the side panel. The
embed route (`/embed/{token}`), which renders the same component, MUST show the same stage, keep posting `question:changed`
and `completed`, and MUST NOT use viewport-height units in the stage, so its posted `resize` height is stable.

#### Scenario: Branding applies

- GIVEN an organization with logo and colour `#771aaf`
- WHEN the call screen is live
- THEN the logo plate and organization name appear in the header, the canvas is that colour, and the panel and question band
  are white card surfaces

#### Scenario: Proctoring continues across the stage change

- GIVEN the call screen is live
- WHEN snapshots and integrity events fire
- THEN `POST /snapshot` and `POST /integrity` are sent as without the flag, and the overlay unmounts on suspend

#### Scenario: The toast does not cover the panel

- GIVEN an integrity event fires
- WHEN the toast is shown
- THEN it is at the top left under the header and its box does not intersect the side panel

#### Scenario: The embed renders the same stage with a stable height

- GIVEN the flag is on and the interview is opened at `/embed/{token}`
- WHEN the stage mounts and the page posts `resize` twice
- THEN both heights are equal, the stage contains no `vh`, `dvh` or `svh` sizing, and `question:changed` is still posted

---

### Requirement: The Call Screen Is Accessible

The call screen, its exit dialog and the suspended screen MUST report zero WCAG 2.1 AA violations under axe in Chromium and
WebKit for a light and a dark brand colour. Focus order MUST be: question band, Exit, help link. Exit and help MUST be
operable by keyboard with targets of at least 44 px. The dialog MUST trap focus, close on Escape and restore focus. At a
competency boundary, and only then, focus MUST move to the question band (not while a dialog is open). The question band is
focusable (`tabindex="0"`) because it can scroll.

#### Scenario: Axe is clean in all three states

- GIVEN the flag is on
- WHEN axe runs on the live call screen, the open exit dialog and the suspended screen, under `#ffd400` and `#771aaf`
- THEN each reports zero violations, in Chromium and WebKit

#### Scenario: Keyboard-only use

- GIVEN the call screen is live
- WHEN the candidate presses Tab repeatedly
- THEN focus visits the question band, then Exit, then the help link, then leaves the screen; Enter on Exit opens the dialog;
  Escape closes it and returns focus to Exit

#### Scenario: Focus moves at a boundary only

- GIVEN a competency boundary is crossed and no dialog is open
- WHEN the new competency becomes live
- THEN focus is on the question band; and a later avatar utterance within the same competency does not move focus

---

### Requirement: The Call Screen Adapts To Desktop Widths And Keeps The Unsupported Gate

At viewport widths of 1280 px and above the stage MUST be two columns (tile column, 18 rem side panel) inside a container
no wider than 96 rem, and MUST NOT scroll vertically at 1280x800, 1440x900 or 1920x1080 in hosted mode. From 1024 px to
1279 px, and in any narrower embedded container down to 480 px, it MUST be one column with the panel as a strip. It MUST
NOT scroll horizontally at any width of 480 px or more. The SA-11 gate MUST be unchanged: below 1024 px (outside the embed)
the browser is redirected to `/unsupported`, and a mid-session narrowing flushes integrity and stops the provider first.

#### Scenario: No scroll at the supported sizes

- GIVEN the call screen is live in hosted mode
- WHEN the viewport is 1280x800, 1440x900 and 1920x1080
- THEN the document height does not exceed the viewport height

#### Scenario: Narrow desktop uses the strip

- GIVEN a viewport of 1100x800
- WHEN the call screen is live
- THEN the side panel is rendered as a strip under the question band and nothing overflows horizontally

#### Scenario: The mobile gate is unchanged

- GIVEN a mobile viewport outside the embed
- WHEN the candidate opens the interview
- THEN the unsupported-experience page is shown as before

---

### Requirement: The Call Screen Ships Behind The candidateCallUi Flag

The call screen MUST render only when `runtimeConfig.public.candidateCallUi === 'true'` (env
`NUXT_PUBLIC_CANDIDATE_CALL_UI`, default empty). Any other value, including absence, MUST render today's live screen
unchanged (header status pill, live dock, Pause). The flag MUST be read once when the component is set up, MUST apply to the
hosted route and the embed alike, and MUST NOT be settable by the candidate.

#### Scenario: Default is today's screen

- GIVEN no flag is configured
- WHEN the live screen renders
- THEN the status pill, the live dock and the Pause button are present and no call-stage element exists

#### Scenario: The flag turns the stage on

- GIVEN `NUXT_PUBLIC_CANDIDATE_CALL_UI=true`
- WHEN the live screen renders
- THEN the stage renders and the header status pill is absent

#### Scenario: A garbage value is off

- GIVEN the flag is `"1"` or `"yes"`
- WHEN the live screen renders
- THEN today's screen is shown

---

### Requirement: A Competency Boundary Is A Smooth Handover

When a competency ends with `next_action = 'continue'`, the interviewer's audio and video MUST be continuous for the
candidate through to the next competency's first utterance: the end phrase MUST play to completion without an audible cut,
there MUST be no unexpected stop of audio or video, no blank, frozen or skeleton frame, and the change MUST be a single
visual transition with no layout shift of the stage. The only permitted discontinuity is a documented fallback
presentation (a slow incoming session beyond its 10 s bound). This requirement is the acceptance test for whichever fix
Appendix A of `design.md` selects; it assumes no cause. Reserved task slot: `T-BUG-1`.

#### Scenario: The end phrase is not truncated

- GIVEN the avatar is speaking its end phrase at the end of the first competency
- WHEN the next competency is prepared
- THEN the end phrase finishes before the outgoing session is silenced or released

#### Scenario: No gap frame and no layout shift

- GIVEN the first competency ends with `continue`
- WHEN the second competency's avatar becomes visible
- THEN at every sampled frame between the two an avatar frame is visible (no skeleton, panel or frozen frame), the stage's
  boxes do not change size, and the question band does not jump

#### Scenario: Audio stays continuous

- GIVEN the same boundary
- WHEN the audio output is observed
- THEN there is no dropout of the interviewer's audio attributable to the handover, and at most one avatar is audible at any instant

---

### Requirement: No Greeting Is Spoken At A Competency Boundary

When a competency starts because the previous one ended with `next_action = 'continue'` in the same interview, the
interviewer MUST NOT speak a greeting, welcome or self-introduction. The opening composed for a non-first competency MUST be
the `next` variant and MUST contain no greeting phrase. Re-entry after a suspend (the `resume` variant) and a re-offered
competency (the `reoffer` variant) keep their own openings. This requirement assumes no cause. Reserved task slot: `T-BUG-2`.

#### Scenario: The second competency opens without a greeting

- GIVEN competency 1 ended with `continue`
- WHEN competency 2 starts
- THEN the composed opening is the `next` variant, contains none of the greeting phrases for the project language, and the
  first avatar utterance of competency 2 is not a greeting

#### Scenario: A resume after a suspend still re-orients the candidate

- GIVEN the interview was suspended and resumed
- WHEN the interview becomes live again
- THEN the `resume` opening is used, unchanged by this requirement

#### Scenario: The first competency still welcomes

- GIVEN a candidate starts the interview
- WHEN competency 1 starts
- THEN the `first` opening is used, unchanged by this requirement
