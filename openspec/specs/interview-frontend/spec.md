# Interview Frontend Specification

## Purpose

Defines the candidate-facing Nuxt 4 SSR interview application delivered by C7b:
browser support gate (SA-11), pre-join device check, live avatar interview loop
(per-competency sessions, proctoring collection, integrity/snapshot flush), provider
abstraction consuming the C7a contract, localized flow screens, and the Permissions-Policy
fix required to unblock camera/microphone access on the interview route.

One session = one competency question played in the fixed C4 `project_competencies.position`
order. Adaptivity (C8), BARS scoring (C9), webhook delivery (C10), and admin review (C11)
are explicitly out of scope.

---

## Non-Goals

- Adaptive question selection or AI follow-ups within a competency (C8)
- BARS scoring computation or display; `summarizeIntegrity()` trigger (C9)
- Outbound webhook delivery (C10)
- Backoffice / admin review dashboards (C11)
- GDPR media retention TTL — storage policy is a backend/ops concern (open decision #2)
- Firefox and mobile browsers are unsupported (not a non-goal — they MUST be gated; see SA-11)

---

## Requirements

### Requirement: Browser Support Gate (SA-11)

The system MUST prevent unsupported browsers from reaching the interview experience.
This gate is a **Firefox-denylist**: Firefox is explicitly rejected; Chrome, Edge, Opera,
and Safari are supported. Detection is split across two layers:

**Server layer** (`useRequestHeaders(['user-agent'])` — SSR only): detects Firefox UA (predicate:
`/Firefox\//i`) and known-mobile UA strings (predicate: `/Mobi|Android|iPhone|iPad/i`). Viewport
width is NOT server-detectable from HTTP headers — pass `Infinity` as the `width` argument to
`isSupportedBrowser` on the server side to skip the width check; only the UA predicates apply.

**Client layer** (`import.meta.client`): detects Firefox UA (`navigator.userAgent`) AND viewport
width `window.innerWidth < 1024` (per DESIGN.md §6: 768–1023 px = tablet = unsupported; ≥1024 px
= desktop). A reactive `window.resize` listener MUST be attached — **this listener lives INSIDE
`useInterviewSession`** (which owns the `provider` instance), NOT in `browser-gate.global.ts`
(a router guard with no provider access). The composable attaches and owns the resize listener.
On resize-triggered redirect, the composable MUST flush integrity (`sendBeacon`) + call
`provider.stop()` BEFORE navigating to `/unsupported`. The resize listener MUST be removed on
transition to `done`/`terminal`/`error` to avoid calling `provider.stop()` on an already-stopped
provider. `provider.stop()` errors during resize teardown are logged and suppressed (non-fatal).
The `browser-gate.global.ts` middleware handles only route-entry gating (SSR UA + client initial
load) — it never directly calls provider methods.

Both layers redirect to the existing `/unsupported` route. The middleware MUST NOT apply its
redirect to `/unsupported` itself (check: `to.path.endsWith('/unsupported')` to cover both
`/unsupported` and `/en/unsupported`, preventing a redirect loop on the non-default locale path).
The gate logic is extracted into the pure testable function
`isSupportedBrowser(ua: string, width: number): boolean` (see D5).

**iPadOS 13+ Safari note:** iPadOS 13+ sends a Mac-like desktop UA string by default
(`Macintosh; Intel Mac OS X`), not `iPad`. Server-side UA detection alone will NOT identify
iPadOS as a mobile/tablet device. The client-side `window.innerWidth < 1024` viewport check is
the authoritative tablet gate and correctly catches iPadOS devices whose UA passes the
server-side filter.

#### Scenario: Firefox redirected to /unsupported (SSR)

- GIVEN an HTTP request with a UA string matching `/Firefox\//i`
- WHEN Nuxt SSR processes any route other than `/unsupported`
- THEN the response is a redirect to `/unsupported`; the interview page is not rendered

#### Scenario: Mobile viewport redirected to /unsupported (client navigation)

- GIVEN a browser with `window.innerWidth` < 1024 px (mobile or tablet)
- WHEN the user navigates to `/interview/[token]`
- THEN the client-side middleware redirects to `/unsupported` before the page mounts

#### Scenario: Tablet viewport (900 px) redirected to /unsupported

- GIVEN a browser with `window.innerWidth` = 900 px (tablet range: 768–1023 px)
- WHEN the user navigates to `/interview/[token]`
- THEN `isSupportedBrowser(ua, 900)` returns `false` and the middleware redirects to `/unsupported`
  (DESIGN.md §6: 768–1023 px is tablet = unsupported)

#### Scenario: Mid-session viewport narrowing triggers gate

- GIVEN an active interview session on a supported desktop viewport (≥ 1024 px)
- WHEN the user resizes the browser window to `window.innerWidth` < 1024 px
- THEN the reactive resize listener flushes the integrity batch via `sendBeacon` and calls
  `provider.stop()` BEFORE redirecting to `/unsupported`; no integrity events are lost

#### Scenario: Supported desktop browser — Chrome — reaches interview page

- GIVEN a Chrome UA on a desktop viewport (width ≥ 1024 px)
- WHEN the user navigates to `/interview/[token]`
- THEN `isSupportedBrowser(ua, width)` returns `true`; the middleware does not redirect

#### Scenario: Supported desktop browser — Edge UA — passes gate

- GIVEN a UA string containing `Edg/` (Chromium-based Edge) on width ≥ 1024 px
- WHEN `isSupportedBrowser(ua, width)` is called
- THEN it returns `true` (Edge is supported; not matched by the Firefox denylist predicate)

#### Scenario: Supported desktop browser — Opera UA — passes gate

- GIVEN a UA string containing `OPR/` (Opera) on width ≥ 1024 px
- WHEN `isSupportedBrowser(ua, width)` is called
- THEN it returns `true` (Opera is supported)

#### Scenario: /unsupported route exempt from middleware redirect (default locale)

- GIVEN a Firefox user-agent
- WHEN the user is already on `/unsupported`
- THEN the middleware early-returns (`to.path.endsWith('/unsupported')`) and does not redirect

#### Scenario: /en/unsupported route exempt from middleware redirect (non-default locale)

- GIVEN a Firefox user-agent
- WHEN the user is already on `/en/unsupported` (i18n-prefixed path)
- THEN the middleware early-returns (`to.path.endsWith('/unsupported')`) and does not redirect
  (exact-match on `to.path === '/unsupported'` would NOT catch this path and cause a loop)

---

### Requirement: Permissions-Policy per-route override

The interview route MUST carry a `Permissions-Policy: camera=(self) microphone=(self)`
response header AND MUST retain all security headers set by the global `/**` rule. All other
routes MUST carry `Permissions-Policy: camera=(), microphone=(), geolocation=()`. This is
implemented as Nitro `routeRules` overrides.

**Nitro header override semantics (critical):** a more-specific route entry **replaces** (does
NOT merge with) less-specific entries. Therefore the interview-route entry MUST explicitly set
ALL headers that `/**` sets, or those headers are silently dropped on interview routes. The
four required headers (exact values matching `frontend/nuxt.config.ts`) are:
- `Permissions-Policy: camera=(self) microphone=(self)` (interview-specific override)
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`

The override MUST cover BOTH the default-locale path (no prefix, `strategy: prefix_except_default`,
`defaultLocale: 'it'`) AND all non-default-locale prefixed paths. With the current `locales`
configuration (`it`, `en`), the required patterns are `/interview/**` and `/en/interview/**`.
If additional locale codes are added, their `/[locale]/interview/**` patterns MUST be added too.

#### Scenario: Default-locale interview route allows camera and microphone

- GIVEN a GET request to `/interview/[token]` (Italian default, no prefix)
- WHEN the server responds
- THEN the `Permissions-Policy` response header equals `camera=(self) microphone=(self) geolocation=()`;
  `X-Frame-Options` equals `DENY`; `X-Content-Type-Options` equals `nosniff`;
  `Referrer-Policy` equals `strict-origin-when-cross-origin`

#### Scenario: Non-default-locale interview route allows camera and microphone

- GIVEN a GET request to `/en/interview/[token]` (English locale prefix)
- WHEN the server responds
- THEN the `Permissions-Policy` response header equals `camera=(self) microphone=(self) geolocation=()`;
  `X-Frame-Options` equals `DENY`; `X-Content-Type-Options` equals `nosniff`;
  `Referrer-Policy` equals `strict-origin-when-cross-origin`

#### Scenario: Interview routes include explicit geolocation=() directive

- GIVEN a GET request to `/interview/[token]` or `/en/interview/[token]`
- WHEN the server responds
- THEN the `Permissions-Policy` response header contains `geolocation=()` explicitly
  (Nitro replaces headers rather than merging them; an omitted directive is dropped
  entirely, reverting to the browser's permissive same-origin default for geolocation)

#### Scenario: Non-interview routes deny camera, microphone, and geolocation

- GIVEN a GET request to any route outside `/interview/**` or `/en/interview/**`
- WHEN the server responds
- THEN the `Permissions-Policy` response header contains `camera=()`, `microphone=()`,
  AND `geolocation=()`

---

### Requirement: Pre-join device check

Before entering the live interview, the system MUST present a device-check gate that:
(a) acquires exactly one live camera and microphone stream at a time, re-acquired via a
fresh `getUserMedia` call with `deviceId: { exact }` constraints whenever the candidate
switches camera or microphone, always stopping every track of the previous stream before
the replacement becomes active — never two live streams concurrently, never a camera left
hot after a switch,
(b) verifies the camera produces a live video track,
(c) verifies the microphone produces audio above an RMS threshold after the candidate speaks,
(d) after confirmation, hands the camera stream to the proctoring collector without issuing a
second `getUserMedia`. A candidate MUST NOT be able to proceed to fullscreen until both checks
pass. All device-check UI copy MUST be i18n-keyed.

#### Scenario: Both devices confirmed — proceed allowed

- GIVEN a supported browser with camera and microphone available
- WHEN the candidate completes the device check (video track live + mic RMS above threshold)
- THEN the "continue" control is enabled and the single shared camera stream is passed
  to the proctoring collector without a second `getUserMedia` call

#### Scenario: Camera unavailable — proceed blocked

- GIVEN `getUserMedia` throws `NotFoundError` or returns no video track
- WHEN the device check runs
- THEN the camera error state is shown; the proceed control remains disabled

#### Scenario: Microphone RMS never exceeds threshold — proceed blocked

- GIVEN a live video track is present but the candidate does not speak above threshold
- WHEN the device check timer expires without passing the mic test
- THEN the mic error state is shown and the proceed control remains disabled

#### Scenario: Device switch releases the previous stream before acquiring the replacement

- GIVEN an active device-check stream from a prior `getUserMedia` acquisition
- WHEN the candidate switches the camera or microphone via the device picker
- THEN every track of the previous stream reports `readyState !== 'live'` before the
  replacement stream's `getUserMedia` call resolves — release-before-replace is an
  ordering, not a race

#### Scenario: Switch fails mid-flight — nothing left hot, pickers stay usable

- GIVEN a device switch is in flight
- WHEN the replacement `getUserMedia` call rejects
- THEN nothing is left live (the previous stream was already released), an actionable
  error is shown, and the device pickers remain usable so the candidate can choose a
  different device instead of being stuck

#### Scenario: Stale deviceId on switch — OverconstrainedError ladder

- GIVEN the candidate selects a device whose id is no longer valid (e.g. unplugged
  between enumeration and selection)
- WHEN the switch's `getUserMedia` call rejects with `OverconstrainedError`
- THEN the system retries once with the constraint dropped (unconstrained), and on
  success reconciles the active selection to the device actually obtained

#### Scenario: Two rapid switches — only the latest stream survives

- GIVEN the candidate switches devices twice in rapid succession, before the first
  switch's `getUserMedia` call has resolved
- WHEN both acquisitions eventually resolve
- THEN only the stream from the LATEST switch becomes active; the superseded stream's
  tracks are stopped and it never becomes the active stream

#### Scenario: Unmount during a switch — the late-arriving stream is stopped, never activated

- GIVEN a device switch is in flight when the device-check screen unmounts
- WHEN the switch's `getUserMedia` call resolves after the unmount
- THEN the late-arriving stream is stopped immediately and never becomes the active
  stream — the only mechanism that stops a stream that did not exist when the unmount
  ran

#### Scenario: Microphone unavailable — recoverable, not a dead end

- GIVEN the acquired stream has no audio track, or `AudioContext` construction throws
- WHEN the device check evaluates the microphone
- THEN the system reports a `micUnavailable` state instead of leaving the check
  permanently unresolved; an explicit Retry (release then re-check) reopens it

---

### Requirement: Device preview geometry

The device-check camera preview MUST fill the full width of its content column and
render at the camera's MEASURED native aspect ratio — never a hardcoded ratio, never
cropped. The ratio MUST be clamped to `[3/4, 21/9]` so a portrait camera cannot produce
an overlong box. Before the ratio is known, the preview MUST hold a placeholder rather
than shift after first paint.

#### Scenario: Ratio unknown before metadata — no layout shift

- GIVEN the device-check screen has just mounted and no video track geometry is known yet
- WHEN the preview renders
- THEN a placeholder holds the expected space; once the track's geometry resolves, the
  common case renders without a visible shift

#### Scenario: Ratio changes on device switch — no crop

- GIVEN an active preview at one camera's aspect ratio
- WHEN the candidate switches to a camera with a different native aspect ratio
- THEN the preview updates to the new ratio without cropping the image

#### Scenario: Portrait camera — clamped, letterboxed not cropped

- GIVEN a camera whose native aspect ratio is narrower than `3/4` (e.g. a 9:16 portrait
  camera)
- WHEN the preview renders
- THEN the container is clamped to the `3/4` floor and the video letterboxes rather than
  being cropped or producing an overlong box

---

### Requirement: Live microphone level meter

The device-check screen MUST expose a live, numeric microphone level (not merely a
pass/fail boolean) with a non-visual equivalent for screen-reader users.

#### Scenario: Visible level moves as the candidate speaks

- GIVEN the device check is evaluating the microphone
- WHEN the candidate speaks
- THEN a visible level indicator moves in response, before the pass state is reached

#### Scenario: Screen reader gets one status announcement, not a continuous live region

- GIVEN a screen-reader user on the device-check screen
- WHEN the microphone level first crosses the pass threshold
- THEN exactly ONE status announcement fires (not a continuously updating live region,
  which would be a screen-reader denial of service), and a static instruction tells the
  candidate to speak

---

### Requirement: Camera and microphone device selection

The device-check screen MUST let the candidate select which camera and microphone to
use, populated from `enumerateDevices()` and kept current on the `devicechange` event.

#### Scenario: Device labels populate only post-grant

- GIVEN the candidate has not yet granted camera/microphone permission
- WHEN the device pickers are populated
- THEN entries with a blank platform label render a numbered fallback name (e.g.
  "Camera 1"), and remain selectable

#### Scenario: Picker list updates live on plug/unplug

- GIVEN the device-check screen is open
- WHEN a camera or microphone is connected or disconnected
- THEN the corresponding picker's option list updates without a page reload

#### Scenario: Denied permission still renders selectable fallback labels

- GIVEN the candidate has denied camera/microphone permission
- WHEN the device pickers render
- THEN they still show numbered fallback labels and remain selectable (selecting one
  does not itself grant permission, but the control is not disabled or hidden)

---

### Requirement: Device preference persistence

The system MUST persist the candidate's device selection in a cookie readable across
every interview locale path (the cookie MUST NOT be scoped to a path narrower than `/`,
since `strategy: 'prefix_except_default'` puts the English locale on
`/en/interview/...`, which a `/interview`-scoped cookie would not cover). A stored
device id that no longer exists MUST fall back to the system default, never a dead end,
and the stored preference MUST be rewritten to whatever was actually obtained.

#### Scenario: Returning candidate gets the same device

- GIVEN a candidate previously selected a specific camera and microphone
- WHEN they return to the device-check screen on a later visit (same locale path)
- THEN the same devices are pre-selected and acquired

#### Scenario: Stored device id gone — falls back to default, preference rewritten

- GIVEN a stored device id that is no longer present on the system
- WHEN the device check runs
- THEN it falls back to the system default device without dead-ending, and the stored
  preference is rewritten to the device actually obtained

#### Scenario: Preference honored regardless of locale path segment

- GIVEN a candidate has a stored device preference set while on one locale's interview
  path
- WHEN they open the interview on a different locale path (e.g. `/en/interview/...`
  after `/interview/...`)
- THEN the same stored preference is honored — the cookie is not scoped to a single
  locale's path segment

---

### Requirement: Instructional and permission-recovery copy

Every step of the device-check screen MUST carry instructional copy, and a denied
permission state MUST show a browser-neutral recovery path — no user-agent-specific
instructions. Zero literal strings: every string MUST be i18n-keyed in both `it` and
`en`.

#### Scenario: Denied-state recovery copy shown

- GIVEN the candidate has denied camera or microphone permission
- WHEN the device-check screen renders the failure state
- THEN browser-neutral recovery guidance is shown (anchored on the address-bar
  permission control every supported browser exposes), along with a Retry control — no
  failure state on this screen is terminal

#### Scenario: Full-screen i18n-key coverage across every state

- GIVEN any device-check state (default, error, confirmed)
- WHEN the rendered output is inspected
- THEN every visible string resolves through an i18n key present in both `it.json` and
  `en.json` — zero literal strings

---

### Requirement: Device-check accessibility

The device-check screen MUST be operable and understandable via assistive technology:
pickers MUST be labelled, the microphone meter MUST have a non-visual equivalent, and
all instructional copy MUST be reachable by a screen reader.

#### Scenario: Picker accessible name and selection announced on focus

- GIVEN a screen-reader user focuses a device picker
- WHEN the picker receives focus
- THEN its accessible name (e.g. "Camera" / "Microphone") and current selection are
  announced

#### Scenario: Zero axe violations across default/error/confirmed states

- GIVEN the device-check screen in its default, error, and confirmed states
- WHEN an automated WCAG 2.1 AA accessibility scan runs against each state
- THEN it reports zero violations, in both Chromium and WebKit

---

### Requirement: Continuous auto-advance directed by the server's `next_action`

Between competencies, the client MUST branch exclusively on the `next_action` field of
the `POST /end` response body (`interview-session` addendum) — it MUST NOT compute
"is this the last competency" or "is a pause due" itself from any client-side count or
list.

| `next_action` | Client behaviour |
|---|---|
| `continue` | `POST /start` is called immediately for the next competency. For HeyGen, no empty, skeleton, or panel screen is shown — the outgoing avatar stays visible until the incoming one is ready (see "Continuous avatar presence..."). For Tavus, the currently-shipped connecting presentation is unchanged. |
| `pause` | State transitions to `end_of_question` (rendered as the SA-04 pause screen). `POST /start` is NOT called until the candidate presses Resume. |
| `done` | State transitions to `done`. No further API calls are made. |

(Previously: the `continue` row read "No interstitial screen" without distinguishing
providers. HeyGen now additionally keeps the outgoing avatar visibly mounted through the
handover instead of relying on the between-competency connecting panel; Tavus is
unchanged.)

#### Scenario: next_action=continue — HeyGen shows a continuous avatar, immediate next /start

- GIVEN a HeyGen competency's `POST /end` returns `200` with `next_action = 'continue'`
- WHEN the client processes the response
- THEN `POST /start` is called immediately for the next competency and no empty,
  skeleton, or panel screen appears before the new avatar is ready

#### Scenario: next_action=pause — SA-04 screen shown, waits for Resume

- GIVEN `POST /end` returns `200` with `next_action = 'pause'`
- WHEN the client processes the response
- THEN the state machine transitions to `end_of_question` (the SA-04 pause screen);
  `POST /start` is NOT called until the candidate explicitly presses Resume

#### Scenario: next_action=done — done screen, no further calls

- GIVEN `POST /end` returns `200` with `next_action = 'done'`
- WHEN the client processes the response
- THEN the state machine transitions to `done`; no further `/start` call is made

#### Scenario: A missing next_action degrades to today's behaviour, not a crash

- GIVEN `POST /end` returns `200` with no `next_action` field (older `api` deploy, per the
  Dependencies ordering constraint)
- WHEN the client processes the response
- THEN it falls back to the pre-change `end_of_question` interstitial rather than
  throwing — deploying `frontend` ahead of `api` degrades gracefully

### Requirement: Skip control removed from the live interview UI

No Skip control MUST exist anywhere in the interview UI. The candidate's only two ways
to end a `live` question remain the avatar's own completion signal
(`ended_reason = 'completed'`) and the 5-minute per-question timer
(`ended_reason = 'timeout'`, ratified — unchanged).

#### Scenario: Skip control absent from the live interview screen
- GIVEN the live interview screen in any state
- WHEN its rendered controls are inspected
- THEN no Skip control exists, and `interview.live.skip` is absent from both `it.json`
  and `en.json`

---

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

### Requirement: Candidate is informed when a competency is re-offered

When a competency is re-offered after a bounded single re-offer (Decisions 4 & 5,
`interview-session` delta), the interview UI MUST render the `reoffer` opening variant
(`interview-conversation` delta) rather than the copy used for a first attempt, so the
candidate understands they are re-attempting this competency, not being asked something
new for the second time with no explanation.

#### Scenario: A re-offered competency shows re-attempt copy
- GIVEN a competency whose prior session ended in `error` and has now been reset to
  `pending` (re-offer)
- WHEN the candidate reaches the `connecting`/`live` screen for that competency
- THEN the rendered opening copy is the `reoffer` variant, distinct from first-attempt
  copy, in the candidate's project language (it/en minimum)

#### Scenario: A first-time competency never shows re-attempt copy
- GIVEN a competency with no prior `error` session
- WHEN the candidate reaches it
- THEN standard first/next/resume opening copy is shown, never the `reoffer` variant

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

### Requirement: Interview session loop — endpoint call order

The system MUST drive the per-competency interview session by calling the five C7a endpoints
in the order mandated by the backend contract:

1. `POST /start` — called on entering each competency; on `429 provider_busy` the client
   MUST retry with a 3-second backoff. Retry budget: **at most 3 total attempts** (1 initial
   call + 2 retries). If all 3 attempts return `429`, the retryable error+retry screen is shown.
   The retry counter resets when the user initiates a retry from the error screen (user-initiated
   retry = a fresh attempt sequence, not a continuation of the previous count). After 3 consecutive
   `429` failures the session remains `pending` (backend side); the user can retry from the error
   screen which resets the counter and starts a new attempt sequence.
   **Tavus continuation branch (single-session):** the client sends `live_conversation_id`
   (the conversation id it holds) in the `/start` body ONLY while it holds a live, joined Tavus
   handle; it sends nothing otherwise. When the `201` response contains a `continuation` object
   (`conversation_id`, `competency_code`) and null `provider_token`/`conversation_url`, the client
   MUST NOT create a provider handle, mount a player or transition to `connecting`; it moves the
   attribution cursor to the new `session_id` and then sends the boundary steering (an append, then the mandatory
   respond) over the EXISTING Daily data channel (see "Utterance Attribution Retargets At A Competency Boundary
   Without A Race Window"). A response with a fresh handle and no `continuation` takes today's
   path unchanged. A response with `continuation` but a missing field, or with `continuation` AND
   a non-null handle, is malformed and takes the existing retryable error screen. The client
   acts on the presence of `continuation` only; it never reads a feature flag.
2. `POST /utterance` — called best-effort on every provider transcript event; a `409`
   response MUST be silently dropped.
3. `POST /integrity` — called every `FLUSH_INTERVAL_MS` (10 000 ms); also flushed via
   `navigator.sendBeacon` on `pagehide`. The `pagehide` flush MUST use an **absolute URL**
   built from `runtimeConfig.public.apiBase` (to work cross-origin in production) and MUST
   send a `Blob` with `type: 'application/json'`.
4. `POST /snapshot` — called every `SNAPSHOT_INTERVAL_MS` (10 000 ms) and on snapshot
   integrity events; `413` and `422` responses MUST be logged but MUST NOT interrupt the
   session.
5. `POST /end` — called when the avatar signals completion or the per-question timer
   expires; `ended_reason` MUST be one of `{completed, timeout}`. The Skip control
   has been removed from the UI, so the candidate-facing client only ever produces
   `completed` or `timeout` — `skipped` remains a valid, accepted value for historical rows
   and non-candidate paths (Decision 1; unchanged on the backend). A `409` response from
   `POST /end` MUST be treated as a successful no-op: the session was already ended (e.g.
   avatar-completion and timer-expiry race). The client already holds the outcome supplied
   by the winning concurrent call's `200` response (including its `next_action`); the losing
   call's `409` requires no separate handling. This is DISTINCT from the `/utterance` `409`
   silent-drop: same treatment, different semantic.
   (Previously: `ended_reason` also included the candidate's own skip action; that trigger
   no longer exists.)

A `403` response from any endpoint MUST redirect the candidate to the terminal screen.
A `502` or unexpected error response MUST show the error+retry screen.

**Between-competency flow (server-directed):** after `POST /end` returns `200`, the client
branches exclusively on the response body's `next_action` — see the "Continuous
auto-advance directed by the server's `next_action`" requirement above for the full
behaviour. The client MUST NOT compute this decision itself.
(Previously: the candidate always saw the `end_of_question` screen after every competency
and had to press an explicit button before the next `/start` was called — an unconditional
interstitial with no relation to `pause_every_n_competencies`.)

**Next-step detection (server-directed, not client-computed):** `total_competencies`
(`/start`'s `question_context`) is used ONLY to render the progress indicator. Whether the
interview continues, pauses, or is done is determined EXCLUSIVELY by `next_action` on the
`/end` response — never re-derived from `question_index`/total comparisons on the client,
and never from an ordered competency list (none is, or will be, shipped to the browser —
see `interview-session`'s Decision 3).
(Previously: last-competency detection compared `question_index + 1` against a total
sourced from "the C6 candidate-session bootstrap" — a list that never shipped, which is
why `session.vue` carried an empty `competencies` array and every interview ended after one
competency.)

**Resume-on-remount guard:** before calling `POST /start` on re-mount (reconnect / browser
refresh), the composable checks an in-flight flag (`isResuming`). If `isResuming` is true,
the second re-mount is skipped (prevents concurrent double-start). When re-mounting,
`provider.stop()` is called on the existing provider instance before issuing a new `/start`.

#### Scenario: Provider busy on /start — retry with backoff (at most 3 total attempts)

- GIVEN the backend returns `429 { error: 'provider_busy' }` for `POST /start`
- WHEN the client receives the response
- THEN the client waits 3 seconds and retries; after 3 total attempts (1 initial + 2 retries)
  all returning `429`, the retryable error+retry screen is shown

#### Scenario: Provider busy — user-initiated retry resets attempt counter

- GIVEN the error+retry screen is shown after 3 consecutive `429` responses
- WHEN the user presses Retry
- THEN a new attempt sequence begins with attempt count reset to 0; up to 3 new total attempts

#### Scenario: /start succeeds — session loop begins

- GIVEN `POST /start` returns `201` with
  `{ session_id, provider, provider_token, question_context }` (HeyGen: `provider_token`)
  or `{ session_id, provider, conversation_url, question_context }` (Tavus: `conversation_url`)
- WHEN the client receives the response
- THEN the avatar player is initialized using the `provider` field and the corresponding
  `provider_token` or `conversation_url`; the timer, proctoring, and flush intervals start

#### Scenario: /utterance 409 — silently dropped

- GIVEN the backend returns `409` for `POST /utterance`
- WHEN the client receives the response
- THEN no error is shown; the session continues uninterrupted

#### Scenario: /snapshot 413 — logged, session continues

- GIVEN the backend returns `413` for `POST /snapshot`
- WHEN the client receives the response
- THEN the error is logged; no user-visible error; the snapshot interval continues

#### Scenario: /snapshot 422 — logged, session continues

- GIVEN the backend returns `422` for `POST /snapshot`
- WHEN the client receives the response
- THEN the error is logged; no user-visible error; the snapshot interval continues
  (same treatment as 413 — malformed payload, not a fatal session error)

#### Scenario: /end 409 — treated as successful no-op (race condition)

- GIVEN the avatar-completion signal and the per-question timer fire concurrently, causing
  two simultaneous calls to `POST /end`, and the second call returns `409`
- WHEN the client receives the `409` from `POST /end`
- THEN the state machine proceeds exactly as if `/end` returned `200`; no error screen
  is shown; no retry is triggered; the session transitions to `end_of_question` (or `done`
  if on the last competency); this is a successful no-op, not an error

#### Scenario: /end called with ended_reason=completed — transitions to end_of_question

- GIVEN the avatar signals completion via the end phrase
- WHEN `/end` is called with `ended_reason = 'completed'` and returns `200`
- THEN the state machine transitions to `end_of_question`; the End of Question screen is shown
  with progress; the candidate MUST explicitly initiate the next competency (no auto-advance);
  only on candidate action does the next `POST /start` get called

#### Scenario: end_of_question → next /start on candidate action

- GIVEN the `end_of_question` state is active (between competencies; at least one competency remains)
- WHEN the candidate presses the "Next" / "Continue" button
- THEN `POST /start` is called for the next competency; state transitions to `connecting`

#### Scenario: /end on last competency — done screen

- GIVEN the frontend has tracked that `question_index + 1 >= total_competency_count` and `POST /end` returns `200`
- WHEN the state machine evaluates the remaining competency list (from C6 bootstrap) and finds it exhausted
- THEN the done screen is shown directly; no `end_of_question` screen is interposed; no further `/start` call is made; `/end` returned `200` (not `203` — no such variant exists)

#### Scenario: Terminal 403 — redirect to done/terminal screen

- GIVEN the backend returns `403` from any interview endpoint (ParticipantStatusGuard)
- WHEN the client receives the response
- THEN the candidate is redirected to the terminal screen with a localized completion message

#### Scenario: A continuation response reuses the live Tavus conversation

- GIVEN `POST /start` returns `201` with `continuation: {conversation_id, competency_code}` and null handles
- WHEN the client processes the response
- THEN `createProvider` is not called again, no player is mounted, the state does not become `connecting`,
  the cursor moves to the new `session_id` before the boundary interaction is sent

#### Scenario: live_conversation_id is sent only while a handle is live

- GIVEN a joined Tavus handle, and separately a reload, a pause, a tab-hidden pause or a re-offer
- WHEN `POST /start` is called
- THEN the body carries `live_conversation_id` only in the first case; in the others the browser holds no
  live handle and the body has none

#### Scenario: A response without continuation takes today's path

- GIVEN a HeyGen interview, a Tavus first competency, a Tavus interview with the flag off, or a refused continuation
- WHEN `POST /start` returns a fresh handle and no `continuation`
- THEN the existing full initialization path (player init, timer, proctoring, flush intervals) runs unchanged,
  and the HeyGen suites pass unmodified

#### Scenario: A malformed continuation is a retryable error

- GIVEN a `continuation` missing `competency_code`, or present together with a non-null `conversation_url`
- WHEN the client validates the response
- THEN the retryable error screen is shown and no cursor move or send occurs

---

### Requirement: Provider abstraction — provider-neutral behavior

The system MUST implement a provider-neutral `InterviewProvider` interface. The active
provider MUST be selected from the `provider` field of the `/start` response — never
hardcoded. Both HeyGen and Tavus implementations MUST emit the same lifecycle states:
`connecting | ready | listening | speaking | stopped | complete`. Provider SDKs
(`@heygen/liveavatar-web-sdk`, `@daily-co/daily-js`) MUST be imported client-side only;
any SSR import of either SDK MUST be treated as a build error. Neither provider file MAY
import its SDK at module scope — the import MUST be a dynamic `await import()` reached
only from a function guarded by `import.meta.client`, so each SDK lands in its own lazy
chunk and a candidate on one provider never downloads a byte of the other's SDK.

For Tavus specifically, ONE joined Daily call object and its attached `<video>` element
MUST persist across every competency the live conversation covers when the server returns a
`continuation` — creating a new call object per competency in that case is a regression. The
context-steering capability is a narrow interface (`SupportsContextSteering`, guarded by
`canSteerContext()`) implemented by the Tavus provider only; the shared `InterviewProvider`
interface MUST NOT gain a method that HeyGen would have to stub, and the Tavus provider's
`sendBoundary(ticket)` MUST be the only call site of `sendAppMessage` in the application. HeyGen's
per-competency session and crossfade handover are UNCHANGED by this: HeyGen continues to
obtain a fresh `provider_token` and re-run its existing crossfade for every competency
exactly as before this change; nothing in this delta removes or narrows that path.

The `StartConfig` interface passed to `provider.start()` MUST include typed, named fields for
both provider connection values and completion phrases. The index signature `[k:string]:unknown`
is BANNED (TypeScript strict + exactOptionalPropertyTypes). Explicit API→StartConfig field
mapping: `provider_token` (HeyGen) → `sessionToken`; `conversation_url` (Tavus) →
`conversationUrl`; `question_context.end_phrase` → `endPhrase`; `question_context.final_phrase` → `finalPhrase`.
**`end_phrase` and `final_phrase` are NESTED inside `question_context` in the `/start` response —
they are NOT top-level fields.** Reading them from the top level of the response returns
`undefined`, which triggers the absent-phrase guard and transitions to `terminal`. The
implementation MUST destructure as `response.question_context.end_phrase` (not `response.end_phrase`).

HeyGen completion is detected when the avatar's transcription contains the backend-provided
`end_phrase` or `final_phrase` (accent/case/punctuation-insensitive containment match via
`matchesEndPhrase`). BOTH fields must be present and non-empty; if either field is absent from
the `/start` response, the HeyGen provider MUST emit an `error` event immediately and the state
machine MUST transition to `terminal` (not retryable — retrying `/start` would return the same
absent field; this indicates a version-mismatch or ops error). The terminal screen for
absent-phrase MUST display a distinct localized message: "service temporarily unavailable —
contact support", separate from the `403` terminal message, and MUST include a support-contact
affordance (link or email address).

**Tavus completion is detected primarily via the same spoken-phrase mechanism as HeyGen**: a
`conversation.utterance` app message whose `properties.role === 'replica'` (the avatar, never
the candidate) and whose `properties.speech` contains `end_phrase` or `final_phrase`
(accent/case/punctuation-insensitive, via the same `matchesEndPhrase`). Only the AVATAR's own
speech may end the interview — a candidate who reads the closing line aloud, or is simply
polite, MUST NOT be able to end their own assessment early. A `conversation.tool_call` event
with `name = 'end_interview'` MUST ALSO be honoured as a second, redundant completion path if
it is ever received — it is kept because it costs three lines and would be a more precise
signal the day Tavus registers the tool, but the spoken-phrase path MUST NOT depend on it: a
Tavus session that never receives a `tool_call` message MUST still complete on the spoken
end phrase, exactly as a HeyGen session does. Within a multi-competency conversation, the
spoken-phrase match at a competency's boundary is ONE of three inputs to an idempotent boundary
assertion (see "Mechanical Boundary Detection Does Not Depend On LLM Phrase Compliance" below); a
competency boundary is not the same event as the interview-ending completion signal, but both
share the same phrase-matching mechanism and the same paraphrase risk.

**Tavus media path (provider opacity):** the Tavus provider MUST join the conversation as a
Daily call object (`Daily.createCallObject({ audioSource: true, videoSource: false })`), NEVER
via `Daily.createFrame()` or any other mechanism that renders vendor UI into the page. The
call MUST join with the local video track off (`startVideoOff: true`) — the candidate's camera
belongs to the proctoring layer, which owns its own `getUserMedia` stream, and handing the same
device to the conversation SDK as well means two consumers of one camera, which several
browsers simply refuse. Remote media tracks MUST be attached directly to the interview page's
own `<video>` element (never to a vendor-rendered surface), and tracks belonging to the LOCAL
participant (the candidate's own microphone) MUST be ignored — piping the candidate's own audio
back into the avatar's element plays their voice back at them on a delay.

**Tavus microphone control:** `toggleMic()` MUST actually mute and unmute the candidate's
outbound audio via the call object's own audio control (`setLocalAudio`), reflecting the
call object's current state rather than an independently tracked flag that can drift from it.

**HeyGen SDK note (C7b delivered):** The correct SDK class is `LiveAvatarSession` from
`@heygen/liveavatar-web-sdk@0.0.18` (NOT `StreamingAvatar` from the legacy
`@heygen/streaming-avatar` package). Lifecycle: `new LiveAvatarSession(token)` → `start()` →
`attach(el)` → `stop()`. Event names are enum string values: `"avatar.transcription"`,
`"user.transcription"`. Mic: `startListening()` / `stopListening()`. Send: `message(text)`.
Barge-in: `interrupt()`.

#### Scenario: Provider selected from /start response

- GIVEN `/start` returns `{ provider: 'tavus', conversation_url: '...' }`
- WHEN the session starts
- THEN the Tavus provider implementation is initialized; HeyGen SDK is not loaded

#### Scenario: HeyGen completion via end_phrase match

- GIVEN a HeyGen session and `question_context.end_phrase = 'Let us move on.'`
- WHEN the avatar transcription contains "let us move on" (case/accent insensitive)
- THEN the `complete` state is emitted by the HeyGen provider

#### Scenario: HeyGen completion via final_phrase match

- GIVEN a HeyGen session and `question_context.final_phrase = 'Thank you for your time.'`
- WHEN the avatar transcription contains "thank you for your time" (last competency)
- THEN the `complete` state is emitted and `/end` is called with `ended_reason = 'completed'`

#### Scenario: Tavus completes on the avatar's spoken end phrase

- GIVEN a Tavus session and `question_context.end_phrase = 'Passiamo alla prossima domanda.'`
- WHEN a `conversation.utterance` app message arrives with `properties.role = 'replica'` and
  `properties.speech` containing the end phrase
- THEN the `complete` state is emitted — with no `conversation.tool_call` message involved at
  all, since the tool is never registered by Tavus

#### Scenario: Tavus does not complete on the candidate saying the phrase

- GIVEN a Tavus session with a configured end/final phrase
- WHEN a `conversation.utterance` app message arrives with `properties.role = 'user'`
  (the candidate) containing that phrase
- THEN no `complete` state is emitted

#### Scenario: Tavus still honours the tool_call path if it ever arrives

- GIVEN a Tavus session
- WHEN a `conversation.tool_call` event is received with `name = 'end_interview'`
- THEN the `complete` state is emitted and `/end` is called with `ended_reason = 'completed'`
  — a second, redundant path, not the primary one

#### Scenario: The Tavus media path renders no vendor iframe

- GIVEN a mount element containing the page's own `<video>` element
- WHEN a Tavus session starts and joins the call
- THEN `mount.querySelector('iframe')` is null — no vendor-branded surface is ever inserted

#### Scenario: Tavus joins with the camera off

- WHEN a Tavus session starts
- THEN the call object's `join()` is invoked with `startVideoOff: true` — the candidate's
  camera stream is never handed to the conversation SDK

#### Scenario: Remote tracks attach to the page's own video element

- GIVEN a Tavus session has started
- WHEN a remote (non-local) track arrives via `track-started`
- THEN the page's own `<video>` element's `srcObject` carries that track

#### Scenario: The candidate's own microphone track is never attached

- GIVEN a Tavus session has started
- WHEN a track arrives via `track-started` for the LOCAL participant
- THEN the page's `<video>` element's `srcObject` is not set from it

#### Scenario: toggleMic actually mutes and unmutes the Tavus call

- GIVEN an active Tavus session with the microphone on
- WHEN `toggleMic()` is called
- THEN the call object's audio control is invoked to turn the microphone off, and calling it
  again turns it back on

#### Scenario: SSR build succeeds without provider SDKs

- GIVEN the Nuxt SSR build process executes
- WHEN both provider implementations are present in the source tree
- THEN the build completes without importing `@heygen/liveavatar-web-sdk` or
  `@daily-co/daily-js` in the server bundle

#### Scenario: A second competency within a live Tavus conversation reuses the existing call object

- GIVEN an active Tavus call object already joined for competency CSF
- WHEN `/start` for INN returns a `continuation`
- THEN no new `Daily.createCallObject()` call is made and no new `<video>` element attachment
  occurs; across three competencies `createProvider` is called once and the number of mounted players never exceeds one

#### Scenario: HeyGen never exposes a context-steering method

- GIVEN the HeyGen provider
- WHEN `canSteerContext(provider)` is evaluated
- THEN it is false, and `HeyGenProvider` has no `sendBoundary` stub

#### Scenario: HeyGen's per-competency session and crossfade are unaffected

- GIVEN a HeyGen interview advancing from one competency to the next
- WHEN the transition occurs
- THEN a fresh `provider_token` is obtained and the existing crossfade handover runs exactly
  as before this change — HeyGen never reuses a session across competencies

---

### Requirement: Provider opacity — the candidate cannot learn which service is behind the face

Nothing in the shipped product MUST name a specific avatar provider (`HeyGen`,
`LiveAvatar`, `Tavus`, `Daily`/`daily.co`, or `LiveKit`) anywhere a candidate
can read it: not a rendered UI string, not an i18n locale entry, not an error
message surfaced to the candidate, not a code comment inside a candidate-facing
component (a comment ships in nothing rendered, but a developer copying a
nearby line does), and not a DOM element the application itself creates (its id,
class, or attributes).

This is a scoped guarantee, not an absolute one: the provider SDK executes in
the candidate's own browser, so a candidate who opens devtools can still see a
network host such as `daily.co`, a global such as `window._daily`, or a LiveKit
signalling connection the SDK itself establishes. Proxying every media and
signalling host is a different, much larger change. What IS guaranteed is that
nothing the PRODUCT itself renders, sends as copy, or labels reveals the
vendor — a candidate simply taking an interview never learns it, and nobody
learns it by accident from the application's own text or markup.

Provider SDK errors reaching the `InterviewProvider`'s `error` event MUST carry
a stable, provider-independent `code`, never the raw error text
(`String(err)` or equivalent) from the SDK — that text routinely names the
vendor and can echo connection details (a room URL, a host). Any diagnostic
`message` accompanying the code MUST also be scrubbed of vendor identifiers
before being emitted, on the basis that a message which exists is a message
something will eventually render.

#### Scenario: Neither locale file names a provider

- WHEN `i18n/locales/it.json` or `i18n/locales/en.json` is inspected
- THEN neither file contains `heygen`, `liveavatar`, `tavus`, `daily.co` /
  `dailyco`, or `livekit`, case-insensitively

#### Scenario: The interview page and avatar player render no vendor name

- WHEN the source of `app/pages/interview/[token].vue` or
  `app/components/AvatarPlayer.client.vue` is inspected
- THEN neither contains any of the provider vendor names, in code, comments, or
  template markup

#### Scenario: A Tavus SDK failure reports a stable code, not the vendor's error text

- GIVEN the Tavus call-object loader rejects with an error whose message names
  Daily and a `daily.co` room URL
- WHEN the `InterviewProvider` emits its `error` event
- THEN the emitted payload's `code` is a stable value (`sdk_error`) and no
  serialisation of the emitted payload matches a vendor name

#### Scenario: A HeyGen SDK failure reports a stable code, not the vendor's error text

- GIVEN the HeyGen SDK loader rejects with an error naming LiveAvatar
- WHEN the `InterviewProvider` emits its `error` event
- THEN no serialisation of the emitted payload matches a vendor name

---

### Requirement: Localized completion-phrase consumption

The frontend MUST NOT hardcode any completion-signal phrases. The `end_phrase` and
`final_phrase` fields from the `/start` `question_context` payload (the C7a addendum)
are the sole source of completion phrases. The frontend MUST apply
accent/case/punctuation-insensitive containment matching against these backend-provided
strings. If `end_phrase` or `final_phrase` is absent from the response, the HeyGen
provider MUST treat completion detection as unavailable and expose that via the
`InterviewProvider` error state.

#### Scenario: Backend-provided phrase matched case-insensitively

- GIVEN `question_context.end_phrase = 'Passiamo alla prossima domanda.'` (it project)
- WHEN the avatar says "passiamo alla prossima domanda" (lowercased, no trailing period)
- THEN the match succeeds and `complete` is emitted

#### Scenario: Backend-provided phrase matched for en project

- GIVEN `question_context.end_phrase = 'Let us move on to the next question.'` (en project)
- WHEN the avatar says "Let us move on to the next question"
- THEN the match succeeds without any Italian fallback string being evaluated

#### Scenario: Absent end_phrase surfaces as terminal provider error (not retryable)

- GIVEN `/start` returns `question_context` without `end_phrase` (contract violation or
  pre-addendum backend version)
- WHEN the HeyGen provider initializes
- THEN the provider emits an `error` state with a descriptive reason; the **terminal** screen is
  shown (no retry control); the terminal message is DISTINCT from the `403` message and reads
  "service temporarily unavailable — contact support" with a support-contact affordance; the
  error is classified as a version-mismatch / ops error — retrying the same `/start` would return
  the same absent field, so retry cannot recover this condition

#### Scenario: Absent final_phrase also surfaces as terminal (same path as absent end_phrase)

- GIVEN `/start` returns `question_context` with `end_phrase` present but `final_phrase` absent
  (or empty string)
- WHEN the HeyGen provider initializes
- THEN the provider emits an `error` state; the terminal screen is shown with the same
  "service temporarily unavailable — contact support" message; BOTH phrases are required before
  `matchesEndPhrase` may be called

---

### Requirement: Proctoring collection — 13 integrity kinds

The system MUST collect all 13 integrity event kinds during a live session:
`tab_hidden`, `focus_lost`, `second_monitor`, `face_absent`, `looking_away`,
`looking_down`, `too_far`, `multiple_faces`, `fullscreen_exit`, `clipboard_copy`,
`clipboard_paste`, `second_voice`, `phone_detected`. Events MUST be batched and flushed
via `POST /integrity` every `FLUSH_INTERVAL_MS` (10 000 ms). Snapshots MUST be captured
and sent via `POST /snapshot` every `SNAPSHOT_INTERVAL_MS` (10 000 ms) and on snapshot
integrity events. On `pagehide`, the pending batch MUST be flushed via
`navigator.sendBeacon`. APIs that are undefined in a given browser (e.g.
`screen.isExtended` on WebKit) MUST be gracefully guarded (no thrown exception; no-op).
The proctoring collector MUST be implemented as a composable returning an object (not
module-scope singletons) to enable isolation in unit tests.

**phone_detected / ObjectDetector:** The `phone_detected` kind is implemented via MediaPipe
`ObjectDetector` (model: `efficientdet_lite0.tflite`). If the model asset is absent at runtime,
`ensureObjectDetector` catches the initialization error and degrades gracefully — phone detection
is skipped silently; all other 12 integrity kinds continue normally. The `.tflite` asset is
deferred from the initial C7b delivery and MUST be committed in a follow-up (see Known Deferred
Items). The graceful-degradation path is covered by unit tests.

#### Scenario: Integrity batch flushed every 10s

- GIVEN an active session with 3 accumulated integrity events
- WHEN 10 000 ms elapse since the last flush
- THEN `POST /integrity` is called with the 3 events; the batch is cleared

#### Scenario: Snapshot sent every 10s

- GIVEN an active session
- WHEN 10 000 ms elapse since the last snapshot
- THEN the camera frame is captured as JPEG base64 and `POST /snapshot` is called

#### Scenario: pagehide triggers sendBeacon flush with absolute URL and correct Content-Type

- GIVEN an active session with pending integrity events and `runtimeConfig.public.apiBase = 'https://api.example.com'`
- WHEN the `pagehide` event fires (browser closes or navigates away)
- THEN `navigator.sendBeacon('https://api.example.com/api/candidate/interview/integrity', blob)` is
  called where `blob` is a `Blob` constructed with `type: 'application/json'`; the Content-Type
  of the beacon request is `application/json`; no events are lost silently

#### Scenario: screen.isExtended undefined — no-op (WebKit)

- GIVEN a WebKit browser where `screen.isExtended` is `undefined`
- WHEN the proctoring collector initializes
- THEN `second_monitor` detection is skipped without throwing; all other integrity kinds
  continue to be collected

---

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

### Requirement: API client typed from generated openapi.json

The frontend MUST consume the five interview endpoints exclusively through a
TypeScript client generated from the C7a-merged `api/develop` `openapi.json`. Hand-authored
request/response types for the interview endpoints are prohibited. The `openapi.json`
MUST be regenerated from the C7a-merged API before any interview endpoint is called
from TypeScript.

#### Scenario: Interview endpoint types present in generated client

- GIVEN `openapi.json` regenerated from C7a-merged `api/develop`
- WHEN `bun run codegen` executes
- THEN `types/api.ts` contains typed definitions for all five `/api/candidate/interview/*`
  endpoints including `question_context` with `end_phrase` and `final_phrase` fields

---

### Requirement: Color token reconciliation

All six brand color tokens in `frontend/app/assets/css/main.css` MUST be reconciled to the
DESIGN.md §3.1 normative values. The font token MUST also be reconciled. Additionally, two
supporting brand tokens (`--color-lavender` and `--color-bg-gradient`) from DESIGN.md §3.1
MUST be present in the reconciled `main.css`. Current `main.css` values are WRONG
(navy/teal/Inter); the DESIGN.md §4 example block that shows those same wrong values is itself
a documentation defect and MUST NOT be followed. The correction of DESIGN.md's own example
block is a C7b deliverable (see D9).

All interview UI components MUST reference semantic tokens (`bg-primary`, `text-muted-foreground`,
etc.) — no raw hex color values in component files.

| Token | Current (WRONG) | Normative (DESIGN.md §3.1) |
|---|---|---|
| `--color-primary` | `#1e3a5f` | `#771AAF` |
| `--color-primary-light` | `#2d5282` | `#C222D3` |
| `--color-primary-dark` | `#132740` | `#4F1AAF` |
| `--color-accent` | `#0d9488` | `#E45526` |
| `--color-accent-light` | `#14b8a6` | `#F19823` |
| `--color-accent-dark` | `#0f766e` | `#B8431E` |
| `--font-sans` | `'Inter', ...` | `"Open Sans", ...` |
| `--color-lavender` | absent | `#8373D2` (supporting secondary — subtle highlights, badges) |
| `--color-bg-gradient` | absent | `linear-gradient(135deg, #FAF7FD 0%, #F6F1FC 45%, #FDF4EF 100%)` (page background gradient; supersedes flat `--color-neutral-50`) |

#### Scenario: Primary color token set to DESIGN.md value

- GIVEN `main.css` is loaded
- WHEN `getComputedStyle(document.documentElement).getPropertyValue('--color-primary')` is read
- THEN the value equals `#771AAF`

#### Scenario: Primary-light color token reconciled

- GIVEN `main.css` is loaded
- WHEN `--color-primary-light` is read
- THEN the value equals `#C222D3`

#### Scenario: Primary-dark color token reconciled

- GIVEN `main.css` is loaded
- WHEN `--color-primary-dark` is read
- THEN the value equals `#4F1AAF`

#### Scenario: Accent color token reconciled

- GIVEN `main.css` is loaded
- WHEN `--color-accent` is read
- THEN the value equals `#E45526`

#### Scenario: Accent-light color token reconciled

- GIVEN `main.css` is loaded
- WHEN `--color-accent-light` is read
- THEN the value equals `#F19823`

#### Scenario: Accent-dark color token reconciled

- GIVEN `main.css` is loaded
- WHEN `--color-accent-dark` is read
- THEN the value equals `#B8431E`

#### Scenario: Font-sans token reconciled to Open Sans

- GIVEN `main.css` is loaded
- WHEN `--font-sans` is read
- THEN the value starts with `"Open Sans"` (not `'Inter'`)

#### Scenario: Lavender color token present

- GIVEN `main.css` is loaded
- WHEN `--color-lavender` is read
- THEN the value equals `#8373D2`

#### Scenario: Background gradient token present

- GIVEN `main.css` is loaded
- WHEN `--color-bg-gradient` is read
- THEN the value equals `linear-gradient(135deg, #FAF7FD 0%, #F6F1FC 45%, #FDF4EF 100%)`

---

## Coverage Note

The ~95% Vitest threshold applies ONLY to the correctness-critical **pure units**:
- `isSupportedBrowser(ua, width)` — Firefox UA rejected, Edge/Opera/Chrome/Safari accepted;
  width < 1024 rejected; Infinity passes for server-side UA-only check
- `useInterviewSession` state machine — all transitions including `terminal`, `429` retry/backoff,
  `409` drop (both `/utterance` and `/end`), `403` terminal redirect, resume-on-remount
- `matchesEndPhrase` — accent/case/punctuation variants; absent phrase → guard fires before call

The following are **NOT** in the Vitest ~95% threshold — they are covered by the **Playwright/E2E
+ CI-build tier** instead:
- `sendBeacon` flush on `pagehide` (needs a real browser context)
- SSR build isolation (no SDK in server bundle — verified by the Nitro CI build succeeding)
- Device-check happy path + camera/mic failure paths (require real `getUserMedia` / Playwright)

The `browser-gate.global.ts` **middleware wrapper** is EXCLUDED from the Vitest 95% threshold.
The middleware integrates the SSR request-headers path (`useRequestHeaders`) — an integration
concern only testable with a real Nuxt request context. SSR-path coverage for the middleware
wrapper is Playwright's responsibility (the chromium/webkit full-flow project navigates with
various UA strings via `browser.newContext({ userAgent })` or a custom fixture).

Playwright projects: chromium + webkit full flow; mobile project asserts the unsupported gate
only (viewport < 1024 px → `/unsupported`). CI SHOULD assert the `routeRules` locale-pattern
count matches the non-default `i18n.locales` count (guards future es/fr/de/pt locale additions).

---

## ADDED Requirements (C10)

### Requirement: Exit redirect at interview completion (C10)

When the candidate reaches the `done` state (all competency sessions ended — see the
existing Flow Screens requirement), the frontend MUST resolve the project's
`exit_redirect_url` and, if it is a non-null, non-empty string, redirect the browser to
that URL. `exit_redirect_url` is already exposed by the API on the candidate session
resource (`ParticipantResource.project.exit_redirect_url`,
`api/app/Http/Resources/ParticipantResource.php:58`, populated from
`Project.exit_redirect_url`, validated at `StoreProjectRequest.php:74`) — this addendum
consumes it for the first time; no backend change is required.

If `exit_redirect_url` is null or empty, the existing inline `done` branch in
`frontend/app/pages/interview/[token].vue` MUST be shown unchanged — "no further API
calls" per its existing doc comment. (`frontend/app/pages/interview/done.vue` is
unreachable dead code — no `navigateTo('/interview/done')` call exists anywhere in
`frontend/` — and is not the rendered surface; see design.md S15.) The redirect MUST fire regardless of the resulting
`Evaluation` status (`completed` or `pending`, per C9): evaluation is asynchronous and
NOT yet known at redirect time (per
`docs/app_description/04-integration-surface/04-user-exit.md` — "la valutazione non
è sincrona con il redirect"), and the frontend MUST NOT wait for it or poll for it before
redirecting.

**Scope note (D8):** this requirement covers ONLY the normal-completion `done` path.
Redirecting from `error`/`terminal` states to a distinct configurable error landing page
is explicitly OUT OF SCOPE for C10 (not requested by the proposal; the binding doc's
"Errore tecnico in intervista → redirect a pagina errore configurabile" case is
unimplemented and remains a future gap).

**Implementation dependency (flagged for design, not a spec requirement):** as of C7b,
no frontend code path calls `GET /api/candidate/session` —
`frontend/app/pages/interview/[token].vue:212-216` hardcodes an empty competency list
with the comment "In production, competency list comes from the C6 bootstrap endpoint."
Delivering this requirement therefore requires the design phase to wire a source for
`exit_redirect_url` (the bootstrap call or an equivalent) into the `done` state path;
this is a design-time concern, not a change to this requirement's observable contract.

#### Scenario: exit_redirect_url set — candidate redirected on done

- GIVEN a project with `exit_redirect_url = "https://hr.acme.com/beai/done?ref=acme-672"`
- WHEN the candidate's session reaches the `done` state (all competencies ended)
- THEN the browser is redirected to `https://hr.acme.com/beai/done?ref=acme-672`
- AND no evaluation-status check or poll precedes the redirect

#### Scenario: exit_redirect_url null — static done page shown, no redirect

- GIVEN a project with `exit_redirect_url = null`
- WHEN the candidate's session reaches the `done` state
- THEN the existing inline `done` branch in `frontend/app/pages/interview/[token].vue` is displayed unchanged
- AND no redirect navigation occurs and no further API calls are made

#### Scenario: Redirect fires identically for a pending evaluation

- GIVEN a project with `exit_redirect_url` set, and the candidate's evaluation will later resolve to `status = pending` (insufficient competency coverage)
- WHEN the candidate's session reaches the `done` state
- THEN the redirect fires exactly as in the completed case — the frontend has no visibility into evaluation status at redirect time and does not differentiate

---

## Known Deferred Items (not blocking archive)

- **`efficientdet_lite0.tflite`**: ObjectDetector model for `phone_detected` not committed in
  C7b delivery. Code degrades gracefully via `ensureObjectDetector` try/catch. Must be committed
  as a follow-up before production (requires Git LFS for `.tflite` files).
- **HeyGen `attach` runtime QA**: `LiveAvatarSession.attach(el)` only callable in a real browser
  context with a valid session token. Runtime behavior needs a real-provider integration test
  environment (no mock can cover this).
- **`useInterviewSession` branch coverage**: settled at 82.71% (dead-code ceiling at lines
  198-202 — unreachable sendSnapshot no-op path). The ~95% spec target was not fully reached
  for this unit specifically; all critical paths are covered.
- **`~/app/` path alias shim**: 23 import sites use `~/app/utils/...` (semantically wrong for
  Nuxt 4 where `~` = `app/`). A regex alias shim in `vitest.config.ts` and `nuxt.config.ts`
  compensates. Should be cleaned up in a follow-up (replace with `~/utils/...` etc.).

<!-- promoted from frontend-root-landing -->

### Requirement: Root route is an informational dead end

`GET /` MUST render a static, localized orientation screen. It MUST NOT return
404.

The screen MUST tell the visitor exactly one thing: that access to an interview
happens through the link they were sent. That is the whole content, because it
is the only true and actionable statement BEAI can make to somebody standing at
the root — the platform does not know who they are, cannot look them up, and
holds no contact data for them.

The page MUST NOT contain:

- any `<input>`, `<form>`, or `<button>` that submits
- any link or affordance suggesting login, sign-up, or "request access"
- any support contact (email, phone, chat)

These prohibitions are requirements, not guidance. BEAI has no candidate
account, enrolment belongs to the calling system, and BEAI is not the
candidate's support channel — a support address here would route confused people
to the wrong party and imply BEAI can identify them. The absence is asserted by
test, because an absence nobody tests is an absence nobody maintains.

The page MUST make no API call and hold no reactive state.

#### Scenario: A visitor reaches the root

- WHEN `GET /` is requested with a supported desktop browser
- THEN HTTP 200 is returned
- AND the rendered document contains the orientation message
- AND the document contains no form control and no login or sign-up affordance

#### Scenario: The root is not indexed

- WHEN `GET /` is rendered
- THEN the document declares `<meta name="robots" content="noindex, nofollow">`

Consistent with every other candidate-facing route: nothing in this application
should appear in a search result, and a page inviting orientation is exactly the
one a search engine would otherwise surface to the wrong audience.

#### Scenario: The root is localized

- GIVEN the active locale is `it`
- WHEN `GET /` is rendered
- THEN the orientation message is the Italian copy
- AND GIVEN the active locale is `en`, the English copy is rendered instead

#### Scenario: The root has a non-empty document title

- WHEN `GET /` is rendered
- THEN `<title>` is non-empty

WCAG 2.4.2 (Page Titled), the same obligation `/unsupported` already carries.

#### Scenario: The root passes the accessibility gate

- WHEN `GET /` is rendered
- THEN an `axe` scan reports no WCAG 2.1 Level AA violation

#### Scenario: An unsupported browser never sees the root

- GIVEN a Firefox user agent, or a viewport narrower than 1024px
- WHEN `GET /` is requested
- THEN the visitor is redirected to `/unsupported`

The existing global browser gate already produces this: it skips only paths
ending in `/unsupported`, so the root is gated like any other route. Asserted
here so a future change to the gate's skip list cannot silently expose the root
to a device the product does not support — and because telling a phone user to
switch device is more actionable than orientation copy they cannot use yet.

---

## ADDED Requirements (C15)

### Requirement: Failed interviews return the candidate to the calling system

When the interview reaches `error` or `terminal` and the project has a non-empty
`error_redirect_url`, the frontend MUST redirect the browser there.

This closes the gap this spec already records as open, and it matters more than
the success redirect it mirrors. On completion the candidate is finished; on
failure they are stranded on a BEAI screen, on a domain they have no account on,
belonging to a company they have no relationship with. The calling system is the
only party that can tell them whether the interview will be re-issued, who to
contact, or whether their application is affected — BEAI can answer none of
those and must not imply otherwise.

The redirect MUST NOT append an error code, reason or any query parameter. The
binding doc places the query-string format out of scope; inventing one would be
a contract nobody agreed to and no caller reads.

When `error_redirect_url` is null or empty the existing inline screen MUST be
shown unchanged, including its retry affordance. This requirement adds a route
out; it never removes the one that already exists.

#### Scenario: A configured project redirects on error

- GIVEN a project with a non-empty `error_redirect_url`
- WHEN the interview reaches the `error` state
- THEN the browser is redirected to that URL

#### Scenario: The terminal state redirects identically

- GIVEN the same project
- WHEN the interview reaches `terminal` for any reason
- THEN the browser is redirected to the same URL

The candidate's need is identical in both: they cannot continue and they need to
get back to whoever sent them. Splitting the destinations would ask the operator
to configure a distinction their candidates cannot perceive.

#### Scenario: An unconfigured project keeps the inline screen

- GIVEN a project whose `error_redirect_url` is null
- WHEN the interview reaches `error`
- THEN the existing inline error screen is rendered, with its retry button

#### Scenario: The redirect carries no diagnostic payload

- WHEN the redirect fires
- THEN the target URL is used verbatim, with no appended query string

### Requirement: Single-use entry-route exchange

The system MUST expose `/interview/{token}` as an entry route that performs the
sso-link exchange **at most once** and renders no durable UI of its own.

On mount, the entry route MUST, in order:
1. Read the stored candidate session, if any. If it exists, is unexpired, and its
   `candidate_ref` + `project_id` claims match the sso-link's own claims, the exchange
   MUST be skipped and the candidate MUST be navigated directly to the session route.
2. Otherwise call `GET /api/sso/exchange` exactly once, persist the returned candidate
   JWT, and `navigateTo` the token-free session route with `replace: true`.

The session route MUST carry no token in its URL. Refreshing the entry route after
step 2 has completed, or refreshing the session route at any point, MUST NOT trigger a
second exchange call.

`useInterviewSession` MUST NOT read the route token itself; it accepts only
`{ competencies, getPendingIntegrityEvents, onIntegrityEventsFlushed }`. No comment,
code, or documentation MAY claim it reads the token internally.

#### Scenario: First visit exchanges once and lands on a token-free URL

- GIVEN a candidate with no stored session opens a fresh, unspent `/interview/{token}` link
- WHEN the entry route mounts
- THEN exactly one `GET /api/sso/exchange` request is made, the returned JWT is
  persisted, and the browser is navigated to the session route with the sso-link
  token no longer present in the URL or browser history entry

#### Scenario: Refresh after exchange does not burn the link

- GIVEN a candidate has already exchanged and is on the token-free session route
- WHEN the candidate refreshes the page
- THEN no additional `GET /api/sso/exchange` request is made and the interview session survives

#### Scenario: A valid stored session skips the exchange entirely

- GIVEN a candidate has a stored, unexpired candidate session whose `candidate_ref`
  and `project_id` claims match a freshly opened sso-link
- WHEN the entry route mounts
- THEN no `GET /api/sso/exchange` request is made; the candidate is routed directly
  to resume (see Resume on entry)

#### Scenario: useInterviewSession does not read the route token

- WHEN the source of `useInterviewSession` is inspected
- THEN its exported factory accepts only `{ competencies, getPendingIntegrityEvents,
  onIntegrityEventsFlushed }`, and no call to `useRoute()` or a route-token read
  exists inside it
- AND no comment in `frontend/app/pages/interview/[token].vue` or in
  `useInterviewSession` claims the composable reads the token internally

---

### Requirement: Candidate session persistence

The system MUST persist the candidate JWT returned by the exchange or by a reusable-link
redemption in `localStorage`, bounded by the interview's lifecycle rather than the browser's:
- Cleared on reaching `done`, on reaching `terminal`, on any `401` response from a
  candidate call, and immediately before an exit or error redirect fires.
- Purged on read when the token's `exp` claim has already passed — an abandoned
  session self-cleans on next load without a network round-trip.

The stored record MUST carry an `entry` marker: `'reusable'` when it was stored by the
reusable entry route, and no `entry` key at all when stored by the single-use or the hosted
route (those records stay byte-identical to what they were). The reusable entry route resumes
a stored session ONLY when its marker is `'reusable'`; the single-use route's existing
matching on `candidate_ref` and `project_id` is unchanged. Clearing conditions apply to both
kinds identically.
(Previously: a single stored shape with no origin marker; only the single-use route existed.)

The composable MUST expose store, read, clear, and expiry-check operations; no other
module MAY read or write the candidate token directly.

#### Scenario: Token persists across a tab close and reopen

- GIVEN a candidate has an unexpired persisted candidate session
- WHEN the tab is closed and the app is reopened at the session route
- THEN the stored token is still present and is used to resume (see Resume on entry)

#### Scenario: Token cleared on terminal

- GIVEN an active candidate session
- WHEN the session reaches `terminal` for any reason
- THEN the stored candidate token is cleared before any redirect fires

#### Scenario: Token cleared on 401

- GIVEN an active candidate session
- WHEN any candidate API call returns `401`
- THEN the stored candidate token is cleared

#### Scenario: Expired token purged on read

- GIVEN a stored candidate token whose `exp` claim is in the past
- WHEN the composable reads the stored session
- THEN the stored value is discarded and reading returns "no session", without a network call

#### Scenario: The reusable route stores the marker

- GIVEN a successful reusable redemption
- WHEN the session is stored
- THEN the stored record has `entry: 'reusable'` alongside the token, `exp`, `candidateRef` and
  `projectId`

#### Scenario: The single-use route stores no reusable marker

- GIVEN a successful single-use exchange, and a hosted session
- WHEN the session is stored
- THEN the stored record has no `entry` key

#### Scenario: A reusable session clears like any other

- GIVEN a stored `entry: 'reusable'` session
- WHEN the session reaches `done`, `terminal` or a `401`
- THEN it is cleared, exactly as a single-use session

#### Scenario: A stored reusable session is not matched by a single-use link

- GIVEN a stored reusable session with `candidate_ref = "rlv_..."`
- WHEN a single-use link for a different `candidate_ref` is opened
- THEN the existing claims match fails and the exchange proceeds as before

---

### Requirement: Every candidate request is authenticated

Every request the frontend makes to a candidate-scoped endpoint — the five interview
endpoints (`/start`, `/utterance`, `/integrity`, `/snapshot`, `/end`),
`GET /api/candidate/session`, and the `pagehide` integrity flush — MUST carry
`Authorization: Bearer <candidate JWT>`. No candidate request MAY be issued without
it. A missing or expired stored session MUST prevent the call from being attempted at
all, rather than being sent unauthenticated.

Satisfying this requirement makes two already-specified behaviors reachable for the
first time: the `done`-state exit redirect and the `error`/`terminal`-state error
redirect both depend on `GET /api/candidate/session` succeeding; today that call is
unauthenticated, returns `401`, and is swallowed as non-fatal, so neither redirect has
ever fired in production.

#### Scenario: /start carries the Authorization header

- GIVEN a persisted candidate session
- WHEN the session machine calls `POST /api/candidate/interview/start`
- THEN the request carries `Authorization: Bearer <token>` and does not receive
  `401` for that reason

#### Scenario: No candidate request is ever issued without the header

- WHEN every call site that issues a candidate-scoped request is inspected
- THEN each one is routed through the single authenticated request path; none
  constructs a candidate request without attaching the header

#### Scenario: /candidate/session succeeds and the exit redirect fires

- GIVEN a persisted candidate session and a project with a non-empty `exit_redirect_url`
- WHEN the candidate reaches `done`
- THEN `GET /api/candidate/session` is called with the Authorization header,
  succeeds, and the exit redirect fires (previously unreachable — the call 401'd
  and was swallowed)

#### Scenario: Unauthenticated call never silently succeeds

- GIVEN no stored candidate session
- WHEN a candidate-scoped endpoint is called
- THEN the call is either not attempted, or attempted and the resulting `401` is
  handled by the `401` state (see Honest failure states) — the UI never treats it
  as success

---

### Requirement: pagehide integrity flush is authenticated or its failure is visible

The end-of-session `pagehide` integrity flush MUST deliver the proctoring evidence
batch to the server authenticated, or its failure MUST be surfaced rather than
silently dropped. `navigator.sendBeacon` cannot set request headers, so the
authentication mechanism for this specific call is a design-time decision; this
requirement constrains only the observable outcome.

#### Scenario: pagehide flush reaches the server

- GIVEN pending integrity events at the moment `pagehide` fires
- WHEN the flush is sent
- THEN the server records the batch against the correct candidate session — not a
  silent `401`

#### Scenario: A failed pagehide flush is not silently lost

- GIVEN the pagehide flush cannot be delivered (network failure, rejected auth)
- WHEN the failure occurs
- THEN it is observable (logged, retried, or surfaced) rather than indistinguishable
  from a successful flush

---

### Requirement: Resume on entry via /start

Reaching the session route with a valid stored candidate session MUST trigger a call
to `POST /api/candidate/interview/start` and MUST render a determinate loading state
while the response is pending — never a blank screen. The response governs whether a
session resumes at the persisted `question_index` (backend `RESUME in_corso` path) or
a new competency session is created; the frontend MUST NOT infer or guess this
outcome client-side.

#### Scenario: Reopening after a tab close resumes at the persisted competency

- GIVEN a candidate with a stored, unexpired session who paused mid-interview and
  closed the tab
- WHEN the candidate reopens the app and lands on the session route
- THEN `POST /start` is called, a loading state is shown while it is pending, and
  the interview resumes at the `question_index` the backend returns
- AND the candidate is never shown a blank screen while resuming

#### Scenario: A brand-new candidate proceeds to device check, not resume

- GIVEN a freshly exchanged candidate session with no prior competency progress
- WHEN the session route is reached
- THEN the existing consent/device-check flow governs entry as before; no
  resume-specific screen is shown

---

### Requirement: Honest failure states, including for a paused candidate who cannot be rescued

The system MUST map failure conditions to distinct, honest screens; no condition MAY
produce a silently broken page.

| Condition | Screen |
|---|---|
| Spent link, no stored session (`401` from exchange) | Terminal, no retry — retry cannot succeed |
| Gate or status refusal (`403` from exchange) | Terminal, generic message — no gate detail disclosed |
| Stored session expired (`401` from any candidate call) | Terminal, distinct "session expired" copy |
| Provider / `502` / network | Unchanged — existing retryable `error` |

`401` MUST be a distinct, non-retryable state in the session machine; it MUST NOT
fall into the retryable `error` state and MUST NOT retry indefinitely.

**A newly minted replacement link does NOT rescue a paused candidate.** The
exchange's pre-flight read only proceeds when the participant's status is
`in_attesa`; a paused candidate's status is `in_corso`, so any new, valid, unspent
sso-link presented for that candidate is refused with a generic `403` at the
exchange, identical to any other blocked status. Combined with the 120-minute
candidate JWT and no revocation mechanism, a candidate whose stored session expires
after pausing has no self-serve path back into the interview from this change. The
expired-session terminal screen MUST state this honestly and MUST NOT suggest that
requesting or receiving a new link will help.

**`error_redirect_url` routing is scoped to terminals reached AFTER a candidate JWT
exists — it is structurally impossible before one does.** `GET /api/candidate/session`
(the endpoint `error_redirect_url` is resolved from) requires an authenticated
candidate JWT (`auth:api-candidate` guard), and this proposal's backend-unchanged
constraint (see Proposal, "Out of Scope") forbids adding an unauthenticated variant
of it. Concretely:

- **CAN route through `error_redirect_url`**: terminals reached via `session.vue`'s
  state machine while a candidate JWT is (or very recently was) valid — the existing
  `403`-from-`/start`-or-`/end` path, `absent_phrase`, `malformed_response`, and a
  mid-session `session_expired` (a live `401` on an authenticated call). For all of
  these, `useExitRedirect.fetchSession()` already resolved `error_redirect_url` once,
  authenticated, at page mount — the redirect uses that already-cached value; it does
  not need a new authenticated call at the moment of failure.
- **CANNOT route through `error_redirect_url`**, by construction, not by omission:
  - The entry route's own exchange failures — spent link (`401`) and gate/status
    refusal (`403`). No candidate JWT has ever existed for this attempt; there is
    nothing to authenticate `GET /api/candidate/session` with.
  - The `candidate-session` middleware's gate on `/interview/session` (no valid
    stored session — absent or already expired). By definition, no valid candidate
    JWT exists at this exact point either.

  Both cases show the static, honest terminal screen (`terminal.vue`, keyed by the
  `reason` query param) with no external-redirect capability. This is the correct,
  final behavior for this proposal, not a gap to close later.

#### Scenario: Spent link with no stored session shows terminal, no retry

- GIVEN a candidate opens an already-spent sso-link and has no stored candidate session
- WHEN the exchange returns `401`
- THEN the terminal screen is shown with no retry control

#### Scenario: Gate refusal discloses no detail

- GIVEN the exchange returns `403` for any gate or status reason
- WHEN the terminal screen is shown
- THEN its copy is the generic message; it does not name the specific gate or
  status that blocked it

#### Scenario: Expired stored session is distinct from a spent link

- GIVEN a stored candidate session whose token has expired
- WHEN a candidate call returns `401`
- THEN a terminal screen distinct from the spent-link terminal is shown, with
  "session expired" copy

#### Scenario: 401 does not retry indefinitely

- GIVEN any candidate call returns `401`
- WHEN the session machine processes the response
- THEN it transitions to the non-retryable `401`/terminal state, not to the
  retryable `error` state, and no automatic retry is attempted

#### Scenario: A paused candidate's fresh replacement link is refused, not honored

- GIVEN a candidate whose status is `in_corso` (paused mid-interview, stored
  session since expired)
- WHEN a newly minted, unspent sso-link is exchanged for that same candidate
- THEN the exchange returns `403` with the generic body, exactly as any other
  non-`in_attesa` status; the candidate is not re-admitted

#### Scenario: The expired-session terminal screen does not imply a new link will help

- GIVEN a candidate reaches the expired-session terminal screen, by any path
- WHEN its copy is inspected
- THEN it does not instruct the candidate to request or use a new link

#### Scenario: A mid-session expired terminal (candidate JWT existed) routes through error_redirect_url

- GIVEN a candidate's session was valid when `session.vue` mounted (so
  `useExitRedirect.fetchSession()` already resolved `error_redirect_url`, if
  configured) and the candidate JWT subsequently expires or is rejected mid-session
- WHEN the session machine reaches the `session_expired` terminal
- THEN the candidate is routed through the already-cached `error_redirect_url`
  when configured, and shown the inline expired-session screen otherwise

#### Scenario: A pre-authentication expired/spent terminal does NOT route through error_redirect_url

- GIVEN a candidate reaches `/interview/session` with no valid stored session
  (the `candidate-session` middleware gate), OR the entry route's own exchange
  returns `401` (spent link) or `403` (gate refusal)
- WHEN the terminal screen is shown
- THEN it is the static `terminal.vue` screen with no external-redirect
  capability — no `GET /api/candidate/session` call is attempted, because no
  candidate JWT exists to authenticate it with, and none MAY be attempted
  unauthenticated

---

### Requirement: Genuine authentication is exercised by tests, not mocked

At least one test MUST exercise the full genuine chain — minting an sso-link,
exchanging it for a candidate JWT, and making an authenticated candidate call —
without mocking ANY step of that chain. **This test lives in the api Pest suite**
(`MintExchangeAuthenticatedCallTest.php`), not in the frontend E2E suite — see
"Where the ownership splits" below for why, decided and recorded here rather than
left as an unstated contradiction between this spec and the frontend test files.

**Where the ownership splits.** `frontend/playwright.config.ts`'s `webServer` boots
the Nuxt app alone — no PHP, no Postgres, no Redis (a real API is a named, costed,
NOT-built-here follow-up: standing one up here means new service containers, new
migrations, a seeded org/project, an artisan mint command, and a new class of CI
flake, for a suite that currently has none). There is therefore no real `/api/sso/exchange`
endpoint for the frontend E2E suite to call unmocked; `page.route()` stubs it in
every scenario. This is not a partial implementation of this requirement — it is
the deliberate, permanent shape: **the api Pest test owns the genuine,
end-to-end, nothing-mocked chain; the frontend E2E suite owns the browser-side
half that Pest cannot reach — does the client actually attach the header, and
does a refresh re-exchange — proven via REQUEST-side assertions that a stubbed
RESPONSE does not weaken:** the exchange is called exactly once across a reload
or a stored-session revisit, and the very next candidate call carries
`Authorization: Bearer <the token the stub returned>`. The one residual seam (the
field name on the wire, `access_token`) is covered separately by
`scripts/check-client-drift.sh`.

#### Scenario: The genuine chain is exercised end to end (api Pest)

- GIVEN a minted sso-link
- WHEN it is exchanged and the returned token is used to call a candidate endpoint
- THEN the call succeeds using the real backend chain, with no endpoint in this
  chain intercepted or faked — verified in `MintExchangeAuthenticatedCallTest.php`,
  not in the frontend E2E suite

#### Scenario: The frontend E2E suite proves request-side behavior against a stubbed exchange response

- GIVEN the frontend E2E suite's `webServer` has no real backend to exchange
  against, and `GET /api/sso/exchange` is stubbed via `page.route()` in every
  scenario that needs to get past the entry route
- WHEN the entry route exchanges and the first `POST /candidate/interview/start`
  request is inspected
- THEN it carries `Authorization: Bearer <the token the stub's response
  returned>` — proving the token is genuinely propagated from the exchange
  response into the next authenticated call, not merely that the stub was
  reachable
- AND a reload or a stored-session revisit of the entry URL triggers no more
  than the expected number of exchange calls, asserted by an exchange-call
  counter that is provably sensitive to disabling the stored-session-match
  guard (a test that cannot fail on the thing it names is not kept)

---

## ADDED Requirements (participant-error-recovery)

### Requirement: Error State Copy Never Promises An Unconditional Resume

`interview.error.body` MUST NOT promise that retrying will always succeed. It MUST
state that the interview can be retried now, and that if the problem persists an
operator must re-open the assessment. This is because the underlying failure is
genuinely retryable in some cases (`ClientError`/`Throttle`, which never mark the
participant) and genuinely terminal in others (`Upstream`, which writes `errore` and
requires operator recovery); the copy MUST be true in both cases and MUST NOT
contradict the terminal-403 screen the candidate may hit next.

The existing structural i18n guard
(`frontend/tests/unit/i18n-interview-keys.spec.ts`, the pattern already applied to
`session_expired`) MUST be extended to the `error` state: `interview.error.body` MUST
be added to `REQUIRED_KEYS`, and a locale-specific assertion MUST fail if the body
matches an unconditional-resume pattern — `it: /riprender|dal punto in cui/i`,
`en: /resume|where you left off/i`.

#### Scenario: interview.error.body is required to exist

- GIVEN the i18n structural guard runs
- WHEN `interview.error.body` is missing from either locale
- THEN the test fails, naming the missing key

#### Scenario: An unconditional resume promise fails the guard

- GIVEN a locale's `interview.error.body` matches that locale's resume-promise
  pattern
- WHEN the structural guard runs
- THEN the test fails

#### Scenario: The corrected copy passes the guard

- GIVEN `interview.error.body` states the interview can be retried now and, if the
  problem persists, must be re-opened by an operator
- WHEN the structural guard runs
- THEN it passes in both `it` and `en`

### Requirement: Continuous avatar presence across a competency handover (HeyGen only)

For a HeyGen-provider interview, the system MUST keep the outgoing avatar mounted, live,
and visible from the moment one competency ends until the incoming competency's avatar
reports ready to be seen. The candidate MUST NOT see any empty, skeleton, or panel state
between two consecutive HeyGen competencies. The outgoing avatar stays live and idling
during this interval — never a frozen frame. This requirement governs HeyGen only. A Tavus
interview is unchanged by it when single-session is off; when single-session is on, Tavus
competency transitions are governed by "Utterance Attribution Retargets At A Competency Boundary
Without A Race Window" (a continuation shows no transition at all) and "Provider Session Ceiling
Handover Extends To Tavus" (a fresh conversation crossfades). An interview's first competency has no outgoing session to
hold and is unaffected — it keeps today's device-check-adjacent connecting presentation.

#### Scenario: No visible break between two HeyGen competencies

- GIVEN a HeyGen interview has just completed a competency and the server directs
  `next_action = 'continue'`
- WHEN the incoming competency's session is requested and becomes ready
- THEN at every point in between, an avatar is visibly mounted on screen — never an
  empty, skeleton, or panel state

#### Scenario: The first competency keeps today's connecting presentation

- GIVEN a candidate has just passed the device check and no competency has run yet
- WHEN the first competency's session is requested
- THEN the existing first-connect presentation is shown, unchanged by this requirement
  (there is no outgoing session to hold)

#### Scenario: Tavus handover with single-session off is unaffected

- GIVEN a Tavus interview with single-session off completes a competency and `next_action = 'continue'`
- WHEN the next competency's session is requested and the response has no `continuation`
- THEN the currently-shipped Tavus connecting presentation is shown exactly as before this change

---

### Requirement: Exactly one avatar is audible during a HeyGen handover

While an outgoing and an incoming HeyGen session are both live, at most one of them MUST
be audible to the candidate at any instant. The outgoing session MUST be muted the moment
it signals completion. The incoming session MUST NOT be heard by the candidate before it
is the one visible on screen.

#### Scenario: The outgoing avatar never speaks after completion

- GIVEN a HeyGen competency's session signals completion
- WHEN the incoming session is being prepared
- THEN the outgoing session produces no audible speech from that point onward

#### Scenario: The incoming avatar is not heard before it is seen

- GIVEN an incoming HeyGen session is live but not yet the one shown to the candidate
- WHEN the incoming session's own greeting becomes available
- THEN the candidate does not hear it until the incoming avatar is the one visible

### Requirement: The outgoing session is torn down once the handover completes

Every HeyGen provider session MUST be released exactly once and MUST NOT be left to
expire on its own provider-side ceiling. The outgoing session's release MUST occur once
the incoming avatar becomes the one shown to the candidate.

#### Scenario: Outgoing session released after the handover

- GIVEN a HeyGen handover has completed and the incoming avatar is now shown
- WHEN the outgoing session's status is inspected
- THEN it has been released; it is not left held open awaiting its provider-side ceiling

### Requirement: An overlap that exceeds its bound degrades to the existing fallback, never an error

If the incoming HeyGen session has not reported ready within 10 seconds of the outgoing
session signalling completion, the system MUST release the outgoing session and present
the currently-shipped visible fallback for a slow connect. This condition MUST NOT be
presented to the candidate as an error state.

#### Scenario: A slow incoming session falls back to the existing presentation

- GIVEN the incoming HeyGen session has not reported ready within 10 seconds of the
  outgoing session signalling completion
- WHEN that bound is reached
- THEN the outgoing session is released and the candidate sees the currently-shipped
  fallback presentation, not an error screen

---

## ADDED Requirements (reusable-interview-links)

Vocabulary: the "reusable entry route" is the page `frontend/app/pages/interview/reusable.vue`
(URL `/interview/reusable`, `/en/interview/reusable` for the `en` locale), opened with the link
token in the URL fragment. "Visitor" and "reusable link" are defined in the capability
`reusable-interview-links`. The single-use route `/interview/{token}` is unchanged. The
"identity form" is the step of `/interview/reusable` that collects the visitor's name and
email; the "held token" is the link token kept in page memory only; the "reopen state" is the
terminal state shown after a reload while the form was displayed.

### Requirement: Reusable Entry Route

The system MUST expose `/interview/reusable` as a client-only entry route (a static route that
outranks `interview/[token]`) that collects the visitor's identity and then redeems a reusable
link once per submit, rendering the identity form, a determinate loading state (never a blank
screen) and the terminal or error states below. It MUST NOT call `GET /api/sso/exchange`. It
MUST set a localized document title (WCAG 2.4.2) while each of its states is on screen: the
accessibility audit reports `document-title` as serious without one.

(Previously: the route rendered no durable UI of its own and redeemed automatically, at most
once per page load, as soon as a token was read; there was no identity step.)

The fragment MUST be stripped by an early client plugin that runs on EVERY route, before the
router and before page code: a phone scanning a kiosk QR code hits the SA-11 gate, whose
redirect to `/unsupported` carries the fragment across, so stripping only on the reusable page
would leave the token in the address bar there. The plugin MUST declare `order: -50` through
the object form of `defineNuxtPlugin` (Nuxt reads a plugin's `order` statically, from the raw
file text and only from that form, and its metadata extraction returns nothing when the raw
text, comments included, contains a function-form call; a file-name prefix alone is NOT
enough). At the default order the router plugin reads `window.location` first and its
`app:created` replay writes the fragment back into the address bar and into
`history.state.current`. The plugin MUST also strip and discard a `#beai_rl_` fragment pasted
into the same tab later (`hashchange`). The strip MUST also remove the token from
`history.state.current`: on a hash-only change `popstate` fires before `hashchange`, and the
router writes the fragment-bearing location into the state first, so an address-bar strip alone
would leave the token in the history state.

On mount, in this order:
1. Read the URL fragment (without `#`). If a non-empty `beai_rl_` fragment exists, it is the
   link token. Strip the fragment from the address bar with `history.replaceState` keeping
   `history.state`, except that a string `current` whose fragment starts with `#beai_rl_` is
   rewritten to the part before the `#` (replacing the current history entry, never pushing)
   BEFORE any network call and before any other asynchronous work (the page also captures
   idempotently itself, so it does not depend on the plugin's timing). The token is held only
   in page memory from here on (the held token), until the redemption succeeds or a terminal
   state is reached; it is never read back from anywhere else. A fragment that does not match
   `^beai_rl_[A-Za-z0-9_-]{43}$` is present but yields no token.
2. If a token was read: clear any stored candidate session first (a kiosk never resumes the
   previous visitor), then show the identity form (see "Reusable Identity Form Content And
   Validation") and make NO network request. The redemption `POST /api/reusable-links/redeem`
   is sent only when the visitor submits a valid form, with the JSON body `{"link_token": <held
   token>, "display_name": <trimmed name>, "email": <trimmed email>}`, exactly one request per
   submit; on HTTP 200 persist the returned `access_token` through the candidate session
   composable with `entry: 'reusable'`, discard the held token and the typed identity from
   memory, and leave for the token-free session route `/interview/session` (localized path)
   with an awaited `router.replace`. Every visit with a fragment yields a NEW visitor, never a
   resumed one. A 200 whose token cannot be stored is a retryable failure, never a navigation
   to a dead session route.
3. If a fragment was present but malformed: show the terminal `link_invalid` state with NO
   network call and NO identity form.
4. If no fragment was read (for example a reload after the strip): if a stored, unexpired
   candidate session with `entry === 'reusable'` exists, navigate to the session route (which
   resumes through `POST /start`); otherwise, if the non-secret "form shown" marker defined in
   "Reusable Reload During The Form Shows A Reopen State" is present, show the terminal reopen
   state (the terminal route with reason `link_reopen`); otherwise show the terminal
   `link_invalid` state. In every case with no fragment there is NO network call. A stored
   session without the `reusable` marker MUST NOT be resumed here.

The redemption is performed by one composable (`useReusableLinkRedeem`) that never throws and
maps the response onto exactly seven outcomes; it MUST drop the HTTP client's error object
(which keeps the request options, and with them the token, the name and the email) and keep
only the response body. Response types come from the generated client, never hand-written.

Outcome mapping: HTTP 404 -> terminal `link_invalid` (existing reason, no retry control). HTTP
403 -> the same handling the single-use entry route gives an exchange 403: a validated https
`redirect_url` is followed through `safeExternalRedirect`, otherwise a terminal generic `403`
state; no gate detail is disclosed and nothing new is invented. HTTP 422 -> the form stays on
screen and editable, with the frontend's OWN localized per-field messages on the fields named
in the response `errors` (`display_name`, `email`); server message text is never shown, and a
422 that names neither known field is the retryable "failed" state, never a silent no-op. HTTP
409 (`duplicate_enrolment`) -> the form stays on screen and editable with a localized error on
the email field telling the visitor the address has already been used for this interview and to
contact whoever shared the link (English: "This email address has already been used for this
interview. Please contact the person who shared the link with you."; Italian: "Questo indirizzo
email è già stato utilizzato per questo colloquio. Contatta chi ti ha condiviso il link."); the
held token is kept and the visitor may correct the email and submit again; a 409 whose body is
not `duplicate_enrolment` is the "failed" state. HTTP 429 -> the "busy" state; a network
failure or a 5xx -> the "failed" state. Both states replace the form with a notice (title,
message and a Retry control) and are retryable on the page itself (the generic error route's
back navigation cannot work, because the URL no longer holds the token) and are NEVER
`link_invalid`, which would be untrue; Retry re-calls redeem with the held token AND the held
identity, so the visitor does not retype, and neither is ever written back to the URL, storage
or history. A reload after such an error has no fragment and therefore falls to step 4. If the
retry then ends in a 422 or a 409, the form is shown again with the held name and email
prefilled. A submit MUST NOT be repeated by re-renders, double clicks, Enter key repeat or a
hydration re-run: submit is disabled and the form is `aria-busy` while a request is in flight,
so one submit is one request.

The token MUST NOT appear, after the strip, in the address bar, history entry or
`history.state`, router state or query, `localStorage`, `sessionStorage`, the DOM, console
output, analytics payloads, or any request other than the single redemption body. The visitor's
name and email MUST NOT appear in the address bar, history, router state or query,
`localStorage`, `sessionStorage`, console output, analytics payloads, error reports or any
request other than the redemption body. The SA-11 browser gate still applies first: an
unsupported browser is redirected to `/unsupported`, MUST NOT show the identity form and MUST
NOT call the redemption (so no visitor is created).

The terminal `link_invalid` state shows copy that is true for every case that reaches it:
single-use links that are expired, already invalid or malformed, and reusable links that are
unknown, malformed or disabled. A reusable link never expires, so the copy MUST NOT claim
expiry. English: title "This Link Is No Longer Valid", body "This interview link is not valid
or is no longer active. Please ask whoever sent it to you for a new link." Italian: title
"Questo link non è più valido", body "Questo link per il colloquio non è valido o non è più
attivo. Chiedi un nuovo link a chi te lo ha inviato."

(Reconciled with the implementation, where it differs from the original delta text: (1) the
page leaves with an awaited `router.replace`, not `navigateTo`. While a router navigation is in
flight (a link pasted into an open tab fires `popstate` before `hashchange`), Nuxt treats
`navigateTo` as a middleware redirect: it returns a route object and does not navigate, and a
caller that ignores it strands the visitor on the page. `router.replace` supersedes the pending
navigation, and awaiting it keeps the form disabled until the router has left. This applies to
every exit: success, `link_invalid`, the generic 403, the reopen state and a resumed session.
(2) The busy and failed states are full notices that replace the form, each with a Retry
control, rather than a message beside the form; Retry shows the loading state and re-posts the
held token and identity. (3) An unrecognized 422 shape is the "failed" state, not a generic
form-level message, so a refusal the page cannot map is never silent. (4) The reload state is
the terminal route with reason `link_reopen`, reached with `router.replace`; the non-secret
marker is read once and removed by that read. (5) The submit button reads "Starting…" while a
request is in flight (disabled and `aria-busy`), and the form is `aria-busy` too.)

(Known limitation: a redemption that succeeds on the server but whose response never reaches
the page (a dropped connection, a timeout) leaves the visitor enrolled and without a session.
The page shows the "failed" state, and Retry re-posts the held token and the same email, which
the api refuses with 409 `duplicate_enrolment` because the enrolment now exists and is never
resumed. The visitor cannot continue that interview: the token was stripped from the address
bar, and only a different email, which creates a second enrolment, or an operator, gets them
further. An idempotency key on the redemption would let a retry return the original result;
it is out of scope for this change and is recorded as a follow-up.)

#### Scenario: The link_invalid copy never claims expiry
- WHEN the terminal page is rendered with `reason=link_invalid` in English or in Italian
- THEN neither the title nor the body contains "expire" (English) or "scad" (Italian)
- AND the body ends with a request to ask whoever sent the link for a new one

#### Scenario: A well-formed fragment shows the form and makes no request

- GIVEN a desktop browser with no stored session opens `/interview/reusable#beai_rl_<43 chars>`
- WHEN the page mounts
- THEN the identity form is shown, no network request is made, and the address bar and history
  hold no fragment

#### Scenario: First visit redeems once on submit and lands on a token-free URL

- GIVEN the form is shown and the visitor enters "Ada Lovelace" and "ada@example.com"
- WHEN the visitor submits
- THEN exactly one `POST /api/reusable-links/redeem` with body `{"link_token": "<token>",
  "display_name": "Ada Lovelace", "email": "ada@example.com"}` is made, the returned JWT is
  stored with `entry: 'reusable'`, and the browser is navigated to `/interview/session` with
  `replace: true`
- AND the token is nowhere in the address bar or history

#### Scenario: The fragment is stripped before any request

- GIVEN the page mounts with a fragment
- WHEN the network and `history` calls are ordered
- THEN `history.replaceState` removing the fragment happens before the form is shown and before
  any redemption request, `history.state` is preserved apart from a `current` that carried the
  fragment (which is cleaned), and no history entry is added

#### Scenario: The plugin strips the fragment before the router can write it back

- GIVEN the built application opened at `/interview/reusable#beai_rl_<43 chars>` and at
  `/unsupported#beai_rl_<43 chars>` (the SA-11 redirect)
- WHEN the application has started
- THEN the address bar and `history.state` hold no fragment on either route, and the plugin
  declares `order: -50` in object form with no function-form call text anywhere in its file

#### Scenario: A fragment pasted later is stripped and discarded

- GIVEN the application is running on any route
- WHEN a `#beai_rl_...` fragment appears through a same-document navigation
- THEN it is stripped from the address bar AND from `history.state.current`, no history entry
  keeps it, it is discarded, and it is never redeemed from there, including by a later in-app
  navigation to the entry route

#### Scenario: Always a new visitor, never the previous one

- GIVEN a stored, unexpired session (reusable or single-use) from a previous visitor
- WHEN `/interview/reusable#<token>` is opened
- THEN the stored session is cleared before the form is shown and the resulting session, after
  submit, belongs to the newly created visitor, with no `POST /start` resume of the old one

#### Scenario: Reload after the strip resumes the stored reusable session

- GIVEN the visitor is on the session route (or reloads `/interview/reusable` with no fragment)
  and holds an unexpired session with `entry: 'reusable'`
- WHEN the page loads
- THEN no redemption request is made and the visitor is routed to the session route and resumes
  through `POST /start`

#### Scenario: A single-use session is not resumed here

- GIVEN no fragment, no "form shown" marker and a stored unexpired session WITHOUT `entry:
  'reusable'`
- WHEN `/interview/reusable` is opened
- THEN the terminal `link_invalid` state is shown and no network call is made

#### Scenario: No fragment and no session is terminal

- GIVEN no fragment, no "form shown" marker and no stored session (or an expired one, purged on
  read)
- WHEN `/interview/reusable` is opened
- THEN the terminal `link_invalid` state is shown, with no retry control, no form and no
  network call

#### Scenario: A malformed fragment is terminal without a form or a request

- GIVEN `/interview/reusable#beai_rl_short`
- WHEN the page mounts
- THEN the terminal `link_invalid` state is shown, no identity form is shown and no request is
  made

#### Scenario: 404 is link_invalid

- GIVEN the form was submitted and the redemption returns 404 (unknown, malformed or disabled
  link)
- WHEN the response is handled
- THEN the terminal `link_invalid` state is shown with no retry control and the typed identity
  is discarded

#### Scenario: 403 uses the existing exchange-403 handling

- GIVEN the redemption returns 403 with a generic body
- WHEN the response is handled
- THEN the candidate is redirected to a validated https `redirect_url` when there is one, and
  otherwise sees the same terminal generic screen as an exchange 403, and no gate detail

#### Scenario: 422 maps onto the fields with the app's own copy

- GIVEN the redemption returns 422 with `errors.email` (and separately `errors.display_name`)
- WHEN the response is handled
- THEN the form stays on screen with the typed values kept, the localized message of the
  frontend is shown under the named field with `aria-invalid` and `aria-describedby`, the
  server's message text is not rendered, and focus moves to the first invalid field

#### Scenario: A 422 that names no known field is a retryable failure

- GIVEN the redemption returns 422 with an `errors` object that names neither `display_name`
  nor `email`, or no `errors` at all
- WHEN the response is handled
- THEN the "failed" state is shown with its Retry control, no field error is invented, and the
  server's message text is not rendered

#### Scenario: 409 is an email-field error and the form stays usable

- GIVEN the redemption returns 409 `{"message": "duplicate_enrolment"}`
- WHEN the response is handled
- THEN the localized duplicate message is shown under the email field, the form stays editable,
  the held token is kept, and no navigation or session write occurs
- AND correcting the email and submitting again sends a new redemption with the held token

#### Scenario: 429 and failures are retryable, not link_invalid

- GIVEN the redemption returns 429, 502 or fails at the network layer
- WHEN the response is handled
- THEN the inline retryable state is shown (busy for 429, failed otherwise), never
  `link_invalid`
- AND Retry re-sends the redemption with the held token and the held identity, and neither is
  written to the URL, storage or history

#### Scenario: One submit is one request

- GIVEN the form is valid
- WHEN the visitor double-clicks Submit, presses Enter repeatedly, or a re-render or hydration
  re-run occurs
- THEN only one redemption request is made while it is in flight, the submit control is
  disabled and the form is `aria-busy`

#### Scenario: The token and the identity leak nowhere else

- GIVEN a completed redemption
- WHEN the address bar, history state, router query, `localStorage`, `sessionStorage`, the DOM,
  console output and every other network request are inspected
- THEN none contains the token, the typed name or the typed email (the redemption body is the
  only carrier)

#### Scenario: An unsupported browser never shows the form or redeems

- GIVEN a mobile user agent (or a viewport under 1024 px, or Firefox) opens
  `/interview/reusable#<token>`
- WHEN the SA-11 gate runs
- THEN the browser is redirected to `/unsupported`, the address bar holds no fragment, no
  identity form is shown and no redemption request is made

#### Scenario: Localized paths behave identically

- GIVEN `/en/interview/reusable#<token>`
- WHEN it is opened
- THEN the behavior is the same and the copy is English

#### Scenario: The static route outranks the dynamic one

- GIVEN `/interview/reusable`
- WHEN the router resolves it
- THEN `pages/interview/reusable.vue` handles it, `interview/[token].vue` does not, and no `GET
  /api/sso/exchange` is made

#### Scenario: A single-use link is unaffected

- GIVEN a normal `/interview/<sso-link-jwt>` link
- WHEN it is opened after this change
- THEN it behaves exactly as in "Single-use entry-route exchange" and shows no identity form

### Requirement: Reusable Identity Form Content And Validation

After a well-formed token is read and before any redemption, the page MUST show a form that
collects the visitor's full name and email address. Both fields are MANDATORY. The form MUST
carry a short, fixed, localized privacy notice and MUST NOT carry a consent checkbox, a link to
a privacy policy, or tenant-editable text. English notice: "Your name and email are shared with
the organization running this interview so your interview can be identified and requests about
your data can be handled." Italian notice: "Il tuo nome e la tua email sono condivisi con
l'organizzazione che conduce il colloquio, così che il tuo colloquio possa essere identificato
e le richieste relative ai tuoi dati possano essere gestite." (Owner decision OD-2: legal
confirmation of this wording is a recorded follow-up, not a blocker.) The email is accepted as
typed and is not verified: the form MUST NOT promise or request a verification code or
confirmation link.

Client validation runs on submit and, for a field the visitor has touched, on blur. Name: after
trimming it MUST be non-empty and at most 255 characters. Email: after trimming it MUST be
non-empty, at most 255 characters and well-formed as an address; the server remains
authoritative. Invalid fields show a localized per-field message, no request is sent, and focus
moves to the first invalid field. A valid submit sends the trimmed values. The form MUST NOT
persist the typed name or email anywhere (no `localStorage`, `sessionStorage`, cookie, URL,
history, router state) and MUST NOT log them or send them to analytics or error reporting; they
live only in component memory until the redemption succeeds or a terminal state is reached.

(Reconciled with the implementation: a field that already shows an error is re-checked as the
visitor edits it, so the message disappears the moment the value is good and not only on the
next blur; an error that came from the server clears as soon as its field is edited. The inputs
carry no `maxlength`, because a browser would truncate silently and store a different value
than the one typed: the limit is a validation message. The client email check is deliberately
loose: exactly one `@`, no whitespace, a non-empty local part and a domain holding a dot that
has a character before and after it; the server rule stays authoritative and a 422 maps back
onto the field. It is written as a split plus linear tests, because the repository lint rule
refuses a super-linear regular expression. Lengths count code points, as the server counts
them.)

#### Scenario: An empty submit flags both fields and focuses the name

- GIVEN the form is shown and both fields are empty
- WHEN the visitor submits
- THEN both errors are shown at once, "Enter your name." under the name and "Enter your
  email." under the email (Italian: "Inserisci il tuo nome." and "Inserisci la tua email."),
  each invalid field has `aria-invalid="true"` and its `aria-describedby`, focus is on the
  name field, and no request is sent

#### Scenario: Whitespace-only values are empty

- GIVEN the form is shown and both fields hold only spaces
- WHEN the visitor submits
- THEN the values are trimmed before they are checked, so the same two required messages are
  shown, focus is on the name field and no request is sent

#### Scenario: A blank name with the email filled flags only the name

- GIVEN the form is shown, the email is a well-formed address and the name is empty
- WHEN the visitor submits
- THEN only "Enter your name." is shown, the name field is `aria-invalid` and focused, the
  email field has neither `aria-invalid` nor `aria-describedby`, "Enter your email." is
  absent and no request is sent

#### Scenario: A blank email with the name filled flags only the email

- GIVEN the form is shown, the name is filled and the email is empty
- WHEN the visitor submits
- THEN only "Enter your email." is shown, the email field is `aria-invalid` and focused, the
  name field has neither `aria-invalid` nor `aria-describedby`, "Enter your name." is absent
  and no request is sent

#### Scenario: Email format and length are checked

- GIVEN the form is shown
- WHEN the email is `not-an-email`, then 256 characters long, and the name is 256 characters
  long
- THEN each shows its localized message, no request is sent, and a name of 255 characters with
  a well-formed email submits

#### Scenario: Values are trimmed before sending

- GIVEN the visitor types `" Ada Lovelace "` and `" ada@example.com "`
- WHEN the form is submitted
- THEN the request body carries `"Ada Lovelace"` and `"ada@example.com"`

#### Scenario: Validation on blur only for touched fields

- GIVEN an untouched empty name field
- WHEN focus first passes through and leaves another field
- THEN no error appears on the untouched field until it has been blurred or the form is
  submitted

#### Scenario: The privacy notice is shown, with no consent checkbox

- GIVEN the form is shown in English and in Italian
- WHEN the form is inspected
- THEN the notice text above is rendered in the matching language, no checkbox, privacy-policy
  link or consent control exists, and no verification code or confirmation step is offered

#### Scenario: Typed identity is never persisted

- GIVEN the visitor has typed a name and email and the form has been shown, blurred and
  submitted with a 429
- WHEN `localStorage`, `sessionStorage`, cookies, the address bar, history state and console
  output are inspected
- THEN none contains the typed name or email

### Requirement: Reusable Identity Form Is Accessible And Localized

The identity form MUST be operable by keyboard alone and satisfy WCAG 2.1 AA: each input has a
visible `<label>` bound to it; each is `required` and `aria-required="true"`; the form uses
`novalidate` with the script validation above; each invalid field has `aria-invalid="true"` and
an error message element referenced by `aria-describedby`; focus moves to the first invalid
field after a failed submit and after a 422 or 409; every field error, whether produced by the
client or mapped from a 422 or a 409, is rendered in the shared `FieldError` element, which is
a live alert region (`role="alert"`), and the loading state is a polite live region
(`aria-live="polite"`, `aria-busy`); the name input has `autocomplete="name"` and the email
input `type="email"` and `autocomplete="email"` (WCAG 1.3.5); the privacy notice is visible
text above the submit button and is associated with it through `aria-describedby`; the submit
control is a real button, disabled while a request is in flight, and the form is `aria-busy`
while in flight. The localized document title and the visible heading MUST be present and
distinct from the `link_invalid` ones. All visible and assistive text MUST be translated in
`it` and `en` (the project languages; no other locale is required), including labels, messages,
notice, heading, title and the reopen state; no key may be missing in either locale. An
automated accessibility audit (axe) of the form in its pristine, invalid, 409, 422, busy and
failed states MUST report no violation in Chromium and in WebKit.

#### Scenario: Labels, required and autocomplete attributes

- GIVEN the form is rendered
- WHEN the DOM is inspected
- THEN each input has a bound label, `required` and `aria-required`, the name input has
  `autocomplete="name"`, and the email input is `type="email"` with `autocomplete="email"`

#### Scenario: Errors are associated and focused

- GIVEN a failed client validation, and separately a 409
- WHEN the error appears
- THEN the invalid input has `aria-invalid="true"` and `aria-describedby` pointing at its error
  message, and focus is on the first invalid field (the email field for a 409)

#### Scenario: Field errors are announced

- GIVEN a client validation failure, a 422 naming `email`, and a 409
- WHEN each error appears
- THEN it is rendered in a `role="alert"` element that is the `aria-describedby` target of its
  field

#### Scenario: The busy and failed states are notices with a Retry control

- GIVEN a 429, and separately a network failure
- WHEN each is handled
- THEN a notice with its own heading, a message and a Retry control replaces the form, and the
  notice has no axe violation in either browser

#### Scenario: Keyboard-only completion

- GIVEN only the keyboard is used
- WHEN the visitor tabs through the form, fills both fields and presses Enter on the submit
  control
- THEN the redemption is sent once and tab order follows the visual order

#### Scenario: Both locales are complete

- GIVEN the `it` and `en` locale files
- WHEN the identity form keys are compared
- THEN every key exists in both, and the page renders the matching language at
  `/interview/reusable` and `/en/interview/reusable`

#### Scenario: The accessibility audit is clean in both browsers

- GIVEN the form in its pristine, invalid, 409, 422, busy and failed states
- WHEN axe runs in Chromium and in WebKit
- THEN no violation is reported in either

### Requirement: Reusable Reload During The Form Shows A Reopen State

The token exists only in page memory and the stored session was cleared when it was read, so a
reload while the identity form is shown loses the token. This is accepted and is the safe
behavior (the token is never kept in storage, URL or history). To keep the copy true, the page
MUST set a NON-SECRET boolean marker in `sessionStorage` (no token, no name, no email, no URL,
no other data) while the form is shown, and MUST remove it when the visitor leaves the form by
success or by any terminal outcome (`link_invalid`, 403 generic screen or redirect). A load
with NO fragment, NO unexpired `reusable` session and the marker present MUST show a dedicated
terminal reopen state with no form, no retry control and no network call, and MUST NOT show
`link_invalid`. A load with a well-formed fragment starts again at the form (the marker is
simply set again); a load with a stored unexpired `reusable` session resumes it as before and
removes a stale marker. The reopen copy, English: title "Please open the link again", body
"This page was reloaded, so your interview link is no longer here. Open the link again (scan
the QR code or use the message you received) to start."; Italian: title "Apri di nuovo il
link", body "Questa pagina è stata ricaricata, quindi il link del tuo colloquio non è più qui.
Riapri il link (inquadra di nuovo il codice QR oppure usa il messaggio ricevuto) per iniziare."
The reopen state sets a localized document title.

(Reconciled with the implementation: the marker is the single character `1` under the
`sessionStorage` key `beai_reusable_identity_pending`, and an unavailable or throwing storage
degrades to "no marker", so a reload then shows `link_invalid` instead of a crashed page. The
marker is read once and removed by that read. The reopen state is rendered by the terminal
route (`/interview/terminal?reason=link_reopen`, localized path), reached with
`router.replace`. The marker is set when the form is first shown for a fragment and is NOT
touched by the retryable states: it stays set while the busy or failed notice is on screen,
while a Retry is in flight, and when a 422 or a 409 returns the visitor to the form. It is
removed only by a success, a 404, a 403, a resumed session, a malformed fragment, a fresh
fragment (which sets it again for the new form), the read of a reload, or the page being left inside the app. A
200 whose token cannot be stored is also the failed state and leaves it set.)

#### Scenario: Reload while the form is shown

- GIVEN the identity form is shown (marker set) and the visitor reloads the page
- WHEN `/interview/reusable` loads with no fragment and no session
- THEN the reopen state is shown, no form and no retry control, and no network request is made
- AND the typed name and email are gone

#### Scenario: Without the marker the link_invalid state applies

- GIVEN no fragment, no session and no marker
- WHEN the page loads
- THEN the terminal `link_invalid` state is shown, not the reopen state

#### Scenario: The marker carries no secret or personal data

- GIVEN the form is shown with a name and email typed
- WHEN `sessionStorage` is inspected
- THEN the marker exists as a boolean and no stored value contains the token, the name, the
  email or the URL

#### Scenario: The marker is removed when the form is left

- GIVEN the form was shown (marker set)
- WHEN the redemption succeeds, and separately when it ends in 404 or 403
- THEN the marker is absent afterwards

#### Scenario: The marker survives the busy and failed states

- GIVEN the form was shown (marker set) and the redemption ended in 429, and separately in a
  network failure
- WHEN the busy or the failed notice is on screen, and again while a Retry is in flight
- THEN the marker is still set
- AND a reload at that point finds no fragment and no session, so it shows the reopen state,
  not `link_invalid`, because the token held in memory is gone
- AND a Retry that ends in 422 or 409 shows the form again with the marker still set, and a
  Retry that ends in success, 404 or 403 removes it

#### Scenario: Reopening the link starts again at the form

- GIVEN the reopen state is shown
- WHEN the visitor opens the link again with the fragment
- THEN the stored session is cleared, the identity form is shown empty, and the token is held
  in memory only

#### Scenario: The reopen copy is localized

- GIVEN the reopen state at `/interview/reusable` and `/en/interview/reusable`
- WHEN it is rendered
- THEN the Italian and English title and body above are shown and the document title is set

### Requirement: Visitor Identity Is Not Retained After Redemption

After a successful redemption, a terminal outcome, or a navigation away, the typed name and
email MUST be discarded from component state and composables (no module-level cache, no store,
no query cache). Neither value MUST be placed in the candidate session storage, the
`access_token` claims, the session route, or any analytics or error-report payload. The
identity reaches the network only inside the single redemption body per submit.

#### Scenario: Nothing remains after success

- GIVEN a successful redemption and navigation to `/interview/session`
- WHEN the application state and browser storage are inspected
- THEN no module state, store, storage entry or URL holds the typed name or email, and the
  candidate session holds only the access token and the `reusable` entry marker

#### Scenario: Nothing remains after a terminal outcome

- GIVEN the redemption ended in 404
- WHEN the terminal state is shown
- THEN the typed identity is no longer in component state or storage

### Requirement: The Reusable Entry Route Is Not Indexed, Sends No Referrer, And Keeps The Camera And Microphone Policy

The page MUST declare `<meta name="robots" content="noindex, nofollow">` and
`<meta name="referrer" content="no-referrer">`. The Nitro `routeRules` patterns
`/interview/**` and `/en/interview/**` MUST cover `/interview/reusable` and
`/en/interview/reusable` (no `nuxt.config` change is needed, and a test over the declared
patterns pins it) so that the responses carry
`Permissions-Policy: camera=(self) microphone=(self) geolocation=()` together with the three
other headers every interview route sets (`X-Frame-Options: DENY`,
`X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`). No
reusable-specific route rule MAY weaken them.

#### Scenario: The page is noindex and no-referrer

- GIVEN `/interview/reusable` is rendered
- WHEN the document head is inspected
- THEN the robots meta is `noindex, nofollow` and the referrer meta is `no-referrer`

#### Scenario: Default-locale path carries the interview headers

- GIVEN a GET request to `/interview/reusable`
- WHEN the server responds
- THEN `Permissions-Policy` equals `camera=(self) microphone=(self) geolocation=()` and the
  three other interview headers are present with their exact values

#### Scenario: Prefixed-locale path carries the interview headers

- GIVEN a GET request to `/en/interview/reusable`
- WHEN the server responds
- THEN the same four headers are present

### Requirement: The Link Token Never Reaches Error Reports Or Analytics From The Candidate App

The candidate app's Sentry scrubber MUST scrub, from every event at any depth (request URL,
breadcrumbs, transaction and span names, contexts, extras, messages), any string matching
`beai_rl_[A-Za-z0-9_-]{16,}` and any fragment on an `/interview/` route, including data captured
BEFORE the strip (the pageload transaction and first breadcrumb read `location.href`). The
analytics path redaction MUST keep stripping the query and fragment of the interview branch,
which is already analytics-unsafe, and `reusable` is a named interview page for grouping. The
general rule is in `observability`; these scenarios pin the candidate app.

#### Scenario: A pageload event captured before the strip is clean

- GIVEN a Sentry event whose `request.url`, transaction name and first navigation breadcrumb
  contain `https://app.example/interview/reusable#beai_rl_<43 chars>`
- WHEN the event passes through the scrubber
- THEN the fragment and any token-shaped string are absent from every field

#### Scenario: A token-shaped string in any field is replaced

- GIVEN an event whose message, extra data and a nested context contain a token-shaped string
- WHEN it is scrubbed
- THEN each occurrence is replaced by the filtered placeholder and unrelated text is untouched

#### Scenario: Analytics paths drop the fragment

- GIVEN the interview branch route `/interview/reusable#<token>`
- WHEN the analytics path is computed
- THEN the result contains neither the fragment nor the token
### Requirement: Utterance Attribution Retargets At A Competency Boundary Without A Race Window

The client MUST hold a single attribution cursor per interview whose value is the id of the
`InterviewSession` row currently being discussed. The cursor MUST be the only source of the session id for
`POST /utterance`, `POST /end`, `POST /suspend`, `POST /snapshot`, `POST /integrity` (including the resize
and `pagehide` flushes), the composable's exposed `sessionId`, the per-question timer reset and the
proctoring overlay's `session-id`. The provider handle's own `dbSessionId` MUST identify the player only
(its keyed slot) and MUST NOT be used for any of those calls once a continuation can retarget the cursor.
The transcript handler MUST read the cursor at EMIT time, never capture it at wiring time.

The cursor's only mutator MUST both move the cursor and mint the capability required to send the boundary
interaction (an `AdvanceTicket` that cannot be constructed elsewhere), so that the retargeting write is
ordered strictly BEFORE the interaction that causes the new competency. Unsent integrity events MUST be
flushed against the outgoing row before the cursor moves. Across the boundary window the client MUST
`/end` the outgoing row only after every in-flight `/utterance` request has settled (bounded), MUST mute the
candidate's microphone before `/end` and keep it muted until the boundary steering has been acknowledged or has
failed (not merely sent: the `respond` echo arrives after the send and must not meet candidate speech), and MUST
use the outgoing row's id for `/end`.

#### Scenario: The attribution tape posts every utterance under the right row

- GIVEN a scripted event tape `[u1 (CSF), end phrase, u2 (spoken in the mic-muted window), u3 (INN)]`
- WHEN the interview advances from CSF to INN through a continuation
- THEN the multiset of `(session_id, text)` pairs posted is exactly `{(CSF, u1), (INN, u3)}` and `u2` is
  absent because the microphone was muted; against the pre-change code the same tape posts `u3` under CSF

#### Scenario: The cursor write precedes the send

- GIVEN a continuation response for INN
- WHEN the boundary path runs
- THEN the recorded order is `[cursor.advanceTo, sendAppMessage(append_llm_context), sendAppMessage(respond)]`; a
  transcript event fired between the two posts under INN, one fired before the cursor write posts under CSF

#### Scenario: Sending without a ticket does not compile

- GIVEN `sendBoundary(ticket)`
- WHEN a caller passes a string or a hand-built ticket literal
- THEN the TypeScript check fails (pinned by `@ts-expect-error` tests)

#### Scenario: Every session-id reader follows the cursor

- GIVEN the cursor has moved from CSF to INN
- WHEN `/end`, `/suspend`, a snapshot, an integrity flush (including the resize flush), the question-timer
  reset and the proctor overlay each read their session id
- THEN each uses INN's id; and `/end` is never POSTed twice for CSF

#### Scenario: The closing utterance is not lost

- GIVEN the avatar's closing sentence and its `complete` state arrive in the same tick
- WHEN `/end` is about to be called
- THEN the closing utterance's POST has settled first (the shipped drain), including when one POST rejects

### Requirement: Steering Is Acknowledged By The Next Avatar Utterance, Or It Failed

The boundary steering is two data-channel messages sent by the one choke point, `conversation.append_llm_context`
followed by the mandatory `conversation.respond` (verified live 2026-10-09: an append alone leaves the avatar
silent). Tavus provides no acknowledgement event for either. After sending, the Tavus provider MUST treat the
FIRST avatar `conversation.utterance` observed after the send (the provider's de-duplicated `replica`/`pal`
copy) as the acknowledgement. If none arrives within `STEERING_ACK_TIMEOUT_MS` (10 000 ms), or the Daily call
object reports `left-meeting` or `error`, or a send throws, or the call is not in `joined-meeting`, the provider
MUST emit `steering_failed` and MUST NOT send into a call that is not joined. The candidate's microphone MUST
stay muted from before `/end` until the acknowledgement or `steering_failed`. On `steering_failed` the client
MUST unmute the microphone, keep the cursor where it is, and: if the call is still joined, resend the same
steering once; otherwise, or after the second failure, end the NEW competency as `timeout` through
`POST /end` and let the next `/start` issue a fresh conversation (the browser then holds no live handle, so
the server refuses a continuation). The failure of one competency's steering MUST NOT fail the interview.

#### Scenario: An avatar utterance acknowledges the steering

- GIVEN a boundary steering was sent
- WHEN an avatar utterance arrives within the window
- THEN no `steering_failed` is emitted, the ack timer is cleared and the microphone is unmuted

#### Scenario: The microphone stays muted until the acknowledgement

- GIVEN both steering messages were sent and no avatar utterance has arrived yet
- WHEN the window is still open
- THEN the microphone is still muted; it unmutes on the acknowledgement or on `steering_failed`

#### Scenario: No avatar utterance triggers one retry then a timeout

- GIVEN a boundary steering was sent and the call is still joined
- WHEN no avatar utterance arrives within `STEERING_ACK_TIMEOUT_MS`
- THEN `steering_failed` is emitted, the same steering is resent once, and if the second window also
  expires the new competency ends with `ended_reason = 'timeout'` and the interview continues

#### Scenario: A left meeting fails the steering immediately without a send

- GIVEN the Daily call object reports `left-meeting`
- WHEN the boundary path would send
- THEN no `sendAppMessage` call is made and `steering_failed` is emitted

#### Scenario: A send that throws fails the steering

- GIVEN `sendAppMessage` throws
- WHEN the boundary path sends
- THEN `steering_failed` is emitted, the microphone is unmuted and the cursor is unchanged

#### Scenario: The duplicate pal copy is not a second acknowledgement

- GIVEN the avatar utterance arrives as a `replica` event and a `pal` event with the same `inference_id`
- WHEN the provider processes them
- THEN exactly one avatar utterance is emitted, and it is the acknowledgement

### Requirement: The Client Drops Its Own Steering Echo

Tavus echoes a `conversation.respond` back as a `conversation.utterance` with `properties.role: "user"`,
`properties.speech` equal to the text sent, the same `inference_id` as the avatar's reply and a `turn_idx`
(verified live 2026-10-09). The Tavus provider MUST arm a one-shot echo filter when it sends the `respond`. While
armed it MUST hold, without emitting, the first user-role `conversation.utterance` whose normalised text equals the
closed trigger. When the next avatar utterance arrives carrying the same `inference_id`, the held utterance is the
echo: it MUST be discarded, its `inference_id` and `turn_idx` remembered as the steering turn, and any further
user-role copy of that turn dropped. If the acknowledgement window ends without a reply, the held utterance MUST
still be discarded and `steering_failed` raised. A user-role utterance that does not match, or that arrives when
the filter is not armed, MUST be emitted as ordinary candidate speech; a held utterance MUST be released as
candidate speech if the filter disarms without a match. The echo MUST never reach the `transcript` stream and
MUST never be posted to `/utterance`. `inference_id` alone is not a discriminator, because every candidate turn
also shares its `inference_id` with the reply; the microphone staying muted until the acknowledgement is what
guarantees no genuine speech is in flight while the echo arrives.

#### Scenario: The echoed steering text is not posted

- GIVEN the provider sent the fixed `respond` text
- WHEN a user-role utterance with identical text arrives, followed by an avatar utterance with the same `inference_id`
- THEN no `transcript` event is emitted for the user-role utterance and no `/utterance` call is made for it, and
  the avatar utterance is emitted and acknowledges the steering

#### Scenario: A held utterance is dropped even when the reply never comes

- GIVEN the echo was held and no avatar utterance arrives within the window
- WHEN the window expires
- THEN the held utterance is discarded, `steering_failed` is emitted, and nothing reaches `/utterance`

#### Scenario: Candidate speech with other text is untouched

- GIVEN the filter is armed
- WHEN a user-role utterance with different text arrives
- THEN it is emitted as candidate speech

#### Scenario: The same words later are candidate speech

- GIVEN the echo has already been dropped once and the filter is disarmed
- WHEN a later user-role utterance with the same text arrives
- THEN it is emitted as candidate speech

### Requirement: Mechanical Boundary Detection Does Not Depend On LLM Phrase Compliance

Boundary detection MUST NOT depend solely on the avatar reproducing an instructed phrase verbatim. The
client MUST assert the boundary through ONE idempotent function with three inputs: (1) the end/final phrase
spoken by the avatar (`matchesEndPhrase`, a hint); (2) `boundary_due: true` in the `/utterance` 202 body (the
mechanical, server-asserted signal; see `interview-session`); (3) the 300 s per-question timer (the floor,
ending the competency as `timeout`). The function MUST be guarded so a second entrant returns immediately,
a losing concurrent `/end` (`409`) is a no-op, and the boundary ticket is minted at most once per boundary.
The Tavus `continue` directive MUST be routed off `confirmDevices()` onto the boundary path only when the
`/start` response contains `continuation`; with no `continuation` the existing teardown-and-start path
runs. The `end_interview` tool call remains a redundant fourth path. The `matchesEndPhrase` function itself
is unchanged.

#### Scenario: A paraphrased closing line still advances the interview

- GIVEN the avatar concludes a competency with wording that does not match the end phrase
- WHEN a `/utterance` response carries `boundary_due: true`
- THEN `/end` is called, the next `/start` is requested, and the cursor retargets, exactly as on a phrase match

#### Scenario: The literal phrase still fires the boundary

- GIVEN the avatar speaks the instructed end phrase verbatim
- WHEN boundary detection runs
- THEN the boundary fires via the phrase match without needing `boundary_due`

#### Scenario: Two inputs racing cause one boundary

- GIVEN the phrase match and `boundary_due` both fire in the same tick
- WHEN the boundary is asserted
- THEN `/end` is called once, one ticket is minted, and a `409` from a losing call is a no-op

#### Scenario: The 300 s timer is still the floor

- GIVEN neither the phrase nor `boundary_due` ever fires
- WHEN the per-question timer expires
- THEN the competency ends with `ended_reason = 'timeout'` and the interview continues

### Requirement: Re-Entry Paths Never Claim A Continuation

Every path on which the browser no longer holds a live, joined Tavus handle MUST start the next competency
without `live_conversation_id`, so the server issues a fresh conversation: a page reload or remount, a
manual pause and resume, the tab-hidden and network-drop guards, a scheduled pause (SA-04), device
re-check, `retry()`, a bounded re-offer, and embed/public-API mode. A resume MUST NOT assume the conversation
survived the browser leaving the room.

#### Scenario: Reload mid-interview issues fresh

- GIVEN a reload during competency INN of a shared conversation
- WHEN the page re-enters and calls `/start`
- THEN the body has no `live_conversation_id`, the server resumes INN on a fresh ref, and the interview continues

#### Scenario: Pause and resume issue fresh

- GIVEN a manual or scheduled pause
- WHEN the candidate resumes
- THEN no `live_conversation_id` is sent and the response has a fresh handle

### Requirement: Provider Session Ceiling Handover Extends To Tavus

When the `/start` response returns a FRESH handle while a live handle exists, the client MUST run the
shipped crossfade handover regardless of the provider's name; the HeyGen-only gate
(`handle.providerName === 'heygen'`) MUST be removed in favour of that response-shaped predicate, so HeyGen
is unchanged by construction and Tavus crossfades at a ceiling. The Tavus handover bound is armed when the
fresh handle is published as the incoming session (the server fact is only known on the `/start`
response). The client MUST also run a conversation-age timer, armed when the conversation is created,
whose duration is the `conversation_ttl_seconds` returned by the creating `/start` minus a fixed
handover lead (120 s), and, when it fires mid-competency, call `/start` on the still-`in_corso` row
(resume path: fresh ref on the same row) while preserving the remaining question time. If the handover
exceeds its bound it degrades to the existing `transition-panel`, never an error. The candidate MUST NOT lose
the competency in progress, its utterances or its attribution.

#### Scenario: A fresh handle while a live one exists crossfades for Tavus

- GIVEN a live Tavus handle and a `/start` response with a fresh handle and no `continuation`
- WHEN the response is processed
- THEN an incoming handle is published, the bound is armed, and the shipped crossfade runs

#### Scenario: A mid-competency expiry preserves the competency

- GIVEN the conversation ages out while DRV is being answered
- WHEN the age timer fires
- THEN `/start` is called on the `in_corso` DRV row, DRV's row and utterances are preserved on a fresh ref, and the question clock is preserved

#### Scenario: The flag flipped off mid-interview crossfades

- GIVEN a live shared conversation and the server's gate switched off
- WHEN the next `/start` returns a fresh handle
- THEN the client crossfades to it

#### Scenario: An unannounced end of the conversation is handled as a ceiling

- GIVEN Tavus ends a conversation at its limit with no prior warning, and the client's age timer has not fired
  (the observed sequence: `conversation.left`, `system.shutdown`, the avatar's tracks stop, Daily `error`
  "Meeting has ended", `left-meeting`)
- WHEN that sequence arrives while a competency is `in_corso`
- THEN the Tavus provider reports a stop, and the client calls `/start` on the `in_corso` row (fresh ref on the
  same row), preserving the row, its utterances and the remaining question time

#### Scenario: HeyGen's own crossfade is unaffected

- GIVEN a HeyGen interview reaching its session limit
- WHEN its crossfade handover fires
- THEN it behaves exactly as before, and the HeyGen handover suites pass unmodified
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

- GIVEN `interview_max_seconds` has not been returned, or is not a positive finite number
- WHEN the panel renders
- THEN no duration heading, bar, maximum or remaining sentence is shown
- AND the enforcing countdown (the page's only `role="timer"`) stays visible, because the fallback clock still ends the
  interview on expiry and an enforcing timeout MUST never be invisible to the candidate

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

