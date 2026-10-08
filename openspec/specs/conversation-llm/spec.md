# Conversation LLM Specification

## Purpose

The global registry of Google Gemini conversation models and their published
rates, mode derivation, and the `managed`-mode wiring that lets an avatar
template bind a registered model and a credential on either avatar provider,
together with the cost estimate and per-template forecast derived from the
registry rates. `native_duplex` is registered and priced here but refused at
every save path.

Coverage target: 95%. This capability guards credentials (a security-evidence
path) and cost (a billing-evidence path); a gap here is a leaked key or a
wrong invoice, discovered only when it is too late.

Scope note: this version carries only the requirements that were confirmed
against the implementation at archive time (2026-10-08) and the HeyGen
requirements proven against the live provider on 2026-10-08. The registry
contents and the credential storage and validation requirements of the
originating change were not merged; see the archived
`pluggable-conversation-llm` report.

---

## Requirements

### Requirement: Registry sync runs via a console command, never `db:seed`

`beai:sync-llm-registry` MUST be the only production path that populates or
refreshes `llm_models`, because production never runs `db:seed`. It MUST be
idempotent and safe to re-run with no TTY.

#### Scenario: Running the sync command twice yields an identical row set

- WHEN `beai:sync-llm-registry` runs twice in succession with no seed-array change
- THEN the resulting `llm_models` rows are identical after both runs

### Requirement: A credential in use cannot be deleted; unbinding is a separate, narrower action

`DELETE /llm-credentials/{id}` on a credential bound to one or more templates
MUST be refused with 409 `credential_in_use`, naming the bound templates.
Unbinding a single template (`PATCH /avatar-templates/{id}` with both binding
ids null) MUST leave every other template bound to that credential untouched.

#### Scenario: Deleting a bound credential is refused

- GIVEN a credential bound to two templates
- WHEN `DELETE /llm-credentials/{id}` is called
- THEN the response is 409 `credential_in_use`, naming both templates, and the credential still exists

#### Scenario: Unbinding one template leaves siblings intact

- GIVEN a credential bound to templates A and B
- WHEN template A is unbound (both binding ids set to null via PATCH)
- THEN template B's binding is unchanged

#### Scenario: An unbound credential can be deleted

- GIVEN a credential bound to no template
- WHEN `DELETE /llm-credentials/{id}` is called
- THEN the response is 200 and the credential no longer exists

### Requirement: Mode is derived from the bound model's capability, and `native_duplex` is refused at every write path

`LlmCapability::mode()` MUST be an exhaustive mapping with no default arm. A
model whose capability resolves to `native_duplex` MUST be rejected with 422
`mode_unsupported` when bound via `create`, `update`, or `forceFill()->save()`
(the portability import path) — there MUST be no write path that bypasses
this check.

#### Scenario: A managed-capability model binds successfully

- GIVEN a registry model with `capability = 'text'`
- WHEN it is bound to a template via `PATCH`
- THEN the binding succeeds

#### Scenario: A native_duplex model is rejected on create, update, and import

- GIVEN a registry model with `capability = 'native_duplex'`
- WHEN it is bound via `create`, via `update`, and via the portability import's `forceFill()->save()` path
- THEN each of the three attempts is rejected with 422 `mode_unsupported`, and no binding is persisted

### Requirement: The Tavus wire merges the LLM layer without wiping other persona knobs

The PAL layer merge MUST use `array_replace_recursive`, never `array_merge`,
and the empty-layers early-return MUST be evaluated after the merge. A single
PATCH MUST carry both the LLM binding fields and any pre-existing
persona-level tuning knob (e.g. `llmTemperature`) in the same request body.

#### Scenario: One PATCH carries both the binding and existing tuning

- GIVEN a Tavus template bound to a model and credential, with `llmTemperature` also configured
- WHEN the template is saved
- THEN the resulting PAL PATCH body carries both `layers.llm.{model,base_url,api_key}` and `layers.llm.extra_body.temperature`

#### Scenario: A bound template with an otherwise-empty config still syncs

- GIVEN a Tavus template whose only configuration is the LLM binding
- WHEN it is saved
- THEN the PAL PATCH is sent — the sync is not skipped by the empty-layers guard

### Requirement: HeyGen's secret and configuration lifecycle is lazy, synchronous, and leaves no orphan

Registering a HeyGen `llm_configuration` MUST happen only at template save
time when a binding is present, never at candidate session start. The secret
is created with `POST /v1/secrets` and the configuration with
`POST /v1/llm-configurations`; the configuration id stored in
`heygen_llm_configuration_id` is the sole ledger for the configuration. A model
change on a bound template MUST update the stored configuration in place.
Deleting a bound template, or unbinding it, MUST delete the associated
`llm_configuration`. HeyGen's secrets API has no update verb (only create,
list and delete), so rotating a credential MUST delete and recreate its HeyGen
secret, then update every configuration bound to that credential.

`llm_configuration_id` MUST be sent as a top-level field of the
`POST /v1/sessions/token` body, through the provider-owned position and never
through the environment-extendable token allowlist. It MUST NOT be nested under
`avatar_persona` (HeyGen silently ignores it there, so the avatar would answer
with the provider's default model while the template looks bound) and MUST NOT
be sent to `POST /v1/contexts`, which has no such field. The same call MUST
carry `avatar_persona`, because HeyGen rejects a token request without it.

HeyGen validates the format of `llm_configuration_id` when the token is issued
but checks that the configuration exists only when the session starts. A
session start rejected with 400 because the configuration is not found in the
account MUST be treated as a missing configuration, reported as a degraded
binding, and never as an applied one.

#### Scenario: Binding a HeyGen template creates its configuration at save

- GIVEN an unbound HeyGen-provider template
- WHEN it is saved with a model and credential
- THEN a HeyGen secret and a HeyGen `llm_configuration` are created and the configuration id is stored on the template

#### Scenario: Changing the model of a bound template updates its configuration in place

- GIVEN a HeyGen template bound to a configuration
- WHEN the template is saved with a different model
- THEN the stored configuration is updated in place and its id is unchanged

#### Scenario: Deleting a bound HeyGen template removes its configuration

- GIVEN a HeyGen template bound to a configuration
- WHEN the template is deleted
- THEN the HeyGen `llm_configuration` is deleted and no orphan remains

#### Scenario: Rotating a credential recreates its secret and patches every bound configuration

- GIVEN a credential bound to two HeyGen templates
- WHEN the credential is rotated
- THEN the HeyGen secret is deleted and recreated, because the secrets API has no update verb, and both bound configurations are updated to reference it

#### Scenario: The binding is a top-level field of the token request

- GIVEN a HeyGen session-token body being built for a bound template
- WHEN the body is assembled
- THEN `llm_configuration_id` appears at the top level of the body, `avatar_persona` is present, and `llm_configuration_id` appears nowhere under `avatar_persona`
- AND no `POST /v1/contexts` body carries `llm_configuration_id`

#### Scenario: The binding cannot be silently disabled by an environment change

- GIVEN a HeyGen session-token body being built for a bound template
- WHEN the token field allowlist environment variable is changed
- THEN `llm_configuration_id` still appears in the body — it is not gated by that allowlist

#### Scenario: A start-time rejection of an unknown configuration is a degraded binding

- GIVEN a session token issued with a well-formed `llm_configuration_id` that no longer exists in the HeyGen account
- WHEN the session start is rejected with 400 "LLM configuration ... not found"
- THEN the binding is reported as degraded and not as applied

### Requirement: Stopping a HeyGen session uses the stop endpoint and a failed stop is reported

Tearing down a HeyGen session MUST send `POST /v1/sessions/stop` with the
session id and a reason; HeyGen offers no other way to end a session, and a
`DELETE` on the session resource is refused with 405 and leaves the session
running. The teardown MUST check the response status explicitly and MUST NOT
treat an unconfirmed stop as a success. A 404 means the session is already gone
and counts as stopped. Any other non-2xx status, or a transport error, MUST be
logged with the provider's message redacted and MUST be reported to the caller
as a failed stop, without throwing.

#### Scenario: A confirmed stop is reported as stopped

- GIVEN a HeyGen session with a provider session reference
- WHEN teardown is requested and `POST /v1/sessions/stop` answers 2xx
- THEN the teardown reports the session as stopped

#### Scenario: A session that is already gone counts as stopped

- GIVEN a HeyGen session with a provider session reference
- WHEN `POST /v1/sessions/stop` answers 404
- THEN the teardown reports the session as stopped

#### Scenario: An unconfirmed stop is reported, never treated as success

- GIVEN a HeyGen session with a provider session reference
- WHEN `POST /v1/sessions/stop` answers a non-2xx status other than 404, or the request fails in transport
- THEN the teardown reports a failed stop and logs the failure with the provider's message redacted
- AND no exception propagates to the caller

### Requirement: The usage estimator rejects the naive per-character count in favor of a context-resend formula

Let `t` index **avatar turns**; let `P` be the system-prompt tokens, `p_i` the
tokens of the participant utterance that elicited avatar turn `i`, and `o_i`
the tokens of avatar turn `i`, where `tokens(s) = ceil(mb_strlen(s) / 4)`.

`ConversationLlmUsageEstimator` MUST compute the context carried by turn `t` as

```
c_t = P + Σ_{i<t} (p_i + o_i) + p_t
```

reflecting that a conversational LLM re-sends the full history every turn.
The trailing `p_t` term is REQUIRED: the participant's turn-`t` message IS the
input the model is responding to, so a request that omitted it could not have
produced `o_t`. `p_t` is `0` where no participant utterance precedes the turn
(the opening greeting).

The naive `Σ all chars / 4` MUST be explicitly rejected by test as
under-counting. A formula that omits `p_t` MUST also be rejected by test —
that omission is a structural under-count, not a rounding difference, and it
is invisible to any test derived from the same formula.

#### Scenario: Hand-computed arithmetic matches a fixed three-turn oracle

- GIVEN `P = 100`, participant utterances of `20`, `60`, `60` tokens and avatar utterances of `80`, `80`, `80` tokens
- WHEN the estimator computes the per-turn context
- THEN `c_1 = 120`, `c_2 = 260` and `c_3 = 400`
- AND the values `100`, `200`, `340` — the result of omitting `p_t` — are asserted NOT to be produced

#### Scenario: The naive character-sum estimate is explicitly asserted wrong

- GIVEN the same fixture used above
- WHEN the naive `Σ all chars / 4` value is compared to the estimator's result
- THEN the naive value is asserted to be a materially different (lower) number, not merely different by rounding

### Requirement: The per-template forecast is a labelled estimate over reference parameters, never a per-minute figure

A template's projected conversation-LLM cost MUST be expressed as a total
estimated USD figure over a fixed reference interview (minutes and turns
sourced from `config/conversation_llm.php`), and MUST NEVER be expressed as a
$/minute rate — input tokens grow quadratically in turn count, so a
per-minute figure misstates cost at any point other than the reference length.

#### Scenario: The forecast states minutes, turns, and a USD figure — never $/minute

- GIVEN a template bound to a priced model
- WHEN its cost forecast is computed
- THEN the result carries the reference minutes, reference turns, and one USD amount
- AND no per-minute rate is exposed anywhere in that forecast
