# HR-Avatar Integration Specification

## Purpose

Defines BEAI's server-side client of HR-Avatar, the standalone avatar conversation engine extracted
from BEAI: when the integration is available, how an interview session is mapped onto an HR-Avatar
conversation, how failures are classified, how the secret key is confined, how a BEAI administrator
browses HR-Avatar avatar configs, and how existing templates are exported to HR-Avatar.

The integration is a deliberate, opt-in third provider (`hr_avatar`) next to Tavus and HeyGen. It is
additive and dark by default: with HR-Avatar unconfigured, BEAI behaves exactly as it did before this
change (see "Default path invariance").

The HR-Avatar contract is binding as written in `hr-avatar/openspec/changes/hr-avatar-engine/`;
where its specs and design differ, `reconciliation.md` wins. This specification restates only what
BEAI depends on:

- API under `/v1`; errors are RFC 9457 Problem+JSON with a stable `code`.
- Server calls authenticate with the secret key as `Authorization: Bearer <secret key>`.
- `POST /v1/conversations` creates a conversation in status `created` and returns its `id`
  (`conv_` + ULID) and a one-time `client_secret`. It makes no provider call.
- `POST /v1/conversations/{id}/end` is idempotent (200 on an already terminal conversation).
- `GET /v1/avatar-configs` is paginated (`limit` 1 to 100, opaque `cursor`, body `{data, next_cursor}`)
  and requires scope `avatar_configs:read`. `POST /v1/avatar-configs` requires `avatar_configs:write`.
- The `client_secret` is a short-lived, single-connect browser credential. A second connect for the
  same conversation is refused (`already_connected`), so one BEAI session issue maps to one
  conversation and one browser connect.

## Out of Scope

- Making `hr_avatar` the default provider, migrating projects, or changing Tavus/HeyGen code.
- Conversation continuation across competencies (`sendContext`), Tavus-style boundary steering, and any
  single-session behaviour for `hr_avatar`: each issued BEAI session is one HR-Avatar conversation.
- Consuming HR-Avatar outbound webhooks.
- Platform (superadmin) templates, `ProviderSmokeCheck`, and `provider_override` support for `hr_avatar`.
- Any change to `@beai/embed`.

## Requirements

### Requirement: The integration is available only when all three settings are present

BEAI MUST read the integration settings from one configuration file, fed by the environment values
`HR_AVATAR_BASE_URL`, `HR_AVATAR_SECRET_KEY` and `HR_AVATAR_PUBLISHABLE_KEY`. The integration MUST be
reported as **available** if and only if all three values are non-empty after trimming and the base URL
is an absolute `http` or `https` URL. In every other case it MUST be reported as **unavailable**.

Availability MUST be evaluated from configuration only. Computing it MUST NOT perform any network
request. There MUST be exactly one place that answers "is HR-Avatar available", and every consumer
(provider selection, template validation, field specs, catalogue, export command) MUST use it.

An unavailable integration MUST be inert: it MUST NOT be offered as a template provider, MUST NOT appear
in field specs, MUST NOT be reachable through the catalogue, and MUST NOT cause any outbound request.

#### Scenario: All three settings present

- GIVEN `HR_AVATAR_BASE_URL=https://hra.example.test`, a non-empty secret key and a non-empty publishable key
- WHEN availability is evaluated
- THEN the integration is available and no HTTP request was made

#### Scenario: Any single missing setting makes it unavailable

- GIVEN the base URL and publishable key are set and the secret key is unset
- WHEN availability is evaluated
- THEN the integration is unavailable
- AND the same holds when only the base URL is missing, and when only the publishable key is missing

#### Scenario: Blank or malformed values count as missing

- GIVEN the secret key is whitespace only, or the base URL is `not a url`
- WHEN availability is evaluated
- THEN the integration is unavailable

#### Scenario: Nothing set is the default state

- GIVEN none of the three environment values is set (a fresh install)
- WHEN the application boots and serves requests
- THEN the integration is unavailable and no HTTP request to any HR-Avatar host is ever made

### Requirement: The secret key never leaves the server

`HR_AVATAR_SECRET_KEY` MUST be used only by BEAI's server-to-server HR-Avatar client. It MUST NOT appear
in any HTTP response body or header, in any API Resource, in the template export/import document, in the
OpenAPI document or its examples, in any log line, exception message, or report, and in any output of the
export command.

The publishable key and the base URL are browser-safe values. They MUST be returned only in the
`POST /candidate/interview/start` response of an `hr_avatar` session (see `interview-session`) and
MUST NOT appear in field specs, catalogue responses, template resources, or the export document.

The per-conversation `client_secret` is a browser credential issued once. BEAI MUST return it to the
candidate's browser in the `/start` response of the session that issued it and MUST NOT persist it
(database, cache, queue payload, log) anywhere. Only the `conv_…` conversation id MAY be persisted, as
the session's `provider_session_ref`.

#### Scenario: Secret key absent from every response

- GIVEN `HR_AVATAR_SECRET_KEY=hra_sk_live_SECRETVALUE` and an `hr_avatar` interview
- WHEN `POST /start`, the catalogue proxy, the field-specs endpoint, the template list, the template export
  and the outline endpoint respond
- THEN no body or header of any of them contains `hra_sk_live_SECRETVALUE`

#### Scenario: Secret key redacted from diagnostics

- GIVEN HR-Avatar answers an error whose Problem+JSON `detail` echoes the secret key
- WHEN the failure is logged and the exception message is built
- THEN neither contains the raw key nor any part of `detail` (the provider never reads `detail`)

#### Scenario: Client secret is returned once and never stored

- GIVEN `POST /v1/conversations` returned `client_secret` `CS_VALUE` and id `conv_01ABC`
- WHEN `/start` completes
- THEN the response `provider_token` equals `CS_VALUE`
- AND `interview_sessions.provider_session_ref` equals `conv_01ABC`
- AND `CS_VALUE` appears in no database row, cache entry, queued job payload or log line

#### Scenario: Publishable key confined to the hr_avatar start response

- GIVEN HR-Avatar is available
- WHEN field specs, the catalogue, a template resource and the export document are read
- THEN none contains the publishable key or the base URL

### Requirement: Issuing a session creates one HR-Avatar conversation

`HrAvatarProvider` MUST implement `ProviderSessionService` under the provider name `hr_avatar`.
`issue()` MUST send exactly one `POST {HR_AVATAR_BASE_URL}/v1/conversations` with the secret key as the
bearer credential and a JSON body of exactly these members:

| Member | Value |
|---|---|
| `avatar_config_id` | the `hr_avatar_config_id` of the template that selected this provider for the session |
| `system_prompt` | the composed system prompt, sent unchanged |
| `opening_text` | the composed opening text, sent unchanged |
| `language` | the project language, a two-letter lowercase code matching `^[a-z]{2}$` |
| `max_duration_seconds` | an integer between 30 and 3600 inclusive: the session ceiling BEAI already derives for the session (`SessionLiveClock::resolveMaxSeconds()`, today 1200 for `hr_avatar`, whose templates carry no duration knob), clamped into that range |
| `external_ref` | an opaque reference that is a pure function of the BEAI `InterviewSession` id, at most 255 characters |
| `metadata` | the empty JSON object, serialized as `{}` (never as the empty array `[]`) |

`issue()` MUST NOT send any other member, MUST NOT contain a template `display_name`, and MUST NOT call
any other HR-Avatar endpoint. It MUST return a `ProviderToken` whose `token` is the response
`client_secret` and whose `provider_session_ref` is the response `id`. The provider name carried by the
token MUST be `hr_avatar`.

If the response is not a 201 carrying a `conv_`-prefixed `id` and a non-empty `client_secret`, `issue()`
MUST fail as an upstream failure and MUST NOT return a token.

#### Scenario: Request body is exactly the contract shape

- GIVEN a session for a project with language `it`, an `hr_avatar` template with `hr_avatar_config_id`
  `avc_01XYZ`, and a composed prompt and opening text
- WHEN `issue()` runs under `Http::fake`
- THEN exactly one `POST /v1/conversations` is sent with a bearer secret key
- AND its JSON body has exactly the members `avatar_config_id`, `system_prompt`, `opening_text`, `language`,
  `max_duration_seconds`, `external_ref`, `metadata`
- AND `avatar_config_id` is `avc_01XYZ`, `language` is `it`, and `metadata` serializes as `{}`

#### Scenario: Token maps the conversation id and client secret

- GIVEN HR-Avatar answers 201 with `id` `conv_01ABC` and `client_secret` `CS_VALUE`
- WHEN `issue()` returns
- THEN the `ProviderToken` has `token` `CS_VALUE`, `provider_session_ref` `conv_01ABC` and provider `hr_avatar`

#### Scenario: Duration is clamped into the contract range

- GIVEN the derived session ceiling is 10 seconds, and separately 99999 seconds
- WHEN `issue()` builds the body
- THEN `max_duration_seconds` is 30 in the first case and 3600 in the second

#### Scenario: external_ref is opaque and carries no candidate data

- GIVEN a candidate with a known display name, email and `candidate_ref`
- WHEN `issue()` builds the body
- THEN `external_ref` is derived only from the `InterviewSession` id
- AND no member of the request body, header or query string contains the candidate's name, email or `candidate_ref`

#### Scenario: Template display name is never sent

- GIVEN the template carries `persona.display_name = "Giulia"`
- WHEN `issue()` runs
- THEN no member of the outbound request contains `Giulia`

#### Scenario: Malformed success response is an upstream failure

- GIVEN HR-Avatar answers 201 without a `client_secret`, or with an `id` not starting with `conv_`
- WHEN `issue()` runs
- THEN it fails as an upstream failure and no token is returned

#### Scenario: The prompt is not truncated

- GIVEN a composed system prompt longer than 32000 characters, or an opening text longer than 4000 characters
- WHEN `issue()` runs
- THEN no request is sent, the failure is classified as a client contract error, and the prompt is not shortened

#### Scenario: Missing config id is a client contract error

- GIVEN the selecting template has a null `hr_avatar_config_id`
- WHEN `issue()` runs
- THEN no request is sent and the failure is classified as a client contract error

### Requirement: HR-Avatar failures map onto BEAI's existing provider failure classes

`HrAvatarProvider` MUST classify every failure into the existing `ProviderFailureClass` values so that
`InterviewController::handleProviderFailure()` and its failure matrix apply unchanged:

| HR-Avatar outcome | Class | `/start` effect (existing matrix) |
|---|---|---|
| HTTP 429 | Throttle | 429 `{error: "provider_busy"}`, session stays `pending`, participant unchanged |
| HTTP 4xx other than 429 (including 401, 403, 404, 409, 422) | ClientError | HTTP 500, participant unchanged |
| HTTP 5xx, timeout, connection failure, or a response that is not valid JSON | Upstream | HTTP 502 `provider_error`, session `error`, participant `errore` |

Exceptions raised by the provider MUST carry only a generic message plus the HTTP status class and, when
present, the Problem+JSON `code`. The message MUST NOT include the response body, the request body, the
system prompt, the `client_secret`, or the secret key. BEAI MUST NOT introduce a new HTTP status or error
code for these failures.

#### Scenario: Rate limit is retryable

- GIVEN HR-Avatar answers 429 to `POST /v1/conversations`
- WHEN `POST /start` runs
- THEN the response is 429 `{"error":"provider_busy"}`, the session remains `pending` and the participant is not set to `errore`

#### Scenario: A contract error does not blame the candidate

- GIVEN HR-Avatar answers 422 `validation_failed`
- WHEN `POST /start` runs
- THEN the response is HTTP 500, the participant status is unchanged and the session is not marked as an upstream failure

#### Scenario: An upstream failure uses the existing hard-failure path

- GIVEN HR-Avatar answers 503
- WHEN `POST /start` runs
- THEN the session status is `error`, the participant is `errore` and the response is HTTP 502

#### Scenario: Timeout is upstream

- GIVEN the HTTP request to HR-Avatar times out
- WHEN `issue()` runs
- THEN the failure is classified as upstream

#### Scenario: Diagnostics carry the code but no payload

- GIVEN HR-Avatar answers 409 with `code` `config_not_synced` and a body echoing the system prompt
- WHEN the failure is logged and raised
- THEN the log context and exception message contain `config_not_synced` and the status class
- AND neither contains any part of the system prompt

### Requirement: Teardown ends the conversation and never throws

`teardown()` MUST call `POST {HR_AVATAR_BASE_URL}/v1/conversations/{id}/end` once for the token's
`provider_session_ref`, authenticated with the secret key. It MUST treat HTTP 2xx as success (an already
terminal conversation answers 200). It MUST NEVER throw: a 4xx, 5xx, timeout or connection failure MUST be
logged without the secret key and swallowed. A null, empty or non-`conv_` reference MUST result in no
request.

`teardown()` MUST be invoked from the same points of the interview flow as for the other providers
(reconnect of a live session, compensation after a database failure following provider success, session
end, and the abandoned-interview sweep).

#### Scenario: Teardown ends the conversation

- GIVEN a token for `conv_01ABC`
- WHEN `teardown()` runs
- THEN exactly one `POST /v1/conversations/conv_01ABC/end` is sent

#### Scenario: Teardown is idempotent and silent on failure

- GIVEN HR-Avatar answers 404, then 503, then times out on three successive teardowns
- WHEN each `teardown()` runs
- THEN none throws and each logs a failure without the secret key

#### Scenario: A malformed reference sends nothing

- GIVEN a reference that is null or `abc`
- WHEN `teardown()` runs
- THEN no HTTP request is made

#### Scenario: Compensation after a database failure ends the new conversation

- GIVEN `issue()` succeeded and the following database write fails
- WHEN the compensation path runs
- THEN `teardown()` receives the in-memory token returned by `issue()` and posts `/end` for its `conv_…` id

#### Scenario: No listing and no ending of other conversations

- GIVEN any `hr_avatar` session issue or teardown
- WHEN the outbound requests are inspected
- THEN none lists conversations and none ends a conversation other than this session's own

### Requirement: BEAI remains the transcript of record

`reconcileTranscript()` of `HrAvatarProvider` MUST return an empty list. BEAI's own utterance rows,
posted by the browser during the interview, MUST remain the transcript used for scoring: the interview end
path MUST keep them unchanged for an `hr_avatar` session and MUST NOT delete and re-insert them.
`HrAvatarProvider` MUST NOT fetch a transcript from HR-Avatar.

#### Scenario: Live utterances survive the end of an hr_avatar session

- GIVEN an `hr_avatar` session with 6 live utterance rows
- WHEN `POST /end` completes with `ended_reason = completed`
- THEN the same 6 rows remain and no transcript request is sent to HR-Avatar

#### Scenario: Scoring input is unchanged

- GIVEN a participant whose competencies ran on `hr_avatar`
- WHEN scoring reads the transcript
- THEN it reads BEAI's `utterances` rows exactly as for any other provider

### Requirement: The avatar-config proxy lists only the caller organization's configs

The existing admin-only endpoint `GET /api/avatar-templates/catalogue` MUST accept `provider=hr_avatar`
with `resource=avatar_config` when, and only when, the integration is available. It MUST list HR-Avatar
avatar configs by calling `GET /v1/avatar-configs` with the secret key, following `next_cursor` until the
list is exhausted or a bound of 10 pages of 100 is reached, and MUST return the existing `{status, items}`
shape with every item in the existing catalogue entry shape (`id`, `provider`, `label`, `name`,
`language`, `locale`, `accent`, `italian`, `preview_image_url`, `preview_audio_url`,
`preview_audio_via_api`, `preview_video_url`), where `id` is the config's `avc_…` id, `provider` is
`hr_avatar`, `label` and `name` are its name, `preview_audio_via_api` is false, and every other member is
`null`.

Only configs usable for a new conversation (`sync_status` of `synced` or `not_required`) MUST be listed.

The HR-Avatar account is shared by all BEAI organizations, so the proxy MUST apply tenant attribution:
it MUST return only configs whose `external_ref` equals the attribution value of the caller's
organization. The attribution value MUST be an opaque, stable function of the organization id, MUST
contain no organization name or other personal data, and is the value the export command writes (see
below). Configs without that attribution MUST NOT be returned to any tenant admin.

A proxy failure MUST degrade exactly as the existing catalogue does: HTTP 200 with `status`
`provider_error`, an empty `items` list and a stable `code` (`provider_unauthorized`,
`provider_rate_limited`, `provider_unavailable` or `provider_bad_response`), never a 500 and never any
HR-Avatar error text. A successful empty result MUST report `status` `empty`. The endpoint MUST keep the
existing caching discipline (server-side cache per provider, resource and organization, with a TTL, so
that repeated opening of the form does not re-call HR-Avatar). An unavailable integration MUST answer
`provider=hr_avatar` with 422, exactly like an unknown provider value. Only `admin` users may call it.

#### Scenario: Admin lists their organization's configs

- GIVEN the integration is available and HR-Avatar holds three synced configs attributed to organization A
- WHEN an admin of organization A calls `GET /api/avatar-templates/catalogue?provider=hr_avatar&resource=avatar_config`
- THEN the response is 200, `status` is `ok` and `items` has three entries in the existing catalogue entry shape with `id` starting `avc_` and `provider` `hr_avatar`

#### Scenario: Cross-tenant isolation of the proxy

- GIVEN HR-Avatar holds a config attributed to organization B and one attributed to organization A
- WHEN an admin of organization A calls the proxy
- THEN only organization A's config is returned and organization B's id and label appear nowhere in the response

#### Scenario: Unattributed configs are not listed

- GIVEN a config with no `external_ref`
- WHEN any tenant admin calls the proxy
- THEN it is not returned

#### Scenario: Unsynced configs are not offered

- GIVEN an attributed config with `sync_status` `pending` and another with `failed`
- WHEN the proxy lists configs
- THEN neither is returned

#### Scenario: Pagination is followed

- GIVEN HR-Avatar answers the first page with a `next_cursor` and a second page without one
- WHEN the proxy runs
- THEN both pages are requested and their attributed items are merged

#### Scenario: Upstream failure degrades without leaking

- GIVEN HR-Avatar answers 503 with a body containing the secret key
- WHEN the proxy runs
- THEN the response is 200 with `status` `provider_error`, `items` `[]`, `code` `provider_unavailable`, and the body contains neither the secret key nor HR-Avatar's error text

#### Scenario: Repeated requests are cached

- GIVEN a successful proxy result is cached for organization A
- WHEN the same request is made again within the TTL
- THEN no request reaches HR-Avatar

#### Scenario: Operator and viewer are refused

- GIVEN a user with the `operator` or `viewer` role
- WHEN they call the proxy
- THEN the response is 403

#### Scenario: Unavailable integration is an unknown provider

- GIVEN the integration is unavailable
- WHEN an admin calls the catalogue with `provider=hr_avatar&resource=avatar_config`
- THEN the response is 422 and no HTTP request is made

### Requirement: Templates are exported to HR-Avatar by an explicit, dry-run-by-default command

The command `php artisan hr-avatar:export-templates` MUST read the existing `avatar_templates` of every
organization and prepare one HR-Avatar avatar config per eligible template. A template is eligible when
its provider is `tavus` or `heygen`, it belongs to an organization (platform templates are skipped), and
its `hr_avatar_config_id` is null. A template that already has an id MUST be reported as already linked
and MUST NOT be processed again.

**Dry run (default).** Without `--apply` the command MUST make no HTTP request to any host, MUST NOT write
to the database, and MUST print for each template its id, organization id, provider, intended config name
and outcome (`would_create` or `already_linked`), plus a final count. It MUST work when the integration is
unavailable.

**Apply.** With `--apply` the command MUST require the integration to be available (otherwise it MUST
exit with a non-zero status naming the missing environment variables by name, never by value, and write
nothing). For each eligible template it MUST `POST /v1/avatar-configs` with the secret key, creating a
config with the template's provider, a name derived from the template name, the template configuration
mapped to HR-Avatar's field names, and `external_ref` set to the owning organization's attribution value.
On success it MUST write the returned `avc_…` id to that template's `hr_avatar_config_id` and to no other
column: no other column of the row, including `updated_at` and `is_active`, MAY change. On failure of one
template it MUST report that template as `failed` with a stable code, MUST NOT write its row, MUST continue
with the remaining templates, and MUST exit non-zero.

The command MUST NOT delete, deactivate, or modify any other BEAI row or column, MUST NOT change any
template's provider, MUST NOT transfer provider credentials or API keys, MUST NOT transfer the BEAI LLM
binding, and MUST NOT transfer `persona.display_name`. Running `--apply` twice MUST NOT create a second
config for a template already linked.

#### Scenario: Dry run writes nothing and calls nothing

- GIVEN three eligible templates and `Http::preventStrayRequests()`
- WHEN the command runs without `--apply`
- THEN no HTTP request is made, no `avatar_templates` row changes, and the output lists three `would_create` lines

#### Scenario: Dry run works without HR-Avatar configured

- GIVEN the integration is unavailable
- WHEN the command runs without `--apply`
- THEN it lists the plan and exits 0

#### Scenario: Apply refuses when unavailable

- GIVEN the integration is unavailable
- WHEN the command runs with `--apply`
- THEN it exits non-zero, names the missing variables by name only, sends no request and writes nothing

#### Scenario: Apply links templates and writes only the config id

- GIVEN two eligible templates and HR-Avatar answering 201 with `avc_A` and `avc_B`
- WHEN the command runs with `--apply`
- THEN `avatar_templates.hr_avatar_config_id` is `avc_A` and `avc_B` respectively
- AND every other column of both rows, including `updated_at`, `is_active` and `provider`, is byte-identical to before

#### Scenario: Apply attributes each config to the template's own organization

- GIVEN a template of organization A and a template of organization B
- WHEN the command applies
- THEN the config created for the first carries organization A's attribution as `external_ref` and the second carries organization B's, never crossed

#### Scenario: Idempotent re-run

- GIVEN a template already linked by a previous apply
- WHEN the command runs with `--apply` again
- THEN it reports `already_linked` and sends no create request for it

#### Scenario: One failure does not stop the rest

- GIVEN HR-Avatar rejects the first template with 422 and accepts the second
- WHEN the command applies
- THEN the first is reported `failed` and keeps a null id, the second is linked, and the exit status is non-zero

#### Scenario: Credentials and bindings are not transferred

- GIVEN a template bound to an LLM credential and carrying `persona.display_name`
- WHEN the command applies
- THEN no request body contains any provider API key, LLM credential, LLM binding, or the display name

#### Scenario: Platform templates are skipped

- GIVEN a platform template with no organization
- WHEN the command runs in either mode
- THEN it is not listed as eligible and no config is created for it

### Requirement: Default path invariance

With HR-Avatar unavailable (`HR_AVATAR_*` unset) and the frontend flag `NUXT_PUBLIC_HR_AVATAR_ENABLED`
unset or false, every existing behavior of BEAI MUST be unchanged. In particular:

- The `POST /candidate/interview/start` response of a Tavus, HeyGen or mock session MUST be
  byte-identical to the response produced before this change for the same input.
- `GET /api/avatar-templates/field-specs` MUST return exactly the same object as before (keys `heygen` and `tavus` only).
- `GET /api/avatar-templates/catalogue` MUST behave exactly as before for every existing provider and resource, and `provider=hr_avatar` MUST be rejected.
- The avatar template resource and the template export document MUST be unchanged for every template whose `hr_avatar_config_id` is null (the member is omitted when null).
- The provider-selection result for every existing project, participant and configuration combination MUST be unchanged, and no request is ever sent to an HR-Avatar host.
- The committed OpenAPI document MAY change only additively on the start, template, field-spec and catalogue endpoints (new optional members and new enum or query values); no existing member MAY be removed, renamed, retyped or made required. One disclosed exception (amendment A6): the organization template store body's `config` changes from required to required unless `provider` is `hr_avatar` (`required_unless:provider,hr_avatar`). For `heygen` and `tavus` requests the runtime behavior MUST be unchanged (same 422 key, status and message text when `config` is omitted), proved by the existing template suites run unedited.
- The frontend provider factory MUST behave exactly as before for `heygen`, `tavus` and the mock provider, and no `hr_avatar` code or SDK is loaded.
- The existing api, frontend and backoffice test suites MUST pass with zero edits to existing tests.

#### Scenario: Tavus and HeyGen start responses are byte-identical

- GIVEN HR-Avatar is unavailable and recorded `/start` fixtures for a Tavus and a HeyGen session
- WHEN `POST /start` is called for the same inputs after this change
- THEN the response bodies equal the recorded bodies and contain no `hr_avatar` member

#### Scenario: Field specs and catalogue are unchanged

- GIVEN HR-Avatar is unavailable
- WHEN field specs and the catalogue for each existing provider and resource are read
- THEN the responses equal their pre-change values and the field-spec object has no `hr_avatar` key

#### Scenario: Unchanged selection for every existing combination

- GIVEN HR-Avatar is unavailable and a project with any combination of pinned template (heygen or tavus), `provider_override` (heygen or tavus) and environment default
- WHEN the provider name is resolved
- THEN the result equals the pre-change result

#### Scenario: Template resource and export carry no new member

- GIVEN a heygen or tavus template with null `hr_avatar_config_id`
- WHEN it is read through the template resource and the export document
- THEN neither contains `hr_avatar_config_id`

#### Scenario: Existing suites run unedited

- GIVEN the api, frontend and backoffice suites as they were before this change
- WHEN they are run with HR-Avatar unconfigured and the flag unset
- THEN they all pass with no existing test edited, deleted, skipped or weakened

#### Scenario: No outbound HR-Avatar traffic on the default path

- GIVEN HR-Avatar is unavailable
- WHEN any interview, template or catalogue request is served for a Tavus, HeyGen or mock configuration
- THEN no HTTP request is sent to the HR-Avatar base URL (`Http::preventStrayRequests()` stays green)

### Requirement: New fields are classified in the exposure catalogue

Every new field that BEAI exposes or exports because of this change MUST have its own `T-EXPOSE-001`
entry in `api/tests/Helpers/PublicApi/ExposureCatalogue.php`, classified in the same change. This
includes at least: `hr_avatar_config_id` on the avatar template resource, `hr_avatar_config_id` in the
template export document, and each member of the `hr_avatar` object of the `/start` response. None of
them MUST be added to the `/v1` public API. The exposure test MUST stay green without editing existing
entries.

#### Scenario: Every new field has an entry

- GIVEN the new avatar template resource, export document and start-response members
- WHEN the exposure test enumerates them
- THEN each is covered by an entry classified in this change and the test passes

#### Scenario: Public API does not expose them

- GIVEN a template with `hr_avatar_config_id`
- WHEN the `/v1` public API responses are inspected
- THEN none contains `hr_avatar_config_id`, the base URL, or the publishable key
