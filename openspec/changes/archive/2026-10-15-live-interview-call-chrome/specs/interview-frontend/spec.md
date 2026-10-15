# Delta for interview-frontend

Change: `live-interview-call-chrome`. Scope is the candidate `live` state only. Consent, device check, notices, the
suspended screen and every other screen keep their current header, white logo plate included.

## Reversals of the archived change `candidate-interview-call-ui` (2026-10-11), by name

This delta reverses two statements of that archived change. They are owner rulings of 2026-10-14, not accidents:

1. **Competency names in the side panel (REVERSED).** The archived requirement "The Side Panel Shows Progress And Time,
   Never A Competency Name" banned any competency name or code in the panel. That ban was an orchestrator synthesis, not an
   owner decision. The panel now names competencies in the "Percorso" storyboard. The ban is lifted for competency
   **names**; the progress denominator rule (server `total_competencies`) is kept.
2. **Min/ideal/max answer-length band (REVERSED).** The archived requirement "The Per-Question Timer Is A Counter"
   forbade any minimum, ideal or maximum answer length, because BEAI defines no ideal answer length (an unruled fairness
   question). The owner has ruled (D3, O1): the panel shows a **suggested** answer-length band. It is guidance only and
   never ends or limits an answer; the whole-interview time limit (`interview_max_seconds`) and its `timeout` path are
unchanged. (The archived requirement's "per-question timer" is in fact the whole-interview countdown; this delta names it
correctly.)

A third archived rule is modified by owner decision O4: "The Written Question Is Always Shown Under The Avatar". The
candidate may now turn the visible question text off (captions); the screen-reader live region always stays.

## ADDED Requirements

### Requirement: The Live Screen Has A Top Bar With Logo, Title, Clock And The Three Controls

While the state is `live`, the call screen MUST render a top bar containing, in DOM and reading order: the
organization's logo **without** the white plate (a bare logo; when the organization has no logo, the existing default brand
mark, also without plate), the assessment title, the elapsed clock, and exactly three controls: **Sottotitoli**
("Captions"), **Microfono** ("Microphone") and **Esci** ("Exit"). It MUST NOT render a camera toggle, a "Ripeti
domanda"/"Repeat question" control, a Pause button or any other control. The white logo plate MUST remain on every
non-live screen (consent, device check, notices, suspended and error screens).

The title MUST be the localized text "Colloquio di assessment · {role name}" (en: "Assessment interview · {role name}")
for a `standard` assessment, using the `role_name` of the interview outline; for a `potential` assessment it MUST be
"Colloquio di assessment · Potenziale" (en: "Assessment interview · Potential"). When a `standard` assessment has no
`role_name` (outline unavailable or `null`) the title MUST be "Colloquio di assessment" (en: "Assessment interview")
with no separator and no placeholder. The title text follows the candidate's UI language; the role name is shown in the
project language as returned.

The elapsed clock MUST show whole seconds of live time as `mm:ss` (minutes not wrapped at 60), counting only while the
state is `live`, with an accessible name that is not announced every second (it MUST NOT be a live region).

#### Scenario: The top bar is composed of exactly these parts

- GIVEN the session is `live`
- WHEN the top bar is inspected
- THEN it contains, in order, a logo, the title, the clock, and three buttons named "Sottotitoli", "Microfono" and
  "Esci"; and no button named "Camera"/"Fotocamera", "Ripeti domanda" or "Pausa"

#### Scenario: A standard assessment names the role

- GIVEN a `standard` project in Italian with `role_name = "Responsabile Vendite"`
- WHEN the top bar renders
- THEN the title reads "Colloquio di assessment · Responsabile Vendite"

#### Scenario: A potential assessment names its type

- GIVEN a `potential` assessment (`role_name = null`), in Italian and then in English
- WHEN the top bar renders
- THEN the title reads "Colloquio di assessment · Potenziale", then "Assessment interview · Potential"

#### Scenario: A missing role name degrades without a placeholder

- GIVEN a `standard` assessment whose outline has not loaded or has `role_name = null`
- WHEN the top bar renders
- THEN the title reads "Colloquio di assessment" with no "·" and no `null`/`undefined` text

#### Scenario: The logo has no plate while live and keeps it elsewhere

- GIVEN an organization with a logo
- WHEN the candidate views the consent page, then the live screen
- THEN the consent page shows the logo inside the white plate and the live screen shows the logo with no plate element

#### Scenario: A brand-coloured logo is not engineered around

- GIVEN a logo that is the same colour as the canvas
- WHEN the live screen renders
- THEN the logo is still rendered bare (no plate is added to compensate)

#### Scenario: The clock counts live time only

- GIVEN 3 minutes 12 seconds of live time have elapsed and the interview is suspended for 10 minutes
- WHEN the candidate resumes
- THEN the clock reads 03:12 and continues from there

#### Scenario: Reload restarts the clock

- GIVEN the candidate reloads the page mid-interview
- WHEN the interview resumes
- THEN the clock restarts from 00:00 (documented limitation)

### Requirement: The Microphone Toggle Mutes The Candidate Without Ending Or Timing Anything

The top bar's **Microfono** control MUST toggle the candidate's microphone between muted and unmuted by calling the
provider's existing microphone mute. Its state MUST be exposed programmatically (pressed/unpressed) and shown by an
icon **and** a text or visually-hidden label that does not rely on colour. The microphone MUST be unmuted when the
interview becomes `live` for the first time in a page load; the candidate's chosen state MUST persist across competency
handovers and a suspend/resume in the same page load, and MUST NOT persist across a reload.

Muting MUST NOT call `POST /end`, MUST NOT change the interview-time-remaining countdown, the clock or any timeout, MUST
NOT freeze or reset the answer timer, and the client MUST NOT itself interpret a muted microphone as the end of an answer.
While muted, a persistent
visible indication MUST remain on screen. The candidate's tile MUST NOT show the speaking ring while the microphone is
muted.

Mutes owned by the interview logic (the competency boundary and handover) take precedence: while one is in effect the
toggle MUST be disabled (never hidden) and show the muted state; when it ends, the microphone MUST return to the state
the candidate last chose, never silently unmuting a candidate who muted.

#### Scenario: Muting and unmuting call the provider

- GIVEN the session is `live` and the microphone is unmuted
- WHEN the candidate activates Microfono twice
- THEN the provider mute is applied, then removed, and the control reports pressed then unpressed

#### Scenario: Muting does not end or time anything

- GIVEN the candidate is answering
- WHEN the candidate mutes the microphone for 30 seconds
- THEN no `POST /end` is sent, the interview-time-remaining countdown and the answer timer keep counting (the answer timer
  is not frozen), and the clock keeps running

#### Scenario: The muted state is visible without colour

- GIVEN the microphone is muted
- WHEN the top bar is inspected
- THEN the control shows a muted icon and a text or hidden-text label, and a persistent muted indication is visible

#### Scenario: The ring is not lit while muted

- GIVEN the microphone is muted and the audio level would exceed `MIC_SPEAK_THRESHOLD`
- WHEN the screen is inspected
- THEN the candidate's tile shows no ring

#### Scenario: A forced mute wins and restores the candidate's choice

- GIVEN the candidate had left the microphone unmuted, and a competency boundary mutes it
- WHEN the boundary is in flight and then completes
- THEN during the boundary the control is present, disabled and shows muted, and afterwards it returns to unmuted

#### Scenario: A candidate's mute survives a boundary

- GIVEN the candidate muted the microphone before a competency boundary
- WHEN the boundary completes
- THEN the microphone is still muted and the control still reports pressed

#### Scenario: A reload resets the microphone

- GIVEN the candidate muted the microphone
- WHEN the page is reloaded and the interview resumes
- THEN the microphone is unmuted

### Requirement: The Captions Toggle Persists And Defaults To On

The top bar's **Sottotitoli** control MUST toggle whether the interviewer's question is shown as visible text (see "The
Written Question Is Shown As Captions Over The Avatar, Unless The Candidate Turns Them Off"). Its state MUST be exposed
programmatically (pressed/unpressed) and by an icon and a label that do not rely on colour. Captions MUST default to **on**
for a candidate with no stored preference. The preference MUST be stored in the browser and MUST be restored on reload and
on resume; when the stored value cannot be read or written, captions MUST be on and the toggle MUST still work for the
current page. The preference MUST NOT be sent to the server, MUST NOT contain personal data, and MUST NOT change how the
interview is conducted.

#### Scenario: First use shows captions

- GIVEN a candidate with no stored preference
- WHEN the interview becomes `live`
- THEN captions are on and the control reports pressed

#### Scenario: Turning them off survives a reload

- GIVEN captions are on
- WHEN the candidate turns them off and reloads the page
- THEN captions are off after the reload and the control reports unpressed

#### Scenario: Unreadable storage defaults to on and still toggles

- GIVEN browser storage throws on read and on write
- WHEN the interview becomes `live` and the candidate toggles captions
- THEN captions start on, toggle for the current page, and no error is shown

#### Scenario: No request is made

- GIVEN the candidate toggles captions
- WHEN the network is inspected
- THEN no request carries the preference

### Requirement: The Suggested Answer Length Is Derived From The Interview Budget And Never Enforced

The panel MAY show a suggested answer-length bar only when a budget exists. The per-answer **max** MUST be
`floor(interview_max_seconds / primary_total_all)` whole seconds, where `interview_max_seconds` is the value returned by
`POST /start` and `primary_total_all` is the value returned by the interview outline. The **min** MUST be 0.25 x max, and
the **ideal band** MUST span 0.375 x max to 0.75 x max, each rounded to the nearest whole second. When
`interview_max_seconds` or `primary_total_all` is missing, not a finite number, zero or negative, or when the computed max is
less than 1 second, there is no budget and the bar (and its labels) MUST NOT be rendered; no other part of the panel
changes. The client-side fallback seed of the interview countdown (300 s, used before the server states
`interview_max_seconds`) MUST NEVER be used as, or rendered as, a maximum or as an input of this budget.

The bar MUST be guidance only: it MUST NOT call `POST /end`, end, pause or shorten an answer, change any timeout, or alter
what the interviewer does. The whole-interview time limit and its `timeout` path are unchanged. Past the max, the bar MUST
stay full without any error or warning treatment. The min, ideal range and max MUST appear as real text labels (not
colour alone), formatted `mm:ss`, described as suggestions.

#### Scenario: The budget arithmetic

- GIVEN `interview_max_seconds = 1200` and `primary_total_all = 6`
- WHEN the budget is computed
- THEN max is 200 s, min is 50 s, and the ideal band is 75 s to 150 s, shown as 03:20, 00:50 and 01:15 to 02:30

#### Scenario: The max is floored and the rest rounded

- GIVEN `interview_max_seconds = 1210` and `primary_total_all = 6`
- WHEN the budget is computed
- THEN max is 201 s (floor of 201.67), min is 50 s, and the ideal band is 75 s to 151 s, shown as 03:21, 00:50 and 01:15
  to 02:31

#### Scenario: A missing or zero input hides the bar

- GIVEN `primary_total_all = 0`, or the outline has not loaded, or `interview_max_seconds` is missing
- WHEN the panel renders
- THEN no bar and no min/ideal/max label is rendered, and the answer timer, status chip, storyboard and duration still render

#### Scenario: A max below one second hides the bar

- GIVEN `interview_max_seconds = 5` and `primary_total_all = 10`
- WHEN the panel renders
- THEN no bar and no min/ideal/max label is rendered

#### Scenario: The fallback clock seed is never a maximum

- GIVEN the server has not yet stated `interview_max_seconds` and the countdown runs from its 300 s fallback seed
- WHEN the panel renders
- THEN no bar is rendered and "05:00" is not presented anywhere as a maximum

#### Scenario: The bar is only guidance

- GIVEN a budget of 200 s and the answer timer at 260 s
- WHEN the panel renders
- THEN the bar is full with no error styling, no `POST /end` is sent, and the interview-time-remaining countdown is unaffected

#### Scenario: Labels are text

- GIVEN a budget exists
- WHEN the bar is inspected
- THEN the min, ideal range and max values are present as text and the bar exposes the current answer time against the
  max to assistive technology

### Requirement: The Panel Shows The Named Path Of Competencies

The panel MUST show a "Percorso" ("Path") storyboard: an ordered list of the interview's competencies in outline order,
each showing the competency **name** from the interview outline (project language). Each item MUST convey its status by
an icon and text that do not rely on colour, and expose it to assistive technology:

- `done`: a check mark and the hidden text "Completata"/"Completed";
- `current`: the text "In corso · domanda {k} di {n}" (en: "In progress · question {k} of {n}") and `aria-current="step"`,
  where `n` is that competency's `primary_total` and `k` is `primary_index` (the number of distinct scripted primary
  questions asked so far in this competency session, from the latest `POST /utterance` response of the live session),
  clamped into 1..`n` when `primary_index` is a number and `n >= 1`; when `primary_index` is unknown (`null`, for example
  right after a resume or a new competency session and before the first utterance response) or `n` is 0 or unknown the
  text is "In corso" (en: "In progress") with no counts;
- `upcoming`: its 1-based ordinal;
- `retry`: a retry indicator and a text that tells the candidate the competency will be offered again.

Brand accents (`--color-primary-ink` on white surfaces) MAY colour the current and done items; colour MUST NOT be the
only carrier of status. A competency code MUST NOT be rendered as text. If the outline cannot be loaded the storyboard
MUST be omitted (no empty or failed frame) and the rest of the panel MUST still render; the outline MUST be requested at
most once at a time per page.

#### Scenario: The storyboard lists names in order with statuses

- GIVEN an outline of three competencies with statuses `done`, `current`, `upcoming` and names "Pensiero strategico",
  "Orientamento al risultato", "Collaborazione"
- WHEN the panel renders
- THEN it shows those three names in that order, the first with a check and "Completata", the second as the current
  step, the third with the number 3

#### Scenario: The current step shows the question counter

- GIVEN the current competency has `primary_total = 3` and the latest utterance response carried `primary_index = 2`
- WHEN the storyboard renders
- THEN the current item reads "In corso · domanda 2 di 3"

#### Scenario: The counter is clamped

- GIVEN `primary_total = 3` and `primary_index = 0`, then `primary_index = 5`
- WHEN the storyboard renders each time
- THEN the current item reads "domanda 1 di 3", then "domanda 3 di 3"

#### Scenario: A competency without primaries shows no counts

- GIVEN the current competency has `primary_total = 0`
- WHEN the storyboard renders
- THEN the current item reads "In corso" with no counts

#### Scenario: An unknown index shows no counts

- GIVEN the current competency has `primary_total = 3` and no utterance response has arrived for the live session (the
  index is `null`, for example right after a resume)
- WHEN the storyboard renders
- THEN the current item reads "In corso" with no counts, and after the next utterance response carrying `primary_index = 2`
  it reads "In corso · domanda 2 di 3"

#### Scenario: A verbatim re-ask does not advance the counter

- GIVEN the current item reads "domanda 2 di 3" and the interviewer repeats question 2 verbatim after a resume
- WHEN the next utterance response arrives (server `primary_index` still 2)
- THEN the current item still reads "domanda 2 di 3"

#### Scenario: A retry competency is distinguishable without colour

- GIVEN a competency with status `retry`
- WHEN the storyboard renders in forced-colours mode
- THEN its item shows a retry icon and text, and differs from the upcoming items by text

#### Scenario: Codes are not shown

- GIVEN the outline carries no code field, and the session store holds the current competency's code `COL`
- WHEN the panel and the whole live screen render
- THEN no competency code appears in any element text or accessible name

#### Scenario: An unavailable outline degrades quietly

- GIVEN the outline request fails
- WHEN the panel renders
- THEN no storyboard is rendered, no error is shown to the candidate, and the answer timer, duration and Exit still work

### Requirement: The Interviewer Name Has A Generic Fallback

Wherever the interviewer is named (the caption prefix and the interviewer tile's name chip), the name MUST be the
outline's `avatar_name`; when it is `null`, absent or blank the name MUST be "Intervistatore AI" (en: "AI interviewer"). The
name MUST be rendered as text by interpolation only (never as markup) and MUST NOT identify a provider.

#### Scenario: A configured name is used

- GIVEN `avatar_name = "Giulia"`
- WHEN a caption and the tile chip render
- THEN both show "Giulia"

#### Scenario: A missing name falls back

- GIVEN `avatar_name = null`, in Italian then in English
- WHEN a caption renders
- THEN the prefix reads "Intervistatore AI", then "AI interviewer"

#### Scenario: Markup is inert

- GIVEN `avatar_name = "<img src=x onerror=alert(1)>"` reaches the client
- WHEN the caption renders
- THEN the text is shown literally and no element is created from it

## MODIFIED Requirements

### Requirement: The Live Interview Screen Is A Work Video Call Stage

The system MUST render the `live` interview as a video-call stage made of exactly: the top bar, the interviewer tile
with the captions overlay at the bottom of its video, the candidate's own tile at the bottom right of the interviewer
tile, and the side panel. A separate question band under the interviewer tile is not required; if one is retained it is
a caption surface and is governed by the captions toggle. It MUST NOT render, in the live state, the header status pill,
the live dock, a Pause button or the question label ("D1", "Q1.2"). The interviewer tile MUST be the existing single keyed
player layer and MUST NOT be re-parented: one mount and one `stop()` per player across `connecting`, `live`, `paused` and a
competency handover. The layer MAY change only its classes (grid placement, `sr-only` when no `live` player exists).
(Previously: the stage was the interviewer tile, a written-question band directly under it, the own tile and the side
panel, with an empty header.)

#### Scenario: The stage is composed of its parts

- GIVEN the session is `live`
- WHEN the live screen is inspected
- THEN it contains the top bar, the interviewer tile with the captions overlay inside the bottom of its video, the own
  tile inside the interviewer tile's bottom-right corner, and the side panel; and it contains no element with
  `data-testid="interview-status"`, no `live-dock`, and no button named "Pause"/"Pausa"

#### Scenario: The player is mounted once across the lifecycle

- GIVEN an interview in progress
- WHEN the session goes `connecting -> live -> paused -> connecting -> live`
- THEN each provider session is rendered by exactly one `AvatarPlayer` instance for its whole lifetime and is stopped
  exactly once; the layer element is the same DOM node before and after each change of screen

#### Scenario: Adding the top bar does not re-parent the player

- GIVEN the layer is mounted in `connecting`
- WHEN the state becomes `live` and the top bar appears
- THEN the player layer is the same DOM node and has not been remounted

#### Scenario: A HeyGen handover still crossfades inside the interviewer tile

- GIVEN a HeyGen competency ends with `next_action = 'continue'`
- WHEN the incoming session paints
- THEN the outgoing and incoming players overlap inside the interviewer tile, and no
  skeleton, empty or panel state is shown in between

### Requirement: The Written Question Is Shown As Captions Over The Avatar, Unless The Candidate Turns Them Off

The call screen MUST show the interviewer's current question as visible text, as a captions overlay at the bottom of the
interviewer's video, while the state is `live` **and captions are on**. The text MUST be the latest transcript entry whose
role is the avatar's, for the `live` player. It MUST persist after the avatar stops speaking and be replaced only by the
next avatar utterance (captions show the latest finished utterance; they do not stream). Each caption MUST be prefixed by
the interviewer's name (see "The Interviewer Name Has A Generic Fallback") rendered in the brand colour on the dark video
(`--color-primary-light`), the name prefix MUST meet a contrast ratio of at least 4.5:1 against the overlay's own
backing, and the caption text MUST do so as well. The overlay MUST NOT cover the candidate's own tile.

**When captions are off, the system MUST NOT render ANY visible question text** (neither the overlay nor any question
band). Independently of the captions state, the screen MUST keep exactly one persistent `aria-live="polite"`
`aria-atomic="true"` region, labelled "Current question"/"Domanda corrente", mounted for the whole `live` state, always
carrying the current question text; when captions are off it is visually hidden (still exposed to assistive technology) and
when captions are on the visible overlay MAY be that same region, so the text is announced once, never twice. Before any
avatar text has arrived, and at the start of each competency, the caption MUST show the existing listen hint
(`interview.live.listen_hint`) and the live region MUST carry it. The text arrives when the provider delivers the finished
utterance, so the system does not promise that text precedes speech.
(Previously: the question was ALWAYS shown as text in a band directly under the avatar, with no way to hide it. Modified by
owner decision O4: captions off hides all visible question text; the screen-reader region is never removed.)

#### Scenario: The question stays visible after the avatar finishes

- GIVEN captions are on and the avatar has said "Raccontami di una volta in cui hai guidato un cambiamento" and stopped
  speaking
- WHEN the candidate starts answering
- THEN the same sentence remains visible in the overlay, prefixed by the interviewer's name, until the next avatar utterance

#### Scenario: A follow-up replaces the question

- GIVEN a question is shown in the overlay
- WHEN the avatar delivers a follow-up utterance
- THEN the overlay shows the follow-up text only

#### Scenario: A new competency starts from the hint

- GIVEN the previous competency ended and the next one has a new `session_id`
- WHEN the new competency becomes the live one
- THEN the overlay shows the listen hint, not the previous competency's closing phrase, until the new avatar utterance arrives

#### Scenario: Before any text exists the hint fills the overlay

- GIVEN the session just became `live`, captions are on, and the avatar has not yet delivered text
- WHEN the screen is inspected
- THEN the overlay shows "Ascolta la domanda, poi rispondi a voce. Prenditi il tuo tempo." (en: "Listen to the question, then
  answer out loud. Take your time.")

#### Scenario: The prefix is the interviewer's name in the brand colour

- GIVEN `avatar_name = "Giulia"` and the brand colour `#771aaf`
- WHEN a caption renders
- THEN it begins with "Giulia" coloured with the brand's light variant for dark backgrounds, and the contrast of the
  prefix and of the text against the overlay backing is at least 4.5:1

#### Scenario: Captions off hides every visible question text

- GIVEN a question has been delivered and captions are on
- WHEN the candidate turns captions off
- THEN no element on the screen shows the question text visibly (no overlay, no band), and the persistent live region is
  still mounted and still contains the question text

#### Scenario: A screen reader still receives questions with captions off

- GIVEN captions are off
- WHEN the avatar delivers a new question
- THEN the live region's text becomes the new question and is announced politely

#### Scenario: The question is announced once when captions are on

- GIVEN captions are on
- WHEN the avatar delivers a new question
- THEN exactly one live region on the screen carries the question text

#### Scenario: Turning captions back on shows the current question

- GIVEN captions are off and a question was delivered
- WHEN the candidate turns captions on
- THEN the overlay shows the latest question text immediately

#### Scenario: Hint and captions off

- GIVEN captions are off at the start of a competency
- WHEN the screen is inspected
- THEN no visible text shows the listen hint and the live region carries it

### Requirement: An Answer Ends By Silence Only

The call screen MUST NOT render any control with which the candidate declares an answer finished (no "I have finished
answering" / "Ho finito di rispondere" button, and no such i18n key in `it.json` or `en.json`). The end of an answer
remains the avatar's decision, signalled by its end phrase or Tavus tool call, or the interview time limit reaching zero (`timeout`),
exactly as the existing `POST /end` flow defines; the client MUST NOT call `POST /end` in response to any candidate click
on the call screen other than the existing `timeout` path. Toggling captions and toggling the microphone are never an end of an answer.
(Previously: the interactive elements were Exit, the help link and the dialog's buttons.)

#### Scenario: No finish control exists

- GIVEN the session is `live`
- WHEN the interactive elements of the screen are listed
- THEN they are only Sottotitoli, Microfono, Exit, the help link, and (while open) the dialog's two buttons; none declares the
  answer finished

#### Scenario: The new toggles never call POST /end

- GIVEN the candidate is answering
- WHEN the candidate toggles Sottotitoli and Microfono repeatedly
- THEN no `POST /end` is sent

#### Scenario: The avatar still ends the question

- GIVEN the candidate stops speaking and the avatar speaks its end phrase
- WHEN the provider reports completion
- THEN the client sends `POST /end` with `ended_reason = 'completed'` and follows `next_action` as before

### Requirement: The Side Panel Is The Interview Panel: Answer Time, Named Path And Duration

(Renamed from "The Side Panel Shows Progress And Time, Never A Competency Name". This reverses the archived
`candidate-interview-call-ui` ban on competency names; see "Reversals" above.)

While the state is `live` the call screen MUST show the side panel, titled "Intervista" ("Interview"), always visible,
containing in order:

1. **Answer time** ("Tempo di risposta"): the answer timer, the status chip and the suggested-length bar when a budget
   exists (see "The Interview Time Remaining Is A Counter, Distinct From The Answer Timer");
2. **Path** ("Percorso"): the competency progress text "Competenza {n} di {N}" (en: "Competency {n} of {N}") with its
   bar, and the named storyboard, which together state the 1-based position `n` of the current competency, never exceeding
   `N`, where `N` MUST be the server's `total_competencies`;
3. **Duration** ("Durata dell'intervista"): a progress bar of elapsed live time against `interview_max_seconds`, the text
   "{elapsed} / {max}", and, while time remains, BOTH the approximate sentence "Restano circa {N} minuti" (en: "About {N}
   minutes left") with `N = ceil(remaining seconds / 60)` AND, beside it, the exact interview-time-remaining countdown
   ("Tempo rimanente" / "Time remaining", `mm:ss`);
4. the help link.

Exit is NOT in the panel; it is in the top bar. The wording of the competency-level progress text ("Competenza n di N")
MUST be distinguishable from the in-competency "domanda k di n" counter. Elapsed MUST count whole seconds only while the
state is `live` and MUST be the same value as the top bar clock. The maximum MUST be `interview_max_seconds` (the server's
value), presented as a maximum with minutes not wrapped at 60, and MUST be hidden, with the duration bar, the remaining
sentence and the visible countdown, until the server has stated it (the countdown's enforcement element stays mounted; its
300 s fallback seed MUST NOT be presented to the candidate as a maximum or as remaining time). When elapsed exceeds the
maximum the bar MUST stay full, the values MUST be clamped, and the remaining text MUST NOT read "0 minutes". At `xl`
(1280 px) and above the panel MUST be exactly 22 rem wide (previously 18 rem) and sit beside the stage, full height of the
stage row; below `xl` the panel MUST become a strip under the stage with the same content.
(Previously: the panel held "Question n of total" with a bar, the duration against `total_competencies x 300 s`, the
per-question timer, Exit and the help link, was 18 rem wide, and MUST NOT contain any competency name or code.)

#### Scenario: The panel contains its sections in order

- GIVEN the session is `live` with an outline and `interview_max_seconds`
- WHEN the panel renders
- THEN its title is "Intervista" and it contains, in DOM order, Tempo di risposta, Percorso, Durata dell'intervista and the
  help link, and it contains no Exit button

#### Scenario: The panel is 22 rem wide on a desktop

- GIVEN a viewport of 1440x900
- WHEN the live screen renders
- THEN the panel is 22 rem (352 px at the default root size) wide, and the page has no vertical scroll

#### Scenario: Competency progress reads 2 of 5

- GIVEN `endedCompetencies = 1` and `totalCompetencies = 5`
- WHEN the panel renders
- THEN the competency progress text reads "Competenza 2 di 5" (en: "Competency 2 of 5"), the bar reports `aria-valuenow = 1`,
  `aria-valuemax = 5` and a `aria-valuetext` stating position 2 of 5, and the text is distinguishable from the
  "domanda k di n" counter

#### Scenario: Names appear, codes do not

- GIVEN the session store holds the current competency's code
- WHEN the panel and the whole live screen render
- THEN competency names from the outline appear, and no competency code appears in any element, attribute or accessible name

#### Scenario: The duration states a maximum from the server

- GIVEN `interview_max_seconds = 1200` and 3 minutes 12 seconds elapsed
- WHEN the duration renders
- THEN it reads "03:12 / 20:00" with the screen-reader text "03:12 trascorsi su un massimo di 20:00", the sentence "Restano
  circa 17 minuti" (`ceil(1008 / 60)`), and beside it the exact countdown "Tempo rimanente 16:48"; with
  `interview_max_seconds = 5400` the maximum reads 90:00

#### Scenario: The duration is hidden until the server states it

- GIVEN `interview_max_seconds` has not been returned
- WHEN the panel renders
- THEN no duration bar, maximum, remaining sentence or visible countdown is shown

#### Scenario: Past the maximum the values are clamped

- GIVEN elapsed live time exceeds `interview_max_seconds`
- WHEN the duration renders
- THEN the bar is full, the elapsed text is clamped to the maximum without error styling, and no "0 minutes" text is shown

#### Scenario: Elapsed matches the top bar clock

- GIVEN the clock reads 03:12
- WHEN the duration renders
- THEN its elapsed value is 03:12

#### Scenario: The panel is a strip on a narrow desktop

- GIVEN a viewport of 1100x800
- WHEN the live screen renders
- THEN the panel is rendered under the stage with the same sections and nothing overflows horizontally

### Requirement: The Interview Time Remaining Is A Counter, Distinct From The Answer Timer

The call screen MUST present two distinct timers:

- the **interview-time-remaining countdown**, the existing `InterviewTimer`, unchanged in behaviour: it counts down the WHOLE
  interview from `interview_max_seconds` (not a per-question or per-competency limit), owned by the page, emitting `tick`
  and `expired` exactly as today, labelled "Tempo rimanente" ("Time remaining") and shown in the panel's "Durata
  dell'intervista" section, with its only threshold unchanged: in the last 10 seconds the value uses `--color-recording` and
  the element is `aria-live="assertive"`. Its expiry still ends the interview through `POST /end` with
  `ended_reason = 'timeout'`. It is the only `role="timer"` element;
- the **answer timer**, in the panel's "Tempo di risposta" section: elapsed time counted from the moment the interviewer
  stops speaking, shown as `mm:ss`, which continues counting through the candidate's whole answer (a pause in speech does not
  stop or reset it) and resets to 00:00 only when the interviewer next starts speaking. It is derived from the existing
  speaker signal (`avatar`, `candidate`, `none`), counts only while the state is `live`, MUST NOT be frozen or reset by
  muting the microphone, and is never a live region (it MUST NOT be announced every second).

A status chip beside the answer timer MUST reflect the speaker signal with text (not colour alone): while the interviewer
speaks, "L'intervistatore sta parlando"; after it has finished and the candidate has not started, "In attesa della tua
risposta" ("Waiting for your answer"); while the candidate speaks, "Stai rispondendo". When the suggested-length bar exists
(see "The Suggested Answer Length ..."), it plots the answer timer against the budget. The limit, the threshold, `tick`,
`expired` and the `timeout` path are unchanged; the answer timer and the bar MUST NEVER emit `expired`, call `POST /end` or
alter the countdown. This reverses the archived ban on any minimum, ideal or maximum answer length (see "Reversals").
(Previously: "The Per-Question Timer Is A Counter": the call screen MUST NOT render a bar or ring timer, threshold bands, an
amber state, or any minimum, ideal or maximum answer length; there was one timer, described as a per-question limit though it
counted the whole interview, and no status chip.)

#### Scenario: The countdown keeps the limit and the threshold

- GIVEN `interview_max_seconds = 1200` and the interview becomes live
- WHEN the panel renders
- THEN the countdown reads 20:00 and counts down; at 00:10 its colour becomes `--color-recording` (at least 4.5:1 on the
  white panel) and it becomes assertive; at 00:00 the client sends `POST /end` with `ended_reason = 'timeout'`

#### Scenario: A competency boundary does not restart the countdown

- GIVEN 5 minutes of a 20-minute interview have elapsed and the next competency starts
- WHEN the panel renders
- THEN the countdown reads about 15:00 and keeps counting down from there

#### Scenario: Exactly one element has the timer role

- GIVEN the call screen is live
- WHEN its elements are inspected
- THEN exactly one element has `role="timer"` (the interview-time-remaining countdown) and the answer timer is not a live
  region

#### Scenario: The answer timer starts when the interviewer stops

- GIVEN the interviewer has just stopped speaking
- WHEN 12 seconds pass with the candidate silent
- THEN the answer timer reads 00:12 and the chip reads "In attesa della tua risposta"

#### Scenario: The answer timer continues through the answer

- GIVEN the interviewer stopped speaking 12 seconds ago and the candidate starts speaking
- WHEN the candidate speaks until the timer reads 00:40, with a 3-second pause in speech along the way
- THEN the timer never reset or stopped, and the chip read "Stai rispondendo" while the candidate spoke

#### Scenario: Muting does not freeze the answer timer

- GIVEN the candidate is answering and the answer timer reads 00:20
- WHEN the candidate mutes the microphone for 10 seconds
- THEN the answer timer reads 00:30 and the countdown has also advanced by 10 seconds

#### Scenario: The chip follows the speaker

- GIVEN the answer timer is running
- WHEN the candidate starts speaking, then the interviewer starts speaking
- THEN the chip reads "Stai rispondendo", then "L'intervistatore sta parlando", and the answer timer resets to 00:00 when the
  interviewer starts

#### Scenario: The answer timer never ends an answer

- GIVEN the answer timer exceeds the suggested maximum
- WHEN the panel renders
- THEN no `POST /end` is sent and the countdown continues unchanged

#### Scenario: The answer timer stops outside live

- GIVEN the interview is suspended
- WHEN the candidate resumes
- THEN the answer timer does not advance while suspended

#### Scenario: Reduced motion

- GIVEN `prefers-reduced-motion: reduce`
- WHEN the bar's fill changes
- THEN it changes without a transition

### Requirement: The Candidate's Own Camera Is A Bottom-Right Tile

The call screen MUST show the candidate's own camera as a tile inside the bottom-right corner of the interviewer tile,
mirrored horizontally for display only. It MUST reuse the device-check `MediaStream` and MUST NOT call `getUserMedia`. It
MUST be muted, MUST have no controls, MUST NOT be focusable, MUST NOT receive pointer events, and MUST carry an accessible
name ("La tua fotocamera" / "Your camera"). If the stream has no live video track it MUST show a static "camera
unavailable" placeholder with the same name. Proctoring and snapshots MUST be unaffected by the display flip. The tile MUST
carry a name chip showing the candidate's own name, taken from the interview outline's `candidate_name` (not from
`GET /candidate/session`), on a semi-transparent black background with white text, legible over any video content (contrast
of at least 4.5:1 against a white video frame); when the name is missing or blank, or the outline could not be loaded, the
chip MUST read "Tu" (en: "You"). The name MUST be rendered as text only and the chip MUST remain non-interactive.
(Previously: the chip, where present, always read "Tu"/"You".)

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

#### Scenario: The chip shows the candidate's name

- GIVEN the outline reports `candidate_name = "Marco Rossi"`
- WHEN the own tile renders
- THEN its chip reads "Marco Rossi" in white on a semi-transparent black background

#### Scenario: A missing name falls back

- GIVEN the outline reports `candidate_name = null`, in Italian then in English
- WHEN the own tile renders
- THEN the chip reads "Tu", then "You"

#### Scenario: A failed outline falls back to the generic label

- GIVEN the outline request fails
- WHEN the own tile renders
- THEN the chip reads "Tu" (en: "You"), no error is shown, and the self-view still works

#### Scenario: The chip is legible over a bright video

- GIVEN a white video frame behind the chip
- WHEN the contrast of the chip text against its effective background is measured
- THEN it is at least 4.5:1

#### Scenario: Markup in the name is inert

- GIVEN `candidate_name = "<b>x</b>"`
- WHEN the chip renders
- THEN the text is shown literally and no element is created from it

### Requirement: Exit Suspends The Interview And Says It Can Be Resumed

The call screen MUST provide an **Esci** ("Exit") button in the top bar, the third and last of its controls. The button's
visible label is "Esci"; its accessible name MUST contain the visible label and MUST still tell the candidate that the
interview can be resumed ("Esci, riprenderai dopo" / "Exit, you can resume later"). Activating it MUST
open a confirmation dialog stating that the interview will be suspended and that it can be resumed from the same question by
reopening the invitation link in this browser until a stated time, derived from the stored candidate token's `exp`
(the sentence omits the time when the stored session cannot be read). Confirming MUST call the existing `session.pause()`
(provider stopped, `POST /candidate/interview/suspend`, state `paused`) and show the suspended screen; it MUST NOT call the
exit redirect and MUST NOT clear the stored candidate session. The suspended screen MUST offer Resume (the existing
`session.resume()`, which re-issues `POST /start` for the same competency). Cancelling MUST close the dialog and return
focus to the Exit button. The button MUST be disabled, never hidden, while a handover is in flight. No new endpoint, event or
state is introduced.
(Previously: the button lived in the side panel and its visible label was "Esci, riprenderai dopo"; behaviour is unchanged.)

#### Scenario: Exit asks first and cancel changes nothing

- GIVEN the call screen is live
- WHEN the candidate activates Exit and then cancels
- THEN the dialog closes, focus returns to the Exit button in the top bar, no request is sent and the interview continues

#### Scenario: Exit lives in the top bar

- GIVEN the call screen is live
- WHEN the side panel and the top bar are inspected
- THEN the Exit button is inside the top bar after Sottotitoli and Microfono, and the panel contains no Exit button

#### Scenario: The accessible name keeps the resume hint

- GIVEN the Exit button with the visible label "Esci"
- WHEN its accessible name is read
- THEN it contains "Esci" and tells the candidate that the interview can be resumed

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
- THEN `POST /start` resumes the same `in_corso` competency and the interview returns to `live` with the interview-time
  countdown continuing from its remaining value

#### Scenario: Exit during a handover is disabled, not hidden

- GIVEN a handover is in flight
- WHEN the top bar renders
- THEN the Exit button is present, disabled and shows its loading state

#### Scenario: An automatic pause keeps its own wording

- GIVEN the tab-hidden guard pauses the interview
- WHEN the paused screen renders
- THEN it shows the existing paused copy and the tab-hidden warning, not the suspended wording

### Requirement: A Fixed Help Link Leads To Support

The call screen MUST show a link labelled "Problemi con audio o video?" ("Trouble with audio or video?") at the bottom of
the side panel, always, after every other focusable control of the live screen in DOM order. Its target MUST come from
`runtimeConfig.public.supportUrl`
(`NUXT_PUBLIC_SUPPORT_URL`); only `https:` and `mailto:` values MUST be accepted; an empty or any other value MUST fall back to
`mailto:support@beai.app`. An `https:` link MUST open in a new tab with `rel="noopener noreferrer"` and visually hidden text
"(opens in a new tab)"; a `mailto:` link MUST do neither. The same setting MUST feed every other support link in the
candidate app (the three in `InterviewSession.vue` and the one in `pages/interview/terminal.vue`).
(Previously: the link was "after the Exit button in DOM order" in a panel that held Exit.)

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

#### Scenario: The help link is last in the panel and in focus order

- GIVEN the call screen is live
- WHEN the DOM order of the focusable elements is read
- THEN the help link comes after the top bar controls and after every other focusable element of the stage

#### Scenario: Leaving the tab for more than a minute pauses, as it already does

- GIVEN the candidate opens the support page in another tab
- WHEN the interview tab stays hidden for more than 60 seconds
- THEN the existing tab-visibility guard pauses the interview and the paused screen explains why

### Requirement: The Call Screen Keeps Branding, Proctoring And The Embed Working

The organization's logo and primary colour MUST still apply through the existing canvas: the canvas is the primary
colour, the logo is shown in the top bar **without** the white plate while live (the plate remains on every non-live
screen), the organization's name stays available to assistive technology as the logo's accessible name, and the side panel
and any caption backing MUST use the existing surface tokens (white `bg-card` panel; a dark backing for captions); brand accents
use `--color-primary-ink` on white and `--color-primary-light` on the video; no brand colour MUST be used for the ring. The proctoring
overlay MUST remain mounted exactly while the state is `live` and unmounted when paused, so snapshots and integrity events
behave as today. The integrity toast MUST appear at the top left under the top bar so it never covers the side panel or the
top bar controls. The embed route (`/embed/{token}`), which renders the same component, MUST show the same stage, keep
posting `question:changed` and `completed`, and MUST NOT use viewport-height units in the stage, so its posted `resize`
height is stable.
(Previously: the logo plate and organization name appeared in the header while live, and the toast sat under the empty
header.)

#### Scenario: Branding applies

- GIVEN an organization with logo and colour `#771aaf`
- WHEN the call screen is live
- THEN the bare logo appears in the top bar with the organization's name as its accessible name, the canvas is that colour, and the
  panel is a white card surface

#### Scenario: Proctoring continues across the stage change

- GIVEN the call screen is live
- WHEN snapshots and integrity events fire
- THEN `POST /snapshot` and `POST /integrity` are sent unchanged, and the overlay unmounts on suspend

#### Scenario: The toast does not cover the panel or the top bar

- GIVEN an integrity event fires
- WHEN the toast is shown
- THEN it is at the top left under the top bar and its box intersects neither the top bar controls nor the side panel

#### Scenario: The embed renders the same stage with a stable height

- GIVEN the interview is opened at `/embed/{token}`
- WHEN the stage mounts and the page posts `resize` twice
- THEN both heights are equal, the stage (including the top bar) contains no `vh`, `dvh` or `svh` sizing, and
  `question:changed` is still posted

#### Scenario: Axe passes under a light and a dark brand with the bare logo

- GIVEN the brand colours `#ffd400` and `#771aaf`
- WHEN axe runs on the live screen
- THEN it reports zero violations, including for the top bar text and controls on the canvas

### Requirement: The Call Screen Is Accessible

The call screen, its exit dialog and the suspended screen MUST report zero WCAG 2.1 AA violations under axe in Chromium and
WebKit for a light and a dark brand colour. Focus order MUST be: Sottotitoli, Microfono, Esci, the visible caption surface
only if it is focusable (it is when it can scroll, `tabindex="0"`), then the help link; the persistent screen-reader live
region and the status chip are not tab stops. Sottotitoli, Microfono, Esci and the help link MUST be operable by keyboard
with targets of at least 44 px and visible focus indication. The dialog MUST trap focus, close on Escape and restore focus.
At a competency boundary, and only then, focus MUST move to the visible caption surface when captions are on and no dialog is
open; when captions are off, focus MUST NOT be moved (the live region announces the new question instead).
(Previously: the focus order was question band, Exit, help link; and at a boundary focus always moved to the question band.)

#### Scenario: Axe is clean in all three states

- GIVEN a candidate interview
- WHEN axe runs on the live call screen, the open exit dialog and the suspended screen, under `#ffd400` and `#771aaf`
- THEN each reports zero violations, in Chromium and WebKit

#### Scenario: Keyboard-only use

- GIVEN the call screen is live
- WHEN the candidate presses Tab repeatedly
- THEN focus visits Sottotitoli, then Microfono, then Esci, then the caption surface if it is focusable, then the help link,
  then leaves the screen; Space/Enter on Sottotitoli and Microfono toggle them; Enter on Esci opens the dialog; Escape
  closes it and returns focus to Esci

#### Scenario: Toggles keep focus and announce their state

- GIVEN focus is on Sottotitoli
- WHEN the candidate activates it
- THEN focus stays on the control and its pressed state changes for assistive technology

#### Scenario: Targets are large enough

- GIVEN the top bar controls and the help link
- WHEN their boxes are measured
- THEN each is at least 44 px in both dimensions

#### Scenario: Focus moves at a boundary only

- GIVEN a competency boundary is crossed, captions are on and no dialog is open
- WHEN the new competency becomes live
- THEN focus is on the caption surface; and a later avatar utterance within the same competency does not move focus

#### Scenario: A boundary with captions off moves no focus

- GIVEN captions are off and focus is on Microfono
- WHEN a competency boundary is crossed
- THEN focus stays on Microfono and the live region carries the new competency's opening text

### Requirement: Progress indicator reflects the server-reported competency total

The progress indicator MUST source its denominator from `total_competencies`
(`question_context`, `POST /start` addendum), never from a client-side competency array
or list, **including the interview outline's list of competencies**. The numerator MUST be the 1-based position of the
current competency (`question_index + 1`, equal to the server-reported ended count plus one) and MUST never
exceed the denominator. Its text MUST read "Competenza {n} di {N}" (en: "Competency {n} of {N}"), a wording distinct from the
in-competency "domanda k di n" counter. The indicator MAY name the current competency (the archived "MUST NOT name a competency" is
lifted for names, not codes, by this change; see "Reversals"); it MUST NOT render a competency code.
(Previously: the indicator MUST NOT name a competency; the call screen read "Question 3 of 5" / "Domanda 3 di 5".)

#### Scenario: Progress reads N/N with the real total, never x/0
- GIVEN `/start` returns `question_context.total_competencies = 5` and `question_index = 2`
- WHEN the interview screen renders the progress indicator
- THEN its text reads "Competenza 3 di 5", its numerator is 3 and its denominator is 5 (progress bar `aria-valuenow`/`aria-valuemax` consistent with them); the
  denominator is never `0`

#### Scenario: Progress total is stable across the whole session
- GIVEN `total_competencies = 4` established on the session's first `/start`
- WHEN later competencies are reached
- THEN the denominator stays `4` throughout, never recomputed from a client-side list

#### Scenario: The outline never drives the denominator
- GIVEN `total_competencies = 5` and an outline listing 4 entries
- WHEN the panel renders
- THEN the progress denominator is 5

#### Scenario: A competency name may be shown, a code never
- GIVEN the outline names the current competency "Collaborazione" with code `COL`
- WHEN the progress indicator and storyboard render
- THEN the name may appear and the code `COL` appears nowhere as text

## RENAMED Requirements

### Requirement: The Written Question Is Always Shown Under The Avatar → The Written Question Is Shown As Captions Over The Avatar, Unless The Candidate Turns Them Off

(Reason: the question is no longer unconditionally visible and no longer sits in a band under the tile; owner decision O4.)
(Migration: tests, docs and references to the old name update to the new name; the screen-reader live region keeps its
label "Current question"/"Domanda corrente".)

### Requirement: The Per-Question Timer Is A Counter → The Interview Time Remaining Is A Counter, Distinct From The Answer Timer

(Reason: the archived "per-question timer" was never per question; it counts down the whole interview from `interview_max_seconds`. The requirement now names it correctly and adds the separate answer timer.)
(Migration: tests, docs and references to the old name update to the new name; the countdown's behaviour, threshold, `tick`, `expired` and `timeout` path are unchanged.)

### Requirement: The Side Panel Shows Progress And Time, Never A Competency Name → The Side Panel Is The Interview Panel: Answer Time, Named Path And Duration

(Reason: the panel now names competencies and shows answer-time guidance; the old name states two rules that are reversed.)
(Migration: `call-ui-arch.spec.ts` no longer asserts that the panel names no competency; tests, docs and references update to the new name.)
