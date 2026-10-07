# Tasks: Scoring Retry (RT-B) — single re-interview of a `pending` evaluation

Inputs: `proposal.md`, `design.md`, `specs/*/spec.md` (9 deltas), owner resolutions R2, No-email-links,
Audit (AuditRecorder) and Route. Strict TDD: every behaviour is RED test first, then GREEN, then REFACTOR.
Test runners: api `php artisan test --compact <file>` (Pest) and serial CI-equivalent
`vendor/bin/pest --coverage --min=85`; also `vendor/bin/pint` and `vendor/bin/phpstan analyse --memory-limit=1G`;
backoffice `bun run vitest` + Playwright (Chromium + WebKit); frontend Vitest. OpenAPI export only against
Postgres (api `CLAUDE.md`). No deploy. SemVer bumps happen only at release branches, never in these slices.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~2,800 authored across 15 slices (generated `openapi.json` / `types/api.ts` excluded) |
| 400-line budget risk | High overall; Medium for PR1b, PR2a, PR3b (each 330-390); Low for the rest |
| Chained PRs recommended | Yes |
| Suggested split | PR0w -> PR0 -> PR0b -> PR1a -> PR1b -> PR2a -> PR2b -> PR2c -> PR3a -> PR3b -> PR4a -> PR4b -> PR4f -> PR5 |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

Deviations from the design's slice plan (all keep the design's order and dependencies):
- PR0b (new, backoffice, ~60): the entry-link disclosure fix (absolute expiry, no fixed duration). It must reach
  operators no later than the api release that carries PR0, otherwise the static "30 minutes" copy is false for
  emailed links. Fallback if the owner prefers fewer slices: fold into PR4a.
- PR1 is split as the design pre-planned (R1), because the owner-mandated `AuditRecorder` row adds ~35 lines:
  PR1a = foundations (migration, edge, DTOs, enums, matrix tests), PR1b = the action (+ arch test, audit).
- PR2c (new, api, ~120): the spec-mandated `reinterview` opening variant. The design's "no production code" claim
  (A10) is superseded by `specs/interview-conversation/spec.md`. Independent of PR1/PR2a/PR2b; must merge before PR3b.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Binding SSO rule amended + change specs reconciled | PR0w (wrapper) | `rg -n "15.60" CLAUDE.md docs/app_description/04-integration-surface/01-sso-ingress.md` returns no stale rule | N/A: docs only | revert the commit |
| 2 | Emailed links live 24 h, returned links stay 30 min | PR0 (api) | `php artisan test --compact tests/Feature/Sso/EmailedLinkTtlTest.php tests/Feature/C6/SsoLinkRegressionPinsTest.php` | `POST /api/entry-links` locally, decode the JWT `exp - iat` | revert; already-emailed 24 h tokens still exchange |
| 3 | Link disclosure shows absolute expiry | PR0b (backoffice) | `bun run vitest tests/unit/components/organisms/EntryLinkPanel.spec.ts` | Playwright `tests/e2e/entry-link.spec.ts` | revert; copy returns to fixed text |
| 4 | Foundations: migration, `completato -> in_attesa` edge, DTOs, refusal types | PR1a (api) | `php artisan test --compact --filter=ParticipantTransition` | `php artisan migrate` + `migrate:rollback --step=1` | revert + rollback migration (dark) |
| 5 | The authorization action with audit row | PR1b (api) | `php artisan test --compact tests/Feature/Participant/AuthorizeEvaluationRetryTest.php tests/Arch/RetryEdgeWriterArchTest.php` | N/A: no route yet; covered by feature tests | revert (dark) |
| 6 | Pipeline retry branch, forced completed, attempt-scoped finalize key | PR2a (api) | `php artisan test --compact tests/Feature/Jobs/ScoreEvaluationJobDefensiveBranchesTest.php tests/Feature/Retry/RetryScoringTest.php` | fake LLM provider end-to-end scoring test | see Rollback note: NOT while any participant is mid-retry |
| 7 | `failed()` finalization, dedupe keys, recovery guard exception | PR2b (api) | `php artisan test --compact tests/Feature/Retry tests/Feature/ParticipantRecovery/RecoverFailedParticipantTest.php` | two delivery rows asserted in DB | see Rollback note |
| 8 | `reinterview` opening variant | PR2c (api) | `php artisan test --compact tests/Unit/Services/Conversation/OpeningTextComposerTest.php --filter=reinterview` | candidate `/start` feature test | revert (dark: only reachable after a retry) |
| 9 | Retry email + admin read fields + exposure entries (still dark) | PR3a (api) | `php artisan test --compact tests/Feature/Retry/RetryEmailTest.php tests/Feature/PublicApi/Exposure/ExposureTest.php` | `Queue::fake` / `Notification::fake` rendered mail | revert (dark) |
| 10 | Two controllers, routes, policy, abilities (switches the feature on) | PR3b (api) | `php artisan test --compact tests/Feature/Retry/EvaluationRetryEndpointTest.php tests/Feature/Authorization` | SA-07 end-to-end feature test; Postgres OpenAPI export diff | revert PR3b = feature off |
| 11 | Backoffice composable + panel + i18n | PR4a (backoffice) | `bun run vitest tests/unit/components/organisms/EvaluationRetryPanel.spec.ts` | N/A: component unmounted until PR4b | revert (dark) |
| 12 | Page wiring + Playwright | PR4b (backoffice) | `bunx playwright test tests/e2e/participant-evaluation-retry.spec.ts` | Playwright Chromium + WebKit with mocked API | revert = panel hidden |
| 13 | Frontend regenerated client | PR4f (frontend) | `bun run vitest` + the openapi parity check | N/A: generated only | revert |
| 14 | Docs promotion, ruling 4, pins | PR5 (wrapper) | `rg -n "RATIFIED 2026-10-05" CLAUDE.md openspec/ROADMAP.md` | submodule pin check script / CI guard | revert the commit |

### Stacking and merge order (stacked-to-main, strictly sequential merges, four repos)

| Order | Slice | Repo / base | Blocked by | Authoring parallel with |
|---|---|---|---|---|
| 1 | PR0w | wrapper `develop` | none | PR0 (authoring only) |
| 2 | PR0 | api `develop` | PR0w merged (CLAUDE.md is binding) | PR0b |
| 3 | PR0b | backoffice `develop` | none technically; must release no later than the api release with PR0 | PR0 |
| 4 | PR1a | api | PR0 | PR2c |
| 5 | PR1b | api | PR1a | PR2c |
| 6 | PR2a | api | PR1b | PR2c |
| 7 | PR2b | api | PR2a | PR2c |
| 8 | PR2c | api | none technically (uses existing `evaluations.retry_attempt`); merge before PR3b | PR1a..PR2b |
| 9 | PR3a | api | PR1b, PR2b | PR2c |
| 10 | PR3b | api | PR2a, PR2b, PR2c, PR3a (all earlier slices are dark; this one switches it on) | none |
| 11 | PR4a | backoffice | PR3b merged to api `develop` (regenerate client from its `openapi.json`) | PR4f |
| 12 | PR4b | backoffice | PR4a | PR4f |
| 13 | PR4f | frontend | PR3b merged | PR4a, PR4b |
| 14 | PR5 | wrapper | api, backoffice, frontend release tags exist | none |

Api-first release order: the api release carrying PR3b bumps `openapi.json` `info.version`; backoffice and
frontend catch up in their own patch releases; the wrapper pins the released tags in PR5 (and never earlier).
Every api slice before PR3b is dark. No deploy is performed by any task.

## Consistency Report (spec vs design vs owner resolutions)

Each row lists a mismatch found while reading all three sources, the default the tasks below apply, and what must
be edited. None blocks apply; rows marked CONFIRM should be answered by the owner before the named slice.

| # | Item | Specs say | Design says | Default applied in these tasks | Action |
|---|---|---|---|---|---|
| I1 | Interim log line name | `participant.retry_authorized` | `evaluation.retry_authorized` | Log line = `participant.retry_authorized` (spec). Audit row action = `evaluation.retry_authorized`, subject `evaluation` (precedent `evaluation.audit_requested`, `EvaluationAuditController:124`) | Design text fixed in PR0w note; record both names in spec |
| I2 | Audit row | "interim log only, ratified audit log out of scope" (participant-sso interim logging, proposal A8) | Q1 open | Owner resolution wins: write an `AuditRecorder` row in the same transaction plus the log line | Amend spec requirement "Interim Retry Audit Logging" (PR0w) |
| I3 | Audit placement | n/a | n/a | Owner says same transaction. Sibling actions (`DuplicateAvatarTemplate`, `DisableReusableInterviewLink`, `CreateReusableInterviewLink`) record AFTER commit because `AuditRecorder` swallows exceptions and a Postgres error inside a transaction aborts it. CONFIRM before PR1b; default = inside the transaction as instructed, with a RED test that a refusal leaves zero audit rows and a success exactly one; note the abort risk in the action docblock | Owner confirm |
| I4 | Read-API shape | flat `retry_attempt`, `retry_authorized_at`, `retry_available` | nested `retry: {state, authorized_at}` | Specs win: three flat fields. Panel phase derived from literal `status` (spec table). `retry_available` additionally excludes test-mode participants (design `eligible` rule), because the action refuses them | Amend spec "retry_available" definition; ExposureCatalogue gets three entries, not two |
| I5 | Open competency/variant | `reinterview` opening variant requires production code | "no production code" (A10) | Spec wins: new PR2c | Design D-section A10 superseded |
| I6 | Finalize dedup | release `finalize:{pid}` after commit (spec requirement + 3 scenarios; proposal A13) | attempt-scoped key `finalize:{pid}:retry`, no cache write (D7) | Design wins (deterministic, transactional). Behavioural scenarios kept; the "released after commit / untouched on refusal" scenarios are rewritten as "key `finalize:{pid}` is not touched by the action" | Rewrite interview-session requirement and participant-sso scenario (PR0w) |
| I7 | Refusal reasons | 4 reasons (no `test_mode_participant`) in participant-sso, m2m-auth, admin-backoffice | 5 reasons; order consumed, not_completed, test_mode, not_pending, project_inaccessible | Design list and order, `retry_already_consumed` first. Backoffice i18n gets 5 keys | Add `test_mode_participant` to the three spec deltas (PR0w) |
| I8 | Response body | `{entry_url, expires_at, email_sent}` | adds `status`, `competencies_reset` | Superset: keep both extra fields (internal surface, Scramble-derived) | Note in spec |
| I9 | Retry link lifetime for placeholder / reusable-link visitor | retry link "always" 24 h, even when no email is sent (participant-sso scenarios) | Emailed only for deliverable; minter downgrades visitors to 30 min (D1, D4) | CONFIRM before PR1b. Owner resolution says placeholder / visitor stay 30 min for operator mints with no email and lists "retry link" as 24 h. Default = spec (retry always 24 h): the action requests `Emailed`; the minter's visitor downgrade must therefore not apply to the retry call (add an explicit parameter or let the retry action bypass it). A RED test pins whichever is confirmed | Owner confirm; align spec or design |
| I10 | Job flag source | guard uses job payload `retry_attempt`; `failed()` branches on payload | DB row is authoritative (D8 table) | Design table (DB authoritative, payload only a hint) because crash-resumed jobs carry no reliable flag; spec scenarios stay valid | Adjust spec wording "retry_attempt is read from the JOB PAYLOAD" (PR0w) |
| I11 | Route / names | `/api/participants/{id}/retry`, `/api/m2m/participants/{id}/retry`; HTTP 200; reasons as listed; `reinterview`; flat read fields | design already corrected | Consistent; no residual mismatch found beyond I1-I10 | none |
| I12 | `resume` vs `reinterview` | silent on a retry-reset session resumed mid-conversation | n/a | `resume` keeps priority (provider session re-issue) over `reinterview`; `retry` (provider-error re-offer) beats `reinterview` per spec | Add one scenario in PR2c |

### PR0 reconciliation notes (recorded during apply, 2026-10-05)

PR0-relevant rows of the Consistency Report: none of I1-I8, I10-I12 touch PR0. I9 (retry link lifetime for a
placeholder or visitor target) is for PR1b only; PR0 lands the seam it needs: `LinkDelivery` is chosen by the caller
and `EntryLinkMinter` currently downgrades `Emailed` to `Returned` for a reusable-link visitor target. If I9 is
confirmed as "spec wins" (retry always 24 h), PR1b must add an explicit bypass of that downgrade for the retry call.
Residual items found while applying PR0 (follow tasks.md, spec/design not edited):
- R1. Task 2.1 lists "reusable redemption = 30". A reusable-link redemption mints a candidate JWT (typ `candidate`,
  120 min), never an sso-link, so there is no 30-minute link to assert. The test pins the real behaviour instead:
  no sso-link, candidate credential keeps its 120-minute lifetime.
- R2. Task 2.4 asks for the expiry label "in `CandidateInvitationNotification`". The notification receives the label as
  a scalar built by the dispatcher, so the test asserts the `SendCandidateInvitationJob` argument against the token
  `exp` for both dispatchers (operator mint, scheduled sweep).
- R3. The spec scenario "scheduled-start link ... queues the invitation email" holds for the sweep, which mails
  unconditionally (pre-existing). For a sweep row that is a reusable-link visitor the minter downgrades to 30 min while
  the sweep still mails the link; for a placeholder address the job refuses to send. Neither is reachable through the
  scheduling paths today (visitors are never scheduled); left unchanged and recorded here.
- R4. Not in design: `CandidateTokenFactory::mintSsoLink` restores the shared JWT factory TTL after minting. The factory
  is a container singleton and `setTTL()` is sticky, so a 24 h mint would otherwise become the lifetime of every later
  token minted without its own `setTTL()` in the same long-lived worker (user access tokens). Covered by a RED test.
- R5. `phpstan analyse` reported 0 errors on the PR0 branch, not the two known pre-existing errors; the baseline of
  that gate may have moved since this file was written.

### PR1b reconciliation notes (recorded during apply, 2026-10-05)

- I3 RESOLVED by the owner: the `AuditRecorder` row AND the `participant.retry_authorized` log line are written AFTER the transaction commits (like `DuplicateAvatarTemplate`, `DisableReusableInterviewLink`), not inside it. The spec scenario "WHEN the transaction commits THEN a line is emitted" already matches.
- I9 RESOLVED by the owner, overriding the specs: the retry link lives 24 h ONLY when BEAI emails it (real address, not a reusable-link visitor); a placeholder or purged address and a visitor get a returned-only link of 30 min. Specs to patch in PR0w: `specs/participant-sso/spec.md` (intro item 2 "RT-B retry link"; requirement "Emailed Invitation Links Live 24 Hours" item 2 and its exemption list; requirement "Evaluation Retry Authorization Action" ("mint a fresh single-use link with the 24-hour ... (always, whether or not an email is sent)"); scenario "Placeholder address gets no email but the link is returned" (lifetime becomes 30 minutes); scenario "Reusable-link visitor gets no email" (add 30 minutes)) and `specs/m2m-auth/spec.md:70` ("the 24-hour retry link").
- The spec also says the link is minted "after the transaction commits"; the design and these tasks mint it INSIDE the transaction (so a gate refusal rolls back). Followed tasks/design.
- The action only checks the placeholder address itself; the visitor downgrade has one owner, `EntryLinkMinter`. `emailSent` is false until PR3a queues the mail, so until then a deliverable address receives a 24 h link that is only returned. Dark slice, no route reaches it.
- `RetryActor::user(null)` stays constructible (PR1a test pins it) but the action refuses it with `InvalidArgumentException` before any write, so no audit row can exist without an authorizer.
- No two-process lock-contention test (5.6): the sequential second call plus a `FOR UPDATE` statement assertion stand in for it.
### PR2a reconciliation notes (recorded during apply, 2026-10-05)

- Followed tasks/design over the specs where they differ: the retry flag is read from the evaluation ROW (I10); the spec text "retry_attempt is read from the JOB PAYLOAD" and the payload-based guard rows in `specs/scoring-engine/spec.md` stay to be reworded in PR0w (1.3).
- Owner resolutions applied: pending evaluation stays unreadable during a retry (no read-gate change); the retry outcome is always definitive `completed`.
- Not re-stamped: the merge does not refresh `model_version` / `prompt_version` / `framework_version_id` on the Evaluation (design D8 and task 6.2 list only delete + status flip; the spec line "UPDATES ... (status, evaluated_at, versioning)" is broader). A retry scored after a prompt/model bump therefore keeps the first run's versions. Needs an owner call before PR3b.
- The new arch allowlist entry for `Listeners/DispatchScoringJob.php` in `AdminTenancySafetyArchTest` was needed (the listener strips the `tenant` scope with an explicit organization filter, as design D8 prescribes); `FinalizeInterview` lives under `Jobs/`, which is not a guarded root.
- PR2b pick-up: four `todo()` tests at the end of `api/tests/Feature/Retry/RetryScoringTest.php` (failed()/unresolvable finalization, `:retry` evaluation key, `:retry` progress keys, recovery guard). `failed()`, `endParticipantUnresolvable()`, `SendEvaluationWebhook`, `SendProgressWebhook` and `RecoverFailedParticipant` are untouched in PR2a.
- Size: the slice is ~1,010 authored lines (production ~210, tests ~800); no further split point exists in design/tasks. The natural cut, if wanted, is finalize key + dispatch (commit da5ed59) versus Resolve + job (c7163ee, ea72169).

### PR2b reconciliation notes (recorded during apply, 2026-10-05)

- Dedupe facts verified against code, all as the design states: `SendEvaluationWebhook::handleCompleted()` keyed on `(string) $evaluation->id`; unique index `webhook_deliveries_org_project_event_dedupe_unique (organization_id, project_id, event_type, dedupe_key)` in migration `2026_07_27_000001` (:102-105); `WebhookDeliveryRecorder` catches `UniqueConstraintViolationException` inside a savepoint and returns the existing row, discarding the loser's payload. No migration was needed. Nothing the design got wrong; one omission: `SendEvaluationWebhook::handleFailed()` still keys on the bare evaluation id, which is safe only because a retry can no longer reach `EvaluationFailed` (D10).
- Deviation from D10: the terminal resolution (`ResolveEvaluationTerminalState::resolve()`) in `finalizeRetryWithRetainedResults()` runs inside one `DB::transaction()`. Without it, a throw between the evaluation UPDATE and the participant save would leave `completed + retry_attempt` with the participant still `in_valutazione`, which the A6 no-op can never repair. Covered by a RED test (a throwing `EvaluationCompleted` listener leaves participant `in_valutazione` and evaluation `processing`).
- Design gap closed: `failed()` for a pending retry whose participant is not `in_valutazione` (stray job) is a logged no-op rather than a merge/finalize, so the single retry is not burned. The spec text only says the participant transition is "skipped" in that case; the tasks/design do not discuss it.
- `endParticipantUnresolvable()` and `failed()` share the helper; EvaluationCompleted is emitted inside the transaction, and `DeliverWebhookJob` is dispatched `afterCommit()` by the listener, so a rolled-back finalization delivers nothing.
- gga flagged the PR2a `mergeRetryResults()` participant read (id only): fixed by adding the `organization_id` filter from the locked evaluation row. `Participant` has no `tenant` scope, so `withoutGlobalScope('tenant')` there is a no-op kept for convention; the organization filter is what scopes the read.
- Tasks 7.1-7.3 name the `todo()` tests of PR2a; the recovery one moved to `RecoverFailedParticipantTest.php` as task 7.3 prescribes, the two webhook ones are real tests in `RetryScoringTest.php`.
- Size: ~600 authored lines (production ~150, tests ~430). Over ~400; neither design nor tasks define a split point for PR2b. Natural cuts are the three commits: failed() finalization / webhook keys / recovery guard.

### PR3a reconciliation notes (recorded during apply, 2026-10-05)

- Followed the specs over design D14: three flat fields (I4), not a nested `retry` block; `retry_available` also excludes test-mode participants. Three exclusion entries, not two.
- Task (c) of the run brief, "a retry-reset competency opens neutrally", was already delivered by PR2c (`ReinterviewOpeningTest`, `reinterview` variant); nothing was added here.
- Added a third lang key, `candidate_invitation.retry.expiry`, beyond the two tasks 9.4/9.5 list: the spec says the email states the link is single-use and shows its absolute expiry; the shared `expiry` line only says "personal". Subject, intro and expiry are the only lines that differ from the first invitation.
- The retry email is queued by `AuthorizeEvaluationRetry` itself (`DB::afterCommit`), not by the controllers, so both PR3b surfaces get it for free. `RetryAuthorization::emailSent` and the log line's `email_queued` now report the real decision; the PR1b log assertion moved from `false` to `true` and that test file now fakes the queue.
- Fixed in passing (gga finding on code PR3a touches): `SendCandidateInvitationJob::handle()` cleared `EmailBranding` only on success; a failed send left the previous tenant's colour/name/logo on the worker. `try/finally`, RED test first.
- The retry link is never logged: it is passed to the job as a scalar, and neither the action nor the job logs it.
- Characterization tests that cannot be mutation-killed meaningfully: "a refused authorization queues nothing", "a gate refusal after the flip queues nothing" (the queue registration comes after every refusal point, so only a future reordering would break them) and "not a C12 notification" (nothing in the slice writes `notification_logs`).

### PR3b reconciliation notes (recorded during apply, 2026-10-06)

- Defect found and fixed (PR1b assumption was wrong): `AuditRecorder` took `actor_id` from `Auth::user()`, which on `auth:api-m2m` is the authenticated ApiClient, so the M2M audit row hit the `audit_logs_actor_id_foreign` violation (row lost, swallowed) or could name an unrelated user with the same id. PR1b only tested the action directly, where nobody is authenticated. Fix: only a `User` is recorded as actor (own commit and test `tests/Feature/Audit/AuditRecorderActorTest.php`). The M2M actor travels in the payload, as PR1b designed.
- `reason`: `nullable|string|max:500` on both surfaces (the specs' bound); trimming is the framework's global `TrimStrings`/`ConvertEmptyStringsToNull`, pinned by a test (audit `reason` is `customer asked`, not padded; absent is `null`).
- A caller with no organization in scope (a superadmin not acting for one) gets 404 from the operator controller (`abort_if`), matching the catalogue `bare: NOT_FOUND`; the `(int)` cast of a null org was a latent org 0.
- Response `status` returns the action's value (a literal `in_attesa` in a controller is a write to the arch guard `RetryEdgeWriterArchTest`). Scramble cannot read DTO property types, so `email_sent` and `competencies_reset` carry key-level `@var` annotations (otherwise the export types them `string`, which would poison the generated TS client in PR4a).
- Exposure: the retry routes are internal (`/api/participants`, `/api/m2m`); `ExposureTest` passes with no catalogue entry, as `specs/m2m-auth` requires. The M2M route IS in the internal `openapi.json` like every other `/api/m2m` route, and absent from `openapi.v1.json` and `public-api/openapi.yaml` (untouched).
- `AdminReadRouteSurfaceTest` enumerates every `api/participants*` URI and gained `api/participants/{id}/retry`.
- Operator-vs-M2M "race": covered as sequential calls in all four surface orders (one 200, one 409 `retry_already_consumed`, one audit row); the single `FOR UPDATE` serialization is PR1b's. No two-process test.
- Size: ~1,005 authored lines excluding the 217-line generated `openapi.json` (production ~190, tests ~800); over ~400, no size:exception requested; natural cuts are the commits: audit fix / policy+abilities / endpoints+matrix+e2e.


### Batch 13 notes: wrapper documentation slice (recorded during apply, 2026-10-06)

- Spec-vs-reality reconciliation applied to the nine deltas and `design.md`, each statement read against api `origin/develop` (worktree `api-retry`, f972484): retry link 24 h only when BEAI emails it and 30 min when only returned (I9); participant row locked before the Evaluation row, in the action and in the job's merge; row-authoritative retry flag, payload only a hint (I10); link minted inside the transaction, email via `DB::afterCommit`, interim log line and `AuditRecorder` row `evaluation.retry_authorized` written AFTER commit and swallowed on failure (I1-I3); flat `retry_attempt` / `retry_authorized_at` / `retry_available` with test mode excluded (I4); five refusal reasons with `retry_already_consumed` first and `test_mode_participant` third (I7); response adds `status` and `competencies_reset` (I8); attempt-scoped finalize key `finalize:{pid}:retry` and the interview-session requirement renamed accordingly (I6); `:retry` webhook dedupe keys; the merge re-stamps `model_version` and `prompt_version` (framework version stays pinned), resolving the PR2a open question; `reinterview` opening variant with precedence resume > retry > reinterview > first > next (I5, I12); `AuditRecorder` records only a `User` as actor, the M2M client travels in the payload; `/api/participants/{id}/retry` on both surfaces and the M2M 403 documented; "single transaction" relaxed. `design.md` keeps its planned text, with the superseded A10 paragraph, D4, D8, D14 and D15 patched in place, the open questions Q1-Q3 closed and a "Reconciliation As Built" table appended.
- Not confirmable against merged code: the backoffice page wiring (PR4b) is on remote branch `feature/retry-pr4b-page-wiring`, not yet on backoffice `origin/develop` at the time of writing, so the panel and page statements follow the PR4a/PR4b notes of this file and the PR4a code on develop (five refusal keys, `canRetry` input, absence of a re-issue control in the retry link view); the `hideGenerate` behaviour was not re-read in the merged page.
- Task 1.2 (`docs/app_description/04-integration-surface/01-sso-ingress.md`) already carries the two lifetimes on `develop` (PR0w, #72, line 39); the "expiry is read from the token's own `exp`" half was not found there and is left to the orchestrator to confirm or add.
- Live specs that still contradict the shipped behaviour and are left to the archive phase (14.4 and the archive-time list above, NOT edited here): `openspec/specs/notifications/spec.md:10-11` (Purpose) and `:293` (Non-Goals bullet); `openspec/specs/interview-conversation/spec.md:38` (Non-Goals "Domain retry (RT-B)"); `openspec/specs/scoring-engine/spec.md` (Delivery Status DEFERRED paragraph, the old RT-B requirement and RT-B-O1/O2/O3, the `:63-64` payload note); `openspec/specs/participant-sso/spec.md:156,1402,1644` (the "30-minute TTL" wordings are true only for returned links); `openspec/specs/reusable-interview-links/spec.md:9,1810,1820` stays true (returned links stay 30 min).

### Batch 11 follow-up notes (recorded during apply, 2026-10-06)

- api commit d277625 (branch `feature/retry-followups-403-doc-and-potential-e2e`): `POST /api/m2m/participants/{id}/retry` now documents 403 through `@throws AuthorizationException` on `store()`, the same mechanism as `PlatformAvatarTemplateController`. Exported `openapi.json` (Postgres, `APP_NAME=BEAI`, `APP_URL=http://localhost`) differs from develop by exactly the new `403 -> #/components/responses/AuthorizationException`. Guard: `tests/Feature/OpenApi/M2mRetryDocumentsForbiddenTest.php` (RED before the fix). The other ability-gated M2M operations (`participants:create|read|schedule`) still list no 403; a generic route-to-spec guard would fail on them, so it was not added (out of this slice).
- Potential below-gate retry end to end: see `potential-assessment-interview` task 5.3.

## Phase 1: PR0w — wrapper docs and change-spec reconciliation (wrapper, ~70 lines)

- [x] 1.1 Edit `CLAUDE.md` (wrapper): amend the SSO ingress bullet to "non-forgeable signed single-use token; links returned to a caller expire in 30 min; links BEAI emails (initial invitation, scheduled sweep, retry) are config-driven, default 24 h". `AGENTS.md` is a symlink, do not edit it. Verify: `rg -n "15.60" CLAUDE.md` shows no stale rule.
- [ ] 1.2 Edit `docs/app_description/04-integration-surface/01-sso-ingress.md` (line ~39 "15-60 minutes"): same amendment, state the two lifetimes and that expiry is read from the token's own `exp`.
- [x] 1.3 (done in batch 13, see the batch 13 notes: every reconciliation of I1-I10 and of the PR0..PR4b notes applied to the nine deltas and design.md, each statement confirmed against api `origin/develop` f972484/63e1f3f) Reconcile the change specs per the Consistency Report: edit `openspec/changes/scoring-retry-rt-b/specs/participant-sso/spec.md` (I1 log name+audit row I2, I6 finalize scenarios, I7 add `test_mode_participant` to guards/order, I9 once confirmed), `specs/m2m-auth/spec.md` and `specs/admin-backoffice/spec.md` (I7 reason list), `specs/interview-session/spec.md` (I6 requirement rewritten to attempt-scoped key), `specs/admin-read-api/spec.md` (I4 `retry_available` excludes test mode), `specs/scoring-engine/spec.md` (I10 flag source wording). Verify by re-reading: each reason list has five entries in the design order.
- [x] 1.4 (done in batch 13: the deletion-at-authorization sentence added to `specs/scoring-engine/spec.md` and `specs/admin-read-api/spec.md`; the 30-minute no-email rule confirmed and extended to the retry link in `specs/participant-sso/spec.md`) Record the owner resolutions as spec text: R2 (evaluation unreadable during retry, reset competencies' answers deleted at authorization) in `specs/scoring-engine/spec.md` and `specs/admin-read-api/spec.md` (already stated; confirm wording, add the deletion-at-authorization sentence); no-email links stay 30 min in `specs/participant-sso/spec.md` (already present; confirm).

## Phase 2: PR0 — emailed links live 24 h (api, ~290 lines)

RED
- [x] 2.1 RED: create `api/tests/Feature/Sso/EmailedLinkTtlTest.php`. Cases (decode the JWT, assert `exp - iat` and response `expires_at == exp`): operator `POST /api/entry-links` emailed = 1440 min and `email_sent=true`; `send_email=false` = 30 and `email_sent=false`; placeholder address = 30 and `email_sent=false`; reusable-link-visitor target = 30; scheduled sweep (`DispatchScheduledInterviewInvitations`) = 1440; M2M `POST /api/m2m/sso-link` = 30 with byte-identical response; reusable redemption = 30; config 720 gives 720. Spec: participant-sso "Emailed Invitation Links Live 24 Hours".
- [x] 2.2 RED: in the same file add config-range tests: `candidate_invitations.emailed_link_ttl_minutes` of 14, 10081 and a non-integer throws `RuntimeException` at mint time (refused, not clamped), mirroring `ReapStaleInterviews:56-71`.
- [x] 2.3 RED: exchange boundary tests: an emailed link exchanges at TTL minus 1 min (`travel`), is refused 401 at TTL plus 1 min with the participant untouched, and a second exchange within lifetime is 401; assert the consumed-jti record lives at least until `exp` (`SsoExchangeController:213-219`).
- [x] 2.4 RED: notification test that the expiry label in `CandidateInvitationNotification` equals the token `exp` (locate the existing notification test with `fd -t f Invitation tests`).
- [x] 2.5 Verify (read-only, no change): `api/tests/Feature/C6/SsoLinkRegressionPinsTest.php` still pins `SSO_LINK_TTL_MINUTES = 30` and passes.

GREEN
- [x] 2.6 Create `api/config/candidate_invitations.php` (`emailed_link_ttl_minutes`, env `CANDIDATE_INVITATION_LINK_TTL_MINUTES`, default 1440, documented range [15, 10080]) and add the variable to `api/.env.example`.
- [x] 2.7 Create `api/app/Support/Sso/LinkDelivery.php` (`Returned|Emailed` string-backed enum).
- [x] 2.8 Modify `api/app/Support/Jwt/CandidateTokenFactory.php`: `mintSsoLink(array $claims, int $ttlMinutes = self::SSO_LINK_TTL_MINUTES)`; the constant stays 30.
- [x] 2.9 Modify `api/app/Support/Sso/EntryLinkMinter.php` and `api/app/Support/Sso/MintedEntryLink.php`: trailing `LinkDelivery $delivery = LinkDelivery::Returned`, downgrade `Emailed` to `Returned` for reusable-link visitors (existing `$targetsReusableLinkVisitor`), range check via `config()->integer()`, expose effective channel on `MintedEntryLink::$delivery`; `expires_at` still read back from the token `exp`. Keep a seam for the retry action to request 24 h for a visitor/placeholder target if I9 is confirmed as "spec wins".
- [x] 2.10 Modify `api/app/Http/Controllers/Api/EntryLinkController.php`: pass `Emailed` iff `send_email && ! PlaceholderEmail::is()`; derive `email_sent` from `$minted->delivery === LinkDelivery::Emailed` (replace the inline condition near `:278`).
- [x] 2.11 Modify `api/app/Console/Commands/DispatchScheduledInterviewInvitations.php` (near `:359`): pass `Emailed`.
- [x] 2.12 Modify `api/app/Notifications/CandidateInterviewNoticeNotification.php`: docblock states 24 h, not 30 min.

REFACTOR / verify
- [x] 2.13 Run `vendor/bin/pint`, `vendor/bin/phpstan analyse --memory-limit=1G`, the focused tests of 2.1-2.5 and the existing C6/entry-link suites; if any Scramble docblock changed, re-export `openapi.json` against Postgres and confirm the diff is empty or generated-only.

## Phase 3: PR0b — link disclosure shows the absolute expiry (backoffice, ~60 lines)

- [x] 3.1 RED: extend `backoffice/tests/unit/components/organisms/EntryLinkPanel.spec.ts`: single-use disclosure renders the absolute expiry from `expires_at` and its text contains no "30" or "24" duration, for `email_sent` true (24 h away) and false (30 min away), locales `it` and `en` (spec admin-backoffice "Link Disclosure Never Hard-Codes A Lifetime").
- [x] 3.2 RED: adjust `backoffice/tests/unit/reusable-link-i18n.spec.ts` (line ~104 asserts `entryLink.disclosure` mentions single-use / monouso): keep that, add the "no fixed duration" assertion; the reusable variant is untouched.
- [x] 3.3 GREEN (deviation: no interpolation; the existing "Expires:" line already renders expires_at, the disclosure now says "at the moment shown below"): modify `backoffice/i18n/locales/en.json` and `backoffice/i18n/locales/it.json` key `entryLink.disclosure` (currently "expires in 30 minutes"/"scade tra 30 minuti") to an interpolated absolute expiry, same meaning in both languages.
- [x] 3.4 GREEN (no change needed: the panel already renders expires_at via FormattedDate in entry-link-expiry; originally: modify `backoffice/app/components/organisms/EntryLinkPanel.vue` to pass the formatted `expires_at` (reuse the existing date formatter) into the disclosure; the single-use panel structure is unchanged).
- [x] 3.5 Update `backoffice/tests/e2e/entry-link.spec.ts` disclosure assertions (two tests at `:51` and `:86`) to the new copy; run Chromium + WebKit.

## Phase 4: PR1a — foundations (api, ~200 lines)

RED
- [x] 4.1 RED: create `api/tests/Unit/Participant/ParticipantRetryTransitionTest.php`: dataset over the full from/to status matrix: `completato -> in_attesa` allowed; `completato -> {in_corso, in_valutazione, errore}` throw `ParticipantTransitionException`; every pre-existing edge unchanged; `errore -> in_attesa` still allowed. Spec: interview-session FIX-5 (amended) and participant-sso Lifecycle Guard.
- [x] 4.2 RED (observed: NO existing test asserted the empty `completato` set, so none failed; only the wording of `ParticipantTransitionsC7aTest` was updated, and `tests/Feature/Participant/CompletatoRetryEdgeAuditTest.php` was added to cover the D3 sites the edge touches: entry-link minter, candidate status guard, evaluation read gate, evaluations index): update any existing test that asserts `completato` is terminal with an empty allowed set.
- [x] 4.3 RED: migration test (feature): `evaluations.retry_authorized_at` exists, nullable timestamp, `Evaluation` casts it to `datetime`, migrate down removes it.
- [x] 4.4 RED: unit test for `EvaluationRetryRefusalReason` machine values (`retry_already_consumed`, `not_completed`, `test_mode_participant`, `evaluation_not_pending`, `project_inaccessible`), `EvaluationRetryRefused` carrying a reason, and `RetryActor::user()/apiClient()` shapes.

GREEN
- [x] 4.5 Create `api/database/migrations/2026_10_05_100000_add_retry_authorized_at_to_evaluations_table.php` (nullable `retry_authorized_at` timestamp, reversible). No other migration: `retry_attempt` already exists, and the `webhook_deliveries` unique index needs no change because `:retry` keys are distinct values.
- [x] 4.6 (cast is `immutable_datetime`, matching `evaluated_at`) Modify `api/app/Models/Evaluation.php`: fillable and `datetime` cast for `retry_authorized_at`.
- [x] 4.7 Modify `api/app/Models/Participant.php` (`$allowedTransitions`, near `:165`): `completato => ['in_attesa']`, docblock names the single writer, mirroring the `errore` entry.
- [x] 4.8 Create `api/app/Exceptions/Participant/EvaluationRetryRefusalReason.php`, `api/app/Exceptions/Participant/EvaluationRetryRefused.php`, `api/app/Actions/Participant/RetryActor.php`, `api/app/Actions/Participant/RetryAuthorization.php` (shapes per design Interfaces; `RetryAuthorization` carries `status, entryUrl, expiresAt, emailSent, competenciesReset`).
- [x] 4.9 Verify (pint 0, phpstan 0 errors, tests 4.1-4.4 + audit green, migrate/rollback/migrate on a throwaway Postgres DB OK, OpenAPI export diff empty, full suite 8011 tests / coverage 95.7% / exit 0): pint, phpstan, tests 4.1-4.4, plus `php artisan migrate:rollback --step=1` then `migrate` against Postgres.

## Phase 5: PR1b — the authorization action (api, ~290 lines)

RED (all in `api/tests/Feature/Participant/AuthorizeEvaluationRetryTest.php` unless noted; factories only)
- [x] 5.1 RED happy path: participant `completato`, Evaluation `pending`, 2 invalid + 8 valid competencies, accessible project: participant becomes `in_attesa`; only the 2 invalid sessions are `pending` with `provider_session_ref`, `ended_reason`, `ended_at` cleared and utterances deleted; valid sessions, their utterances and all `CompetencyResult` rows are untouched (answers of reset competencies deleted at authorization, owner R2); `retry_attempt=true`, `retry_authorized_at` set; link minted from row values (no request input); DTO carries `competenciesReset`.
- [x] 5.2 RED refusals, one test per reason with "nothing modified" assertions: `retry_already_consumed`, `not_completed` (datasets `in_attesa|in_corso|in_valutazione|errore`), `test_mode_participant`, `evaluation_not_pending` (completed evaluation, and no evaluation row), `project_inaccessible` (closed, not-yet-live, past deadline, soft-deleted).
- [x] 5.3 RED order: participant that is both `retry_attempt=true` and not `completato` returns `retry_already_consumed`; `test_mode_participant` is evaluated before `evaluation_not_pending`.
- [x] 5.4 RED atomicity: `project_inaccessible` raised by the mint after the flip rolls back everything (status still `completato`, flag false, sessions intact, zero audit rows). (observed: the clock is moved past the project deadline right after the participant flip so the mint refuses on its own; the mint's Gates refusal is mapped to `project_inaccessible`)
- [x] 5.5 RED tenancy: id of another organization throws `ModelNotFoundException` with no write; sessions/results reads happen under `TenantContextScope::runFor`.
- [x] 5.6 RED concurrency: second authorization after the first commit gets `retry_already_consumed` and mints no second link; add a two-connection lock-contention test if the suite supports it. (observed: sequential second authorization refused with nothing written, plus a FOR UPDATE statement assertion; NO two-process lock-contention test, the suite helper needs committed rows and a separate OS process, not worth it for a one-line `lockForUpdate` already pinned by mutation)
- [x] 5.7 RED log line: `Log::spy()` asserts `participant.retry_authorized` with actor type/ids, participant, organization, project, previous/new status, reason (nullable, max 500), reset codes, email-queued flag, ISO-8601 timestamp, and NO email, display name, `candidate_ref`, link or token; labelled INTERIM like `participant.recovered`; no line on refusal.
- [x] 5.8 RED audit row (owner resolution): exactly one `audit_logs` row on success with action `evaluation.retry_authorized`, subject `evaluation` + evaluation id, `after` = participant id, evaluation id, reset codes, reason, actor kind and id (M2M actor has `actor_id` null because `AuditRecorder` reads `Auth::user()`, so the client id goes in `after`), no PII, no link; none on refusal; none when the transaction rolls back (see I3). (observed; owner resolution: written AFTER commit, not inside the transaction, overriding I3; test asserts the INSERT runs at the base transaction level)
- [x] 5.9 RED arch: create `api/tests/Arch/RetryEdgeWriterArchTest.php`: the `completato -> in_attesa` write exists only under `app/Actions/Participant/AuthorizeEvaluationRetry.php`; no other caller (SSO exchange, minters, recovery, scoring job) writes it.
- [x] 5.10 RED link lifetime per I9 (whichever is confirmed): assert `exp - iat` for a deliverable address, a placeholder address and a reusable-link visitor. (observed; owner resolution I9: 24 h only when BEAI can email it, i.e. deliverable address and not a visitor; placeholder, purged address and reusable-link visitor = 30 min)

GREEN
- [x] 5.11 Create `api/app/Actions/Participant/AuthorizeEvaluationRetry.php`: `handle(int $participantId, int $organizationId, RetryActor $actor, ?string $reason): RetryAuthorization` inside `TenantContextScope::runFor` and one `DB::transaction`; `Participant::where('organization_id', ...)->lockForUpdate()->findOrFail()`; guards in the design order; flip status; invalid set = project competencies (current composition) minus codes with `valid=true`; `(new ResetSessionForRetry)($session)` per invalid session that exists; set `retry_attempt` and `retry_authorized_at`; mint through `EntryLinkMinter` with row values only (no `ExternalReference`); write the log line and the `AuditRecorder` row; DTO `emailSent=false` until PR3a wires the queue. (observed; deviation: the log line and audit row are written after commit, `emailSent` is false until PR3a)
- [x] 5.12 Docblock on the action: single writer of the edge, minted in-transaction so a gate refusal rolls back, the `AuditRecorder` abort-risk note (I3), the finalize key is attempt-scoped and is not touched here (I6).
- [x] 5.13 Verify: pint, phpstan, tests 5.1-5.10, `AdminTenancySafetyArchTest`, and coverage of the action >= 95% (`pest --coverage` on the file). (observed: pint pass, phpstan 0 errors, action coverage 100%, AdminTenancySafetyArchTest green; full serial suite 8053 tests / 8035 passed / 18 skipped / coverage 95.8%)

## Phase 6: PR2a — pipeline knows it is a retry (api, ~330 lines)

RED
- [x] 6.1 RED: replace the stub pin in `api/tests/Feature/Jobs/ScoreEvaluationJobDefensiveBranchesTest.php` (around `:794`, "retry stub") with the real behaviours; create `api/tests/Feature/Retry/RetryScoringTest.php` using the fake/cassette LLM provider. (observed: RetryScoringTest 9 of 16 RED against the stub, 4 todo; the stub pin in `ScoreEvaluationJobDefensiveBranchesTest` was replaced, not weakened: same input, now asserts the logged no-op, no LLM call, nothing written)
- [x] 6.2 RED merge: `pending + retry_attempt=true`, participant `in_valutazione`: in ONE transaction the `valid=false` results (and indicator scores/audits via cascade) are deleted and status becomes `processing`; a failure injected between the two steps leaves both untouched; valid results keep ids, scores and excerpts; the Evaluation row id is unchanged (no new row). (observed: merge, atomicity via a failure injected on the status UPDATE, row-lock statement and lock-time re-check tests)
- [x] 6.3 RED re-score: only competencies without a result are scored (no duplicate LLM call for existing results); result is `completed` even below 90% valid (retry ratio e.g. 6/10); participant `in_valutazione -> completato`; `EvaluationCompleted` emitted; `retry_attempt` stays true. (observed: 6/10 ratio ends completed; cassette fails on any call for a code that already has a result)
- [x] 6.4 RED guard table (D8): `processing + retry_attempt` resumes without re-merging; `pending + retry_attempt=true` with participant not `in_valutazione` is a logged no-op; `completed + retry_attempt=true` logged no-op, no LLM call, no event; `retry_attempt=false` DB with payload flag true logged no-op; DB true with payload false merges with a `warning` log; non-retry paths unchanged. (observed: all six guard rows plus the unchanged first-attempt no-op)
- [x] 6.5 RED forced completed on an emptied composition: retry on a project with zero scorable competencies ends `completed`, never `errore` (D9). (observed)
- [x] 6.6 RED dispatch: `DispatchScoringJob` dispatches `ScoreEvaluationJob` with `retryAttempt` read org-filtered from the evaluation row (`true` for retry, `false` otherwise); add to the existing listener test. (observed, in `FinalizeInterviewHookTest`, which holds the existing listener tests; includes a foreign-organization row case)
- [x] 6.7 RED finalize key (I6): `api/tests/Feature/...` (locate the existing `FinalizeInterview` test with `fd -t f Finalize tests`): with `finalize:{pid}` already set less than 2 h ago and the evaluation `retry_attempt=true`, the last `/end` emits the C9 trigger exactly once under `finalize:{pid}:retry`; a queue retry of that finalize job within the retry run still emits once; first-attempt key unchanged. (observed, new `tests/Feature/Retry/RetryFinalizeKeyTest.php`; the existing finalize tests stay green)

GREEN
- [x] 6.8 Modify `api/app/Jobs/FinalizeInterview.php`: read `retry_attempt` (`withoutGlobalScope('tenant')`, org filter) and use `finalize:{pid}:retry` when true; never touch the cache from the action.
- [x] 6.9 Modify `api/app/Listeners/DispatchScoringJob.php` (`:80`): pass `retryAttempt` from the DB.
- [x] 6.10 Modify `api/app/Jobs/ScoreEvaluationJob.php` `enterEvaluationGuard()`: implement the D8 table and the merge transaction (`lockForUpdate`, re-check, delete invalid results, set `processing`), then the unchanged resume-skip loop.
- [x] 6.11 Modify `api/app/Actions/Scoring/ResolveEvaluationTerminalState.php`: when the refreshed row has `retry_attempt=true`, skip the gate (and the ZeroCompetencies `errore` arm), persist `Completed`, keep the participant transition and `EvaluationCompleted`; still log `valid_count`/`total_count`.
- [x] 6.12 Verify: pint, phpstan, focused tests, coverage of the job retry branch and `ResolveEvaluationTerminalState` >= 95%. (observed: pint pass, phpstan 0 errors, OpenAPI export diff 0 lines, ScoreEvaluationJob 98.1% with the only uncovered lines in `failed()` (PR2b), ResolveEvaluationTerminalState / FinalizeInterview / DispatchScoringJob 100%; full serial suite 8106 tests / 8083 passed / 23 skipped / coverage 95.8% / exit 0)

## Phase 7: PR2b — failure path, dedupe keys, recovery guard (api, ~300 lines)

RED
- [x] 7.1 (observed: 6 RED of 7 against the unchanged job; the first-attempt control passed on arrival and was mutation-checked; tests live in `RetryScoringTest.php`; extra case: a stray job for a participant that has not re-interviewed leaves the retry untouched) RED `failed()`: retry job with 8 retained valid results exhausts queue retries: Evaluation `completed` with the 8 results retained, participant `completato`, `EvaluationCompleted` emitted, `EvaluationFailed` NOT emitted, never `errore`; same via `endParticipantUnresolvable()`; failure before the merge also merges first (no first-attempt invalid results survive); `completed + retry_attempt` no-op; a throw inside the finalization leaves the participant `in_valutazione` with an `error` log, never `errore`. Non-retry `failed()` unchanged (`errore` + `EvaluationFailed`).
- [x] 7.2 (observed: 3 RED of 7, the 4 others passed on arrival and were mutation-checked; the "authorization creates no `webhook_deliveries` row" case already exists from PR1b, `AuthorizeEvaluationRetryTest` "no webhook delivery is created by an authorization") RED webhooks (real recorder, no fake): first run writes `{evaluation_id}`; retry completion writes a second `evaluation` row `{evaluation_id}:retry` with payload status `completed` and the first row unchanged; replaying the retry event leaves exactly one `:retry` row; first-run keys unchanged (`competency-ended:{pid}:{code}`); retry-era progress rows `competency-ended:{pid}:{code}:retry` distinct from first-run rows; authorization itself creates no `webhook_deliveries` row.
- [x] 7.3 (observed: 3 RED, 4 passed on arrival and mutation-checked) RED recovery guard (extend `api/tests/Feature/ParticipantRecovery/RecoverFailedParticipantTest.php`): `errore` + one `error` session + Evaluation `pending` with `retry_attempt=true` and the first-run delivery present recovers to `in_attesa`; with the `:retry` delivery present (or Evaluation `completed`) it is refused `evaluation_already_delivered`; non-retry participants unchanged; `nothing_to_recover` unchanged.

GREEN
- [x] 7.4 (deviation: the terminal resolution runs inside ONE `DB::transaction` so it is all-or-nothing; a stray job before the candidate re-interviewed is a logged no-op, the retry is not burned) Modify `api/app/Jobs/ScoreEvaluationJob.php`: private `finalizeRetryWithRetainedResults(Participant)` called first from `failed()` and `endParticipantUnresolvable()` when the row has `retry_attempt=true` and status `pending|processing`; runs the idempotent merge if still `pending`, then `ResolveEvaluationTerminalState::resolve()`; try/catch with `error` log; no `EvaluationFailed`; A6 no-op for `completed + retry_attempt`.
- [x] 7.5 Modify `api/app/Listeners/SendEvaluationWebhook.php` (`handleCompleted()`): `":retry"` suffix when `$evaluation->retry_attempt`; `handleFailed()` unchanged.
- [x] 7.6 Modify `api/app/Listeners/SendProgressWebhook.php` (`handleCompetencyEnded()`): append `:retry` when an Evaluation row with `retry_attempt=true` exists (`withoutGlobalScope('tenant')`, org id from `resolveOrganizationId()`); creation keys unchanged.
- [x] 7.7 Modify `api/app/Actions/Participant/RecoverFailedParticipant.php` (guard 1, `:101-107`): while the participant's Evaluation is `pending` with `retry_attempt=true`, refuse only if an `evaluation` delivery with `dedupe_key = '{evaluation_id}:retry'` exists; otherwise any evaluation delivery (unchanged). Guard 2 untouched.
- [x] 7.8 (observed: pint pass, phpstan 0 errors, no migration, OpenAPI export diff 0 lines, full serial suite green) Verify: pint, phpstan, focused tests; confirm no migration was needed (the unique index `(organization_id, project_id, event_type, dedupe_key)` is untouched).

## Phase 8: PR2c — `reinterview` opening variant (api, ~120 lines)

RED
- [x] 8.1 RED unit (`api/tests/Unit/Services/Conversation/OpeningTextComposerTest.php`): `compose('reinterview', ...)` returns non-empty, language-correct text for `it` and `en`; text does not contain the apology wording of `retry` and no reference to scores, results, "invalid" or "failed"; contains no BARS indicator or anchor text (anti-leak); carries `prompt_version`; unknown-variant exception message still holds; `first|next|resume|retry` output unchanged. (observed RED: 8 of 9 new composer tests failed `unknown variant [reinterview]`; the unknown-variant message pin passed on arrival as a characterization; GREEN: 35 tests pass across the composer and feature files)
- [x] 8.2 RED controller feature test (`InterviewController::start()`; locate the existing start tests with `fd -t f Interview tests/Feature`): after an authorization-reset competency, `/start` composes `reinterview` (not `first|next|resume|retry`); a provider-error re-offer inside the retry run keeps `retry`; a mid-conversation `resume` keeps `resume` (I12); a participant with no retry never gets `reinterview`. (observed RED: the reset-competency test failed with actual opening `CAS fixture question 1` = the `next` variant verbatim, expected `interview.opening.reinterview_authored`; precedence and no-retry tests passed on arrival and were mutation-checked: reinterview-before-resume RED, reinterview-before-retry RED, always-true RED x3, dropped participant filter RED, dropped org filter RED, each restored and diffed)
- [x] 8.3 RED regression: `OpeningInvitesAnswerTest` and `TurnClassifierTest` (they reference the opening) still pass with the new wording, and the TurnClassifier recognises the reinterview opening utterance the same way it recognises the others. (observed: the opening key-list guard in `OpeningInvitesAnswerTest` failed on the new key and was updated deliberately; TurnClassifier recognises the reinterview opening in en and it because the template ends on `:question`; mutation: trailing text after `:question` RED x5, restored)

GREEN
- [x] 8.4 Modify `api/app/Services/Conversation/OpeningTextComposer.php`: add `reinterview` to `VARIANTS` and the docblock; compose from `interview.opening.reinterview_authored`. (done)
- [x] 8.5 Modify `api/lang/it/interview.php` and `api/lang/en/interview.php`: add `opening.reinterview_authored` (neutral "we continue with the remaining topics", no apology). (done: it `Proseguiamo il colloquio con gli argomenti rimanenti. :question`, en `Let's continue the interview with the remaining topics. :question`)
- [x] 8.6 Modify `api/app/Http/Controllers/Candidate/InterviewController.php` (`start()`, the `$openingVariant` match near `:350`): precedence `resume`, `retry` (re-offer), `reinterview` (Evaluation `retry_attempt=true`, org-scoped read), `first`, `next`. (done: `isInEvaluationRetryRun()` reads `evaluations.retry_attempt` through the ambient tenant scope (TenantContextCandidate) + explicit organization_id and participant_id filters, NO scope strip; a first version stripped `tenant` and the full suite caught it in `AdminTenancySafetyArchTest` (guarded root `Http/`), so it was replaced instead of adding an allowlist entry; arm ordered after resume and retry)
- [x] 8.7 Check whether `conversation.prompt_version` must be bumped for a new greeting (the composer docblock says wording changes are a lang-file + version bump) and whether golden/snapshot tests pin it; bump and update only if the convention requires it. (decision: NO bump. `StandardPromptCharacterizationTest` pins `characterization-v1` and is untouched and green; the system prompt and every existing opening are unchanged, and the precedent commit that last changed opening wording (19a1db2) did not touch config/conversation.php)

## Phase 9: PR3a — retry email, admin read fields, exposure entries (api, ~300 lines, still dark)

RED
- [x] 9.1 (observed: RetryEmailTest 17 of 20 RED against the unchanged action: no job queued, `kind` missing; the no-email, rollback and refusal cases passed on arrival and are characterization tests; a 21st test added after a gga finding: a failed send must not leave the tenant colour behind, RED then GREEN; 13 mutations across the slice all killed) RED (`api/tests/Feature/Retry/RetryEmailTest.php`, `Queue::fake`/`Notification::fake`): successful authorization queues exactly one `SendCandidateInvitationJob` with `kind=Retry` for a deliverable address; `it` and `en` retry subject/intro rendered, other lines reused; body has display name, organization, project, link, absolute expiry from the token `exp`; no score, competency name/code, evaluation status or `reason` text; branding is chrome only; not a C12 notification (no notification audit row); not queued for placeholder or reusable-link visitor (`email_sent=false`, link still returned); mail failure after bounded attempts leaves the authorization intact and no second authorization possible; the queue happens only after commit (a rolled-back authorization queues nothing).
- [x] 9.2 (observed: ParticipantDetailRetryStateTest 10 of 11 RED, the cross-tenant 404 characterization passed on arrival; the read-gate test passed on arrival: the gate is untouched) RED admin read (`ParticipantDetailResource` tests): `retry_attempt`, `retry_authorized_at`, `retry_available` for the four spec scenarios (eligible, completed evaluation, authorized/in_attesa, no evaluation) plus test-mode participant => `retry_available=false` (I4); cross-tenant detail 404 exposes nothing; evaluation read gate unchanged during `in_attesa|in_corso|in_valutazione`.
- [x] 9.3 (observed RED: the Interview diff listed exactly `retry_attempt`, `retry_authorized_at`, `retry_available`; GREEN with three exclusion entries and a written reason) RED exposure: `ExposureTest` fails first for the three new admin-only fields, then passes with three exclusion entries (T-EXPOSE-001, permanent rule); nothing added to `/v1`, M2M or exports.

GREEN
- [x] 9.4 Create `api/app/Support/Mail/CandidateInvitationKind.php` (`Initial|Retry`, string-backed); modify `api/app/Jobs/SendCandidateInvitationJob.php` (trailing `kind = Initial`, keeps its placeholder refusal) and `api/app/Notifications/CandidateInvitationNotification.php` (select `candidate_invitation.retry.subject` / `.intro`).
- [x] 9.5 (deviation: a third key `retry.expiry` too, because the spec requires the email to say the link is single-use and the shared expiry line does not) Modify `api/lang/it/candidate_invitation.php` and `api/lang/en/candidate_invitation.php`: `retry.subject`, `retry.intro` (static, not tenant-editable).
- [x] 9.6 (the queue is registered with `DB::afterCommit` once the link is composed; `emailSent` is `minted->delivery === Emailed`, so lifetime, mail and flag share one decision) Modify `api/app/Actions/Participant/AuthorizeEvaluationRetry.php`: `DB::afterCommit` dispatch of the retry job unless placeholder or `reusable_interview_link_id !== null`; DTO `emailSent` and the log/audit `email_queued` reflect the real decision; update the PR1b assertions accordingly.
- [x] 9.7 Modify `api/app/Http/Resources/Admin/ParticipantDetailResource.php`: the three flat fields (one extra org-scoped Evaluation query); `@return` and `@scramble-return` docblocks in lockstep.
- [x] 9.8 Modify `api/tests/Helpers/PublicApi/ExposureCatalogue.php`: three admin-only exclusion entries under `'Interview'`, classified in this same change, in the catalogue's existing entry format.
- [x] 9.9 (observed: diff is exactly the three properties and three `required` entries of `ParticipantDetailResource`) Re-export `api/openapi.json` against Postgres (generated, excluded from budget) and confirm only the detail schema changed.
- [x] 9.10 (observed: pint pass, phpstan 0 errors, RetryEdgeWriterArchTest and the arch suite green, full serial `pest --coverage --min=85` 8185 tests / 8166 passed / 19 skipped / 0 failed / coverage 95.8% / exit 0; AuthorizeEvaluationRetry, ParticipantDetailResource, SendCandidateInvitationJob, CandidateInvitationNotification 100%; ~810 authored lines over two commits, over the ~400 heuristic, no split point defined) Verify: pint, phpstan, focused tests; the PR1b arch test still passes (afterCommit change does not add a second edge writer).

## Phase 10: PR3b — surfaces on (api, ~360 lines; switches the feature on)

RED
- [x] 10.1 (observed: 35 of 38 RED against missing routes; the 3 that passed on arrival are negative checks, killed by mutation; refusal/403/404/422/actor/org/link-leak cases all mutation-checked) RED (`api/tests/Feature/Retry/EvaluationRetryEndpointTest.php`): `POST /api/participants/{id}/retry`: admin and operator 200 with `{status, entry_url, expires_at, email_sent, competencies_reset}`; viewer 403 before 404 even for a foreign id; cross-tenant id 404; optional `reason` (501 characters = 422; absent = log `reason: null`); every refusal reason maps to 409 `{reason}`.
- [x] 10.2 (observed with 10.1; M2M actor test additionally exposed the AuditRecorder foreign-key defect, see PR3b notes; the operator-vs-M2M race is covered sequentially, all four surface orders, one 200 and one `retry_already_consumed`, one audit row) RED M2M: `POST /api/m2m/participants/{id}/retry`: client with `participants:retry` 200; without the ability 403 before resolution (even a foreign id); cross-organization 404; refusal 409 with shared reasons; actor recorded as the client in log and audit; operator-vs-M2M race gives exactly one 200 and one `retry_already_consumed`.
- [x] 10.3 (observed: AbilitiesMapTest RED on the new `retry` key for all three roles; store test added in EvaluationRetryEndpointTest) RED abilities: `UserAbilities` carries `participants.retry` true/true/false for admin/operator/viewer; `POST /api/m2m/clients` accepts `participants:retry` (stored lowercase) and still rejects unknown abilities.
- [x] 10.4 (observed: AuthMatrix RED `Undefined array key` then 500 for the missing candidate origin config; fixtures and catalogue added; 1798 matrix tests green; catalogue/fixture removals each killed) RED matrix: add both routes to `api/tests/Helpers/AuthMatrix/AuthMatrixCatalogue.php` (`self::orgScoped([A, O], cross: NOT_FOUND, bare: NOT_FOUND)` and `self::m2m('participants:retry')`); the AuthMatrix suite fails until routes exist; arch guard forbids a literal `Participant::` in `Http/Controllers/Api`.
- [x] 10.5 (observed: green on first complete run since all slices exist; 2 production mutations killed: finalize `:retry` key and webhook `:retry` key) RED SA-07 end to end (`api/tests/Feature/Retry/RetryEndToEndTest.php`): first interview scores `pending` and delivers the `pending` webhook; authorize through the endpoint; exchange the returned link; re-interview only invalid competencies (valid never re-asked, first competency opens with `reinterview`); second `evaluation` webhook `completed` with a distinct delivery id and `{evaluation_id}:retry` key; participant `completato`; second authorization 409 `retry_already_consumed`.
- [x] 10.6 (observed: ExposureTest passes with no catalogue change; no retry path in openapi.v1.json or public-api/openapi.yaml; route-list test pins exactly the two internal paths) RED exposure: `ExposureTest` still passes without a `/v1` retry path; OpenAPI export diff clean.

GREEN
- [x] 10.7 (no ApiClient validation change: the set is driven by config) Modify `api/app/Policies/ParticipantPolicy.php` (`retry(User): bool`, admin/operator), `api/app/Support/Authorization/UserAbilities.php` (`participants.retry`), `api/config/m2m_abilities.php` (`participants:retry`), and the ApiClient ability validation set if it is not driven by that config.
- [x] 10.8 Create `api/app/Http/Controllers/Api/EvaluationRetryController.php`: `$this->authorize('retry', ParticipantPolicy::MODEL)` first, org from `TenantResolver::getOrgId()`, actor `RetryActor::user`, render `EvaluationRetryRefused` as 409 following the `RecoverFailedParticipant` precedent, response literals inline for Scramble.
- [x] 10.9 Create `api/app/Http/Controllers/M2m/EvaluationRetryController.php`: org from `$request->user('api-m2m')->organization_id`, actor `RetryActor::apiClient`.
- [x] 10.10 Modify `api/routes/api.php`: operator route in the `['auth:api', TenantContext::class]` write group adjacent to `/evaluation/audit` (`:720`); M2M route with `ability:participants:retry`.
- [x] 10.11 (diff = exactly the two operations, 215 lines) Re-export `api/openapi.json` against Postgres (generated) and commit; confirm the fresh export diff is clean in CI terms.
- [x] 10.12 (observed: pint pass, phpstan 0 errors, full serial `pest --coverage --min=85` 8254 tests / 8235 passed / 19 skipped / 0 failed / coverage 95.8% / exit 0; both controllers, the action, the policy and AuditRecorder 100%; the feature is now reachable on both surfaces) Verify: pint, phpstan, full `pest --coverage --min=85` serially, coverage >= 95% on the action and job retry branch; record that the feature is now reachable.

## Phase 11: PR4a — backoffice client, composable, panel (backoffice, ~340 lines)

- [x] 11.1  (observed: openapi.json byte-identical to api 2ebf112; `bunx openapi-typescript`; `scripts/check-client-drift.sh` exit 0 both stages; the wrapper cross-repo parity stays red for frontend until PR4f by design; the new required detail fields broke the e2e `participantDetail` fixture typecheck, fixed with honest no-retry defaults)Regenerate `backoffice/openapi.json` and `backoffice/types/api.ts` from the api release/develop spec (generated, never hand-edited); parity check passes.
- [x] 11.2  (observed: 29 tests; DEVIATION: the retry flag is NOT in the generated `Abilities` type, the api's `AuthController::me` `@scramble-return` shape stops at `recover`, so the panel is gated by a `canRetry` prop the page derives later and the unit/e2e abilities mirrors were NOT extended; 24 mutations killed after triangulating 4 survivors; the panel emits `authorized` without the link)RED: create `backoffice/tests/unit/components/organisms/EvaluationRetryPanel.spec.ts`: five states from `retry_available`, `retry_attempt`, `retry_authorized_at` and literal `status` (Available / Waiting with authorized date / In progress / Scoring / Finished) and not rendered when no retry state (completed evaluation without retry, no evaluation); authorize action absent without the `participants.retry` flag (viewer) and absent by the flag, not the role name; confirm dialog lists invalid-only re-interview, evaluation unreadable until scored, once-only and not withdrawable, single-use link created and emailed when deliverable, with an optional reason (max 500) and no request sent before confirm; reason trimmed, empty sends no `reason`; success shows link, Copy, single-use statement, absolute expiry from `expires_at` and the email line, and after dismissal the link cannot be shown again; no claim that an earlier link was revoked; each 409 reason (`retry_already_consumed`, `not_completed`, `test_mode_participant`, `evaluation_not_pending`, `project_inaccessible`) maps to its i18n key and disables the action; `it` and `en` have every key.
- [x] 11.3  (observed: RED = module missing, GREEN 3 tests, 4 mutations killed)RED: composable spec for `useEvaluationRetry` (path `/api/participants/{id}/retry`, body, typed from `types/api.ts`, mocked `useApi`).
- [x] 11.4  GREEN: create `backoffice/app/composables/useEvaluationRetry.ts` (mirror `useParticipantRecovery.ts`).
- [x] 11.5  (observed: EntryLinkPanel gained an opt-in `hideGenerate` prop so the retry link has no re-issue button; an `allowGenerate` boolean was tried first and Vue boolean casting made absent = false, hiding the button by default)GREEN: create `backoffice/app/components/organisms/EvaluationRetryPanel.vue` (mirror the recovery panel; reuse the consequence-driven confirm dialog and `EntryLinkPanel` single-use branch; `getErrorReason` for 409).
- [x] 11.6  (observed: 5 refusal keys plus `unknown`, parity and no-fixed-duration asserted by the spec)GREEN: modify `backoffice/i18n/locales/it.json` and `backoffice/i18n/locales/en.json`: `evaluationRetry.*` including `refusalReason.{reason}` for all five reasons.
- [x] 11.8  (observed: client regenerated from api develop 63e1f3f, `Abilities` now has `participants.retry`; RED = nuxi typecheck TS2741 on the unit mirror, GREEN after `retry: operator`; contract stub probes the key; value test added and mutation-killed; full Vitest 214 files / 3503 passed / 1 skipped; drift check exit 0 both stages; the panel keeps its `canRetry` prop, the page derives it in PR4b)Extend the abilities mirrors for `participants.retry` after the api publishes it.
- [x] 11.7  (observed: eslint 0, prettier --check clean, `bun run typecheck` exit 0, full Vitest 214 files / 3502 passed / 1 skipped / exit 0; panel not mounted)Verify: `bun run vitest`, lint, typecheck; the panel is not mounted yet (dark).

## Phase 12: PR4b — page wiring and E2E (backoffice, ~150 lines)

- [x] 12.1 (observed: 22 Playwright tests, 11 per browser; passed on arrival because the page was wired in the same slice after the unit RED, so each was mutation-checked on Chromium: canRetry=true, no refresh, console leak and sessionStorage leak all fail the suite; covers consequences-first, link once with absolute expiry and email status, dismissal and reload, five 409 reasons, viewer, no-retry) RED: create `backoffice/tests/e2e/participant-evaluation-retry.spec.ts` (Playwright, Chromium + WebKit, mocked API routes): operator authorizes with a reason, sees link, expiry and email status once, then sees the Waiting state; viewer sees no action; eligible participant of a `completed` evaluation shows no panel.
- [x] 12.2 (observed: 5 RED of 7, then 10 tests in detail.spec.ts; 9 page mutations killed after triangulating status and locale; the gating reads the shared `can('participants.retry')`; the page does not reuse the instance on id change, so the panel's own reset is covered by its spec) RED: unit test for the page mount condition (`can('participants.retry')` gating from the shared current-user state, fetched once).
- [x] 12.3 (observed: panel mounted beside the recovery card in an `empty:hidden` wrapper, `canRetry` from `can('participants.retry')`, `authorized` refetches the participant; backoffice commits 3f813ff and ba17216 on feature/retry-pr4b-page-wiring) GREEN: modify `backoffice/app/pages/participants/[id].vue`: mount `EvaluationRetryPanel`; read-only state lines for all roles.
- [x] 12.4 (skipped with note: analytics-path.ts redacts `/participants/:id/*` by pattern, it does not enumerate write paths) GREEN: modify `backoffice/app/utils/analytics-path.ts` only if the module enumerates write paths (verify first; skip and tick with a note if not).
- [x] 12.5 (observed: eslint 0, prettier clean, `bun run typecheck` exit 0, full Vitest 214 files / 3518 passed / 1 skipped, Playwright 22/22 on Chromium and WebKit; no browser gate introduced) Verify: Vitest + Playwright (both browsers); no browser/viewport gate is introduced in backoffice.

## Phase 13: PR4f — frontend regenerated client (frontend, 0 authored lines)

- [x] 13.1 (observed: api origin/develop 63e1f3f openapi.json copied byte-identical; bunx openapi-typescript; check-client-drift.sh RED exit 1 then GREEN exit 0; typecheck 0; Vitest 2081/2081; frontend-pr4f commit 9b89348, no frontend code or fixture changes needed) Regenerate `frontend/openapi.json` and generated types from the same api release as PR4a; run the frontend Vitest suite and the openapi parity check. No hand edits.

## Phase 14: PR5 — docs promotion and submodule pins (wrapper, ~120 lines)

- [ ] 14.1 Pin the released api, backoffice and frontend tags in the wrapper (verify each submodule push landed on its remote; versions only change in release branches).
- [x] 14.2 (done in batch 13, wrapper branch `feature/retry-and-potential-docs`, commit df5d22c: ruling 4 RATIFIED 2026-10-05 with the owner-confirmed wording; Completion gate and Candidate lifecycle bullets aligned; ROADMAP decision 4 ratified and decisions 8/9 aligned with CLAUDE.md) Edit `CLAUDE.md` ruling 4 to RATIFIED with the proposal's Q2/Q3 wording, mentioning the 24 h emailed link; edit `openspec/ROADMAP.md` (line ~72 ruling 4 plus decisions 8 and 9 per A14).
- [x] 14.3 (done in batch 13, commit 48ea363, also `02-evaluation-rules.md`, `02-domain/02-evaluation.md` and SA-07) Edit `docs/app_description/05-business-rules/01-candidate-lifecycle.md` (retry rules, `completato` no longer terminal).
- [ ] 14.4 Apply the archive-time edits below when `sdd-archive` promotes the deltas.

### Archive-time edits (from the specs' non-requirement notes)

- `openspec/specs/scoring-engine/spec.md`: delete the "Retry sub-system (chain-PR 4) - DEFERRED" paragraph in "Delivery Status" (lines ~15-19) and keep the first-pass line; remove the old requirement "Retry - Fast-Follow Work Unit (RT-B)" (line ~1160) with its DEFERRED banner and the open items RT-B-O1/O2/O3; update the cross-reference "Retry - Fast-Follow Work Unit" at lines ~1008-1009 to the new requirement name; fix the "records domain-retry context for audit only; the RT-B dispatch sets both" note (lines ~63-64) per I10.
- `openspec/specs/notifications/spec.md`: correct the Purpose paragraph (lines 10-16) and the first Non-Goals bullet (lines 293-294): candidate-facing transactional email exists (rulings 8 and 10); only reminders and time-triggered notifications remain non-goals.
- `CLAUDE.md` ruling 4, `openspec/ROADMAP.md` line ~72 and decisions 8/9, `docs/.../01-candidate-lifecycle.md` (listed in 14.2-14.3).
- Verify at archive that `openspec/specs/reusable-interview-links/spec.md` line ~1810 (sso-link TTL unchanged) is still true: returned links stay 30 min.
- Merge all nine deltas (participant-sso, scoring-engine, webhooks-integration, interview-session, interview-conversation, m2m-auth, admin-read-api, admin-backoffice, notifications) with the I1-I10 reconciliations applied.

## Rollback note

- PR0: revert restores 30-minute emailed links; links already emailed keep their 24 h `exp` and still exchange.
- PR0b: revert restores the fixed-duration copy (false for emailed links once PR0 is live; revert PR0 first or together).
- PR1a..PR3a: dark; revert the merge commit and re-release. Migration `retry_authorized_at` is reversible.
- Stop the feature: revert PR3b (routes, ability, policy) and PR4b; no new authorizations occur. Participants already mid-retry stay valid (D-C).
- DO NOT revert PR2a or PR2b while any participant is mid-retry. Reverting PR2a turns their scoring into a no-op (stub) and leaves them `in_valutazione` with a `pending` evaluation; reverting PR2b lets the retry completion webhook collide with the first `{evaluation_id}` row and be swallowed. Check first:
  `select count(*) from evaluations e join participants p on p.id = e.participant_id where e.retry_attempt and p.status <> 'completato';`
  Proceed only when the count is 0 (or the owner accepts remaining `pending`). Delivery rows under `:retry` keys remain valid history.

## Task dependency summary

- Sequential (merge): see the stacking table. Authoring may run in parallel for: PR0 with PR0b; PR2c with PR1a..PR2b; PR4f with PR4a/PR4b.
- Within a slice, RED tasks precede GREEN tasks; verify tasks close each slice.
- Spec traceability: Phase 2 -> participant-sso "Emailed Invitation Links Live 24 Hours"; Phase 3 -> admin-backoffice "Link Disclosure"; Phase 4/5 -> participant-sso (guard, action, refusals, role gating, interim logging), interview-session (FIX-5, re-interview offers only invalid); Phase 6/7 -> scoring-engine (job lifecycle, RT-B), webhooks-integration, participant-sso (recovery guards), interview-session (finalize dedup); Phase 8 -> interview-conversation; Phase 9 -> notifications, admin-read-api; Phase 10 -> participant-sso (role gating), m2m-auth; Phase 11/12 -> admin-backoffice; Phase 14 -> docs and archive.

Threat matrix: N/A (no shell, subprocess, VCS/PR automation or process-integration boundary); authorization, tenant isolation and TTL cases are covered by the RED tasks above.
