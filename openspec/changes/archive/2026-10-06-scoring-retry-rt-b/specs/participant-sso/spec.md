# Delta for Participant SSO

Two independent concerns live in this delta:

1. **Prerequisite slice PR0 — emailed invitation link lifetime.** Owner decision of
   2026-10-05 (overrides proposal assumption A1): every candidate invitation link that BEAI
   delivers BY EMAIL — the initial invitation, the scheduled-start sweep and the RT-B retry link
   WHEN BEAI emails it — lives 24 hours. A link that is only RETURNED to a caller (the M2M mint,
   an operator mint with no email, and a retry link for a placeholder address or a reusable-link
   visitor, where no email is sent) stays at 30 minutes: the lifetime follows the delivery
   channel, never the kind of link (owner resolution I9, which overrides the earlier "the retry
   link is always 24 hours"). This amends the binding `CLAUDE.md` rule "SSO ingress: non-forgeable
   signed token, short expiry (15–60 min)" for emailed links only. The retry slices depend on PR0.
2. **RT-B retry authorization** — the shared action, its guards, authorization, link, email
   trigger, audit row and interim log, the recovery-guard exception and the lifecycle edge.

## MODIFIED Requirements

### Requirement: Participant Model Lifecycle Guard

The `Participant` model MUST expose a transition-guard backstop in `booted()` that
rejects status transitions outside the defined state machine. Illegal transitions MUST
throw a `ParticipantTransitionException` (domain exception), which MUST be registered
in `bootstrap/app.php` to render HTTP 422. It MUST NOT throw a bare `RuntimeException`
(which would yield HTTP 500). This mirrors `ImmutableProjectException`/
`LockedFrameworkVersionException` from C4.

C6 MUST only write `in_attesa`; no other status transition may be triggered by C6 code.

The transition map additionally permits exactly two further edges: `errore =>
['in_attesa']` and `completato => ['in_attesa']`. The `errore` edge MUST be written ONLY
by the dedicated recovery action (see Requirement: Atomic Participant and Session Recovery
from Errore). The `completato` edge MUST be written ONLY by the evaluation-retry
authorization action (see Requirement: Evaluation Retry Authorization Action). Each runs
under its own authorization, locking, and refusal guards — no other write path may trigger
either edge. `errore => in_corso`, `errore => in_valutazione`, `completato => errore`,
`completato => in_corso` and `completato => in_valutazione` remain illegal.
(Previously: `completato` was terminal with no outbound edge.)

#### Scenario: New participant starts in in_attesa

- GIVEN the exchange endpoint creates a participant
- WHEN the record is first inserted
- THEN `status` is `in_attesa`
- AND `started_at` and `completed_at` are null

#### Scenario: Transition guard rejects illegal jump — throws domain exception

- GIVEN a `Participant` with `status = in_attesa`
- WHEN code attempts to set `status = completato` directly (bypassing normal flow)
- THEN `ParticipantTransitionException` is thrown
- AND the model guard renders HTTP 422 (NOT 500)
- AND the record is not mutated

#### Scenario: C6 never sets status beyond in_attesa

- GIVEN the full C6 code path executes (mint → exchange → upsert → session)
- WHEN all operations complete
- THEN no `Participant` record has a status other than `in_attesa`

#### Scenario: errore recovers to in_attesa only via the recovery action

- GIVEN a `Participant` at `status = errore`
- WHEN the recovery action transitions it to `in_attesa`
- THEN the guard permits the write
- AND no other code path setting `status = in_attesa` on an `errore` participant is
  permitted

#### Scenario: errore still cannot jump directly to in_corso or in_valutazione

- GIVEN a `Participant` at `status = errore`
- WHEN code attempts `status = in_corso` or `status = in_valutazione` directly
- THEN `ParticipantTransitionException` is thrown

#### Scenario: completato returns to in_attesa only via the retry authorization action

- GIVEN a `Participant` at `status = completato`
- WHEN the evaluation-retry authorization action transitions it to `in_attesa`
- THEN the guard permits the write
- AND any other code path writing `status = in_attesa` on a `completato` participant
  (SSO exchange, entry-link mints, recovery action, scoring job) is rejected with
  `ParticipantTransitionException`

#### Scenario: completato cannot move to errore, in_corso or in_valutazione

- GIVEN a `Participant` at `status = completato`
- WHEN code attempts `status = errore`, `in_corso` or `in_valutazione`
- THEN `ParticipantTransitionException` is thrown and the record is not mutated

### Requirement: No Revocation Semantics

Minting a new entry link for a participant MUST NOT invalidate any previously
minted, unexpired entry link for that same participant. There is no mechanism
that consumes a jti before its own exchange or expiry; each minted link remains
independently valid until it is either exchanged once or its own TTL elapses (30 minutes
for a link that is not delivered by email; the configured invitation lifetime, 24 hours by
default, for an emailed invitation link — see Requirement: Emailed Invitation Links Live
24 Hours).
(Previously: "its 30-minute TTL" for every link.)

This requirement governs single-use sso-link entry links only. Reusable interview
links are a separate mechanism with their own explicit Disable semantics
(capability `reusable-interview-links`); creating or disabling a reusable link
changes nothing about how any sso-link behaves.

An authorized retry mints a NEW link and likewise revokes nothing: an earlier, unexpired,
unexchanged link of the same participant stays redeemable until its own expiry.

#### Scenario: A superseded link remains valid until its own expiry

- GIVEN an entry link minted for a participant, not yet exchanged or expired
- WHEN a new entry link is minted for the same participant
- THEN the previous link's token can still be exchanged successfully until its
  own `expires_at`, unless it is exchanged first

#### Scenario: Disabling a reusable link does not revoke any sso-link

- GIVEN an unexpired, unexchanged sso-link for a participant of project P and a reusable
  link on P
- WHEN the reusable link is disabled
- THEN the sso-link can still be exchanged successfully

#### Scenario: Minting an sso-link does not disable a reusable link

- GIVEN an enabled reusable link on project P
- WHEN an sso-link is minted for a participant of P
- THEN the reusable link still redeems successfully

#### Scenario: A retry link does not revoke an earlier invitation link

- GIVEN an unexpired, unexchanged invitation link for participant P
- WHEN a retry is authorized for P and a retry link is minted
- THEN both links remain exchangeable, each at most once, until their own expiry

### Requirement: Recovery Refusal Guards

Recovery MUST be refused with HTTP 409, evaluated inside the transaction before any
write, guard 1 first:

1. `evaluation_already_delivered` — a `WebhookDelivery` row exists for the participant
   with `event_type = evaluation`, EXCEPT while an evaluation retry is in progress (the
   participant's `Evaluation` is `pending` with `retry_attempt = true`): the first run's
   delivered `pending` evaluation webhook MUST NOT make an interview-stage `errore` of the
   re-interview unrecoverable. No scoring-stage failure ever leaves an `error` session
   (scoring runs only once every session is `completed`), so this is the sole detection
   rule needed for scoring-stage refusal.
2. `nothing_to_recover` — no `InterviewSession` of the participant is at `status =
   error`.

After the guards, status is re-read inside the lock:

| In-lock status | Result |
|---|---|
| `errore` | Proceed |
| `in_attesa` | HTTP 200, idempotent no-op |
| any other status | HTTP 409 `not_failed` |

(Previously: guard 1 had no retry-in-progress exception, so a participant that failed
during the re-interview of an already-delivered `pending` evaluation could never be recovered.)

#### Scenario: Evaluation already delivered refuses recovery

- GIVEN a participant with a `WebhookDelivery` row where `event_type = evaluation`
- AND no evaluation retry is in progress
- WHEN recovery is called
- THEN HTTP 409 `reason: "evaluation_already_delivered"` is returned
- AND no field is modified

#### Scenario: A failure during the retry re-interview stays recoverable

- GIVEN a participant at `errore` whose `Evaluation` is `pending` with `retry_attempt = true`
  and a first-run `evaluation` delivery row
- AND one `InterviewSession` at `status = error`
- WHEN recovery is called
- THEN the recovery proceeds and the participant returns to `in_attesa`

#### Scenario: The exception does not apply once the retry has been scored

- GIVEN a participant whose `Evaluation` is `completed` with `retry_attempt = true`
- WHEN recovery is called
- THEN HTTP 409 `reason: "evaluation_already_delivered"` is returned

#### Scenario: No errored session refuses recovery

- GIVEN a participant at `errore` with no `error` session
- WHEN recovery is called
- THEN HTTP 409 `reason: "nothing_to_recover"` is returned

#### Scenario: Concurrent recovery is idempotent

- GIVEN two operators call recover for the same `errore` participant nearly
  simultaneously
- WHEN both are processed
- THEN exactly one performs the reset and returns 200
- AND the second observes `in_attesa` inside its own lock and returns 200 with no
  second utterance deletion

#### Scenario: A live participant cannot be recovered

- GIVEN a participant at `in_corso`, `in_valutazione`, or `completato`
- WHEN recovery is called
- THEN HTTP 409 `reason: "not_failed"` is returned

## ADDED Requirements

### Requirement: Emailed Invitation Links Live 24 Hours

Every candidate invitation link that BEAI delivers by email MUST be a single-use,
HS256-signed `typ:sso-link` token (same mint, claims, jti single-consumption and exchange
steps as today) whose lifetime is a single configuration value, default **1440 minutes
(24 hours)**. This applies to exactly:

1. the initial invitation link sent by the transactional invitation email — both the
   operator entry-link mint when the invitation email is queued, and the scheduled-start
   invitation sweep; and
2. the RT-B retry link, but ONLY when the retry email is queued (a real address, and the
   participant was not created by a reusable interview link; see Requirement: Evaluation Retry
   Authorization Action). A retry link that is only returned lives 30 minutes.

The `expires_at` returned by the mint and the expiry shown in the email MUST be derived from
the token's own `exp` claim, never recomputed, so they cannot drift from what the token carries.

The 24-hour lifetime applies ONLY to links BEAI emails. The following MUST be unchanged:
the M2M mint `POST /api/m2m/sso-link` (30 minutes — the calling system delivers that link),
an operator entry-link mint for which no invitation email is queued (send_email false,
placeholder address, reusable-link visitor), a retry link for which no retry email is queued
(placeholder or purged address, reusable-link visitor), the candidate JWT (120 minutes), reusable
interview links, the public-API session token, and every access, refresh and password-reset
token. Single-use consumption MUST be unchanged: the first successful exchange consumes the
jti and any replay returns 401, and the consumed-jti record MUST persist at least until
the token's `exp` (so a 24-hour token cannot be replayed within its lifetime).
(Previously: every sso-link lived exactly 30 minutes.)

#### Scenario: An emailed initial invitation link lives 24 hours

- GIVEN `POST /api/entry-links` with an email address that will be mailed
- WHEN the link is minted and the invitation email is queued
- THEN the token's `exp - iat` equals the configured invitation lifetime (default 24 hours)
- AND the response `expires_at` equals the token's `exp`
- AND the emailed expiry label matches that `exp`

#### Scenario: A scheduled-start invitation link lives 24 hours

- GIVEN a scheduled interview whose start is due
- WHEN the sweep mints the link and queues the invitation email
- THEN the token's `exp - iat` equals the configured invitation lifetime

#### Scenario: The M2M mint stays at 30 minutes

- GIVEN a valid `POST /api/m2m/sso-link` request
- WHEN the link is minted
- THEN `exp - iat` is 30 minutes and the response contract is byte-identical to before

#### Scenario: An operator mint that queues no email stays at 30 minutes

- GIVEN `POST /api/entry-links` with `send_email = false`, or a placeholder address, or a
  reusable-link-visitor target
- WHEN the link is minted
- THEN `exp - iat` is 30 minutes and `email_sent` is false

#### Scenario: A retry link that BEAI does not email stays at 30 minutes

- GIVEN a retry authorized for a participant whose address is a placeholder, or who was created
  by a reusable interview link
- WHEN the retry link is minted
- THEN `exp - iat` is 30 minutes and `email_sent` is false

#### Scenario: A 24-hour link is still single-use

- GIVEN an emailed invitation link
- WHEN it is exchanged twice within its lifetime
- THEN the first exchange succeeds and the second returns 401

#### Scenario: An expired emailed link is refused

- GIVEN an emailed invitation link past its `exp`
- WHEN it is exchanged
- THEN the exchange returns 401 and the participant is untouched

#### Scenario: The lifetime is configuration, not code

- GIVEN the invitation lifetime configuration set to 720 minutes
- WHEN an emailed invitation link is minted
- THEN `exp - iat` is 720 minutes

### Requirement: Evaluation Retry Authorization Action

One shared action MUST authorize the single retry of a `pending` evaluation. Both HTTP
surfaces (the backoffice route and the M2M route) MUST be thin controllers over this one
action; no second implementation of the authorization decision may exist.

The action MUST run inside the tenant context of the participant's organization and inside
one `DB::transaction` holding `lockForUpdate` on the participant row, resolved scoped to the
caller's organization, with the participant status and the Evaluation re-read inside the lock
before any write. Lock order is participant row first, Evaluation row second; the scoring job's
retry merge takes the same order, so the two can never wait on each other. Inside the
transaction, after the refusal guards pass, it MUST: transition the participant `completato →
in_attesa`; reset every `InterviewSession` of an INVALID competency (the project's current
composition minus the competencies holding a valid result) to `pending` (refs, ended reason and
ended-at cleared, utterances deleted) while leaving valid competencies' sessions, utterances and
every `CompetencyResult` untouched; set the Evaluation's `retry_attempt = true` and
`retry_authorized_at`; and mint a fresh single-use link through the shared entry-link minter,
from the participant row's own values and never from request input. The link is minted INSIDE
the transaction so that a project that closed after the guards (a gate refusal from the mint,
reported as `project_inaccessible`) rolls the whole authorization back: "authorized" and "a link
exists" are atomic.

The link lifetime follows the delivery channel (owner resolution I9): it lives the 24-hour
emailed-link lifetime ONLY when BEAI emails it, that is when the participant's address is a real,
deliverable one and the participant was not created by a reusable interview link. Otherwise the
link is only returned to the authorizer and lives 30 minutes. The decision has one owner, the
entry-link minter, so the lifetime, the queued email and `email_sent` cannot disagree.

After the transaction commits the action MUST queue the retry email (under the same condition),
write the interim log line and write the audit row (see Requirement: Interim Retry Audit
Logging). The email is registered with `DB::afterCommit`, so a rolled-back authorization queues
nothing. A failure of the log sink or of the audit write is reported and swallowed: the
authorization is already committed and MUST NOT be reported to the caller as failed.

The action MUST NOT touch the `finalize:{participant_id}` trigger dedup cache: the dedup key is
attempt-scoped and read from the Evaluation row (see `interview-session`: Requirement: The
Finalize Trigger Dedup Is Attempt-Scoped For A Retry).

The success response MUST be HTTP 200 with `status` (always `in_attesa`), `entry_url` (absolute
URL), `expires_at` (ISO-8601, from the token's own `exp`), `email_sent` (boolean, true only when
a retry email was actually queued) and `competencies_reset` (the codes whose session was reset).
It MUST NOT carry the bare token. The link is minted once and is never stored, so it cannot be
re-read later. An actor of kind `user` MUST carry the authorizing user id; an authorization
without an authorizer is refused before any write.

The retry email MUST NOT be queued, and `email_sent` MUST be false, when the participant's
address is a placeholder (legacy row or purged row) or the participant was created by a
reusable interview link (self-declared, unverified address). In those cases the link is still
minted and returned to the authorizer, with the 30-minute lifetime.

#### Scenario: Successful authorization

- GIVEN a participant at `completato` whose Evaluation is `pending` with `retry_attempt = false`,
  2 invalid competencies, a real email address and an accessible project
- WHEN an authorized caller authorizes the retry
- THEN HTTP 200 is returned with `status`, `entry_url`, `expires_at`, `email_sent: true` and
  `competencies_reset`
- AND the link's `exp - iat` is 24 hours
- AND the participant is `in_attesa`, the 2 invalid sessions are `pending` with utterances deleted,
  the valid sessions are untouched, and `retry_attempt = true`
- AND the retry email is queued to the participant's address

#### Scenario: The returned link redeems and resumes the re-interview

- GIVEN a successful authorization
- WHEN the candidate exchanges the returned link
- THEN the exchange succeeds, the participant stays the same row, and the interview offers only the 2 reset competencies

#### Scenario: Placeholder address gets no email but the link is returned

- GIVEN a participant whose email is a placeholder address
- WHEN the retry is authorized
- THEN HTTP 200 is returned with `entry_url` and `email_sent: false`
- AND no email job is queued
- AND the link lifetime is 30 minutes, because BEAI does not email it

#### Scenario: Reusable-link visitor gets no email

- GIVEN a participant created by a reusable interview link
- WHEN the retry is authorized
- THEN `email_sent` is false, no email job is queued, and the link is returned
- AND the link lifetime is 30 minutes

#### Scenario: Concurrent authorizations — exactly one wins

- GIVEN an operator and the calling system authorize the same eligible participant at the same time
- WHEN both reach the action
- THEN exactly one succeeds and mints the link
- AND the other receives HTTP 409 `reason: "retry_already_consumed"` and no link

#### Scenario: A retry link is never re-returned

- GIVEN a retry already authorized
- WHEN authorization is called again
- THEN HTTP 409 `retry_already_consumed` is returned and no new link is minted

#### Scenario: The action does not touch the finalize trigger dedup

- GIVEN `finalize:{participant_id}` is set from the first run
- WHEN a retry is authorized, or refused, or rolled back
- THEN the action neither reads, writes nor deletes that key
- AND the attempt-scoped key `finalize:{participant_id}:retry` is the one the re-interview uses

#### Scenario: A rolled-back authorization queues no email and writes no audit row

- GIVEN an authorization whose mint is refused by the entry gates after the participant flip
- WHEN the refusal rolls the transaction back
- THEN the participant is still `completato`, `retry_attempt` is false, the sessions are intact
- AND no email job is queued, no log line is emitted and no audit row exists

### Requirement: Evaluation Retry Refusal Guards

Authorization MUST be refused with HTTP 409 and a machine-facing `reason`, evaluated inside
the transaction before any write, in this order (first match wins):

1. `retry_already_consumed` — the participant's Evaluation has `retry_attempt = true`. It is
   checked first on purpose: a participant mid-retry is `in_attesa`, so a status-first order
   would answer a second authorization `not_completed`.
2. `not_completed` — the participant is not at `completato` (including `errore`, which is
   recovered through the recovery action, never retried).
3. `test_mode_participant` — the participant is a test-mode participant (`mode = test`): the
   real scoring job never scores it, so a retry would strand it at `in_valutazione`.
4. `evaluation_not_pending` — the participant has no Evaluation, or it is not `pending`
   (a `completed` evaluation is definitive and is never retried).
5. `project_inaccessible` — the participant's project fails the entry-gate predicate shared
   with every mint (not `active`, before `goes_live_at`, past `deadline_at`, or soft-deleted),
   whether detected by the guard or by the mint inside the transaction.

A refused authorization MUST NOT modify any row, release any lock, mint any link, queue any
email, write an audit row or write a success log line. `reason` values are machine-facing and not
localized.

#### Scenario: Participant not completed

- GIVEN a participant at `in_corso` (or `in_attesa`, `in_valutazione` or `errore`) without a consumed retry
- WHEN authorization is called
- THEN HTTP 409 `reason: "not_completed"` is returned and nothing is modified

#### Scenario: Evaluation completed is never retried

- GIVEN a participant at `completato` whose Evaluation is `completed` and `retry_attempt = false`
- WHEN authorization is called
- THEN HTTP 409 `reason: "evaluation_not_pending"` is returned

#### Scenario: No evaluation row

- GIVEN a participant at `completato` with no Evaluation row
- WHEN authorization is called
- THEN HTTP 409 `reason: "evaluation_not_pending"` is returned

#### Scenario: Retry already consumed

- GIVEN a participant whose Evaluation has `retry_attempt = true` (retry in progress or finished)
- WHEN authorization is called
- THEN HTTP 409 `reason: "retry_already_consumed"` is returned

#### Scenario: Test-mode participant is refused

- GIVEN a test-mode participant at `completato` whose Evaluation is `pending`
- WHEN authorization is called
- THEN HTTP 409 `reason: "test_mode_participant"` is returned and nothing is modified

#### Scenario: Closed, not-yet-live or past-deadline project

- GIVEN an otherwise eligible participant whose project is closed, not yet live, or past its deadline
- WHEN authorization is called
- THEN HTTP 409 `reason: "project_inaccessible"` is returned
- AND the participant remains `completato` with `retry_attempt = false`

#### Scenario: Guard order is deterministic

- GIVEN a participant that is both `retry_attempt = true` and not at `completato`
- WHEN authorization is called
- THEN the reason is `retry_already_consumed`

#### Scenario: Test mode is evaluated before the evaluation state

- GIVEN a test-mode participant at `completato` with no Evaluation
- WHEN authorization is called
- THEN the reason is `test_mode_participant`, not `evaluation_not_pending`

### Requirement: Evaluation Retry Authorization Is Role-Gated And Org-Scoped

The backoffice route `POST /api/participants/{id}/retry` (`auth:api` + `TenantContext`, its own
write route group) MUST be authorized by a `ParticipantPolicy::retry` ability granted to `admin`
and `operator`; `viewer` MUST be denied. Authorization MUST be checked BEFORE the participant is
resolved by id (403 before 404); a denied caller MUST NOT learn whether the id exists in another
organization. The participant MUST then be resolved scoped to the caller's `organization_id`; a
participant of another organization MUST return HTTP 404. The request body MAY carry an optional
free-text `reason` (string, max 500 characters; 422 above that). The M2M route is specified in
the `m2m-auth` capability and reaches the same action.

#### Scenario: Admin and operator can authorize

- GIVEN an authenticated `admin` or `operator` of the participant's organization
- WHEN authorization is called for an eligible participant
- THEN the retry is authorized (HTTP 200)

#### Scenario: Viewer is denied before the participant is resolved

- GIVEN an authenticated `viewer`
- WHEN authorization is called with an id belonging to another organization
- THEN HTTP 403 is returned, not 404, and nothing is modified

#### Scenario: Cross-tenant authorization is not found

- GIVEN an authenticated `operator` of Org A
- WHEN authorization is called with a participant id belonging to Org B
- THEN HTTP 404 is returned

#### Scenario: Reason over 500 characters is rejected

- GIVEN a `reason` of 501 characters
- WHEN authorization is called
- THEN HTTP 422 is returned and nothing is modified

#### Scenario: Reason is optional

- GIVEN a request without `reason`
- WHEN authorization is called for an eligible participant
- THEN the retry is authorized and the log line carries `reason: null`

### Requirement: Interim Retry Audit Logging

Every retry authorization that reaches authorization success MUST write, AFTER the authorization
transaction has committed (never inside it, like the other audit-writing actions; the audit
writer swallows its own exceptions, and a Postgres error raised inside a transaction would abort
the work it records), two records:

1. an `audit_logs` row through the shared audit recorder, with action
   `evaluation.retry_authorized`, subject type `evaluation` and the evaluation id as subject id.
   Its `after` payload carries the participant id, the evaluation id, the reset competency codes,
   the optional reason and the actor (kind, user id, API client id). The `actor_id` column is set
   only when the actor is a backoffice `User`; for an M2M caller the client id travels in the
   payload (the authenticated principal on that surface is an API client, not a user). The row
   carries no email, display name, link or token; and
2. a structured log line `participant.retry_authorized` carrying actor (kind, user id, M2M client
   id), participant id, organization id, project id, previous status, new status, the operator- or
   caller-supplied reason (nullable, max 500 chars), the reset competency codes, whether an email
   was queued (`email_queued`), and an ISO-8601 timestamp. It MUST NOT contain the candidate's
   email, display name, `candidate_ref`, the link or the token. The line is explicitly labelled
   INTERIM, with the same limits as the recovery log (`participant.recovered`).

Neither record is written for a refused authorization or a rolled-back transaction. A failure to
write either MUST be reported and MUST NOT fail the committed authorization.
(Previously: "interim log only, the ratified audit log is out of scope"; the owner resolution
ratified the audit row.)

#### Scenario: A successful authorization is audited and logged

- GIVEN an authorized retry that resets the participant
- WHEN the transaction commits
- THEN exactly one `audit_logs` row exists with action `evaluation.retry_authorized`, subject
  `evaluation` and the evaluation id
- AND a `participant.retry_authorized` line is emitted with actor, participant, organization,
  project, previous/new status, reason, reset competencies and email-queued flag

#### Scenario: An M2M authorization names the client in the payload

- GIVEN an authorization made by an M2M client
- WHEN the audit row is written
- THEN `actor_id` is null and the payload carries the client id as actor
- AND the row is written (it is not lost to a foreign-key violation on the user table)

#### Scenario: The records carry no secret or contact data

- GIVEN a successful authorization
- WHEN the log line and the audit payload are inspected
- THEN they contain neither the `entry_url`, the token, the candidate's email nor display name

#### Scenario: A refused authorization writes no success record

- GIVEN a refused authorization
- WHEN the refusal is returned
- THEN no `participant.retry_authorized` line is emitted and no audit row is written
