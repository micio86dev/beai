# Proposal: One Tavus Conversation Across Many Competencies

> **STATUS: Rescoped 2026-10-08.** This is a living change, rewritten in place. The original proposal
> (2026-08-21) was re-validated against `develop` (api `e215c43`, frontend `99523a3`) and the Tavus
> documentation (`https://docs.tavus.io/llms-full.txt`, fetched 2026-10-08). Thirteen corrections (A1-A13)
> and the new decisions are recorded in `design.md` under "Amendments 2026-10-08". `tasks.md` now exists and
> owns the slicing. Nothing is implemented yet: this change is docs-only until the first task slice lands.
> What changed in one line: the boundary interaction is `conversation.append_llm_context`, not
> `overwrite_llm_context`; the schema is no longer untouched; the whole path ships dark behind a flag; and a
> live spike is a separate, explicitly authorized step that this change does NOT assume.

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
| 1 | Tavus accepts context interactions on a **live** conversation over the Daily data channel: `conversation.append_llm_context {context}` **appends** to the LLM context, `conversation.overwrite_llm_context {context}` **replaces** it, `conversation.respond {text}` is "a user typed a message and the PAL should respond as if the user had spoken that text". | `llms-full.txt` lines 15583-15586 (interaction table) and 6384-6400 (`respond` envelope). Envelope for all of them: `{message_type:'conversation', event_type, conversation_id, properties:{...}}` sent with `call.sendAppMessage(payload,'*')`. `@daily-co/daily-js ^0.91.0` is installed; BEAI only *receives* app-messages today (`frontend/app/providers/tavus.ts:146`). |
| 2 | Tavus has **no server transcript**: utterances arrive live, per utterance, already attributed. HeyGen's one-blob-per-session-ref problem does not exist here. | `TavusProvider::reconcileTranscript()` returns `[]`. |
| 3 | The ceiling is configurable per avatar template and capped by the plan: `max_call_duration` is "automatically capped to your plan's maximum". `TAVUS_MAX_SECONDS = 3600` is BEAI's platform bound; a template can set a lower `maxCallDurationSec` (the demo template uses 900). At a 300 s question limit a short project fits in one conversation; a 14-18 competency role does not and needs the ceiling handover. | `ProviderFieldSpecs.php:60,256`; `SessionLiveClock::resolveMaxSeconds` (`:135-156`); `llms-full.txt` line 4627. |

**What the original proposal got wrong, now corrected.** It named `overwrite_llm_context` as the steering
interaction and recorded a smoke result for it. Overwriting with a pointer would delete the multi-topic
anchors the design relies on, so the rescope uses **context-append** and, if the live spike shows the avatar
does not open the next topic on its own, a fixed `respond` trigger. The 2026-08-21 overwrite smoke result is
kept as history and was NOT re-run in this rescope.

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
| 2 | **A non-sensitive steering interaction at each boundary**: `conversation.append_llm_context` carrying a fixed template plus the server-issued competency code, optionally followed by a fixed `conversation.respond` trigger. No anchors, no indicator text, no prompt. |
| 3 | **A server grant path** (`App\Actions\Interview\AdvanceOnLiveConversation`) that creates the next `interview_sessions` row on the same live ref instead of calling `issue()`, only when the browser asserts `live_conversation_id` and every grant rule holds. |
| 4 | **An attribution cursor** in the frontend that retargets utterance attribution, `/end`, `/suspend`, snapshots, integrity flushes, the question timer and the proctor overlay to the current competency, always *before* the steering message is sent. |
| 5 | **A mechanical boundary signal** (`boundary_due` on the `/utterance` 202) and an **explicit steering acknowledgement rule** (first replica utterance, or `steering_failed`). |
| 6 | **Echo suppression**: the client drops its own `respond` text if Tavus echoes it back as a user-role utterance. |
| 7 | **Ceiling handling**: `ProviderRefLifetime` derives the ref age and the ceiling from the template, the server refuses a continuation near it and returns `conversation_ttl_seconds` on a fresh plan, the client crossfades to a fresh conversation, a client age timer covers mid-competency expiry. |
| 8 | **`ReleaseProviderConversation`**: a queued, tenant-scoped, best-effort teardown dispatched after the ceiling resume, after `/end` when `next_action` is not `continue`, and from the stale-interview reaper. |
| 9 | **Resume teardown that knows about siblings**: skip teardown only when a live sibling row shares the ref. |
| 10 | **Schema**: nullable `conversation_plan` plus one partial unique index (one open live period per `provider_session_ref`). Both additive, both dropped by `down()`. |
| 11 | **A feature flag** `INTERVIEW_TAVUS_SINGLE_SESSION` (default **false**) and an optional project-id canary list. Everything ships dark. |
| 12 | Tests in all three tiers (Pest, Vitest, Playwright), strict TDD, plus the offline-versus-live split in `tasks.md`. |

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
- **The live spike itself** (L1-L8 in `tasks.md`). It spends Tavus credits and needs a separate explicit owner
  authorization. It is not assumed, not scheduled and not a prerequisite for merging any dark slice.
- **The per-question 300 s timer as the boundary answer.** It stays the floor (design D5).
- **Flipping the flag.** Enabling it for a canary project is an owner decision after the spike.

## Rescope: what changed and where it is recorded

| Ref | Original claim | Verified reality | Recorded in |
|---|---|---|---|
| A1 | D4a drain is to be built | Already shipped (`useInterviewSession.ts:632-657`, awaited in `callEnd` and `callSuspend`); only the uplink mute remains | design A1 |
| A2 | Handle keeps `dbSessionId` for `/end` | That would POST `/end` for row N again (409). A cursor must feed `/end`, `/suspend`, `sessionId`, snapshot, integrity | design A2 |
| A3 | `overwrite_llm_context` | Tavus documents `append_llm_context` ("Appends") and `overwrite_llm_context` ("Replaces") | design A3 |
| A4 | Steering has an observable result | No interaction acknowledgement exists; the only signals are the next replica utterance and Daily `left-meeting`/`error` | design A4 |
| A5 | `/end` leaks a live conversation | Overstated: `participant_left_timeout` defaults to 0 and `participant_absent_timeout` to 300 | design A5 |
| A6 | Conversation id handed over on continuation only | A fresh multi-plan `/start` must return `conversation_id` too | design A6 |
| A7 | Frozen 20-code set | Codes are operator-authored `^[A-Z0-9_]+$`, max 16 | design A7 |
| A8 | `composeMany` maps `compose()` | Per-competency resolution is not a map; it lives in a new action | design A8 |
| A9 | Snapshots per row are free | Each row snapshots `primary_questions` and `follow_up_budget`; needs a freeze and an LLM snapshot copy | design A9 |
| A10 | Ceiling is the constant 3600 | It comes from the template; headroom 480 s | design A10 |
| A11 | Resume reuses the live ref | Resume issues first, tears down second; the browser has left the room | design A11 |
| A12 | Two code paths | Eight paths must go through plan/continuation logic | design A12 |
| A13 | Response schema | Hand-written `@scramble-return` must grow `conversation_id`, `conversation_ttl_seconds`, `continuation`; `/utterance` gains a 202 body | design A13, N11 |

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
4. **Steer by appending, acknowledge by the next replica utterance** (A3, A4): a bounded wait, one retry if
   still joined, otherwise the competency ends as `timeout` and the next `/start` issues fresh.
5. **Boundary has three inputs, one mechanical** (D5): end phrase, server-asserted `boundary_due`, 300 s timer.
6. **Anti-leak is a type, a choke point and sentinels** (D6 amended by A7): branded regex on the server-issued
   code, one send site, UUID sentinel sweep of every candidate response.
7. **Ceiling and release** (D7 amended by A10, A5): template-derived lifetime, 480 s headroom, delayed
   `ReleaseProviderConversation` as belt-and-braces.
8. **Ship dark, in order**: API slices, then frontend slices (response-driven, act only if `continuation` is
   present), then the optional live spike, then an owner-decided canary flip. The old one-conversation-per-
   competency path stays as the fallback forever (flag off, ceiling, any refusal).

## Rollout and flag

- `config/interview.php`: `tavus.single_session` (env `INTERVIEW_TAVUS_SINGLE_SESSION`, default **false**) and
  `tavus.single_session_projects` (env `INTERVIEW_TAVUS_SINGLE_SESSION_PROJECTS`, comma-separated project ids,
  default empty). Single-session applies to a project when the flag is true or its id is in the list.
- Flag off means: no plan composed, no `conversation_plan` written, `live_conversation_id` ignored, no
  `continuation`, no `conversation_id` added to the response. The response is byte-identical to today's.
- The frontend never reads the flag. It acts only when the `/start` response contains `continuation`, so
  frontend slices are inert until the server is switched on.
- Order: API-01..07, API-08 sync, frontend FE-01..08, then (separately authorized) the live spike, then the
  owner's canary decision.

## Owner decisions

Defaults taken in this rescope so the work can proceed unattended, each reversible without code changes:

| # | Decision | Default taken | Who decides when |
|---|---|---|---|
| 1 | Anchor exposure to the model: every remaining competency's BARS anchors are in the avatar context from minute one | **Accepted by the design** (they never reach the browser; they already reach the model for one competency today) | Settled |
| 2 | Q1 adaptivity go/no-go threshold for the live A/B against the single-competency baseline | Not decided | Owner, **before the flag flip**, not before the code |
| 3 | Canary scope (organization or project) and the default flag value | Flag **off**; canary list empty | Owner, at the flip |
| 4 | Mid-competency forced reconnect is audible/visible (Q5) | Accepted as a bounded degradation (existing 10 s `transition-panel` fallback) | Owner may revisit after the spike |
| 5 | Cost: Tavus billing for a longer conversation, larger LLM context per turn | Not decided | Owner, at the flip |

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `api/app/Actions/Interview/ComposeConversationPlan.php` | New | Plan composition and per-competency snapshot (A8, A9) |
| `api/app/Actions/Interview/AdvanceOnLiveConversation.php` | New | Continuation grant (D2, A6, A9) |
| `api/app/Services/Conversation/SystemPromptComposer.php` | Modified | `composeMany` and `ConversationPlan` DTO; F3 (`db-driven-conversation-prompts`) also edits this file and merges first |
| `api/app/Services/Provider/TavusProvider.php` | Modified | Multi-context create body; golden fixture added, old one kept for flag off |
| `api/app/Http/Controllers/Candidate/InterviewController.php` (1966 lines) | Modified | Thin wiring only; hand-written `@scramble-return` at `:141` grows `conversation_id` and `continuation` |
| `api/app/Http/Controllers/Candidate/UtteranceController.php` | Modified | `boundary_due` on the 202 |
| `api/app/Support/Interview/ProviderRefLifetime.php`, `SessionLiveClock.php` | New / Modified | Ref age span and template ceiling (`resolveMaxSeconds` is private today and gets exposed) |
| `api/app/Jobs/ReleaseProviderConversation.php`, `app/Console/Commands/ReapStaleInterviews.php` | New / Modified | Release job and a reaper dispatch (`endSession` never tears down today) |
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
| `api` `tests/Feature/Interview/ReapStaleInterviewsTest.php` | Must stay green; gains a release-dispatch assertion |
| `frontend` HeyGen suites (`interview-handover.spec.ts`, `use-interview-session.spec.ts`) | Must stay green unmodified |
| `frontend` any test asserting one `/start` per Tavus competency | Stays valid with the flag off (a response without `continuation` takes today's path) |

## Changed-line forecast and delivery

The per-slice figures in `tasks.md` add up to roughly **4,400 authored changed lines** (about 2,200 in `api`
and 2,200 in `frontend`, tests included, generated OpenAPI snapshots excluded). That is nearly double the
2026-08-21 forecast of 1,300-1,700 and the 2,000-2,400 of its design, because the rescope adds the plan freeze
and column, the grant action, the ref lifetime, the release job, the acknowledgement rule and echo suppression.

```
400-line budget risk: High
Chained PRs recommended: Yes (15 slices, each <= ~400 authored lines incl. tests)
Decision needed before apply: No (owner defaults recorded above)
```

Delivery strategy: each slice is its own PR merged in dependency order, all dark. PR0 is this docs slice.

| Slice | Repo | Subject | ~Lines |
|---|---|---|---|
| PR0 | wrapper | Rescoped proposal, design, specs, tasks (this slice) | docs |
| API-01 | api | Schema, config | 180 |
| API-02 | api | `composeMany`, `ConversationPlan` | 350 |
| API-03 | api | Create path with plan (flag-gated) | 400 |
| API-04 | api | Continuation grant | 400 |
| API-05 | api | `ProviderRefLifetime`, ceiling refusal | 250 |
| API-06 | api | `boundary_due` | 250 |
| API-07 | api | `ReleaseProviderConversation`, sibling guard | 350 |
| API-08 | api + consumers | OpenAPI sync, one wrapper bump | generated |
| FE-01 | frontend | Interaction template, code check | 250 |
| FE-02 | frontend | `sendBoundary`, acknowledgement, echo | 300 |
| FE-03 | frontend | `AttributionCursor` refactor | 350 |
| FE-04 | frontend | Continuation flow | 400 |
| FE-05 | frontend | `boundary_due` consumption | 200 |
| FE-06 | frontend | Ceiling handover | 350 |
| FE-07 | frontend | Playwright flows | 350 |
| FE-08 | frontend | Generated client and drift check | generated |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| **BARS anchors reach the candidate's browser** | Certain if the naive design is taken | The plan column holds no anchors; the only client-bound strings are a code and fixed templates; UUID sentinel sweep of `/start` (create and continuation), `/utterance`, `/end`, `/integrity`, `/snapshot` with a positive assertion on the faked `/v2/conversations` body |
| **Utterance misattributed across the boundary** | High | Cursor moves before the send (type-enforced); scripted-tape test with an exact `(session_id,text)` multiset that fails on `main` |
| **Avatar does not obey "do not begin a topic until told"** with a long multi-topic context | Med-High | Offline: nothing. Live: L5 A/B. Mitigated by the flag staying off until the owner accepts the result |
| **Steering silently lost** (no acknowledgement exists) | Med | Explicit ack rule: first replica utterance within the window, else `steering_failed`, one retry if joined, else `timeout` and the fresh path |
| **`respond` echoed back as candidate speech** | Med | Client drops its own steering text from the transcript stream; live L4 records the real shape |
| Paraphrased end phrase never fires the boundary | Med-High | `boundary_due` and the 300 s timer; both funnel into one idempotent `assertBoundary()` |
| A browser drop kills the shared conversation (`participant_left_timeout` 0) | Med | Fresh-issue by construction on resume, tab-hidden, pause and re-offer, since the browser holds no live handle |
| Resume teardown kills a ref another live row depends on | Low-Med | Skip teardown only when a live sibling shares the ref |
| Ceiling hit mid-competency or at a boundary | Certain on 14-18 competency roles | Server refusal at the boundary, client age timer mid-competency, shipped crossfade ungated |
| Two open periods on one ref halve the computed age | Low | Partial unique index |
| F3 and API-02 both edit `SystemPromptComposer` | Certain if parallel | Ordering dependency: F3 merges first, API-02 rebases onto it |
| HeyGen regression | Med | HeyGen suites unmodified are a must-stay-green invariant |

## Rollback Plan

- **Operational, no deploy**: set `INTERVIEW_TAVUS_SINGLE_SESSION=false` and clear the canary list. The next
  `/start` ignores `live_conversation_id`, issues fresh, and the frontend crossfades (FE-06). An interview in
  flight degrades to a fresh `/start`, which every version of this code handles.
- **Code**: revert slices in reverse order. Frontend slices are response-driven and revert independently; API
  slices are additive.
- **Schema**: the only artefacts are the nullable `conversation_plan` column and one partial unique index; both
  are additive and dropped by `down()`. No backfill and no data migration.

## Dependencies

- `frontend v0.9.0` (shipped): the crossfade that FE-06 ungates.
- api `v0.26.4` (shipped): the resume transcript-harvest fix the sibling guard builds on.
- `db-driven-conversation-prompts` (F3, open): edits `SystemPromptComposer`; it merges first and API-02 rebases
  onto it.
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
- [ ] An interview crossing the template ceiling hands over without losing a competency or an utterance.
- [ ] Scoring input for a shared-ref interview equals N separate-ref interviews.
- [ ] Every HeyGen path behaves as before; `openapi.v1.json` is byte-identical after a fresh export.
- [ ] Full Pest, Vitest and Playwright (chromium + webkit) green; Pint, PHPStan, typecheck clean.

## Open questions (carried, none block dark slices)

1. **Q1 - does one large context degrade adaptivity?** Measured by L5 before the flip; threshold is owner
   decision 2.
2. **Q2 - mechanical boundary fallback:** RESOLVED by design D5, kept: server-asserted `boundary_due`.
3. **Q3 - where the race closes:** RESOLVED by design D3 amended: client cursor ordered before the cause.
4. **Q4 - boundary failure scope:** RESOLVED: a competency-level `timeout`, never an interview-level failure.
5. **Q5 - visible ceiling handover:** accepted default (owner decision 4).
6. **Q6 - release delay versus `TavusConcurrencyGuard`:** open; observable only under load.

## Assumptions for user review

1. **The anchors never reach the browser.** Non-negotiable.
2. **The full context ships at creation**, server-side; a server-side Daily participant stays rejected.
3. **The per-competency `interview_sessions` row stays.** One additive column and one additive index are the
   only schema change (correcting the original "no schema change").
4. **Two mechanisms**: boundary steering and ceiling crossfade.
5. **HeyGen is untouched.**
6. **The steering interaction carries a server-issued competency code inside a fixed template and nothing else.**
7. **The flag is off by default** and flipping it is the owner's decision after an authorized live spike.
