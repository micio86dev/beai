# Design: Scoring Retry (RT-B) — single re-interview of a `pending` evaluation

Change: `scoring-retry-rt-b` · Phase: design · Date: 2026-10-05
Inputs: `proposal.md`, `exploration.md`, owner decisions D-A/D-B/D-C, assumptions A2..A14
(standing), owner override of A1 on 2026-10-05 (all emailed invitation links live 24 h).
Every code reference below was read from the working tree on 2026-10-05.

## Technical Approach

Four moves, each reusing delivered machinery rather than inventing a parallel path:

1. **PR0 — emailed links live 24 h.** The link lifetime becomes a function of the delivery
   channel, decided in ONE place (`EntryLinkMinter`). A link BEAI emails lives
   `candidate_invitations.emailed_link_ttl_minutes` (default 1440); every link only *returned*
   to a caller (M2M sso-link, operator `send_email=false`, reusable-link visitors, placeholder
   addresses) keeps `CandidateTokenFactory::SSO_LINK_TTL_MINUTES = 30`. The binding `CLAUDE.md`
   SSO rule is amended first.
2. **PR1 — one authorization action.** `AuthorizeEvaluationRetry`, modelled on
   `RecoverFailedParticipant`: org filter + `lockForUpdate` inside one `DB::transaction`,
   status re-read under the lock, typed refusals rendered 409. Inside the transaction it flips
   `completato -> in_attesa` (a new edge writable only here), resets the invalid competencies'
   sessions with `ResetSessionForRetry`, sets `evaluations.retry_attempt = true` +
   `retry_authorized_at`, and mints the link (so a gate refusal rolls everything back). After
   commit it queues the retry email and writes the interim log line and the audit row.
3. **PR2a/PR2b — the pipeline knows it is a retry from the database.** `FinalizeInterview`
   uses an attempt-scoped dedup key; `DispatchScoringJob` passes `retryAttempt` read from the
   evaluation row; `ScoreEvaluationJob` merges at job start (delete invalid results + set
   `processing` in one transaction) and reuses resume-skip; `ResolveEvaluationTerminalState`
   forces `completed`; `failed()` finalizes `completed` with retained results, never `errore`;
   webhook dedupe keys gain a `:retry` suffix; the recovery guard admits an interview-stage
   `errore` during an in-flight retry.
4. **PR3a/PR3b/PR4a/PR4b — surfaces.** Retry email copy + dispatch and the admin read state
   land dark (PR3a); the two thin HTTP controllers, policy, ability and abilities flag switch it
   on (PR3b); the backoffice panel follows (PR4a/PR4b); the wrapper promotes the docs (PR5).

> **SUPERSEDED (consistency report I5, as built in PR2c).** This paragraph originally claimed the
> neutral re-interview opening (A10) needed no production code, because a competency reset to
> `pending` resolves to `next` (the authored primary, verbatim, no greeting). The interview-conversation
> spec requires a neutral greeting, so a new `reinterview` opening variant was built: a new
> `OpeningTextComposer` variant, the `opening.reinterview_authored` key in `lang/{it,en}/interview.php`
> and an arm in `InterviewController::start()`. Precedence is `resume` > `retry` > `reinterview` >
> `first` > `next`, the `reinterview` arm reading `evaluations.retry_attempt` through the ambient tenant
> scope plus explicit organization and participant filters (no tenant-scope strip). No
> `conversation.prompt_version` bump: the system prompt is unchanged.

## Architecture Decisions

### D1 — Link lifetime follows the delivery channel, decided inside `EntryLinkMinter`

**Choice**: New enum `App\Support\Sso\LinkDelivery { Returned, Emailed }`. `EntryLinkMinter::mint()`
gains a trailing `LinkDelivery $delivery = LinkDelivery::Returned` (after `ExternalReference`, so
every positional caller stays valid). The minter downgrades `Emailed` to `Returned` when the
target row is a reusable-link visitor (it already computes `$targetsReusableLinkVisitor`, `:91-93`)
and returns the effective channel on `MintedEntryLink::$delivery`. TTL =
`Emailed ? config('candidate_invitations.emailed_link_ttl_minutes') : SSO_LINK_TTL_MINUTES`.
`CandidateTokenFactory::mintSsoLink(array $claims, int $ttlMinutes = self::SSO_LINK_TTL_MINUTES)`
takes the TTL as a parameter; `expires_at` is still read back from the token's own `exp`
(`EntryLinkMinter:145-146`), so it cannot drift.
Callers: `EntryLinkController` passes `Emailed` iff `send_email && ! PlaceholderEmail::is()`, and
derives `email_sent` from `$minted->delivery === Emailed` (replacing the inline triple-condition at
`:278`); `DispatchScheduledInterviewInvitations` (`:359`) passes `Emailed`; the retry action passes
`Emailed` iff the address is not a placeholder; the minter then downgrades a reusable-link visitor to
`Returned` itself, so the retry link is 24 h only when BEAI emails it (owner resolution I9) and 30 minutes
otherwise. `SsoLinkController` (M2M) and the reusable-link redemption are untouched and stay at 30 minutes.
Config: new `api/config/candidate_invitations.php`, key `emailed_link_ttl_minutes`, env
`CANDIDATE_INVITATION_LINK_TTL_MINUTES`, default `1440`. Read with `config()->integer()`; a value
outside `[15, 10080]` throws a `RuntimeException` at mint time (refused, not clamped — same doctrine
as `ReapStaleInterviews:56-71`).
**Alternatives considered**: (a) raise `SSO_LINK_TTL_MINUTES` globally to 24 h — rejected: the owner
scoped the change to emailed links, and `reusable-interview-links/spec.md:1810` forbids altering the
sso-link TTL for that capability; a returned link sitting in an integrator's logs for a day is a
larger bearer-token window for no benefit. (b) Decide the TTL in each controller — rejected: the
visitor downgrade lives in the minter, so the controller cannot know the final channel; two places
deciding means the TTL and the `email_sent` flag can disagree. (c) A separate `mintEmailedLink()`
method — rejected: duplicates the gate/inheritance logic the minter exists to centralize.
**Rationale**: one decision point means "the link lifetime matches how it was delivered" is a
single testable invariant, and `email_sent` becomes a projection of it instead of a parallel rule.
The exchange needs no change: `checkOrFail()` validates `exp` whatever its value, and the jti
consume TTL is already `max(exp - time(), 60)` (`SsoExchangeController:213-219`).

### D2 — `completato -> in_attesa` edge, writable only by the action

**Choice**: `Participant::$allowedTransitions['completato'] = ['in_attesa']` (`Participant.php:165`),
with the docblock rewritten to state the single writer, mirroring the `errore` entry. An arch test
(new, `tests/Arch/RetryEdgeWriterArchTest.php`) asserts that the literal edge is written only under
`app/Actions/Participant/AuthorizeEvaluationRetry.php`. `completato -> errore` stays forbidden.
**Alternatives considered**: a new participant status (`in_ripetizione`) — rejected: every read
gate, serializer, public `InterviewStatus` mapping and dashboard counter would need a new arm, and
the existing `in_attesa -> in_corso -> in_valutazione -> completato` path already does exactly what
the re-interview needs (proven by the recovery precedent).
**Rationale**: RT-B-O3 dissolves (A7). The model guard still rejects every other move out of
`completato`.

### D3 — Audit of every check that assumes `completato` is terminal

| Site | Current behaviour | Impact | Action |
|---|---|---|---|
| `ParticipantStatusGuard::TERMINAL_STATUSES` | blocks candidate interview routes for `completato`/`errore` | after the flip the participant is `in_attesa`, so the new link works | none |
| Old candidate JWT (120 min, `CandidateTokenFactory:130`) | still valid after the flip if minted < 2 h earlier | same participant, same authority as the new link; identical to the recovery precedent | accepted, documented (risk R6) |
| `SsoExchangeController` step 9 (`:240-244`) | refuses any existing status other than `in_attesa` | flip makes the retry link pass; step 4 interviewability is exempt (sessions exist) | none |
| `SsoExchangeController` upsert (`:337-365`) | overwrites `display_name/email/role_code/language` from claims | the action mints with the participant's current values, so the upsert is a no-op rewrite | mint uses row values (D5) |
| `EntryLinkMinter` (`:100-106`) | refuses `completato`/`errore` rows | the action mints inside the transaction after the flip, same connection sees `in_attesa` | none |
| `LifecycleReadGate` (`:75-78`) | evaluation readable only at `completato`; transcript from `in_corso` | evaluation unreadable during the retry (A3); transcript readable during the re-interview | none (risk R2 for D-C) |
| `EvaluationIndexQuery` (`:63-65`) | lists only `completato` | a mid-retry participant drops out of the evaluations index until it returns | none (consistent with A3) |
| `EvaluationAuditController` | 409 before `completato` | audit unavailable mid-retry; audit rows on deleted invalid indicator scores cascade away (`indicator_score_audits.indicator_score_id` cascadeOnDelete) | none, documented |
| `FinalizeInterview` (`:125`, `:135-138`) | 2 h NX key `finalize:{pid}` | would drop a re-interview finished within 2 h | D7 attempt-scoped key |
| `ScoreEvaluationJob` guard (`:251-266`) | stub for retry | — | D8 |
| `ResolveEvaluationTerminalState` (`:84-104`, `:121-145`) | gate decides status; ZeroCompetencies -> `errore` | — | D9 forced `completed` |
| `ScoreEvaluationJob::failed()` / `endParticipantUnresolvable()` (`:502-558`) | `in_valutazione -> errore` + `EvaluationFailed` | swallowed webhook + unrecoverable | D10 |
| `RecoverFailedParticipant` guard 1 (`:101-107`) | refuses when any evaluation delivery exists | interview-stage `errore` during a retry unrecoverable | D11 |
| `SendEvaluationWebhook` / `SendProgressWebhook` dedupe keys | `{evaluation_id}`; `competency-ended:{pid}:{code}` | second webhook / retry progress swallowed | D12 |
| `RunMockInterviewJob` / `DispatchScoringJob` test-mode skip (`:76-78`) | test-mode participants are never scored by the real job | a test-mode retry would strand at `in_valutazione` | refusal `test_mode_participant` (D4) |
| Public `InterviewStatus` (`Support/PublicApi/InterviewStatus.php:46`), `UsageAggregator:130`, `DashboardController:114`, `ClientOverviewReader:64` | count / map `completato` | a mid-retry participant is temporarily reported as not completed | accepted (risk R5) |
| `ReapStaleInterviews` / `settleAbandoned` | acts on `in_corso` sessions only; `$spoke` counts all utterances | an abandoned re-interview settles to `in_valutazione` and is scored definitively | correct by D-C/RT-B rule |
| `PurgeExpiredDataCommand` | age-based, status-agnostic | a purged row becomes a placeholder address: no email (D-B) | none |
| `InterviewEventRecorder` | append-only, no unique key | `under_evaluation`/`completed`/`scoring_ready` recorded a second time | accepted (append-only log of real events) |

### D4 — `AuthorizeEvaluationRetry`: one action, explicit org, typed refusals

**Choice**: `App\Actions\Participant\AuthorizeEvaluationRetry::handle(int $participantId,
int $organizationId, RetryActor $actor, ?string $reason): RetryAuthorization`. The organization id
is an explicit argument (as `RescheduleParticipant::handle($id, $orgId, …)` does for its two
surfaces), and the body runs inside `TenantContextScope::runFor($organizationId, …)` so the
tenant-scoped `Evaluation`/`InterviewSession` reads are scoped by construction on both surfaces.
Refusals: `App\Exceptions\Participant\EvaluationRetryRefused` carrying
`EvaluationRetryRefusalReason`:

| Reason (machine value) | Condition (checked in this order, under the lock) |
|---|---|
| `retry_already_consumed` | an evaluation row exists with `retry_attempt === true` |
| `not_completed` | participant status is not `completato` |
| `test_mode_participant` | `participant.mode === ApiKeyMode::Test` (would never be scored, D3) |
| `evaluation_not_pending` | no evaluation row, or `status !== pending` |
| `project_inaccessible` | `EntryLinkMinter::projectIsAccessible($project)` is false (A9) |

`retry_already_consumed` is checked first on purpose: a participant mid-retry is `in_attesa`, so
with a status-first order a second authorization (A12) would be answered `not_completed`. Lock the
participant, load its evaluation, and refuse a consumed retry before anything else; every second
authorization then receives `retry_already_consumed` whatever the participant's current status.
Inside the transaction, after the guards: flip to `in_attesa`; compute the invalid set
(`project competencies (current composition) minus codes with CompetencyResult.valid = true`);
for each invalid code with an existing `InterviewSession`, `(new ResetSessionForRetry)($session)`;
set `retry_attempt = true`, `retry_authorized_at = now()`; mint the link via
`EntryLinkMinter::mint($project, row values…, delivery)`. AFTER the transaction commits (owner
resolution I3, like `DuplicateAvatarTemplate` and `DisableReusableInterviewLink`; `AuditRecorder`
swallows its own exceptions and a Postgres error inside a transaction would abort it): write the
interim log line `participant.retry_authorized` (the name the spec uses; same shape and "INTERIM —
NOT the ratified audit trail" label as `participant.recovered`, plus `actor_type`/`actor_user_id`/
`actor_api_client_id`, never display name, email or candidate_ref) AND an `AuditRecorder` row with
action `evaluation.retry_authorized`, subject `evaluation` + the evaluation id (precedent
`evaluation.audit_requested`); a failure of either is reported and swallowed. The retry email is
registered inside the transaction with `DB::afterCommit` (wired in PR3a) and queues
`SendCandidateInvitationJob` with the retry kind unless the address is a placeholder or the row is
a reusable-link visitor (D13). The action refuses a `user` actor without a user id before any write.
Result DTO `RetryAuthorization { status: 'in_attesa', entryUrl, expiresAt, emailSent,
competenciesReset: list<string> }`. Returned to both surfaces; the link is never stored and never
re-returned.
**Alternatives considered**: (a) Implicit org from `TenantResolver` like `RecoverFailedParticipant`
— rejected: the M2M surface resolves the org from the `ApiClient`; an explicit argument makes the
scoping visible in the signature and testable without middleware. (b) Mint after commit — rejected:
a project closing between commit and mint would leave the retry consumed with no link; minting
inside the transaction (pure JWT signing plus one read on the same connection) lets a
`EntryLinkRefused` roll the whole authorization back. (c) Delete invalid results at authorization
— rejected (A11): if the candidate never returns (D-C), the pending evaluation must stay intact and
consistent with the `pending` webhook already delivered.
**Rationale**: one action is D-A; a row lock plus the flag in the same transaction is A12; minting
in-transaction makes "authorized" and "link exists" atomic. The "single transaction" wording
therefore covers the state change and the mint, not the log line, the audit row or the email.

### D5 — The retry link is minted from the row, never from request input

**Choice**: `candidate_ref`, `display_name`, `email`, `role_code`, `language` all come from the
locked participant row; no `ExternalReference` is passed (the exchange's `COALESCE` keeps the stored
values, `SsoExchangeController:348-349`). The request body accepts only `reason` (nullable, max 500).
**Alternatives considered**: accepting a new email in the retry request — rejected: identity is the
email (ruling 8) and changing it is a different operation with its own uniqueness rules.
**Rationale**: the exchange upsert rewrites identity columns from claims; claims equal to the row
make that rewrite a no-op.

### D6 — HTTP surfaces: two thin controllers over the action

**Choice**:
- Operator: `POST /api/participants/{id}/retry` ->
  `App\Http\Controllers\Api\EvaluationRetryController::store`, route group
  `['auth:api', TenantContext::class]` adjacent to `/evaluation/audit` (`routes/api.php:720`).
  `$this->authorize('retry', ParticipantPolicy::MODEL)` first (403 before 404, model-less, the
  arch guard forbids a literal `Participant::` under `Http/Controllers/Api`). Org id from
  `TenantResolver::getOrgId()`.
- M2M: `POST /api/m2m/participants/{id}/retry` -> `App\Http\Controllers\M2m\EvaluationRetryController::store`,
  middleware `ability:participants:retry`, org id from `$request->user('api-m2m')->organization_id`.
- Both: 200 `{status, entry_url, expires_at, email_sent, competencies_reset}`; 409
  `{reason}` for every `EvaluationRetryRefusalReason`; 404 cross-tenant/unknown id
  (`ModelNotFoundException`); 422 validation. Response literals inline per controller so Scramble
  derives each schema (the `EntryLinkController` convention). The field is named `entry_url` on
  purpose: the backoffice Sentry key denylist already redacts `entry_url`
  (`backoffice/app/utils/sentry-scrub.ts:315`).
- `ParticipantPolicy::retry(User): bool` — admin/operator. `UserAbilities` gains
  `participants.retry`. `config/m2m_abilities.php` gains `participants:retry`.
  `tests/Helpers/AuthMatrix/AuthMatrixCatalogue.php` gains both routes
  (`self::orgScoped([A, O], cross: NOT_FOUND, bare: NOT_FOUND)` and `self::m2m('participants:retry')`).
**Route (resolved by the orchestrator before tasks)**: both surfaces use `/participants/{id}/retry`,
matching the specs, the proposal and the `/participants/{id}/recover` precedent. Rejected:
`/participants/{id}/evaluation/retry` (beside `/evaluation/audit`) — the action also moves the participant
(`completato -> in_attesa`), so it is an operation on the participant, not only on the evaluation. One controller with two guards — rejected: the two surfaces differ in
auth guard, org source and actor type; sharing the action is the deduplication that matters.
**Rationale**: D-A with zero duplicated decision logic.

### D7 — `FinalizeInterview` dedup key is attempt-scoped, not released

**Choice**: `FinalizeInterview::handle()` reads
`Evaluation::withoutGlobalScope('tenant')->where('organization_id', $this->organizationId)
->where('participant_id', $this->participantId)->value('retry_attempt')` and uses
`finalize:{pid}` for the first attempt and `finalize:{pid}:retry` when the flag is true. The action
never touches the cache.
**Alternatives considered**: `Cache::forget('finalize:{pid}')` in the action (A13 as written) —
rejected: a cache write is not transactional (a forget that runs and then a rolled-back
authorization, or a Redis blip after commit, both fail silently), and the failure mode is SA-07
dropping a re-interview with nothing logged.
**Rationale**: A13's goal (a re-interview finished within 2 h is not dropped) is met
deterministically; exactly one retry exists, so two keys are a closed set.

### D8 — `ScoreEvaluationJob` retry branch: the database is authoritative

**Choice**: `DispatchScoringJob` (`:80`) reads the evaluation's `retry_attempt` (org-filtered, same
`$event->organizationId`) and dispatches `ScoreEvaluationJob::dispatch($pid, retryAttempt: $flag)`.
In `enterEvaluationGuard()`:

| Evaluation state (DB) | Participant | Job flag | Behaviour |
|---|---|---|---|
| none | any non-`errore` | any | create `processing`, score (unchanged) |
| `processing` | any non-`errore` | any | resume-skip (unchanged); D9 forces `completed` if `retry_attempt` |
| `pending`, `retry_attempt=false` | — | any | no-op (unchanged) |
| `pending`, `retry_attempt=true` | `in_valutazione` | true | **merge transaction**, then `runScoringPipeline()` |
| `pending`, `retry_attempt=true` | `in_valutazione` | false | same merge, plus a `warning` log (unreachable after PR2a; never strand the participant) |
| `pending`, `retry_attempt=true` | not `in_valutazione` | any | logged no-op (stray job while the candidate has not re-interviewed) |
| `completed`, `retry_attempt=true` | — | any | logged no-op (A6) |
| `completed`, `retry_attempt=false` | — | any | no-op (unchanged) |
| any, `retry_attempt=false` | — | true | logged no-op (flag without DB authorization) |

Merge transaction: lock the PARTICIPANT row first (organization-filtered) and re-check
`in_valutazione`, then `Evaluation::withoutGlobalScope('tenant')->lockForUpdate()->find($id)`: the same
order as `AuthorizeEvaluationRetry`, so the two never wait on each other; re-check
`pending && retry_attempt`; `CompetencyResult::withoutGlobalScope('tenant')->where('evaluation_id', $id)
->where('valid', false)->delete()` (indicator scores and audits cascade); re-stamp `model_version` and
`prompt_version` to today's configuration (owner decision 2026-10-05; `framework_version_id` stays
pinned); update `status = processing`. Then the unchanged per-competency loop re-scores only competencies with no result.
**Alternatives considered**: per-competency atomic replace with a marker column; staged DTO swap —
rejected in exploration (more code, new crash states). Trusting only the job flag — rejected: a
crash-resumed `processing` job carries no reliable flag; the row does.
**Rationale**: A11 with crash safety from the existing `processing` resume path (RT-B-O1 / A6).

### D9 — Forced `completed` in `ResolveEvaluationTerminalState`

**Choice**: `resolve()` refreshes `$evaluation->retry_attempt`; when true it skips the gate (and
therefore the ZeroCompetencies `errore` arm) and persists `EvaluationStatus::Completed`; the
participant transition and `EvaluationCompleted` are unchanged. The gate result is still logged
(`valid_count`, `total_count`) for traceability.
**Alternatives considered**: computing the gate and overriding only `pending` — rejected: a retry
on a project whose composition was emptied would still reach `errore`, contradicting "the retry is
definitive".
**Rationale**: binding rule "the next evaluation is definitive `completed` even below threshold".

### D10 — `failed()` and `endParticipantUnresolvable()` on a retry finalize `completed`

**Choice**: new private `finalizeRetryWithRetainedResults(Participant)`; both `failed()` and
`endParticipantUnresolvable()` call it first when the evaluation row has `retry_attempt = true` and
status `pending|processing`. It runs the same idempotent merge as D8 if the row is still `pending`
(so the definitive result never mixes first-attempt invalid results), then
`ResolveEvaluationTerminalState::resolve()` (forced `completed`, participant `completato`,
`EvaluationCompleted`). It does not emit `EvaluationFailed` and never moves the participant to
`errore`. Wrapped in try/catch: if the finalization itself throws, the participant stays
`in_valutazione` with a `processing`/`pending` evaluation and an `error`-level log
(risk R4) — still never `errore`.
**Alternatives considered**: keep `errore` + `EvaluationFailed` — rejected (A5): the failed webhook
would collide with the dedupe key and the recovery guard would refuse; a dead end.
**Rationale**: RT-B-O2 resolved; the retry is the definitive run by rule.

### D11 — Recovery guard exception during an in-flight retry

**Choice**: `RecoverFailedParticipant` guard 1 becomes: refuse `evaluation_already_delivered` only
if an `evaluation` delivery exists **for the current attempt** — when the participant's evaluation
has `retry_attempt = true` and `status = pending`, the current attempt's delivery is the one with
`dedupe_key = '{evaluation_id}:retry'`; otherwise any evaluation delivery (unchanged). Guard 2
(an `error` session must exist) is unchanged and is what limits this to interview-stage failures.
**Alternatives considered**: a new refusal-free path for retry participants — rejected: guard 2
already discriminates interview-stage from scoring-stage failures.
**Rationale**: an interview-stage `errore` during the re-interview (`in_attesa|in_corso -> errore`)
stays recoverable; once recovered, a new link comes from the unchanged operator entry-link or M2M
sso-link mints (the participant is `in_attesa`).

### D12 — Webhook dedupe keys derived from the evaluation row

**Choice**: `SendEvaluationWebhook::handleCompleted()` uses `"{$evaluation->id}:retry"` when
`$evaluation->retry_attempt` is true, else `"{$evaluation->id}"` (unchanged).
`SendProgressWebhook::handleCompetencyEnded()` appends `:retry` when an evaluation row exists for
the participant with `retry_attempt = true` (read `withoutGlobalScope('tenant')` filtered by the
already-resolved organization id). Before the first scoring there is no evaluation row, so first-
attempt progress keys are unchanged. `handleFailed()` is unchanged (unreachable on a retry after
D10). No payload shape change: the definitive webhook is told apart by status `completed` and its
own delivery id (A2; no new public field, so T-EXPOSE-001 is untouched by the webhook).
The unique index `(organization_id, project_id, event_type, dedupe_key)`
(`2026_07_27_000001_create_webhook_deliveries_table.php:103`) needs no migration; `:retry` keys are
distinct values.
**Alternatives considered**: a new `evaluation_retry` event type — rejected (A2): integrators would
need a new handler for the same payload. A per-attempt counter key — rejected: exactly one retry.
**Rationale**: SA-07 requires two distinct evaluation delivery rows.

### D13 — Retry email: same job and notification, a `kind` parameter

**Choice**: `SendCandidateInvitationJob` gains a trailing `CandidateInvitationKind $kind =
CandidateInvitationKind::Initial` scalar (enum `Initial|Retry`, string-backed so it serializes);
`CandidateInvitationNotification` selects `candidate_invitation.retry.subject` and
`candidate_invitation.retry.intro` for `Retry`, reusing every other line (requirements, action,
URL fallback, expiry). Copy lives in `api/lang/{it,en}/candidate_invitation.php` under `retry`,
static, not tenant-editable (ruling 10); tenant chrome via the existing `EmailBranding`. No email is
queued for a placeholder address (D-B) **or a reusable-link visitor row**
(`reusable_interview_link_id !== null`), matching `EntryLinkController:269-278`; the job keeps its
own placeholder refusal.
**Alternatives considered**: a separate `CandidateRetryInvitationNotification` class — rejected:
duplicates the requirements/URL-fallback/expiry body that must never drift from the invitation.
**Rationale**: ruling 10 compliance with the smallest diff; the visitor rule is the existing policy
for unverified addresses (flag for spec alignment, risk R8).

### D14 — Admin read state: `retry` block on the participant detail only

**Choice**: `Admin\ParticipantDetailResource` gains
three FLAT fields (consistency report I4: the specs won over the nested `retry` block this design first
described): `retry_attempt` (bool), `retry_authorized_at` (ISO-8601 or null) and `retry_available`
(`!retry_attempt` ∧ `completato` ∧ not test mode ∧ evaluation `pending`). The panel phase is derived by the
client from the literal `status`. One extra query on the participant's evaluation (org-scoped via
`TenantContext`). The docblock `@return` and `@scramble-return` move in lockstep. The evaluation read
gate is unchanged (A3). T-EXPOSE-001: three admin-only exclusion entries under `'Interview'` in
`tests/Helpers/PublicApi/ExposureCatalogue.php`, classified in the same PR (the permanent rule);
nothing is added to `/v1`, M2M or exports.
**Alternatives considered**: exposing `retry_attempt` raw — rejected: the panel needs the derived
state, and deriving it client-side would re-implement eligibility in a second repo (the
`UserAbilities` docblock's drift argument). Adding it to the list resource — rejected: not needed
for the panel; a smaller exposure surface.
**Rationale**: the panel renders without a second request; the state never carries a score.

### D15 — Backoffice panel mirrors the recovery panel

**Choice**: `backoffice/app/components/organisms/EvaluationRetryPanel.vue` +
`backoffice/app/composables/useEvaluationRetry.ts` (types from `types/api.ts` paths, like
`useParticipantRecovery.ts`). Mounted on `pages/participants/[id].vue` with a `canRetry` input derived from
`can('participants.retry')`, driven by `retry_available`, `retry_attempt`, `retry_authorized_at` and the
literal `status`; a read-only state line for the waiting, in-progress, scoring and finished phases is
shown to every role. Flow: description ->
confirm disclosure (lists the competencies that will be re-interviewed, sourced from the already
loaded sessions/evaluation; warns that their previous answers are discarded) + optional reason ->
submit -> success shows `EntryLinkPanel` (single-use branch) with `entry_url`/`expires_at` and an
`email_sent` line. 409 reasons map to `evaluationRetry.refusalReason.{reason}` via `getErrorReason`.
i18n `evaluationRetry.*` in `i18n/locales/{it,en}.json`.
**Rationale**: an operator already knows this interaction shape; zero new UI primitives.

## Data Flow

### Authorization (both surfaces)

```
Operator (backoffice)                    Calling system (M2M)
POST /api/participants/{id}/retry   POST /api/m2m/participants/{id}/retry
  auth:api + TenantContext                       auth:api-m2m + TenantContextM2m + ability:participants:retry
  authorize('retry') -> 403 viewer               orgId = ApiClient.organization_id
  orgId = TenantResolver                         |
        \____________________  _____________________/
                             \/
              AuthorizeEvaluationRetry::handle(id, orgId, actor, reason)
              TenantContextScope::runFor(orgId)
              DB::transaction
                Participant where org_id=orgId lockForUpdate findOrFail   -> 404
                Evaluation where participant_id (tenant scope)
                guards (D4)                                              -> 409 {reason}
                participant completato -> in_attesa
                ResetSessionForRetry(invalid sessions)
                evaluation.retry_attempt=true, retry_authorized_at=now
                EntryLinkMinter::mint(row values, Emailed|Returned)      -> 409 project_inaccessible (rollback)
                DB::afterCommit: SendCandidateInvitationJob(kind=Retry) unless placeholder/visitor
              (after commit) Log::info participant.retry_authorized (INTERIM) + AuditRecorder
                evaluation.retry_authorized
              <- {status, entry_url, expires_at, email_sent, competencies_reset}  200
```

### Re-interview and definitive scoring (sequence)

```
Candidate      SsoExchange      InterviewController     Settle/Finalize         DispatchScoringJob   ScoreEvaluationJob            Webhooks
   | email link (24h) |                 |                       |                        |                    |                        |
   |--GET exchange--->| step 4 exempt (sessions exist), jti consume, status in_attesa OK, upsert no-op
   |<--candidate JWT--|                 |                       |                        |                    |                        |
   |--/start---------------------------->| next pending competency (variant 'next', no apology)
   |                  |                 | in_attesa -> in_corso |                        |                    |                        |
   |--/end (each invalid competency)---->| CompetencySessionEnded --------------------------------------------------------> progress key ...:{code}:retry
   |                  |                 | tally == total -> CAS in_corso -> in_valutazione
   |                  |                 |---------------------->| FinalizeInterview key finalize:{pid}:retry
   |                  |                 |                       |--ScoringRequested----->| reads retry_attempt=true
   |                  |                 |                       |                        |--dispatch(pid, true)->|
   |                  |                 |                       |                        |   lock eval; pending&&retry -> delete valid=false; status=processing
   |                  |                 |                       |                        |   resume-skip loop scores missing competencies
   |                  |                 |                       |                        |   Resolve: forced completed; in_valutazione -> completato
   |                  |                 |                       |                        |   EvaluationCompleted --------------------> evaluation key {eval_id}:retry
   |                  |                 |                       |                        |   (failed(): same finalize, never errore)
```

### Explicit query scopes (multi-tenancy, `openspec/config.yaml` rules.design)

| Query | Scope mechanism |
|---|---|
| Action participant load | `Participant::where('organization_id', $orgId)->lockForUpdate()->findOrFail()` (plain model, explicit filter) |
| Action evaluation / sessions / results | `TenantModel` global scope under `TenantContextScope::runFor($orgId)` + `participant_id` of the org-filtered row |
| Action project | `$participant->project()` under the same tenant scope |
| Operator controller org | `TenantResolver::getOrgId()` set by `TenantContext` |
| M2M controller org | `ApiClient::organization_id` of the authenticated client |
| `FinalizeInterview` flag read | `Evaluation::withoutGlobalScope('tenant')->where('organization_id', $this->organizationId)` |
| `DispatchScoringJob` flag read | same, with `$event->organizationId` |
| Job merge | `withoutGlobalScopes()` by `evaluation_id` inside the job's existing `TenantContextScope::runFor($orgId)` (unchanged job pattern) |
| `SendProgressWebhook` flag read | `withoutGlobalScope('tenant')` + organization id from `resolveOrganizationId()` |
| `RecoverFailedParticipant` retry check | tenant scope of the request (unchanged action pattern) |
| Detail resource retry state | tenant scope via `TenantContext` |

## File Changes

| File | Action | Slice | Description |
|---|---|---|---|
| `CLAUDE.md` (wrapper) | Modify | PR0w | Amend SSO ingress rule: signed single-use token; returned links 30 min; emailed invitation links config-driven, default 24 h |
| `docs/app_description/04-integration-surface/01-sso-ingress.md` | Modify | PR0w | Same amendment in the domain doc |
| `api/config/candidate_invitations.php` | Create | PR0 | `emailed_link_ttl_minutes` (env, default 1440) |
| `api/app/Support/Sso/LinkDelivery.php` | Create | PR0 | `Returned|Emailed` enum |
| `api/app/Support/Jwt/CandidateTokenFactory.php` | Modify | PR0 | `mintSsoLink(..., int $ttlMinutes = SSO_LINK_TTL_MINUTES)` |
| `api/app/Support/Sso/EntryLinkMinter.php` | Modify | PR0 | `LinkDelivery` param, visitor downgrade, TTL resolution, range check |
| `api/app/Support/Sso/MintedEntryLink.php` | Modify | PR0 | `delivery` property |
| `api/app/Http/Controllers/Api/EntryLinkController.php` | Modify | PR0 | pass channel; `email_sent` from `$minted->delivery` |
| `api/app/Console/Commands/DispatchScheduledInterviewInvitations.php` | Modify | PR0 | pass `Emailed` |
| `api/app/Notifications/CandidateInterviewNoticeNotification.php` | Modify | PR0 | docblock: 24 h, not 30 min |
| `api/.env.example` | Modify | PR0 | `CANDIDATE_INVITATION_LINK_TTL_MINUTES=1440` |
| `api/database/migrations/2026_10_xx_add_retry_authorized_at_to_evaluations.php` | Create | PR1 | nullable `retry_authorized_at` timestamp (reversible) |
| `api/app/Models/Evaluation.php` | Modify | PR1 | fillable + datetime cast |
| `api/app/Models/Participant.php` | Modify | PR1 | `completato => ['in_attesa']` + docblock |
| `api/app/Actions/Participant/AuthorizeEvaluationRetry.php` | Create | PR1 | the action (D4) |
| `api/app/Actions/Participant/RetryAuthorization.php`, `RetryActor.php` | Create | PR1 | result DTO, actor value object |
| `api/app/Exceptions/Participant/EvaluationRetryRefused.php`, `EvaluationRetryRefusalReason.php` | Create | PR1 | typed refusal |
| `api/tests/Arch/RetryEdgeWriterArchTest.php` | Create | PR1 | single-writer guard for the edge |
| `api/app/Jobs/FinalizeInterview.php` | Modify | PR2a | attempt-scoped key (D7) |
| `api/app/Listeners/DispatchScoringJob.php` | Modify | PR2a | pass `retryAttempt` from DB |
| `api/app/Jobs/ScoreEvaluationJob.php` | Modify | PR2a/PR2b | retry branch + merge (2a); `failed()`/unresolvable retry finalize, A6 no-op (2b) |
| `api/app/Actions/Scoring/ResolveEvaluationTerminalState.php` | Modify | PR2a | forced `completed` |
| `api/tests/.../ScoreEvaluationJobDefensiveBranchesTest.php` | Modify | PR2a | replace the stub pin (`:794`) |
| `api/app/Listeners/SendEvaluationWebhook.php`, `SendProgressWebhook.php` | Modify | PR2b | `:retry` dedupe keys |
| `api/app/Actions/Participant/RecoverFailedParticipant.php` | Modify | PR2b | guard 1 retry exception |
| `api/app/Jobs/SendCandidateInvitationJob.php`, `api/app/Notifications/CandidateInvitationNotification.php` | Modify | PR3a | `CandidateInvitationKind` |
| `api/app/Support/Mail/CandidateInvitationKind.php` | Create | PR3a | enum |
| `api/lang/{it,en}/candidate_invitation.php` | Modify | PR3a | `retry.subject`, `retry.intro` |
| `api/app/Actions/Participant/AuthorizeEvaluationRetry.php` | Modify | PR3a | afterCommit email dispatch |
| `api/app/Http/Resources/Admin/ParticipantDetailResource.php` | Modify | PR3a | `retry` block (D14) |
| `api/tests/Helpers/PublicApi/ExposureCatalogue.php` | Modify | PR3a | `retry.state`, `retry.authorized_at` exclusions |
| `api/app/Http/Controllers/Api/EvaluationRetryController.php` | Create | PR3b | operator surface |
| `api/app/Http/Controllers/M2m/EvaluationRetryController.php` | Create | PR3b | M2M surface |
| `api/routes/api.php` | Modify | PR3b | two routes |
| `api/app/Policies/ParticipantPolicy.php` | Modify | PR3b | `retry()` |
| `api/app/Support/Authorization/UserAbilities.php` | Modify | PR3b | `participants.retry` |
| `api/config/m2m_abilities.php` | Modify | PR3b | `participants:retry` |
| `api/tests/Helpers/AuthMatrix/AuthMatrixCatalogue.php` | Modify | PR3b | both routes |
| `api/openapi.json` | Regenerate | PR3a/PR3b | Scramble export against Postgres (generated, excluded from the budget) |
| `backoffice/openapi.json`, `backoffice/types/api.ts` | Regenerate | PR4a | from the released api spec (generated) |
| `backoffice/app/composables/useEvaluationRetry.ts` | Create | PR4a | typed write |
| `backoffice/app/components/organisms/EvaluationRetryPanel.vue` | Create | PR4a | panel (D15) |
| `backoffice/i18n/locales/{it,en}.json` | Modify | PR4a | `evaluationRetry.*` |
| `backoffice/tests/unit/components/organisms/EvaluationRetryPanel.spec.ts` | Create | PR4a | Vitest |
| `backoffice/app/pages/participants/[id].vue` | Modify | PR4b | mount + state line |
| `backoffice/app/utils/analytics-path.ts` | Modify | PR4b | normalize the new path if the module enumerates write paths (verify) |
| `backoffice/tests/e2e/participant-evaluation-retry.spec.ts` | Create | PR4b | Playwright (Chromium + WebKit) |
| `frontend/openapi.json` (+ generated types) | Regenerate | PR4f | generated only; 0 authored lines |
| `openspec/specs/*` (promotion), `CLAUDE.md` ruling 4, `openspec/ROADMAP.md:72` + decisions 8/9 (A14), `docs/app_description/05-business-rules/01-candidate-lifecycle.md` | Modify | PR5 | docs + submodule pins |

## Interfaces / Contracts

```php
// api/app/Support/Sso/LinkDelivery.php
enum LinkDelivery: string { case Returned = 'returned'; case Emailed = 'emailed'; }

// EntryLinkMinter
public function mint(Project $project, string $candidateRef, string $displayName, string $email,
    ?string $roleCode, ?string $lang, ExternalReference $externalReference = new ExternalReference,
    LinkDelivery $delivery = LinkDelivery::Returned): MintedEntryLink;

// CandidateTokenFactory
public static function mintSsoLink(array $claims, int $ttlMinutes = self::SSO_LINK_TTL_MINUTES): string;

// api/app/Exceptions/Participant/EvaluationRetryRefusalReason.php
enum EvaluationRetryRefusalReason: string {
    case RetryAlreadyConsumed = 'retry_already_consumed';
    case NotCompleted = 'not_completed';
    case TestModeParticipant = 'test_mode_participant';
    case EvaluationNotPending = 'evaluation_not_pending';
    case ProjectInaccessible = 'project_inaccessible';
}

// api/app/Actions/Participant/RetryActor.php
final readonly class RetryActor {
    private function __construct(public string $type, public ?int $userId, public ?int $apiClientId) {}
    public static function user(?int $userId): self;
    public static function apiClient(int $apiClientId): self;
}

// api/app/Actions/Participant/AuthorizeEvaluationRetry.php
/** @throws ModelNotFoundException (404) @throws EvaluationRetryRefused (409) */
public function handle(int $participantId, int $organizationId, RetryActor $actor, ?string $reason): RetryAuthorization;

// RetryAuthorization
final readonly class RetryAuthorization {
    /** @param list<string> $competenciesReset */
    public function __construct(public string $status, public string $entryUrl,
        public Carbon $expiresAt, public bool $emailSent, public array $competenciesReset) {}
}
```

HTTP (both surfaces):

```
POST /api/participants/{id}/retry      (auth:api, admin|operator)
POST /api/m2m/participants/{id}/retry             (auth:api-m2m, ability participants:retry)
Body:  { "reason": string|null (max 500) }
200:   { "status": "in_attesa", "entry_url": string, "expires_at": ISO-8601,
         "email_sent": bool, "competencies_reset": string[] }
409:   { "reason": "retry_already_consumed"|"not_completed"|"test_mode_participant"
                   |"evaluation_not_pending"|"project_inaccessible" }
403:   viewer / missing ability          404: unknown or other-tenant id          422: validation
```

Admin detail addition (flat): `retry_attempt: bool`, `retry_authorized_at: string|null`,
`retry_available: bool`.

Webhook dedupe keys: evaluation `"{evaluation_id}"` (first) / `"{evaluation_id}:retry"` (definitive);
progress `"competency-ended:{participant_id}:{code}"` / `"...:{code}:retry"`; creation unchanged.

## Testing Strategy

TDD per `openspec/config.yaml` (RED first). Correctness-critical (~95%): the action, the job retry
branch, `ResolveEvaluationTerminalState`, `failed()`, the transition map.

| Layer | What to test | Approach |
|---|---|---|
| Unit (Pest) | Transition map: `completato -> in_attesa` allowed; `completato -> {in_corso, in_valutazione, errore}` refused; existing edges unchanged | dataset over the full from/to matrix |
| Arch (Pest) | The edge is written only by `AuthorizeEvaluationRetry`; no `Participant::` literal in new `Api` controller | `RetryEdgeWriterArchTest`, existing `AdminTenancySafetyArchTest` |
| Feature (PR0) | TTL per channel: operator emailed = config (assert `exp - iat`), `send_email=false` = 30, placeholder = 30 + `email_sent=false`, visitor = 30, sweep = config, M2M sso-link = 30, reusable redemption = 30; config outside `[15,10080]` throws; exchange accepts at TTL-1 min and refuses at TTL+1 min; `SsoLinkRegressionPinsTest` constant still 30 | `travel()` + JWT payload decode |
| Feature (PR1) | Happy path (flip, only invalid sessions reset, utterances of valid sessions intact, results untouched, flag + timestamp set, link minted with row values); each refusal reason; refusal order (`retry_already_consumed` first); project closed -> 409 and full rollback (status still `completato`, flag false); cross-tenant id 404 with no write; interim log shape has no PII | factories + `Log::spy()` |
| Concurrency (PR1) | Two authorizations: second gets `retry_already_consumed`; only one link minted | sequential calls after the first commit + a lock-contention test using two connections where the suite supports it |
| Feature (PR2a) | Merge deletes only `valid=false` results; valid results byte-identical; evaluation row id unchanged; forced `completed` below 90%; `processing + retry_attempt` resumes and forces `completed`; stray job while `in_attesa` no-op; flag-without-DB no-op; FinalizeInterview within 2 h of the first run is not dropped (`finalize:{pid}` held, `:retry` free); DispatchScoringJob passes the flag | queue fakes + cassette LLM provider |
| Feature (PR2b) | `failed()` on retry -> evaluation `completed`, participant `completato`, `EvaluationCompleted` emitted, no `EvaluationFailed`, never `errore`; failure before merge also merges; `completed + retry_attempt` no-op; two evaluation delivery rows (`{id}` and `{id}:retry`) for one evaluation; retry progress rows distinct from first-attempt rows; recovery during an in-flight retry succeeds; recovery after the `:retry` delivery refused | `Event::fake` selectively; real recorder for dedupe collisions |
| Feature (PR3a) | Email queued with `kind=Retry` and the retry subject in it/en; not queued for placeholder or visitor (`email_sent=false`); detail `retry.state` for all four states; ExposureTest passes with the two exclusions; re-interview first competency uses variant `next` (no apology) | `Queue::fake`, `Notification::fake` |
| Feature (PR3b) | Authorization matrix: admin/operator 200, viewer 403 (before 404 on foreign id), M2M with ability 200, without ability 403, cross-tenant 404 on both surfaces; 409 mapping per reason; response shape; `UserAbilities.participants.retry`; OpenAPI export diff clean | `AuthMatrixCatalogue` + dedicated feature tests |
| E2E SA-07 (api) | First interview -> `pending` webhook -> authorize -> exchange -> re-interview invalid competencies only -> second `evaluation` webhook `completed` with distinct delivery id | one end-to-end feature test driving controllers with the fake provider |
| Unit (Vitest) | Panel: hidden without ability; confirm disclosure lists competencies; reason trimmed/null; success renders `EntryLinkPanel` + email line; each 409 reason maps to its i18n key; composable path/body | Vue Test Utils with mocked `useApi` |
| E2E (Playwright) | Admin authorizes a retry and sees the link; viewer sees no button; state line for `in_progress` | mocked API routes, Chromium + WebKit |

## Threat Matrix

N/A — no shell, subprocess, VCS/PR automation, executable-file classification, or
process-integration boundary. (New HTTP routes are covered by the authorization matrix, tenant
isolation tests and the TTL tests above, not by this agent-process matrix.)

| Boundary | Applicability |
|---|---|
| Documentation-like paths | N/A: no file classification or execution |
| Git repository selection | N/A: no git automation |
| Commit state | N/A: no git automation |
| Push state | N/A: no git automation |
| PR commands | N/A: no PR automation |

## Migration / Rollout

**Slice plan (auto-chain; authored lines incl. tests; generated `openapi.json`/`types/api.ts` excluded)**

| Order | Slice | Repo | Content | Estimate |
|---|---|---|---|---|
| 1 | PR0w | wrapper | `CLAUDE.md` SSO rule amendment + `01-sso-ingress.md` | ~25 |
| 2 | PR0 | api | D1 (24 h emailed links) + tests; independently releasable (patch/minor) | ~290 |
| 3 | PR1 | api | migration, edge, refusal types, DTOs, action without email (D2/D4/D5), arch + feature tests | ~390 |
| 4 | PR2a | api | D7, D8, D9, dispatch flag, stub-test replacement | ~330 |
| 5 | PR2b | api | D10, A6, D11, D12 + dedupe-collision tests | ~300 |
| 6 | PR3a | api | D13 email + afterCommit dispatch, D14 detail state + ExposureCatalogue, A10 regression test (still dark) | ~280 |
| 7 | PR3b | api | D6 controllers, routes, policy, abilities, M2M ability, AuthMatrix, SA-07 e2e test, OpenAPI export (**switches the feature on**) | ~360 |
| 8 | PR4a | backoffice | regenerated client, composable, panel, i18n, Vitest | ~340 |
| 9 | PR4b | backoffice | page wiring, abilities usage, Playwright | ~150 |
| 10 | PR4f | frontend | regenerated `openapi.json`/types only | 0 authored |
| 11 | PR5 | wrapper | spec promotion, ruling 4 RATIFIED, ROADMAP (+A14), lifecycle doc, submodule pins | ~120 |

PR1 sits closest to the budget (400-line budget risk: Medium); if it overruns, the arch test and
DTOs move to a PR1b without changing order. Every api slice before PR3b is dark (no route reaches
the action). Release order follows "api first": the api release carrying PR3b bumps
`openapi.json` `info.version`; backoffice and frontend regenerate from that release in their own
patches; the wrapper pins the released tags in PR5. PR0w merges before PR0 because `CLAUDE.md`
is binding and PR0 would otherwise contradict it.

**Migration**: one additive nullable column (`evaluations.retry_authorized_at`); reversible. No
backfill. No webhook index change. Deploy note for PR2a: `FinalizeInterview`'s constructor is
unchanged, so no queue drain is required.

**Rollback**:
- PR0: revert restores 30-minute emailed links; links already emailed keep their 24 h `exp`
  (the token is self-describing) and still exchange — harmless.
- PR1..PR3a: dark; revert the merge commit and re-release.
- To stop the feature: revert PR3b (routes, ability, policy) and PR4b; no new authorizations occur.
- **Do not revert PR2a/PR2b while any participant is mid-retry** (`retry_attempt = true` and
  participant not `completato`). Reverting PR2a would turn their scoring into a no-op (stub) and
  leave them `in_valutazione` with a `pending` evaluation; reverting PR2b would let a retry
  completion webhook collide with the first `{evaluation_id}` row and be swallowed. Check with
  `select count(*) from evaluations e join participants p on p.id = e.participant_id
  where e.retry_attempt and p.status <> 'completato'` before reverting either.
- Delivery rows written under `:retry` keys remain valid history.

## Risks

| ID | Risk | Mitigation |
|---|---|---|
| R1 | PR1 at ~390 lines is near the 400 budget | pre-planned PR1b split point (arch test + DTOs) |
| R2 | D-C + A3 together: a candidate who never re-interviews leaves the participant `in_attesa` forever, so the `pending` evaluation becomes **unreadable in the backoffice forever** (read gate is `completato`), and the reset competencies' utterances are already deleted | flag to owner/spec; a later change could admit evaluation reads for `retry_attempt ∧ in_attesa`; not in scope |
| R3 | Route naming differed between spec and design | RESOLVED: `/api/participants/{id}/retry` everywhere |
| R4 | `failed()` finalization itself throws (DB outage) -> participant stuck `in_valutazione` | error log; a re-dispatch resumes via the `processing` path; never `errore` |
| R5 | Mid-retry participant shown as not completed in public `/v1` status, usage counters and dashboards (status regresses `completed -> pending`-equivalent) | documented; the public `/v1` retry surface is deferred (A4) and should define this when it lands |
| R6 | A first-attempt candidate JWT (< 120 min old) still works after the flip | same participant and authority as the new link; identical to the recovery precedent; documented |
| R7 | Interim log vs ratified audit log: `App\Support\Audit\AuditRecorder` (C13) **already exists** and is used by newer actions (`CreateReusableInterviewLink`, `EvaluationAuditController`); A8 predates it | RESOLVED (Q1): the action writes both the interim log line and the audit row, after commit |
| R8 | Visitor rows receive no retry email (D13) — not stated in D-B | consistent with the existing unverified-address rule; confirm in spec |
| R9 | Production mail is broken pending Resend domain verification | link always returned to the authorizer (D-B) |
| R10 | Competency composition edited between attempts: invalid set uses the current composition; retained valid results of detached competencies remain on the evaluation | same behaviour as the gate's `count_unscorable_against_total` denominator; documented |

## Open Questions

- [x] Q1 (RESOLVED: yes, an `audit_logs` row `evaluation.retry_authorized`, written after commit) — A8 says "interim log only, ratified audit log out of scope", but the ratified writer
  `AuditRecorder` already exists in code. Should the action also write an `audit_logs` row
  (`evaluation.retry_authorized`, ~6 lines)? Non-blocking: the design ships the interim log.
- [x] Q2 (RESOLVED by the owner: accepted; the evaluation stays unreadable during a retry and the reset competencies' answers are deleted at authorization) — R2: accept that a never-taken retry makes the pending evaluation unreadable in the
  backoffice, or admit evaluation reads while `retry_attempt ∧ in_attesa`? Non-blocking for PR0..PR3.
- [x] Q3 (RESOLVED: owner-confirmed wording, applied to `CLAUDE.md` and `openspec/ROADMAP.md` in the docs slice) — Ruling 4 wording at archive (proposal Q2), now also mentioning the 24 h emailed link.

## Reconciliation As Built (recorded 2026-10-06, docs slice of PR5)

The sections above describe the design as planned. Where code, tasks or owner resolutions
differ, this list is authoritative; every row was confirmed against api `origin/develop`.

| Topic | Planned | As built |
|---|---|---|
| Retry link lifetime | "always 24 h" (specs) | 24 h ONLY when BEAI emails the link; 30 min when only returned (placeholder or purged address, reusable-link visitor) (I9) |
| Interim log and audit | log inside the transaction, no audit row | log line `participant.retry_authorized` AND audit row `evaluation.retry_authorized`, both after commit, failures reported and swallowed (I1, I2, I3) |
| AuditRecorder actor | assumed `Auth::user()` was always a user | only a `User` is recorded as `actor_id`; the M2M client id travels in the payload (fixed in PR3b) |
| Lock order | participant lock in the action only | participant row first, Evaluation second, in both the action and the job's retry merge |
| Retry flag source | job payload (specs) | the Evaluation row; the payload is a hint (I10) |
| Finalize dedup | released after commit (specs) | attempt-scoped key `finalize:{pid}:retry`, the action never touches the cache (I6, D7) |
| Refusals | 4 reasons (specs) | 5 reasons in the order `retry_already_consumed`, `not_completed`, `test_mode_participant`, `evaluation_not_pending`, `project_inaccessible` (I7) |
| Response | `{entry_url, expires_at, email_sent}` | adds `status` and `competencies_reset` (I8) |
| Admin read | nested `retry` block | flat `retry_attempt`, `retry_authorized_at`, `retry_available`; the flag also excludes test mode (I4) |
| Re-stamp | not listed | the merge re-stamps `model_version` and `prompt_version`; `framework_version_id` stays pinned |
| Opening | no production code (A10) | new `reinterview` variant, precedence `resume` > `retry` > `reinterview` > `first` > `next` (I5, I12) |
| `failed()` finalization | idempotent merge then resolve | resolve runs inside one transaction; a stray job for a participant not at `in_valutazione` is a logged no-op |
| Route | `/participants/{id}/retry` | as designed, on both surfaces; the M2M operation also documents 403 |
| Atomicity wording | "single transaction" merge | atomic only for delete-and-flip; re-scoring follows on the resume-skip path |
