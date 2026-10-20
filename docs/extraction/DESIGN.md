# HR-Avatar extraction — Phase 1 design

> Status: approved by the owner on 2026-10-19. Inputs: [`FINDINGS.md`](FINDINGS.md) (Phase 0) and the ratified decisions recorded there.

### D1. Repository layout
New independent git repo **`hr-avatar/`** (added to the wrapper as a 5th submodule only after a
remote exists), containing:
- `service/` — Laravel 13 + PHP 8.5 + Postgres 17 + Redis 8, Pest, Scramble (versions per
  `docs/version-catalog.md`); own `docker-compose.yml` (NOT added to BEAI's compose, whose
  8-service count is CI-guarded).
- `sdk/` — `@hr-avatar/sdk`, TypeScript, Bun, tsup (ESM/CJS/IIFE), Vitest + Playwright.
- `openspec/` — HR-Avatar's own SDD store (it must be reusable without BEAI).
- The name lives only in `config/hr-avatar.php`, `package.json` name, key prefix constant,
  env prefix `HRA_` → rename = find-and-replace.

### D2. Service data model (account-scoped, no BEAI concepts)
- `accounts` (one per consuming product; BEAI = one account; BEAI keeps the org↔config mapping).
- `api_keys`: `type` secret|publishable, `mode` live|test, `key_prefix`, `key_hash` sha256,
  `scopes` jsonb, `allowed_origins` jsonb (publishable only), `expires_at`, `revoked_at`,
  `last_used_at`, `rotated_from_id`.
- `provider_credentials` (account, provider, encrypted key) with platform env fallback.
- `llm_models` (platform catalogue), `llm_credentials` (account, encrypted).
- `avatar_configs` — generic part of today's `avatar_templates`: provider, `config` jsonb,
  `persona` jsonb, llm binding, sync status columns, `external_ref`.
- `conversations`: account, avatar_config, provider, `provider_session_ref`,
  `provider_context_ref`, status (`created→connecting→live→ended|failed`), language,
  `max_duration_seconds`, `ended_reason`, timestamps, `external_ref`, `metadata` jsonb.
- `conversation_events` (utterances + lifecycle events, ordered, idempotency key).
- `provider_webhook_receipts` (dedupe), `webhook_endpoints` + `webhook_deliveries` (outbound).

### D3. Provider abstraction
Port `ProviderSessionService` with a BEAI-free input:
`ConversationSpec { systemPrompt, openingText, language, maxDurationSeconds, metadata }` →
`JoinMaterial { provider, transport: 'daily'|'liveavatar', conversationUrl?, sessionToken?, expiresAt }`.
Adapters: Tavus, HeyGen LiveAvatar, Mock (deterministic, for consumers' tests). Concurrency
guard, pal sync, registrars, catalogue and voice preview ported with their tests.

### D4. Auth scheme (independent key space)
- **Secret key** `hra_sk_{live|test}_<96 hex>`: server-to-server only; rejects requests carrying
  an `Origin` header in live mode (BEAI's rule); scopes per key; rotation endpoint with overlap window.
- **Publishable key** `hra_pk_{live|test}_<…>`: browser-safe, origin allowlist, cannot do
  anything alone — it only identifies the account for CORS/origin checks.
- **Client secret**: per-conversation short-lived single-use-to-connect JWT (pattern of
  `SessionTokenMinter`) minted by `POST /v1/conversations`, handed by the host back-end to its browser.
- Problem+JSON errors, request id, per-key rate limit — same middleware chain shape as BEAI `/api/v1`.

### D5. API surface (`/v1`, Scramble-documented)
- Secret key: `avatar-configs` CRUD + `catalogue` + `voice-preview`; `provider-credentials`,
  `llm-credentials`, `llm-models`; `POST /conversations` (→ id + client_secret),
  `GET /conversations/{id}`, `POST /conversations/{id}/end`, `GET /conversations/{id}/transcript`;
  `webhook-endpoints` CRUD; `api-keys` list/create/rotate/revoke.
- Client (publishable key + client_secret): `POST /client/conversations/{id}/connect`
  (→ JoinMaterial), `POST /client/conversations/{id}/events` (utterances, batched,
  idempotent), `POST /client/conversations/{id}/end`.
- Inbound: `POST /webhooks/providers/{provider}/{token}` — per-conversation unguessable token +
  provider signature where the provider offers one (Tavus `callback_url` / LiveAvatar webhook
  semantics to be verified against current provider docs during sdd-design; unverified today).
- Outbound to consumers: `conversation.live`, `conversation.ended`, `transcript.ready`,
  signed `X-HRA-Signature: v1=hmac_sha256("{ts}.{body}")`, retries/backoff (BEAI pattern).
- Teardown: explicit `/end`, provider webhook, max-duration sweeper job, delayed release job.

### D6. SDK `@hr-avatar/sdk`
```ts
const convo = await HrAvatar.connect({ baseUrl, publishableKey, clientSecret, mount: videoEl, audioDeviceId })
convo.on('state' | 'transcript' | 'error' | 'ended', fn)
convo.setMicMuted(b); convo.toggleMic(); convo.say(text); convo.interrupt()
convo.sendContext(payload)   // generic replacement of Tavus boundary steering
convo.whenAvatarSilent(ms); await convo.end()
```
- Harvested from `frontend/app/providers/{heygen,tavus,factory}.ts`, `types/interview-provider.ts`,
  `utils/utterance-outbox.ts` (auto-forwards transcript to `/client/.../events`, opt-out).
- BEAI semantics removed: `endPhrase/finalPhrase` → optional `completionPhrases`;
  `dbSessionId` → conversation id; `TavusBoundaryTicket` → `sendContext`.
- `daily-js` and `liveavatar-web-sdk` as optional peer deps, lazy-imported per provider.
- Mock provider exported for consumers' tests (mirrors `NUXT_PUBLIC_INTERVIEW_PROVIDER_MOCK`).

### D7. `embed/` split — module disposition
| Module | Disposition |
|---|---|
| `index.ts`, `embed.ts`, `protocol.ts`, `dom.ts`, `errors.ts` | Stay in `@beai/embed`, unchanged |
Composition happens where the avatar actually runs: the BEAI `frontend` (loaded inside the embed
iframe) consumes `@hr-avatar/sdk` through a new `HrAvatarProvider` adapter. `@beai/embed` gains
no dependency (it must stay zero-dep, ≤12 KB). Owner-ratified deviation from PROMPT.md (decision 4).

### D8. BEAI side (additive, opt-in, demo untouched)
- api: `HrAvatarProvider implements ProviderSessionService` (provider name `hr_avatar`),
  maps `QuestionContext` + composed prompt → `ConversationSpec`; config `HR_AVATAR_BASE_URL`,
  `HR_AVATAR_SECRET_KEY` (unset ⇒ provider unavailable, never selected); nullable
  `avatar_templates.hr_avatar_config_id`; `hr_avatar` arm in `providerNameFor`/`resolveProvider`.
  Only templates explicitly set to `hr_avatar` route there ⇒ Tavus/HeyGen paths byte-identical.
- frontend: `HrAvatarProvider implements InterviewProvider` wrapping the SDK; factory arm,
  gated by the runtime flag `NUXT_PUBLIC_HR_AVATAR_ENABLED` (default `false`). With the flag off
  the factory never constructs it, even if the api answers `provider: hr_avatar` (the session
  then fails closed with the existing unknown-provider error), so the default path is unchanged.
- backoffice: `hr_avatar` provider option + HR-Avatar config picker, listed through BEAI api
  (secret key never reaches a browser). BEAI stores only the association.
- Scramble: re-export `openapi.json` for touched endpoints; CI diff gates already exist.

### D9. Migration (non-destructive)
`php artisan hr-avatar:export-templates --dry-run` (default dry): reads `avatar_templates`,
creates matching `avatar_configs` in HR-Avatar, writes back `hr_avatar_config_id` only on
explicit `--apply`. No BEAI row deleted or altered otherwise; session history stays in BEAI.

### D10. Railway topology (config only, never applied)
`hr-avatar-api` (Dockerfile, preDeploy `migrate --force`), `hr-avatar-worker`
(`queue:work`), Postgres, Redis. Env: `APP_KEY`, `DB_URL`, `REDIS_URL`, `HRA_JWT_SECRET`,
`HRA_WEBHOOK_SIGNING_SECRET`, optional platform `TAVUS_API_KEY`/`HEYGEN_API_KEY`/
`CARTESIA_API_KEY`/`ELEVENLABS_API_KEY`. Files: `service/railway.json`, `docs/railway.md`.

### D11. Test strategy
- service: Pest, CI `--coverage --min=90`; auth/keys/signatures/conversation state machine ≥95%;
  Http::fake contract fixtures per provider (ported); arch tests banning BEAI namespaces.
- sdk: Vitest thresholds 90 (lines/branches/functions); Playwright smoke page on the mock
  provider (Chromium + WebKit); bundle-size check.
- BEAI: new Pest tests for `HrAvatarProvider` + selection; existing suites must stay green
  unchanged (proof the demo path is untouched); frontend adapter spec.

---

## Phase 2 — Execution slices (SDD per slice, strict TDD, gga before each commit)

Branches: `feature/extract-avatar-service` in every repo touched. Commits local; **no push
without your say-so**, no Railway calls, no `main`.

| # | Slice | Repo |
|---|---|---|
| S0 | Engram: save decisions 1–4; re-point wrapper branch to `develop`; commit `docs/extraction/FINDINGS.md` + `DESIGN.md` (this file's Phase 0/1) | wrapper |
| S1 | SDD proposal/spec/design/tasks for service + SDK; verify provider webhook docs | hr-avatar |
| S2 | Laravel scaffold, Pest, Scramble, health, CI workflow, own compose | hr-avatar |
| S3 | accounts + secret/publishable keys + middleware + rotation | hr-avatar |
| S4 | provider contract + Mock/Tavus/LiveAvatar adapters (ported tests first) | hr-avatar |
| S5 | avatar configs, LLM binding, voice registrars, catalogue, voice preview | hr-avatar |
| S6 | conversations lifecycle + client endpoints + client_secret + events | hr-avatar |
| S7 | provider webhook ingestion + outbound consumer webhooks | hr-avatar |
| S8 | `@hr-avatar/sdk` (providers harvested, mock, build, tests) | hr-avatar |
| S9 | BEAI adapters: api `HrAvatarProvider` + migration + Scramble; frontend adapter; backoffice option | api, frontend, backoffice |
| S10 | README, architecture, SDK usage, local wiring guide, Railway config, final summary | hr-avatar, wrapper |

## Verification
- hr-avatar: `php artisan test --coverage --min=90`; `php artisan scramble:export` +
  Spectral lint on the output; `bun run test:coverage`, `bunx playwright test`, `bun run size`.
- BEAI: full `task test:api`, `task test:frontend`, `task test:backoffice` green with no edits to
  existing tests; `scramble:export` diff limited to touched endpoints; `task stack:check`.
- Local wiring smoke: HR-Avatar compose up → create account/keys → BEAI `.env`
  `HR_AVATAR_*` → template set to `hr_avatar` with mock provider → candidate interview
  completes end-to-end; a Tavus/HeyGen template still behaves exactly as before.
