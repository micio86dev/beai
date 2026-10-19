# Delta for Interview Frontend

Adds a flag-gated `hr_avatar` provider adapter to the provider abstraction. The HeyGen and Tavus
requirements, the factory behavior for them, and the session loop are not changed. The adapter wraps the
`@hr-avatar/sdk` browser library; the SDK's own contract is defined by HR-Avatar and restated here only
where BEAI depends on it.

## ADDED Requirements

### Requirement: The hr_avatar adapter is reachable only behind a runtime flag that is off by default

The runtime flag `NUXT_PUBLIC_HR_AVATAR_ENABLED` (public runtime config `hrAvatarEnabled`) MUST default
to false and MUST be true only when its runtime value is `true` (boolean or the string `'true'`). The
runtime value is the environment string after Nuxt's `destr` coercion, which is case-insensitive for
`true` (amendment A7): the environment values `true`, `TRUE` and `True` therefore enable the flag, while
`1`, `yes`, empty and unset do not (they arrive as `1`, `'yes'` and `''`). Any runtime value other than
`true` or `'true'` MUST count as false.

`ProviderName` MUST gain the value `hr_avatar`, and `createProvider` MUST gain an `hr_avatar` arm that
returns the HR-Avatar adapter only when the flag is true. With the flag false, `createProvider('hr_avatar', false)`
MUST NOT construct the adapter, MUST NOT load the adapter module or `@hr-avatar/sdk`, and MUST fail
closed through the same unknown-provider error path used today for an unexpected `provider` value. The
mock-provider path (`mock === true`) MUST keep precedence over provider names, exactly as today. The
observable behavior of `createProvider` for `heygen`, `tavus` and the mock provider (arguments, return
type, synchronous return, error text) MUST be unchanged.

The client MUST select the adapter solely from the `provider` field of the `/start` response and the
flag; it MUST NOT infer HR-Avatar from any other field.

#### Scenario: Flag off, api answers hr_avatar

- GIVEN `hrAvatarEnabled` is false and `/start` returns `provider: 'hr_avatar'`
- WHEN `createProvider('hr_avatar', false)` is called
- THEN it throws the existing unknown-provider error, no adapter instance is created, and neither the adapter module nor `@hr-avatar/sdk` is imported

#### Scenario: Flag on returns the adapter

- GIVEN `hrAvatarEnabled` is true
- WHEN `createProvider('hr_avatar', false)` is called
- THEN an `InterviewProvider` instance is returned and `@hr-avatar/sdk` is not yet imported

#### Scenario: Only the literal true enables it

- GIVEN the runtime value `hrAvatarEnabled` is `1`, then `'1'`, then `'yes'`, then empty
- WHEN `createProvider('hr_avatar', false)` is called each time
- THEN each call fails closed as in the flag-off case

#### Scenario: Environment casing of true enables it

- GIVEN `NUXT_PUBLIC_HR_AVATAR_ENABLED=TRUE` in the environment, which Nuxt coerces to the boolean `true`
- WHEN `createProvider('hr_avatar', false)` is called
- THEN the adapter is returned, as for `true`

#### Scenario: Mock keeps precedence

- GIVEN `mock` is true and the flag is false
- WHEN `createProvider('hr_avatar', true)` is called
- THEN the mock provider is returned, as for any provider name

#### Scenario: Existing providers are unaffected

- GIVEN the flag is false
- WHEN `createProvider('heygen', false)` and `createProvider('tavus', false)` are called
- THEN they return the HeyGen and Tavus providers exactly as before, and the existing factory test suite passes unedited

#### Scenario: Default path loads no HR-Avatar code

- GIVEN the flag is false and a HeyGen or Tavus interview runs
- WHEN the interview page loads and a session starts
- THEN no chunk containing `@hr-avatar/sdk` is requested

### Requirement: The adapter connects with the start response and exposes the provider contract

The `/start` response of an `hr_avatar` session MUST map to the typed `StartConfig`: `provider_token` to
the client secret, `hr_avatar.base_url` to the HR-Avatar base URL, `hr_avatar.publishable_key` to the
publishable key, plus the existing `end_phrase`, `final_phrase` and `audioDeviceId` fields. `StartConfig`
MUST keep its closed shape (no index signature). The adapter MUST import `@hr-avatar/sdk` by a dynamic
`import()` inside `start()`, reached only on the client, and MUST call the SDK's `connect` with
`{ baseUrl, publishableKey, clientSecret, mount, audioDeviceId, completionPhrases, forwardTranscript }`
where `mount` is the interview page's own video element. `forwardTranscript` MUST be an explicit value from
one named constant that defaults to `false` (BEAI's own utterance rows remain the transcript of record; the
retention decision for transcripts stored in HR-Avatar is open).

The adapter MUST implement the full `InterviewProvider` contract:

- `start` resolves once the SDK has connected.
- `toggleMic`, `setMicMuted` delegate to the SDK microphone controls and keep the adapter's state consistent with the SDK's returned muted state.
- `whenAvatarSilent(maxMs)` delegates to the SDK and never rejects and never waits longer than `maxMs`.
- `stop` ends the SDK conversation, is idempotent, swallows its own errors, and releases media.
- `on` subscribes to `transcript`, `state` and `error`.
- `nudgeWrapUp` MAY be implemented through the SDK's verbatim speech control; if omitted it is a no-op.

The client secret, publishable key and base URL MUST NOT be logged, stored in the DOM, persisted, or
included in any emitted event payload.

#### Scenario: Start config mapping

- GIVEN a `/start` response with `provider: 'hr_avatar'`, `provider_token: 'CS'`, `hr_avatar: {base_url: 'https://hra.test', publishable_key: 'PK'}` and phrases in `question_context`
- WHEN the session builds the start config
- THEN the adapter's SDK `connect` receives `baseUrl 'https://hra.test'`, `publishableKey 'PK'`, `clientSecret 'CS'`, the page's video element as `mount`, and `completionPhrases` containing `end_phrase` and `final_phrase`

#### Scenario: SDK imported lazily inside start

- GIVEN the adapter has been constructed
- WHEN `start()` has not been called
- THEN `@hr-avatar/sdk` has not been imported; it is imported on the first `start()` call

#### Scenario: Selected microphone is applied

- GIVEN the candidate selected a microphone during the device check
- WHEN the adapter connects
- THEN `audioDeviceId` is passed to the SDK

#### Scenario: Transcript forwarding is explicit

- GIVEN the adapter connects
- WHEN the SDK `connect` options are inspected
- THEN `forwardTranscript` is present and equals the named constant, whose default is `false`

#### Scenario: Mic controls follow the SDK

- GIVEN a live adapter with the microphone on
- WHEN `setMicMuted(true)` is called twice, then `toggleMic()` once
- THEN the SDK microphone is muted (the second call is a no-op, not a flip) and then unmuted by the toggle

#### Scenario: whenAvatarSilent is bounded

- GIVEN the SDK silence promise never resolves
- WHEN `whenAvatarSilent(2000)` is awaited
- THEN it resolves no later than 2000 ms and never rejects

#### Scenario: stop is idempotent and quiet

- GIVEN a live adapter whose SDK `end()` rejects
- WHEN `stop()` is called twice
- THEN neither call rejects and the SDK `end()` was attempted once

#### Scenario: Secrets are not exposed

- GIVEN a connected adapter
- WHEN its emitted event payloads, console output and the page DOM are inspected
- THEN none contains the client secret or the publishable key

#### Scenario: Missing join inputs fail before the SDK loads

- GIVEN `provider: 'hr_avatar'` with a missing `hr_avatar` object or empty `provider_token`
- WHEN the adapter starts
- THEN it emits an `error` event with code `sdk_error` and `@hr-avatar/sdk` is never imported

### Requirement: SDK states, transcripts and completion map onto the existing provider events

The adapter MUST map SDK state `connecting` to provider state `connecting`, `live` to `ready`, and `ended`
to `stopped` (or `complete`, below); an SDK `error` state MUST produce an `error` event. Each final SDK
transcript entry (`role` `user` or `avatar`, `text`, `occurredAt`) MUST be emitted as a `transcript` event
with the existing `TranscriptEntry` shape, so the session loop posts it to `POST /utterance` unchanged.
Interim (non-final) entries MUST NOT be emitted as transcript entries.

Completion MUST follow the existing rule of the other providers: the adapter MUST emit `complete` when the
AVATAR's final spoken line contains `end_phrase` or `final_phrase` under accent-, case- and
punctuation-insensitive containment, and MUST NOT complete on the candidate's speech. Both phrases MUST be
non-empty; if either is absent or empty the adapter MUST emit an `error` event immediately (the existing
terminal absent-phrase handling). When the SDK ends with reason `completion_phrase` the adapter MUST emit
`complete`; reasons `user`, `server` and `provider` MUST emit `stopped` without `complete`; reason `error`
MUST emit an `error` event. `complete` MUST be emitted at most once per start.

#### Scenario: State mapping

- GIVEN a mock SDK that emits `connecting`, `live`, `ended`
- WHEN the adapter relays them
- THEN the provider `state` events are `connecting`, `ready`, `stopped` in order

#### Scenario: Final transcripts become utterance inputs

- GIVEN the SDK emits a final avatar line "Buongiorno" and a final user line "Salve"
- WHEN the adapter relays them
- THEN two `transcript` events with roles `avatar` and `user` are emitted and the session loop posts both to `/utterance`

#### Scenario: Interim lines are dropped

- GIVEN the SDK emits an interim avatar line
- WHEN the adapter relays events
- THEN no `transcript` event is emitted for it

#### Scenario: Avatar says the end phrase

- GIVEN `end_phrase = 'Passiamo alla prossima domanda.'`
- WHEN the avatar's final line is "passiamo alla prossima domanda"
- THEN `complete` is emitted exactly once

#### Scenario: Candidate saying the phrase does not complete

- GIVEN the same phrases
- WHEN the candidate's final line contains the end phrase
- THEN no `complete` is emitted

#### Scenario: Absent phrase is terminal

- GIVEN `final_phrase` is empty
- WHEN the adapter starts
- THEN an `error` event is emitted immediately and the session reaches the existing terminal screen (not the retryable error)

#### Scenario: SDK ends by completion phrase

- GIVEN the SDK emits `ended` with reason `completion_phrase`
- WHEN the adapter relays it
- THEN `complete` is emitted

#### Scenario: Unrequested end is stopped, not complete

- GIVEN the SDK emits `ended` with reason `provider`
- WHEN the adapter relays it
- THEN `stopped` is emitted and `complete` is not

### Requirement: The hr_avatar adapter honours provider opacity and reports stable error codes

SDK failures reaching the adapter's `error` event MUST carry a stable, provider-independent `code` and
MUST NOT carry the SDK's raw error text. The code MUST be `origin_not_allowed` when the SDK reports an
origin-allowlist refusal (the BEAI origin is missing from the publishable key's allowed origins, a
documented local wiring step), and `sdk_error` for every other SDK failure, including a failed dynamic
import of the SDK, a failed connect, a network failure and an unmapped error. Any accompanying `message`
MUST be scrubbed of vendor and product identifiers.

Nothing the product renders MUST name HR-Avatar: neither locale file MUST contain `hr-avatar`,
`hr_avatar`, `hravatar` or `hr avatar` (case-insensitive), and the adapter MUST NOT create DOM elements
whose id, class or attributes contain those strings. The existing vendor-name prohibitions are unchanged.

#### Scenario: SDK failure reports sdk_error

- GIVEN the SDK `connect` rejects with an error whose message names HR-Avatar and the base URL
- WHEN the adapter emits `error`
- THEN `code` is `sdk_error` and no serialisation of the payload contains `hr-avatar` or the base URL host

#### Scenario: Origin refusal has its own stable code

- GIVEN the SDK rejects with its origin-not-allowed error
- WHEN the adapter emits `error`
- THEN `code` is `origin_not_allowed`

#### Scenario: Failed SDK import is a stable error

- GIVEN the dynamic import of `@hr-avatar/sdk` rejects
- WHEN `start()` runs
- THEN an `error` event with code `sdk_error` is emitted and `start()` does not leak the rejection text

#### Scenario: Locale files and DOM stay neutral

- WHEN `it.json`, `en.json` and the DOM created by the adapter are inspected
- THEN none contains `hr-avatar`, `hr_avatar`, `hravatar` or `hr avatar`, case-insensitively

### Requirement: An hr_avatar interview runs the standard session loop with a fresh connection per competency

The session loop for an `hr_avatar` session MUST be the existing one: `/start`, `/utterance` posts,
`/integrity` and `/snapshot` flushes, the 5-minute per-question timer, proctoring, `POST /end` with
`ended_reason` in `{completed, timeout}`, and branching exclusively on `next_action`. The client MUST NOT
send `live_conversation_id` for an `hr_avatar` handle, MUST NOT treat the response as a continuation, and
MUST stop the previous adapter before the next `/start`. Between competencies the `continue` branch MUST
use the standard connecting presentation (the HeyGen crossfade handover applies to HeyGen only), and the
adapter MUST be a distinct instance with a distinct SDK connection per competency. A `403` on any endpoint
and a `502` on `/start` MUST behave as for other providers.

#### Scenario: Each competency gets a new connection

- GIVEN an `hr_avatar` interview of two competencies with `next_action = 'continue'`
- WHEN the first ends and the second starts
- THEN the first adapter is stopped, a second `/start` is called, and a second adapter performs its own SDK `connect`

#### Scenario: No continuation field is sent

- GIVEN a live `hr_avatar` handle
- WHEN the client calls the next `POST /start`
- THEN the body contains no `live_conversation_id`

#### Scenario: Timer, proctoring and end behave as before

- GIVEN a live `hr_avatar` question
- WHEN 5 minutes elapse
- THEN `POST /end` is called with `ended_reason = 'timeout'` and the session loop continues per `next_action`, with integrity and snapshot flushes unchanged

#### Scenario: Provider busy on start

- GIVEN `/start` answers 429 `provider_busy` for an `hr_avatar` session
- WHEN the client handles it
- THEN the existing retry rule (3 attempts, 3 seconds backoff) applies

### Requirement: The SDK dependency is recorded, vendored and kept out of the server bundle

`@hr-avatar/sdk` MUST be consumed as a vendored tarball referenced from `frontend/package.json` as a
`file:` dependency, with its integrity recorded in `bun.lock`, so that a clone of `frontend` alone
installs and builds. It MUST be recorded, with its version and peer dependencies, in
`docs/version-catalog.md`. If the tarball cannot be resolved, the Dependency Resolution Policy applies:
stop and report. The SSR build MUST NOT include `@hr-avatar/sdk` in the server bundle, and the adapter
MUST import it only from client-guarded code. `@beai/embed` MUST have no change.

#### Scenario: Bare clone installs and builds

- GIVEN a fresh clone of `frontend` with no sibling repository
- WHEN `bun install` and the build run
- THEN both succeed and `@hr-avatar/sdk` resolves from the vendored tarball

#### Scenario: SSR bundle excludes the SDK

- GIVEN the SSR build completes
- WHEN the server bundle is inspected
- THEN it does not import `@hr-avatar/sdk`

#### Scenario: Version recorded

- WHEN `docs/version-catalog.md` is read
- THEN it lists `@hr-avatar/sdk` with the vendored version and its peer dependencies

#### Scenario: Embed unchanged

- WHEN the change is diffed
- THEN `@beai/embed` has no differences
