# Delta for Webhooks Integration

## MODIFIED Requirements

### Requirement: Idempotency — stable delivery id and dedupe key

`X-BEAI-Delivery-Id` MUST be a UUID generated once at row creation. A UNIQUE index on
`(organization_id, project_id, event_type, dedupe_key)` MUST collapse duplicate
emissions of the same logical event into one delivery row. For `progress` events,
`dedupe_key` MUST be derived from the participant and the triggering boundary (creation,
or the specific competency just completed) so that a race producing two "creation"
triggers for the same candidate collapses into one row. For `evaluation` events,
`dedupe_key` MUST be the `evaluation_id`, EXCEPT for the evaluation event produced by an
authorized retry (RT-B), whose `dedupe_key` MUST be `{evaluation_id}:retry`. For
`competency-ended` `progress` events recorded while the participant's Evaluation has
`retry_attempt = true`, the `dedupe_key` MUST carry the `:retry` suffix
(`competency-ended:{participant_id}:{competency_code}:retry`). The distinct keys are what
let the definitive post-retry `evaluation` webhook and the re-interview's progress events
reach the integrating system instead of being absorbed by the rows of the first run. BEAI
guarantees at-least-once delivery, never exactly-once; receivers MUST treat a repeated
`X-BEAI-Delivery-Id` as a no-op.
(Previously: the evaluation `dedupe_key` was always the bare `evaluation_id` and the
`competency-ended` key had no retry-era form, so the second `evaluation` event and the
re-interview progress of a retried participant would have collapsed into the first run's rows.)

The `evaluation` `dedupe_key` is derived from the Evaluation row's `retry_attempt`, and the
failed-evaluation path keeps the bare `evaluation_id` key, which is safe only because a retry can
never reach `EvaluationFailed` (see `scoring-engine`: `failed()` on a retry job). No migration is
needed: the unique index on `(organization_id, project_id, event_type, dedupe_key)` is unchanged
and the `:retry` keys are distinct values. When the second delivery row collides on that index,
the recorder returns the existing row and discards the loser's payload, which is exactly why the
distinct key is required.

No new webhook event type is emitted when a retry is authorized: the integrating system
learns of the retry from the retry-era `progress` events and the final `evaluation` event.

#### Scenario: Concurrent SSO exchange race collapses into one progress delivery

- GIVEN two concurrent SSO exchange requests for the same `(project_id, candidate_ref)` both observe "no existing participant" at their pre-flight read
- WHEN both attempt to record a participant-creation `progress` trigger
- THEN exactly ONE `webhook_deliveries` row exists for that `(organization_id, project_id, 'progress', dedupe_key)` — the unique index absorbs the duplicate without altering the SSO exchange's raw upsert statement

#### Scenario: Repeated delivery id is a documented receiver no-op (not a BEAI guarantee of exactly-once)

- GIVEN a delivery attempt succeeds but the receiver's 2xx acknowledgement is lost in transit
- WHEN BEAI's retry logic (unaware the receiver already processed it) sends a further attempt with the SAME `X-BEAI-Delivery-Id`
- THEN this is expected, documented at-least-once behavior — the receiver contract requires treating the repeated id as a no-op

#### Scenario: The post-retry evaluation webhook is a distinct delivery row

- GIVEN a `pending` Evaluation E whose `evaluation` webhook was recorded under `dedupe_key = E.id`
- AND a retry run finishes with E `completed`
- WHEN the evaluation event is recorded for the retry run
- THEN a second `webhook_deliveries` row exists with `dedupe_key = "{E.id}:retry"` and event type `evaluation`
- AND its payload status is `completed`
- AND the first row is unchanged

#### Scenario: A duplicate retry-era evaluation emission still collapses

- GIVEN the retry-run evaluation event was already recorded under `"{E.id}:retry"`
- WHEN the same event is emitted again (listener re-run)
- THEN exactly ONE row exists for `(organization_id, project_id, 'evaluation', "{E.id}:retry")`

#### Scenario: Re-interview progress events use the retry suffix

- GIVEN a participant whose Evaluation has `retry_attempt = true` re-interviews competency INN
- AND a `competency-ended` row for INN from the first interview already exists under `competency-ended:{participant_id}:INN`
- WHEN the INN session ends in the re-interview
- THEN a new `progress` row exists with `dedupe_key = "competency-ended:{participant_id}:INN:retry"`
- AND the first-interview row is unchanged

#### Scenario: First-run keys are unchanged

- GIVEN a participant whose Evaluation has `retry_attempt = false`
- WHEN a competency ends and the evaluation completes
- THEN the keys are exactly `competency-ended:{participant_id}:{code}` and `{evaluation_id}` with no suffix

#### Scenario: Authorizing a retry emits no webhook

- GIVEN a retry is authorized for a `pending` evaluation
- WHEN the authorization commits
- THEN no `webhook_deliveries` row is created at authorization time
