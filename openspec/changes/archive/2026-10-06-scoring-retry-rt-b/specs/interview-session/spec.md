# Delta for Interview Session

## MODIFIED Requirements

### Requirement: Participant lifecycle guard — allowed transitions only (CRITICAL-1)

The system MUST enforce that C7a fires ONLY the transitions in the COMPLETE
`$allowedTransitions` map below. The C6 map is INSUFFICIENT for C7a: it blocks
`in_attesa → errore` and `in_corso → errore`, which are required for provider
hard-failure on the first and subsequent competencies respectively. Both transitions
MUST be added or the provider failure path throws `ParticipantTransitionException` (422)
instead of the correct 502.

**REQUIRED complete `$allowedTransitions` map:**

| From | To (allowed) |
|---|---|
| `in_attesa` | `in_corso`, `errore` |
| `in_corso` | `in_valutazione`, `errore` |
| `in_valutazione` | `completato`, `errore` |
| `completato` | `in_attesa` (ONLY via the evaluation-retry authorization action) |
| `errore` | `in_attesa` (ONLY via the recovery action) |

(Previously: `completato` was terminal with an empty allowed set.)

Constraints:
- **FIX-5 (amended): every status key is explicit.** `$allowedTransitions['completato']`
  is exactly `['in_attesa']` and `$allowedTransitions['errore']` is exactly `['in_attesa']`.
  Neither may fall through to the `?? []` defensive default — both MUST appear in the map
  so intent is visible and auditable.
- The `completato → in_attesa` edge MUST be written ONLY by the evaluation-retry
  authorization action (see `participant-sso`: Requirement: Evaluation Retry Authorization
  Action). No other code path, including the SSO exchange, the entry-link mints, the
  recovery action and the scoring job, may write it.
- `completato → errore`, `completato → in_corso` and `completato → in_valutazione` MUST NOT
  be added.
- Both the `completato` and `errore` keys MUST be present explicitly.

C7a fires these specific transitions:
- `in_attesa → in_corso` (first `/start`)
- `in_corso → in_valutazione` (last `/end` via `FinalizeInterview` CAS)
- `in_attesa → errore` (provider hard-failure on the FIRST competency `/start`)
- `in_corso → errore` (provider hard-failure on a subsequent competency `/start`)

Any attempt to trigger an illegal transition (e.g., `in_valutazione → in_corso`) MUST raise `ParticipantTransitionException`, which MUST be caught and returned as HTTP 422.

#### Scenario: Illegal transition rejected

- GIVEN participant.status = 'in_valutazione'
- WHEN the system attempts to transition to 'in_corso'
- THEN ParticipantTransitionException is raised and HTTP 422 is returned

#### Scenario: Provider failure on first competency (in_attesa) → errore

- GIVEN participant.status = 'in_attesa' (first `/start`, no session yet in_corso)
- WHEN the provider returns a 5xx/timeout hard-failure
- THEN participant.status transitions to 'errore' (in_attesa → errore, now an allowed transition) and HTTP 502 is returned

#### Scenario: Provider failure on subsequent competency (in_corso) → errore

- GIVEN participant.status = 'in_corso' (at least one competency already finished) and a fatal provider REST error during `/start`
- WHEN the error is caught and cannot be retried
- THEN participant.status transitions to 'errore' (in_corso → errore, allowed transition) and HTTP 502 is returned

#### Scenario: completato still cannot move to errore or any live state

- GIVEN a participant at `completato`
- WHEN code attempts `status = errore`, `in_corso` or `in_valutazione`
- THEN `ParticipantTransitionException` is raised and the record is not mutated

#### Scenario: completato to in_attesa is permitted only for the retry action

- GIVEN a participant at `completato` and the retry authorization action holding the participant row lock
- WHEN the action writes `status = in_attesa`
- THEN the guard permits the write
- AND an arch/feature test asserts no other caller writes this edge

## ADDED Requirements

### Requirement: The Finalize Trigger Dedup Is Attempt-Scoped For A Retry

The `finalize:{participant_id}` trigger dedup (FIX-4, TTL 7200 s) MUST NOT suppress the
scoring trigger of a retry re-interview. `FinalizeInterview` MUST read the participant's
Evaluation `retry_attempt` from the database (organization-filtered) and use the key
`finalize:{participant_id}` for the first attempt and `finalize:{participant_id}:retry` when the
flag is true. The dedup is therefore NOT released or cleared by the retry authorization (the
authorization never touches the cache): exactly one retry exists, so the two keys are a closed
set, and the choice is deterministic and transactional instead of depending on a cache write
that can be lost. A re-interview finished at any time after authorization emits the C9 trigger
exactly once. The FIX-4 exactly-once guarantee MUST otherwise be unchanged: within one interview
run a failed-and-retried `FinalizeInterview` job still emits the trigger once, and the
first-attempt key is unchanged.
(Previously: the first-run key was released after the authorization transaction committed.)

#### Scenario: A re-interview finished within two hours is not dropped

- GIVEN a participant whose first run set `finalize:{participant_id}` less than 2 hours ago
- AND a retry has since been authorized for that participant (the Evaluation has `retry_attempt = true`)
- WHEN the re-interview's last `/end` fires `FinalizeInterview`
- THEN the C9 trigger is emitted exactly once, under `finalize:{participant_id}:retry`, and
  `ScoreEvaluationJob` is dispatched with `retry_attempt = true`

#### Scenario: A queue retry of FinalizeInterview within the retry run still emits once

- GIVEN a retry re-interview's `FinalizeInterview` job fails after setting the dedup and is retried by the queue
- WHEN the retried job runs
- THEN no second C9 trigger is emitted

#### Scenario: The first-attempt key is unchanged

- GIVEN a participant whose Evaluation has `retry_attempt = false`, or has no Evaluation yet
- WHEN `FinalizeInterview` fires
- THEN the dedup key is exactly `finalize:{participant_id}`

#### Scenario: The authorization does not touch the dedup

- GIVEN a retry authorization, successful or refused
- WHEN it completes
- THEN `finalize:{participant_id}` is neither read, written nor deleted by it

### Requirement: Re-Interview Offers Only Competencies Without A Valid Result

During a retry, the competency resolver MUST offer only competencies whose session is
`pending` or missing. Sessions of valid competencies MUST remain `completed` and untouched;
sessions of invalid competencies are reset to `pending` by the retry authorization action
(refs, ended reason and ended-at cleared, utterances deleted). The candidate re-entering
through the new link MUST therefore never be re-asked a competency whose result was valid.

#### Scenario: Only invalid competencies are re-asked

- GIVEN a retry authorized with INN and STG invalid and 8 other competencies valid
- WHEN the candidate re-enters and the interview resolves the next competency repeatedly
- THEN it returns INN, then STG, then reports the interview complete
- AND none of the 8 valid competencies is offered

#### Scenario: Reset sessions start clean

- GIVEN the INN session had utterances from the first interview
- WHEN the retry is authorized
- THEN the INN session is `pending` with `provider_session_ref`, `ended_reason` and `ended_at` cleared
- AND its utterances are deleted
