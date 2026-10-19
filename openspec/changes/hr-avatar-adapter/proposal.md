# Proposal: HR-Avatar adapter (BEAI side, additive and opt-in)

> Change `hr-avatar-adapter` — slice S9 of the HR-Avatar extraction. Binding inputs:
> `docs/extraction/DESIGN.md` D7, D8, D9 (owner-approved 2026-10-19), `docs/extraction/FINDINGS.md`,
> and the HR-Avatar contract in `hr-avatar/openspec/changes/hr-avatar-engine/`
> (`reconciliation.md` wins over its specs and design where they differ).

## Intent

The avatar engine is being extracted into HR-Avatar, a standalone service with its own key space
and a browser SDK (`@hr-avatar/sdk`). BEAI must be able to run an interview through HR-Avatar
**without** the cutover: a deliberate, opt-in third path next to Tavus and HeyGen. That proves the
extraction end to end while the trade-fair demo keeps running on the current integrated code.

Why now: the extraction gives no value until a real consumer uses it. BEAI is that consumer.
Success means an operator can point a template at an HR-Avatar config and a candidate completes an
interview through it. In every environment where HR-Avatar is not configured, BEAI behaves
exactly as it does today.

## Scope

### In Scope
- **api: provider.** `HrAvatarProvider implements ProviderSessionService` (provider name
  `hr_avatar`):
  - `issue()` maps `QuestionContext` plus the composed system prompt and opening text to
    HR-Avatar `POST /v1/conversations`, using `system_prompt`, `opening_text`, `language` (project
    language, `^[a-z]{2}$`), `max_duration_seconds` (template ceiling, 30..3600), `external_ref`
    (an opaque BEAI session reference) and `metadata` `{}`.
  - It returns a `ProviderToken` carrying the per-conversation `client_secret` (as `token`) and
    the `conv_…` id (as `provider_session_ref`).
  - `teardown()` calls `POST /v1/conversations/{id}/end` (idempotent 200, never throws).
  - `reconcileTranscript()` returns `[]`. BEAI keeps its own live utterance rows, as with Tavus.
- **api: configuration.** `HR_AVATAR_BASE_URL`, `HR_AVATAR_SECRET_KEY`, `HR_AVATAR_PUBLISHABLE_KEY`
  in a single config file. The provider is *available* only when all three are set. The secret key
  is used only server to server and is never serialized, logged or returned.
- **api: selection.** An explicit `hr_avatar` arm in `InterviewController::providerNameFor` and
  `resolveProvider`. A session is routed to `hr_avatar` **only** when the pinned template's
  provider is `hr_avatar` and the provider is available.
  - Test-mode participants still always run `mock` (T-TEST-006).
  - `projects.provider_override` and `config('interview.provider')` do not accept `hr_avatar`.
  - The `default => HeygenProvider` arm stays as it is.
- **api: start response.** For `hr_avatar` sessions only, the `POST /candidate/interview/start`
  response (`BuildInterviewSessionResponse`) carries the join inputs the SDK needs: the
  `client_secret` in the existing `provider_token`, plus the HR-Avatar base URL and publishable key.
  Each new field gets its own `T-EXPOSE-001` entry. Tavus and HeyGen responses are byte-identical.
- **api: templates.**
  - Migration adding nullable `avatar_templates.hr_avatar_config_id` (an opaque `avc_…` string; no
    foreign key, because it points into another service).
  - `hr_avatar` accepted as a template provider only when available. The config id is required for
    `hr_avatar` templates.
  - No Tavus PAL sync, HeyGen voice or LLM registration, or provider catalogue call for `hr_avatar`
    templates (HR-Avatar owns that).
  - Field visible on `AvatarTemplateResource` and in the export/import portability JSON, with
    `T-EXPOSE-001` entries.
- **api: backoffice proxy and capability.**
  - The HR-Avatar avatar-config list (`GET /v1/avatar-configs`, secret key, scope
    `avatar_configs:read`) is proxied through the existing admin-only
    `GET /api/avatar-templates/catalogue` as a new `hr_avatar` provider/resource arm. It reuses the
    existing `{status, items}` shape, so a failure degrades to `unavailable`.
  - The `hr_avatar` key appears in `GET /api/avatar-templates/field-specs` only when the provider is
    available. That key is the backoffice capability signal.
- **api: migration command (D9).** `php artisan hr-avatar:export-templates`, a dry run by default.
  It reads `avatar_templates`, creates matching HR-Avatar avatar configs, and writes back
  `hr_avatar_config_id` only with `--apply`. It never deletes or changes any other BEAI column or
  row, and transfers no provider or LLM credentials.
- **api: OpenAPI.** Scramble re-export of `openapi.json` (against Postgres). The diff is limited to
  the touched endpoints: start, templates, field specs and catalogue.
- **frontend: adapter.**
  - `HrAvatarProvider implements InterviewProvider`, wrapping `@hr-avatar/sdk` through a dynamic
    `import()` inside `start()`, so nothing new is loaded on the default path.
  - New `hr_avatar` arm in `createProvider`, gated by the runtime flag
    `NUXT_PUBLIC_HR_AVATAR_ENABLED` (default `false`). With the flag off, the factory never
    constructs the adapter and an `hr_avatar` answer fails closed with the existing
    unknown-provider error.
  - It maps SDK states, transcripts, `whenAvatarSilent`, `setMicMuted`, `toggleMic` and
    end-phrase/final-phrase completion (through `completionPhrases`).
  - SDK errors are mapped to provider-independent codes. No raw SDK text is passed on, as the
    provider-opacity requirement demands.
- **backoffice: template form.**
  - Adds the `hr_avatar` provider option in `AvatarTemplateForm.vue`. The provider list is derived
    from the field-spec keys instead of the hardcoded `['heygen','tavus']`, so the option is hidden
    unless the api reports HR-Avatar available.
  - Adds an HR-Avatar config picker fed by the catalogue proxy. Only the association is stored.
- **Tests:**
  - New Pest tests for the provider (`Http::fake` + `Http::preventStrayRequests()` against the
    HR-Avatar contract), selection, availability gating, the proxy, template validation, the export
    command and cross-tenant isolation of the new template field and proxy.
  - New Vitest specs for the adapter and factory gating, and for the backoffice option and picker
    visibility.

### Out of Scope
- Cutover: making `hr_avatar` the default, migrating projects, removing or changing Tavus/HeyGen
  code. A future cutover also has to deal with provider immutability: you cannot convert an
  existing template, you create a new `hr_avatar` template.
- Any change to `@beai/embed` (D7: unchanged, zero-dep, ≤12 KB).
- Tavus-style competency-boundary steering and conversation continuation or handover on
  `hr_avatar`. Each BEAI session issues one HR-Avatar conversation. `sendContext` mapping is deferred.
- Platform (superadmin) templates in `PlatformAvatarTemplateController`, `ProviderSmokeCheck`, and
  `provider_override` support for `hr_avatar`.
- HR-Avatar outbound webhooks consumed by BEAI. BEAI drives the lifecycle synchronously, as it does
  today.
- Publishing `@hr-avatar/sdk` to any registry, any push, any deploy, and any Railway change.
- Fixing the frontend/backoffice CI `--coverage.thresholds.lines=85` override (FINDINGS F8: report
  only).

## Capabilities

### New Capabilities
- `hr-avatar-integration`: covers:
  - BEAI's server-side client of HR-Avatar: availability gating on the three env values,
    secret-key confinement, and the `QuestionContext` → `POST /v1/conversations` mapping.
  - Teardown and error mapping to BEAI's existing `ProviderException` classes (4xx client
    contract vs 5xx/429 upstream).
  - The avatar-config list proxy.
  - The `hr-avatar:export-templates` dry-run/apply command.

### Modified Capabilities
- `interview-session`:
  - Provider selection gains a template-only `hr_avatar` arm (test mode still forces `mock`;
    override/env never select it).
  - The `POST /start` response carries the HR-Avatar join inputs for `hr_avatar` sessions only.
  - "Provider API secrets never exposed to the client" is extended to the HR-Avatar secret key.
- `avatar-templates`:
  - `hr_avatar` provider value and nullable `hr_avatar_config_id`.
  - The provider is offered only when HR-Avatar is available (field-spec key).
  - Catalogue proxy arm, no provider-side sync for `hr_avatar`, and the new field in export/import.
- `interview-frontend`: the provider abstraction gains a flag-gated `hr_avatar` adapter. The
  default factory behaviour is unchanged with the flag off. Provider opacity applies to the adapter
  and its error codes.

## Approach

Strictly additive, behind two independent off-by-default switches:
- **Server side.** The provider is available only when the three `HR_AVATAR_*` values are set. When
  it is unavailable, the `hr_avatar` provider value cannot be written and is never selected.
- **Client side.** `NUXT_PUBLIC_HR_AVATAR_ENABLED=false` means the factory never constructs the
  adapter.

Every existing branch keyed on `'tavus'` or `'heygen'` stays untouched. `hr_avatar` reaches the
interview flow only through new explicit arms. The design phase audits every `provider === …`
branch in `InterviewController` (continuation, release, concurrency guard) and confirms that
`hr_avatar` behaves as "neither". The existing suites passing **with no edits** is the proof that
the demo path is unchanged.

The api speaks to HR-Avatar with plain Laravel `Http`, like `TavusProvider` and `HeygenProvider`.
No SDK is involved on the server. The browser receives only the publishable key, the base URL and
the per-conversation `client_secret`. The SDK then connects and drives the transport itself. BEAI's
own utterance outbox stays the transcript of record, so scoring is untouched.

### SDK consumption before publication (design dependency)

No registry publish is allowed. The candidate options:

| Option | CI safety | Verdict |
|---|---|---|
| `file:../hr-avatar/sdk` link | Breaks: CI clones `frontend` alone, and `hr-avatar` has no remote and is not a submodule yet | Rejected |
| git dependency | Impossible: no remote exists | Rejected |
| Bun workspace | Not applicable across separate repos | Rejected |
| **Vendored tarball** `frontend/vendor/hr-avatar-sdk-<version>.tgz` (`bun pm pack` output from `hr-avatar/sdk`) referenced as `"@hr-avatar/sdk": "file:./vendor/hr-avatar-sdk-<version>.tgz"` | Self-contained, deterministic, integrity recorded in `bun.lock`, works on a bare `frontend` clone | **Recommended** |

The new dependency and its peer dependencies (`@daily-co/daily-js` and
`@heygen/liveavatar-web-sdk`, already pinned in `frontend`) must be recorded in
`docs/version-catalog.md` (D25). If the tarball cannot be resolved, the Dependency Resolution
Policy applies: stop and report. Replacing the tarball with the published package is a later,
one-line change.

### Delivery

auto-chain, local commits on `feature/extract-avatar-service` in `api`, `frontend` and
`backoffice`, branched from `develop`, no push. The expected order:
1. api provider, configuration and selection.
2. api templates, proxy, capability, `T-EXPOSE-001` and Scramble.
3. api export command.
4. frontend adapter and vendored SDK.
5. backoffice option and picker.

The total is expected to exceed the 400-line budget. `sdd-tasks` must slice it.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `api/app/Services/Provider/HrAvatarProvider.php` | New | `ProviderSessionService` implementation over HR-Avatar `/v1` |
| `api/config/` (new HR-Avatar config file), `api/.env.example` | New/Modified | `HR_AVATAR_BASE_URL`, `HR_AVATAR_SECRET_KEY`, `HR_AVATAR_PUBLISHABLE_KEY` |
| `api/app/Http/Controllers/Candidate/InterviewController.php` (`providerNameFor` :1703, `resolveProvider` :1931) | Modified | Explicit `hr_avatar` arms; existing arms unchanged |
| `api/app/Actions/Interview/BuildInterviewSessionResponse.php` | Modified | HR-Avatar join inputs, only for `hr_avatar` |
| `api/app/Providers/InterviewServiceProvider.php` | Modified | Bind the provider |
| `api/database/migrations/*_add_hr_avatar_config_id_to_avatar_templates.php` | New | Nullable column |
| `api/app/Models/AvatarTemplate.php`, `app/Http/Resources/AvatarTemplateResource.php`, `app/Http/Controllers/Concerns/ValidatesAvatarTemplateWrites.php` (`in:heygen,tavus`), `app/Http/Controllers/AvatarTemplateController.php` (`PROVIDERS`, `fieldSpecs`, `catalogue`, activation sync) | Modified | `hr_avatar` provider gated on availability; config id; no provider sync |
| `api/app/Support/AvatarTemplates/*` (catalogue / field specs), `AvatarTemplatePortabilityController` | Modified | Catalogue arm, field spec, export/import of the new field |
| `api/app/Console/Commands/` (export command) | New | D9 dry-run/apply |
| `api/tests/Helpers/PublicApi/ExposureCatalogue.php` | Modified | `T-EXPOSE-001` entries for every new field |
| `api/openapi.json` | Modified | Scramble re-export |
| `frontend/app/providers/hr-avatar.ts`, `frontend/app/providers/factory.ts`, `frontend/app/types/interview-provider.ts` (`ProviderName`, `StartConfig`), `useInterviewSession` start mapping | New/Modified | Adapter, gated factory arm, start config fields |
| `frontend/nuxt.config.ts`, `frontend/package.json`, `frontend/vendor/`, `bun.lock` | Modified/New | Runtime flag (default false); vendored SDK tarball |
| `backoffice/app/components/organisms/AvatarTemplateForm.vue` (`providers` :551) and its catalogue picker composable | Modified | Provider list from field-spec keys; HR-Avatar config picker |
| `docs/version-catalog.md` | Modified | `@hr-avatar/sdk` entry |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| HR-Avatar service and SDK are not implemented yet: `hr-avatar/` holds only `openspec/` (S2–S8 pending) | High | The api slices build against the spec contract with `Http::fake`. The frontend slice is sequenced after S8 produces a packable SDK. `tasks` must encode this ordering |
| A shared branch silently routes `hr_avatar` to HeyGen (`resolveProvider` `default` arm) or into Tavus continuation logic | Med | Explicit arms plus an audit of every provider branch in design. A Pest test asserts `hr_avatar` never constructs `HeygenProvider` or `TavusProvider` |
| The demo path changes by accident (start response, field specs, bundle) | Low | New fields only for `hr_avatar`. The field-spec key appears only when available. The SDK is dynamically imported. The existing suites pass unedited, and the OpenAPI diff is reviewed |
| The secret key leaks to a browser | Low | Used only in the server client. Tests assert it never appears in any response, log or resource, and the proxy returns only normalized items |
| The composed system prompt exceeds HR-Avatar's 32,000-char limit, or carries candidate PII to a second store | Med | Design measures the real composed prompt size. `external_ref` is opaque and `metadata` is empty. PII question below |
| CORS: the publishable key's `allowed_origins` must list the BEAI frontend origin | Med | Documented local wiring step. Surfaced as a stable error code, not a silent failure |
| Vendored tarball drifts from the `hr-avatar` source | Low | The tarball name carries the version, and the version is recorded in D25 |

## Open product decisions (returned to the orchestrator; none blocks the api slices)

1. **Template pinned to `hr_avatar` while HR-Avatar is unconfigured** (env removed after the
   template was created). Options:
   - Recommended: fall through to `provider_override`, then the env default, as if no template
     were pinned ("never selected").
   - Fail closed with the existing provider error.

   This blocks only the selection spec scenario.
2. **GDPR (ruling 2 extension).** On `hr_avatar` interviews, the system prompt and the candidate
   utterances are also stored in HR-Avatar, which has **no purge** (hr-avatar conversations spec,
   retention open item). The retention sign-off must name that store before
   `NUXT_PUBLIC_HR_AVATAR_ENABLED` is ever turned on outside local. It also has to decide whether
   the SDK runs with `forwardTranscript: false`. This blocks enabling, not implementation.
3. **Does the composed system prompt carry the candidate's display name?** If it does, it becomes
   personal data sent to HR-Avatar, and decision 2 must cover it.

## Rollback Plan

Every piece is additive and switched off by default:
- **Operational rollback.** Unset `HR_AVATAR_*` (the provider becomes unavailable and is never
  selected) and leave `NUXT_PUBLIC_HR_AVATAR_ENABLED=false`. No deploy is involved.
- **Code rollback.** Revert the slice commits on `feature/extract-avatar-service` in each submodule.
  The migration is a single nullable column with a `down()` that drops it, and nothing else reads
  it.
- **Export command.** `hr-avatar:export-templates --apply` changes only `hr_avatar_config_id`.
  Undo it by setting the column back to `NULL`. Configs created in HR-Avatar are deleted there
  through its API.

## Dependencies

- HR-Avatar `hr-avatar-engine` implemented through S8: `/v1/conversations`, `/end`,
  `/v1/avatar-configs`, and the packable `@hr-avatar/sdk` with its `./mock` export. These are a
  hard prerequisite for the frontend slice and for the local wiring smoke.
- An HR-Avatar account plus secret and publishable keys (`hra:bootstrap-account`,
  `hra:issue-key`), with the publishable key's origin allowlist set to the BEAI frontend origin,
  for local verification.
- Design decision: SDK consumption by vendored tarball (recommended above).
- `docs/version-catalog.md` (D25) entry for the new dependency.

## Success Criteria

- [ ] With `HR_AVATAR_*` unset and the flag off, **all existing api, frontend and backoffice suites
  pass with zero edits to existing tests**.
- [ ] With HR-Avatar unset, the Scramble export has no diff for the start, template, field-spec and
  catalogue responses.
- [ ] Tavus and HeyGen sessions produce byte-identical `/start` responses and provider calls before
  and after the change.
- [ ] `@beai/embed` has no diff.
- [ ] `hr_avatar` is selected only when the pinned template's provider is `hr_avatar` and HR-Avatar
  is available. Test-mode participants still get `mock`. `provider_override` and the env default can
  never yield `hr_avatar`.
- [ ] The HR-Avatar secret key never appears in any HTTP response, resource, export or log.
  Asserted by tests.
- [ ] With `NUXT_PUBLIC_HR_AVATAR_ENABLED=false`, `createProvider('hr_avatar', false)` never
  constructs the adapter and never imports `@hr-avatar/sdk`. Asserted by a unit test.
- [ ] The backoffice hides the `hr_avatar` option and the picker unless field specs report
  `hr_avatar`, and shows both when they do.
- [ ] Every new public or export field has a `T-EXPOSE-001` entry.
- [ ] `openapi.json` is re-exported against Postgres and the CI drift gate is green.
- [ ] `hr-avatar:export-templates` performs no write without `--apply`. With `--apply` it changes
  only `hr_avatar_config_id`.
- [ ] New code coverage > 85%, and the api global gate stays at `--min=98`.
- [ ] Cross-tenant tests: template field and proxy results are org-scoped, and one tenant's
  `hr_avatar_config_id` is never readable by another.
- [ ] Local wiring smoke: HR-Avatar compose plus a mock-provider config, and a BEAI template set to
  `hr_avatar` with the flag on. A candidate interview completes. A Tavus/HeyGen template on the same
  stack behaves exactly as before.
