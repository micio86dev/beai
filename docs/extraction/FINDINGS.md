# HR-Avatar extraction — Phase 0 findings

> Status: Phase 0 complete (2026-10-19). Read-only analysis of `api/`, `frontend/`, `backoffice/`, `embed/`, dependency manifests and CI. Source mission: [`PROMPT.md`](PROMPT.md). Design: [`DESIGN.md`](DESIGN.md).

## Context

`docs/extraction/PROMPT.md` asks to extract everything that is purely "how an avatar
conversation runs" out of BEAI into a standalone, reusable service (**HR-Avatar**, placeholder
name) with its own HTTP API, its own key space, and its own client SDK, so that a second product
can use only the avatar piece. Hard constraints: never touch `main`, never deploy anything, the
trade-fair demo path stays untouched (strictly additive), SDD + strict TDD, Engram, gga before
every commit, English-only artifacts, OpenAPI via Scramble on both services.

Phase 0 was run read-only (3 exploration passes over `api/`, `frontend/`, `backoffice/`,
`embed/`, manifests, CI). Its first implementation step is committing these findings as
`docs/extraction/FINDINGS.md`.

### Decisions ratified by the owner (2026-10-19, end of Phase 0)
1. **Repo home:** new independent repo `hr-avatar/` initialized locally (`service/`, `sdk/`,
   `openspec/`); owner creates the GitHub remote later, then it becomes the 5th submodule.
2. **Base branch:** `develop` in every repo (Git Flow). The wrapper's existing
   `feature/extract-avatar-service` currently points at `main`'s tip with no own commits →
   re-point it to `develop` (`git switch -C feature/extract-avatar-service develop`) after
   verifying `git log develop..HEAD` is empty; untracked `docs/extraction/` is preserved.
3. **Provider keys:** per-account encrypted credentials in HR-Avatar, falling back to platform env keys.
4. **Embed:** `@beai/embed` unchanged; BEAI `frontend` composes `@hr-avatar/sdk`.
All four are saved to Engram as the first action of S0.

---

## Findings (verified from code)
### F1. `SDKS/embed` is `embed/` (4th submodule, `@beai/embed` 0.1.1) and contains NO avatar mechanics
- 5 modules, ~600 lines, zero runtime deps, ≤12 KB gz: `index.ts` (facade `BEAI.mount`),
  `embed.ts` (`BeaiEmbed`: mount/on/start/end/destroy, ready-queue, 15 s timeout, resize),
  `protocol.ts` (postMessage envelope `source:"beai-embed", version:1`), `dom.ts`
  (iframe `{origin}/embed/{token}`, `allow="camera; microphone; autoplay"`), `errors.ts`.
- It never calls an HTTP endpoint or a provider. It iframes BEAI's own `frontend`
  (`pages/embed/[token].vue` + `useEmbedBridge.ts`), and the frontend inside the iframe runs the avatar.
- Disposition consequence: **nothing in `embed/` moves**. The avatar code that must become the
  HR-Avatar SDK lives in `frontend/app/providers/*`, `frontend/app/types/interview-provider.ts`,
  `AvatarPlayer.client.vue`, `utils/utterance-outbox.ts`.
- Tests: Vitest+jsdom, 8 unit files, thresholds 85; last lcov ≈99% lines. No playwright config present.

### F2. Real-time transport (code + lockfiles)
| Provider | Browser library | Transport | Server side |
|---|---|---|---|
| Tavus | `@daily-co/daily-js@0.91.0` (`createCallObject`, no Daily UI) | Daily WebRTC room; app-messages for steering + `conversation.utterance` | `POST tavusapi.com/v2/conversations` → `conversation_url` |
| HeyGen LiveAvatar | `@heygen/liveavatar-web-sdk@0.0.18` | LiveKit WebRTC (`livekit-client 2.15.7`, transitive only) | `POST api.liveavatar.com/v1/contexts` + `/sessions/token` → `session_token` |
- api has no media/WebRTC/LiveKit/Daily packages; it only mints join material. No WebSocket,
  no raw `RTCPeerConnection`, no provider iframe. Both render into BEAI's own `<video>`.

### F3. api provider layer (`api/app/Services/Provider/`)
- Contract `ProviderSessionService { issue(InterviewSession, QuestionContext): ProviderToken;
  reconcileTranscript(InterviewSession): array; teardown(ProviderToken): bool }`;
  impls `TavusProvider`, `HeygenProvider`, `MockProvider`; plain `Http` clients, no SDKs.
- Selection: `InterviewController::providerNameFor` (:1703) → template `AvatarTemplate.provider`
  → `projects.provider_override` → `config('interview.provider')`; dispatch via
  `resolveProvider()` (:1931).
- Generic (movable): providers, `TavusConcurrencyGuard`, `TavusPalSync`, `AvatarProviderCatalogue`,
  `HeygenLlmRegistrar`, `HeygenVoiceRegistrar`, `ManagedLlmPayload`, `LlmBindingResolver`,
  `VoicePreviewService`, `CatalogueSampleService`, `ProviderFieldSpecs`, LLM usage estimators.
- BEAI-only (stays): `SystemPromptComposer`, `ComposeCompetencyPrompt`,
  `ComposeConversationPlan`, `OpeningTextComposer`, BARS loaders, competency handover,
  participant state machine, `InterviewController` (1,939 lines, the main entanglement).
- Seam: `QuestionContext` carries competency semantics; the engine needs only
  `{systemPrompt, openingText, language, limits}`.

### F4. LLM brain and voice
- No BEAI callback endpoint: providers run the LLM themselves. Binding per template
  (`llm_model_id`, `llm_credential_id`) → Gemini via OpenAI-compatible base URL.
  Tavus: written into the persona `layers.llm` (key stored provider-side). HeyGen: secret +
  `llm-configuration`, referenced by id in `/sessions/token`.
- Voice is template config (`ttsEngine` cartesia/elevenlabs/azure, `ttsExternalVoiceId`,
  `ttsModelName`); Tavus via persona PATCH, HeyGen via voice binding
  (`heygen_vendor_secrets`, `heygen_bound_voices`). Language comes from `project.language`.

### F5. Provider webhooks: **none exist**
- No inbound Tavus/HeyGen route. State is driven synchronously (`/start`, `/suspend`, `/end`)
  plus `ReleaseEndedProviderSessionJob`, `participant_left_timeout`, `AvatarSilenceDetector`.
- Outbound BEAI→caller webhooks exist (`DeliverWebhookJob`, `WebhookSigner`
  `v1=hmac_sha256("{ts}.{body}")`, 6 attempts) — a reusable pattern, not avatar code.
- HR-Avatar provider-webhook ingestion is therefore **new work**, not a port.

### F6. Credentials and keys
- Tavus/HeyGen/Cartesia/ElevenLabs keys are **platform-wide env vars**; the only per-org secret is the
  Gemini key (`llm_credentials`, encrypted cast, never returned).
- BEAI M2M keys (`api_clients`): `beai_{live|test}_` + 96 hex, sha256 hash, indexed
  `key_prefix`, `hash_equals`, jsonb abilities, revocation cache, no rotation endpoint.
  Browser leg = short-lived single-use JWT (`SessionTokenMinter`, 15 min). Solid pattern to reuse.
- There is no publishable/public key today: only secret keys + ephemeral browser tokens.

### F7. Org config / templates
- `GET /candidate/session` → branding `{logo_url, name, primary_color, background_color}`;
  applied as CSS custom properties (`useBrandTheme`, `useCandidateBranding`).
- The frontend has **no template renderer**; the only avatar-coupled presentation flag is
  `audio_only`. `InterviewSession.vue` (1,236 lines) composes avatar tile + proctoring + captions,
  but branding never reaches the avatar layer. **Verdict: not entangled, templates stay in BEAI.**

### F8. Tests and coverage
- api: Pest, CI `--coverage --min=98` (98.2% on 2026-10-13). Avatar-relevant: `tests/Unit/C7a/*`,
  `tests/Feature/C7a/*`, `tests/Feature/C14/*`, `ConversationLlm/*`, `Support/AvatarTemplates/*`.
- frontend: provider specs (`heygen-provider`, `tavus-provider*`, `provider-factory`,
  `provider-anonymity`, `utterance-outbox`, `avatar-player*`), Playwright with a mock provider.
- backoffice: `avatar-template-form*`, combobox, LLM panels, e2e template specs.
- Re-home (port nearly verbatim): provider unit/contract tests, registrar/pal-sync/catalogue tests,
  frontend provider + outbox specs. Rewrite: anything built on `InterviewSession`/`QuestionContext`.
- CI note: frontend/backoffice CI passes `--coverage.thresholds.lines=85` on the CLI, overriding
  the 98/99 in `vitest.config.ts` (likely unintended — report, do not fix in this task).
