# Delta for Interview Frontend

> Rescoped 2026-10-08. MODIFIED requirements keep their main-spec titles exactly and their current full text
> (the HeyGen-only presentation requirement keeps its "(HeyGen only)" title). Nothing is REMOVED.

## MODIFIED Requirements

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
   attribution cursor to the new `session_id` and then sends the boundary interaction over the
   EXISTING Daily data channel (see "Utterance Attribution Retargets At A Competency Boundary
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

## ADDED Requirements

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
candidate's microphone before `/end` and unmute it after the boundary interaction has been sent, and MUST
use the outgoing row's id for `/end`.

#### Scenario: The attribution tape posts every utterance under the right row

- GIVEN a scripted event tape `[u1 (CSF), end phrase, u2 (spoken in the mic-muted window), u3 (INN)]`
- WHEN the interview advances from CSF to INN through a continuation
- THEN the multiset of `(session_id, text)` pairs posted is exactly `{(CSF, u1), (INN, u3)}` and `u2` is
  absent because the microphone was muted; against the pre-change code the same tape posts `u3` under CSF

#### Scenario: The cursor write precedes the send

- GIVEN a continuation response for INN
- WHEN the boundary path runs
- THEN the recorded order is `[cursor.advanceTo, sendAppMessage]`; a transcript event fired between the
  two posts under INN, one fired before the cursor write posts under CSF

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

### Requirement: Steering Is Acknowledged By The Next Replica Utterance, Or It Failed

Tavus provides no acknowledgement for a data-channel interaction. After sending the boundary interaction the
Tavus provider MUST treat the FIRST `conversation.utterance` with `properties.role === 'replica'` observed
after the send as the acknowledgement. If none arrives within `STEERING_ACK_TIMEOUT_MS` (10 000 ms), or the
Daily call object reports `left-meeting` or `error`, or the send throws, or the call is not in
`joined-meeting`, the provider MUST emit `steering_failed` and MUST NOT send into a call that is not joined.
On `steering_failed` the client MUST unmute the microphone, keep the cursor where it is, and: if the call
is still joined, resend the same interaction once; otherwise, or after the second failure, end the NEW
competency as `timeout` through `POST /end` and let the next `/start` issue a fresh conversation (the
browser then holds no live handle, so the server refuses a continuation). The failure of one competency's
steering MUST NOT fail the interview.

#### Scenario: A replica utterance acknowledges the steering

- GIVEN a boundary interaction was sent
- WHEN a `role: 'replica'` utterance arrives within the window
- THEN no `steering_failed` is emitted and the ack timer is cleared

#### Scenario: No replica utterance triggers one retry then a timeout

- GIVEN a boundary interaction was sent and the call is still joined
- WHEN no replica utterance arrives within `STEERING_ACK_TIMEOUT_MS`
- THEN `steering_failed` is emitted, the same interaction is resent once, and if the second window also
  expires the new competency ends with `ended_reason = 'timeout'` and the interview continues

#### Scenario: A left meeting fails the steering immediately without a send

- GIVEN the Daily call object reports `left-meeting`
- WHEN the boundary path would send
- THEN no `sendAppMessage` call is made and `steering_failed` is emitted

#### Scenario: A send that throws fails the steering

- GIVEN `sendAppMessage` throws
- WHEN the boundary path sends
- THEN `steering_failed` is emitted, the microphone is unmuted and the cursor is unchanged

### Requirement: The Client Drops Its Own Steering Echo

If the boundary interaction includes a `conversation.respond` trigger, the Tavus provider MUST remember the
exact trigger text it sent and MUST drop, once, the first user-role `conversation.utterance` whose
normalised text equals it, so the platform's own steering text is never emitted on the `transcript` stream
and never posted to `/utterance` as candidate speech. Genuine candidate speech MUST be unaffected. The real
shape of any echo (role, `inference_id`) is verified only by the authorized live spike (L4).

#### Scenario: An echoed steering text is not posted

- GIVEN the provider sent the fixed `respond` text
- WHEN a user-role utterance with identical text arrives
- THEN no `transcript` event is emitted for it and no `/utterance` call is made

#### Scenario: Candidate speech that merely resembles the trigger is kept after the first match

- GIVEN the echo has already been dropped once
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

#### Scenario: HeyGen's own crossfade is unaffected

- GIVEN a HeyGen interview reaching its session limit
- WHEN its crossfade handover fires
- THEN it behaves exactly as before, and the HeyGen handover suites pass unmodified
