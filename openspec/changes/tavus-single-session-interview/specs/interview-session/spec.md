# Delta for Interview Session

> Rescoped 2026-10-08. No requirement is REMOVED: every requirement below either extends a main-spec
> requirement (MODIFIED, full text) or is new (ADDED). Main-spec titles are quoted exactly.

## MODIFIED Requirements

### Requirement: POST /start — session creation, duplicate prevention, and provider token issuance

`POST /api/candidate/interview/start` MUST:

1. Resolve the next competency from `project_competencies.position` ASC: the lowest
   position whose `InterviewSession` for this participant is ABSENT or whose status is
   NOT in `{completed, timeout, skipped}`. A session with `status = pending | in_corso`
   → RESUME it (return the existing session; do NOT create a duplicate). The UNIQUE
   constraint on `(participant_id, competency_code)` enforces idempotency at the DB
   level: a unique-violation means a session already exists → RESUME that session.
   **WARNING-7 (concurrent double /start):** if two concurrent `/start` requests race,
   the second INSERT will raise `Illuminate\Database\UniqueConstraintViolationException`
   (SQLSTATE 23505). The implementation MUST catch this exception and recover by
   re-querying the existing session (→ RESUME path), NOT surface it as a 500.
2. INSERT `InterviewSession(status='pending', question_index = position,
   framework_version_id copied from project, ...)` in a SHORT DB transaction.
   `question_index` MUST equal `project_competencies.position` for that competency —
   never `position - 1`.
   (Previously: `question_index = position - 1`, which produced `-1` for a project's
   first competency because `position` is 0-based, not 1-based.)
3. Call the configured provider (HeyGen or Tavus) REST API server-side using secret
   keys stored only in environment/config — NEVER returned to the client.
   **The provider HTTP call (`ProviderSessionService.issue()`) MUST be outside any DB
   transaction.** Holding a DB transaction open across a network call risks connection
   starvation and deadlock.
4. On provider SUCCESS: wrap BOTH of the following writes in ONE short DB transaction (FIX-8):
   - UPDATE session `status='in_corso'`, `provider_session_ref`.
   - On the **first** competency (`position = 0`, i.e. `participant.status = 'in_attesa'`):
     set `participant.started_at` via **direct property assignment** (NOT mass-assign,
     because `started_at` is NOT in `$fillable`): `$p->started_at = now(); $p->status = 'in_corso'; $p->save();`
   **FIX-8 rationale:** without a surrounding transaction, a failure between the two writes leaves
   the session `in_corso` but the participant `in_attesa` (inconsistent state). Wrapping both
   writes in ONE atomic short transaction ensures they commit or roll back together. On rollback,
   the session reverts to `pending` and is resumable via the RESUME-pending path on next `/start`.
   The step-4d compensation (teardown + 500) covers failure of EITHER write inside this transaction.
5. Return HTTP **201** with `{ session_id, provider, provider_token|conversation_url, question_context }`.
   When the single-session gate in step 6 applies, the body additionally carries
   `conversation_id` (fresh create of a multi-competency plan) or `continuation` (granted
   continuation); otherwise the body is byte-identical to the shape above.
6. **Single-session path (Tavus only, flag-gated).** Everything in this step applies ONLY when
   all of the following hold: the resolved provider is `tavus`; config
   `interview.tavus.single_session` is true OR the project's id is listed in
   `interview.tavus.single_session_projects`; and the project has more than one competency left
   to cover. When any of them fails, `/start` runs steps 1-5 exactly as before: one
   `ProviderSessionService.issue()`, one fresh session-scoped `provider_session_ref`, no new
   field in the response, and `live_conversation_id` ignored.
   a. **Fresh create of a plan.** The first `/start` of a conversation composes a conversation
      plan (see `interview-conversation`), calls `issue()` exactly once with the combined
      context, persists the plan on the creating row (`interview_sessions.conversation_plan`),
      and returns the ordinary body plus `conversation_id` (the provider conversation id;
      non-secret; never derived from `conversation_url`) and `conversation_ttl_seconds` (the
      conversation's ceiling in seconds, so the client can start a handover before it).
   b. **Continuation.** `/start` accepts an optional body field `live_conversation_id`. The
      client asserts it is still joined to that conversation; the server never infers reuse
      from its own rows. A continuation is granted ONLY IF every one of the following holds
      (see "Continuation Is Granted Only For An Owned, Planned, Brand-New Competency"):
      the id equals the `provider_session_ref` of a row of THIS participant in THIS
      organization whose provider is `tavus`; the plan stored on the row that owns the ref
      covers the resolved next competency code; no `InterviewSession` row exists yet for
      `(participant, that code)` (so it is not a RESUME, not `pending`, not a re-offer and not
      an evaluation-retry reset); and the ref's lifetime permits it ("Provider Reference
      Lifetime Is Derived From The Template Ceiling").
      On grant `/start` MUST NOT call `issue()`. It inserts the new competency's row
      (`status='in_corso'`, `provider_session_ref` = the SAME ref, `question_index` =
      `project_competencies.position`, `primary_questions` and `follow_up_budget` copied from
      the plan entry, the LLM snapshot copied from the creating row) and opens a live period,
      in ONE short DB transaction, and returns HTTP 201 with `provider_token: null`,
      `conversation_url: null`, `continuation: {conversation_id, competency_code}` and the
      usual `question_context`.
   c. **Refusal is never an error.** When any grant condition fails (including an absent,
      foreign or stale `live_conversation_id`), `/start` takes the ordinary issue path and
      returns a fresh handle with no `continuation`.
   This is the ONLY path that shares a `provider_session_ref` across two `InterviewSession`
   rows; every HeyGen path, every mock-provider path, and every Tavus path with the gate off
   or a refused continuation issues a fresh, session-scoped ref exactly as before.
   (Previously: `/start` unconditionally called `ProviderSessionService.issue()` for every
   competency, for every provider; no reuse path and no `live_conversation_id` existed.)

The response body MUST NOT contain any provider API secret key.

**Failure matrix:**

| Failure | Status | Participant | HTTP |
|---|---|---|---|
| Provider 5xx / timeout (hard-failure) | `status='error'`, `ended_reason='error'` | → `errore` (if not already terminal) | 502 |
| Provider 429 / concurrency (retryable) | `status='pending'` (or delete row) | NO transition to `errore` | 429 `{ error: 'provider_busy' }` |
| DB failure AFTER provider success | `teardown(token)` provider session to avoid orphan — pass the in-memory `ProviderToken` returned by `issue()` directly (WARNING-6: the ref may not yet be persisted; do NOT use `$session->provider_session_ref` — null ref → silent no-op → orphaned provider session; do NOT pass a raw string — teardown() only accepts a ProviderToken) | — | 500 |

Note: the `teardown()` call on DB-failure may itself fail (network); log the teardown
failure for manual cleanup. Do NOT suppress the original DB error.

#### Scenario: First question — in_attesa → in_corso

- GIVEN participant.status = 'in_attesa' and the project has 3 competencies
- WHEN `POST /start` is called
- THEN HTTP 201 is returned, `participant.status` = 'in_corso', `participant.started_at` is set
  (via direct property assignment), and the response body contains `session_id` and
  `provider_token` (or `conversation_url`) but NOT a secret key

#### Scenario: Second question — status unchanged

- GIVEN participant.status = 'in_corso' (first competency already finished)
- WHEN `POST /start` is called for the second competency
- THEN HTTP 201 is returned and `participant.status` remains 'in_corso' (no redundant transition)

#### Scenario: Resume existing in_corso session — fresh token issued, old session torn down (CRITICAL-2 + FIX-1)

- GIVEN a session for competency PRS exists with `status = 'in_corso'` for this participant
  (e.g. candidate reconnected after a network drop or browser refresh)
- WHEN `POST /start` is called again
- THEN HTTP 201 is returned with the EXISTING session (no duplicate row created; UNIQUE
  constraint on (participant_id, competency_code) enforces this), AND:
  (a) A FRESH provider token is issued (re-calling `ProviderSessionService.issue()`) — NOT
      the stale stored `provider_session_ref`. The response contains a currently-valid token.
  (b) The OLD provider session referenced by the currently-persisted `provider_session_ref`
      IS TORN DOWN (best-effort `ProviderSessionService.teardown()` called with
      `ProviderToken::fromRef($session->provider, $session->provider_session_ref)` — teardown()
      always takes a ProviderToken, never a raw string; fromRef() wraps the persisted ref +
      provider name into a typed token so teardown routes to the correct provider client (F1)),
      UNLESS another live sibling row of the same participant still shares that ref (see
      "Resume Teardown Is Skipped Only While A Live Sibling Shares The Ref"). The fresh token is
      issued BEFORE the old ref is torn down in either case, because the browser has already left
      the old room. A teardown failure is logged but non-fatal — the candidate needs the fresh session.
  (c) The session row is updated with the NEW `provider_session_ref`.
  This prevents leaking a billable HeyGen session-minute or Tavus concurrency slot on reconnect.
  NOTE: the teardown in this RESUME path wraps the OLD persisted ref via ProviderToken::fromRef()
  — this is DISTINCT from the step-4d compensation teardown which passes the NEW in-memory
  ProviderToken directly from issue() (WARNING-6). teardown() always takes a ProviderToken.

#### Scenario: Resume pending session (prior 429 left no token) — fresh token issued (CRITICAL-2)

- GIVEN a session for competency PRS exists with `status = 'pending'` and no `provider_session_ref`
  (e.g. a prior `/start` returned 429 `provider_busy` and left the session tokenless)
- WHEN `POST /start` is called again
- THEN `ProviderSessionService.issue()` is retried; on success: `provider_session_ref` is
  persisted, `status` is flipped to `'in_corso'`, and HTTP 201 is returned with a fresh token.
  The failure matrix is identical to the create path (provider 429 → `provider_busy` NOT →errore;
  provider 5xx → →errore + 502; DB failure → teardown + 500).

#### Scenario: Provider hard-failure → 502 and errore

- GIVEN `Http::fake` returns a 503 for the provider endpoint
- WHEN `POST /start` is called
- THEN HTTP 502 is returned, session `status = 'error'`, and `participant.status = 'errore'`

#### Scenario: Provider 429 → retryable, participant NOT marked errore

- GIVEN `Http::fake` returns a 429 for the provider endpoint
- WHEN `POST /start` is called
- THEN HTTP 429 is returned with `{ "error": "provider_busy" }`, session remains
  `status = 'pending'`, and `participant.status` is NOT transitioned to `'errore'`

#### Scenario: DB failure after provider success → teardown + 500

- GIVEN the provider returns success but the subsequent DB UPDATE fails
- WHEN `POST /start` is called
- THEN `ProviderSessionService.teardown()` is called to release the provider session,
  and HTTP 500 is returned

#### Scenario: Provider selected via env

- GIVEN `INTERVIEW_PROVIDER=heygen` in environment config
- WHEN `POST /start` is called
- THEN the session `provider` field = 'heygen' and the HeyGen REST API is called for the token

#### Scenario: Provider overridden at project level (FIX-6: canonical column = `provider_override`)

- GIVEN the project record carries `provider_override = 'tavus'` (nullable additive column;
  falls back to env `INTERVIEW_PROVIDER` when null — FIX-6: `provider_override` is the
  canonical column name, not `provider`, to avoid collision with future non-override semantics)
- WHEN `POST /start` is called
- THEN the session `provider` field = 'tavus' and the Tavus REST API is called

#### Scenario: Concurrent double /start recovers via RESUME (WARNING-7)

- GIVEN no existing session for competency PRS for this participant
- WHEN two concurrent `POST /start` requests race and the second INSERT hits the
  UNIQUE(participant_id, competency_code) constraint
- THEN `UniqueConstraintViolationException` (23505) is caught; the second request
  re-queries the existing session and proceeds as a RESUME — HTTP 201 is returned;
  no 500 is surfaced

#### Scenario: No unstarted competency remaining

- GIVEN all competencies for the project have sessions with status ∈ {completed, timeout, skipped}
- WHEN `POST /start` is called
- THEN the response is HTTP 422 (no next competency available)

#### Scenario: Flag off — /start is byte-identical to today

- GIVEN `interview.tavus.single_session` is false and the project is not in the canary list
- WHEN `POST /start` is called for any competency, with or without `live_conversation_id`
- THEN `issue()` is called, no `conversation_plan` is written, the response has no
  `conversation_id` and no `continuation`, and the body equals the pre-change body

#### Scenario: A fresh multi-competency create returns conversation_id

- GIVEN the gate applies and the project has competencies [CSF, INN, DRV]
- WHEN `POST /start` creates the conversation for CSF
- THEN `issue()` is called once, the creating row stores `conversation_plan` covering all
  three competencies, and the 201 body contains `conversation_id` equal to the ref persisted
  on the row and `conversation_ttl_seconds` equal to the template-derived ceiling

#### Scenario: A second competency is granted a continuation without a new provider session

- GIVEN a live Tavus conversation created for [CSF, INN, DRV], CSF ended (`completed`), and the
  client sends `live_conversation_id` equal to the ref of the CSF row
- WHEN `POST /start` resolves INN and INN has no row yet
- THEN `issue()` is NOT called (`Http::assertNotSent` on `/v2/conversations`); a new INN row is
  `in_corso` with the SAME ref; a live period is opened; and the 201 body has
  `provider_token: null`, `conversation_url: null` and
  `continuation: {conversation_id, competency_code: "INN"}`

#### Scenario: A foreign or absent id is refused silently

- GIVEN a `live_conversation_id` that belongs to another participant, or to another
  organization, or that matches no row, or is absent
- WHEN `POST /start` is called
- THEN the ordinary issue path runs and the response has a fresh handle and no `continuation`;
  no information about the other participant's row is disclosed

#### Scenario: A code outside the plan, a pending row or a re-offer is never granted

- GIVEN the resolved next competency is not in the owning row's plan, or its row already exists
  as `pending`, or it is a bounded re-offer, or an evaluation retry reset it
- WHEN `POST /start` is called with the owned `live_conversation_id`
- THEN no continuation is granted and `issue()` runs

#### Scenario: HeyGen and the mock provider are unaffected

- GIVEN a HeyGen interview, or a test-mode interview on the mock provider
- WHEN `POST /start` is called for the next competency
- THEN `issue()` is called exactly as before, no `InterviewSession` row ever shares a
  `provider_session_ref`, and no `conversation_plan` is written

#### Scenario: A transaction failure on the continuation leaks nothing

- GIVEN a granted continuation whose row insert fails
- WHEN the transaction rolls back
- THEN the response is the existing 500 `db_error`, no row shares the ref, no period is open, and
  no provider call was made that would need a teardown

#### Scenario: Near the ceiling a genuine new conversation is produced

- GIVEN the owned ref is within `ceiling_headroom_seconds` of its template-derived ceiling, or
  the remaining plan no longer covers the next competency
- WHEN `POST /start` is called for the next competency
- THEN no continuation is granted; `issue()` is called and creates a new conversation (with a new
  plan covering what remains), exactly as the create path does for a first competency

---

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
`{ "boundary_due": <bool> }`. After the utterance is committed, the server counts the session's
SUBSTANTIVE candidate turns: rows with `speaker = 'candidate'` whose `length(text)` is at least
`projects.nudge_min_chars` (every candidate row when `nudge_min_chars` is null); turns shorter than
`nudge_min_chars` MUST NOT count. `boundary_due` is true when that count is greater than or equal to
`1 + follow_up_budget + boundary_grace_turns`, where `follow_up_budget` is the ROW's own
`interview_sessions.follow_up_budget` snapshot (the number the prompt was composed from) and
`boundary_grace_turns` is `conversation.boundary_grace_turns` (default 1). The field is a hint to the
client and never changes the 202/409/404/422 contract; the 409 body is unchanged. With the default
config (`followup_budget` 4) the threshold is 6 substantive turns.
(Previously: the 202 carried no body.)

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
- THEN HTTP 202 is returned with `{ "boundary_due": false }`

#### Scenario: boundary_due is true at and above the threshold

- GIVEN the same session
- WHEN the 6th substantive candidate utterance is posted, and again when a 7th is posted
- THEN both responses are HTTP 202 with `{ "boundary_due": true }`

#### Scenario: Short turns do not count

- GIVEN a session with 5 substantive candidate turns and several candidate turns shorter than
  `nudge_min_chars`
- WHEN a short candidate utterance is posted
- THEN HTTP 202 is returned with `{ "boundary_due": false }`; the short turn is persisted but not counted

#### Scenario: Avatar turns never count and 409 is unchanged

- GIVEN a session at the threshold
- WHEN avatar-speaker utterances are posted, or an utterance is posted to a session no longer `in_corso`
- THEN avatar turns do not change the count, and the dropped utterance returns 409 exactly as before

---

### Requirement: Tavus Conversation Wire Contract

`POST https://tavusapi.com/v2/conversations` MUST be called with
`{replica_id, persona_id, conversational_context, custom_greeting, properties}` — no
`competency_code`/`question_index`. When the single-session gate applies and the plan covers several
competencies, `conversational_context` MUST carry the FULL combined context for every competency the
conversation will cover (the plan's text), composed server-side before the request is sent — never a
partial context extended later by a client-supplied addition. The conversation id/URL MUST be read from
the TOP-LEVEL `conversation_id`/`conversation_url`, not nested under `data`. Teardown MUST be
`POST /v2/conversations/{id}/end`, never `DELETE`.

At a competency boundary inside a live conversation, the candidate's browser sends a
`conversation.append_llm_context` interaction over the Daily data channel, with the envelope
`{message_type:'conversation', event_type:'conversation.append_llm_context', conversation_id,
properties:{context}}`. It APPENDS to the conversation's LLM context and MUST NOT be
`conversation.overwrite_llm_context`, which REPLACES the context and would delete the other
competencies' coverage that the combined context established. The client MAY follow the append with a
fixed `conversation.respond {text}` interaction when the avatar does not open the next topic on its own;
that trigger text is a closed constant. Both interactions are governed by "Outbound Interaction Payload
Carries No Scoring Content". Neither re-sends `conversational_context`.
(Previously: `conversational_context` held a single competency's composed prompt, no boundary
interaction existed, and the 2026-08-21 text named `overwrite_llm_context`.)

#### Scenario: /conversations body is the real shape
- GIVEN a candidate starting a Tavus interview
- WHEN `TavusProvider::issue()` builds the request
- THEN the body contains `replica_id`, `persona_id`, `conversational_context`,
  `custom_greeting`, `properties`, and no `competency_code`/`question_index`

#### Scenario: Response ids are read top-level
- GIVEN Tavus returns `{conversation_id:'conv_1', conversation_url:'https://...'}`
- WHEN the response is parsed
- THEN both values are extracted from the top level

#### Scenario: Teardown ends, does not delete
- GIVEN an active Tavus conversation
- WHEN `TavusProvider::teardown()` is called
- THEN it issues `POST /v2/conversations/{id}/end`; no `DELETE` is made

#### Scenario: A multi-competency conversation ships every covered competency's context at creation

- GIVEN the gate applies and a plan covering [CSF, INN, DRV]
- WHEN `TavusProvider::issue()` builds the FIRST `POST /v2/conversations` request for this conversation
- THEN `conversational_context` contains the composed content for all three competencies, matching
  the golden `conversations_request_multi_golden.json`; the single-competency golden
  `conversations_request_golden.json` is unchanged and still matches when the gate is off

#### Scenario: The boundary interaction appends and never overwrites

- GIVEN a live conversation advancing from CSF to INN
- WHEN the client sends the boundary interaction
- THEN the envelope's `event_type` is `conversation.append_llm_context`, it contains no
  `conversational_context` key, and no `conversation.overwrite_llm_context` message is built anywhere
  in `frontend/app` (asserted by a single-call-site guard)

#### Scenario: Live-only — append retains earlier topics and overwrite does not (L2)

- GIVEN a live Tavus conversation created knowing codeword AMBER for topic ALPHA and COBALT for topic BRAVO
- WHEN `append_llm_context` is sent, then `overwrite_llm_context` as a negative control
- THEN after the append the avatar still knows the earlier topic's codeword, and after the overwrite
  it does not. This scenario is verified only by the authorized live spike and is NOT asserted offline
---

## ADDED Requirements

### Requirement: Single-Session Is Flag-Gated And Dark By Default

The single-session behaviour (conversation plan, continuation grant, `conversation_id` and `continuation`
in the `/start` response, `live_conversation_id` handling, release job dispatch) MUST be reachable only
through one gate: provider `tavus` AND (`interview.tavus.single_session` is true OR the project's id is in
`interview.tavus.single_session_projects`). `interview.tavus.single_session` MUST default to `false`
(env `INTERVIEW_TAVUS_SINGLE_SESSION`) and the canary list MUST default to empty (env
`INTERVIEW_TAVUS_SINGLE_SESSION_PROJECTS`, comma-separated project ids). With the gate closed, every
candidate-facing response and every provider call MUST be identical to the pre-change behaviour. The
old one-conversation-per-competency path MUST remain available as the fallback, including after the flag
is enabled, for any refused continuation.

#### Scenario: Default configuration leaves behaviour unchanged

- GIVEN no environment override
- WHEN a Tavus interview runs end to end
- THEN each competency has its own `issue()` call and its own ref, no row carries `conversation_plan`,
  and no response contains `conversation_id` or `continuation`

#### Scenario: A canary project is enabled without enabling the platform

- GIVEN `interview.tavus.single_session` is false and project 42 is in `single_session_projects`
- WHEN project 42 and project 43 both start a Tavus interview
- THEN only project 42 composes a plan and may be granted continuations

#### Scenario: Turning the flag off mid-interview degrades to a fresh start

- GIVEN a live shared conversation and the flag is switched off before the next `/start`
- WHEN the client sends `live_conversation_id`
- THEN the server ignores it, issues a fresh conversation, and the response has no `continuation`

### Requirement: Conversation Plan Is Frozen On The Creating Row

When the gate applies and a Tavus conversation is created for several competencies, the server MUST
persist on the creating `interview_sessions` row a nullable JSON column `conversation_plan` of the shape
`{"competencies":[{"code","primary_questions","follow_up_budget"}],"chars":<int>}`. The plan MUST NOT
contain any BARS indicator name, anchor text or composed prompt fragment. It is written once, in the same
transaction that stamps the ref, and never rewritten. A later row on the same ref MUST take its
`primary_questions` and `follow_up_budget` snapshot from the plan entry for its code (so the avatar turn
classifier audits against what the conversation was actually composed with), and MUST receive a copy of the
creating row's LLM snapshot (`avatar_template_id`, `llm_model_key`, `llm_binding_status`,
`system_prompt_chars`) so that cost recording works for the continuation row. A single-competency
conversation MUST NOT write a plan.

#### Scenario: The plan holds snapshots and no anchors

- GIVEN a created conversation for [CSF, INN, DRV] whose BARS anchor text contains a random UUID sentinel
- WHEN `conversation_plan` is read
- THEN it lists the three codes with their `primary_questions` and `follow_up_budget`, `chars` equals the
  length of the combined context, and the UUID appears nowhere in the stored JSON

#### Scenario: A continuation row classifies against the plan entry

- GIVEN a continuation row for INN created from the plan
- WHEN an avatar utterance is posted for INN
- THEN `TurnClassifier` audits it against the plan entry's `primary_questions` and `follow_up_budget`
  stored on the INN row, not against a freshly recomputed list

#### Scenario: A continuation row has an LLM snapshot and a cost record

- GIVEN a granted continuation for INN
- WHEN INN ends
- THEN `llm_binding_status` on the INN row equals the creating row's value and a usage/cost row is written

#### Scenario: A single-competency conversation writes no plan

- GIVEN a project with exactly one competency left to cover
- WHEN `/start` creates its conversation
- THEN `conversation_plan` is null

### Requirement: Continuation Is Granted Only For An Owned, Planned, Brand-New Competency

The server MUST grant a continuation only when ALL of the following hold, and MUST evaluate them in the
server, never trusting the client's claim beyond the id it names: (1) the gate applies; (2) the submitted
`live_conversation_id` equals the `provider_session_ref` of an `InterviewSession` row of the SAME
participant and organization whose provider is `tavus`; (3) the `conversation_plan` of the row that owns the
ref lists the resolved next competency code; (4) no `InterviewSession` row exists for
`(participant, code)` yet; (5) the ref is not near its ceiling and the plan still covers the code. A
refused continuation MUST NOT surface an error or any detail about why. A row whose ref was nulled by
`/suspend` or `ResetSessionForRetry` MUST never match.

#### Scenario: Each failing condition independently refuses the grant

- GIVEN an owned live ref with a plan covering [CSF, INN, DRV] and CSF ended
- WHEN `/start` is called with, in turn: no id; another participant's id; another organization's id;
  an id for a row whose ref was nulled by `/suspend`; a plan that omits the next code; an existing
  `pending` row for the next code; a bounded re-offer; a ref past the ceiling headroom
- THEN each call takes the ordinary issue path with no `continuation`, and none of the responses differ in
  shape from an ordinary fresh `/start`

#### Scenario: Cross-tenant isolation is preserved

- GIVEN organization A's participant names a conversation id that belongs to organization B
- WHEN `/start` is called
- THEN the lookup is scoped by participant and organization, the id does not match, and no row of B is read
  into the response

### Requirement: Outbound Interaction Payload Carries No Scoring Content

Every interaction the candidate's browser sends over the Tavus data channel at a competency boundary MUST be
structurally restricted: the `conversation.append_llm_context` `properties.context` MUST equal a fixed,
versioned template with exactly one substituted value, the competency code issued by the server in
`continuation.competency_code`, and the optional `conversation.respond` `properties.text` MUST be a closed
constant that carries no code and no variable at all. The code MUST be validated by a branded constructor
that requires the pattern `^[A-Z0-9_]{1,16}$` (the same alphabet and length the catalogue allows, since codes
are operator-authored and no closed set exists). No BARS indicator name, anchor text
(`anchor_5`/`anchor_3`/`anchor_1`) or composed prompt fragment MUST be assignable to the template slot or
appended to the payload by any code path.

Verification MUST be structural, never a naive substring search: a test MUST assert (a) the serialized
payload length equals the fixed template length plus the code length; (b) removing the template's literal
wrapper text leaves a value EXACTLY equal to the server-issued code and matching the pattern; (c) the
envelope's key set and the `properties` key set deep-equal fixed sets, so `conversational_context` cannot
ride along; (d) the whole envelope equals a golden fixture
(`tests/fixtures/tavus/boundary_interaction_golden.json`) that changes only deliberately; and (e) a decoy
fixture in which another competency's anchor text contains `INN` inside `INNOVAZIONE` can neither satisfy
nor leak into the payload. `payload.includes(code)` MUST NOT be the sole leak detector. On the server, a
sentinel test MUST seed a BARS indicator whose `anchor_5` contains a random UUID, drive `/start` (create
and continuation), `/utterance`, `/end`, `/integrity` and `/snapshot`, assert the UUID appears in none of
the response bodies, and assert it DOES appear in the faked `POST /v2/conversations` request body.

#### Scenario: A boundary payload contains only the code and the fixed template

- GIVEN a live conversation advancing from CSF to INN
- WHEN the client builds the boundary interaction
- THEN stripping the template's wrapper text leaves exactly `INN`, the length equals template plus code,
  and the envelope equals the golden fixture with `INN` substituted

#### Scenario: A coincidental substring in unrelated anchor text neither passes nor leaks

- GIVEN a competency whose anchor text contains `INNOVAZIONE`
- WHEN the interaction for competency `INN` is built
- THEN exact equality with the server-issued code is what passes, and the anchor text cannot reach the payload

#### Scenario: An oversized or free-text payload fails the assertions

- GIVEN a hypothetical payload with an extra field or any prose beyond the template and the code
- WHEN the anti-leak test runs
- THEN the length and key-set assertions fail

#### Scenario: Anchors appear only in the server-to-Tavus create body

- GIVEN a live multi-competency conversation
- WHEN every candidate-facing response body and every client-to-Tavus message is inspected for the UUID sentinel
- THEN the sentinel appears only in the faked server-to-Tavus `POST /v2/conversations` body

### Requirement: A Competency Boundary Requires A Server Round Trip Even When The Provider Conversation Does Not Change

Advancing to a new competency within a live Tavus conversation MUST still go through the server: the server
remains the sole source of truth for competency completion, the running completion tally, the pause cadence
(`pause_every_n_competencies`), and the progress webhook trigger. The absence of a new provider session or a
new room MUST NOT be read as licence to skip the existing `/end` then `/start` round trip; a shared
conversation changes only which provider call is made, never which server state transitions occur. Scoring
input for an interview whose competencies share one ref MUST equal the scoring input of the same interview
with one ref per competency.

#### Scenario: Completion tally still advances correctly on a shared-conversation boundary

- GIVEN a project with 5 competencies in one live Tavus conversation; 2 already ended
- WHEN the 3rd competency ends via `POST /end`
- THEN `ended_competencies` reads 3 exactly as it would across separate conversations, and `next_action` is
  computed by the same rule as today

#### Scenario: A scheduled pause still fires inside a shared conversation

- GIVEN `pause_every_n_competencies = 3` and a live Tavus conversation spanning 5 competencies
- WHEN the 3rd competency ends
- THEN `next_action = 'pause'` is returned, and the next `/start` (the browser has left the room) issues fresh

#### Scenario: A progress webhook still fires per competency

- GIVEN a live multi-competency Tavus conversation
- WHEN any competency within it ends via `POST /end`
- THEN one `progress` event is dispatched after that commit, exactly as the existing addendum requires

#### Scenario: Scoring input is identical to the separate-ref interview

- GIVEN two interviews with the same utterances, one on a shared ref and one on separate refs
- WHEN the scoring input is assembled for each
- THEN the two inputs are equal

### Requirement: Resume Teardown Is Skipped Only While A Live Sibling Shares The Ref

`handleResumeInCorso` MUST continue to issue a FRESH provider session for the resumed row BEFORE tearing the
old ref down (the browser has already left the old room, so the old conversation can never be reused). The
teardown of the old persisted ref MUST be SKIPPED when another `InterviewSession` row of the same
participant that shares that ref is itself still `in_corso`; otherwise teardown behaves exactly as today.
`/suspend` MUST keep nulling only the suspended row's ref. The live period of the resumed row MUST be closed
whether or not teardown ran.

#### Scenario: Resume with a live sibling does not tear down the shared ref

- GIVEN two rows of one participant, both `in_corso`, sharing one ref
- WHEN `/start` resumes one of them
- THEN a fresh ref is issued for the resumed row, `teardown()` is NOT called against the shared ref, and
  the resumed row's period is closed

#### Scenario: Resume on an unshared ref still tears down and reissues

- GIVEN a row whose ref is shared with no live row
- WHEN `/start` resumes it
- THEN the existing teardown-and-reissue behaviour runs unchanged (`ResumeTranscriptTest` stays green)

#### Scenario: A ref becomes eligible for teardown once its last live dependent ends

- GIVEN a shared ref backing two rows, one `completed` and one `in_corso`
- WHEN the remaining row is resumed
- THEN teardown is permitted because no live sibling remains

### Requirement: Provider Reference Lifetime Is Derived From The Template Ceiling

The server MUST derive a conversation's age and ceiling from data, not from a constant: age is
`now() - min(started_at)` over the live periods of the ref (a span, not a sum); the ceiling is the avatar
template's `maxCallDurationSec` for the session's project when set, otherwise
`ProviderFieldSpecs::TAVUS_MAX_SECONDS`. A ref is NEAR its ceiling when
`age + conversation.ceiling_headroom_seconds >= ceiling`, with a default headroom of 480 seconds (the 300 s
question limit plus a join buffer). A continuation MUST be refused for a ref near its ceiling. The ceiling
logic MUST live in one class (`ProviderRefLifetime`), reusing the existing template resolution in
`SessionLiveClock`.

#### Scenario: A template cap of 900 seconds is honoured

- GIVEN a template with `maxCallDurationSec = 900` and a ref aged 500 seconds
- WHEN `/start` evaluates a continuation
- THEN the ref is near its ceiling (500 + 480 >= 900) and the continuation is refused

#### Scenario: Without a template the platform bound applies

- GIVEN no active template and a ref aged 2000 seconds
- WHEN `/start` evaluates a continuation
- THEN the ceiling is 3600, the ref is not near it, and the continuation may be granted

#### Scenario: Age is a span across contiguous periods

- GIVEN a ref with two closed periods and one open period over 700 seconds of wall-clock life
- WHEN the age is computed
- THEN it is 700 seconds measured from the earliest `started_at`, not the sum of the periods

### Requirement: Superseded Provider Conversations Are Released Asynchronously

The server MUST release a provider conversation that no live row depends on, through a queued job
`ReleaseProviderConversation` that carries scalar identifiers only, declares `$tries` and `$timeout`, and
runs under `TenantContextScope::runFor`. It MUST be dispatched `afterCommit` with a delay (a) from the
ceiling resume, (b) from `POST /end` when `next_action` is not `continue`, and (c) from the stale-interview
reaper after it ends a row. The job MUST be best-effort and idempotent, never decide a request's outcome, and
never release a ref that a live row still uses. It is belt-and-braces: Tavus ends a conversation after
`participant_left_timeout` (documented default 0) and `participant_absent_timeout` (default 300), neither of
which BEAI sets to a value that would rely on this job.

#### Scenario: The ceiling resume dispatches a delayed release instead of tearing down inline

- GIVEN a resume that issues a fresh ref because the old one is near its ceiling
- WHEN the transaction commits
- THEN `ReleaseProviderConversation` is dispatched with a delay for the old ref and `teardown()` is not
  called inline

#### Scenario: A terminal /end dispatches a release

- GIVEN the last competency ends with `next_action = 'done'`, or a pause
- WHEN `/end` commits
- THEN a release is dispatched for the row's ref when no live row shares it

#### Scenario: The reaper dispatches a release

- GIVEN `ReapStaleInterviews` ends an abandoned `in_corso` row
- WHEN the row is marked `timeout`
- THEN a release is dispatched for its ref

#### Scenario: A shared live ref is never released

- GIVEN a ref still used by an `in_corso` row
- WHEN a release job for that ref runs
- THEN no `POST /v2/conversations/{id}/end` is sent

### Requirement: At Most One Open Live Period Per Provider Reference

The database MUST enforce at most one open `interview_session_live_periods` row per non-null
`provider_session_ref` through a partial unique index
(`provider_session_ref IS NOT NULL AND ended_at IS NULL`), in addition to the existing at-most-one-open-
period-per-session index. The migration MUST be additive, write no data, and drop the index in `down()`.

#### Scenario: A second open period on the same ref raises a unique violation

- GIVEN an open period on ref R for one row
- WHEN a second open period on R is inserted for another row
- THEN the database raises a unique violation

#### Scenario: Closed periods and null refs do not collide

- GIVEN several closed periods on ref R and several open periods with a null ref
- WHEN they are inserted
- THEN no violation occurs
