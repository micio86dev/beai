# Delta for interview-session

Change: `live-interview-call-chrome`. Additive only: one new read endpoint and one new field on an existing 202 body.
No existing status, ordering, scoring or timeout behaviour changes.

## ADDED Requirements

### Requirement: GET /candidate/interview/outline — a read-only, owned, localized view of the interview path

`GET /api/candidate/interview/outline` MUST return the authenticated candidate's interview path as JSON with exactly
these six top-level fields, all `snake_case`, and no `data` envelope:

- `assessment_type`: `standard` or `potential`, the project's assessment type;
- `role_name`: the role's display name in the **project language**, or `null` for a `potential` assessment (which has no
  role), for a project with no role, when the project's pinned catalogue revision cannot be resolved, or when the role has
  no usable name;
- `avatar_name`: the `persona.display_name` of the avatar template that configures this participant's interview, or
  `null` when none is set or the stored value does not satisfy the display-name rules of `avatar-templates` (for example an
  imported legacy value);
- `candidate_name`: the authenticated participant's own display name, trimmed, or `null` when blank;
- `competencies`: an array ordered by the project's competency `position`, one entry per competency of the interview, each
  `{ name, ordinal, status, primary_total }` and **no competency code or identifier**, where `name` is the competency name
  in the **project language** (never empty), `ordinal` is the 1-based rank of the entry in this order,
  `primary_total` is the number of primary questions the system will ask for that competency (an integer >= 0; the count
  frozen in that competency's interview session when one exists, otherwise the count the system would freeze), and `status`
  is exactly one of `done`, `current`, `upcoming`, `retry`;
- `primary_total_all`: the sum of every entry's `primary_total`.

`status` MUST be derived from server state only, evaluated per entry in this order, over the same "open" rule that decides
which competency `POST /start` serves next (so the outline's `current` is always the competency the next `POST /start` would
serve). A competency is **open** when it has no interview session, or its session is `pending` or `in_corso`, or its session
is in `error` with re-offer attempts left.

1. `current`: the FIRST open entry in order (at most one entry; none when no entry is open). A first open entry that is an
   errored session with attempts left, or a session reset for an evaluation retry, is `current`, not `retry`.
2. `retry`: any LATER open entry that already has an interview session (an errored session with attempts left, or a session
   reset to `pending` by the evaluation retry); it is queued behind the current one and will be offered again. It MUST NOT be
   reported as `upcoming` and MUST NOT be reported as `done`.
3. `upcoming`: an entry with no interview session yet.
4. `done`: every other entry (completed, timed out, skipped, or errored with re-offer attempts exhausted).

The endpoint MUST be authenticated by the same candidate JWT and tenant scope as `GET /api/candidate/session` and MUST
refuse a missing, expired or unresolvable token exactly as that endpoint does. It MUST be registered in the candidate
`interview` route group and therefore pass the same participant-status guard as every other interview sub-route: a
participant in a terminal status MUST be refused with the status that guard returns, and no outline MUST be built for it. The
participant MUST be derived from the token alone; the endpoint MUST accept no participant, project or session identifier. A
project whose stored `assessment_type` is not a supported value MUST be refused with `422 assessment_type_not_supported`,
the same refusal `POST /start` gives. It MUST be read-only: no request to it MAY change any participant status, create or
modify any interview session, utterance or event, or issue a provider token. It MUST NOT be added to `ParticipantResource`,
which also feeds the enrolment resource. It MUST NOT appear in the `/v1` public API. Its response MUST be documented in the
generated OpenAPI document.

#### Scenario: A standard interview returns role, avatar and ordered competencies

- GIVEN a `standard` project in Italian whose pinned revision names the role "Responsabile Vendite", with three
  competencies at positions 1, 2, 3 and primary totals 2, 3 and 1, and an avatar template with `persona.display_name` "Giulia"
- AND the participant's display name is "  Marco Rossi  "
- WHEN the candidate calls `GET /api/candidate/interview/outline`
- THEN the response is 200 with `assessment_type = "standard"`, `role_name = "Responsabile Vendite"`,
  `avatar_name = "Giulia"`, `candidate_name = "Marco Rossi"`, three competencies in position order with `ordinal` 1, 2, 3
  and Italian `name` values and no `code` key, and `primary_total_all = 6`

#### Scenario: A potential assessment has no role name

- GIVEN a `potential` project
- WHEN the candidate calls the outline endpoint
- THEN `assessment_type = "potential"`, `role_name` is `null` and `competencies` lists the potential competencies

#### Scenario: An unset persona name returns null

- GIVEN the avatar template has no `persona.display_name`
- WHEN the candidate calls the outline endpoint
- THEN `avatar_name` is `null`

#### Scenario: An invalid imported persona name returns null

- GIVEN the avatar template carries an imported `persona.display_name` longer than 60 characters or containing `<`
- WHEN the candidate calls the outline endpoint
- THEN `avatar_name` is `null`

#### Scenario: A blank participant name returns null

- GIVEN the participant's display name is empty or whitespace
- WHEN the candidate calls the outline endpoint
- THEN `candidate_name` is `null`

#### Scenario: Status follows the interview state

- GIVEN competency 1 finished, competency 2 is in progress, competency 3 has not started
- WHEN the candidate calls the outline endpoint
- THEN the statuses in order are `done`, `current`, `upcoming`

#### Scenario: An errored competency with attempts left that is next reports current

- GIVEN competency 1 finished, competency 2 ended in `error` with re-offer attempts left (so the next `POST /start` re-offers
  it), and competency 3 has not started
- WHEN the candidate calls the outline endpoint
- THEN the statuses in order are `done`, `current`, `upcoming`

#### Scenario: A later competency queued behind the current one reports retry

- GIVEN four competencies where 1 finished, 2 and 4 were reset to `pending` by the evaluation retry, and 3 finished and was
  kept
- WHEN the candidate calls the outline endpoint
- THEN the statuses in order are `done`, `current`, `done`, `retry`

#### Scenario: Exhausted re-offer attempts close the competency

- GIVEN competency 2 ended in `error` with no re-offer attempts left and competency 3 has not started
- WHEN the candidate calls the outline endpoint
- THEN competency 2 reports `done` and competency 3 reports `current`

#### Scenario: A participant still in progress with every competency closed has no current competency

- GIVEN the participant is still `in_corso` and every competency is closed
- WHEN the candidate calls the outline endpoint
- THEN no entry reports `current`

#### Scenario: A terminal participant is refused

- GIVEN a participant in a terminal status (for example `completato`)
- WHEN the candidate calls the outline endpoint
- THEN the request is refused with the status the participant-status guard returns for the other interview routes, and no
  outline body is returned

#### Scenario: An unsupported assessment type is refused

- GIVEN a project whose stored `assessment_type` is not a supported value
- WHEN the candidate calls the outline endpoint
- THEN the response is `422` with the error `assessment_type_not_supported`, as `POST /start` answers

#### Scenario: A frozen session snapshot drives primary_total

- GIVEN competency 1 has an interview session whose frozen set holds 2 primaries while the live configuration now yields 3
- WHEN the candidate calls the outline endpoint
- THEN competency 1 has `primary_total = 2`, and a competency with no session reports the live count

#### Scenario: A competency without a primary question reports zero

- GIVEN a competency with no primary question configured
- WHEN the candidate calls the outline endpoint
- THEN that entry has `primary_total = 0` and `primary_total_all` is the sum of the others

#### Scenario: Names follow the project language, not the request language

- GIVEN a project in English and a request sent with an Italian `Accept-Language`
- WHEN the candidate calls the outline endpoint
- THEN `role_name` and every competency `name` are in English

#### Scenario: A missing translation falls back and never returns an empty name

- GIVEN a competency with no name in the project language
- WHEN the candidate calls the outline endpoint
- THEN its `name` is a non-empty string

#### Scenario: Another tenant's data is never returned

- GIVEN organization A and organization B each with a project that uses the same competency codes
- WHEN a candidate of organization A calls the outline endpoint
- THEN every field describes organization A's project only; and a token for a participant that does not resolve in the
  tenant scope is refused exactly as `GET /api/candidate/session` refuses it

#### Scenario: No token is refused

- GIVEN a request with no candidate token, and another with an expired one
- WHEN each calls the outline endpoint
- THEN each is refused with the same status as `GET /api/candidate/session`

#### Scenario: The endpoint accepts no identifiers and mutates nothing

- GIVEN a candidate request with a `participant_id` or `session_id` query parameter belonging to someone else
- WHEN the endpoint is called
- THEN the parameter is ignored, the response describes the authenticated candidate only, and the participant status,
  the interview sessions and the event tables are unchanged

#### Scenario: The response is documented

- GIVEN the generated `openapi.json`
- WHEN the outline operation is inspected
- THEN it documents the six top-level fields (`assessment_type`, `role_name`, `avatar_name`, `candidate_name`,
  `primary_total_all`, `competencies`), the `status` enumeration, the absence of any competency code, the nullable
  `role_name`, `avatar_name` and `candidate_name`, and the `422` refusal

## MODIFIED Requirements

### Requirement: POST /utterance — best-effort live transcript ingestion

`POST /api/candidate/interview/utterance` MUST accept `{ session_id, speaker, text, ts }` and persist an `Utterance` row linked to the specified session. The endpoint MUST return HTTP 202 on success (session is `in_corso` at insertion time); MUST return HTTP 409 when the session is no longer `in_corso` (utterance atomically dropped, 0 rows inserted). It MUST NOT block the interview flow on failure.

**WARNING-5 / FIX-2 — TOCTOU window — ATOMIC guard required:**
A plain `SELECT + check status` followed by a separate `INSERT` is a TOCTOU race: a
concurrent `/end` can commit `completed` between the check and the INSERT (open for both
HeyGen and Tavus — the HeyGen `/end` FOR UPDATE lock does NOT block `/utterance`'s
plain SELECT). The status guard MUST be ATOMIC.

Required: use a conditional insert pattern (e.g. `INSERT ... WHERE EXISTS (SELECT 1 FROM
interview_sessions WHERE id = ? AND status = 'in_corso')`) OR acquire `SELECT ... FOR SHARE`
inside a short transaction and re-check before inserting. Do NOT use plain check-then-insert.

Response contract (CANONICAL):
- An utterance arriving when the session is no longer `in_corso` is atomically dropped (0 rows
  inserted) and the endpoint MUST return **409 Conflict** WITHOUT throwing.
- Do NOT return 202 for a dropped utterance (misleading). Do NOT throw 500 (user-visible error
  for a best-effort endpoint). 409 is the single canonical signal; the client treats it as no-op.

**Boundary signal (single-session addendum).** The 202 response body MUST be
`{ "boundary_due": <bool>, "primary_index": <int> }`. After the utterance is committed, the server counts the session's
SUBSTANTIVE candidate turns: rows with `speaker = 'candidate'` whose `length(text)` is at least
`projects.nudge_min_chars` (every candidate row when `nudge_min_chars` is null); turns shorter than
`nudge_min_chars` MUST NOT count. `boundary_due` is true when that count is greater than or equal to
`1 + follow_up_budget + boundary_grace_turns`, where `follow_up_budget` is the ROW's own
`interview_sessions.follow_up_budget` snapshot (the number the prompt was composed from) and
`boundary_grace_turns` is `conversation.boundary_grace_turns` (default 1). The field is a hint to the
client and never changes the 202/409/404/422 contract; the 409 body is unchanged. With the default
config (`followup_budget` 4) the threshold is 6 substantive turns.
(Previously: the 202 carried no body, then `{ "boundary_due" }` only.)

**Primary index (live-interview-call-chrome addendum).** `primary_index` MUST be the number of DISTINCT scripted primary
questions of this competency session that the interviewer has asked so far, once this request is committed, an integer
>= 0 (the value `TurnClassifier::matchedCount()` returns for the session). It is the 1-based index of the latest scripted
primary asked. It counts the posted utterance when that utterance is the avatar asking a scripted primary for the first
time. It MUST NOT advance for candidate turns, follow-up avatar turns, a verbatim re-ask of a primary already counted
(for example after a resume), or any turn of another session; a competency session whose frozen set holds no primaries
always returns `0`. When a competency is re-offered after an error and its transcript is discarded, the count restarts at 0.
It is returned for candidate and avatar utterances alike. It is a presentation hint and MUST NOT change `boundary_due`,
the 202/409/404/422 contract, or any stored value (the stored `question_asked` event index is unchanged).

#### Scenario: Valid utterance ingested

- GIVEN a session S owned by the authenticated candidate with `status = 'in_corso'`
- WHEN `POST /utterance` is called with valid fields
- THEN HTTP 202 is returned and an Utterance row is persisted

#### Scenario: Utterance rejected into completed session (WARNING-5)

- GIVEN a session S owned by the authenticated candidate with `status = 'completed'`
  (i.e. `/end` was already called)
- WHEN `POST /utterance` is called
- THEN HTTP 409 is returned and no Utterance row is persisted

#### Scenario: session_id belongs to another candidate

- GIVEN session S2 belonging to candidate B
- WHEN candidate A calls `POST /utterance` with `session_id = S2`
- THEN HTTP 404 is returned and no Utterance is persisted

#### Scenario: boundary_due is false below the threshold

- GIVEN a session with `follow_up_budget = 4`, `nudge_min_chars = 80`, `boundary_grace_turns = 1`
  and 5 substantive candidate turns persisted
- WHEN the 5th substantive candidate utterance is posted
- THEN HTTP 202 is returned with `boundary_due = false`

#### Scenario: boundary_due is true at and above the threshold

- GIVEN the same session
- WHEN the 6th substantive candidate utterance is posted, and again when a 7th is posted
- THEN both responses are HTTP 202 with `boundary_due = true`

#### Scenario: Short turns do not count

- GIVEN a session with 5 substantive candidate turns and several candidate turns shorter than
  `nudge_min_chars`
- WHEN a short candidate utterance is posted
- THEN HTTP 202 is returned with `boundary_due = false`; the short turn is persisted but not counted

#### Scenario: Avatar turns never count and 409 is unchanged

- GIVEN a session at the threshold
- WHEN avatar-speaker utterances are posted, or an utterance is posted to a session no longer `in_corso`
- THEN avatar turns do not change the count, and the dropped utterance returns 409 exactly as before

#### Scenario: primary_index counts the first primary question

- GIVEN a session with no scripted primary asked yet
- WHEN the avatar's first scripted primary question is posted
- THEN HTTP 202 is returned with `primary_index = 1`

#### Scenario: A follow-up and a candidate turn do not advance primary_index

- GIVEN a session whose `primary_index` is 1
- WHEN an avatar follow-up (not a scripted primary) and then a candidate utterance are posted
- THEN both responses are HTTP 202 with `primary_index = 1`

#### Scenario: A verbatim re-ask does not advance primary_index

- GIVEN a session whose `primary_index` is 2 and the interviewer repeats scripted primary 2 verbatim (for example after a
  resume)
- WHEN the repeated utterance is posted
- THEN HTTP 202 is returned with `primary_index = 2`, and the next distinct scripted primary yields 3

#### Scenario: primary_index is 0 before any primary question

- GIVEN a session with no scripted primary asked
- WHEN a candidate utterance is posted
- THEN HTTP 202 is returned with `primary_index = 0`

#### Scenario: A competency without primaries always returns 0

- GIVEN a competency session whose frozen set holds no scripted primaries
- WHEN avatar and candidate utterances are posted
- THEN every response carries `primary_index = 0`

#### Scenario: A re-offered competency restarts the count

- GIVEN a competency session with `primary_index` 2 that errored and is re-offered with its transcript discarded
- WHEN the first scripted primary of the re-offer is posted
- THEN the response carries `primary_index = 1`

#### Scenario: primary_index is scoped to its own session

- GIVEN competency session S1 with `primary_index` 3 and a new competency session S2 for the same participant
- WHEN S2's first scripted primary question is posted
- THEN the response carries `primary_index = 1`

#### Scenario: A dropped utterance carries no primary_index

- GIVEN a session no longer `in_corso`
- WHEN an utterance is posted
- THEN HTTP 409 is returned with the body it returned before this change
