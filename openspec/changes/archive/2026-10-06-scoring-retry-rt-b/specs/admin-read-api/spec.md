# Delta for Admin Read API

## ADDED Requirements

### Requirement: Participant Detail Carries The Evaluation Retry State

The participant detail resource (`GET /api/participants/{id}`, internal backoffice surface) MUST
carry the evaluation-retry state the backoffice panel needs, as machine-facing values that are
never localized: `retry_attempt` (boolean — whether the single retry has been authorized, from
the participant's Evaluation; `false` when the participant has no Evaluation), `retry_authorized_at`
(ISO-8601 instant, or null when not authorized), and `retry_available` (boolean — true only when
the participant is at `completato`, is NOT a test-mode participant, its Evaluation is `pending`
and `retry_attempt` is `false`; the action refuses a test-mode participant, so the flag mirrors
that guard; the project entry-gate refusal is NOT part of this flag and is reported by the
action's 409). The three fields are flat properties of the detail, not a nested block.
The phase of an authorized retry (waiting for the candidate / re-interview in progress /
scoring / finished) is derived by the client from the existing literal `status`, never from a
new status value.

The evaluation read gate is UNCHANGED: the structured evaluation remains readable only at
participant `completato`, so an authorized retry's pending evaluation stays unreadable until the
retry completes. The answers (utterances) of the competencies that the retry resets are deleted
at authorization, not at scoring time, so a retry that the candidate never takes leaves those
competencies without a transcript. These fields are internal to the authenticated, tenant-scoped backoffice API;
they MUST NOT appear on the public `/v1` surface, in exports, or in webhook payloads, and the
detail remains org-scoped (a participant of another organization is 404).

#### Scenario: An eligible participant reports retry_available

- GIVEN a participant at `completato` with a `pending` Evaluation and `retry_attempt = false`
- WHEN the detail is read
- THEN `retry_available` is true, `retry_attempt` is false and `retry_authorized_at` is null

#### Scenario: A test-mode participant is not retryable

- GIVEN a test-mode participant at `completato` with a `pending` Evaluation
- WHEN the detail is read
- THEN `retry_available` is false

#### Scenario: A completed evaluation is not retryable

- GIVEN a participant at `completato` whose Evaluation is `completed`
- WHEN the detail is read
- THEN `retry_available` is false

#### Scenario: An authorized retry reports its state

- GIVEN a retry authorized at instant T for a participant now at `in_attesa`
- WHEN the detail is read
- THEN `retry_attempt` is true, `retry_authorized_at` equals T and `retry_available` is false
- AND `status` is the literal `in_attesa`

#### Scenario: A participant without an Evaluation

- GIVEN a participant at `in_corso` with no Evaluation
- WHEN the detail is read
- THEN `retry_attempt` is false, `retry_authorized_at` is null and `retry_available` is false

#### Scenario: The evaluation stays unreadable during the retry

- GIVEN a participant with an authorized retry at `in_attesa`, `in_corso` or `in_valutazione`
- WHEN the structured evaluation is requested
- THEN the existing read gate refuses it

#### Scenario: Cross-tenant detail is not found

- GIVEN an operator of Org A
- WHEN they read the detail of a participant of Org B
- THEN HTTP 404 is returned and no retry field is exposed
