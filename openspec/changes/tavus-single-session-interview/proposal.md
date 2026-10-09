# Proposal: One Tavus Conversation Across Many Competencies

> **STATUS: Rescoped 2026-10-08, amended 2026-10-09.** This is a living change, rewritten in place. The
> original proposal (2026-08-21) was re-validated against `develop` on 2026-10-08 (api `e215c43`, frontend
> `99523a3`) and again on 2026-10-09 (api `cf1d82a`, frontend `cc26363`, wrapper `fc451c5`) after an
> owner-authorized **live spike** (design Appendix A) and after `heygen-context-cleanup` and
> `db-driven-conversation-prompts` merged. Thirteen corrections (A1-A13) are recorded in `design.md` under
> "Amendments 2026-10-08"; what the spike and the merges changed (S1-S6, C1-C5, N12-N17) is under "Amendments
> 2026-10-09". Nothing is implemented yet: this change is docs-only until the first task slice lands.
> What changed in one line since 2026-10-08: steering is `append_llm_context` **plus a mandatory `respond`**;
> the `respond` is echoed back as candidate speech and must be dropped; a browser leave does NOT end a Tavus
> conversation, so release is explicit; and `/end` itself now releases the conversation on `develop`, which would
> kill a shared one unless guarded.

> **The constraint that shapes everything below.** Tavus interactions travel **only over the
> Daily data channel**. There is no server-side REST endpoint for them: the Tavus server
> module creates a conversation and ends it, nothing more. So whoever sends a context interaction
> **must be a participant in the room**, which today means the candidate's browser. And the **BARS
> anchors must never reach that browser**: they are the instrument the candidate is scored against.
> Any design that ships the composed per-competency prompt to the client to be relayed is an
> assessment-integrity failure, not a tradeoff. The whole approach is built around that single fact.

## Intent

Today one competency = one provider session. `InterviewController::start()` calls
`provider->issue()` and creates a fresh `interview_sessions` row on **every** `/start`. For Tavus that
means a new Daily conversation, a new room and a new avatar connect per competency.

Tavus can do better, for three independently verified reasons:

| # | Fact | Evidence |
|---|---|---|
| 1 | Tavus accepts context interactions on a **live** conversation over the Daily data channel: `conversation.append_llm_context {context}` **appends** to the LLM context, `conversation.overwrite_llm_context {context}` **replaces** it, `conversation.respond {text}` is "a user typed a message and the PAL should respond as if the user had spoken that text". | `llms-full.txt` lines 15583-15586 (interaction table) and 6384-6400 (`respond` envelope). Envelope for all of them: `{message_type:'conversation', event_type, conversation_id, properties:{...}}` sent with `call.sendAppMessage(payload,'*')`. **Verified live 2026-10-09** (design Appendix A, L1): all three interactions are accepted from a browser Daily participant. `@daily-co/daily-js ^0.91.0` is installed; BEAI only *receives* app-messages today (`frontend/app/providers/tavus.ts:146`). |
| 2 | Tavus has **no server transcript**: utterances arrive live, per utterance, already attributed. HeyGen's one-blob-per-session-ref problem does not exist here. | `TavusProvider::reconcileTranscript()` returns `[]`. |
| 3 | The ceiling is configurable per avatar template and capped by the plan: `max_call_duration` is "automatically capped to your plan's maximum". `TAVUS_MAX_SECONDS = 3600` is BEAI's platform bound; a template can set a lower `maxCallDurationSec` (the demo template uses 900). At a 300 s question limit a short project fits in one conversation; a 14-18 competency role does not and needs the ceiling handover. | `ProviderFieldSpecs.php:60,256`; `SessionLiveClock::resolveMaxSeconds` (`:135-156`); `llms-full.txt` line 4627. |

**What the original proposal got wrong, now corrected.** It named `overwrite_llm_context` as the steering
interaction and recorded a smoke result for it. Overwriting with a pointer would delete the multi-topic anchors the
design relies on (confirmed live: an overwrite really discards creation-time context, an append keeps it), so the
steering uses **context-append followed by a mandatory fixed `respond`**: the live spike showed that an append
alone leaves the avatar silent. The 2026-10-08 rescope called the `respond` "if the spike shows it is needed";
that is now a verified requirement. The 2026-08-21 overwrite smoke result is kept as history only.

**HeyGen cannot do any of this.** It sends the prompt once at `POST /v1/contexts` with no update method.
HeyGen keeps the crossfade handover and is **out of scope**.

**The server side is already decoupled.** Proctoring, snapshots, scoring and webhooks key on
`interview_sessions.id`, never on `provider_session_ref`. Only two places hardwire the 1:1 assumption:
`/start` always issuing, and the frontend closing over one session id.

## Scope

### In Scope

| # | Deliverable |
|---|---|
| 1 | **A multi-competency conversation plan composed server-side and sent at conversation creation** (`App\Actions\Interview\ComposeConversationPlan`), frozen on the creating row in a nullable JSON column `interview_sessions.conversation_plan` (`[{code, primary_questions, follow_up_budget}]` plus `chars`, no anchors). |
| 2 | **A non-sensitive steering at each boundary**: `conversation.append_llm_context` carrying a fixed template plus the server-issued competency code, **followed by a mandatory fixed `conversation.respond` trigger** (live-verified). No anchors, no indicator text, no prompt. The wording of both constants is provisional until the live steering gate. |
| 3 | **A server grant path** (`App\Actions\Interview\AdvanceOnLiveConversation`) that creates the next `interview_sessions` row on the same live ref instead of calling `issue()`, only when the browser asserts `live_conversation_id` and every grant rule holds. |
| 4 | **An attribution cursor** in the frontend that retargets utterance attribution, `/end`, `/suspend`, snapshots, integrity flushes, the question timer and the proctor overlay to the current competency, always *before* the steering message is sent. |
| 5 | **A mechanical boundary signal** (`boundary_due` on the `/utterance` 202) and an **explicit steering acknowledgement rule** (first replica utterance, or `steering_failed`). |
| 6 | **Echo suppression**: Tavus echoes every `respond` back as a user-role utterance (live-verified); the client holds and drops it by correlation (armed one-shot window plus the avatar reply's `inference_id`), with the microphone muted until the steering is acknowledged so no genuine speech can be in flight. |
| 7 | **Ceiling handling**: `ProviderRefLifetime` derives the ref age and the ceiling from the template, the server refuses a continuation near it and returns `conversation_ttl_seconds` on a fresh plan, the client crossfades to a fresh conversation, a client age timer covers mid-competency expiry. |
| 8 | **A shared-ref release guard** (no new job): `/end` no longer releases a shared conversation that a planned competency will use (it defers through the existing `ReleaseEndedProviderSessionJob`), and that job, the reaper and the resume teardown skip a ref a live sibling row still uses. The ceiling resume releases through the same deferred job. |
| 9 | **Resume teardown that knows about siblings**: skip teardown only when a live sibling row shares the ref. |
| 10 | **Schema**: nullable `conversation_plan` plus one partial unique index (one open live period per `provider_session_ref`). Both additive, both dropped by `down()`. |
| 11 | **A feature flag** `INTERVIEW_TAVUS_SINGLE_SESSION` (default **false**) and an optional project-id canary list. Everything ships dark. |
| 12 | Tests in all three tiers (Pest, Vitest, Playwright), strict TDD, plus the offline-versus-live split in `tasks.md`. |
| 13 | **An explicit `participant_left_timeout`** (config, default 60 s) on conversations created while the gate applies, because the unset default was observed not to end a conversation after the browser left. The flag-off create body is untouched. |
| 14 | **Composition through the stored prompt set**: `ComposeConversationPlan` resolves each covered competency through `PromptSetResolver` exactly as the single path does, from ONE set, and the creating row's `conversation_prompt_version` is copied to every continuation row. |

### Out of Scope

- **HeyGen.** Nothing in this change touches the HeyGen path except to stop its crossfade gate being
  provider-named.
- **A server-side Daily participant.** Recorded as the rejected alternative (design D2).
- **Removing the per-competency `interview_sessions` row.** The unique `(participant_id, competency_code)` and
  every downstream consumer stay as they are.
- **Scoring, webhooks, completion gate.** They key on `interview_sessions.id` and are untouched by
  construction. A Pest test asserts the scoring input for a shared-ref interview equals N separate-ref
  interviews.
- **`backoffice`** feature work. It only receives the generated OpenAPI snapshot and typed client.
- **Further live runs.** The first spike ran on 2026-10-09 with explicit owner authorization (design Appendix A).
  Any further live run (the realistic multi-topic A/B for Q1, the end-to-end steering sequence, the plan-level
  ceiling, an explicit `participant_left_timeout`; gates G-A to G-D in `tasks.md`) spends Tavus credits and needs
  its own explicit authorization. None is a prerequisite for merging a dark slice.
- **The per-question 300 s timer as the boundary answer.** It stays the floor (design D5).
- **Flipping the flag.** Enabling it for a canary project is an owner decision after the spike.

## Rescope: what changed and where it is recorded

| Ref | Original claim | Verified reality | Recorded in |
|---|---|---|---|
| A1 | D4a drain is to be built | Already shipped (`useInterviewSession.ts:632-657`, awaited in `callEnd` and `callSuspend`); only the uplink mute remains | design A1 |
| A2 | Handle keeps `dbSessionId` for `/end` | That would POST `/end` for row N again (409). A cursor must feed `/end`, `/suspend`, `sessionId`, snapshot, integrity | design A2 |
| A3 | `overwrite_llm_context` | Tavus documents `append_llm_context` ("Appends") and `overwrite_llm_context` ("Replaces"); live: append keeps creation-time context, overwrite drops it, and a `respond` is mandatory | design A3, S1, S5 |
| A4 | Steering has an observable result | No interaction acknowledgement exists; the only signals are the next replica utterance and Daily `left-meeting`/`error` | design A4 |
| A5 | `/end` leaks a live conversation | **2026-10-08 said "overstated"; superseded.** A browser leave left the conversation `active` for 86+ s and only an explicit `/end` ended it; and `develop` now releases on `/end`, which would kill a shared conversation | design A5 (superseded), S3, C1, N12, N16 |
| A6 | Conversation id handed over on continuation only | A fresh multi-plan `/start` must return `conversation_id` too | design A6 |
| A7 | Frozen 20-code set | Codes are operator-authored `^[A-Z0-9_]+$`, max 16 | design A7 |
| A8 | `composeMany` maps `compose()` | Per-competency resolution is not a map; it lives in a new action | design A8 |
| A9 | Snapshots per row are free | Each row snapshots `primary_questions` and `follow_up_budget`; needs a freeze and an LLM snapshot copy | design A9 |
| A10 | Ceiling is the constant 3600 | It comes from the template; headroom 480 s | design A10 |
| A11 | Resume reuses the live ref | Resume issues first, tears down second; the browser has left the room | design A11 |
| A12 | Two code paths | Eight paths must go through plan/continuation logic | design A12 |
| A13 | Response schema | Hand-written `@scramble-return` (now at `InterviewController.php:148`) must grow `conversation_id`, `conversation_ttl_seconds`, `continuation`; `/utterance` gains a 202 body | design A13, N11 |
| S1-S6 | Live spike 2026-10-09 | Respond mandatory; echo shape; A5 disproved; unannounced ceiling; append vs overwrite; what stayed untested | design S1-S6, Appendix A |
| C1-C5 | `develop` moved | `/end` releases (hazard for a shared ref); release plumbing exists; composition via the stored set; snapshot gained a column; locators moved | design C1-C5 |

## Capabilities

### New Capabilities

None. The data-channel interaction belongs in the spec that already owns the **Tavus Conversation Wire
Contract**. A separate document would let the same provider's two transports drift apart.

### Modified Capabilities

- **`interview-session`**: `POST /start` (grant rules, `conversation_id`, `continuation`),
  `POST /utterance` (`boundary_due`), Tavus Conversation Wire Contract (multi-context create, context-append
  interaction), plus new requirements for the conversation plan, the grant rules, the ref lifetime, the release
  job, the open-period invariant and the feature gate.
- **`interview-conversation`**: `System-Prompt Composition - Pure Function` and `QuestionContext Carries Composed
  Prompt` gain the multi-competency mode and the plan freeze; anchors stay server-side.
- **`interview-frontend`**: `Interview session loop - endpoint call order`, `Provider abstraction -
  provider-neutral behavior` and the HeyGen-only presentation requirement are modified; new requirements cover
  attribution, the acknowledgement rule, echo suppression, the boundary signal and the Tavus ceiling handover.

## Approach

The decisions D1-D10 of the original design are kept where the amendments say RETAINED, and amended or
superseded elsewhere; `design.md` carries a status tag on every one. In short:

1. **Compose once, server-side, for the competencies that remain** (D1 amended by A8, A9): a plan action
   returns the combined context plus the per-competency snapshot, bounded by `max_context_chars`; a longer
   remainder yields a prefix, which is the same fresh-conversation path as the time ceiling.
2. **The client asserts, the server verifies** (D2 amended by A6): `live_conversation_id` in, `continuation`
   out, and only when every grant rule holds. Absent or refused means today's behaviour.
3. **Attribution is retargeted before its own cause** (D3 amended by A2): a cursor whose only mutator mints the
   branded ticket `sendBoundary` requires.
4. **Steer by appending then responding, acknowledge by the next avatar utterance** (A3, A4, S1, N5): the
   microphone stays muted until the acknowledgement, the `respond` echo is held and dropped (N15), a bounded wait,
   one retry if still joined, otherwise the competency ends as `timeout` and the next `/start` issues fresh.
5. **Boundary has three inputs, one mechanical** (D5): end phrase, server-asserted `boundary_due`, 300 s timer.
6. **Anti-leak is a type, a choke point and sentinels** (D6 amended by A7): branded regex on the server-issued
   code, one send site, UUID sentinel sweep of every candidate response.
7. **Ceiling and release** (D7 amended by A10, N12, N16, N17): template-derived lifetime, 480 s headroom, `/end`
   does not release a shared ref a planned competency needs, release goes through the existing deferred job with a
   sibling guard, an explicit `participant_left_timeout`, and an unannounced end is handled as a ceiling.
8. **Ship dark, in order**: API slices (the `/end` release guard before the continuation grant), then frontend
   slices (response-driven, act only if `continuation` is present), then the remaining live gates, then an
   owner-decided canary flip. The old one-conversation-per-
   competency path stays as the fallback forever (flag off, ceiling, any refusal).

## Rollout and flag

- `config/interview.php`: `tavus.single_session` (env `INTERVIEW_TAVUS_SINGLE_SESSION`, default **false**) and
  `tavus.single_session_projects` (env `INTERVIEW_TAVUS_SINGLE_SESSION_PROJECTS`, comma-separated project ids,
  default empty). Single-session applies to a project when the flag is true or its id is in the list.
- Flag off means: no plan composed, no `conversation_plan` written, `live_conversation_id` ignored, no
  `continuation`, no `conversation_id` added to the response. The response is byte-identical to today's.
- The frontend never reads the flag. It acts only when the `/start` response contains `continuation`, so
  frontend slices are inert until the server is switched on.
- Order: API-01..03, API-07 (the release guard), API-04..06, API-08 sync, frontend FE-01..08, then the
  separately authorized live gates G-A to G-D, then the owner's canary decision.

## Owner decisions

Defaults taken in this rescope so the work can proceed unattended, each reversible without code changes:

| # | Decision | Default taken | Who decides when |
|---|---|---|---|
| 1 | Anchor exposure to the model: every remaining competency's BARS anchors are in the avatar context from minute one | **Accepted by the design** (they never reach the browser; they already reach the model for one competency today) | Settled |
| 2 | Q1 adaptivity go/no-go threshold for the live A/B against the single-competency baseline | Not decided | Owner, **before the flag flip**, not before the code |
| 3 | Canary scope (organization or project) and the default flag value | Flag **off**; canary list empty | Owner, at the flip |
| 4 | Mid-competency forced reconnect is audible/visible (Q5) | Accepted as a bounded degradation (existing 10 s `transition-panel` fallback) | Owner may revisit after gate G-B |
| 5 | Cost: Tavus billing for a longer conversation, larger LLM context per turn | Not decided (the spike returned no cost signal) | Owner, at the flip |
| 6 | `participant_left_timeout` value, and whether to also set it on the flag-off path (where lingering exists today) | 60 s, single-session only, config-driven | Owner, after gate G-D |
| 7 | Steering wording (append template, `respond` constant) | Provisional; shape frozen | Before the flip, at gate G-C |

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `api/app/Actions/Interview/ComposeConversationPlan.php` | New | Plan composition and per-competency snapshot (A8, A9) |
| `api/app/Actions/Interview/AdvanceOnLiveConversation.php` | New | Continuation grant (D2, A6, A9) |
| `api/app/Services/Conversation/SystemPromptComposer.php` | Modified | `composeMany` and `ConversationPlan` DTO over already-resolved inputs (templates and override included); `db-driven-conversation-prompts` is merged and archived, so `compose()` already takes `?PromptTemplateSet` and `?string $override` |
| `api/app/Services/Provider/TavusProvider.php` | Modified | Multi-context create body with `participant_left_timeout`; golden fixture added, old one kept for flag off |
| `api/app/Http/Controllers/Candidate/InterviewController.php` (2092 lines) | Modified | Thin wiring only; the per-competency composition (`composePromptForCompetency`, `:945`) is extracted into an action first; `end()` release guard; hand-written `@scramble-return` at `:148` grows `conversation_id`, `conversation_ttl_seconds` and `continuation` |
| `api/app/Http/Controllers/Candidate/UtteranceController.php` | Modified | `boundary_due` on the 202 |
| `api/app/Support/Interview/ProviderRefLifetime.php`, `SessionLiveClock.php` | New / Modified | Ref age span and template ceiling (`resolveMaxSeconds` is private today and gets exposed) |
| `api/app/Jobs/ReleaseEndedProviderSessionJob.php`, `app/Actions/Interview/ReleaseProviderSession.php`, `app/Console/Commands/ReapStaleInterviews.php` | Modified | Sibling guard before any release (the job and the reaper's release already exist on `develop`) |
| `api/database/migrations/` | New | Nullable `conversation_plan` plus partial unique index on open periods per ref |
| `api/config/interview.php`, `api/config/conversation.php` | Modified | Flag and canary; `max_context_chars`, `ceiling_headroom_seconds`, `boundary_grace_turns` |
| `frontend/app/utils/advance-interaction.ts`, `competency-codes.ts` | New | Fixed template, branded code check |
| `frontend/app/providers/tavus.ts` | Modified | `sendBoundary(ticket)` behind `SupportsContextSteering` (the only `sendAppMessage` call site) |
| `frontend/app/composables/useInterviewSession.ts` | Modified | Cursor, `'boundary'` target, `assertBoundary()`, ceiling crossfade ungated |
| `frontend/app/components/InterviewSession.vue` | Modified | Question-timer reset and `ProctorOverlay :session-id` follow the cursor (`:771`, `:323`) |
| `{api,frontend,backoffice}/openapi.json`, `{frontend,backoffice}/types/api.ts` | Regenerated | Not counted against the review budget |
| `backoffice/` feature code, public API (`openapi.v1.json`) | **Unchanged** | `PublicApi\InterviewController` returns no provider handle; asserted by a fresh export diff |

`api` and `frontend` are git submodules: every slice is a submodule PR plus, at the sync points, a wrapper
pointer bump.

## Existing tests that pin today's behaviour

| Test | Effect |
|---|---|
| `api` `tests/Feature/C8/TavusProviderPayloadTest.php` (`conversational_context` is the composed prompt) | Stays green with the flag off; a new multi-context test is added beside it |
| `api` `tests/Fixtures/Provider/tavus/conversations_request_golden.json` | Stays untouched for flag off; new `conversations_request_multi_golden.json` added |
| `api` `tests/Feature/C9/ResumeTranscriptTest.php` | Must stay green for the unshared-ref case |
| `api` `tests/Unit/Support/Interview/SessionLiveClockTest.php` | Must stay green; the platform cap is unchanged, the template cap is exposed |
| `api` `tests/Feature/Interview/ReapStaleInterviewsTest.php` | Must stay green; gains a live-sibling-skips-release assertion |
| `api` `tests/Feature/Interview/EndReleasesProviderContextTest.php` | Must stay green: `/end` releases exactly as today unless the new shared-ref guard applies |
| `api` the F3 prompt goldens (`tests/Unit/C8/SystemPromptComposerTemplatesTest.php`, `SystemPromptComposerTest.php`) | Must stay byte-identical green: every plan segment is the single-competency composition |
| `frontend` HeyGen suites (`interview-handover.spec.ts`, `use-interview-session.spec.ts`) | Must stay green unmodified |
| `frontend` any test asserting one `/start` per Tavus competency | Stays valid with the flag off (a response without `continuation` takes today's path) |

## Changed-line forecast and delivery

The per-slice figures in `tasks.md` add up to roughly **4,500 authored changed lines** (about 2,200 in `api`
and 2,300 in `frontend`, tests included, generated OpenAPI snapshots excluded). That is more than double the
2026-08-21 forecast of 1,300-1,700 and the 2,000-2,400 of its design, because the rescope adds the plan freeze
and column, the grant action, the ref lifetime, the release guard, the acknowledgement rule, echo suppression and,
since 2026-10-09, the composition-through-the-stored-set extraction. API-03 and FE-06 are the slices most likely
to cross 400; each is pre-split (03a/03b, 06a/06b) in `tasks.md`.

```
400-line budget risk: High
Chained PRs recommended: Yes (15 slices, each <= ~400 authored lines incl. tests)
Decision needed before apply: No (owner defaults recorded above)
```

Delivery strategy: each slice is its own PR merged in dependency order, all dark. PR0 is this docs slice.

| Slice | Repo | Subject | ~Lines |
|---|---|---|---|
| PR0 | wrapper | Rescoped proposal, design, specs, tasks (this slice) | docs |
| API-01 | api | Schema, config | 220 |
| API-02 | api | `composeMany` over resolved inputs, `ConversationPlan` | 350 |
| API-03 | api | Create path with plan through the stored set, `participant_left_timeout` (flag-gated) | 400 (03a extraction + 03b plan) |
| API-04 | api | Continuation grant | 400 |
| API-05 | api | `ProviderRefLifetime`, ceiling refusal, deferred release on refusal | 300 |
| API-06 | api | `boundary_due` | 250 |
| API-07 | api | Shared-ref release guard (`/end`, deferred job, reaper, resume); merges BEFORE API-04 | 300 |
| API-08 | api + consumers | OpenAPI sync, one wrapper bump | generated |
| FE-01 | frontend | Interaction template, code check | 250 |
| FE-02 | frontend | `sendBoundary` (append + respond), acknowledgement, echo hold | 350 |
| FE-03 | frontend | `AttributionCursor` refactor | 350 |
| FE-04 | frontend | Continuation flow | 400 |
| FE-05 | frontend | `boundary_due` consumption | 200 |
| FE-06 | frontend | Ceiling handover, unannounced end | 400 (06a + 06b) |
| FE-07 | frontend | Playwright flows | 350 |
| FE-08 | frontend | Generated client and drift check | generated |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| **BARS anchors reach the candidate's browser** | Certain if the naive design is taken | The plan column holds no anchors; the only client-bound strings are a code and fixed templates; UUID sentinel sweep of `/start` (create and continuation), `/utterance`, `/end`, `/integrity`, `/snapshot` with a positive assertion on the faked `/v2/conversations` body |
| **Utterance misattributed across the boundary** | High | Cursor moves before the send (type-enforced); scripted-tape test with an exact `(session_id,text)` multiset that fails on `main` |
| **Avatar does not obey "do not begin a topic until told"** with a long multi-topic context | Med-High | Offline: nothing. Live: the two-topic spike supports the negative half only (L5 inconclusive); gate G-A is the realistic A/B. Mitigated by the flag staying off until the owner accepts the result |
| **`/end` kills the shared conversation at the first boundary** (since `heygen-context-cleanup`, `/end` releases) | Certain if unguarded | Shared-ref release guard (N12) merged BEFORE the continuation grant; deferred job as the safety net; sibling guard on every release path |
| **Steering silently lost** (no acknowledgement exists) | Med | Explicit ack rule: first avatar utterance within the window, else `steering_failed`, one retry if joined, else `timeout` and the fresh path |
| **`respond` echoed back as candidate speech** | **Certain (live-verified)** | Armed one-shot hold-and-drop by correlation (N15) and the microphone muted until the acknowledgement |
| **The steering sequence does not open the next topic, or answers in English in a non-English interview** | Med | Shape verified; wording provisional; live gate G-C before the flip (N14) |
| Paraphrased end phrase never fires the boundary | Med-High | `boundary_due` and the 300 s timer; both funnel into one idempotent `assertBoundary()` |
| A browser drop leaves a conversation running, billing and holding a concurrency slot (`participant_left_timeout` unset did NOT end it, live-verified) | Med-High | Explicit release on every ending path (N12), explicit `participant_left_timeout` on single-session conversations (N16, value unverified: gate G-D); fresh-issue by construction on resume, tab-hidden, pause and re-offer |
| Resume teardown kills a ref another live row depends on | Low-Med | Skip teardown only when a live sibling shares the ref |
| Ceiling hit mid-competency or at a boundary | Certain on 14-18 competency roles | Server refusal at the boundary, client age timer mid-competency, shipped crossfade ungated |
| Two open periods on one ref halve the computed age | Low | Partial unique index |
| Mixing two prompt sets inside one plan (the active set flips between two resolutions) | Low | One-set assertion in `ComposeConversationPlan`, fail closed with the existing 422 (N13) |
| HeyGen regression | Med | HeyGen suites unmodified are a must-stay-green invariant |

## Rollback Plan

- **Operational, no deploy**: set `INTERVIEW_TAVUS_SINGLE_SESSION=false` and clear the canary list. The next
  `/start` ignores `live_conversation_id`, issues fresh, and the frontend crossfades (FE-06). An interview in
  flight degrades to a fresh `/start`, which every version of this code handles. The `/end` release guard acts
  only on rows that carry a plan, so with the flag off (no new plans) it is inert; a conversation already shared
  when the flag is switched off is released by the deferred job or by the next `/end` that finds no plan to cover.
- **Code**: revert slices in reverse order. Frontend slices are response-driven and revert independently; API
  slices are additive.
- **Schema**: the only artefacts are the nullable `conversation_plan` column and one partial unique index; both
  are additive and dropped by `down()`. No backfill and no data migration.

## Dependencies

- `frontend v0.9.0` (shipped): the crossfade that FE-06 ungates.
- api `v0.26.4` (shipped): the resume transcript-harvest fix the sibling guard builds on.
- `db-driven-conversation-prompts` (F3): **merged and archived 2026-10-09**
  (`openspec/changes/archive/2026-10-09-db-driven-conversation-prompts/`). `compose()` takes `?PromptTemplateSet`
  and `?string $override`; `PromptSetResolver::resolveActive(locale, code, roleCode)` resolves the active stored set;
  `ComposedPrompt::$promptSetRef` and `QuestionContext::stampedPromptVersion()` carry the set into the durable
  `conversation_prompt_version` stamp. API-02 and API-03 build on these (design N13); there is no ordering
  dependency left.
- `heygen-context-cleanup` (merged): `ReleaseProviderSession`, `ReleaseEndedProviderSessionJob`,
  `interview.provider_release_delay_seconds`; `/end` and the reaper release the provider session after commit. The
  shared-ref guard (N12) extends them.
- frontend PR #69 (merged): de-duplicates the avatar's `pal` copy by `inference_id`; the acknowledgement rule
  depends on it.
- `@daily-co/daily-js ^0.91.0`: already installed; `sendAppMessage` needs no new dependency.
- Two `openapi.json` exports regenerated together: `task openapi:sync` with `DB_CONNECTION=pgsql`.
- Pest runs by exact file path, never `php artisan test --filter` (observed fabricating passes in this repo).

## Success Criteria

- [ ] With the flag on for a canary project, a 3-competency Tavus interview completes in one Daily
      conversation: one `createProvider` call, at most one player, one fresh `/start` and two continuations.
- [ ] With the flag off, every response and every provider call is byte-identical to today's.
- [ ] No BARS anchor text, indicator text or composed prompt appears in any candidate-readable response,
      asserted by UUID sentinel (positive assertion on the Tavus create body).
- [ ] Every utterance lands on the row of the competency being discussed; the scripted tape test passes.
- [ ] A paraphrased closing line still advances the interview (`boundary_due`).
- [ ] A reload, pause, tab-hidden or re-offer never claims a continuation and always issues fresh.
- [ ] `/end` of a competency whose conversation a planned competency will use does not release it, and a deferred
      release never ends a ref a live row still uses.
- [ ] The `respond` echo never reaches `/utterance` or the transcript; no candidate speech is lost to the filter.
- [ ] An interview crossing the template ceiling hands over without losing a competency or an utterance.
- [ ] Live gates G-A to G-D recorded in `tasks.md` and the owner decisions of Appendix B taken before any flag flip.
- [ ] Scoring input for a shared-ref interview equals N separate-ref interviews.
- [ ] Every HeyGen path behaves as before; `openapi.v1.json` is byte-identical after a fresh export.
- [ ] Full Pest, Vitest and Playwright (chromium + webkit) green; Pint, PHPStan, typecheck clean.

## Open questions (carried, none block dark slices)

1. **Q1 - does one large context degrade adaptivity?** Measured by the realistic A/B (gate G-A; the 2026-10-09
   L5 was inconclusive) before the flip; threshold is owner decision 2.
2. **Q2 - mechanical boundary fallback:** RESOLVED by design D5, kept: server-asserted `boundary_due`.
3. **Q3 - where the race closes:** RESOLVED by design D3 amended: client cursor ordered before the cause.
4. **Q4 - boundary failure scope:** RESOLVED: a competency-level `timeout`, never an interview-level failure.
5. **Q5 - visible ceiling handover:** accepted default (owner decision 4).
6. **Q6 - release delay versus `TavusConcurrencyGuard`:** open; observable only under load.
7. **Q7 - does the end-phrase, append, respond sequence open the next topic in the project's language?** Open;
   gate G-C.
8. **Q8 - which `participant_left_timeout` value ends a single-session conversation, and how fast?** Open;
   gate G-D.

## Assumptions for user review

1. **The anchors never reach the browser.** Non-negotiable.
2. **The full context ships at creation**, server-side; a server-side Daily participant stays rejected.
3. **The per-competency `interview_sessions` row stays.** One additive column and one additive index are the
   only schema change (correcting the original "no schema change").
4. **Two mechanisms**: boundary steering and ceiling crossfade.
5. **HeyGen is untouched.**
6. **The steering interaction carries a server-issued competency code inside a fixed template and nothing else.**
7. **The flag is off by default** and flipping it is the owner's decision after the remaining authorized live gates.
8. **A shared conversation is never released by an ordinary `/end`** while a planned competency will use it.
9. **Composition goes through the stored prompt set** from one set per conversation, stamped on every row.
