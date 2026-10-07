# Proposal: Scoring Retry (RT-B) — single re-interview of a `pending` evaluation

## Intent

An evaluation below the 90% completion gate is finalized `pending` and its webhook carries
partial data (SA-07). The binding business rules (`05-business-rules/01-candidate-lifecycle.md`
"Interview retry", `02-evaluation-rules.md` "Retry handling") require exactly ONE retry: the
candidate repeats the interview for the competencies that came out invalid, and the next
evaluation is definitive `completed` even below the threshold. Today none of this is reachable:

- `completato` is terminal (`api/app/Models/Participant.php:165`), so a candidate cannot re-enter.
- The job's retry branch is a stub (`api/app/Jobs/ScoreEvaluationJob.php:262-266`) and
  `DispatchScoringJob` never passes `retryAttempt` (`api/app/Listeners/DispatchScoringJob.php:80`).
- The evaluation webhook `dedupe_key` IS the `evaluation_id`
  (`api/app/Listeners/SendEvaluationWebhook.php:86`, webhooks-integration spec), so the
  definitive `completed` webhook SA-07 requires would be collapsed into the first `pending` row
  and never sent.

The requirement has been specced but DEFERRED since C9 (scoring-engine "Retry — Fast-Follow
Work Unit (RT-B)", ROADMAP decision 4 OPEN). The owner settled the blocking product decisions on
2026-10-05, so the chain-PR 4 can now be delivered.

**Success looks like:** an admin/operator in the backoffice, or the calling system through the
M2M API, authorizes the single retry of a `pending` evaluation; the candidate receives a fresh
single-use link by email (and the authorizer gets the link back); only invalid competencies are
re-interviewed; valid results are retained; exactly one further `evaluation` webhook arrives with
status `completed`.

## Owner decisions (settled 2026-10-05, not reopened here)

- **D-A** — The retry is authorized by BOTH the backoffice operator AND the calling system (M2M)
  through ONE shared authorization action. Rejected: calling-system-only, candidate self-service.
- **D-B** — The candidate receives the new link through a BEAI transactional email (same family as
  the existing invitation, ruling 10: static, multilingual it/en, tenant chrome only) AND the link
  is returned to whoever authorized it. Placeholder emails (legacy rows, purged rows): no email,
  link returned only.
- **D-C** — If the candidate never re-interviews, the evaluation stays `pending` and the participant
  stays `in_attesa` indefinitely. No expiry and no auto-finalize (consistent with ratified
  decision 5: BEAI has no deadline concept).

## Assumptions (explorer defaults — owner may override each)

| ID | Assumption | Rationale |
|----|------------|-----------|
| A1 | **OVERRIDDEN by the owner on 2026-10-05.** ALL emailed candidate invitation links — the initial invitation AND the RT-B retry link — live **24 hours** (config-driven), single-use and signed as today. This replaces the explorer default (60 minutes, `scoring.retry.link_ttl_minutes`). It is delivered as a prerequisite slice **PR0** (api) that the retry slices depend on, and it amends the binding `CLAUDE.md` rule "SSO ingress short expiry (15–60 min)" at the wrapper docs slice. | Owner's decision: a 30/60-minute lifetime is too short for a link a candidate reads in an inbox. Expiry stays recoverable: once the participant is `in_attesa` the existing operator entry-link and M2M sso-link mints work unchanged. Scope is the email-delivered links only (see the participant-sso delta). |
| A2 | The post-retry `evaluation` webhook is always status `completed` and uses its own dedupe key `{evaluation_id}:retry`; retry-era `competency-ended` progress events use `competency-ended:{participant_id}:{code}:retry`. No new webhook event type is emitted at authorization. | Same collision class as the evaluation key: without a distinct key the re-interview's progress events would be silently absorbed by the unique index. The calling system learns of the retry from progress events and the final webhook. — owner may override |
| A3 | While the retry is in progress the evaluation stays unreadable through the existing read gate (structured evaluation only at `completato`); the backoffice panel shows the retry state (authorized at, re-interview pending/in progress/scoring). | Reuses the existing gate rather than inventing a partial-read mode. — owner may override |
| A4 | The M2M surface is the internal `/api/m2m` (`POST /api/m2m/participants/{id}/retry`). The public `/v1` endpoint (SPEC, `ExposureCatalogue` T-EXPOSE-001 entry, SDK) is explicitly deferred to a follow-up change. | Keeps public exposure out of this change; T-EXPOSE-001 stays untouched. — owner may override |
| A5 | **RT-B-O2 resolution:** if the retry scoring job fails technically (queue retries exhausted), the evaluation is finalized `completed` with the retained valid results and the participant moves to `completato`, never `errore`. | Today `failed()` would move `in_valutazione -> errore`, the `EvaluationFailed` webhook would be swallowed by the dedupe key, and `RecoverFailedParticipant` would refuse (evaluation already delivered) — an unrecoverable dead end. The retry is the definitive run by rule. — owner may override |
| A6 | **RT-B-O1:** `processing + retry_attempt=true` stays on the delivered resume-skip path; `completed + retry_attempt=true` is a logged no-op. | Covers the crash-mid-retry and duplicate-dispatch races. — owner may override |
| A7 | **RT-B-O3** dissolves: a new `completato -> in_attesa` edge, writable ONLY by the authorization action, lets the normal `in_attesa -> in_corso -> in_valutazione -> completato` path run again. | Mirrors the `errore -> in_attesa` precedent of `RecoverFailedParticipant`. — owner may override |
| A8 | Roles: Spatie `admin` and `operator` may authorize, `viewer` is denied; new M2M ability `participants:retry`. Optional free-text `reason`, recorded in an interim structured log (same shape as `participant.recovered`); the ratified audit log is out of scope. | Same authorization shape as the recovery action. — owner may override |
| A9 | A closed, not-yet-live or past-deadline project refuses authorization through the existing `EntryLinkMinter::projectIsAccessible()` gate (409 with a typed refusal reason). | One gate, already shared by every mint. — owner may override |
| A10 | The re-interview opens with a neutral wording variant (not the existing `retry` variant, which apologizes for a provider error). | The candidate did nothing wrong and nothing broke. — owner may override |
| A11 | Only invalid competencies are re-interviewed: invalid = project competencies minus `CompetencyResult.valid = true`; their sessions are reset with `ResetSessionForRetry`. Merge: at retry-job start, delete the invalid results and set the evaluation `processing` in ONE transaction, then reuse resume-skip. The spec's "entire merge runs in a single DB transaction" wording is relaxed accordingly. | Reuses delivered, tested machinery; crash-safety comes from the existing `processing` resume path; the evaluation is unreadable during the window (A3). — owner may override |
| A12 | A concurrent second authorization (operator and caller racing) is refused 409 `retry_already_consumed` under the participant row lock; the link is minted once and never re-returned. | The link is single-use and is never stored. — owner may override |
| A13 | The retry action releases the `finalize:{participant_id}` Redis lock (TTL 7200 s, `api/app/Jobs/FinalizeInterview.php:57`) so a re-interview finished within two hours is not dropped. | Otherwise SA-07 fails silently for any fast candidate. — owner may override |
| A14 | PR5 also syncs the stale `openspec/ROADMAP.md` decisions 8 and 9 (still "BEAI does not hold contact data" / "white-label PARKED") with `CLAUDE.md`, which reversed both on 2026-09-01. Doc-only. | Found while verifying; the retry email depends on ruling 8 as reversed. — owner may override |

## Scope

### In Scope
- One shared `AuthorizeEvaluationRetry` action (org-scoped, row lock, typed 409 refusals: not
  `completato`, evaluation not `pending`, retry already consumed, project inaccessible), the
  `completato -> in_attesa` edge, invalid-session reset, finalize-lock release, retry-link mint with
  the A1 TTL, transactional email dispatch (D-B), interim log (A8), `retry_attempt = true` (plus an
  optional `retry_authorized_at` audit column).
- `ScoreEvaluationJob` retry branch: delete-invalid + `processing` in one transaction, resume-skip
  re-scoring, forced `Completed` via `ResolveEvaluationTerminalState`, dispatch flag from
  `DispatchScoringJob`, `failed()` per A5, no-op per A6.
- Webhook dedupe keys per A2 (evaluation and retry-era progress).
- `RecoverFailedParticipant` guard adjustment so an interview-stage `errore` DURING a retry stays
  recoverable (the first `pending` webhook must not make it unrecoverable).
- Endpoints: `POST /api/participants/{id}/retry` (backoffice) and `POST /api/m2m/participants/{id}/retry`
  (ability `participants:retry`), policy method, `UserAbilities` flag, OpenAPI regeneration.
- Retry invitation email copy (it/en) and the neutral opening variant (A10).
- Backoffice retry panel (state + authorize + link display + email-sent status), composable,
  i18n it/en, abilities contract, Vitest and Playwright coverage.
- Docs: scoring-engine DEFERRED banner removed, `CLAUDE.md` ruling 4 and `ROADMAP.md:72`
  promoted OPEN -> RATIFIED at archive, lifecycle doc, A14 sync.

### Out of Scope
- Public `/v1` retry endpoint, its SPEC/SDK, and the T-EXPOSE-001 catalogue entry (A4).
- Any retry expiry, deadline, reminder or auto-finalize (D-C, ratified decision 5).
- The ratified audit-log capability (interim log only).
- Candidate self-service retry (rejected by D-A).
- A second or configurable number of retries (binding: exactly 1).
- Retry of `potential` assessment specifics beyond what the shared pipeline already does (the
  same invalid-only rule applies; no MTG/LAT-specific behavior is added).
- Changes to the C12 operator notifications (the retry email is transactional, not a C12 trigger).

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `scoring-engine`: RT-B promoted from DEFERRED to delivered; retry branch, merge semantics (A11,
  relaxing "single transaction"), forced `completed`, dispatch flag, `failed()` on retry (A5),
  `completed + retry_attempt=true` no-op (A6), RT-B-O1/O2/O3 resolved and removed from the banner.
- `webhooks-integration`: dedupe-key requirement amended — `{evaluation_id}:retry` for the
  post-retry evaluation event, `:retry` suffix for retry-era `competency-ended` progress events (A2).
- `interview-session`: transition map (FIX-5) gains `completato -> in_attesa`, writable only by the
  retry action; `completato -> errore` stays forbidden.
- `participant-sso`: Participant Model Lifecycle Guard gains the new edge; new requirements for the
  shared retry authorization action, refusal guards, retry-link mint TTL (A1), the retry email
  (D-B, placeholder rule), interim retry log, and the recovery guard exception for an interview-stage
  `errore` during a retry.
- `m2m-auth`: new ability `participants:retry` in the ability catalogue and the M2M retry route.
- `admin-backoffice`: retry panel, ability gating (admin/operator yes, viewer no), link and
  email-sent display, retry state.
- `admin-read-api`: participant detail exposes the retry state (`retry_attempt`, authorized at)
  needed by the panel; the evaluation read gate is unchanged (A3).
- `interview-conversation`: neutral re-interview opening variant (A10).

## Approach

Model the action on `RecoverFailedParticipant` (`api/app/Actions/Participant/RecoverFailedParticipant.php`):
org filter + `lockForUpdate` inside one `DB::transaction`, status re-read inside the lock, typed
refusals rendered 409, a 403-before-404 order, interim log. Inside the transaction: verify
`completato` + evaluation `pending` + `retry_attempt = false` + project accessible; flip the
participant to `in_attesa`; reset the invalid competencies' sessions with `ResetSessionForRetry`;
set `retry_attempt = true`. After commit: release the finalize lock, mint the link through
`EntryLinkMinter` (which already accepts an `in_attesa` participant; it needs a TTL parameter),
queue `SendCandidateInvitationJob`-style delivery with retry copy unless the address is a
placeholder, and return `{entry_url, expires_at, email_sent}` — the same response shape as the
operator entry-link endpoint. Both HTTP surfaces are thin controllers over this one action (D-A).

The candidate then follows the existing exchange -> interview path; `resolveNextCompetency`
already offers only `pending`/missing sessions, so valid competencies are skipped. On completion,
`DispatchScoringJob` reads the evaluation's `retry_attempt` and dispatches with
`retryAttempt: true`; the job deletes invalid results and sets `processing` in one transaction,
re-scores via resume-skip, forces `completed`, and emits `EvaluationCompleted`, which records the
delivery under `{evaluation_id}:retry`.

The slices are dark until PR3 wires the routes, so each earlier slice merges without any
user-reachable behavior change.

## Slice plan (stacked-to-main, auto-chain; ~400 authored lines per PR, tests included)

| Slice | Repo | Content | Estimate |
|---|---|---|---|
| PR1 | api | `AuthorizeEvaluationRetry` action, refusal enum/exception, `completato -> in_attesa` edge, invalid-session reset, finalize-lock release, minter TTL parameter, policy method, interim log | ~350 |
| PR2a | api | job retry branch (delete-invalid + `processing` transaction, resume-skip), forced `Completed`, `DispatchScoringJob` flag | ~240 |
| PR2b | api | `failed()` on retry (A5), `completed + retry_attempt` no-op (A6), webhook dedupe keys (A2), recovery guard exception during retry | ~220 |
| PR3 | api | backoffice and M2M endpoints, ability `participants:retry`, `UserAbilities` flag, admin-read retry state, retry email copy it/en, neutral opening variant, OpenAPI export | ~350 |
| PR4 | backoffice | retry panel, composable, i18n it/en, abilities contract, regenerated client, Vitest + Playwright | ~300 |
| PR5 | wrapper | spec promotion, `CLAUDE.md` ruling 4, `ROADMAP.md:72` (+A14), lifecycle doc, submodule pins | ~120 |
| deferred | api | public `/v1` endpoint, SPEC, `ExposureCatalogue` T-EXPOSE-001, SDK | ~350 (separate change) |

The exploration's single PR2 (~400) sat exactly at the budget; it is split into PR2a/PR2b.
Frontend: expected 0 lines (the opening text is composed by the api) — to be confirmed in design.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `api/app/Actions/Participant/AuthorizeEvaluationRetry.php` | New | Shared authorization action |
| `api/app/Models/Participant.php` | Modified | Transition map `completato -> in_attesa` |
| `api/app/Jobs/ScoreEvaluationJob.php` | Modified | Retry branch, `failed()` on retry, no-op |
| `api/app/Actions/Scoring/ResolveEvaluationTerminalState.php` | Modified | Forced `Completed` on retry |
| `api/app/Listeners/DispatchScoringJob.php` | Modified | Passes `retryAttempt` |
| `api/app/Listeners/SendEvaluationWebhook.php`, `SendProgressWebhook.php` | Modified | Retry dedupe keys |
| `api/app/Jobs/FinalizeInterview.php` | Modified | Lock release hook |
| `api/app/Support/Sso/EntryLinkMinter.php`, `api/app/Support/Jwt/CandidateTokenFactory.php` | Modified | TTL parameter for the retry link |
| `api/app/Actions/Participant/RecoverFailedParticipant.php` | Modified | Guard exception during retry |
| `api/routes/api.php`, new controllers, policy, ability catalogue | Modified/New | Two endpoints, `participants:retry` |
| `api/app/Notifications/*`, `api/lang/{it,en}` | New/Modified | Retry email copy, neutral opening variant |
| `backoffice/` | New/Modified | Retry panel, composable, i18n, tests |
| `openspec/specs/*`, `CLAUDE.md`, `openspec/ROADMAP.md`, `docs/app_description/05-business-rules/01-candidate-lifecycle.md` | Modified | Promotion and docs |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Webhook dedupe collision: the definitive `completed` webhook (and retry-era progress events) absorbed by the unique index | High if unaddressed | A2 retry dedupe keys + webhooks-integration delta + a test asserting two distinct evaluation delivery rows |
| Finalize lock (7200 s) silently drops a re-interview finished within 2 h | High if unaddressed | A13 lock release in the action + test with a fast re-interview |
| Unrecoverable `errore`: an interview-stage failure during the retry hits the recovery guard "evaluation already delivered" | Med | Recovery guard exception scoped to `retry_attempt = true` + `pending` evaluation |
| Scoring-stage failure during retry leaves `errore` with a swallowed webhook | Med | A5: finalize `completed`, never `errore` |
| State-machine invariant change: `completato` is no longer terminal; other code may assume it is | Med | Edge writable only by the action (guard + arch/feature tests); audit every `completato` check (read gates, minter, `ParticipantStatusGuard`) in design |
| 400-line budget: PR2 at the limit, PR1/PR3 near it | Med | PR2 split into PR2a/PR2b; OpenAPI and regenerated clients excluded as generated |
| 30-minute link precedent vs emailed retry link | Med | A1: config TTL, default 60 (binding ceiling); re-mint always possible while `in_attesa`; Q1 for anything longer |
| Race between operator and M2M authorization | Low | Row lock + `retry_attempt` set in the same transaction (A12) |
| Merge window: invalid results deleted before re-scoring completes | Low | Evaluation unreadable until `completato` (A3); crash resumes on the `processing` path |

## Rollback Plan

- Every slice before PR3 is dark (no route reaches it); revert its merge commit and re-release.
- To stop the feature after PR3/PR4: revert PR3 (routes, ability) and PR4 (panel). No new
  authorizations can occur. The optional `retry_authorized_at` migration is reversible; the
  `retry_attempt` column already exists and is untouched.
- Participants already mid-retry at rollback time (`in_attesa`, evaluation `pending`,
  `retry_attempt = true`): do NOT revert PR2a/PR2b until they have finished or been accepted as
  remaining `pending` (D-C makes that state legitimate). Reverting PR2a while such a participant
  completes the re-interview would turn its scoring into a no-op and leave it `pending`.
- Webhook delivery rows written under `:retry` keys remain valid history; no data migration is
  needed to revert.

## Dependencies

- Owner decisions D-A, D-B, D-C (settled 2026-10-05).
- Existing delivered machinery: `RecoverFailedParticipant`, `ResetSessionForRetry`,
  `EntryLinkMinter`, `SendCandidateInvitationJob`, resume-skip in `ScoreEvaluationJob`.
- Production mail delivery (known broken on both paths pending Resend domain verification —
  memory "prod mail is broken"); the link-returned path (D-B) works regardless.

## Success Criteria

- [ ] SA-07 passes end to end: `pending` webhook, authorized retry, re-interview of invalid
      competencies only, a second `evaluation` webhook with status `completed` (distinct delivery row).
- [ ] The same action is reachable by an admin/operator (backoffice) and by an M2M client with
      `participants:retry`; a viewer and a client without the ability get 403; cross-tenant ids 404.
- [ ] Valid `CompetencyResult` rows survive the retry unchanged; the `Evaluation` row is updated in place.
- [ ] A second authorization is refused 409; a non-`pending` or non-`completato` participant is refused 409.
- [ ] The candidate receives the retry email (non-placeholder address) and the authorizer always
      receives `entry_url` + `expires_at` + `email_sent`.
- [ ] A retry scoring failure ends `completed` / `completato`, never `errore`.
- [ ] Coverage: 85% overall, ~95% on the retry state-machine and scoring branch; Pest, Vitest and
      Playwright green in CI on all affected repos.
- [ ] `CLAUDE.md` ruling 4 and `ROADMAP.md:72` read RATIFIED with owner-confirmed wording at archive.

## Remaining Open Product Questions

- **Q2 — Ruling 4 wording.** At archive, `CLAUDE.md` ruling 4 and `ROADMAP.md:72` are promoted from
  OPEN to RATIFIED. Proposed wording for owner confirmation:
  "4. **RATIFIED 2026-10-05** — retry semantics. Exactly one retry per evaluation, offered only for a
  `pending` evaluation of a `completato` participant, authorized by an admin/operator or by the
  calling system (`participants:retry`) through one shared action. It re-interviews invalid
  competencies only, emails the candidate a fresh single-use link that is also returned to the
  authorizer, and the next evaluation is definitive `completed`. No expiry: a retry never taken
  leaves the evaluation `pending` and the participant `in_attesa`."
