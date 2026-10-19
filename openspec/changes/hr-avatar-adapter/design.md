# Design: HR-Avatar adapter (BEAI side, additive and opt-in)

> Change `hr-avatar-adapter`, slice S9 of the HR-Avatar extraction. Conforms to `proposal.md` and
> `specs/{hr-avatar-integration,interview-session,avatar-templates,interview-frontend}/spec.md`.
> Binding inputs: `CLAUDE.md`, `openspec/config.yaml`, `docs/extraction/DESIGN.md` (D7-D9), and
> `hr-avatar/openspec/changes/hr-avatar-engine/reconciliation.md` (binding over the HR-Avatar specs
> and design). Deviations from the spec are listed under "Spec amendments" and were applied to the
> spec files in this phase. Amended 2026-10-19 by a corrective re-run after a fresh-context
> validation (17 findings); each finding and where it landed is listed under "Validation corrections".

## Technical Approach

`hr_avatar` is a third provider that reaches the interview flow **only through new explicit arms**.
Every existing branch keyed on `'tavus'` or `'heygen'` is left as it is, and every `default =>`
arm that would silently absorb an unknown provider name gets an explicit `hr_avatar` arm in front of
it. Two independent switches keep the default path dark:

- **api**: `HrAvatarConnection::isAvailable()` (config-only, the single answer to "is HR-Avatar
  available") gates provider selection, template writes, field specs, the catalogue proxy and the
  export command. Unset `HR_AVATAR_*` means `hr_avatar` can be neither written nor selected, and no
  request ever leaves for an HR-Avatar host.
- **frontend**: `NUXT_PUBLIC_HR_AVATAR_ENABLED` (public runtime config `hrAvatarEnabled`, default
  `''`). With it off, `createProvider('hr_avatar', …)` throws the existing unknown-provider error and
  neither the adapter module nor `@hr-avatar/sdk` is ever loaded.

The api talks to HR-Avatar with plain Laravel `Http`, like `TavusProvider`/`HeygenProvider`. The
browser receives only the per-conversation `client_secret` (as the existing `provider_token`), the
base URL and the publishable key; the SDK drives the transport. BEAI's own `utterances` rows stay the
transcript of record (`reconcileTranscript()` returns `[]`, like Tavus), so scoring is untouched.

## Resolved open points (orchestrator items 1-8)

| # | Question | Resolution |
|---|---|---|
| 1 | Fail-closed class for a pinned `hr_avatar` template when HR-Avatar is unconfigured | **The existing pre-flight**, not a provider failure. `ProviderPreflight::check()` (`api/app/Services/Provider/ProviderPreflight.php:50`) already exists for exactly this class of fault ("a template that names something the provider refuses ... Here the same problem is a 422 with a machine code, raised before a session exists"). It is called at `InterviewController::start()` :258 **before** any session row exists, returns `422 {error: interview_configuration_invalid, reasons: [{key, code}]}`, and mutates neither the session nor the participant. The alternatives both mutate state: `Upstream` → `markSessionError(..., $participant)` moves the participant to `errore` (`InterviewController.php:1390`, `:1774`); `ClientError` → session `error` + `error_count+1` (`:1388`, `:1737`). New `hr_avatar` arm: unavailable → `{key: credentials, code: provider_key_missing}`; pinned template without config id → `{key: hr_avatar_config_id, code: avatar_missing}`. Both codes already exist. The frontend already treats that 422 as the retryable `error` screen (`useInterviewSession.ts:2134`), same as the 502. **Spec amendment A1.** |
| 2 | Synchronous `createProvider` that never loads the adapter or SDK while the flag is off | The `hr_avatar` arm returns a small **deferred handle** defined in `factory.ts` whose `start()` performs `await import('~/app/providers/hr-avatar')` (behind `import.meta.client`), constructs `HrAvatarProvider` and delegates; the adapter's own `start()` then performs `await import('@hr-avatar/sdk')`. Flag off: the arm falls through to the existing throw, so neither import is reached. The flag is read inside the arm only (`useRuntimeConfig().public.hrAvatarEnabled`), so the `createProvider(name, mock)` signature and the heygen/tavus/mock paths do not change. |
| 3 | SDK consumption without publishing | Vendored tarball `frontend/vendor/hr-avatar-sdk-<ver>.tgz`, produced by `bun pm pack` in `hr-avatar/sdk`, referenced as `"@hr-avatar/sdk": "file:./vendor/hr-avatar-sdk-<ver>.tgz"`, integrity in `bun.lock`, row in `docs/version-catalog.md`. `frontend/Dockerfile` copies `vendor/` before `bun install --frozen-lockfile`. See D-SDK. |
| 4 | Tenant isolation of the avatar-config proxy | **Confirmed, not simplified.** All BEAI organizations share one HR-Avatar account (one secret key), so listing without a filter would show tenant A the names of tenant B's configs. Attribution value `org_<organization_id>`: opaque to HR-Avatar, stable, no name or personal data. Written by the export command as the config's `external_ref`; the proxy returns only configs whose `external_ref` equals the caller organization's value. Rejected "simplify" (list everything): a cross-tenant read surface, which `CLAUDE.md` forbids. Residual risk recorded in Security. |
| 5 | Does the composed system prompt carry the candidate's display name? | **No.** `SystemPromptComposer::compose()` (`api/app/Services/Conversation/SystemPromptComposer.php:131`) takes competency code, role id, competency id, locale, budgets, phrases, primary questions, spoken opening, revision, prompt templates and an operator override: no participant input. `OpeningTextComposer::compose()` (`:88`) takes variant, competency name, language, spoken primary and intro phrase. `InterviewController::start()` builds `QuestionContext` only from those (:482-507). Consequence: `system_prompt`/`opening_text` sent to HR-Avatar carry no candidate PII; they do carry BEAI's BARS content (proprietary, not personal) and any operator-authored prompt override. Candidate speech still reaches HR-Avatar through its own provider-side transcript merge even with `forwardTranscript: false` (reconciliation item 20; item 39 confirms the flag suppresses client utterance forwarding only), so proposal decision 2 (GDPR store with no purge) stands and still blocks enabling outside local. |
| 6 | Completion matching | **In the BEAI adapter**, with the existing `matchesEndPhrase()` (`frontend/app/utils/proctor-config.ts:181`: accent-, case- and punctuation-insensitive containment) on final **avatar** transcript lines. The SDK's `completionPhrases` (case-insensitive substring + 1500 ms settle, reconciliation item 34) is still passed (the spec requires it) and acts as a second, transport-level trigger: SDK `ended{reason: completion_phrase}` also emits `complete`. A per-start terminal latch guarantees `complete` at most once and gives `complete`/`error` precedence over `stopped` (SDK state `ended` maps to `stopped` only when neither was emitted). The SDK alone would miss an accent or punctuation difference the other two providers already tolerate. See D-COMPLETE. |
| 7 | Exact touch points, Scramble, T-EXPOSE-001, migration, config, command | See File Changes, D-SCRAMBLE, D-EXPOSE and Interfaces. |
| 8 | Test plan and slicing | See Testing Strategy and Work-unit slicing. |

## Architecture Decisions

### D-CONN: one static `HrAvatarConnection` class owns settings, availability and the HTTP client

**Choice**: `api/app/Services/Provider/HrAvatarConnection.php`, a `final` class with static methods
only: `isAvailable()`, `missingVariables()`, `baseUrl()`, `publishableKey()`, `secretKey()`,
`client()` (a `PendingRequest`: base URL, bearer secret key, `acceptJson()`, 15 s timeout),
`organizationRef(int $organizationId)` and `unavailableProviderRule()` (a validation closure). It
reads `config('hr_avatar.*')` from the new `api/config/hr_avatar.php`.
**Alternatives considered**: an injected service (constructor changes would ripple into
`BuildInterviewSessionResponse` and break existing direct constructions in tests); availability
inside `HrAvatarProvider` (the catalogue, template validation and the export command would then
depend on a session provider).
**Rationale**: the spec demands exactly one place that answers availability, computed from config
only. A static class follows `AvatarProviderCatalogue`/`ProviderFieldSpecs`, needs no DI changes, and
keeps every consumer's diff to one call. `secretKey()` exists only for the catalogue proxy, which
reuses `AvatarProviderCatalogue::request()` and its safe-code mapping.

### D-SELECT: selection arms, with no fallthrough into HeyGen

**Choice**:
- `InterviewController::providerNameFor()` (:1703): a pinned template's provider is returned as is
  (now possibly `hr_avatar`). For the two fallbacks, a value of `hr_avatar` is treated as absent:
  override `hr_avatar` → env default; env `hr_avatar` → `'heygen'`. Test mode stays first and returns
  `mock`.
- `InterviewController::resolveProvider()` (:1931): `'hr_avatar' => app(HrAvatarProvider::class)`
  before `default`.
- `ReleaseProviderSession::forRefs()` (`api/app/Actions/Interview/ReleaseProviderSession.php:56`):
  same explicit arm. **This was a latent defect for this change**: without it, the `/end` release,
  `ReleaseEndedProviderSessionJob` and the `ReapStaleInterviews` sweep would hand a `conv_…` ref to
  `HeygenProvider::teardown()`.
- `ProviderPreflight::check()`: `hr_avatar` arm (item 1).
- `InterviewServiceProvider` is **not** changed: its binding resolves from override/env only, which
  can never yield `hr_avatar`, and `resolveProvider()` is the actual routing point.
**Alternatives considered**: availability check inside `providerNameFor()` with fallback to
override/env (the proposal's original recommendation; rejected by the spec, it silently swaps the
avatar a project pinned); fail inside `issue()` (mutates session state, item 1).
**Rationale**: the only way into `hr_avatar` is a pinned template, and every switch that previously
defaulted to HeyGen now names it.

Provider-name branch audit of `InterviewController` (all treat `hr_avatar` as "neither", no edit):

| Line | Branch | `hr_avatar` behaviour |
|---|---|---|
| :290 | `SingleSessionGate::applies()` (`provider !== 'tavus'` → false) | gate closed: no plan, no continuation, `live_conversation_id` ignored |
| :348, :437 | `start()`: harvest/release of the outgoing session via `resolveProvider($liveSession->provider)` | new arm: `reconcileTranscript()` = `[]`, `teardown()` = `/end` |
| :480 | `start()`: `resolveProvider($providerName)` for the new session | new arm: `HrAvatarProvider::issue()` |
| :506 | `participantLeftTimeout` only when single-session | null |
| :593 | `suspend()`: `resolveProvider($session->provider)`, then `harvestOutgoingTranscript()` and `releaseProviderSession()` | new arm: `reconcileTranscript()` = `[]` (no request), `teardown()` = one `/end`; never reaches HeyGen |
| :700 | `end()`: `resolveProvider($providerName)` before the transaction | new arm constructs `HrAvatarProvider` (no I/O at construction); it is used only by the :717 branch, which does not run |
| :717 | `end()`: HeyGen transcript REPLACE (`reconcileTranscript` + `replaceUtterances`) | not run; live utterances kept |
| :801 | `handsOverToNextCompetency()`: HeyGen-completed handover (`provider === 'heygen' && completed`) or `planCoversLaterCompetency()` | false for both terms (no plan for `hr_avatar`), so `/end` releases at once through `releaseEnded` |
| :815 | `planCoversLaterCompetency()`: Tavus shared-ref guard (`provider !== 'tavus'` → false) | not run |
| :1154 | Tavus deferred release near ceiling | not run; immediate teardown on resume |
| :1176, :1642 | `markReleased`/`releaseProviderSession` | provider-filtered; refs are unique per row |

Every `resolveProvider()` call site (:348, :437, :480, :593, :700) reaches the new explicit arm, so no
path hands a `conv_…` ref to `HeygenProvider`. Task 3.1 re-verifies these line numbers before coding.

`provider_override` has **no** write-side validation to extend: no FormRequest or controller rule
validates the column (`rg provider_override api/app` finds only readers, and `ProjectResource.php:81`
records that it became unreachable from the API). The spec bullet "`hr_avatar` MUST NOT be accepted by
the validation of `provider_override`" is therefore **N/A** for this change: there is no validation to
refuse it in, and adding one would be new, unrequested scope. The read side is what is enforced: a
stored `hr_avatar` override is ignored by `providerNameFor()`, kept as a test ("override `hr_avatar`
→ env default" in `HrAvatarSelectionTest`).

Outside the controller: `SessionCostEstimator` (`default => null`, so no estimate, no failure),
`ResyncTemplateBinding::run()` (`default => skipped`, no stamp), `TemplateReferenceValidator`
(`default => []`, no HTTP), `BindHeygenTemplateVoice` (`provider !== 'heygen'` → no-op),
`SessionLiveClock::resolveMaxSeconds()` (`default` → 1200 s).

### D-ISSUE: request mapping and failure classification

**Choice**: `HrAvatarProvider::issue()` resolves the pinned template with
`ActiveTemplateResolver::resolve('hr_avatar', $session->project_id)` and sends exactly the seven
members of the spec. The following fail as `ProviderFailureClass::ClientError` **before any
request**: integration unavailable, null template or config id, null `systemPrompt` or
`openingText`, `systemPrompt` > 32000 or `openingText` > 4000 characters (never truncated), and a
language not matching `^[a-z]{2}$`. `max_duration_seconds` =
`clamp(SessionLiveClock::resolveMaxSeconds($session), 30, 3600)` (1200 for `hr_avatar` today:
`hr_avatar` templates carry no duration knob). `external_ref` = `"session_{$session->id}"`.
`metadata` = `new \stdClass` so it serializes as `{}`.
Response: 429 → Throttle; other 4xx → ClientError; 5xx, `ConnectionException`, non-JSON, a status
other than 201, an id without the `conv_` prefix, or an empty `client_secret` → Upstream.
Two operator faults land in ClientError on purpose (HTTP 500, participant unchanged, session `error`,
`error_count+1`), with the stable code in the log line: a **403 scope gap** (the secret key lacks
`conversations:write`, see Rollout) and a **409 `config_not_synced`** (the pinned config is still
`pending`, see D-EXPORT). Neither is the candidate's fault, so neither may move the participant to
`errore`; both are fixed by the operator and the candidate's retry then succeeds.
Exception message: `hr_avatar: {operation} failed (status {N}xx[, code {code}])`. The Problem+JSON
`code` is included only when it matches `^[a-z_]{1,64}$`. `detail`, the body and the prompt are
never read into a message or log line. Log context: `operation`, `status_class`, `code`, `class`.
**Alternatives considered**: porting `ProviderErrorMessage::extract()` with redaction (reconciliation
item 33 forbids it; it puts response text into logs); retrying on 429 like `TavusConcurrencyGuard`
(YAGNI; the browser already retries 429 three times).
**Rationale**: the existing `handleProviderFailure()` matrix applies unchanged, and the cheapest
redaction is never reading the text. **Spec amendments A2, A3.**

### D-TEARDOWN: `/end` with a validated ref, never throws

**Choice**: `teardown()` sends nothing for a null ref or one not matching `^conv_[0-9A-Za-z]+$`
(returns `true`: nothing to release; the pattern also blocks path injection into the URL). Integration
unavailable → logs and returns `false` with no request. Otherwise one `POST /v1/conversations/{id}/end`:
2xx → `true`; anything else, including exceptions, is logged (`status_class`, `code`, exception class)
and returns `false`. **Rationale**: matches the interface contract (`ProviderSessionService.php:60-69`)
and the four existing call sites (resume, compensation, `/end` release, sweep) with no edit.

### D-START: `hr_avatar` join inputs in the 201 body, only for `hr_avatar`

**Choice**: `BuildInterviewSessionResponse::handle()` adds
`$body['hr_avatar'] = ['base_url' => HrAvatarConnection::baseUrl(), 'publishable_key' => HrAvatarConnection::publishableKey()]`
inside `if ($token->provider === 'hr_avatar')`, after `continuation`. `provider_token` already
carries `$token->token` (the client secret); `conversation_url` is null. The `@scramble-return` of
`InterviewController::start()` (:121) gains `hr_avatar?: array{base_url: string, publishable_key: string}`.
**Rationale**: the key is absent for every other provider, so their bodies stay byte-identical (the
same "absent, not null" convention as `conversation_id`).

### D-TEMPLATES: template writes, import/export and activation

**Choice** (all in `api/app/Http/Controllers/AvatarTemplateController.php` unless stated):
- Store validates `organizationTemplateStoreRules()`, a new private method spreading the shared
  `templateStoreRules()` and overriding four keys with literal rules:
  `provider` → `['required','string','in:heygen,tavus,hr_avatar', HrAvatarConnection::unavailableProviderRule()]`;
  `config` → `['required_unless:provider,hr_avatar','array']` (**spec amendment A6**), with one
  custom message passed to `validate()`:
  `['config.required_unless' => __('validation.required', ['attribute' => 'config'])]`, so a heygen or
  tavus request that omits `config` still gets exactly today's 422 key, status and message text. An
  `hr_avatar` template may send `{}` or omit it; normalised with `$validated['config'] ??= []`;
  `hr_avatar_config_id` → `['required_if:provider,hr_avatar','nullable','string','max:64','regex:/^avc_[0-9A-Za-z]+$/']`;
  `llm_model_id`/`llm_credential_id` → existing rules plus `prohibited_if:provider,hr_avatar`.
  The shared trait (also used by `PlatformAvatarTemplateController`) is **not** changed, so platform
  templates keep refusing `hr_avatar` (out of scope).
- **One 422 for an `hr_avatar` store** (validation finding 1). Today `store()` raises two separate
  `ValidationException`s: `$request->validate()` at `AvatarTemplateController.php:228` and
  `assertConfigValid()` at :233. A malformed `hr_avatar_config_id` plus an unknown config key would
  therefore report only the first. For `provider = 'hr_avatar'` only, `store()` computes the config
  errors first (`ConfigValidator::validate('hr_avatar', $config)` when `config` is an array, mapped to
  `config.{key} => code` exactly as `assertConfigValid()` maps them), then calls
  `$request->validate(...)`; if that throws, it rethrows one
  `ValidationException::withMessages(array_merge($e->errors(), $configErrors))`; if it passes and
  `$configErrors !== []`, it throws those. `$request->validate()` stays the call Scramble reads. For
  heygen and tavus `$configErrors` is always `[]` and the existing two-step order (rules, then
  `assertConfigValid()` with its reference checks) is untouched. The update path gets the same merge
  for an `hr_avatar` template (its provider is known from the row).
- Update adds `hr_avatar_config_id` with the same format rule. Two post-validation checks follow the
  existing provider-immutability precedent: an `hr_avatar` template refuses a null id (422 on
  `hr_avatar_config_id`) and a non-null LLM field (422 on that field).
- `activate()`: an `hr_avatar` template while unavailable → 422 on `provider`, `is_active` unchanged.
- `ConfigValidator::validate()`: an `hr_avatar` arm before the empty-spec early return reports every
  key as `unknown` (the empty-spec path would otherwise accept anything).
- `fieldSpecs()`: `$specs['hr_avatar'] = []` only when available; `#[ResponseDoc]` gains
  `hr_avatar?: list<…>`.
- `AvatarTemplateResource`: `'hr_avatar_config_id' => $this->when($template->hr_avatar_config_id !== null, …)`;
  `@scramble-return`/`@return` gain `hr_avatar_config_id?: string`.
- `TemplateDocument::export()` adds the member only when non-null; `flatten()` carries the raw value
  (or null); `AvatarTemplatePortabilityController::reject()` replaces
  `ProviderFieldSpecs::for(...) === []` with an explicit provider check (heygen, tavus, or
  `hr_avatar` while available), validates the id format whenever it is non-null, requires it for
  `hr_avatar`, and refuses an `llm` block for `hr_avatar`; `create()` force-fills the id.
- `DuplicateAvatarTemplate::run()` copies `hr_avatar_config_id`. Duplication is superadmin-only and
  cross-organization (`AvatarTemplateDuplicateController`); the id travels like the provider-side ids
  already inside `config` (`avatarId`, `faceId`), which belong to the shared platform accounts too.
- `AvatarTemplate`: `hr_avatar_config_id` in `$fillable` and `@property`.
**Alternatives considered**: adding the rules to the shared trait (would open platform templates);
`Rule::requiredIf(closure)` on `config` (the previous choice: Scramble cannot read a closure, so the
schema change was undeclared; `required_unless` documents the condition, and the custom message keeps
the heygen/tavus text identical); merging the config check into the rules as a `config.*` closure
(an implicit-rule edge for `null` values and a noisy `config.*` schema); one 422 via
`Validator::make()->after()` (moves the call away from the `$request->validate()` form Scramble reads);
HTTP existence check on write (forbidden by spec).
**Rationale**: org-only, smallest override, one 422 for every `hr_avatar` field error, and identical
behaviour for heygen and tavus (proved by the unedited existing template suites, task 5.6). The
closures read the request only at validation time, never while `rules()` is built (the Scramble trap
in memory "Scramble swallows FormRequest exceptions").

### D-PROXY: catalogue arm with per-organization cache

**Choice**: `catalogue()` accepts `in:heygen,tavus,cartesia,elevenlabs,hr_avatar` plus
`unavailableProviderRule()`, resource `in:voice,avatar,replica,pal,avatar_config`, and
`CATALOGUE_RESOURCES['hr_avatar'] = ['avatar_config']`. For `hr_avatar` it calls
`AvatarProviderCatalogue::fetch('hr_avatar', 'avatar_config', organizationId: $orgId)` with `$orgId`
from `TenantResolver::getOrgId()`. A null organization (bare superadmin) answers `{status: empty}`
without a request. `fetch()` gains a trailing `?int $organizationId = null` (after the existing
`bool $fresh = false`). **`cacheKey()` (`AvatarProviderCatalogue.php:168`, "the one place a catalogue
cache key is built") is extended, not bypassed**: `cacheKey(string $provider, string $resource, ?int $organizationId = null)`
returns today's string unchanged when the id is null and appends `:org{$id}` otherwise; `fetch()`
passes the id through, so `Cache::forget` on `$fresh` and the existing callers
(`TemplateReferenceValidator`, `TavusPalEditableCatalogueTest`, which reads `cacheKey('tavus','pal')`)
see identical keys. When the id is non-null the TTL is 5 minutes; existing TTL and behaviour are
unchanged when it is null. `fetchLive()` gains the same trailing parameter and the arm
`'hr_avatar:avatar_config' => self::hrAvatarConfigs($organizationId)`:
`GET {base}/v1/avatar-configs?limit=100&external_ref=org_{id}[&cursor=]` through the existing
`request()` (Authorization `Bearer <secret>`). The **`external_ref` filter is server-side** (HR-Avatar
reconciliation item 38: exact match, applied before pagination, scope `avatar_configs:read`), so the
10-page bound now caps one organization's configs, not the whole shared account, and no tenant can
lose configs to another tenant's volume. The proxy still follows `next_cursor` for at most 10 pages,
keeps `sync_status ∈ {synced, not_required}`, and as defence in depth drops any returned row whose
`external_ref` is not exactly `HrAvatarConnection::organizationRef($id)` (a filter regression upstream
must never become a cross-tenant read). Rows map through the existing
`entry(provider: 'hr_avatar', id, label: name)`. Failures degrade through the existing
`CatalogueFetchException` codes (a 403 scope gap → `provider_unauthorized`).
**Alternatives considered**: a separate catalogue class (duplicates caching and error mapping); the
24 h TTL (a config created in HR-Avatar would be invisible for a day; manual entry still covers it);
client-side filtering over unfiltered pages (the previous design: with one shared account, 10 pages
of 100 could be filled by other tenants' configs and hide the caller's own); building the
organization key outside `cacheKey()` (a second place that builds keys, contradicting its contract).
**Rationale**: maximum reuse of a proven degrade path, and the existing item shape keeps the
backoffice combobox unchanged. **Spec amendment A4.**

### D-EXPORT: `hr-avatar:export-templates`, dry run by default

**Choice**: `api/app/Console/Commands/ExportTemplatesToHrAvatar.php`, signature
`hr-avatar:export-templates {--apply}`. It reads
`AvatarTemplate::withoutGlobalScopes()->whereNotNull('organization_id')->whereNull('deleted_at')->orderBy('id')`
(the cross-tenant listing idiom of `ReapStaleInterviews`). Outcome per row: `already_linked` (id
set), `would_create` (dry run), `created avc_…`, or `failed <code>`. Dry run: no HTTP, no write,
works while unavailable. `--apply` while unavailable → exit 1 naming `missingVariables()` by name.
Per eligible template: `POST /v1/avatar-configs` with
`{name: mb_substr(name, 0, 120), provider, config, voice, external_ref: organizationRef(org)}`.
`config` is the template config minus `ttsEngine`/`ttsExternalVoiceId`; `voice` is
`{engine, voice_id}` when `ttsEngine ∈ {cartesia, elevenlabs}` with a voice id, otherwise omitted.
No `persona`, no `llm_model_id`, no keys. The returned id must match `^avc_[0-9A-Za-z]+$` (≤ 64).
The write is
`DB::table('avatar_templates')->where('id', …)->where('organization_id', …)->whereNull('hr_avatar_config_id')->update(['hr_avatar_config_id' => $id])`:
query builder, so no `updated_at`, no model events, and a concurrent second run cannot overwrite.
Failure codes reuse the catalogue vocabulary (`provider_unauthorized`, `provider_rate_limited`,
`provider_unavailable`, `provider_unreachable`, `provider_rejected`, `provider_bad_response`); the
command continues and exits 1. A 403 scope gap (the key lacks `avatar_configs:write`) reports
`provider_unauthorized` for every row.

**`sync_status` is printed per created row** (validation finding 6): the success line is
`created avc_… sync_status=<value>`, where `<value>` is the 201 body's `sync_status` when it matches
`^[a-z_]{1,32}$`, otherwise `unknown` (upstream text is never echoed). After the run the command prints
one summary line counting rows by `sync_status`. Rationale: HR-Avatar may answer a create with
`pending` (a provider-side sync is still running), and a `pending` config **cannot start a
conversation**: `POST /v1/conversations` answers 409 `config_not_synced`, which `HrAvatarProvider`
classifies as ClientError (D-ISSUE: 500, participant unchanged). The id is still written (it is the
right link, and re-running `--apply` would otherwise create a duplicate config), and the catalogue
proxy already hides `pending`/`failed` configs, so an admin cannot pick one there. The operator rule,
written into the command's closing line and the Rollout: **do not switch a project to an `hr_avatar`
template whose config is not yet `synced` or `not_required`**; re-check it in the picker (it appears
there only once usable).
**Rationale**: D9 non-destructive; idempotent through the `whereNull` predicate; nothing beyond the
one column changes. Key parity of `config` with HR-Avatar's field specs is an open question (below);
a mismatch fails safely as `provider_rejected` with no write.

### D-FACTORY: deferred handle in `factory.ts`

**Choice**: in `createProvider`, `case 'hr_avatar': if (flag === true || flag === 'true') return createDeferredHrAvatar(); break;`
and the existing throw moves after the `switch` with the same text (the `never` exhaustiveness
binding is dropped). `flag = useRuntimeConfig().public.hrAvatarEnabled`, read only inside that arm.
`createDeferredHrAvatar()` (about 50 lines, private to `factory.ts`) buffers `on()` subscriptions;
`start()` throws if `!import.meta.client`, then does a dynamic import of the adapter, replays the
subscriptions, and delegates. A rejected import emits `error {code: 'sdk_error', message: 'provider_unavailable'}`
and resolves `{}`. `stop`, `toggleMic` and `setMicMuted` before load are no-ops; `whenAvatarSilent`
before load resolves.
**Flag semantics (validation finding 12).** The check runs on the **runtime value**, after Nuxt
has coerced the environment string with `destr`. `destr` compares `true`/`false` case-insensitively,
so `NUXT_PUBLIC_HR_AVATAR_ENABLED=true`, `TRUE` and `True` all arrive as the boolean `true` and
**enable** the arm; `1` arrives as the number `1`, `yes` as the string `'yes'`, and an empty or unset
variable as `''` (the default), all of which keep it off. The string `'true'` is still accepted for a
value set directly in `nuxt.config.ts`. Unit tests therefore stub runtime values (`true`, `'true'` on;
`1`, `'1'`, `''`, `undefined`, `false`, `'yes'` off), and the env-level casing is documented in Rollout;
the earlier claim that env `TRUE` stays off was wrong.

**Both switches flip together (validation finding 13).** The api availability and the frontend flag
are independent, so one mismatch is reachable and must be known to operators: api available, a
project pinned to an `hr_avatar` template, frontend flag **off**. Then `/start` passes pre-flight,
`issue()` creates an HR-Avatar conversation (the session row goes `in_corso` with a `conv_…` ref),
and only then does the browser's `createProvider('hr_avatar')` throw the unknown-provider error. That
error has no HTTP status, so it lands in the generic branch of the `/start` catch
(`useInterviewSession.ts:2087`) and shows the retryable `error` screen; each retry resumes the
`in_corso` row, creating a new conversation and ending the previous one (D-TEARDOWN). Nothing leaks
and the participant is never moved to `errore`, but every attempt burns one HR-Avatar conversation
until an operator acts. HR-Avatar expires an unconnected conversation by itself (reconciliation
item 15: `created → ended`, reason `expired`, after 900 s) and BEAI's `ReapStaleInterviews` sweep ends
any ref left behind. Mitigation is operational, not code: the two switches are flipped together and
in this order (frontend flag first, then the api variables; reverse on rollback). The reverse
mismatch (flag on, api unavailable) is harmless: no `/start` ever returns `hr_avatar`.
**Alternatives considered**: a static import of the adapter (loads adapter code on the default
path; the spec forbids it); an async `createProvider` (changes the signature of every caller); having
the api read the frontend flag (couples two deployables for a temporary local-only feature).
**Rationale**: synchronous signature, nothing new on the default path, and the `import.meta.client`
guard lets Vite drop the branch from the SSR bundle (the same technique as `heygen.ts:164`).

### D-ADAPTER: `HrAvatarProvider` (frontend)

**Choice**: `frontend/app/providers/hr-avatar.ts`, modelled on `heygen.ts`: an injectable
`sdkLoader` defaults to `import('@hr-avatar/sdk')` behind `import.meta.client`. SDK types come from
`typeof import('@hr-avatar/sdk')` inside the module, never from an `import` line, so the textual
anonymity scan holds. `start(mountEl, cfg)`:
1. Empty `endPhrase`/`finalPhrase` → `error {code: 'absent_phrase'}` (existing terminal path).
   Missing `cfg.hrAvatar` or empty `cfg.sessionToken` → `error {code: 'sdk_error'}`. In both cases
   the SDK is not loaded.
2. `emitState('connecting')`, load the SDK, `connect({ baseUrl, publishableKey, clientSecret: cfg.sessionToken, mount: mountEl, audioDeviceId?, completionPhrases: [endPhrase, finalPhrase], forwardTranscript: HR_AVATAR_FORWARD_TRANSCRIPT })`
   with `export const HR_AVATAR_FORWARD_TRANSCRIPT = false`. `false` is safe for the conversation
   lifecycle: HR-Avatar reconciliation item 39 guarantees that `forwardTranscript: false` suppresses
   **utterance** forwarding only, and that the lifecycle events (`live`, `error`) are always forwarded,
   because for the `mock` and `heygen` transports the client `live` event is HR-Avatar's only
   `connecting → live` transition. Without that guarantee BEAI's `false` would strand every
   conversation in `connecting` server-side.
3. SDK `state connecting` → `connecting`; SDK `state live` → `ready`; SDK `transcript {final: true}` →
   `transcript {role, text, ts: occurredAt}` (interim dropped); a final avatar line matching
   `matchesEndPhrase()` → `whenAvatarSilent(COMPLETION_SETTLE_MS)` raced with `closingFallbackMs(text)`
   → `complete()`. Terminal mapping (validation finding 2, see D-COMPLETE for the latch):
   SDK `state ended` → `stopped`; SDK `ended{reason}`: `completion_phrase` → `complete()`, `error` →
   `error`, `user`/`server`/`provider` → `stopped`; SDK `state error` and SDK `error` event → `error`.
   The completion/error latch takes precedence: `stopped` is emitted at most once per start and never
   after `complete` or `error`.
4. Failures map to `{code: 'origin_not_allowed' | 'sdk_error', message: 'provider_unavailable'}`;
   the SDK message is never forwarded. **Connect-time server refusals** (validation finding 7): the
   browser's connect is the first call that touches the provider, so three HR-Avatar codes surface
   only **after** BEAI's `/start` has already returned 201: `provider_concurrency_limited` (429),
   `provider_credential_missing` and `provider_error`. The SDK rejects `connect()` (or emits `error`)
   with an `HrAvatarError` carrying one of those codes; the adapter maps each to the recoverable
   `sdk_error` (never `origin_not_allowed`, never `absent_phrase`). The retry path is the existing one
   and needs no new code: a non-`absent_phrase` provider error moves the session to the retryable
   `error` state (`useInterviewSession.ts:1604`, `:1612-1618`); the candidate's retry calls `/start`
   again; the api resumes the `in_corso` row, issues a new conversation and ends the old one
   (D-TEARDOWN, "Resume" in Data Flow). BEAI's own 429 retry (3 attempts, 3 s) does **not** apply here,
   because that rule keys on the `/start` HTTP status, which was 201. A persistent
   `provider_credential_missing` is an operator fault (HR-Avatar account setup) and is documented in
   Rollout.
`toggleMic`/`setMicMuted` delegate (`setMicMuted` asserts, `toggleMic` flips). `whenAvatarSilent(maxMs)`
is `Promise.race([sdk.whenAvatarSilent(AVATAR_SETTLE_MS), sleep(maxMs)])` with its rejection
swallowed. `AVATAR_SETTLE_MS` is **imported** from `~/app/providers/tavus` (`tavus.ts:71`, value 500,
its own "UNMEASURED" note applies) and is **not moved**: `tavus.ts` is already in the default-path
bundle through the static import in `factory.ts`, so the import adds no new code to any chunk, and
moving the constant would edit a Tavus file this change promises not to touch. `stop()` latches,
calls `end()` once and swallows errors. `nudgeWrapUp` is omitted (optional in the contract; the spec
allows a no-op).
**Rationale**: the same contract shape as the two existing providers, with the shared completion
utilities and settle constant reused rather than re-implemented.

### D-COMPLETE: two completion triggers, one `complete`

**Choice**: see item 6. One per-start `terminal` latch (`null | 'complete' | 'error' | 'stopped'`),
reset only in `start()`:

| Input | Latch `null` | Latch set |
|---|---|---|
| BEAI end-phrase match on a final avatar line | arm the settle race (`completing = true`); its resolution emits `complete` and sets `complete` | ignored |
| SDK `ended{completion_phrase}` | emit `complete`, set `complete` | ignored |
| SDK `ended{error}`, SDK `state error`, SDK `error` | emit `error`, set `error` | ignored |
| SDK `state ended`, SDK `ended{user\|server\|provider}` | if `completing`: emit `complete` at once (the conversation is over, the settle wait is moot), set `complete`; else emit `stopped`, set `stopped` | ignored |

The SDK spec says `ended` fires exactly once and `state` emits `connecting, live, ended` in order
(`hr-avatar/openspec/changes/hr-avatar-engine/specs/client-sdk/spec.md:60-70`), but not the order of
`state ended` relative to the `ended` event. So that a `state ended` arriving in the same tick just
before `ended{completion_phrase}` cannot pre-empt `complete` with `stopped`, the `stopped` emission for
SDK `state ended` is deferred by one macrotask (`setTimeout(0)`) and re-checks the latch when it runs;
`ended{…}` is handled synchronously. Net guarantees: `complete` at most once, `stopped` at most once,
never `stopped` after `complete` or `error`.
**Alternatives considered**: ignoring SDK `state ended` (the previous design; it contradicts the
spec's `connecting, ready, stopped` state-mapping scenario and drops the `stopped` signal when the SDK
reports the state without a reasoned `ended`); emitting `stopped` synchronously (races
`completion_phrase`).
**Rationale**: the BEAI matcher is a superset of the SDK's (accent and punctuation), so BEAI never
completes later than the SDK; the SDK trigger still covers a transport that closes first.

### D-SDK: vendored tarball

**Choice**: `cd hr-avatar/sdk && bun run build && bun pm pack --destination ../../frontend/vendor`
(file `hr-avatar-sdk-<ver>.tgz`); `cd frontend && bun add ./vendor/hr-avatar-sdk-<ver>.tgz`
(writes `file:` plus integrity to `bun.lock`); `frontend/Dockerfile` `COPY vendor ./vendor` next to
`COPY package.json bun.lock ./` (line 14); `docs/version-catalog.md` row under "Runtimes and
frameworks": `@hr-avatar/sdk` | `<ver>` (vendored, exact) | optional peers `@daily-co/daily-js`
`^0.91`, `@heygen/liveavatar-web-sdk` `^0.0.18`, already direct dependencies of `frontend`.
The catalog row is written **in slice F1, in the same work unit that adds the dependency** (a wrapper
commit made alongside the frontend commit), not deferred to W1: `CLAUDE.md` makes D25 the single
source of truth for pinned versions and says the stack table and D25 must never diverge, so a
dependency must never exist in `bun.lock` without its row. W1 only re-verifies it.
**Alternatives considered**: see the proposal table (`file:../hr-avatar/sdk`, git dependency and Bun
workspace are all unusable for a bare `frontend` clone).
**Rationale**: self-contained and deterministic. Replacing it with the published package later is a
one-line change. If the tarball does not resolve, the Dependency Resolution Policy applies: stop and
report.

### D-SCRAMBLE: OpenAPI re-export procedure

Every api slice that changes a documented surface re-exports in the same commit:

```bash
cd api && DB_CONNECTION=pgsql DB_HOST=127.0.0.1 DB_PORT=5432 DB_DATABASE=beai_test \
  DB_USERNAME=postgres DB_PASSWORD=postgres DB_URL= php artisan scramble:export
git diff --exit-code openapi.v1.json        # MUST be clean: no /v1 change
git diff openapi.json                        # MUST be additive only (reviewed)
```

Expected additive diff: the start 201 (`hr_avatar?`), the `AvatarTemplateResource` schema
(`hr_avatar_config_id?`), **the `PlatformAvatarTemplateResource` schema (`hr_avatar_config_id?`,
inherited: it `extends AvatarTemplateResource` and spreads `parent::toArray()`,
`PlatformAvatarTemplateResource.php:22,39`; the member is always absent at runtime because a platform
template can never be `hr_avatar` and the export command skips platform rows)**, field specs
(`hr_avatar?`), the store/update bodies (`hr_avatar_config_id`, `provider` enum + `hr_avatar`), and the
catalogue query enums (`hr_avatar`, `avatar_config`). Exactly **one disclosed non-additive change
(spec amendment A6)**: the organization store body's `config` leaves the `required` list because it
is now `required_unless:provider,hr_avatar`. Runtime for heygen and tavus is unchanged (same 422 key,
status and message text through the custom message in D-TEMPLATES), proved by the existing template
suites run unedited. Any other non-additive line in the diff is a defect, not a disclosure. If Scramble
loses the store or update body schema (an empty object in the diff), inline the literal rule array in
the controller method; never ship an empty schema. Consumers sync
the file in their own slices (`frontend` and `backoffice`: copy `api/openapi.json`, then
`bun run codegen`).

### D-EXPOSE: T-EXPOSE-001 classification of conditional fields

**Choice**: `ExposureCatalogue` gains a new method `conditionalExclusions()`. Existing entries are
not edited:

```php
'AvatarTemplate' => ['hr_avatar_config_id'],                         // admin-only, present only when set
'PlatformAvatarTemplate' => ['hr_avatar_config_id'],                 // superadmin-only, inherited, never set in practice
'AvatarTemplateExport' => ['templates[].hr_avatar_config_id'],       // admin export document only
'InterviewStart' => ['hr_avatar.base_url', 'hr_avatar.publishable_key'], // candidate start response only
```

New `api/tests/Feature/PublicApi/Exposure/HrAvatarExposureTest.php`: for each entry, the key set
with the value present minus the key set with it absent equals the list, none of the keys appears in
`ProjectSerializer`/`InterviewSerializer` output, and `openapi.v1.json` contains neither
`hr_avatar_config_id` nor `hr_avatar`.
**Rationale**: the existing Project exposure test compares exact sets on a fixture whose id is null,
so adding the key to `exclusions()['Project']` would break an existing test. A separate,
fully-classified section keeps "existing suites unedited" and still forces classification.

### D-BO-TYPES: backoffice types without widening `ProviderName`

**Choice** (validation finding 10): `ProviderName` (`backoffice/app/types/avatar-template.ts:50`)
stays `'heygen' | 'tavus'`. It keys `Record<ProviderName, …>` maps and types `PlatformTemplate.provider`
(:295) and the platform page, none of which can ever hold `hr_avatar`; widening it would make every
`Record<ProviderName, FieldSpec[]>` literal `{ heygen: [], tavus: [] }` (`avatar-templates/index.vue:400`,
`platform-templates/index.vue:259`) a type error and would claim platform templates can be `hr_avatar`.
Instead:

```ts
// backoffice/app/types/avatar-template.ts
export type ProviderName = 'heygen' | 'tavus'                    // unchanged
/** An organization template's provider. `hr_avatar` exists only while the api reports it. */
export type TemplateProvider = ProviderName | 'hr_avatar'
/** The field-specs map: always heygen and tavus; hr_avatar only when the api reports the capability. */
export type FieldSpecMap = Record<ProviderName, FieldSpec[]> & { hr_avatar?: FieldSpec[] }
export type FieldSpecsResponse = { data: FieldSpecMap }           // was Record<ProviderName, FieldSpec[]> (:193)
// AvatarTemplate.provider: TemplateProvider                       // was ProviderName (:232); PlatformTemplate untouched
```

`FieldSpecMap` replaces `Record<ProviderName, FieldSpec[]>` at the three sites named above (:193, :400,
:259) and in the form prop (`AvatarTemplateForm.vue:521`); the existing `{ heygen: [], tavus: [] }`
initialisers still type-check because `hr_avatar` is optional. The form's provider state and the
create payload cast (`avatar-templates/index.vue:580`, `(payload.provider ?? 'heygen') as ProviderName`)
use `TemplateProvider`.

`CatalogueProvider` and `CatalogueResource` are derived from the generated client (:64, :71), so
after the openapi sync they gain `hr_avatar` and `avatar_config` with no hand edit. That widening
reaches `AvatarTemplateProviderCombobox.vue`: `previewProvider` (:473) is typed
`'heygen' | 'cartesia' | 'elevenlabs' | null` and today narrows only `tavus` to `null`, and
`blockPreview.provider` (:477) falls back to `props.provider`, while the `preview` prop (:452) is the
closed union `'heygen' | 'tavus' | 'cartesia' | 'elevenlabs'`. Both computeds gain the `hr_avatar` →
no-preview branch (an HR-Avatar config has no voice sample), so the `preview` prop type and
`useVoicePreview` are left as they are. The gate is `bun run typecheck` (`nuxi typecheck` plus the
e2e tsconfig) exiting 0 in B1, alongside lint and the unit suite.
**Alternatives considered**: widening `ProviderName` (the previous design; breaks the two `Record`
initialisers and types platform templates as possibly `hr_avatar`); a `Partial<Record<…>>` map (loses
the guarantee that `heygen` and `tavus` are always present, forcing `?.` at every existing read).
**Rationale**: the narrowest types that tell the truth: the capability is optional, existing keys are
guaranteed, and platform code cannot see `hr_avatar` at all.

## Data Flow

### `POST /candidate/interview/start`, `hr_avatar` session (fresh)

```
Browser            InterviewController            ProviderPreflight   HrAvatarProvider        HR-Avatar
  | POST /start          |                                |                   |                     |
  |--------------------->| providerNameFor(): pinned tpl  |                   |                     |
  |                      |   provider = hr_avatar         |                   |                     |
  |                      |--check('hr_avatar', project)-->| available? id?    |                     |
  |                      |<----------- [] ----------------|                   |                     |
  |                      | compose prompt + opening;      |                   |                     |
  |                      | createOrResumeSession(pending) |                   |                     |
  |                      | resolveProvider('hr_avatar') ------------------->  |                     |
  |                      |------------- issue(session, ctx) ----------------->| POST /v1/conversations
  |                      |                                |                   |-------------------->|
  |                      |                                |                   |<-- 201 {id, secret}-|
  |                      |<------ ProviderToken{hr_avatar, token=secret, ref=conv_…}               |
  |                      | txn: ref, in_corso, llm snapshot (unbound), live period, participant    |
  |<-- 201 {provider: hr_avatar, provider_token: secret, hr_avatar:{base_url, publishable_key}, …}  |
  | createProvider('hr_avatar') → deferred → import adapter → import SDK                          |
  | connect({baseUrl, publishableKey, clientSecret, mount, completionPhrases, forwardTranscript:false})
  |----------------------------------------------------------------------------------------------->|
  | transcript lines → POST /utterance (BEAI)   …   complete → POST /end (BEAI) → teardown → /end   |
```

Failure exits: preflight non-empty → 422 `interview_configuration_invalid` (no session row); 429 →
`provider_busy`, session stays `pending`; 4xx → 500, participant unchanged; 5xx/timeout/malformed →
502, participant `errore`.

### Resume (`in_corso`)

`issue()` creates `conv_NEW` → `teardown(fromRef(hr_avatar, conv_OLD))` (best effort, logged) → txn
stores `conv_NEW` → 201 with the new secret. Matches `handleResumeInCorso()` unchanged.

### Catalogue proxy

```
Backoffice ─GET /api/avatar-templates/catalogue?provider=hr_avatar&resource=avatar_config─▶ AvatarTemplateController
  authorize viewAny (admin) ─▶ validate (hr_avatar only while available, else 422)
  ─▶ AvatarProviderCatalogue::fetch('hr_avatar','avatar_config', orgId)
       cache hit (key …:hr_avatar:avatar_config:org{orgId}, 5 min) ─▶ return
       miss ─▶ GET /v1/avatar-configs?external_ref=org_{orgId} (server-side filter, ≤10 pages)
            ─▶ keep synced|not_required; drop any row whose external_ref != org_{orgId} (defence in depth)
            ─▶ entry(...) items ─▶ cache only status ok ─▶ {status, items[, code]}
```

### Export command

```
avatar_templates (withoutGlobalScopes, org rows, not deleted) ──▶ classify per row
  dry run:  print would_create / already_linked, count, exit 0 (no HTTP, no write)
  --apply:  unavailable? exit 1 (names only)
            POST /v1/avatar-configs {name, provider, config, voice?, external_ref: org_{org}}
              201 avc_… ─▶ UPDATE avatar_templates SET hr_avatar_config_id WHERE id AND org AND id IS NULL
                          ─▶ print "created avc_… sync_status=<synced|not_required|pending|…>"
              else ─▶ failed <code>, continue, exit 1 at end
            summary: counts by sync_status; reminder that pending configs cannot start until synced
```

## Multi-tenancy (explicit query scopes)

| Query | Scope |
|---|---|
| `providerNameFor`: pinned template provider | `AvatarTemplate::availableToTenant()` (existing) under the candidate's tenant context |
| `ActiveTemplateResolver::resolve('hr_avatar', projectId)` in `issue()` and preflight | `Project` via `TenantScoped`; template via `availableToTenant()` (existing) |
| Template CRUD, resource, export document | `TenantScoped` global scope (existing); another tenant's row is a 404 |
| Catalogue proxy | HR-Avatar list requested with the server-side filter `external_ref=org_{TenantResolver::getOrgId()}` (reconciliation item 38) and re-checked row by row; cache key built by `cacheKey(..., $orgId)` includes the organization id; null organization → empty, no request |
| Export command read | `withoutGlobalScopes()` + `whereNotNull('organization_id')` (platform rows excluded); each POST carries the row's own `organization_id` attribution |
| Export command write | `where('id')->where('organization_id')->whereNull('hr_avatar_config_id')` |
| Release/teardown | `ReleaseProviderSession::markReleased()` keeps its explicit `organization_id` predicate |

## File Changes

### api (submodule `api`, branch `feature/extract-avatar-service`)

| File | Action | Description |
|---|---|---|
| `config/hr_avatar.php` | Create | `base_url`, `secret_key`, `publishable_key` from `HR_AVATAR_*` |
| `.env.example` | Modify | Three blank `HR_AVATAR_*` entries with a one-line comment |
| `app/Services/Provider/HrAvatarConnection.php` | Create | D-CONN |
| `app/Services/Provider/HrAvatarProvider.php` | Create | D-ISSUE, D-TEARDOWN, `reconcileTranscript()` = `[]` |
| `database/migrations/2026_10_19_100000_add_hr_avatar_config_id_to_avatar_templates.php` | Create | `string('hr_avatar_config_id', 64)->nullable()`; `down()` drops it; no FK, no index |
| `app/Models/AvatarTemplate.php` | Modify | `$fillable`, `@property string|null $hr_avatar_config_id` |
| `app/Http/Controllers/Candidate/InterviewController.php` | Modify | `providerNameFor` (:1703), `resolveProvider` (:1931; reached from :348, :437, :480, :593, :700), `@scramble-return` of `start` (:121) |
| `app/Actions/Interview/ReleaseProviderSession.php` | Modify | `'hr_avatar'` arm (:56) |
| `app/Services/Provider/ProviderPreflight.php` | Modify | `hr_avatar` arm (:52) |
| `app/Actions/Interview/BuildInterviewSessionResponse.php` | Modify | D-START |
| `app/Http/Controllers/AvatarTemplateController.php` | Modify | D-TEMPLATES store/update/activate/fieldSpecs (including the single-422 merge at :228/:233 and the `required_unless` custom message), D-PROXY catalogue |
| `app/Support/AvatarTemplates/ConfigValidator.php` | Modify | `hr_avatar` arm: every key `unknown` |
| `app/Http/Resources/AvatarTemplateResource.php` | Modify | Conditional member + docblocks |
| `app/Support/AvatarTemplates/TemplateDocument.php` | Modify | Export/flatten the member |
| `app/Http/Controllers/AvatarTemplatePortabilityController.php` | Modify | `reject()` provider check and id/llm rules; `create()` force-fill |
| `app/Actions/AvatarTemplates/DuplicateAvatarTemplate.php` | Modify | Copy the id |
| `app/Support/AvatarTemplates/AvatarProviderCatalogue.php` | Modify | `fetch(..., ?int $organizationId)`, `cacheKey(..., ?int $organizationId = null)` (:168), `fetchLive(..., ?int)`, `hrAvatarConfigs()` with the `external_ref` query filter |
| `app/Console/Commands/ExportTemplatesToHrAvatar.php` | Create | D-EXPORT (per-row `sync_status`, summary) |
| `tests/Helpers/PublicApi/ExposureCatalogue.php` | Modify | New `conditionalExclusions()` only (four entries, including `PlatformAvatarTemplate`) |
| `openapi.json` | Modify (generated) | D-SCRAMBLE; `openapi.v1.json` unchanged |
| `tests/…` | Create | See Testing Strategy |

Not changed: `app/Providers/InterviewServiceProvider.php` (see D-SELECT),
`app/Http/Controllers/Api/PlatformAvatarTemplateController.php`, `ProviderSmokeCheck`,
`SessionCostEstimator`, `SessionLiveClock`, the shared validation trait.

### frontend (submodule `frontend`)

| File | Action | Description |
|---|---|---|
| `vendor/hr-avatar-sdk-<ver>.tgz` | Create | D-SDK (binary) |
| `package.json`, `bun.lock` | Modify | `file:` dependency |
| `Dockerfile` | Modify | `COPY vendor ./vendor` before `bun install` |
| `nuxt.config.ts` | Modify | `public.hrAvatarEnabled: ''` (`NUXT_PUBLIC_HR_AVATAR_ENABLED`) |
| `openapi.json`, `types/api.ts` | Modify (generated) | Sync from api, `bun run codegen` |
| `app/types/interview-provider.ts` | Modify | `ProviderName` + `'hr_avatar'`; `StartConfig.hrAvatar?: { baseUrl: string; publishableKey: string }` |
| `app/providers/factory.ts` | Modify | D-FACTORY |
| `app/providers/hr-avatar.ts` | Create | D-ADAPTER (imports `AVATAR_SETTLE_MS` from `~/app/providers/tavus`; `tavus.ts` itself is not edited) |
| `app/composables/useInterviewSession.ts` | Modify | `startConfig` (:2025): `...(response.hr_avatar ? { hrAvatar: {...} } : {})` |
| `tests/unit/hr-avatar-start-config.spec.ts`, `tests/unit/hr-avatar-provider.spec.ts`, `tests/unit/hr-avatar-provider-completion.spec.ts`, `tests/unit/hr-avatar-factory.spec.ts`, `tests/unit/hr-avatar-connect-retry.spec.ts` | Create | See Testing Strategy |
| `tests/e2e/interview-default-provider-path.spec.ts` | Create | Playwright, both desktop projects: flag off, default path renders the call stage and requests no HR-Avatar chunk (see Testing Strategy, E2E) |

`@beai/embed` (wrapper `embed/`) is not touched.

### backoffice (submodule `backoffice`)

| File | Action | Description |
|---|---|---|
| `openapi.json`, `types/api.ts` | Modify (generated) | Sync from api, `bun run codegen` |
| `app/types/avatar-template.ts` | Modify | D-BO-TYPES: `ProviderName` **unchanged**; new `TemplateProvider = ProviderName \| 'hr_avatar'` for `AvatarTemplate.provider` only; `FieldSpecsResponse.data` (:193) becomes `FieldSpecMap`; `CatalogueProvider`/`CatalogueResource` widen by themselves through the regenerated client; `AvatarTemplate.hr_avatar_config_id?`; submit type |
| `app/components/organisms/AvatarTemplateForm.vue` | Modify | `fieldSpecs` prop (:521) typed `FieldSpecMap`; form provider state (:556) typed `TemplateProvider`; `providers` (:551) computed: `['heygen','tavus']`, plus `'hr_avatar'` iff `fieldSpecs.hr_avatar !== undefined`; picker block when provider is `hr_avatar` (reuses `AvatarTemplateProviderCombobox` with a synthetic field `{key: 'hr_avatar_config_id', catalogue_resource: 'avatar_config', required: true}`); LLM block hidden; client check `^avc_[0-9A-Za-z]+$`; 422 `hr_avatar_config_id` mapped by `applyServerFieldErrors`; submit adds `hr_avatar_config_id` and `config: {}` **only** for `hr_avatar` |
| `app/components/organisms/AvatarTemplateProviderCombobox.vue` | Modify | Optional prop `manualOnEmpty` (default false) that also renders the manual input in the `empty` state; `previewProvider` (:473) returns `null` for `hr_avatar` as for `tavus`; `blockPreview` (:476) yields no preview for `hr_avatar`, so the `preview` prop type (:452) and `useVoicePreview` stay as they are and no sample control renders |
| `app/composables/useAvatarTemplates.ts` | Modify | `hr_avatar_config_id?` in create/update payload types |
| `app/pages/avatar-templates/index.vue` | Modify | `fieldSpecs` ref (:400) typed `FieldSpecMap`; forward `hr_avatar_config_id` only when present (:567, :577) |
| `app/pages/platform-templates/index.vue` | Modify | `fieldSpecs` ref (:259) typed `FieldSpecMap` (type only: it shares `FieldSpecsResponse`; the platform endpoint never returns `hr_avatar`) |
| `i18n/locales/{it,en}.json` | Modify | `avatar_templates.provider.hr_avatar`, picker label and hint; **`projects.avatarProvider.hr_avatar`** (read by `ProjectTable.vue:65` for a project pinned to an `hr_avatar` template; without it the column renders the raw key) |
| `tests/unit/avatar-template-form-hr-avatar.spec.ts` | Create | See Testing Strategy |

### wrapper

| File | Action | Description |
|---|---|---|
| `docs/version-catalog.md` | Modify | `@hr-avatar/sdk` row (D-SDK), committed in slice **F1** with the dependency |
| `openspec/changes/hr-avatar-adapter/specs/*/spec.md` | Modify | Spec amendments A1-A7 (applied in the design phase and its corrective re-run) |

## Interfaces / Contracts

```php
// api/config/hr_avatar.php
return [
    'base_url' => env('HR_AVATAR_BASE_URL'),
    'secret_key' => env('HR_AVATAR_SECRET_KEY'),
    'publishable_key' => env('HR_AVATAR_PUBLISHABLE_KEY'),
];

// api/app/Services/Provider/HrAvatarConnection.php
final class HrAvatarConnection
{
    public const PROVIDER = 'hr_avatar';
    /** true iff all three are non-empty after trim and base_url is an absolute http(s) URL. No I/O. */
    public static function isAvailable(): bool;
    /** @return list<'HR_AVATAR_BASE_URL'|'HR_AVATAR_SECRET_KEY'|'HR_AVATAR_PUBLISHABLE_KEY'> names only */
    public static function missingVariables(): array;
    public static function baseUrl(): string;         // rtrim('/')
    public static function publishableKey(): string;
    public static function secretKey(): string;       // server-side only; never serialized or logged
    public static function client(): PendingRequest;  // baseUrl + withToken(secret) + acceptJson + timeout(15)
    public static function organizationRef(int $organizationId): string; // "org_{$organizationId}"
    /** Validation closure: fails with the `validation.in` message for 'hr_avatar' while unavailable. */
    public static function unavailableProviderRule(): Closure;
}

// api/app/Support/AvatarTemplates/AvatarProviderCatalogue.php (existing, extended; null keeps today's behaviour)
public static function fetch(string $provider, string $resource, bool $fresh = false, ?int $organizationId = null): array;
public static function cacheKey(string $provider, string $resource, ?int $organizationId = null): string; // + ":org{$id}" when non-null

// POST /v1/conversations body built by HrAvatarProvider::issue()
[
    'avatar_config_id' => 'avc_…',
    'system_prompt' => $ctx->systemPrompt,          // ≤ 32000, never truncated
    'opening_text' => $ctx->openingText,            // ≤ 4000
    'language' => $ctx->language,                   // ^[a-z]{2}$
    'max_duration_seconds' => clamp(resolveMaxSeconds($session), 30, 3600),
    'external_ref' => "session_{$session->id}",
    'metadata' => new \stdClass,                    // serializes as {}
]
```

`/start` 201 for `hr_avatar` (other providers unchanged):

```json
{ "session_id": 1, "provider": "hr_avatar", "audio_only": false,
  "provider_token": "<client_secret>", "conversation_url": null,
  "question_context": { "...": "unchanged" }, "interview_max_seconds": 1200,
  "answer_min_seconds": 90, "answer_max_seconds": 150,
  "hr_avatar": { "base_url": "https://hra.example.test", "publishable_key": "hra_pk_live_…" } }
```

```ts
// frontend/app/types/interview-provider.ts
export type ProviderName = 'heygen' | 'tavus' | 'hr_avatar'
export interface StartConfig { /* existing fields unchanged */ hrAvatar?: { baseUrl: string; publishableKey: string } }

// frontend/app/providers/hr-avatar.ts
export const HR_AVATAR_FORWARD_TRANSCRIPT = false
export class HrAvatarProvider implements InterviewProvider {
  constructor(sdkLoader?: () => Promise<typeof import('@hr-avatar/sdk')>) // type query, not an import line
}
```

## Testing Strategy

Strict TDD: every behaviour starts with a RED test. **No existing test file is edited**; the
unedited existing suites are the proof of default-path invariance. `Http::preventStrayRequests()` in
every new api test.

| Layer | What to test | Approach |
|---|---|---|
| api unit | `HrAvatarConnection` availability (all, each missing, blank, malformed URL), no HTTP | `tests/Unit/HrAvatar/HrAvatarConnectionTest.php`, `config()` overrides |
| api unit | `issue()` body is exactly 7 members, `metadata` is `{}`, clamp 10→30 / 99999→3600, `external_ref` has no candidate data, no `display_name`; token mapping; malformed 201 → Upstream; oversize prompt/opening, null id, bad language → ClientError with no request; 429/422/409/503/timeout classification, including 403 `insufficient_scope` → ClientError and 409 `config_not_synced` → ClientError with the code in the log; message/log carry `code` and status class and never the secret, prompt or `detail` | `tests/Unit/HrAvatar/HrAvatarProviderTest.php`, `Http::fake` with `Http::assertSent`/`assertSentCount`, `Log::spy()` |
| api unit | `teardown()`: one `/end`; 404/503/timeout never throw and log without the secret; null/`abc` ref → no request | same file |
| api feature | Selection: pinned `hr_avatar` → `hr_avatar` + one `/v1/conversations`; test mode → `mock`, no HR-Avatar request; stored override `hr_avatar` (written directly to the row: no validation exists to refuse it, D-SELECT) → ignored, env default; env `hr_avatar` → `heygen`; tavus pin + heygen override → `tavus`; container spies prove `HeygenProvider`/`TavusProvider` never constructed | `tests/Feature/HrAvatar/HrAvatarSelectionTest.php` |
| api feature | Fail closed: unavailable + pinned `hr_avatar` → 422 `interview_configuration_invalid` (`provider_key_missing`), no session row, participant unchanged, no request, no fallback even with override `tavus`; test mode still succeeds | `tests/Feature/HrAvatar/HrAvatarFailClosedTest.php` |
| api feature | `/start` shape: `hr_avatar` object, `provider_token` = secret, no `conversation_id`/`conversation_ttl_seconds`/`continuation`; `live_conversation_id` ignored; secret key and prompt absent from body and headers; `client_secret` not in any DB row (scan `interview_sessions`), log or queued payload; three competencies → three conversations, distinct refs, no `conversation_plan`; resume → new conv, `/end` of the old one, 503 on that end still 201 (this is also the server half of the connect-failure retry path, D-ADAPTER step 4); `/suspend` of an `hr_avatar` session → one `/end`, no HeyGen call; `/end` keeps the 6 live utterances and releases at once (no handover deferral); snapshot `unbound`/null model; review without a rate → no cost estimate; failure matrix 429/422/409 `config_not_synced`/503 | `tests/Feature/HrAvatar/HrAvatarInterviewFlowTest.php` |
| api feature | **Invariance**: golden `/start` bodies for a Tavus and a HeyGen session recorded **on the unmodified base** in the first RED commit (`tests/Fixtures/hr_avatar/start-{tavus,heygen}.json`), compared after the change with `HR_AVATAR_*` both unset and fully set; field specs exactly `{heygen, tavus}` when unset; catalogue `hr_avatar` → 422 and no request when unset | `tests/Feature/HrAvatar/HrAvatarDefaultPathInvarianceTest.php` |
| api feature | Templates: create 201 inactive; unavailable → 422 on `provider`, no row; `config` omitted for `hr_avatar` → 201 with `config` `{}`; `config` omitted for heygen/tavus → 422 on `config` with exactly the pre-change message text (A6); field specs key only when available; `config` knobs → `config.avatarId` + `config.nonsense` `unknown`; id required; malformed `cfg_1` id **and** an unknown config key → ONE 422 whose `errors` carries both `hr_avatar_config_id` and `config.nonsense` (finding 1); PATCH null → 422; `llm_model_id` → 422; activation refused while unavailable; rename while unavailable succeeds; no outbound request on create/update/activate/delete; null id omitted from resource and export; tavus with id → Tavus body identical; export/import round trip; import of an `hr_avatar` block while unavailable fails; superadmin duplicate copies the id; PATCH provider to/from `hr_avatar` → 422; platform store still refuses `hr_avatar`; cross-tenant: B's `avc_B` absent from A's list/show/export, B's id → 404 | `tests/Feature/HrAvatar/HrAvatarTemplateTest.php` |
| api feature | Proxy: every request carries `external_ref=org_<A>` in its query (`Http::assertSent`); three attributed synced configs → ok; a row with B's `external_ref` returned by a faked upstream that ignores the filter is still dropped (defence in depth); unattributed, `pending` and `failed` filtered; two pages merged, both with the filter; 503 with the secret in the body → `provider_error`/`provider_unavailable` and no secret; 403 → `provider_unauthorized`; cached second call → no request; `cacheKey('hr_avatar','avatar_config', A)` ends `:org{A}` and `cacheKey('tavus','pal')` equals its pre-change value; operator/viewer 403; unavailable → 422 | `tests/Feature/HrAvatar/HrAvatarCatalogueProxyTest.php` |
| api feature | Export command: dry run → no request, no write, three `would_create`, works while unavailable; `--apply` unavailable → exit 1, names only; apply writes only the id (row compared column by column, including `updated_at`, `is_active`, `provider`); each created line prints its `sync_status` (`synced`, `pending`; a hostile value prints `unknown`) and the summary counts them; attribution per organization; idempotent re-run; one 422 + one 201 → `failed` + linked + exit 1; 403 → `failed provider_unauthorized`; no key, LLM binding or display name in any body; platform template skipped | `tests/Feature/HrAvatar/ExportTemplatesToHrAvatarTest.php` |
| api feature | T-EXPOSE-001 conditional section | `tests/Feature/PublicApi/Exposure/HrAvatarExposureTest.php` (D-EXPOSE) |
| frontend unit | Factory: runtime flag off (`undefined`, `''`, `1`, `'1'`, `'yes'`, `false`) → the existing unknown-provider error, adapter module not imported (`vi.doMock` factory sets a flag when evaluated); runtime `true` and `'true'` → instance returned and SDK not imported (env `TRUE` reaches the factory as boolean `true` through `destr`, D-FACTORY); `mock: true` wins; heygen/tavus unchanged; `factory.ts` has no static `hr-avatar` import line | `tests/unit/hr-avatar-factory.spec.ts`, `vi.stubGlobal('useRuntimeConfig', …)` like the existing specs |
| frontend unit | Adapter: lazy SDK import; connect options (baseUrl, publishableKey, clientSecret, mount = page video, audioDeviceId, completionPhrases, `forwardTranscript === HR_AVATAR_FORWARD_TRANSCRIPT === false`); missing join inputs → `sdk_error` with no import; absent phrase → `absent_phrase`; state mapping `connecting, live, ended` → `connecting, ready, stopped`; final transcripts only; mic controls; bounded `whenAvatarSilent` using the imported `AVATAR_SETTLE_MS`; idempotent quiet `stop`; error codes `origin_not_allowed`/`sdk_error` with no vendor text or base URL host; connect rejected with `provider_concurrency_limited`, `provider_credential_missing` or `provider_error` → `sdk_error` each, no vendor text; no static `@hr-avatar` import line; locale files and created DOM free of `hr-avatar|hr_avatar|hravatar|hr avatar` | `tests/unit/hr-avatar-provider.spec.ts`, fake SDK through the injected loader |
| frontend unit | Completion and terminal latch: accent/punctuation end-phrase match → one `complete`; candidate phrase → no complete; `ended` reasons; both triggers → one `complete`; `state ended` then `ended{completion_phrase}` in the same tick → `complete` and no `stopped`; `ended{provider}` while a match is settling → `complete` at once, no `stopped`; `error` then `state ended` → no `stopped`; `stopped` at most once | `tests/unit/hr-avatar-provider-completion.spec.ts`, fake timers |
| frontend unit | `startConfig` mapping from a `/start` body (`hrAvatar` only when `hr_avatar` is present) | `tests/unit/hr-avatar-start-config.spec.ts`, through `useInterviewSession` with the stubbed fetch pattern of the existing session specs |
| frontend unit | Connect-failure retry path: a provider that emits `error {code: 'sdk_error'}` after a 201 `/start` moves the session to the retryable `error` state (not `terminal`, no automatic 429 backoff); the candidate retry issues a second `/start` with no `live_conversation_id` and a fresh adapter instance | `tests/unit/hr-avatar-connect-retry.spec.ts`, `useInterviewSession` with a stubbed fetch and a stubbed factory |
| backoffice unit | No `hr_avatar` key → options exactly `heygen, tavus`, no picker; key present → option, picker lists catalogue items, selecting sets the id; payload carries `hr_avatar_config_id`, `config: {}`, no label; `provider_error` and `empty` → manual input; 422 placed under the picker; edit shows the provider locked; heygen/tavus payload byte-identical; combobox renders no sample control for `hr_avatar`; `ProjectTable` renders `projects.avatarProvider.hr_avatar` in it and en | `tests/unit/avatar-template-form-hr-avatar.spec.ts` |
| backoffice static | Types compile with `ProviderName` unchanged and `FieldSpecMap`/`TemplateProvider` in place (D-BO-TYPES) | `bun run typecheck` (`nuxi typecheck` + e2e tsconfig) exit 0 |
| E2E (frontend) | **New** `tests/e2e/interview-default-provider-path.spec.ts`, run by the existing `chromium` and `webkit` projects against the production build the config already starts (`bun run build && node .output/server/index.mjs`, flag unset): reusing the route mocks of `interview-flow.spec.ts`, a `/start` answering `provider: 'heygen'` renders the existing call stage (same selector the existing call specs assert), and no JS response loaded during the run contains the adapter markers `forwardTranscript` or `completionPhrases` (object keys that survive minification and occur only in the adapter chunk). Why the existing e2e is not enough: every existing interview spec runs with `NUXT_PUBLIC_INTERVIEW_PROVIDER_MOCK=true` (`playwright.config.ts:126,156`), so `createProvider` returns the mock before any provider arm, and no existing spec looks at which chunks load. The new spec still uses the mock (the config forces it), so it proves the browser half (the default page loads no HR-Avatar code and renders as before); construction of the real `HeyGenProvider`/`TavusProvider` with the flag off is proved by the unedited `provider-factory.spec.ts` | Playwright, both desktop projects; the `mobile` project keeps asserting only the unsupported gate |
| E2E (backoffice) | None new. B1 adds a select option and a picker inside the existing form; the unedited backoffice Playwright suites run against the default api (no `hr_avatar` capability key), proving the form is unchanged there | existing CI |
| Build check | SSR bundle has no `@hr-avatar/sdk`; bare-clone install | `bun run build && ! rg -l '@hr-avatar/sdk' .output/server`; fresh clone `bun install --frozen-lockfile` |

Commands: api `php artisan test --parallel` and `php artisan test --coverage --min=98`, plus
`vendor/bin/pint --test` and `vendor/bin/phpstan analyse --memory-limit=1G`; frontend and backoffice
`bun run test:unit` (with coverage), `bun run lint` and `bun run typecheck`; frontend
`bun run test:e2e` (Playwright, chromium + webkit, includes the new default-path spec). New code coverage must be above 85% and the api global gate
stays at 98. Run Pest suites one at a time (shared test database).

## Work-unit slicing (auto-chain, each ≲ 400 authored lines; generated files excluded)

| # | Repo | Slice | Est. lines | Depends on |
|---|---|---|---|---|
| A1 | api | config, `.env.example`, `HrAvatarConnection`, migration + model, `HrAvatarProvider` + unit tests | ~360 | — |
| A2 | api | golden fixtures (RED first, on base), selection arms, `ReleaseProviderSession`, preflight, start response, flow/fail-closed/invariance tests, Scramble re-export | ~400 | A1 |
| A3 | api | template validation, resource, `ConfigValidator`, field specs, portability, duplicate, exposure section + test, Scramble re-export | ~400 | A1 |
| A4 | api | catalogue proxy arm + tests, Scramble re-export | ~260 | A1, A3 |
| A5 | api | export command + tests | ~300 | A1 |
| F1 | frontend + wrapper | vendored tarball, `package.json`/`bun.lock`, Dockerfile, runtime flag, openapi sync, types, start mapping + tests; **`docs/version-catalog.md` row (wrapper commit in the same unit)** | ~290 | A2, **HR-Avatar S8** |
| F2 | frontend | `hr-avatar.ts` adapter (core, completion latch, connect-failure mapping) + tests | ~420 (split F2a/F2b in tasks) | F1 |
| F3 | frontend | factory deferred arm, connect-failure retry test, default-path Playwright spec, SSR/bundle checks | ~260 | F2 |
| B1 | backoffice | openapi sync, D-BO-TYPES, form option + picker, combobox prop and preview narrowing, page forwarding, i18n (incl. `projects.avatarProvider.hr_avatar`) + tests | ~360 | A3, A4 |
| W1 | wrapper | re-verify the catalog row, commit SDD artifacts, cross-repo evidence | ~0 authored | F1 |

A2 is the slice most likely to exceed the budget; if it does, split the flow tests (A2b) from the
selection and response code (A2a). Local commits only, on `feature/extract-avatar-service` in each
submodule; no push.

## Security

- **Secret key**: read only in `HrAvatarConnection`; never in a resource, response, log context,
  exception message or command output (commands print variable names only). Tests grep every
  response and `Log::spy` call for a sentinel secret.
- **client_secret**: in memory from `issue()` to the 201 body; not on `interview_sessions` (only the
  `conv_` ref), not in logs (the controller logs refs only), not in queue payloads
  (`ReleaseEndedProviderSessionJob` carries provider and refs).
- **Untrusted upstream text**: Problem `code` is allowlisted by regex; `detail` is never read.
- **Path injection**: refs are validated `^conv_[0-9A-Za-z]+$` before being placed in a URL.
- **SSRF**: the base URL comes from operator environment only, never from a request or tenant data.
- **Cross-tenant use of a config id (residual, accepted)**: the proxy never shows another tenant's
  config, and ids are unguessable ULIDs, but an admin who learned another tenant's `avc_…` id could
  type it into the manual-entry fallback, because the spec forbids an existence or attribution check
  on write and any extra call in `issue()`. Upgrade path, if ever needed: one
  `GET /v1/avatar-configs/{id}` on template write, comparing `external_ref`.
- **Candidate PII to HR-Avatar**: no name or email in the prompt or body (item 5); candidate speech
  still lands in HR-Avatar's transcript store. Blocks enabling outside local (proposal decision 2).

## Threat Matrix

N/A: the change adds no shell command, subprocess, version-control or PR automation,
executable-file classification or process integration. Rows: documentation-like paths N/A (nothing
is executed from files); Git repository selection N/A; commit state N/A; push state N/A (no push in
scope); PR commands N/A. The outbound HTTP and tenant boundaries are covered under Security and
Multi-tenancy, with tests.

## Migration / Rollout

- Migration: one nullable `varchar(64)` column on `avatar_templates`, no backfill; `down()` drops it.
  Nothing on the default path reads it.
- Rollout: dark by default. Local wiring only, in this order:
  1. HR-Avatar compose running, plus a `mock` config attributed `org_<id>`.
  2. **Secret key scopes** (validation finding 5): the HR-Avatar secret key given to BEAI as
     `HR_AVATAR_SECRET_KEY` MUST carry exactly the three scopes BEAI uses: `conversations:write`
     (create and end conversations), `avatar_configs:read` (the catalogue proxy) and
     `avatar_configs:write` (the export command's `--apply`). A missing scope is a 403 from HR-Avatar,
     which BEAI maps without retry: `issue()` → ClientError (start answers 500, participant
     unchanged, session `error`); `teardown()` → logged, returns false; the proxy →
     `provider_error`/`provider_unauthorized`; the export → `failed provider_unauthorized` and exit 1.
     None of these leaks the key or HR-Avatar's text; the log line's `code` is HR-Avatar's
     `insufficient_scope` (`hr-avatar/openspec/changes/hr-avatar-engine/specs/credentials/spec.md:48`),
     which passes the allowlist regex and names the gap.
  3. The publishable key's `allowed_origins` lists the BEAI frontend origin (else the adapter reports
     `origin_not_allowed`).
  4. **Flip both switches together** (D-FACTORY): first `NUXT_PUBLIC_HR_AVATAR_ENABLED=true` on
     frontend, then the three `HR_AVATAR_*` values on api. Nuxt coerces the env value with `destr`,
     which compares `true` case-insensitively: `true`, `TRUE` and `True` enable the flag; `1`, `yes`,
     empty and unset do not. With api available and the flag off, every `hr_avatar` start creates an
     HR-Avatar conversation and then fails in the browser (retryable error screen, conversation left to
     expire after 900 s or ended by the sweep).
  5. `hr-avatar:export-templates` dry run, then `--apply`; read each row's `sync_status`. **Pin a
     project to an `hr_avatar` template only once its config is `synced` or `not_required`** (it then
     appears in the backoffice picker); a `pending` config makes every start fail with 409
     `config_not_synced` → 500 until HR-Avatar finishes the sync.
  6. Connect-time refusals after a successful `/start` (`provider_concurrency_limited`,
     `provider_credential_missing`, `provider_error`) show the candidate the retryable error screen;
     a persistent `provider_credential_missing` means the HR-Avatar account lacks the provider
     credential for that config and is fixed in HR-Avatar, not in BEAI.
- Rollback: unset `HR_AVATAR_*` first (pinned `hr_avatar` templates then fail closed at pre-flight),
  then the frontend flag; revert slice commits; `--apply` is undone by setting the column back to
  NULL.

## Spec amendments (applied to the spec files in this phase)

- **A1** (`interview-session`, "A template pinned to hr_avatar fails closed…"): the closed failure is
  the existing pre-flight `422 interview_configuration_invalid` with reason
  `{key: credentials, code: provider_key_missing}`, raised before a session exists, with the session
  and participant untouched, instead of `502 provider_error` through the upstream-failure path
  (orchestrator item 1: an operator misconfiguration must not move the candidate to `errore`).
- **A2** (`hr-avatar-integration`, scenario "Secret key redacted from diagnostics"): the provider
  never reads `detail`, so neither the log nor the exception message contains the key or any part of
  `detail`. No `[REDACTED]` substitution is needed (reconciliation item 33).
- **A3** (`hr-avatar-integration`, `max_duration_seconds` row): the value is the ceiling
  `SessionLiveClock::resolveMaxSeconds()` derives for the session (1200 s for `hr_avatar`, whose
  templates carry no duration knob), clamped to 30..3600, so BEAI's countdown and HR-Avatar's
  ceiling agree. The earlier "otherwise 3600" parenthetical is dropped.
- **A4** (`hr-avatar-integration`, proxy item shape): items use the existing catalogue entry shape
  (`id`, `provider`, `label`, `name`, `language`, `locale`, `accent`, `italian`, `preview_image_url`,
  `preview_audio_url`, `preview_audio_via_api`, `preview_video_url`), a superset of the five members
  the spec named, so that the backoffice combobox reuses it unchanged.
- **A5** (`avatar-templates`, "Existing hr_avatar template stays manageable while unavailable"):
  duplication is superadmin-only in the existing code (`AvatarTemplateDuplicateController`), so the
  scenario's duplicate step is performed by a superadmin.
- **A6** (`hr-avatar-integration`, "Default path invariance", OpenAPI bullet; `avatar-templates`,
  provider requirement): the organization template store body's `config` changes from required to
  `required_unless:provider,hr_avatar`. It is the **only** non-additive OpenAPI change of this change
  (`config` leaves the store body's `required` list). Runtime for `heygen` and `tavus` is unchanged
  (same 422 key, status and message text), proved by the existing template suites run unedited.
- **A7** (`interview-frontend`, flag requirement and scenario "Only the literal true enables it"):
  the flag is evaluated on the runtime value after Nuxt's `destr` coercion, which is case-insensitive
  for `true`, so env `true`, `TRUE` and `True` enable it; `1`, `yes`, empty and unset do not. The
  scenario previously listed env `TRUE` as off, which `destr` makes impossible.

The interview-session bullet "`hr_avatar` MUST NOT be accepted by the validation of
`provider_override`" is **N/A**, recorded here rather than amended: no such validation exists to
extend (D-SELECT). The read-side guarantee (a stored `hr_avatar` override is ignored) is implemented
and tested.

## Validation corrections (2026-10-19 corrective re-run)

A fresh-context validation found no runtime change on the default path and 17 defects or gaps. Each
was adopted:

| # | Finding | Where it landed |
|---|---|---|
| 1 | Malformed `hr_avatar_config_id` and config errors raised as two 422s (`AvatarTemplateController.php:228`, `:233`) | D-TEMPLATES "One 422"; Testing (templates); task 5.3a |
| 2 | SDK state `ended` was ignored | D-ADAPTER step 3, D-COMPLETE latch table; tasks 11.1, 12.1, 12.2 |
| 3 | `config` conditionally required was undeclared in OpenAPI | A6; D-TEMPLATES; D-SCRAMBLE; tasks 5.3, 5.6, 5.7 |
| 4 | `provider_override` has no FormRequest validation | D-SELECT (N/A note); Spec amendments; task 3.2 keeps the "ignored" test |
| 5 | Secret key scopes and the 403 mapping undocumented | D-ISSUE; D-EXPORT; D-PROXY; Rollout step 2; tasks 2.2, 7.1, 8.2, 14.4 |
| 6 | Export did not report `sync_status`; `pending` configs fail at start | D-EXPORT; D-ISSUE; Rollout step 5; tasks 4.3, 8.2, 8.3 |
| 7 | Connect-time HR-Avatar refusals happen after `/start` | D-ADAPTER step 4; Rollout step 6; tasks 11.1, 13.1a |
| 8 | `forwardTranscript: false` lifecycle guarantee not cited | D-ADAPTER step 2 (reconciliation item 39); resolved item 5 |
| 9 | Proxy filtered client-side over capped pages | D-PROXY (`external_ref` query filter, reconciliation item 38); tasks 7.1, 7.3 |
| 10 | Backoffice widened `ProviderName` | D-BO-TYPES; File Changes (backoffice); tasks 9.3, 9.4, 9.6a, 9.7 |
| 11 | Missing `projects.avatarProvider.hr_avatar` for `ProjectTable.vue:65` | File Changes (backoffice i18n); tasks 9.2, 9.6 |
| 12 | Env `TRUE` does enable the flag (`destr`) | A7; D-FACTORY; Rollout step 4; task 13.1 |
| 13 | api available + frontend flag off burns conversations | D-FACTORY "Both switches"; Rollout step 4; task 14.4 |
| 14 | Scramble diff misses `PlatformAvatarTemplateResource`; `cacheKey()` bypassed | D-SCRAMBLE; D-EXPOSE; D-PROXY; tasks 5.7, 6.2, 6.6, 7.1, 7.3 |
| 15 | D-SELECT audit mislabelled :801 and missed :593, :700 | D-SELECT audit table; task 3.1 |
| 16 | `AVATAR_SETTLE_MS` source | D-ADAPTER (import from `tavus.ts:71`, not moved); task 11.2 |
| 17 | Catalog row deferred to W1; no frontend e2e | D-SDK (row in F1); Testing (E2E frontend); tasks 10.8a, 13.3a, 14.1 |

## Open Questions

- [ ] HR-Avatar config key parity (S5): does HR-Avatar keep BEAI's config keys verbatim for
  `tavus`/`heygen` (its design says "keys, types and limits kept") and model external voices only as
  `voice {engine, voice_id}`? Verify against the implemented field specs before any non-local
  `--apply`. A mismatch fails safely (`provider_rejected`, no write).
- [ ] Real composed prompt size against the 32000-character limit: measure
  `max(system_prompt_chars)` on a representative local dataset during A1. If it exceeds the limit,
  every `hr_avatar` start fails as ClientError (500, participant unchanged), and that is a product
  decision (no truncation).
- [ ] SDK version string and `bun.lock` integrity behaviour for `file:` tarballs: confirmed only once
  S8 produces a packable SDK. The frontend slices are blocked on S8.
- [ ] (Non-blocking, inherited) GDPR sign-off naming HR-Avatar's transcript store before the flag is
  enabled outside local.
- [ ] (Non-blocking) The HR-Avatar SDK's relative order of `state ended` and the `ended` event is not
  specified; D-COMPLETE is correct for either order (deferred `stopped`), and task 12.1 pins both
  orders. Re-check against the implemented SDK when F2b runs.
- [ ] (Non-blocking) The exact `HrAvatarError` codes the SDK surfaces for connect-time refusals
  (`provider_concurrency_limited`, `provider_credential_missing`, `provider_error`) are taken from the
  validation finding; the adapter maps every non-origin code to `sdk_error`, so a renamed code changes
  nothing at runtime, only the test fixture names.
