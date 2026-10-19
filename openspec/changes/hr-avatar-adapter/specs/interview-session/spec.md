# Delta for Interview Session

Adds `hr_avatar` as a template-only provider next to HeyGen and Tavus, the `hr_avatar` join inputs in the
`POST /start` response, and extends the secret-confinement rule to the HR-Avatar secret key. No existing
HeyGen or Tavus requirement is changed. See `hr-avatar-integration` for the server-side client itself.

## ADDED Requirements

### Requirement: hr_avatar is selected only by a pinned template, never by override, environment or test mode

`InterviewController` MUST gain an explicit `hr_avatar` arm in both its provider-name resolution and its
provider resolution. The resolved provider name for a session MUST be `hr_avatar` if and only if all of
the following hold: the participant is not a test-mode participant, and the project's pinned avatar
template (the template that already wins the precedence chain) has `provider = 'hr_avatar'`.

- A test-mode participant (`beai_test_…`) MUST still always run `mock`, whatever the pinned template is
  (T-TEST-006 is unchanged). No HR-Avatar request is made.
- A `projects.provider_override` value of `hr_avatar` and a `config('interview.provider')` value of
  `hr_avatar` MUST NOT select `hr_avatar`. Such a value MUST be ignored as if it were absent, so the
  chain continues to the next source and ends at the existing default. `hr_avatar` MUST NOT be accepted
  by the validation of `provider_override`.
- The existing `default => HeygenProvider` arm MUST remain, and `hr_avatar` MUST be an explicit arm that
  can never fall into it. Resolving `hr_avatar` MUST NOT construct `HeygenProvider` or `TavusProvider`.
- The existing precedence among pinned template, `provider_override` and the environment default for
  `heygen`, `tavus` and `mock` MUST be unchanged.

#### Scenario: A pinned hr_avatar template selects hr_avatar

- GIVEN HR-Avatar is available and the project is pinned to a template with provider `hr_avatar`
- WHEN `POST /start` is called by a live-mode participant
- THEN the session `provider` is `hr_avatar` and HR-Avatar `POST /v1/conversations` is called

#### Scenario: Test mode still forces the mock provider

- GIVEN the project is pinned to an `hr_avatar` template and the participant is test-mode
- WHEN `POST /start` is called
- THEN the session `provider` is `mock` and no request is sent to HR-Avatar

#### Scenario: provider_override cannot select hr_avatar

- GIVEN a project with no pinned template and a stored `provider_override` of `hr_avatar`
- WHEN the provider name is resolved
- THEN the value is ignored and the environment default (or the existing default) applies, never `hr_avatar`

#### Scenario: The environment default cannot select hr_avatar

- GIVEN `INTERVIEW_PROVIDER=hr_avatar` and a project with no pinned template and no override
- WHEN the provider name is resolved
- THEN the result is `heygen`, the existing default, never `hr_avatar`

#### Scenario: An hr_avatar session never constructs another provider

- GIVEN an `hr_avatar` session is issued
- WHEN the container resolutions are inspected
- THEN neither `HeygenProvider` nor `TavusProvider` was constructed and no request was sent to a HeyGen or Tavus host

#### Scenario: Existing precedence is untouched

- GIVEN a project pinned to a `tavus` template with `provider_override = 'heygen'`
- WHEN the provider name is resolved
- THEN the result is `tavus`, exactly as before

### Requirement: A template pinned to hr_avatar fails closed when HR-Avatar is unavailable

When the project's pinned template has `provider = 'hr_avatar'` and the integration is unavailable (the
environment values were removed after the template was created), `POST /start` MUST fail closed through
the existing interview pre-flight: HTTP 422 `{"error": "interview_configuration_invalid"}` with the reason
`{key: "credentials", code: "provider_key_missing"}`, raised before any session row exists. The session
and the participant MUST NOT be changed: an operator misconfiguration MUST NOT move the candidate to
`errore`. A pinned `hr_avatar` template whose `hr_avatar_config_id` is null MUST fail the same way, with
the reason `{key: "hr_avatar_config_id", code: "avatar_missing"}`. It MUST NOT fall back to
`provider_override`, to the environment default, to HeyGen or to Tavus, MUST NOT send any HTTP request,
and MUST NOT introduce a new error code or status.

#### Scenario: Unavailable integration fails closed

- GIVEN a project pinned to an `hr_avatar` template and `HR_AVATAR_*` unset
- WHEN a live-mode participant calls `POST /start`
- THEN the response is HTTP 422 `interview_configuration_invalid` with the reason `provider_key_missing` on `credentials`
- AND no session row is created, the participant status is unchanged
- AND no HTTP request is sent to any provider host

#### Scenario: No fallback to another provider

- GIVEN the same project also has `provider_override = 'tavus'` and the environment default is `heygen`
- WHEN `POST /start` is called
- THEN neither Tavus nor HeyGen is called and the session provider is never `tavus` or `heygen`

#### Scenario: Test mode is unaffected by unavailability

- GIVEN the same pinned template and a test-mode participant
- WHEN `POST /start` is called
- THEN the session runs on `mock` and succeeds

### Requirement: POST /start carries the HR-Avatar join inputs for hr_avatar sessions only

For a session whose provider is `hr_avatar`, the `201` response of `POST /api/candidate/interview/start`
MUST contain `provider` equal to `hr_avatar`, `provider_token` equal to the conversation's
`client_secret`, and an additional object `hr_avatar` with exactly the members `base_url` (the configured
HR-Avatar base URL) and `publishable_key` (the configured publishable key). `conversation_url` MUST be
null or absent exactly as for a HeyGen session. `question_context` (including `end_phrase`,
`final_phrase`, `prompt_version`, `total_competencies`) and `session_id` MUST be present and unchanged in
meaning.

For every other provider the response MUST NOT contain an `hr_avatar` member, and the body MUST be
byte-identical to the one produced before this change. The composed system prompt and the secret key
MUST NOT appear anywhere in the response.

An `hr_avatar` session MUST NOT receive `conversation_id`, `conversation_ttl_seconds` or `continuation`;
the single-session gate never applies to it, and an inbound `live_conversation_id` MUST be ignored.

#### Scenario: hr_avatar response shape

- GIVEN HR-Avatar answers 201 with `client_secret` `CS_VALUE`, base URL `https://hra.example.test`, publishable key `hra_pk_live_PUB`
- WHEN `POST /start` returns 201
- THEN the body has `provider` `hr_avatar`, `provider_token` `CS_VALUE`, and `hr_avatar` equal to `{base_url: "https://hra.example.test", publishable_key: "hra_pk_live_PUB"}`
- AND the body has no `conversation_id`, `conversation_ttl_seconds` or `continuation`

#### Scenario: Other providers carry no hr_avatar member

- GIVEN HR-Avatar is fully configured and a HeyGen, a Tavus and a mock session
- WHEN each `POST /start` returns 201
- THEN none of the three bodies contains an `hr_avatar` member and each equals its pre-change shape

#### Scenario: Prompt and secret never in the response

- GIVEN an `hr_avatar` session
- WHEN the response body and headers are inspected
- THEN they contain neither the composed prompt text nor the HR-Avatar secret key

#### Scenario: live_conversation_id is ignored

- GIVEN a body containing `live_conversation_id` equal to a ref the participant owns
- WHEN `POST /start` is called for an `hr_avatar` competency
- THEN a fresh conversation is created and the response has no `continuation`

### Requirement: hr_avatar is neither Tavus nor HeyGen in provider-specific branches

Every `InterviewController` branch keyed on a provider name MUST treat `hr_avatar` as belonging to
neither `tavus` nor `heygen`:

- The Tavus single-session gate, conversation plan, continuation grant, shared-ref release, and Tavus
  concurrency self-heal MUST NOT run for `hr_avatar`.
- The HeyGen server-transcript REPLACE at `/end` MUST NOT run for `hr_avatar`.
- No Tavus PAL sync and no HeyGen voice, LLM or context registration MUST run for `hr_avatar`.
- No `InterviewSession` row of an `hr_avatar` session MAY share a `provider_session_ref` with another row,
  and no `conversation_plan` is written.

Each BEAI session issue MUST create exactly one HR-Avatar conversation; each competency therefore runs on
its own conversation.

#### Scenario: No Tavus or HeyGen side effects

- GIVEN an `hr_avatar` interview of three competencies run end to end under `Http::preventStrayRequests()`
- WHEN every `/start` and `/end` completes
- THEN the only outbound hosts are the HR-Avatar base URL, no `conversation_plan` is written, and no two session rows share a `provider_session_ref`

#### Scenario: End keeps live utterances

- GIVEN an `hr_avatar` session with live utterance rows
- WHEN `POST /end` runs
- THEN the rows are kept (no DELETE and re-INSERT) and the status guard, completion count and `next_action` behave as for any provider

#### Scenario: Each competency has its own conversation

- GIVEN a project of three competencies on `hr_avatar`
- WHEN the three `/start` calls complete
- THEN three distinct `POST /v1/conversations` requests were sent and the three rows hold three distinct `conv_…` refs

### Requirement: Reconnecting an hr_avatar session issues a fresh conversation

Because a `client_secret` can be used for one connect only, a RESUME of an `hr_avatar` session that is
`in_corso` (or `pending` without a ref) MUST create a new HR-Avatar conversation through `issue()` and
return its new `client_secret`; it MUST NOT return or reuse the stored reference's secret. The previous
conversation MUST be ended by a best-effort `teardown()` of the persisted ref after the fresh one is
issued, and a teardown failure MUST NOT fail the request. The row MUST be updated with the new ref.

#### Scenario: Resume issues a new conversation and ends the old one

- GIVEN an `hr_avatar` session `in_corso` with ref `conv_OLD`
- WHEN `POST /start` is called again
- THEN a new conversation `conv_NEW` is created, the response carries its `client_secret`, `POST /v1/conversations/conv_OLD/end` is sent, and the row's ref is `conv_NEW`

#### Scenario: Teardown failure on resume is non-fatal

- GIVEN the end request for `conv_OLD` answers 503
- WHEN the resume completes
- THEN the response is still 201 with the fresh conversation

### Requirement: hr_avatar sessions snapshot no BEAI LLM binding and need no cost rate

An `hr_avatar` session MUST record `provider = 'hr_avatar'`, the pinned `avatar_template_id` and
`system_prompt_chars` at `issue()` like any other session. Because the LLM is bound on the HR-Avatar side,
its snapshot MUST be `llm_binding_status = 'unbound'` with a null `llm_model_key`.

The session's live period MUST open at the `in_corso` transition and close at the end of the session,
exactly as for other providers. When no per-minute cost rate is configured for `hr_avatar`, the session
cost estimate MUST be absent and reading the review MUST NOT fail.

#### Scenario: Snapshot is unbound

- GIVEN an `hr_avatar` session is issued
- WHEN the row is read
- THEN `provider` is `hr_avatar`, `llm_binding_status` is `unbound`, `llm_model_key` is null and `avatar_template_id` is the pinned template

#### Scenario: Cost estimate is absent without a rate

- GIVEN a completed `hr_avatar` session with a closed live period and no configured rate for `hr_avatar`
- WHEN its review is read
- THEN the cost estimate is absent and the response is successful

#### Scenario: Live period accounting is unchanged

- GIVEN an `hr_avatar` session that becomes `in_corso` and is later ended
- WHEN its live periods are read
- THEN exactly one period is opened at the `in_corso` transition and closed at the end

## MODIFIED Requirements

### Requirement: Provider API secrets never exposed to the client

Provider secret keys (HeyGen API key, Tavus API key, HR-Avatar secret key) MUST be stored exclusively
in server-side environment/config. No response body, header, or log entry accessible
to the client MUST contain a raw provider secret. The `/start` response MUST contain
only the ephemeral session token or conversation URL issued by the provider. For an `hr_avatar` session
that ephemeral value is the per-conversation `client_secret`, together with the browser-safe HR-Avatar
base URL and publishable key; the HR-Avatar secret key MUST never be returned.
(Previously: named only the HeyGen and Tavus API keys.)

#### Scenario: Response body contains no secret key

- GIVEN HEYGEN_API_KEY = 'sk-secret' in server env
- WHEN `POST /start` returns HTTP 201
- THEN the response body does not contain 'sk-secret' or any substring matching the raw key pattern; it contains only `provider_token` (ephemeral)

#### Scenario: HR-Avatar secret key is not in the hr_avatar start response

- GIVEN `HR_AVATAR_SECRET_KEY = 'hra_sk_live_SECRET'` in server env and an `hr_avatar` session
- WHEN `POST /start` returns HTTP 201
- THEN neither the body nor the headers contain `hra_sk_live_SECRET`; the body contains only the ephemeral `provider_token`, the base URL and the publishable key

#### Scenario: HR-Avatar secret key is not in logs or errors

- GIVEN an HR-Avatar failure whose response echoes the secret key
- WHEN the failure is handled
- THEN no log line, exception message or client-visible error contains the raw key
