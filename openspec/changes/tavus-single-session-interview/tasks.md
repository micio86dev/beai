# Tasks: One Tavus Conversation Across Many Competencies

Strict TDD: every behaviour task is a RED step (a failing test, observed failing for the stated reason) followed by a
GREEN step (the smallest change that makes it pass), then REFACTOR with the suite green. A box is ticked only for an
observed outcome, with the commit sha next to it. Inputs: `proposal.md`, `design.md` (read "Amendments 2026-10-08" first),
`specs/*/spec.md`. Created 2026-10-08 from the verified plan (api read from `origin/develop` `e215c43`, frontend `99523a3`).

## Rules for every slice

- **Review budget.** About **400 authored changed lines per slice, tests and docs included** (additions plus deletions).
  It is a planning heuristic, not a hard cap: if the correct solution is larger, say why in the PR and continue; never
  delete blank lines or comments, omit tests, minify or split artificially to fit. **Excluded from the count and stated
  as such in each PR:** `openapi.json` (api, frontend, backoffice), `types/api.ts` (frontend, backoffice), and recorded
  fixtures or goldens produced by a command rather than written by hand.
- **Commits.** One Conventional Commit per work unit on a `feature/*` branch (Git Flow), tests and docs alongside the
  behaviour, no AI attribution, never `--no-verify`. Push, PR and merge stay with the owner under ordinary repository policy.
- **Flag and darkness.** Every behaviour is behind `INTERVIEW_TAVUS_SINGLE_SESSION` (default `false`) or the canary list
  (`INTERVIEW_TAVUS_SINGLE_SESSION_PROJECTS`). The frontend acts only when a `/start` response contains `continuation`.
  The old one-conversation-per-competency path remains as the fallback.
- **api commands.** Pest by **exact file path**: `cd api && ./vendor/bin/pest <file>` (never `php artisan test --filter`).
  Then `./vendor/bin/pint --test` and `./vendor/bin/phpstan analyse --memory-limit=1G`. Full suite once per slice before
  its PR: `php artisan test --parallel` (never beside another Pest run: parallel runs share one test database).
- **frontend commands.** Bun only. Per file: `cd frontend && bun run test:unit -- <file>`. Before a PR: `bunx nuxi prepare`,
  `bun run typecheck`, `bun run lint`, `bun run test:unit:coverage`. Any user-visible string needs `it` and `en`
  (`i18n-interview-keys.spec.ts` stays green). Playwright only through `task e2e:frontend` (i.e.
  `bash scripts/e2e-container.sh frontend`), chromium and webkit, `--workers=1`.
- **TDD mode.** Strict TDD on; runners are Pest (api) and Vitest (frontend); Playwright for E2E.
- **Delegation route.** Each slice is delegated-direct work: one writer per slice, reading that prepares the write belongs
  to the writer. No SDD phase workers. Record the route per slice in the PR.
- **Review gate.** Where receipt-driven development is enabled by the owner, the native review candidate is a work-unit
  commit or a PR slice, never a checkbox and never the accumulated branch.

## Ordering and dependencies

```
PR0 (docs)
 └─ API-01 ─ API-02 ─ API-03 ─ API-04 ─ API-05 ─┬─ API-06 (may start after API-03)
                                                  └─ API-07 (needs API-03 and API-05)
 API-08 after API-01..07 (single OpenAPI sync + one wrapper bump)

 FE-01 ─ FE-02 ─ FE-03      (API-independent, may start immediately after PR0)
 FE-04 needs API-04, FE-02, FE-03
 FE-05 needs API-06, FE-04
 FE-06 needs API-05, FE-04
 FE-07 last (needs FE-04..06)
 FE-08 with API-08

 SPIKE-01 (live, separate explicit owner authorization) after FE-07, before any flag flip
```

- **F3 ordering.** `db-driven-conversation-prompts` (F3) also edits `SystemPromptComposer` (its PR 5 changes
  `compose()`'s signature to take a `PromptTemplateSet` first). **F3 merges first; API-02 rebases onto it.** If F3 has not
  merged when API-02 is ready, API-02 waits; it does not fork the composer. API-01 and everything not touching the
  composer may proceed regardless.
- **Plan correction.** The plan allowed API-06 and API-07 in parallel after API-03. API-07's "dispatch from the ceiling
  resume" classifies a resume with `ProviderRefLifetime`, so API-07 also needs API-05; the sibling guard, the `/end` and
  the reaper dispatches do not, but they ship in the same slice.
- **Cross-stack sync rule.** API slices commit their own regenerated `openapi.json` (generated, excluded from the budget).
  The wrapper pointer for `api` is NOT advanced between slices: advancing `api` alone turns the wrapper's parity gate red.
  API-08 performs the single sync to `frontend` and `backoffice` and ONE wrapper commit moving all three pointers.

## Offline versus live

Everything marked OFFLINE is provable with Pest, Vitest and Playwright route mocks, and is the merge gate. Everything marked
LIVE needs a real Tavus conversation, spends credits, and needs a **separate explicit owner authorization**; none of it is
assumed true, and no slice is blocked on it.

| Id | Claim (LIVE only) | Why offline cannot prove it |
|---|---|---|
| L1 | A browser can send `append_llm_context` / `respond` over the Daily data channel and Tavus accepts it | Needs a real room |
| L2 | After append the model still knows the earlier topic's codeword; after overwrite it does not | Model behaviour |
| L3 | After the end phrase plus an append, the avatar opens the next topic unprompted, or only after `respond` | Model behaviour |
| L4 | `respond` comes back as a role-`user` `conversation.utterance` (and with which `inference_id`) | Vendor behaviour |
| L5 | A realistic three-topic context obeys "do not begin a topic until told" (Q1 adaptivity A/B against the baseline) | Model behaviour |
| L6 | Real behaviour at `max_call_duration` and at the plan limit (which Daily event, when) | Vendor behaviour |
| L7 | `participant_left_timeout` 0 ends the conversation on browser leave, how fast, and the concurrency slot is freed | Vendor behaviour |
| L8 | `POST /conversations/{id}/end` on an already-ended conversation is benign | Vendor behaviour |

OFFLINE proofs: create-body golden, UUID-sentinel anti-leak, envelope golden, length/key-set tests, cursor-before-send order,
the attribution tape, fake-Daily send / no-ack / echo / `left-meeting` through the injectable `sdkLoader`, Playwright route
mocks, the grant/refusal matrix, ceiling arithmetic, and release-job semantics.

## PR0: this docs slice (wrapper)

- [x] PR0.1 `proposal.md` and `design.md` rescoped 2026-10-08 (Amendments A1-A13, N1-N11, status tags).
- [x] PR0.2 Spec deltas rewritten (`interview-session`, `interview-conversation`, `interview-frontend`).
- [x] PR0.3 `tasks.md` added (this file). Verification: the placeholder scan named in the PR0 brief finds nothing in the change folder.
  PR0 is ticked only because the three docs commits exist on `feature/tavus-single-session-sdd`; it is not a merge or review claim.

## API slices

### API-01: schema, config, gate (about 220 lines)

Depends on: PR0. Files: one migration, `config/interview.php`, `config/conversation.php`, `App\Support\Interview\SingleSessionGate`.

- [ ] API-01.1 RED `tests/Feature/Interview/OpenPeriodPerRefTest.php`: a second open period on the same non-null ref raises a
      unique violation; closed periods and null refs do not collide.
- [ ] API-01.2 RED `tests/Feature/Interview/ConversationPlanColumnTest.php`: `interview_sessions.conversation_plan` round-trips
      the documented JSON through the model cast and is null by default.
- [ ] API-01.3 RED `tests/Unit/Support/Interview/SingleSessionGateTest.php`: false by default; true for provider `tavus` when the
      flag is true; true for a project id in the canary list with the flag false; always false for `heygen`; false for `mock`.
- [ ] API-01.4 GREEN migration: nullable JSON `conversation_plan` and partial unique index on
      `interview_session_live_periods(provider_session_ref) WHERE provider_session_ref IS NOT NULL AND ended_at IS NULL`;
      `down()` drops both. Config: `interview.tavus.single_session` (env, default `false`),
      `interview.tavus.single_session_projects` (env list, default empty), `conversation.max_context_chars` (40000),
      `conversation.ceiling_headroom_seconds` (480), `conversation.boundary_grace_turns` (1). Add `SingleSessionGate`.
- [ ] API-01.5 Verify: the three test files green; migrate fresh and rollback on Postgres; Pint; PHPStan; the existing
      `SessionLivePeriodExitsTest` and `SessionLiveClockTest` still green.
- [ ] API-01.6 Commit: `feat(api): add the single-session schema, config and gate`.

### API-02: `composeMany` and `ConversationPlan` DTO (about 350 lines; pure, unwired)

Depends on: API-01, **F3 merged** (rebase onto it). Files: `SystemPromptComposer::composeMany`, `App\DTOs\Conversation\ConversationPlan`.

- [ ] API-02.1 RED `tests/Unit/Conversation/SystemPromptComposerManyTest.php`: byte-identical on repeat; exactly one `prompt_version`;
      global rules and `=== TOPIC CODE: X ===` markers; each segment holds only its own anchor sentinel; the last entry carries the
      final phrase; role-less `potential` entries compose; truncation to the longest prefix at `max_context_chars` (a test also
      records the measured length of one composed competency so the owner can retune the 40000 default); fewer than two entries
      is refused (the single path stays separate).
- [ ] API-02.2 GREEN `composeMany(list<ResolvedCompetencyInput>): ConversationPlan` as a pure assembler over already-resolved
      inputs; no DB, no LLM, no time.
- [ ] API-02.3 Verify: existing `tests/Unit/C8/SystemPromptComposerTest.php` and `SystemPromptComposerBudgetTest.php` (and F3's golden,
      if merged) stay byte-identical green; Pint; PHPStan.
- [ ] API-02.4 Commit: `feat(api): compose a multi-competency conversation context`.

### API-03: create path with a plan, flag-gated (about 400 lines)

Depends on: API-02. Files: `App\Actions\Interview\ComposeConversationPlan`, `InterviewController` wiring (thin), `BuildInterviewSessionResponse`,
`@scramble-return` at `:141`, new golden.

- [ ] API-03.1 RED `tests/Unit/Actions/Interview/ComposeConversationPlanTest.php`: resolves revision, role (null for `potential`), authored
      primaries, spoken opening and advance phrase per competency (not a plain map); a composition failure for any covered
      competency surfaces the existing 422 reasons.
- [ ] API-03.2 RED `tests/Feature/C8/TavusProviderPayloadTest.php` (new multi-context case) plus new
      `tests/Fixtures/Provider/tavus/conversations_request_multi_golden.json`; the old golden stays untouched for flag off.
- [ ] API-03.3 RED `tests/Feature/Interview/ConversationPlanCreateTest.php`: flag on persists `conversation_plan` on the creating row and
      returns `conversation_id`; flag off: response byte-identical, no column write; HeyGen and mock invariant; single remaining
      competency writes no plan.
- [ ] API-03.4 RED `tests/Feature/Interview/SingleSessionAntiLeakSentinelTest.php`: a UUID in `anchor_5` appears in none of the bodies of
      `/start`, `/utterance`, `/end`, `/integrity`, `/snapshot`, and DOES appear in the faked `/v2/conversations` request body;
      the stored plan holds no sentinel.
- [ ] API-03.5 GREEN `ComposeConversationPlan`, gate wiring in `start()`, persist the plan in the existing short transaction, return
      `conversation_id`, grow `@scramble-return`. The creating row also carries the usual snapshots.
- [ ] API-03.6 Verify: new tests plus `TavusProviderPayloadTest`, `ResumeTranscriptTest`, `ResumeHarvestTeardownRefTest`,
      `ResumeCompositionFailureTeardownTest`, `ProviderContractFixtureTest`; Pint; PHPStan; regenerate `api/openapi.json` on Postgres.
- [ ] API-03.7 Commit: `feat(api): create a multi-competency Tavus conversation behind the single-session flag`.

### API-04: continuation grant (about 400 lines)

Depends on: API-03. Files: `App\Actions\Interview\AdvanceOnLiveConversation`, `/start` optional input `live_conversation_id`, response `continuation`.

- [ ] API-04.1 RED `tests/Unit/Actions/Interview/AdvanceOnLiveConversationTest.php` and
      `tests/Feature/Interview/ContinuationGrantTest.php`: granted only for an owned ref whose plan covers the next code and whose next row
      is brand new; each of absent id, other participant, other organization, nulled ref (`/suspend`), code not in plan, `pending` row,
      re-offer, evaluation-retry reset, flag off falls to the issue path with an unchanged response shape.
- [ ] API-04.2 RED same file: `Http::assertNotSent` on `/v2/conversations`; the new row shares the ref, is `in_corso`, opens a live period,
      copies the LLM snapshot (`llm_binding_status` not null, cost row written when it ends) and takes `primary_questions` and
      `follow_up_budget` from the plan entry; a transaction failure does not leak the ref and returns the existing 500.
- [ ] API-04.3 RED `tests/Feature/Interview/SharedRefScoringParityTest.php`: scoring input for a shared-ref interview equals N separate-ref interviews.
- [ ] API-04.4 GREEN the action, validation of `live_conversation_id`, response `continuation`, `@scramble-return` growth. The grant is
      evaluated after `resolveNextCompetency` and before the single-competency composition, because a continuation composes nothing.
- [ ] API-04.5 Verify: new tests plus `InterviewabilityIngressRefusalTest`, `InFlightSessionSurvivesTest`; PHPStan; regenerate `openapi.json`.
- [ ] API-04.6 Commit: `feat(api): grant a continuation on a live Tavus conversation`.

### API-05: `ProviderRefLifetime` and ceiling refusal (about 250 lines)

Depends on: API-04. Files: `App\Support\Interview\ProviderRefLifetime`, `SessionLiveClock::resolveMaxSeconds` exposed, `/start` grant rule 5.

- [ ] API-05.1 RED `tests/Unit/Support/Interview/ProviderRefLifetimeTest.php`: age is the span from `min(started_at)` (not the sum); the template cap
      900 is honoured; without a template 3600 applies; near-ceiling is `age + headroom >= ceiling`; headroom from config.
- [ ] API-05.2 RED `ContinuationGrantTest` (extend): a continuation is refused near the ceiling and `issue()` runs; a fresh multi-plan response
      also carries `conversation_ttl_seconds` (see "Plan gap G1" below).
- [ ] API-05.3 GREEN the class, expose the template ceiling from `SessionLiveClock` (single owner of the resolution), wire the refusal and the
      `conversation_ttl_seconds` field, `@scramble-return`.
- [ ] API-05.4 Verify: `SessionLiveClockTest` (Tavus cap, line `192` area) green; PHPStan; regenerate `openapi.json`.
- [ ] API-05.5 Commit: `feat(api): derive the Tavus conversation ceiling from the template`.

### API-06: `boundary_due` on `/utterance` (about 250 lines)

Depends on: API-03 (may run in parallel with API-04/05). Files: `UtteranceController`, `@scramble-return` for the 202.

- [ ] API-06.1 RED `tests/Feature/Interview/BoundaryDueTest.php`: below, at and above `1 + follow_up_budget + grace` substantive candidate turns
      (6 at the default config); turns shorter than `nudge_min_chars` do not count; avatar turns do not count; the 202 and 409 contracts and
      the 404/422 paths are unchanged; the threshold uses the row's own `follow_up_budget` snapshot.
- [ ] API-06.2 GREEN the count and the 202 body inside the existing atomic insert flow; no extra round trip.
- [ ] API-06.3 Verify: `tests/Feature/C7a/UtteranceControllerTest.php` and the `TurnClassifier` tests green; Pint; PHPStan; regenerate `openapi.json`.
- [ ] API-06.4 Commit: `feat(api): report when a competency has met its turn budget`.

### API-07: `ReleaseProviderConversation` and the sibling guard (about 350 lines)

Depends on: API-03 and API-05. Files: `App\Jobs\ReleaseProviderConversation`, `handleResumeInCorso`, `end()`, `ReapStaleInterviews::endSession`.

- [ ] API-07.1 RED `tests/Feature/Interview/ReleaseProviderConversationTest.php`: scalar ids, `$tries`, `$timeout`, runs under `TenantContextScope::runFor`; a live
      sibling on the ref means no `POST /v2/conversations/{id}/end`; an already-ended conversation is benign; the queue arch tests
      `QueuedJobTenantContextArchTest` and `QueuedJobRetryOwnershipArchTest` stay green.
- [ ] API-07.2 RED `tests/Feature/Interview/SharedRefResumeGuardTest.php`: resume with a live sibling issues a fresh ref and skips teardown; an
      unshared ref still tears down (`ResumeTranscriptTest` green); the period is closed either way.
- [ ] API-07.3 RED dispatch tests: `afterCommit` with a delay from the ceiling resume (no inline `teardown()`), from `/end` when `next_action` is not
      `continue`, and from the reaper (`ReapStaleInterviewsTest` gains the assertion).
- [ ] API-07.4 GREEN the job, the guard, the three dispatch sites.
- [ ] API-07.5 Verify: new tests plus `ResumeTranscriptTest`, `ResumeHarvestTeardownRefTest`, `ReapStaleInterviewsTest`, `tests/Arch`; PHPStan.
- [ ] API-07.6 Commit: `feat(api): release superseded Tavus conversations and guard shared-ref resume`.

### API-08: OpenAPI sync (generated; not counted against the budget)

Depends on: API-01..07 merged in `api`. One sync, one wrapper bump.

- [ ] API-08.1 `DB_CONNECTION=pgsql` (verified with `php artisan config:show database.default`), then `task openapi:sync`.
- [ ] API-08.2 Confirm only the intended operations changed: `/start` response (`conversation_id`, `conversation_ttl_seconds`, `continuation`),
      `/start` request (`live_conversation_id`), `/utterance` 202 (`boundary_due`).
- [ ] API-08.3 Confirm `api/openapi.v1.json` (the public spec) is byte-identical after a fresh export.
- [ ] API-08.4 Commit the generated snapshots in `api`, `frontend` and `backoffice` (`chore(api): sync openapi.json and the typed client with the single-session contract`) and ONE wrapper
      commit moving the three pointers; `codegen:check` and `scripts/verify-openapi-parity.sh` pass in both Nuxt apps.

## Frontend slices

### FE-01: advance interaction template and code check (about 250 lines)

Depends on: PR0. Files: `app/utils/advance-interaction.ts`, `app/utils/competency-codes.ts`, `tests/fixtures/tavus/boundary_interaction_golden.json` (new directory).

- [ ] FE-01.1 RED `tests/unit/advance-interaction.spec.ts`: decoy `INNOVAZIONE`; the serialized length equals the fixed template plus the code length;
      stripping the template leaves exactly the code; exact key sets for the envelope and `properties`; the `respond` constant carries no code; the golden
      envelope matches; `@ts-expect-error` on `sendBoundary('Begin INN now.')` and on a hand-built ticket (compiled in the typecheck lane).
- [ ] FE-01.2 RED `tests/unit/competency-codes.spec.ts`: `asCompetencyCode` accepts `^[A-Z0-9_]{1,16}$`, rejects lowercase, empty, 17 characters, spaces and prose.
- [ ] FE-01.3 RED `tests/unit/arch/send-app-message-single-site.spec.ts`: `sendAppMessage` appears in exactly one source file and one call site; `overwrite_llm_context`
      appears nowhere in `app/`.
- [ ] FE-01.4 GREEN the template, `buildAdvancePayload(ticket)`, the branded `AdvanceTicket`, `asCompetencyCode`. The golden is the
      DOCUMENTED shape and stays provisional until SPIKE-01 (L1-L4) confirms or amends it; changing it afterwards is a deliberate, reviewed change.
- [ ] FE-01.5 Verify: unit tests, `bunx nuxi prepare`, `bun run typecheck`, `bun run lint`.
- [ ] FE-01.6 Commit: `feat(frontend): add the fixed Tavus boundary interaction`.

### FE-02: `TavusProvider.sendBoundary` (about 300 lines)

Depends on: FE-01. Files: `app/providers/tavus.ts`, `app/types/interview-provider.ts` (`SupportsContextSteering`, `canSteerContext`).

- [ ] FE-02.1 RED `tests/unit/tavus-provider-steering.spec.ts` with an injected fake Daily (`sdkLoader`): sends the `append_llm_context` envelope (and the fixed
      `respond` trigger) through `sendAppMessage(msg,'*')`; refuses when the call is not `joined-meeting` (no send); emits `steering_failed` when the send throws or
      on `left-meeting`/`error`; acknowledges on the first replica utterance; emits `steering_failed` after `STEERING_ACK_TIMEOUT_MS` (10 000 ms, fake timers);
      drops its own echoed `respond` text exactly once; leaves genuine candidate speech alone.
- [ ] FE-02.2 GREEN `sendBoundary(ticket)` as the only outbound call site, behind the narrow guard; HeyGen gets no stub (`canSteerContext(heygen) === false`).
- [ ] FE-02.3 Verify: existing Tavus provider and provider-anonymity suites green; typecheck; lint.
- [ ] FE-02.4 Commit: `feat(frontend): send the Tavus boundary interaction and acknowledge it`.

### FE-03: `AttributionCursor` refactor (about 350 lines)

Depends on: FE-02. Files: `useInterviewSession.ts`, `InterviewSession.vue`, a new cursor module. No behaviour change for HeyGen.

- [ ] FE-03.1 RED `tests/unit/use-interview-session-attribution.spec.ts`: the scripted tape `[u1(A), end, u2(window), u3(B)]` asserts the exact multiset of
      `(session_id, text)` pairs; `/end`, `/suspend`, `sessionId`, snapshot and integrity (including the resize flush) read the cursor; the cursor write
      precedes `sendBoundary`; unsent integrity events are flushed against the outgoing row before the cursor moves.
- [ ] FE-03.2 GREEN the cursor (single mutator mints the ticket); the transcript handler reads it at emit time; `handle.dbSessionId` stays the player key only;
      `InterviewSession.vue` timer reset and `ProctorOverlay :session-id` follow `sessionId`.
- [ ] FE-03.3 Verify: the entire HeyGen suites (`interview-handover.spec.ts`, `use-interview-session.spec.ts`) pass **unmodified**; typecheck; lint; coverage.
- [ ] FE-03.4 Commit: `refactor(frontend): route every session-id reader through an attribution cursor`.

### FE-04: continuation parsing and boundary flow (about 400 lines; split 04a/04b if over)

Depends on: API-04, FE-02, FE-03. Files: `useInterviewSession.ts`.

- [ ] FE-04.1 RED parse: `isValidStartResponse` accepts `continuation`/`conversation_id`, rejects a malformed continuation or one combined with a handle.
- [ ] FE-04.2 RED flow (`tests/unit/use-interview-session-continuation.spec.ts`): `createProvider` is called once across three competencies; `players.length <= 1`;
      `/start` carries `live_conversation_id` only while a handle is live and never after a reload, pause, tab-hidden, re-offer or `retry()`; a response with no
      `continuation` takes today's path; the `'boundary'` start target neither transitions to `connecting` nor publishes a handle.
- [ ] FE-04.3 RED `assertBoundary()`: idempotent, two racing inputs mint one ticket and one `/end`, a losing `409` is a no-op; inputs here are the end phrase and the
      300 s timer; mute before `/end`, unmute after the send; the Tavus `continue` directive is routed off `confirmDevices()` only when `continuation` came back.
- [ ] FE-04.4 GREEN the above. `steering_failed` handling per the spec (unmute, keep cursor, resend once if joined, else end the new competency as `timeout`).
- [ ] FE-04.5 Verify: HeyGen suites unmodified green; typecheck; lint; coverage.
- [ ] FE-04.6 Commit: `feat(frontend): continue a Tavus conversation across competencies`.

### FE-05: `boundary_due` consumption and paraphrase (about 200 lines)

Depends on: API-06, FE-04.

- [ ] FE-05.1 RED: `sendUtterance` parses the 202 body; `boundary_due: true` triggers `assertBoundary()`; a paraphrased closing line (no phrase match) still advances; the
      phrase and `boundary_due` firing together cause one boundary; a missing or malformed body is ignored (best-effort contract).
- [ ] FE-05.2 GREEN the third input.
- [ ] FE-05.3 Verify: unit suites; typecheck; lint.
- [ ] FE-05.4 Commit: `feat(frontend): advance on the server's boundary signal`.

### FE-06: ceiling handover (about 350 lines)

Depends on: API-05, FE-04.

- [ ] FE-06.1 RED: the crossfade predicate is "a fresh handle arrives while a live handle exists" (the `isHeyGen` gate at `useInterviewSession.ts:1124-1135` is removed);
      a Tavus fresh handle crossfades and arms the bound when published as incoming; HeyGen suites unmodified.
- [ ] FE-06.2 RED: a conversation-age timer armed from `conversation_ttl_seconds` minus `HANDOVER_LEAD_MS` (120 000 ms) calls `/start` on the `in_corso` row mid-competency; the
      question clock is preserved; the flag flipped off mid-interview results in a fresh `/start` and a crossfade.
- [ ] FE-06.3 GREEN the predicate, the timer and the resume call.
- [ ] FE-06.4 Verify: `interview-handover.spec.ts` and `use-interview-session.spec.ts` (C1 mid-crossfade race) unmodified green; typecheck; lint.
- [ ] FE-06.5 Commit: `feat(frontend): hand a Tavus conversation over at its ceiling`.

### FE-07: Playwright route-mocked flows (about 350 lines)

Depends on: FE-04, FE-05, FE-06. Files: `tests/e2e/interview-single-session.spec.ts`; a steering recorder added to the mock provider returned by `createProvider(name, true)` in `app/providers/factory.ts`.

- [ ] FE-07.1 RED then GREEN: a 3-competency Tavus flow with one fresh `/start` and two continuations (route mocks); a paraphrased closing line advances through
      `boundary_due`; reload mid-interview issues fresh; pause and resume issue fresh; the ceiling handover keeps the competency. Chromium and webkit, `--workers=1`, via `task e2e:frontend`.
- [ ] FE-07.2 Verify: the existing `interview-flow.spec.ts`, `interview-chrome.spec.ts` and `embed.spec.ts` stay green.
- [ ] FE-07.3 Commit: `test(frontend): cover the single-session Tavus flows end to end`.

### FE-08: generated client and drift check (generated; not counted against the budget)

Depends on: API-08.

- [ ] FE-08.1 `types/api.ts` regenerated in `frontend` and `backoffice`; `bun run codegen:check` passes in both; wrapper parity script passes.

## Live spike (separate authorization; NOT part of any merge gate)

### SPIKE-01: verify L1-L8 against a real Tavus conversation

Blocked until the owner explicitly authorizes the spend and the scope in writing. Nothing above depends on it; the flag stays off until it has run and the owner has
decided. Minimal script: extend `interview:smoke-check --provider=tavus` with `--multi` (a dummy two-topic context "TOPIC ALPHA codeword AMBER, TOPIC BRAVO codeword COBALT,
do not begin a topic until told by code"; prints the id and URL, ends it), plus `frontend/scripts/live/tavus-steering-verify.mjs` (headless chromium with a fake microphone
joining through the Daily call object, logging app-message events for 90 s: append then expect BRAVO; `respond` "what is codeword ALPHA?" then expect AMBER; overwrite as the
negative control; assert no user-role echo or record its shape; print timings). Mapping: L1-L4 confirm or amend the FE-01 golden and the `respond` trigger decision; L5 feeds the
Q1 decision; L6 re-derives `ceiling_headroom_seconds`, `HANDOVER_LEAD_MS` and `STEERING_ACK_TIMEOUT_MS`; L7 and L8 confirm the A5 and `ReleaseProviderConversation` assumptions.

- [ ] SPIKE-01.1 Owner authorization recorded (date, scope, budget).
- [ ] SPIKE-01.2 Script extension and live script committed (separate PR, excluded from CI).
- [ ] SPIKE-01.3 L1-L8 results recorded in this file with the date; the FE-01 golden confirmed or amended in a reviewed commit.

## Owner decisions at the flip (not code)

Q1 adaptivity threshold from L5; canary scope and default flag value; acceptance of the visible mid-competency reconnect (Q5); cost. Defaults and rationale are in the proposal.

## Plan gaps closed in this rescope

- **G1 - the client has no ceiling.** FE-06's age timer needs a duration, and the browser cannot derive the template-derived ceiling. Decision: the fresh multi-plan
  `/start` response also carries `conversation_ttl_seconds` (the ceiling in seconds, non-secret); the client fires its handover `HANDOVER_LEAD_MS` (120 000 ms) before it.
  Added to API-05 and FE-06; both numbers are retuned from L6.
- **G2 - API-07 dependency.** See "Ordering and dependencies".
- **G3 - the grant runs before composition.** A continuation composes no prompt, so a missing translation for an already-planned competency cannot turn a continuation into a 422.

## Rollback

- **Operational, no deploy:** `INTERVIEW_TAVUS_SINGLE_SESSION=false` and an empty canary list. The next `/start` ignores `live_conversation_id` and issues fresh; the frontend crossfades (FE-06).
- **Code:** revert in reverse slice order; each slice is independently revertible. Frontend slices are response-driven; API slices are additive.
- **Schema:** the only artefacts are the nullable `conversation_plan` column and one partial unique index; both are additive and dropped by `down()`. No backfill, no data migration.
