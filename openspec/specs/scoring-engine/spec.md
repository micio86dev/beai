# Scoring Engine Specification

## Purpose

Defines the async BARS evaluation pipeline (C9): from `FinalizeInterview` trigger through
per-competency LLM scoring, validation, reliability/gate evaluation, and participant
lifecycle resolution. All correctness-critical paths MUST be held to ~95% test coverage.

---

## Delivery Status

**First-pass (PRs 1–3 + D7 LLM binding) — DELIVERED** (merged to `api/develop`, tip `41d3d76`, 2026-07-22).

---

## Requirements

<!-- superseded by queue-worker-scheduler -->

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

### Requirement: Non-EN Anchor Language (L-2 Hard-Fail)

The engine MUST score each competency in the project's configured language.
`PromptBuilder` MUST check translations via `hasTranslation($field,
$projectLocale)` for ALL FOUR translatable fields of each `BarsIndicator`:
`text`, `anchor_5`, `anchor_3`, and `anchor_1`. It MUST NOT use the
convenience method `hasTranslationGap()` (hardcoded to `'it'`, which would
silently mis-evaluate non-IT projects). A missing `indicator.text`
translation in the project locale is as corrupting as a missing anchor — the
prompt would inject an EN indicator description alongside localized
anchors, producing an incoherent rubric. If ANY of the four fields is
missing a project-locale translation, the engine MUST hard-fail that
competency: mark it unscorable and record the reason as
`anchor_translation_missing`. The engine MUST NEVER silently fall back to
English for any of the four fields. An unscorable competency counts against
the 90% gate (see Completion Gate requirement for the full policy and
config-flaggable override).
(Previously: no real catalogue row carried an `it` translation, so every
scenario against `it` exercised only factory/fixture data; this restates
scenarios against the real, partially-translated catalogue.)

#### Scenario: Missing IT anchor → competency hard-failed, no EN fallback

- GIVEN project language = `it` and competency COL has no Italian anchor translations for `anchor_5`
- WHEN the engine attempts to score COL
- THEN COL is marked unscorable with reason `anchor_translation_missing`
- AND NO LLM call is made using English anchors
- AND the `hasTranslation($field, 'it')` check (not `hasTranslationGap()`) is used for each of {text, anchor_5, anchor_3, anchor_1}

#### Scenario: Missing IT indicator text → competency hard-failed (text field in scope)

- GIVEN project language = `it` and competency INN has all three anchor translations but no Italian `text` for one indicator
- WHEN the engine checks translations for INN
- THEN INN is marked unscorable with reason `anchor_translation_missing`
- AND no LLM call is made (missing `text` in project locale is a hard-fail, same as missing anchor)

#### Scenario: Present anchor passes through normally

- GIVEN project language = `it` and competency COM has Italian anchor translations
- WHEN the engine scores COM
- THEN the Italian anchor texts are injected into the prompt and scoring proceeds normally

#### Scenario: A fully-translated role scores every competency in Italian (real catalogue, ICO scope)

- GIVEN a project pinned to role ICO with language = `it`, and ICO's full
  role×competency scope is translated per `framework-catalog-it-translations`
- WHEN the engine scores every competency for that participant
- THEN no competency is marked unscorable with `anchor_translation_missing`
- AND every prompt is composed entirely from Italian text (no EN fallback
  occurs for any of the four fields on any indicator)

#### Scenario: Partial coverage — one role translated, a sibling role is not

- GIVEN role ICO is fully translated to `it` and role FLL is not yet
  translated (still mid-slice)
- WHEN an `it`-language project pinned to ICO is scored
- THEN all of that project's competencies score normally with no hard-fail
- GIVEN a separate `it`-language project pinned to FLL, scored in the same
  deployment
- WHEN FLL's untranslated competencies are scored
- THEN each untranslated FLL competency is still marked unscorable with
  `anchor_translation_missing` (the per-competency hard-fail is unaffected
  by ICO's translated state — coverage is evaluated per pair, not globally)

### Requirement: Per-Competency Scoring Pipeline

For each `InterviewSession` belonging to the participant, the engine MUST:
load BARS indicators and their anchors `{5, 3, 1}` at the PINNED `framework_version_id`
(never the live C3 draft); assemble the transcript corpora per **Requirement: Transcript
Assembly for Scoring** — utterances loaded with an explicit `->orderBy('ts')->orderBy('id')`
(determinism-critical: `ts` is NOT guaranteed unique — HeyGen bulk-replace can produce
timestamp ties; `id` is the stable secondary sort preserving insertion order within a tie)
and serialized as `"{speaker}: {text}"` per utterance joined by `\n`; assemble a prompt that injects those anchors verbatim, instructs the LLM to
return indicators in the EXACT SAME ORDER they were injected (ordered by `position`), and
requests ONLY per-indicator data from the LLM (no `score`/`reliability` roll-up in the
requested schema); call `LLMProvider.complete(prompt, options)` with `temperature=0` and
the pinned `model_version`; persist an `ai_requests` row for the call, linked via
`evaluation_id` (always known because the `Evaluation` row is created at job START); parse
the JSON response per-indicator by ARRAY POSITION (not string-matching echoed text);
validate scores and excerpts; compute the competency mean server-side. Unscorable
competencies MUST NOT make an LLM call and MUST NOT produce an `ai_requests` row;
`CompetencyResult.unscorable_reason` is the sole audit trace.

#### Scenario: Anchors loaded from pinned framework_version_id

- GIVEN an `InterviewSession` with `framework_version_id = V`
- WHEN the scoring pipeline assembles the prompt for competency COL
- THEN anchor texts are read from framework version V, NOT the current live C3 draft

#### Scenario: Transcript assembled with explicit orderBy ts then id

- GIVEN an `InterviewSession` with utterances having timestamps ts1 < ts2 < ts3
- WHEN `PromptBuilder` assembles the transcript
- THEN utterances are loaded via `->orderBy('ts')->orderBy('id')` and serialized in ascending ts order (id as tiebreaker)
- AND the prompt corpus and the validation corpus are derived from that one ordered fetch, satisfying the subset invariant (see Requirement: Transcript Assembly for Scoring)
- AND they are NOT the same string — the prompt corpus carries both speakers, the validation corpus carries the candidate only

#### Scenario: Transcript order stable on timestamp tie (tiebreaker by id)

- GIVEN an `InterviewSession` with two utterances sharing the same `ts` value (e.g. HeyGen bulk-replace collision), with `id` values 42 and 43
- WHEN `PromptBuilder` assembles the transcript
- THEN utterance with `id=42` is serialized before utterance with `id=43` (stable, insertion-order-preserving)
- AND the order is deterministic across retries

#### Scenario: ai_requests row persisted for each scored competency

- GIVEN the engine calls `LLMProvider.complete(...)` for a competency and the `Evaluation` row already exists (created at job START)
- WHEN the call returns
- THEN an `ai_requests` row is persisted with: `evaluation_id`, `competency_code`, model, prompt_version, input tokens, output tokens, timing; `evaluation_id` is never null

#### Scenario: Unscorable competency — no LLM call, no ai_requests row

- GIVEN competency INN is marked unscorable (`role_no_bars`)
- WHEN the engine processes INN
- THEN no LLM call is made and no `ai_requests` row is created for INN
- AND `CompetencyResult.unscorable_reason = 'role_no_bars'` is the sole audit record

#### Scenario: temperature=0 enforced on every LLM call

- GIVEN the engine invokes `LLMProvider.complete(...)` for any competency
- WHEN the options are inspected
- THEN `temperature` equals 0 (no higher value is permitted)

---

### Requirement: Transcript Assembly for Scoring

Transcript assembly MUST produce **two distinct corpora** from the same participant's
utterances, serving two different roles.

**The prompt corpus** MUST contain every utterance of every `InterviewSession` belonging to
the participant, both speakers included (`candidate` and `avatar`), ordered
`orderBy('ts')->orderBy('id')` — the dual sort remains determinism-critical, as `ts` alone is
not unique under HeyGen bulk-replace. Sessions MUST be ordered deterministically among
themselves. The segment belonging to the competency currently being scored MUST be
**explicitly delimited** by a marker the prompt names, so the model can weight it while
remaining free to cite corroborating evidence from elsewhere in the conversation.

**The validation corpus** MUST contain **only** utterances whose `speaker` is `candidate`,
drawn from the same participant-wide set, in the same order. The speaker comparison MUST be
**case-insensitive**: a value differing only in letter case denotes the same speaker, and an
exact comparison would silently drop such an utterance, failing every excerpt that cites it
and scoring the participant `-1` across the board with no stated cause. A `speaker` that is
genuinely neither value MUST be excluded from the validation corpus while remaining present
in the prompt corpus.

Markers MUST be emitted only around a target segment that contains at least one utterance.
An empty pair of markers would announce a primary-evidence block that does not exist.

The corpora MUST satisfy the **subset invariant**: every candidate utterance present in the
validation corpus is also present in the prompt corpus. A change that breaks this invariant
is a defect, because it would allow the model to be shown evidence it is then forbidden to
cite.

(Previously: `TranscriptAssembler::assemble(InterviewSession $session)` produced **one**
string from **one** session — the competency currently being scored — and that single string
was passed both to the LLM prompt and to `ExcerptValidator`. Evidence a candidate gave while
answering a different competency's question was invisible to the evaluator, and the
interviewer's own `avatar:` lines were a legal source of "evidence" about the candidate.)

#### Scenario: Prompt corpus spans every competency of the participant

- GIVEN a participant with three `InterviewSession` rows — COL, DRV, COM — each holding utterances
- WHEN the prompt corpus is assembled while scoring COL
- THEN it contains the utterances of all three sessions
- AND the utterances of each session appear in `ts`, then `id` order
- AND the session ordering is deterministic across repeated assembly of the same data

#### Scenario: The target competency's segment is delimited

- GIVEN the participant above and COL is the competency being scored
- WHEN the prompt corpus is assembled
- THEN the COL segment is enclosed between an explicit start marker and end marker
- AND the DRV and COM segments are present but not enclosed by those markers
- AND assembling the same data while scoring DRV instead moves the markers to the DRV segment, leaving the text otherwise identical

#### Scenario: Validation corpus excludes the interviewer entirely

- GIVEN a session containing `avatar: Tell me about a time you overruled your team` and `candidate: I overruled my team on the vendor choice`
- WHEN the validation corpus is assembled
- THEN it contains `I overruled my team on the vendor choice`
- AND it does NOT contain `Tell me about a time you overruled your team`

#### Scenario: Subset invariant holds

- GIVEN any participant with any number of sessions and utterances
- WHEN both corpora are assembled
- THEN every candidate utterance text present in the validation corpus is also present in the prompt corpus

#### Scenario: Participant with a single session behaves as before

- GIVEN a participant with exactly one `InterviewSession`, for the competency being scored
- WHEN the prompt corpus is assembled
- THEN it contains that session's utterances, both speakers, in `ts`/`id` order
- AND the whole corpus is the delimited target segment

#### Scenario: Participant with no utterances yields empty corpora

- GIVEN a participant whose sessions hold no utterances
- WHEN both corpora are assembled
- THEN both are empty strings
- AND no exception is thrown

#### Scenario: An empty target session among non-empty siblings emits no markers

- GIVEN the target competency's session holds no utterances
- AND another session holds candidate utterances
- WHEN both corpora are assembled
- THEN the prompt corpus contains the other session's utterances
- AND it contains no marker text at all

#### Scenario: A capitalized speaker is still recognized as the candidate

- GIVEN an utterance whose `speaker` is `Candidate` rather than `candidate`
- WHEN the validation corpus is assembled
- THEN that utterance's text is present in it

#### Scenario: An unknown speaker is excluded from validation but kept in the prompt

- GIVEN an utterance whose `speaker` is neither `candidate` nor `avatar`
- WHEN both corpora are assembled
- THEN its text is absent from the validation corpus
- AND its speaker-prefixed line is present in the prompt corpus

#### Scenario: Another participant's utterances never leak in

- GIVEN two participants each holding a session for the same competency
- WHEN the corpora are assembled for the first participant
- THEN neither corpus contains any of the second participant's utterances

---

### Requirement: Indicator Score Domain Validation

Each indicator score returned by the LLM MUST be validated server-side as exactly one
value from `{1, 2, 3, 4, 5} ∪ {-1}`. Scores of 0, 6, any decimal, any other negative
value, or any value outside this set MUST be rejected. An illegal score MUST NOT
discard the whole competency: validation happens per-indicator, and a rejected
indicator is persisted with `IndicatorScore.score = -1` and
`IndicatorScore.unassessable_reason = 'score_illegal'` (see Requirement: Per-Indicator
Validation-Failure Isolation).
Sibling indicators in the same competency that validated cleanly MUST retain their
own scores unaffected.
(Previously: legal domain was `{1, 3, 5} ∪ {-1}`, and an illegal score threw
`InvalidIndicatorScoreException` inside a single `try` spanning the whole competency,
discarding every already-validated sibling indicator.)

#### Scenario: Indicator count mismatch → llm_parse_error, no queue retry

- GIVEN the LLM returns a `behaviors` array with 4 elements for competency COL, but COL has 3 indicators in the BARS catalog
- WHEN `EvaluationParser` maps the response to BARS indicators by array position
- THEN the count mismatch is detected
- AND the competency is immediately marked `llm_parse_error` with `score = NULL`, `valid = false`
- AND NO queue retry is triggered for this competency
- AND this is a competency-envelope failure, unaffected by per-indicator isolation (no per-indicator DTOs exist to isolate when the envelope itself did not parse)

#### Scenario: Score 2 accepted

- GIVEN the LLM returns an indicator score of 2 for indicator I
- WHEN the validator processes the response
- THEN an `IndicatorScore` row is persisted with `score = 2`

#### Scenario: Score 4 accepted

- GIVEN the LLM returns an indicator score of 4 for indicator I
- WHEN the validator processes the response
- THEN an `IndicatorScore` row is persisted with `score = 4`

#### Scenario: Score -1 accepted as unassessable sentinel, tagged model_declared

- GIVEN the LLM returns score -1 for indicator I (no assessable evidence)
- WHEN the validator processes the response
- THEN an `IndicatorScore` row is persisted with `score = -1` and `unassessable_reason = 'model_declared'`

#### Scenario: Score 5 accepted

- GIVEN the LLM returns score 5 for indicator I
- WHEN the validator processes the response
- THEN an `IndicatorScore` row is persisted with `score = 5`

#### Scenario: Illegal score is contained to its own indicator, siblings survive

- GIVEN competency COL has 3 indicators and the LLM returns scores `[3, 6, 5]` (indicator 2 is illegal)
- WHEN the validator processes the response
- THEN indicator 2 is persisted with `score = -1`, `unassessable_reason = 'score_illegal'`
- AND indicators 1 and 3 are persisted with their own scores `3` and `5`, unaffected
- AND no `InvalidIndicatorScoreException` propagates past the single indicator

#### Scenario: Illegal decimal score is contained the same way

- GIVEN the LLM returns an indicator score of 3.5 for one indicator among several valid ones
- WHEN the validator processes the response
- THEN only that indicator is persisted with `score = -1`, `unassessable_reason = 'score_illegal'`
- AND the competency's other indicators are unaffected

#### Scenario: Illegal negative score other than -1 is contained the same way

- GIVEN the LLM returns an indicator score of -2 for one indicator among several valid ones
- WHEN the validator processes the response
- THEN only that indicator is persisted with `score = -1`, `unassessable_reason = 'score_illegal'`
- AND the competency's other indicators are unaffected

---

### Requirement: Competency Mean Recomputed Server-Side

`competency.score` MUST be computed by the server as the arithmetic mean of assessed
indicator scores (those in `{1, 2, 3, 4, 5}` only; `-1` excluded), rounded to 2 decimal places
using standard half-up rounding. The server MUST NOT trust the LLM's own arithmetic. When
the assessed set is empty (all indicators returned -1), `competency.score` MUST be `NULL`.
(Previously: assessed set was `{1, 3, 5}`.)

#### Scenario: Golden cassette — COL {5,4,3} → 4.0

- GIVEN three assessed indicators for COL scored [5, 4, 3]
- WHEN the server computes `competency.score`
- THEN `competency.score` = round((5+4+3)/3, 2) = 4.0
- AND the golden cassette exercises indicator scores 2 and 4 end-to-end and is green

#### Scenario: Golden cassette — SLF {5,3,-1} → 4.0

- GIVEN indicators for SLF scored [5, 3, -1] (one unassessable)
- WHEN the server computes `competency.score`
- THEN `competency.score` = (5+3)/2 = 4.0
- AND the denominator is 2, not 3

#### Scenario: All indicators -1 → NULL score, competency invalid (CC2)

- GIVEN all indicators for a competency return score -1
- WHEN `MeanCalculator` computes the mean
- THEN `competency.score = NULL` and the competency is INVALID

#### Scenario: Indicator score -1 with empty excerpts passes validation (CC2)

- GIVEN an indicator with `score = -1` and `excerpts = []`
- WHEN the validator processes the response
- THEN validation passes and an `IndicatorScore` row is persisted with `score = -1`, `excerpts = []`

---

### Requirement: PromptBuilder Injects the AD-1 Rubric and Drops the Old Prohibition

`PromptBuilder` MUST inject the five-level relational rubric (Requirement:
Relational Rubric for Residual Score Levels, `scoring-model`) into every
scoring prompt, keyed to `prompt_version`. The prior instruction "Do NOT use
scores 2, 4, or any other value" MUST be removed. `config('scoring.prompt_version')`
MUST equal `2.0.0` for every Evaluation created after this change ships.

> **The `2.0.0` pin above is SUPERSEDED by `evaluator-evidence-and-rigor`** (archived
> 2026-08-28), which bumped `prompt_version` to `3.0.0` — see Requirement: Scoring Prompt
> Construction. The rubric-injection and old-prohibition-removal clauses stand unchanged;
> only the version literal moved. Evaluations produced before that change keep `2.0.0`
> (no migration, no backfill).

#### Scenario: The old prohibition is absent from the prompt

- GIVEN any scoring prompt composed after this change
- WHEN its text is inspected
- THEN it contains no instruction prohibiting scores 2 or 4

#### Scenario: New evaluations stamp the current prompt_version

- GIVEN `ScoreEvaluationJob` runs after this change ships
- WHEN the resulting `Evaluation` is persisted
- THEN `prompt_version` = the configured `config('scoring.prompt_version')` — `2.0.0` when
  this requirement shipped, `3.0.0` from `evaluator-evidence-and-rigor` onward

---

### Requirement: Scoring Prompt Construction

The scoring system prompt MUST carry an **EVALUATION STANDARDS** block establishing severity
calibration, in addition to the existing IMPORTANT RULES, SCORING PROCEDURE, rubric and
output-format sections. The block MUST establish that `3` is the baseline for adequate
evidence, that `4` and `5` are rare and require **all three** of a specific situation,
concrete actions and a measurable outcome, and that generic or hypothetical answers score
`1` or `2`.

The block MUST NOT contradict the SCORING PROCEDURE. Specifically, any instruction to
resolve doubt downward MUST be scoped to the residual choice at step 5 of that procedure, and
MUST NOT override the anchor-primacy tie-break: evidence equally consistent with an authored
anchor and an intermediate level still resolves to the **authored anchor**.

The block is written in **English** regardless of project locale, consistent with the
SCORING PROCEDURE it sits beside. The indicator rubric remains localised to the project
locale and continues to hard-fail via `AnchorTranslationMissingException` when any of
`{text, anchor_5, anchor_3, anchor_1}` lacks a translation.

The prompt MUST instruct the model that the transcript spans the whole interview, that the
delimited segment is the target competency, and that evidence from outside that segment is
admissible when it genuinely bears on the indicator.

`config/scoring.php` `prompt_version` MUST be bumped to a new **major** version, because
evaluations produced after this change are not comparable with evaluations produced before it.
The value in force is `3.0.0`.

> **Deployment note (verified 2026-08-25, still binding).** Both the Railway `api` AND
> `worker` services pin `SCORING_PROMPT_VERSION` explicitly, so the `config/scoring.php`
> default never reaches either. Scoring runs inside `ScoreEvaluationJob`, a QUEUED job — the
> `worker` is the service that actually stamps provenance. Bumping only `api` leaves every
> production evaluation stamped with the old version while being scored under the new
> calibration, with no symptom anywhere. Any future `prompt_version` bump MUST update both.

(Previously: the system prompt carried no severity guidance of any kind, and the transcript
was presented as if it were the entire relevant evidence for the one competency being scored.)

#### Scenario: Standards block present and consistent with the procedure

- GIVEN a competency with indicators and a valid locale
- WHEN the scoring prompt is built
- THEN the system prompt contains an EVALUATION STANDARDS section
- AND it states that 3 is the baseline and that 4 and 5 are rare
- AND it names all three requirements for a high score: specific situation, concrete actions, measurable outcome
- AND it does not instruct the model to prefer an intermediate level over a matching authored anchor

#### Scenario: Standards block is English under a non-English locale

- GIVEN a project locale of `it`
- WHEN the scoring prompt is built
- THEN the EVALUATION STANDARDS section is in English
- AND the indicator rubric is in Italian

#### Scenario: Prompt explains the delimited target segment

- GIVEN a prompt corpus containing a delimited COL segment among other competencies
- WHEN the scoring prompt is built for COL
- THEN the system prompt names the delimiter
- AND instructs the model to weight the delimited segment while admitting corroborating evidence from elsewhere

#### Scenario: Missing anchor translation still hard-fails

- GIVEN an indicator lacking an `anchor_3` translation for the project locale
- WHEN the scoring prompt is built
- THEN `AnchorTranslationMissingException` is thrown
- AND no prompt is produced

#### Scenario: prompt_version reflects the recalibration

- GIVEN the scoring configuration after this change
- WHEN a scoring call records its provenance
- THEN `prompt_version` is a major version greater than the one recorded before this change

---

### Requirement: Reliability (R-A) and Validity (V-A)

`reliability` for each competency MUST be computed as `assessed / total` where assessed
excludes `-1` sentinels (R-A assessable-fraction formula). A competency is VALID iff
`reliability >= T` where T defaults to 50% and MUST be injectable via config without code
change. Reliability MUST be stored as a numeric value `[0..1]` (as `numeric(5,4)`) internally
and rendered as a percentage integer at the API/webhook boundary. The rendering formula MUST
be: `(int) round($reliabilityDbValue * 100, 0, PHP_ROUND_HALF_UP)` — standard half-up
rounding to nearest integer (e.g. stored 0.6667 → 67%, not 66%). The `round()` MUST be
applied BEFORE the `(int)` cast: writing `(int)($value * 100)` silently truncates toward
zero and produces wrong results for fractional values. Equivalently, the boundary value may
be computed directly from raw counts as `(int) round($assessed / $total * 100, 0, PHP_ROUND_HALF_UP)`.
When the assessed set is empty, `ReliabilityStrategy` returns `0.0` (never NaN or throws).

#### Scenario: Golden cassette — SLF reliability 67%

- GIVEN SLF has 3 indicators with scores [5, 3, -1] (2 assessed of 3 total)
- WHEN reliability is computed
- THEN `reliability_numeric` = 2/3 ≈ 0.667 and the serialized boundary value = "67%"
- AND the rounding is standard half-up: `(int) round(2/3 * 100)` = 67 (not 66)

#### Scenario: COL reliability 100%

- GIVEN COL has 3 indicators all assessed: [5, 3, 3]
- WHEN reliability is computed
- THEN `reliability_numeric` = 3/3 = 1.0 and the serialized boundary value = "100%"

#### Scenario: Valid competency at default threshold

- GIVEN a competency with `reliability` = 0.5 and config T = 0.50
- WHEN the validity predicate is evaluated
- THEN the competency is VALID (reliability >= T)

#### Scenario: Invalid competency below threshold

- GIVEN a competency with `reliability` = 0.33 and config T = 0.50
- WHEN the validity predicate is evaluated
- THEN the competency is INVALID (reliability < T)

#### Scenario: T is injectable and configurable without code change

- GIVEN `SCORING_RELIABILITY_THRESHOLD=0.75` is set in environment config
- WHEN the validity predicate is evaluated for a competency with reliability = 0.67
- THEN the competency is INVALID (0.67 < 0.75)

---

### Requirement: Completion Gate

`total_competencies` is the count of `project_competencies` rows for the project, FIXED
at project creation. An Evaluation's status MUST be `completed` iff
`valid_competencies / total_competencies >= 0.90` (using `>=`; 9/10 = 90% qualifies).
If the ratio is below 0.90, status MUST be `pending`. Both statuses resolve the participant
to `completato`. A `pending` Evaluation carries partial data and MUST still be emitted for C10.

**Invariant guard**: if `total_competencies == 0`, the gate MUST NOT be evaluated. A
project with zero configured competencies is a data-integrity violation. The job MUST log an
invariant error and mark the participant `errore` without emitting `EvaluationCompleted`.
This guard prevents division-by-zero and surfaces the configuration defect explicitly.

`valid_competencies` = count of `CompetencyResult` rows where `valid = true`.

**Unscorable competency policy (default, CC1)**: unscorable competencies
(`anchor_translation_missing` or `role_no_bars`) are NOT valid and ARE counted in
`total_competencies` (they count against the gate). This is the default policy expressed
as `gate.count_unscorable_against_total = true` (config-flaggable; client must ratify
before go-live). When `false`, unscorables are excluded from both numerator and denominator.

#### Scenario: All competencies valid → completed

- GIVEN 10 project competencies, all 10 have reliability >= T
- WHEN the gate is evaluated
- THEN Evaluation status = `completed`

#### Scenario: 9 of 10 valid (90%) → completed

- GIVEN 10 project competencies, exactly 9 have reliability >= T
- WHEN the gate is evaluated
- THEN Evaluation status = `completed` (9/10 = 90% meets the threshold — uses `>=`)

#### Scenario: 8 of 10 valid (80%) → pending

- GIVEN 10 project competencies, 8 have reliability >= T and 2 do not
- WHEN the gate is evaluated
- THEN Evaluation status = `pending`

#### Scenario: Unscorables count against gate (default policy, CC1)

- GIVEN 10 project competencies, 2 are unscorable (`role_no_bars`), 7 of the remaining 8 are valid
- AND `gate.count_unscorable_against_total = true` (default)
- WHEN the gate is evaluated
- THEN `valid_competencies = 7`, `total_competencies = 10`, `7/10 = 70% < 90%`
- THEN Evaluation status = `pending`

#### Scenario: Pending evaluation still resolves participant to completato

- GIVEN an Evaluation with status = `pending`
- WHEN the scoring job finalizes
- THEN `participant.status` = `completato` (pending is an Evaluation sub-state only)

---

### Requirement: Excerpt Verbatim Validation

Every excerpt on an `IndicatorScore` MUST be validated against the **validation corpus**
(candidate utterances only — see Requirement: Transcript Assembly for Scoring) after
whitespace normalisation — collapsing runs of `\s+` (all whitespace including `\n`, `\t`,
multiple spaces) to a single U+0020 on both sides and trimming. The **original** excerpt
text is persisted in `IndicatorScore.excerpts`, never the normalised form. The system MUST
NOT accept paraphrased, summarized, or invented text for any indicator.

An excerpt containing an **elision marker** — `...` (three ASCII periods) or `…` (U+2026) —
MUST be accepted when its fragments appear in the validation corpus **in order, each strictly
after the previous fragment ended**. Matching MUST be an anchored forward walk with no
backtracking: it MUST NOT be implemented as a regex wildcard, and it MUST NOT accept a quote
whose fragments appear in the corpus in a different order from the one the excerpt asserts.

Empty fragments — produced when an excerpt opens or closes with an elision, or contains two
adjacent markers — MUST be discarded before matching, so that a zero-length needle can never
be the reason a quote is accepted.

An excerpt that fails validation MUST NOT discard its sibling indicators: the affected
indicator alone is persisted with `score = -1` and
`unassessable_reason = 'excerpt_unverifiable'`, as already specified by
Requirement: Per-Indicator Validation-Failure Isolation.

A `score = -1` with an empty excerpts array MUST skip excerpt validation entirely.

Cross-utterance excerpts remain PERMITTED **within the validation corpus**: an excerpt may
span consecutive candidate utterances, because the corpus is one assembled string.

(Previously: validation ran against the single assembled transcript, which included the
interviewer's `avatar:` lines — so an excerpt quoting the interviewer's own question passed
as evidence about the candidate. And matching was a bare `str_contains`, so any quotation
containing an elision — the natural shape a real evaluator produces — was rejected outright.
Earlier still, a non-verbatim excerpt "flagged the competency result as invalid" via the
single competency-wide `try`/catch, discarding every already-validated sibling indicator.)

#### Scenario: Excerpt quoting the interviewer is rejected

- GIVEN the LLM returns the excerpt `Tell me about a time you overruled your team` for indicator I
- AND that sentence was spoken by `avatar`, not by `candidate`
- WHEN excerpt validation runs
- THEN the excerpt is not verbatim in the validation corpus
- AND indicator I alone is persisted with `score = -1` and `unassessable_reason = 'excerpt_unverifiable'`
- AND every sibling indicator of the same competency retains its own score

#### Scenario: Elided excerpt with ASCII ellipsis is accepted

- GIVEN the candidate said `Nel giro di quattro mesi abbiamo rifatto la pipeline e il tempo medio è crollato a otto minuti`
- AND the LLM returns the excerpt `Nel giro di quattro mesi... il tempo medio è crollato`
- WHEN excerpt validation runs
- THEN the excerpt is accepted
- AND the excerpt is persisted with its original text, elision marker included

#### Scenario: Elided excerpt with U+2026 is accepted

- GIVEN the same candidate utterance
- AND the LLM returns the excerpt `Nel giro di quattro mesi… il tempo medio è crollato`
- WHEN excerpt validation runs
- THEN the excerpt is accepted

#### Scenario: Out-of-order fragments are rejected

- GIVEN the candidate said `Nel giro di quattro mesi abbiamo rifatto la pipeline e il tempo medio è crollato`
- AND the LLM returns the excerpt `il tempo medio è crollato... Nel giro di quattro mesi`
- WHEN excerpt validation runs
- THEN the excerpt is rejected, because the second fragment does not occur after the first one ended
- AND indicator I is persisted with `score = -1` and `unassessable_reason = 'excerpt_unverifiable'`

#### Scenario: Fragments must not overlap

- GIVEN the candidate said `abbiamo rifatto la pipeline`
- AND the LLM returns the excerpt `abbiamo rifatto la...rifatto la pipeline`
- WHEN excerpt validation runs
- THEN the excerpt is rejected, because the second fragment's match would have to start before the first fragment ended

#### Scenario: Leading elision is discarded, not treated as an empty match

- GIVEN the candidate said `il tempo medio è crollato a otto minuti`
- AND the LLM returns the excerpt `...il tempo medio è crollato`
- WHEN excerpt validation runs
- THEN the leading empty fragment is discarded
- AND the excerpt is accepted on the strength of its non-empty remainder alone

#### Scenario: An elision does not license invented text

- GIVEN the candidate said `abbiamo rifatto la pipeline`
- AND the LLM returns the excerpt `abbiamo rifatto la pipeline... e ho licenziato il team`
- WHEN excerpt validation runs
- THEN the excerpt is rejected, because the second fragment appears nowhere in the validation corpus

#### Scenario: Non-elided excerpts keep their existing behaviour

- GIVEN the LLM returns an excerpt with no elision marker that is a verbatim substring of the validation corpus
- WHEN excerpt validation runs
- THEN the excerpt is accepted, exactly as before this change

#### Scenario: Cross-utterance excerpt from the candidate still validates

- GIVEN two consecutive `candidate` utterances whose texts, joined, contain the excerpt after whitespace normalisation
- WHEN excerpt validation runs
- THEN the excerpt is accepted

#### Scenario: Non-verbatim excerpt is contained to its own indicator, siblings survive

- GIVEN competency COL has 3 indicators and indicator 2's excerpt "candidate showed collaboration" is absent from the validation corpus
- WHEN the excerpt is validated
- THEN indicator 2 is persisted with `score = -1`, `unassessable_reason = 'excerpt_unverifiable'`
- AND indicators 1 and 3, which validated cleanly, retain their own scores
- AND the competency is NOT discarded — it survives with a lower reliability

#### Scenario: Whitespace normalization — multi-space collapsed

- GIVEN an excerpt "foo  bar" and the validation corpus containing "foo bar" (single space)
- WHEN both are whitespace-normalized and the match runs
- THEN the excerpt is accepted

#### Scenario: Whitespace normalization — newline and tab collapsed

- GIVEN an excerpt "foo\nbar" and the validation corpus containing "foo bar" (single space)
- WHEN both are whitespace-normalized (all `\s+` → single space)
- THEN the excerpt is accepted

---

### Requirement: Non-EN Anchor Language (L-2 Hard-Fail)

The engine MUST score each competency in the project's configured language. `PromptBuilder`
MUST check translations via `hasTranslation($field, $projectLocale)` for ALL FOUR
translatable fields of each `BarsIndicator`: `text`, `anchor_5`, `anchor_3`, and `anchor_1`.
It MUST NOT use the convenience method `hasTranslationGap()` (hardcoded to `'it'`, which
would silently mis-evaluate non-IT projects). A missing `indicator.text` translation in the
project locale is as corrupting as a missing anchor — the prompt would inject an EN indicator
description alongside localized anchors, producing an incoherent rubric. If ANY of the four
fields is missing a project-locale translation, the engine MUST hard-fail that competency:
mark it unscorable and record the reason as `anchor_translation_missing`. The engine MUST
NEVER silently fall back to English for any of the four fields. An unscorable competency
counts against the 90% gate (see Completion Gate requirement for the full policy and
config-flaggable override).

#### Scenario: Missing IT anchor → competency hard-failed, no EN fallback

- GIVEN project language = `it` and competency COL has no Italian anchor translations for `anchor_5`
- WHEN the engine attempts to score COL
- THEN COL is marked unscorable with reason `anchor_translation_missing`
- AND NO LLM call is made using English anchors
- AND the `hasTranslation($field, 'it')` check (not `hasTranslationGap()`) is used for each of {text, anchor_5, anchor_3, anchor_1}

#### Scenario: Missing IT indicator text → competency hard-failed (text field in scope)

- GIVEN project language = `it` and competency INN has all three anchor translations but no Italian `text` for one indicator
- WHEN the engine checks translations for INN
- THEN INN is marked unscorable with reason `anchor_translation_missing`
- AND no LLM call is made (missing `text` in project locale is a hard-fail, same as missing anchor)

#### Scenario: Present anchor passes through normally

- GIVEN project language = `it` and competency COM has Italian anchor translations
- WHEN the engine scores COM
- THEN the Italian anchor texts are injected into the prompt and scoring proceeds normally

---

### Requirement: Missing Catalog Data — Skip and Flag

If a role has no BARS anchors for a competency (e.g. a future role with no
`bars/{ROLE}.json` yet, or a competency absent from an existing role's BARS
file), the engine MUST skip that competency and flag it with reason
`role_no_bars`. The engine MUST NOT crash or throw an unhandled exception.
The flag is visible in the Evaluation result for observability. An
unscorable competency (`role_no_bars`) counts against the 90% gate (see
Completion Gate requirement for the full policy).
(Previously: the illustrative example and its scenario named SRX as the
missing-BARS role — `bars/SRX.json` did not exist. After
`bars-catalogue-completion`, all 83 declared role×competency pairs,
including all of SRX, have anchors, so `role_no_bars` is a defensive-only
path with no real-catalog occurrence today; the example and scenario are
restated against a fixture.)

#### Scenario: Role with no BARS anchors (fixture) → skipped and flagged

- GIVEN a project uses a role×competency pair with no BARS anchors in the
  catalog (test fixture — post-completion, no real declared role×competency
  pair lacks anchors)
- WHEN the engine processes that project's competencies
- THEN the affected competency is skipped, flagged `role_no_bars`, and no
  LLM call is made
- AND no `ai_requests` row is created for the skipped competency

### Requirement: LLM Parse Error — Persistent Malformed Output

When the LLM returns output that cannot be parsed into valid per-indicator results after
the fence/prose tolerance pass (see Requirement: Fence and Leading/Trailing Prose
Tolerance) — including wrong indicator count or JSON that remains invalid after that
tolerance — the competency MUST be marked with `unscorable_reason = 'llm_parse_error'`
and `score = NULL`, `valid = false`. A response whose `finish_reason` indicates
truncation MUST NOT be marked `llm_parse_error`; it is a distinct class (see
Requirement: Truncation Detected From `finish_reason` Before Parsing). Neither class
triggers a queue retry directly; both ARE counted in the gate denominator.
(Previously: rejection criteria was scores outside `{1,3,5,-1}` with zero
pre-processing before `json_decode`, so a markdown-fenced body or a truncated
response both surfaced as the same generic `llm_parse_error`.)

#### Scenario: Persistent invalid JSON, not fenced and not truncated → llm_parse_error

- GIVEN the LLM returns syntactically invalid JSON for competency STG, with no leading/trailing fence and `finish_reason != 'max_tokens'`
- WHEN `EvaluationParser` applies fence/prose tolerance and still cannot decode the body
- THEN the competency is marked `llm_parse_error` with `score = NULL`, `valid = false`
- AND no queue retry is dispatched for this competency
- AND scoring continues to the next competency

#### Scenario: Truncated response is never mislabeled llm_parse_error

- GIVEN a provider response for competency PRS with `finish_reason = 'max_tokens'` and a body that would otherwise fail `json_decode`
- WHEN the engine processes the response
- THEN the competency's `unscorable_reason` is `llm_truncated`, never `llm_parse_error`

---

### Requirement: Fence and Leading/Trailing Prose Tolerance

`EvaluationParser` MUST strip a single leading/trailing markdown code fence (e.g.
` ```json ... ``` `) and any surrounding conversational prose before calling
`json_decode()`. This tolerance is NARROW and NAMED: it MUST NOT become a general
"locate JSON anywhere in the body" salvage routine. Any body that, after stripping at
most one leading and one trailing fence/prose wrapper, still fails `json_decode()` MUST
hard-fail exactly as before (see Requirement: LLM Parse Error).

#### Scenario: Markdown-fenced JSON parses successfully

- GIVEN a provider response body ` ```json\n{"indicators": [...]}\n``` ` for competency COL
- WHEN `EvaluationParser::parse()` runs
- THEN the fence is stripped, `json_decode()` succeeds, and COL scores normally

#### Scenario: Leading conversational prose is stripped

- GIVEN a response body "Here is the evaluation:\n{"indicators": [...]}"
- WHEN `EvaluationParser::parse()` runs
- THEN the leading prose is stripped and the JSON parses successfully

#### Scenario: A genuinely malformed body still hard-fails (negative cassette)

- GIVEN a response body with a stray trailing comma inside the JSON structure itself (not a fence/prose wrapper)
- WHEN `EvaluationParser::parse()` runs, including the fence/prose tolerance pass
- THEN `json_decode()` still fails and the competency is marked `llm_parse_error`
- AND no salvage attempt beyond one leading/trailing strip occurs

---

### Requirement: Truncation Detected From `finish_reason` Before Parsing

Before any parse attempt, the engine MUST inspect the provider response's
`finish_reason` (already carried by `LLMResponse::$finishReason` into
`ai_requests.finish_reason`, per `observability`). If `finish_reason` indicates
truncation (provider's max-output-tokens stop), the engine MUST short-circuit to a
distinct, truncation-specific failure class BEFORE attempting `json_decode()`. This
value MUST NOT collapse into `llm_parse_error`. `CompetencyResult.unscorable_reason`
MUST be `llm_truncated` for this class (superseding the Coverage Note's pinned
three-value enum — see Requirement: Unscorable Reason Enum Widens Beyond Three Values).

#### Scenario: Truncated response short-circuits before json_decode

- GIVEN a provider response with `finish_reason = 'max_tokens'`
- WHEN the engine processes the response
- THEN `unscorable_reason = 'llm_truncated'` is recorded WITHOUT ever calling `json_decode()` on the body
- AND the underlying `ai_requests` row records `finish_reason = 'max_tokens'` and a truncation-specific `failure_reason` (see `observability`)

#### Scenario: A non-truncated finish_reason proceeds to normal parsing

- GIVEN a provider response with `finish_reason = 'end_turn'`
- WHEN the engine processes the response
- THEN parsing proceeds normally (fence/prose tolerance, then `json_decode()`)

---

### Requirement: Truncation-Only Retry At An Enlarged Budget

When a competency's scoring call is short-circuited as truncated (see Requirement:
Truncation Detected From `finish_reason` Before Parsing), the engine MUST retry that
ONE call exactly once, at a configurably enlarged `max_tokens` budget (doubled by
default, config-driven), before finalizing the competency as unscorable. The retry
attempt MUST produce its OWN `ai_requests` row (never reuse or update the first
attempt's row) — every call is billed and every call is logged. This retry applies
ONLY to the truncation class: fence/prose failures, indicator count mismatch,
illegal scores, and non-verbatim excerpts remain non-retryable exactly as before (D4
FIX-9 stands for every class it already correctly covers).

This retry is a queue-job-internal, same-competency, same-interview retry of one LLM
call. It is NOT the domain-level candidate retry (RT-B, Requirement: Retry — Single
Re-Interview of a `pending` Evaluation (RT-B)) — RT-B re-interviews the candidate and is untouched by this requirement.

#### Scenario: A truncated call retries once at double the budget and succeeds

- GIVEN competency PRS truncates at `max_tokens = 2048`
- WHEN the engine retries with `max_tokens = 4096`
- AND the retried call returns `finish_reason = 'end_turn'` with valid JSON
- THEN PRS scores normally from the retried response
- AND TWO `ai_requests` rows exist for PRS: the failed truncated attempt and the successful retry

#### Scenario: A retry that also truncates finalizes as unscorable, no second retry

- GIVEN competency PRS truncates on the first attempt
- WHEN the retry at the enlarged budget ALSO returns `finish_reason = 'max_tokens'`
- THEN PRS is finalized with `unscorable_reason = 'llm_truncated'`
- AND no third attempt is made (the cap is exactly one retry)
- AND TWO `ai_requests` rows exist for PRS, both marked `success = false`

#### Scenario: A fence/prose failure is never retried at an enlarged budget

- GIVEN competency STG fails with a genuinely malformed body (`llm_parse_error`) and `finish_reason = 'end_turn'` (not truncated)
- WHEN the engine handles the failure
- THEN no enlarged-budget retry is attempted for STG
- AND exactly ONE `ai_requests` row exists for STG

---

### Requirement: Per-Indicator Validation-Failure Isolation

`ScoreEvaluationJob`'s per-competency validation MUST catch validation failures at the
INDICATOR level, not with a single `try`/catch spanning every indicator DTO in the
competency. An indicator that fails validation (illegal score, or non-verbatim excerpt)
MUST be persisted as `IndicatorScore.score = -1` with an `unassessable_reason` (see
Requirement: Indicator Validation-Failure Reason Vocabulary), while sibling indicators that validated cleanly
in the SAME competency, whether validated before or after the failing one in processing
order, MUST retain their own scores. The competency's mean and reliability are then
computed over whatever the isolated set produces — no formula changes (see
`scoring-model`'s Validation-Failure Reason Is Excluded From Every Scoring Formula
requirement). Competency-envelope failures (parse, truncation, indicator count
mismatch) are UNAFFECTED by this requirement: there are no per-indicator DTOs to
isolate when the envelope itself did not parse.

#### Scenario: One unverifiable excerpt out of three leaves two indicators scored

- GIVEN competency COL has 3 indicators; indicators 1 and 3 validate cleanly with scores 5 and 3; indicator 2's excerpt is not verbatim
- WHEN `scoreCompetency()` runs
- THEN indicator 2 persists as `score = -1`, `unassessable_reason = 'excerpt_unverifiable'`
- AND indicators 1 and 3 persist their own scores
- AND COL's `reliability` = 2/3 ≈ 0.667, NOT 0 — COL is not discarded

#### Scenario: A failing indicator earlier in processing order does not poison later ones

- GIVEN competency DRV has 3 indicators; indicator 1 has an illegal score; indicators 2 and 3 have not yet been processed
- WHEN `scoreCompetency()` processes indicators in order
- THEN indicator 1 persists as `score = -1, unassessable_reason = 'score_illegal'`
- AND indicators 2 and 3 are still evaluated and persist normally if they validate

### Requirement: Indicator Validation-Failure Reason Vocabulary

Every `IndicatorScore` MUST carry a nullable `unassessable_reason` attribute
distinguishing WHY a `-1` score exists, from exactly three values: `model_declared`
(the LLM itself returned `-1` — no assessable evidence), `excerpt_unverifiable` (the
LLM claimed evidence that failed the verbatim-substring check), and `score_illegal`
(the LLM returned a value outside `{1,2,3,4,5,-1}`). The column is nullable (null when
`score != -1` is not applicable, or for pre-migration rows) and UNCONSTRAINED — no
Postgres CHECK constraint — so the vocabulary MAY extend later without a migration.
`unassessable_reason` is METADATA ONLY: no scoring formula (`MeanCalculator`,
`AssessableFractionReliability`, `CompletionGate`) MAY read it (see `scoring-model`).

#### Scenario: The three reasons are each independently producible

- GIVEN three indicators in one competency: one the LLM declares `-1`, one with an unverifiable excerpt, one with an illegal score
- WHEN validation runs
- THEN the three `IndicatorScore` rows carry `unassessable_reason` values `model_declared`, `excerpt_unverifiable`, and `score_illegal` respectively, all with `score = -1`

#### Scenario: A cleanly-assessed indicator carries a null reason

- GIVEN an indicator that validates with a legal score in `{1,2,3,4,5}`
- WHEN it is persisted
- THEN `IndicatorScore.unassessable_reason` is `null`

### Requirement: Unscorable Reason Enum Widens Beyond Three Values

`CompetencyResult.unscorable_reason` MUST accept a fourth value, `llm_truncated`, in
addition to the three already in force (`anchor_translation_missing`, `role_no_bars`,
`llm_parse_error`). This requirement SUPERSEDES the scoring-engine spec's Coverage
Note text pinning the enum at exactly three values; that note MUST be updated to
reflect four values when this delta is merged, and the widening MUST NOT be read as a
regression against the three-value pin. The column remains a plain string with no
Postgres CHECK constraint, so this widening is schema-safe.

#### Scenario: llm_truncated is a legal, distinct unscorable_reason value

- GIVEN a competency finalized as truncated after the retry (see Requirement:
  Truncation-Only Retry At An Enlarged Budget)
- WHEN `CompetencyResult.unscorable_reason` is read
- THEN it equals `llm_truncated`, distinguishable from `llm_parse_error`,
  `anchor_translation_missing`, and `role_no_bars`

---

### Requirement: Evaluation Versioning

Each `Evaluation` record MUST store `framework_version_id`, `model_version`, and
`prompt_version` as non-null fields at the time of job execution. These fields MUST NOT
be mutable after the job completes. The `ai_requests` log MUST also record these values
per LLM call for audit and cost-tracking purposes.

#### Scenario: Evaluation versioning fields populated

- GIVEN a scoring job completes for participant P
- WHEN the `Evaluation` record is read
- THEN `framework_version_id`, `model_version`, and `prompt_version` are all non-null
- AND they reflect the values active at the time of job dispatch, not the current live values

---

### Requirement: Tenant Scoping

All reads and writes in the scoring pipeline MUST be scoped by `organization_id`.
Cross-tenant isolation MUST be enforced at the query layer (global `TenantScoped` scope).
A scoring job for org A MUST NOT read anchors, participants, sessions, or write evaluation
rows belonging to org B.

#### Scenario: Cross-tenant evaluation isolation

- GIVEN participant P_A in org A and participant P_B in org B exist
- WHEN `ScoreEvaluationJob` runs for P_A
- THEN all DB reads and writes are scoped to org A; org B data is never accessed

Write-side scoping MUST use tenant context re-derived from `P_A`'s own
`organization_id` at job execution time — never from the ambient
`TenantResolver` state left over from a prior request or job (see `tenancy`
capability). This applies to every tenant-scoped write the job performs:
the `Evaluation`, `AiRequest`, `CompetencyResult`, and `IndicatorScore` rows.
(Previously: stated the isolation goal without specifying how write-side org
context is established for a queued job; this closes the ambient-state gap
that let the job stamp a null or foreign org.)

#### Scenario: All four scoring writes stamped under the participant's org

- GIVEN `ScoreEvaluationJob` runs for participant P_A (org A)
- AND the ambient `TenantResolver` holds no org (post `Queue::before` reset)
  or a foreign org
- WHEN the job creates the `Evaluation`, `AiRequest`, `CompetencyResult`,
  and `IndicatorScore` rows
- THEN every created row's `organization_id` equals org A
- AND no row is created with a null or foreign `organization_id`

---

## Non-Goals (Explicit)

- **Webhook delivery** (C10): this spec stops at event emission; C10 owns HTTP delivery.
- **Dashboards / report viewer** (C11): no rendering concerns here.
- **Adaptive question selection / answer-attribution** (C8).
- **GDPR media retention and purge** (C13): C9 reads transcripts but never deletes media.
- **Authoring non-EN BARS anchors**: client/C3 deliverable; C9 only reads and fails hard.
- **Missing catalog authoring** (MTG/LAT): client deliverable.

---

## Coverage Note

The following correctness-critical paths MUST be held to ~95% test coverage: indicator
domain validation (`{1,2,3,4,5}∪{-1}`); server-side competency mean (denominator = assessed
count); `MeanCalculator` returns null (not NaN/throw) when assessed set is empty;
`ReliabilityStrategy` returns 0.0 for empty assessed set; reliability R-A formula;
reliability % rounding (standard half-up: 2/3 → 67%); **reliability rendering round-before-cast
(`(int) round($value * 100)`, not `(int)($value * 100)`)** ; competency score rounding to 2dp
(3.666… → 3.67, `PHP_ROUND_HALF_UP`); validity predicate with injectable T; 90% gate
(`completed`/`pending`); **gate invariant guard (`total_competencies == 0` → `errore`, no division)**;
unscorable competencies counted in denominator (default policy);
excerpt verbatim substring check against the **validation corpus** (whitespace-normalized,
cross-utterance, candidate-only); elision-tolerant matching as an anchored forward walk
(in-order fragments accepted; out-of-order, overlapping, invented and zero-length fragments
rejected); score -1 with
empty excerpts passes validation; the two-corpora split and its subset invariant
(`ScoringCorpora {prompt, validation}` from ONE ordered fetch); target-segment markers in the
prompt corpus only, and never emitted around an empty segment; case-insensitive `speaker`
match for the validation corpus; transcript assembled with `orderBy('ts')->orderBy('id')`
(tiebreaker determinism); the EVALUATION STANDARDS block present, English under any locale,
and not repealing the anchor-primacy tie-break (the step-5 scoping guard);
indicator count mismatch → `llm_parse_error` (no queue retry);
indicator mapping by array position (not string-match); L-2 hard-fail covers `{text, anchor_5,
anchor_3, anchor_1}` (not anchors-only); tenant scoping (cross-org isolation);
Evaluation versioning fields non-null; Evaluation created at job START; start-of-job guard
(errore → no-op; existing {completed|pending} Evaluation + retry_attempt=false → no-op;
processing → resume-skip path, no duplicate LLM call; 23505 on INSERT → re-enter guard);
`CompetencyResult` unique-violation on resume → skip (not fail); `retry_attempt` read from
job payload not DB; `failed()` ships in PR 1 skeleton (not deferred to PR 3); `failed()`
guards participant status before transitioning; `failed()` emits EvaluationFailed even when
participant already errore; terminal-transition race guard (`errore` participant → skip
`in_valutazione→completato` but still persist Evaluation and emit EvaluationCompleted);
retry dispatch precondition (errore participant → retry NOT offered); L-2 hard-fail (no EN
fallback; `hasTranslation($field, $locale)` not `hasTranslationGap()`); `unscorable_reason`
enum is {`anchor_translation_missing`, `role_no_bars`, `llm_parse_error`, `llm_truncated`}
(four values, widened by `scoring-failure-containment` — see Requirement: Unscorable Reason
Enum Widens Beyond Three Values); truncation detected from `finish_reason` before parse,
short-circuited before `json_decode()`, never mislabeled `llm_parse_error`; fence/leading-
trailing-prose tolerance in `EvaluationParser`, narrow and named, negative cassettes still
hard-fail; truncation-only retry at an enlarged budget (capped at one, config-driven), each
attempt its own `ai_requests` row; per-indicator validation-failure isolation — the job's
per-competency validation catches at the INDICATOR level (a `try` inside the per-indicator
loop, not a single `try` spanning the whole competency), so an illegal score or unverifiable
excerpt on one indicator no longer discards its already-validated siblings;
`unassessable_reason` indicator-grain vocabulary (`model_declared`, `excerpt_unverifiable`,
`score_illegal`), nullable and unconstrained, metadata-only (no formula reads it);
`evaluated_at` nullable while processing; golden cassette (COL 3.67, SLF 4.0 @ 67%
reliability — requires `CassetteLLMProvider` keyed by `competency_code`); unit tests for
position-mapping, score-domain, count mismatch, and rounding use single-response
`FakeLLMProvider` (no `CassetteLLMProvider` needed for those); determinism (same input →
same output); `ScoreEvaluationJob::failed()` → errore + event; `indicator_text` persisted
in project scoring locale from pinned catalog version.

---

## Quality Debt (Documented — First-Pass Delivery)

Known gaps documented at archive time (2026-07-22), to be addressed in a follow-up pass:

1. **Pint violations in 3 test files**: `LifecycleResolutionTest.php`, `ZeroCompetenciesGuardTest.php`,
   `GoldenCassetteTest.php` — minor style violations in test files only, not production code.
2. **ScoreEvaluationJob at 81.3% coverage** (target ~95% for critical zone): uncovered
   branches are edge cases (null participant, null project, double re-entry, CW5 unique violation
   on scoreCompetency, alt unscorable policy=false, secondary PromptBuilder throw path,
   persistUnscorable() unique violation, resolveFrameworkVersionId null project, failed()
   transition catch). Several are near-impossible in production given C6 minting guarantees.
3. **RoleNoBarsException at 0% direct coverage**: exercised indirectly via AiRequestLoggingTest
   and LifecycleResolutionTest; the exception class constructor line is never explicitly hit.
4. **No standalone determinism run-twice test**: the golden cassette with CassetteLLMProvider
   at temperature=0 provides de-facto determinism evidence; a dedicated run-twice test is absent.

Carried forward from `evaluator-evidence-and-rigor` verification (2026-08-28). These were
WARNINGs, not blockers — the change archived as PASS WITH WARNINGS — but they are open and
they belong here, not only in the archived folder.

5. **A corpora swap in `ScoreEvaluationJob` would not fail any test.** `ScoreEvaluationJob`
   line 597 sets `$validationCorpus = $corpora->validation` and line 771 passes it to
   `ExcerptValidator::validate()` — correct today. But the subset invariant means the two
   corpora are distinguishable ONLY by content unique to the prompt corpus: avatar-spoken
   text or a segment marker. All 27 test files that exercise that job fixture
   `'speaker' => 'Candidate'` utterances only, so rewriting line 771 to pass `$transcript`
   (the prompt corpus) would leave the entire suite green — on precisely the defect this
   change exists to fix. Consequently the scenario **"Excerpt quoting the interviewer is
   rejected"** (Requirement: Excerpt Verbatim Validation) has **no single covering test**: it
   is assembled from `TranscriptAssemblerTest` (corpus excludes avatar text) plus
   `PerIndicatorIsolationTest` (unverifiable excerpt → `-1` + `excerpt_unverifiable`, no
   sibling dropped). Status: PARTIAL, not untested. **Concrete fix**: one job-level test with
   an `avatar` utterance whose text the cassette then cites as an excerpt, asserting the
   indicator lands at `-1`. Until that exists, the wiring is held by review, not by CI.
6. **`PerIndicatorIsolationTest` never demonstrates a surviving positive sibling.** It ends
   with all three indicators at `-1` (a different reason each), so the clause "every sibling
   indicator retains its own score" — present in this spec in three separate requirements — is
   asserted nowhere with an actual surviving score. Minor, but the isolation guarantee is the
   whole point of the requirement.
7. **The drift gate has never run against `prompt_version` 3.0.0** — see the ci-pipeline
   capability, Requirement: A Skipped `@ai` Guard Test MUST NOT Report Success. Nothing in CI
   has verified that the recalibrated prompt still yields domain-legal, residual-reachable
   scores from the live model, and 3.0.0 is in production. The static guards
   (`PromptBuilderTest` anchor-primacy and step-5 scoping cases) prove the prompt TEXT is
   intact and DO run; they say nothing about model behaviour.

<!-- promoted from notifications-reminders (C12) -->

### Requirement: EvaluationFailed Is a Notification Trigger; Payload Stays Minimal

`EvaluationFailed` MUST continue to carry only `participantId` (no `organization_id`, no
denormalized copy of any tenant-scoped field) — the `notifications` capability's dispatcher
job re-derives `organization_id` fresh from the `Participant` DB record at execution time,
never from the event payload, per the tenancy capability's re-derivation rule. Scoring-engine
code MUST NOT itself resolve notification recipients, render copy, or perform a send in
response to this event — a listener external to this capability owns that behavior.

#### Scenario: EvaluationFailed triggers exactly one notification, event payload unchanged

- GIVEN `ScoreEvaluationJob::failed()` emits `EvaluationFailed(participantId: P)`
- WHEN the event is observed by the `notifications` capability's listener
- THEN exactly one `scoring_failed` notification is triggered for the organization owning
  participant P
- AND the event payload carries only `participantId` — no `organization_id` field was added
  to satisfy this requirement

#### Scenario: Notification dispatcher re-derives org from the participant record, not the event

- GIVEN `EvaluationFailed(participantId: P)` is dispatched while the ambient `TenantResolver`
  holds a foreign or null org
- WHEN the notification dispatcher job runs
- THEN it reloads participant P from the DB and derives `organization_id` from that reload
- AND no notification-related row or recipient uses an org value taken directly from the event
  object or the ambient resolver

#### Scenario: Scoring-engine code performs no notification logic

- GIVEN `EvaluationFailed` is dispatched
- WHEN the scoring pipeline's own code (`ScoreEvaluationJob`, `EvaluationParser`, etc.) is
  inspected
- THEN none of it resolves notification recipients, renders notification copy, or sends mail —
  that logic lives exclusively in the `notifications` capability's listener and dispatcher job
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

