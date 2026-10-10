# Tasks: One Tavus Conversation Across Many Competencies

Strict TDD: every behaviour task is a RED step (a failing test, observed failing for the stated reason) followed by a
GREEN step (the smallest change that makes it pass), then REFACTOR with the suite green. A box is ticked only for an
observed outcome, with the commit sha next to it. Inputs: `proposal.md`, `design.md` (read "Amendments 2026-10-09" and
Appendix A first), `specs/*/spec.md`. Created 2026-10-08, rewritten 2026-10-09 from api `origin/develop` `cf1d82a`,
frontend `origin/develop` `cc26363`, wrapper `develop` `fc451c5` and the live spike of 2026-10-09. Nothing below SPIKE-01
is implemented yet.

## Rules for every slice

- **Review budget.** About **400 authored changed lines per slice, tests and docs included** (additions plus deletions).
  A planning heuristic, not a hard cap: if the correct solution is larger, say why in the PR and continue; never delete
  blank lines or comments, omit tests, minify or split artificially. **Excluded from the count and stated in each PR:**
  `openapi.json` (api, frontend, backoffice), `types/api.ts`, and fixtures or goldens produced by a command.
- **Commits.** One Conventional Commit per work unit on a `feature/*` branch (Git Flow), tests and docs alongside the
  behaviour, no AI attribution, never `--no-verify`, never a push from a worker. Push, PR and merge stay with the owner.
  `api` and `frontend` are submodules: a slice is a submodule PR; the wrapper pointer moves only at the sync points.
- **Flag and darkness.** Every behaviour is behind `INTERVIEW_TAVUS_SINGLE_SESSION` (**default `false`**) or the canary list
  `INTERVIEW_TAVUS_SINGLE_SESSION_PROJECTS` (default empty). The frontend acts only when a `/start` response contains
  `continuation`, so it ships dark. The old one-conversation-per-competency path stays as the permanent fallback.
- **api commands.** Pest by **exact file path**: `cd api && ./vendor/bin/pest <file>` (never `php artisan test --filter`).
  Then `./vendor/bin/pint --test` and `./vendor/bin/phpstan analyse --memory-limit=1G`. Full suite once per slice, never beside
  another Pest run (parallel runs share one test database).
- **frontend commands (Bun only).** Per file: `cd frontend && bun run test:unit -- <file>`. Before a PR: `bunx nuxi prepare`,
  `bun run typecheck`, `bun run lint`, `bun run test:unit:coverage`. Every user-visible string needs `it` and `en`. Playwright
  only through `task e2e:frontend`, chromium and webkit, `--workers=1`.
- **TDD mode.** Strict TDD on; runners are Pest (api), Vitest (frontend), Playwright (E2E).
- **Delegation route.** Each slice is delegated-direct work: one writer per slice; reading that prepares the write belongs to
  the writer. No SDD phase workers. Record the route per slice in the PR.
- **Review gate.** Where receipt-driven development is enabled by the owner, the native review candidate is a work-unit commit
  or a PR slice, never a checkbox.
- **Coordination.** `candidate-interview-call-ui` (slices UI-01..UI-08 merged) also changed `useInterviewSession.ts`,
  `InterviewSession.vue` and the stage components. Every FE slice re-reads the file on `develop` before writing.

## Ordering and dependencies

```
PR0 (docs)
 API-01 -> API-02 -> API-03 (03a extraction, 03b plan) -> API-07 -> API-04 -> API-05
                                  \-> API-06 (after API-03)
 API-08 after API-01..07 (one OpenAPI sync, one wrapper bump)

 FE-01 -> FE-02 -> FE-03        (API-independent; may start after PR0)
 FE-04 needs API-04, FE-02, FE-03
 FE-05 needs API-06, FE-04
 FE-06 needs API-05, FE-04          (06a ceiling crossfade, 06b unannounced end)
 FE-07 last (FE-04..06); FE-08 with API-08

 SPIKE-02 (commit the live script), then live gates G-A..G-D (each needs a SEPARATE owner go), then the owner's flip decision
```

- **API-07 merges BEFORE API-04.** On `develop`, `/end` releases the Tavus conversation after commit
  (`ReleaseProviderSession`). Without the guard of API-07, the first granted continuation would be preceded by an `/end` that
  ended the conversation it needs (design C1, N12). API-07 depends only on API-03 (the plan exists) because the guard keys on
  the stored plan; the ceiling-triggered deferred release moved into API-05.
- **No F3 ordering any more.** `db-driven-conversation-prompts` is merged and archived
  (`openspec/changes/archive/2026-10-09-db-driven-conversation-prompts/`). `composeMany` goes through the stored prompt set
  (design N13): `SystemPromptComposer::compose(..., ?PromptTemplateSet $templates, ?string $override)`, resolved per competency
  by `PromptSetResolver::resolveActive(locale, code, roleCode)`; the set ref is stamped through
  `QuestionContext::stampedPromptVersion()` and copied to continuation rows (API-02, API-03, API-04 say how).
- **Cross-stack sync rule.** API slices commit their own regenerated `openapi.json` (generated, excluded). The wrapper pointer
  for `api` is NOT advanced between slices (the parity gate would turn red); API-08 does the single sync and ONE wrapper commit.

## Offline versus live

Everything OFFLINE is provable with Pest, Vitest and Playwright route mocks and is the merge gate. LIVE claims need a real Tavus
conversation and credits. L1-L8 were run on **2026-10-09 with the owner's authorization** (design Appendix A, evidence E1-E6);
the results below are what the logs show. The remaining gates need a separate go each and block no dark slice.

| Id | Claim | Result 2026-10-09 | Evidence |
|---|---|---|---|
| L1 | Browser can send `append_llm_context` / `respond` over the Daily data channel; Tavus accepts | **Observed: yes** (also `overwrite`) | E1 actions S1-S6 all `ok:true`, effects in later replies |
| L2 | After append the model keeps the earlier codeword; after overwrite it does not | **Observed** (clean controls; the main-run control was contaminated) | E3 (amber + scarlet), E2 (unknown + violet) |
| L3 | After an append the avatar opens the next topic unprompted, or only after `respond` | **Observed: only after `respond`** (real end-phrase sequence not tested) | E1: no event between +35 s and +60 s |
| L4 | `respond` returns as a role-`user` utterance; which `inference_id` | **Observed: yes**, text equal to the sent text, same `inference_id` as the reply, `turn_idx` set, +1.1-1.2 s | E1 utterances |
| L5 | Realistic 3-topic context obeys "do not begin until told" (Q1 A/B) | **Inconclusive**: negative half supported with 2 topics, positive half did not run, no A/B | E1 S4a, S4b |
| L6 | Behaviour at `max_call_duration` and at the plan limit | **Observed in part**: 240 s accepted, unannounced end sequence at about +241 s. **Not observed**: plan cap, clock origin | E1 lifecycle, E5 |
| L7 | `participant_left_timeout` 0 (unset) ends the conversation on browser leave | **Observed: it did not** within 86 s; ended by explicit `/end` at +95 s | E4, E6 |
| L8 | `POST /end` on an ended conversation is benign | **Observed: yes** (200, empty body, repeated and after expiry) | E6 |

Remaining LIVE gates (each a separate owner authorization; spends credits):

| Gate | Claim | Feeds |
|---|---|---|
| G-A | Realistic multi-topic composed context: obedience to "do not begin until told" and the Q1 adaptivity A/B against the single-competency baseline | Owner decision 2 (threshold) |
| G-B | Real behaviour at the plan-level cap and at `max_call_duration` with the clock origin isolated | `ceiling_headroom_seconds` (480), `HANDOVER_LEAD_MS` (120 000), owner decision 4 |
| G-C | End phrase, then append, then respond with a realistic context opens the next topic, in the project's language; final trigger wording; ack latency | N14 constants, `STEERING_ACK_TIMEOUT_MS` |
| G-D | An explicit `participant_left_timeout` (default 60) ends a conversation after the browser leaves, and how fast | N16 default, owner decision 6 |

OFFLINE proofs: create-body goldens, UUID-sentinel anti-leak, envelope golden, length/key-set tests, cursor-before-send order,
the attribution tape, fake-Daily send / no-ack / echo hold / `left-meeting` / the observed end sequence via the injectable
`sdkLoader`, Playwright route mocks, the grant/refusal matrix, ceiling arithmetic, release-guard semantics.

## PR0: docs slice (wrapper)

- [x] PR0.1 `proposal.md`, `design.md` rescoped 2026-10-08 and amended 2026-10-09 (A1-A13, N1-N17, S1-S6, C1-C5, Appendix A and B).
- [x] PR0.2 Spec deltas amended (`interview-session`, `interview-frontend`; `interview-conversation` rebuilt on the post-F3 main spec).
- [x] PR0.3 `tasks.md` rewritten (this file). Ticked because the docs commits exist on `feature/tavus-sdd-amend`; not a merge claim.

## SPIKE-01: live run L1-L8 (Done: 2026-10-09)

- [x] SPIKE-01.1 Owner authorization (spend and scope) given for the run; four conversations, all ended afterwards.
- [x] SPIKE-01.2 L1-L8 recorded with evidence in design Appendix A (table above is the summary).
- [x] SPIKE-01.3 FE-01 golden SHAPE confirmed (envelopes verified); wording stays provisional until G-C.
- [x] SPIKE-02 Commit `tavus-steering-verify.mjs` to `frontend/scripts/live/` (separate frontend PR, excluded from CI, header documents
      the scenarios) and decide whether `spike.php` becomes `interview:smoke-check --provider=tavus --multi`. Not a merge gate.

## API slices

### API-01: schema, config, gate (about 220 lines)

Depends on: PR0. Files: one migration, `config/interview.php`, `config/conversation.php`, `App\Support\Interview\SingleSessionGate`.

- [x] API-01.1 RED `tests/Feature/Interview/OpenPeriodPerRefTest.php`: a second open period on one non-null ref raises a unique violation; closed periods and null refs do not collide.
- [x] API-01.2 RED `tests/Feature/Interview/ConversationPlanColumnTest.php`: `interview_sessions.conversation_plan` round-trips the documented JSON through the cast and is null by default.
- [x] API-01.3 RED `tests/Unit/Support/Interview/SingleSessionGateTest.php`: false by default; true for `tavus` with the flag; true for a canary project id with the flag off; always false for `heygen` and `mock`.
- [x] API-01.4 GREEN migration: nullable JSON `conversation_plan` and the partial unique index on `interview_session_live_periods(provider_session_ref) WHERE provider_session_ref IS NOT NULL AND ended_at IS NULL`; `down()` drops both. Config: `interview.tavus.single_session` (default `false`), `interview.tavus.single_session_projects`, `interview.tavus.participant_left_timeout` (env `INTERVIEW_TAVUS_PARTICIPANT_LEFT_TIMEOUT`, default 60), `conversation.max_context_chars` (40000), `conversation.ceiling_headroom_seconds` (480), `conversation.boundary_grace_turns` (1). Add `SingleSessionGate`.
- [x] API-01.5 Verify: the three files green; migrate fresh and rollback on Postgres; Pint; PHPStan; `SessionLivePeriodExitsTest`, `SessionLiveClockTest` green.
- [x] API-01.6 Commit: `feat(api): add the single-session schema, config and gate`.

### API-02: `composeMany` over resolved inputs (about 350 lines; pure, unwired)

Depends on: API-01. F3 is merged, so no rebase wait. Files: `SystemPromptComposer::composeMany`, `App\DTOs\Conversation\ConversationPlan`, `ResolvedCompetencyInput`.

- [x] API-02.1 RED `tests/Unit/Conversation/SystemPromptComposerManyTest.php`: byte-identical on repeat; one `prompt_version`; global rules and `=== TOPIC CODE: X ===` markers; **each segment equals `compose()` for the same inputs** (so the F3 goldens `tests/Fixtures/Conversation/prompts/G*.txt` keep pinning segments); an override appears only inside its competency's segment; each segment holds only its own anchor sentinel; last entry carries the final phrase; role-less `potential` entries compose; truncation to the longest prefix at `max_context_chars` (measured on the final string; record the measured length of one composed competency so the owner can retune 40000); fewer than two entries refused.
- [x] API-02.2 GREEN `composeMany(list<ResolvedCompetencyInput>): ConversationPlan`: input carries every `compose()` argument including `?PromptTemplateSet $templates` and `?string $override`; the composer calls `compose()` per entry and wraps with code-constant rules and markers. No DB, no LLM, no time.
- [x] API-02.3 Verify: `tests/Unit/C8/SystemPromptComposerTest.php`, `SystemPromptComposerTemplatesTest.php`, `SystemPromptGoldenTest.php`, `PromptOverrideRenderingTest.php`, `tests/Unit/Conversation/SystemPromptComposerBudgetTest.php` unchanged and green; Pint; PHPStan.
- [x] API-02.4 Commit: `feat(api): compose a multi-competency conversation context`.

### API-03: create path with a plan, flag-gated (about 400 lines; split 03a/03b)

Depends on: API-02. Files: `App\Actions\Interview\ComposeConversationPlan`, the extracted per-competency action, `InterviewController` wiring (thin), `BuildInterviewSessionResponse`, `@scramble-return` at `:148`, `TavusProvider`, new golden.

- [x] API-03a.1 Characterisation (must be green BEFORE and AFTER, no behaviour change): extract `composePromptForCompetency()` (`InterviewController.php:945`) into a reusable action; `InterviewStartCompositionTest`, `InterviewStartPromptGoldenTest`, `PromptCutoverTest`, `PromptOverrideStartTest`, `PromptSetResolverTest` unchanged.
- [x] API-03a.2 Commit: `refactor(api): extract the per-competency prompt composition from the controller`.
- [x] API-03b.1 RED `tests/Unit/Actions/Interview/ComposeConversationPlanTest.php`: resolves revision, role (null for `potential`), authored primaries, spoken opening, advance phrase, and the stored set + override per competency through the shared action (not a map over codes); **all entries must report the same `stampRef()`: a flip between two `resolveActive()` calls yields 422 `composition_error` before any session or provider call**; the `baseline` source composes with null set and no override; `PromptTemplateUnresolvableException` keeps its 422 and `report()`; any covered competency's failure fails the whole create.
- [x] API-03b.2 RED `tests/Feature/C8/TavusProviderPayloadTest.php` (new multi case) and `tests/Fixtures/Provider/tavus/conversations_request_multi_golden.json` (includes `properties.participant_left_timeout`); `conversations_request_golden.json` untouched and still matching with the gate closed.
- [x] API-03b.3 RED `tests/Feature/Interview/ConversationPlanCreateTest.php`: flag on persists `conversation_plan` on the creating row, returns `conversation_id` (and `conversation_ttl_seconds` from API-05), stamps `conversation_prompt_version` as `{prompt_version}+s{id}.{sha12}` (bare for baseline); flag off: response byte-identical, no column write, no `participant_left_timeout`; HeyGen and mock invariant; single remaining competency writes no plan.
- [x] API-03b.4 RED `tests/Feature/Interview/SingleSessionAntiLeakSentinelTest.php`: a UUID in `anchor_5` is absent from the bodies of `/start`, `/utterance`, `/end`, `/integrity`, `/snapshot`, present in the faked `/v2/conversations` body, absent from the stored plan.
- [x] API-03b.5 GREEN the action, gate wiring in `start()`, plan persisted in the existing short transaction, `conversation_id`, grown `@scramble-return`, `participant_left_timeout` in the create body when the gate applies.
- [x] API-03b.6 Verify: new tests plus `ResumeTranscriptTest`, `ResumeHarvestTeardownRefTest`, `ResumeCompositionFailureTeardownTest`, `ProviderContractFixtureTest`; Pint; PHPStan; regenerate `api/openapi.json` on Postgres.
- [x] API-03b.7 Commit: `feat(api): create a multi-competency Tavus conversation behind the single-session flag`.

### API-07: shared-ref release guard (about 300 lines; merges BEFORE API-04)

Depends on: API-03. Files: `InterviewController::end()` and `handleResumeInCorso`, `ReleaseProviderSession`, `ReleaseEndedProviderSessionJob`, `ReapStaleInterviews`, a sibling-guard collaborator. **Reuses the existing job; no `ReleaseProviderConversation` is created** (design N12).

- [x] API-07.1 RED `tests/Feature/Interview/SharedRefEndReleaseTest.php`: `/end` with `next_action = 'continue'` on a row whose plan covers a later competency does NOT call `TavusProvider::teardown()` and dispatches `ReleaseEndedProviderSessionJob` `afterCommit` with captured refs and `provider_release_delay_seconds`; `done`, `pause`, a ref no plan shares, HeyGen and mock release exactly as before (`EndReleasesProviderContextTest` green unmodified).
- [x] API-07.2 RED `tests/Feature/Interview/ReleaseSiblingGuardTest.php`: the deferred job, the reaper release and `handleResumeInCorso` teardown each skip when another `in_corso` row shares the ref, and release when none does; an already-ended conversation is benign; a cross-organization row never counts; resume with a live sibling still issues a fresh ref and closes the resumed row's period; `ResumeTranscriptTest` green for the unshared ref.
- [x] API-07.3 GREEN the guard collaborator, the `end()` branch, the three call sites. Arch tests `QueuedJobTenantContextArchTest`, `QueuedJobRetryOwnershipArchTest` stay green.
- [x] API-07.4 Verify: new tests plus `ReapStaleInterviewsTest` (gains a live-sibling assertion), `tests/Arch`; PHPStan.
- [x] API-07.5 Commit: `feat(api): keep a shared Tavus conversation alive across a competency end`.

### API-04: continuation grant (about 400 lines)

Depends on: API-03 and API-07. Files: `App\Actions\Interview\AdvanceOnLiveConversation`, optional `/start` input `live_conversation_id`, response `continuation`.

- [x] API-04.1 RED `tests/Unit/Actions/Interview/AdvanceOnLiveConversationTest.php` and `tests/Feature/Interview/ContinuationGrantTest.php`: granted only for an owned ref whose plan covers the next code and whose next row is brand new; each of absent id, other participant, other organization, nulled ref (`/suspend`), code not in plan, `pending` row, re-offer, evaluation-retry reset, flag off falls to the issue path with an unchanged response shape.
- [x] API-04.2 RED same files: `Http::assertNotSent` on `/v2/conversations`; the new row shares the ref, is `in_corso`, opens a live period, **copies all five snapshot columns including `conversation_prompt_version`** (cost row written on end), takes `primary_questions`/`follow_up_budget` from the plan entry; a transaction failure leaks no ref and returns the existing 500; a deferred release dispatched at the previous `/end` finds a live sibling and sends nothing.
- [x] API-04.3 RED `tests/Feature/Interview/SharedRefScoringParityTest.php`: scoring input for a shared-ref interview equals N separate-ref interviews.
- [x] API-04.4 GREEN the action and `continuation`, `@scramble-return`. The grant runs after `resolveNextCompetency` and before composition (a continuation composes nothing, so a missing translation cannot turn it into a 422).
- [x] API-04.5 Verify: new tests plus `InterviewabilityIngressRefusalTest`, `InFlightSessionSurvivesTest`; PHPStan; regenerate `openapi.json`.
- [x] API-04.6 Commit: `feat(api): grant a continuation on a live Tavus conversation`.

### API-05: `ProviderRefLifetime`, ceiling refusal, deferred release on refusal (about 300 lines)

Depends on: API-04. Files: `ProviderRefLifetime`, `SessionLiveClock::resolveMaxSeconds` exposed (single owner), grant rule 5, `conversation_ttl_seconds`.

- [x] API-05.1 RED `tests/Unit/Support/Interview/ProviderRefLifetimeTest.php`: age is the span from `min(started_at)`; template cap 900 honoured; without a template 3600; near-ceiling is `age + headroom >= ceiling`.
- [x] API-05.2 RED `ContinuationGrantTest` (extend): refused near the ceiling, `issue()` runs, and the old ref is released through a **deferred** `ReleaseEndedProviderSessionJob`, never inline; a mid-competency expiry resume does the same; a fresh multi-plan response carries `conversation_ttl_seconds`.
- [x] API-05.3 GREEN the class, the exposed ceiling, the refusal, the deferred release, the field, `@scramble-return`.
- [x] API-05.4 Verify: `SessionLiveClockTest` (Tavus cap) green; PHPStan; regenerate `openapi.json`.
- [x] API-05.5 Commit: `feat(api): derive the Tavus conversation ceiling from the template`.

### API-06: `boundary_due` on `/utterance` (about 250 lines)

Depends on: API-03 (parallel with 07/04/05). Files: `UtteranceController`, `@scramble-return` for the 202.

- [x] API-06.1 RED `tests/Feature/Interview/BoundaryDueTest.php`: below, at and above `1 + follow_up_budget + grace` substantive candidate turns (6 at default config); turns shorter than `nudge_min_chars` and avatar turns do not count; 202/409/404/422 unchanged; threshold uses the row's own `follow_up_budget` snapshot.
- [x] API-06.2 GREEN the count and the 202 body inside the existing atomic insert flow.
- [x] API-06.3 Verify: `tests/Feature/C7a/UtteranceControllerTest.php` and `TurnClassifier` tests green; Pint; PHPStan; regenerate `openapi.json`.
- [x] API-06.4 Commit: `feat(api): report when a competency has met its turn budget`.

### API-08: OpenAPI sync (generated; not counted)

Depends on: API-01..07 merged in `api`. One sync, one wrapper bump.

- [x] API-08.1 `DB_CONNECTION=pgsql` confirmed (`php artisan config:show database.default`), then `task openapi:sync`.
- [x] API-08.2 Only intended operations changed: `/start` request (`live_conversation_id`) and response (`conversation_id`, `conversation_ttl_seconds`, `continuation`); `/utterance` 202 (`boundary_due`).
- [x] API-08.3 `api/openapi.v1.json` (public spec) byte-identical after a fresh export.
- [x] API-08.4 Commit snapshots in `api`, `frontend`, `backoffice` and ONE wrapper commit moving the pointers; `codegen:check` and `scripts/verify-openapi-parity.sh` pass.

## Frontend slices

### FE-01: advance interaction template and code check (about 250 lines)

Depends on: PR0. Files: `app/utils/advance-interaction.ts`, `app/utils/competency-codes.ts`, `tests/fixtures/tavus/boundary_interaction_golden.json` (new directory).

- [x] FE-01.1 RED `tests/unit/advance-interaction.spec.ts`: decoy `INNOVAZIONE`; serialized length = fixed template + code length; stripping the template leaves exactly the code; exact key sets for both envelopes; the `respond` constant carries no code; golden for BOTH messages (append, then respond) matches the live-verified shape `{message_type:'conversation', event_type, conversation_id, properties:{context}|{text}}`; `@ts-expect-error` on `sendBoundary('Begin INN now.')` and on a hand-built ticket.
- [x] FE-01.2 RED `tests/unit/competency-codes.spec.ts`: `asCompetencyCode` accepts `^[A-Z0-9_]{1,16}$`, rejects lowercase, empty, 17 characters, spaces, prose. No code list exists.
- [x] FE-01.3 RED `tests/unit/arch/send-app-message-single-site.spec.ts`: `sendAppMessage` in exactly one file and one call site; `overwrite_llm_context` nowhere in `app/`.
- [x] FE-01.4 GREEN template, `buildAdvancePayload(ticket)`, branded ticket, `asCompetencyCode`. Shape frozen; the two wording constants are PROVISIONAL until G-C (design N14).
- [x] FE-01.5 Verify: unit tests, `bunx nuxi prepare`, `bun run typecheck`, `bun run lint`.
- [x] FE-01.6 Commit: `feat(frontend): add the fixed Tavus boundary interaction`.

### FE-02: `TavusProvider.sendBoundary` (about 350 lines)

Depends on: FE-01. Files: `app/providers/tavus.ts`, `app/types/interview-provider.ts`.

- [x] FE-02.1 RED `tests/unit/tavus-provider-steering.spec.ts` with an injected fake Daily: sends append THEN respond through `sendAppMessage(msg,'*')`; refuses when not `joined-meeting`; `steering_failed` on throw, `left-meeting`, `error`, or no avatar utterance within `STEERING_ACK_TIMEOUT_MS` (10 000, fake timers); acknowledges on the first de-duplicated avatar utterance (the `pal` twin is not a second ack).
- [x] FE-02.2 RED echo (design N15), replaying the L4 shapes: the user-role utterance with the trigger text is held while armed and discarded when the next avatar utterance carries the same `inference_id`; discarded too on ack timeout; different text while armed is emitted; the same text later (disarmed) is emitted; a held utterance is released if the filter disarms unmatched; nothing echoed reaches `transcript`.
- [x] FE-02.3 GREEN `sendBoundary(ticket)` as the only outbound site behind `SupportsContextSteering`; HeyGen gets no stub.
- [x] FE-02.4 Verify: existing Tavus provider and provider-anonymity suites green; typecheck; lint.
- [x] FE-02.5 Commit: `feat(frontend): send the Tavus boundary steering, acknowledge it and drop its echo`.

### FE-03: `AttributionCursor` refactor (about 350 lines)

Depends on: FE-02. Files: `useInterviewSession.ts`, `InterviewSession.vue`, a cursor module. No HeyGen behaviour change. The drain (`drainUtterances`) is already shipped; only the mute handling is new.

- [x] FE-03.1 RED `tests/unit/use-interview-session-attribution.spec.ts`: tape `[u1(A), end, u2(window), u3(B)]` yields exactly `{(A,u1),(B,u3)}`; `/end`, `/suspend`, `sessionId`, snapshot, integrity (incl. resize flush), question-timer reset and `ProctorOverlay :session-id` read the cursor; cursor write precedes both sends; unsent integrity events flush against the outgoing row first; `/end` is never POSTed twice for A.
- [x] FE-03.2 GREEN the cursor (single mutator mints the ticket); `handle.dbSessionId` stays the player key only.
- [x] FE-03.3 Verify: HeyGen suites (`interview-handover.spec.ts`, `use-interview-session.spec.ts`) pass **unmodified**; typecheck; lint; coverage.
- [x] FE-03.4 Commit: `refactor(frontend): route every session-id reader through an attribution cursor`.

### FE-04: continuation parsing and boundary flow (about 400 lines; split 04a/04b if over)

Depends on: API-04, FE-02, FE-03.

- [x] FE-04.1 RED parse: `isValidStartResponse` accepts `continuation`/`conversation_id`, rejects a malformed continuation or one combined with a handle.
- [x] FE-04.2 RED flow (`use-interview-session-continuation.spec.ts`): `createProvider` once across three competencies; `players.length <= 1`; `/start` carries `live_conversation_id` only while a handle is joined and never after reload, pause, tab-hidden, re-offer, `retry()`, embed re-entry; no `continuation` takes today's path; the `'boundary'` target neither enters `connecting` nor publishes a handle.
- [x] FE-04.3 RED `assertBoundary()`: idempotent, racing inputs mint one ticket and one `/end`, a losing 409 is a no-op; **mute before `/end`, unmute only at the steering ack or `steering_failed`**; `steering_failed` handling (unmute, keep cursor, resend once if joined, else end the new competency as `timeout`); the Tavus `continue` directive leaves `confirmDevices()` only when `continuation` came back.
- [x] FE-04.4 GREEN the above. FE-04.5 Verify: HeyGen suites unmodified; typecheck; lint; coverage.
- [x] FE-04.6 Commit: `feat(frontend): continue a Tavus conversation across competencies`.

### FE-05: `boundary_due` consumption and paraphrase (about 200 lines)

Depends on: API-06, FE-04.

- [x] FE-05.1 RED: `sendUtterance` parses the 202 body; `boundary_due: true` triggers `assertBoundary()`; a paraphrased closing line still advances; phrase plus `boundary_due` in one tick cause one boundary; a missing or malformed body is ignored.
- [x] FE-05.2 GREEN the third input. FE-05.3 Verify: unit suites; typecheck; lint.
- [x] FE-05.4 Commit: `feat(frontend): advance on the server's boundary signal`.

### FE-06: ceiling handover (about 400 lines; 06a crossfade, 06b unannounced end)

Depends on: API-05, FE-04.

- [x] FE-06a.1 RED: crossfade predicate is "fresh handle arrives while a live handle exists" (the `isHeyGen` gate at `useInterviewSession.ts:1124-1135` area is removed); Tavus fresh handle crossfades and arms the bound on publish; HeyGen suites unmodified; flag flipped off mid-interview crossfades.
- [x] FE-06a.2 RED: age timer from `conversation_ttl_seconds` minus `HANDOVER_LEAD_MS` (120 000) calls `/start` on the `in_corso` row; question clock preserved.
- [x] FE-06b.1 RED (design N17): replaying the observed end sequence (`conversation.left`, `system.shutdown`, tracks stop, Daily `error` "Meeting has ended", `left-meeting`) through the fake Daily while a competency is `in_corso` makes the provider report a stop and the client resume the row via `/start`.
- [x] FE-06.3 GREEN predicate, timer, resume call, end-sequence handling. FE-06.4 Verify: HeyGen handover suites unmodified; typecheck; lint.
- [x] FE-06.5 Commit: `feat(frontend): hand a Tavus conversation over at its ceiling`.

### FE-07: Playwright route-mocked flows (about 350 lines)

Depends on: FE-04, FE-05, FE-06. Files: `tests/e2e/interview-single-session.spec.ts`; a steering recorder in the mock provider (`app/providers/factory.ts`).

- [x] FE-07.1 RED then GREEN: 3-competency Tavus flow (one fresh `/start`, two continuations, append then respond recorded in order, echo not posted); paraphrased closing line advances via `boundary_due`; reload issues fresh; pause/resume issue fresh; ceiling handover keeps the competency. Chromium and webkit, `--workers=1`, `task e2e:frontend`.
- [x] FE-07.2 Verify: `interview-flow.spec.ts`, `interview-chrome.spec.ts`, `embed.spec.ts` green.
- [x] FE-07.3 Commit: `test(frontend): cover the single-session Tavus flows end to end`.

### FE-08: generated client and drift check (generated; not counted)

Depends on: API-08.

- [x] FE-08.1 `types/api.ts` regenerated in `frontend` and `backoffice`; `bun run codegen:check` passes in both; wrapper parity script passes.

## Live gates G-A to G-D (separate authorization each; NOT merge gates)

Each needs the owner's written go (date, scope, budget) before any call. Tool: the SPIKE-02 script. Results are recorded here with the date.

- [ ] G-A realistic multi-topic context (composed by API-03 for a real role) and the Q1 A/B against a single-competency baseline on the same scenario; result handed to owner decision 2.
- [ ] G-B plan-level cap and `max_call_duration` with the clock origin isolated; retune `ceiling_headroom_seconds` and `HANDOVER_LEAD_MS`.
- [ ] G-C end phrase, append, respond with the realistic context; confirm or amend the two wording constants (reviewed golden change); check the reply language; record the ack latency and retune `STEERING_ACK_TIMEOUT_MS`.
- [ ] G-D explicit `participant_left_timeout` (default 60): conversation ends after the leave, how fast, concurrency slot freed.

## Owner decisions at the flip (not code)

Defaults and rationale: design Appendix B. Q1 threshold (from G-A); canary scope and default flag value; mid-competency reconnect (Q5); cost; `participant_left_timeout` value and scope; steering wording.

## Plan gaps closed

- **PG1 client has no ceiling:** the fresh multi-plan `/start` returns `conversation_ttl_seconds` (API-05, FE-06).
- **PG2 API-07 ordering:** now BEFORE API-04 and decoupled from the ceiling (see Ordering).
- **PG3 grant before composition:** a continuation composes nothing.
- **PG4 `/end` releases on `develop`:** guarded by API-07 (design C1, N12).
- **PG5 composition via the stored set:** API-02/03 (design N13); five-column snapshot copy in API-04 (design C4).
- **PG6 unset `participant_left_timeout` does not end a conversation:** explicit config in API-03, verified at G-D.

## Rollback

- **Operational, no deploy:** `INTERVIEW_TAVUS_SINGLE_SESSION=false` and an empty canary list. The next `/start` ignores `live_conversation_id` and issues fresh; the frontend crossfades (FE-06). The `/end` guard keys on a stored plan, so with no new plans it is inert.
- **Code:** revert in reverse slice order; each slice is independently revertible (frontend response-driven, API additive). API-07 must not be reverted while API-04 is live.
- **Schema:** only the nullable `conversation_plan` column and one partial unique index; additive, dropped by `down()`. No backfill.

## Merge record (2026-10-10)

All code slices are merged on `develop` in `api`, `frontend` and `backoffice` and dark behind `INTERVIEW_TAVUS_SINGLE_SESSION` (default OFF): API-04 #165, API-05 #167, API-06 #168, API-07 #164, FE-04 #87, FE-05 #89, FE-06 #88, FE-07 #90, and the contract sync in `backoffice` #84 (`frontend` synced slice by slice; `scripts/verify-openapi-parity.sh` reports one identical `openapi.json` across the three repos). Two CI changes landed along the way: the coverage memory ceiling moved from 2G to 4G in both `ci.yml` and `phpunit.xml` (#166, #165).

Open and deliberately not code: the live gates G-A to G-D (each needs the owner's written go and spends Tavus credits), and the owner decisions at the flip. Review notes worth keeping for the flip:

- API-07 ended `escalated` on a finding that a deferred release can run before the boundary `/start`; API-04's `provider_released_at` marker is the mitigation (a continuation is refused for a released ref and falls to a fresh issue).
- `boundary_due` is computed for every row, not only single-session ones (design N9).
- The echo filter is covered by the Vitest provider tests only; the Playwright flows cannot reach Daily's data channel.
