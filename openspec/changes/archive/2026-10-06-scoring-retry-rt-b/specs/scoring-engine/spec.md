# Delta for Scoring Engine

Promotes RT-B (the single domain retry of a `pending` evaluation) from DEFERRED to
delivered. Resolves RT-B-O1, RT-B-O2 and RT-B-O3, relaxes the "single DB transaction"
merge wording, and amends the start-of-job guard and `failed()` contracts accordingly. The
retry flag is read from the persisted Evaluation row (the database is authoritative); the job
payload flag is only a hint (owner/design resolution I10).
The authorization of the retry itself (who may trigger it, the refusal guards, the link and
the email) is specified in the `participant-sso`, `m2m-auth`, `admin-backoffice` and
`notifications` deltas of this change.

## MODIFIED Requirements

### Requirement: Job Dispatch and Lifecycle

`ScoreEvaluationJob` MUST be dispatched from `FinalizeInterview` at the `TODO(C9)` hook,
with the `participant_id` and a retry flag (read from the Evaluation row, see below) as its payload. The job runs on the Redis queue; p95
latency MUST be < 10 min. `ScoreEvaluationJob` MUST declare an execution timeout of at least
`max_role_competencies × scoring.anthropic.timeout_seconds × 1.1` (today: 1200 s / 20 min). The
p95 < 10 min figure remains the **performance target**; the declared timeout is the **execution
ceiling** and MUST exceed 600 seconds regardless of how any input config is tuned (see the
`queue-runtime` capability's Timeout / Retry-After Ordering and Ceiling Invariant requirement,
which enforces this as a config-independent floor). On job completion, the participant MUST
transition from `in_valutazione → completato` regardless of whether the Evaluation is `completed`
or `pending` (both are terminal sub-states of the evaluation).
(Previously: stated only the p95 < 10 min target with no execution ceiling, leaving `retry_after`
unsizeable without risking either premature `SIGALRM` kills or double-processing.)

The C7a Redis-NX `finalize:{pid}` lock dedups the `FinalizeInterview` TRIGGER only — it
does NOT dedup `ScoreEvaluationJob` execution. `ScoreEvaluationJob` MUST perform the
following guards at job START (before any LLM call or DB write), in order:

1. If `participant.status == 'errore'` → **exit no-op** (log + return). This runs BEFORE
   loading any Evaluation row.
2. Load the existing `Evaluation` row for this participant (if any). Then branch:
   - **No Evaluation row** → proceed: create `Evaluation` (status = `processing`), score
     normally. If the INSERT raises a `UniqueConstraintViolationException` (SQLSTATE 23505 —
     concurrent race), catch it, reload the existing row, and re-enter this guard from
     step 2 with the reloaded row. MUST NOT treat 23505 as a job failure.
   - **Status ∈ {completed, pending} AND the row's `retry_attempt` = false** → **exit
     no-op** (terminal, already scored), whatever the job payload says: a payload flag of true
     without a database authorization is also a logged no-op. Queue-level retry is safe: if the
     transient failure happened before the Evaluation INSERT, no row exists and the guard falls
     through.
   - **Status = processing (regardless of `retry_attempt`)** → **proceed on the resume-skip
     path**: resume the in-flight job; skip already-scored competencies (by existing
     `CompetencyResult` rows for this `evaluation_id + competency_code`); do NOT create a
     new `Evaluation` row. This also covers a retry job that crashed after its merge step
     (RT-B-O1, `processing + retry_attempt = true`): it resumes, it never re-merges.
   - **Status = pending AND the row's `retry_attempt` = true AND the participant is
     `in_valutazione`** → **proceed** to the retry merge step (Requirement: Retry — Single
     Re-Interview of a `pending` Evaluation (RT-B)), then re-score the competencies that have no
     valid result on the resume-skip path. A job whose payload flag is false but whose row says
     true merges anyway, with a `warning` log, so a retry is never stranded over a flag.
   - **Status = pending AND the row's `retry_attempt` = true AND the participant is NOT
     `in_valutazione`** → **exit no-op** with a log line (a stray job while the candidate has not
     finished the re-interview). The single retry is not burned.
   - **Status = completed AND the row's `retry_attempt` = true** → **exit no-op** with a
     log line (RT-B-O1: the retry was superseded, duplicated or raced). No LLM call, no
     write, no event.

> `retry_attempt` is read from the **Evaluation ROW** (the database is authoritative), never
> trusted from the **JOB PAYLOAD**: a crash-resumed or re-dispatched job carries no reliable
> flag, the row does. The RT-B dispatch (`DispatchScoringJob`) reads the row and passes the
> payload flag from it, so the two agree in normal operation; the payload is only a hint.

An `Evaluation` row MUST be created at job START in `processing` status, before any LLM
calls, so that `evaluation_id` is always known when appending `ai_requests` rows.

`ScoreEvaluationJob::failed()` (called when the job exhausts all queue retries) MUST:
(a) For a NON-retry job (the Evaluation row has `retry_attempt = false`, or no row): transition `participant
    in_valutazione → errore` ONLY IF `participant.status == 'in_valutazione'` (guard the
    status first; if already `errore`, skip the transition), and ALWAYS emit an
    `EvaluationFailed($participantId)` event for C10, regardless of whether the status
    transition was performed.
(b) For a RETRY job (the Evaluation row has `retry_attempt = true` and status `pending` or
    `processing`, RT-B-O2): the participant MUST NEVER be moved to `errore`, and
    `EvaluationFailed` MUST NOT be emitted. Instead, if the Evaluation is still `pending` the
    same idempotent merge as at job start runs first (so no first-attempt invalid result survives
    into the definitive evaluation), and then the Evaluation MUST be finalized as definitive
    `completed` with the valid `CompetencyResult` rows it retains (competencies not re-scored
    count as invalid in the denominator, exactly as an unscorable competency does), the
    participant MUST move `in_valutazione → completato` (skipped if the participant is not at
    `in_valutazione`), and the `EvaluationCompleted` event MUST be emitted so the definitive
    webhook is delivered. The terminal resolution runs inside ONE database transaction so it is
    all-or-nothing; the webhook job is dispatched after commit, so a rolled-back finalization
    delivers nothing. If the finalization itself throws, the participant stays `in_valutazione`
    with an `error` log, never `errore`. A stray failure for a participant that is not
    `in_valutazione` (the candidate has not re-interviewed) is a logged no-op and does not burn
    the retry; a `completed` retry Evaluation is a logged no-op. The same path serves the
    unresolvable-participant ending of the job. The retry is the definitive run by rule; a
    technical failure of it MUST NOT leave an unrecoverable `errore`.
(Previously: `failed()` had a single behavior — `in_valutazione → errore` plus
`EvaluationFailed` — which on a retry would swallow the failure webhook under the evaluation
dedupe key and leave a participant that `RecoverFailedParticipant` refuses to recover.)

**Implementation timing**: the `ScoreEvaluationJob::failed()` skeleton (at minimum: the
`in_valutazione → errore` guard + `EvaluationFailed` event dispatch) MUST be implemented
in **chain-PR 1** alongside the job skeleton and schema migrations — NOT deferred to PR 3.
Without `failed()` in PR 1, PRs 1 and 2 can leave participants permanently orphaned in
`in_valutazione` on job exhaustion. The full wiring of `failed()` to the gate and lifecycle
resolution completes in PR 3.

A leftover `processing` Evaluation row when a NON-retry `failed()` fires does NOT deadlock future
scoring: the guard step 1 (`participant.status == 'errore'`) fires first on any future
dispatch and exits no-op immediately. The `Evaluation` row is preserved for audit.

#### Scenario: Job dispatched from FinalizeInterview

- GIVEN participant P is in state `in_valutazione` and the `TODO(C9)` hook is reached
- WHEN `FinalizeInterview` executes
- THEN `ScoreEvaluationJob::dispatch(P.id)` is enqueued exactly once on the Redis queue

#### Scenario: Declared timeout clears the derived ceiling

- GIVEN the standard framework's largest role has 18 competencies and
  `scoring.anthropic.timeout_seconds = 60`
- WHEN `ScoreEvaluationJob`'s declared `$timeout` is inspected
- THEN it is >= `18 × 60 × 1.1` = 1188 seconds (today configured at 1200s)
- AND it exceeds 600 seconds regardless of the computed formula value (the config-independent
  floor from the p95 target)

#### Scenario: Start-of-job guard — existing terminal Evaluation → no-op

- GIVEN `ScoreEvaluationJob` has already produced a terminal `Evaluation` (status ∈ {completed, pending}) for participant P
- AND the Evaluation row has `retry_attempt = false`
- WHEN `ScoreEvaluationJob` is invoked again for the same participant
- THEN no additional `Evaluation` row is created and no LLM calls are made

#### Scenario: Start-of-job guard — participant errore → no-op

- GIVEN participant P has `status = 'errore'`
- WHEN `ScoreEvaluationJob` is invoked
- THEN the job exits immediately with no LLM calls and no DB writes

#### Scenario: Queue-level retry safe after transient failure before Evaluation INSERT

- GIVEN `ScoreEvaluationJob` fails with a transient error before the `Evaluation` row is created
- WHEN the queue retries the job
- THEN no existing `Evaluation` is found, guard passes, and job proceeds normally

#### Scenario: Queue retry AFTER Evaluation INSERT (status=processing) — resume-skip path, no duplicate LLM call

- GIVEN `ScoreEvaluationJob` created an `Evaluation` row (status=`processing`) and scored 3 of 10 competencies
  before failing with a transient error (leaving 3 `CompetencyResult` rows)
- WHEN the queue retries the job
- THEN the guard detects status=`processing` → proceeds on the resume-skip path
- AND the job skips the 3 already-scored competencies (existing `CompetencyResult` rows) with no duplicate LLM call
- AND scoring continues from competency 4 onward
- AND no new `Evaluation` row is created

#### Scenario: CompetencyResult unique-violation on resume → skip (not fail)

- GIVEN a `CompetencyResult` row already exists for `(evaluation_id, competency_code)` due to a prior resume attempt
- WHEN the job attempts to INSERT another `CompetencyResult` for the same `(evaluation_id, competency_code)`
- THEN the `unique(evaluation_id, competency_code)` violation is caught, logged, and treated as a successful skip
- AND the job continues to the next competency without failing

#### Scenario: Concurrent race on Evaluation INSERT → re-enter guard

- GIVEN no `Evaluation` row exists when the guard is first evaluated, but a concurrent job wins the INSERT race
- WHEN this job's INSERT raises `UniqueConstraintViolationException` (SQLSTATE 23505)
- THEN the exception is caught, the existing row is reloaded, and the guard re-evaluates against the loaded row
- AND the job does NOT fail

#### Scenario: Both completed and pending Evaluation resolve participant to completato

- GIVEN `ScoreEvaluationJob` finishes and the Evaluation status is `pending`
- WHEN the job persists the Evaluation
- THEN `participant.status` transitions from `in_valutazione` to `completato`

#### Scenario: Terminal-transition race guard — concurrent errore skips completato transition but still persists Evaluation

- GIVEN `ScoreEvaluationJob` finishes scoring and is about to transition `in_valutazione → completato`
- AND a concurrent `failed()` call has already transitioned the participant to `errore`
- WHEN the job checks `participant.status` before the transition
- THEN the `in_valutazione → completato` transition is SKIPPED (forbidden: `errore → completato`)
- AND the Evaluation terminal state IS still persisted (status = `completed` or `pending`)
- AND the `EvaluationCompleted` event IS still emitted for C10

#### Scenario: Job exhausts retries → participant errore + EvaluationFailed event

- GIVEN a NON-retry `ScoreEvaluationJob` (the Evaluation row has `retry_attempt = false`) exhausts all queue retries without completing
- AND `participant.status == 'in_valutazione'`
- WHEN the queue worker calls `ScoreEvaluationJob::failed()`
- THEN `participant.status` transitions from `in_valutazione` to `errore`
- AND an `EvaluationFailed` lifecycle event is emitted for C10

#### Scenario: failed() — participant already errore → skip transition, still emit event

- GIVEN a NON-retry `ScoreEvaluationJob` exhausts all queue retries
- AND `participant.status` is already `errore` (e.g. from a prior failure cycle)
- WHEN the queue worker calls `ScoreEvaluationJob::failed()`
- THEN the `in_valutazione → errore` transition is SKIPPED (participant is already `errore`)
- AND an `EvaluationFailed` lifecycle event is STILL emitted for C10

#### Scenario: failed() on a retry job finalizes completed, never errore (RT-B-O2)

- GIVEN a retry `ScoreEvaluationJob` (the Evaluation row has `retry_attempt = true`) with 8
  retained valid results and 2 re-interviewed competencies, exhausts all queue retries
- AND `participant.status == 'in_valutazione'`
- WHEN the queue worker calls `ScoreEvaluationJob::failed()`
- THEN the `Evaluation` status is `completed` and the 8 valid `CompetencyResult` rows are retained
- AND `participant.status` is `completato`, never `errore`
- AND `EvaluationCompleted` is emitted and `EvaluationFailed` is NOT emitted

#### Scenario: failed() for a stray retry job does not burn the retry

- GIVEN an Evaluation `pending` with `retry_attempt = true` and a participant at `in_attesa`
- WHEN a stray `ScoreEvaluationJob` exhausts its queue retries
- THEN the evaluation and the participant are untouched and a log line records the no-op

#### Scenario: A throw inside the retry finalization never reaches errore

- GIVEN a retry job whose finalization throws (for example an `EvaluationCompleted` listener)
- WHEN `failed()` runs
- THEN the transaction rolls back, the participant stays `in_valutazione`, the Evaluation keeps its status
- AND an `error` log is written and the participant is never `errore`

#### Scenario: Retry job crashed after the merge step resumes without re-merging (RT-B-O1)

- GIVEN a retry job deleted the invalid results and set the Evaluation `processing`, then crashed
- WHEN the job is retried (with or without the payload flag)
- THEN the guard takes the `processing` resume-skip path
- AND no result is deleted a second time and no duplicate LLM call is made for a competency that already has a result

#### Scenario: completed + retry_attempt=true is a logged no-op (RT-B-O1)

- GIVEN an Evaluation with status `completed`, its row `retry_attempt = true`, and a duplicate retry dispatch
- WHEN the start-of-job guard runs
- THEN the job exits with a log line, makes no LLM call and writes nothing
- AND no event is emitted

### Requirement: Retry — Single Re-Interview of a `pending` Evaluation (RT-B)

When an Evaluation has status `pending` and its single retry has not been consumed, the
system MUST support exactly ONE retry: the candidate re-interviews the INVALID competencies
only, the valid results are retained, and the resulting evaluation is definitive `completed`
even below the completion threshold. The retry is authorized by an admin/operator or by the
calling system through one shared authorization action (specified in the `participant-sso`
capability: Requirement: Evaluation Retry Authorization Action). The same invalid-only
rule applies to `standard` and `potential` assessments; no MTG/LAT-specific behavior exists.
(Previously: DEFERRED, with RT-B-O1/O2/O3 unresolved and the merge specified as a single
all-or-nothing DB transaction.)

**Invalid competency**: a competency of the participant's project that has no
`CompetencyResult` with `valid = true` (either no result row at all, or a row with
`valid = false`). The set is computed from persisted results, never from a job payload.

**Retry persistence (CW4)**: the retry UPDATES the existing `Evaluation` row in place
(status, `evaluated_at`, versioning) — it MUST NOT insert a new `Evaluation` row (which would
violate the `unique(participant_id)` constraint). Only the `CompetencyResult` and
`IndicatorScore` rows of invalid competencies are replaced; valid prior results MUST remain
byte-for-byte unchanged. The versioning is re-stamped to the retry run (owner decision
2026-10-05): at the merge the row's `model_version` and `prompt_version` take today's
configured values, because the retry re-scores under today's model and prompt; the
`framework_version_id` stays the one pinned at project creation (ratified decision 3). Per-call
detail remains in `ai_requests`. Valid results retained from the first run keep the model and
prompt of that run in their own `ai_requests` rows.

The answers (utterances and session state) of the competencies to re-interview are deleted when
the retry is AUTHORIZED, not when it is scored (owner resolution R2; see `participant-sso`:
Requirement: Evaluation Retry Authorization Action). The invalid `CompetencyResult` rows are
deleted later, at the merge, so the `pending` evaluation stays intact and consistent with the
`pending` webhook already delivered until the candidate actually re-interviews.

**Merge at retry-job start (relaxed atomicity)**: when the retry job starts with the
Evaluation at `pending`, its row `retry_attempt = true` and the participant at `in_valutazione`,
it MUST, in ONE database transaction that locks the participant row first and the Evaluation row
second (the same order as the authorization action, so the two never wait on each other) and
re-checks both under the lock, (1) delete the `CompetencyResult` rows (and their indicator
scores and audits, by cascade) of the invalid competencies, (2) re-stamp `model_version` and
`prompt_version`, and (3) set the Evaluation to `processing`. Scoring of the re-interviewed
competencies then proceeds on the existing resume-skip path, one result at a time. The merge
is therefore atomic only for the delete-and-flip step; the re-scoring that follows is NOT a
single all-or-nothing transaction, and crash-safety comes from the `processing` resume path.
While the Evaluation is `processing` it MUST remain unreadable through the existing read
gate (structured evaluation only at participant `completato`; the participant is `in_attesa`,
`in_corso` or `in_valutazione` during a retry).
(Previously: "The entire merge runs in a single DB transaction (all-or-nothing)".)

**Definitive outcome**: the Evaluation produced by a retry run MUST be `completed` whatever
the valid-competency ratio (the 90% gate and its ZeroCompetencies `errore` arm are not applied
to a retry run, so a project whose composition was emptied still ends `completed`; the counts are
still logged), the participant MUST
move `in_valutazione → completato`, and the retry is exhausted and MUST NOT be re-offered
(`retry_attempt` stays `true`). There is no further retry and no second retry authorization.

**Dispatch**: when the candidate completes the re-interview, the scoring dispatch MUST carry
`retry_attempt = true` whenever the participant's Evaluation has `retry_attempt = true` in the
database, and MUST carry `false` otherwise.

**No expiry**: a retry that is authorized and never taken leaves the Evaluation `pending`
and the participant `in_attesa` indefinitely; there is no auto-finalize, deadline or
reminder (ratified decision 5).

**Lifecycle re-entry (RT-B-O3)**: the retry completion path runs the ordinary lifecycle
`in_attesa → in_corso → in_valutazione → completato`, enabled by the `completato → in_attesa`
edge (see `participant-sso`: Requirement: Participant Model Lifecycle Guard). The completion
path MUST NOT attempt `completato → completato` or any transition outside the guard map.

#### Scenario: Retry re-interviews invalid competencies only

- GIVEN Evaluation status = `pending` with 2 invalid competencies (INN, STG) and 8 valid
- WHEN the retry is authorized and the candidate completes the re-interview
- THEN only the INN and STG sessions are re-opened; the 8 valid `CompetencyResult` rows are retained unchanged
- AND the existing `Evaluation` row is updated in place (no new row inserted)

#### Scenario: A competency with no result row at all counts as invalid

- GIVEN a `pending` Evaluation where competency INN is unscorable and has no `CompetencyResult` row
- WHEN the invalid set is computed for the retry
- THEN INN is in the invalid set

#### Scenario: Merge deletes invalid results and flips to processing in one transaction

- GIVEN a `pending` Evaluation with 2 invalid results, its row `retry_attempt = true`, the participant at `in_valutazione` and the retry job dispatched
- WHEN the retry job starts
- THEN the invalid results are deleted and the Evaluation becomes `processing` in ONE transaction
- AND `model_version` and `prompt_version` equal today's configured values while `framework_version_id` is unchanged
- AND a failure injected between the two steps leaves both untouched

#### Scenario: Valid results survive the merge

- GIVEN a `pending` Evaluation with 8 valid results
- WHEN the retry merge and re-scoring complete
- THEN the 8 valid `CompetencyResult` rows keep their ids, scores and excerpts

#### Scenario: Retry idempotency guard — pending + retry_attempt = true bypasses early-exit

- GIVEN an existing `Evaluation` with status = `pending` and its row `retry_attempt = true`
- AND the participant is at `in_valutazione` and the job is dispatched
- WHEN the start-of-job guard runs
- THEN the guard does NOT exit no-op; it proceeds to the retry merge and re-scores the invalid competencies

#### Scenario: A retry flag without a database authorization is a no-op

- GIVEN an Evaluation `pending` whose row has `retry_attempt = false`
- AND the job is dispatched with the payload flag `true`
- WHEN the start-of-job guard runs
- THEN the job exits with a log line and writes nothing

#### Scenario: A stray retry job before the re-interview is a no-op

- GIVEN an Evaluation `pending` with `retry_attempt = true` and a participant at `in_attesa`
- WHEN a scoring job runs
- THEN it exits with a log line, makes no LLM call and deletes nothing

#### Scenario: Post-retry → completed regardless of gate

- GIVEN a retry scoring run for the participant in which valid_competencies/total < 0.90
- WHEN the run finishes
- THEN Evaluation status = `completed` (definitive)
- AND `participant.status` = `completato`
- AND the retry is not re-offered

#### Scenario: The evaluation is unreadable while the retry is in progress

- GIVEN a retry has been authorized and the participant is `in_attesa`, `in_corso` or `in_valutazione`
- WHEN the structured evaluation is requested through any read surface
- THEN the existing read gate refuses it (only `completato` exposes the structured evaluation)

#### Scenario: Dispatch carries the retry flag from the persisted column

- GIVEN a participant whose Evaluation has `retry_attempt = true` completes the re-interview
- WHEN the scoring job is dispatched
- THEN `ScoreEvaluationJob` receives `retry_attempt = true`
- AND for a participant whose Evaluation has `retry_attempt = false` it receives `false`

#### Scenario: A never-taken retry leaves the evaluation pending

- GIVEN a retry authorized for participant P and the candidate never opens the link
- WHEN any amount of time passes
- THEN the Evaluation stays `pending` and `participant.status` stays `in_attesa`
- AND no job, reminder or auto-finalize fires

#### Scenario: A fast re-interview within two hours still scores

- GIVEN a retry authorized for P and the re-interview finished within 2 hours of P's first finalization
- WHEN the last `/end` fires `FinalizeInterview`
- THEN the scoring job is dispatched exactly once (the earlier `finalize:{participant_id}` lock does not suppress it)

## REMOVED Requirements

### Requirement: Retry — Fast-Follow Work Unit (RT-B)

(Reason: replaced in place by "Retry — Single Re-Interview of a `pending` Evaluation (RT-B)"
above; the DEFERRED banner and the open items RT-B-O1/O2/O3 are resolved by this change.)
(Migration: none; the archived text of the old requirement is superseded. Also remove the
"Retry sub-system (chain-PR 4) — DEFERRED" paragraph of the "Delivery Status" section at
archive, see the change's non-requirement edit list.)
