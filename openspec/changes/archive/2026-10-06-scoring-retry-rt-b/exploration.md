# Exploration: scoring-retry-rt-b

Single domain retry (RT-B) of a `pending` evaluation. Source: Engram `sdd/scoring-retry-rt-b/explore` (obs 3533), verified by the orchestrator on three points (evaluation webhook dedupe key, 2h finalize lock, terminal `completato`).

## Settled owner decision (2026-10-05)

The retry is authorized by BOTH the backoffice operator AND the calling system (M2M API) through ONE shared authorization action that mints a fresh single-use candidate token and dispatches the retry. Rejected: calling-system-only, candidate self-service.

## What exists

- `evaluations.retry_attempt` column and cast (`Evaluation.php:61,74`); job flag `retryAttempt` (`ScoreEvaluationJob.php:108`); resume-skip by existing `CompetencyResult` (`:384-397`).
- `competency_results` unique `(evaluation_id, competency_code)`, indicator scores cascade; `ai_requests` is append-only.
- `ResetSessionForRetry` resets a session to `pending` and deletes its utterances.
- `RecoverFailedParticipant` is the closest precedent (`errore -> in_attesa` edge, row lock, 409 `RecoveryRefused`, `ParticipantPolicy::recover`, `POST /api/participants/{id}/recover`, backoffice `ParticipantRecoveryPanel.vue`).
- `EntryLinkMinter` (30-minute sso-link) and `SendCandidateInvitationJob` (email).
- `resolveNextCompetency` already offers competencies whose session is `pending` or missing (`InterviewController.php:988-1007`).

## Gaps

1. `completato` is terminal (`Participant.php:165`) and every candidate gate rejects it; a new edge `completato -> in_attesa`, reachable only through the RT-B action, is required. With it, RT-B-O3's premise dissolves.
2. `FinalizeInterview` Redis lock `finalize:{pid}` lasts 7200 s: a re-interview finished inside 2 h would be silently dropped.
3. `DispatchScoringJob.php:80` never passes `retryAttempt: true`.
4. The job retry branch (`ScoreEvaluationJob.php:262-267`) is a stub pinned by `ScoreEvaluationJobDefensiveBranchesTest.php:794`.
5. `ResolveEvaluationTerminalState` must force `Completed` on a retry whatever the ratio.
6. Webhook dedupe trap: the evaluation webhook `dedupe_key` is the `evaluation_id` (spec + `SendEvaluationWebhook.php:86` + unique index), so the definitive `completed` webhook of SA-07 would be collapsed into the first `pending` one and never sent. The retry needs its own dedupe key and a webhooks-integration spec delta.
7. RT-B-O2 is worse than the spec says: on retry exhaustion `failed()` would move the participant from `in_valutazione` to `errore`, the `EvaluationFailed` webhook is swallowed by the same dedupe key, and `RecoverFailedParticipant` then refuses. Recommended: finalize the evaluation `completed` with the valid results retained and the participant `completato`, never `errore`.
8. RT-B-O1: `processing + retry_attempt=true` is already covered by the delivered resume-skip guard; `completed + retry_attempt=true` is unspecified, recommended no-op plus log.
9. No `participants:retry` ability, `UserAbilities` flag, policy method or route.
10. The `retry` opening variant is an apology for a provider error; RT-B needs neutral wording.
11. While the participant is `in_attesa`/`in_corso` the pending evaluation is unreadable (read gate is `completato`).
12. Docs to update: `CLAUDE.md` ruling 4, `ROADMAP.md:72`, the spec DEFERRED banner, the lifecycle doc.

## Slice plan (authored lines, tests included; budget about 400)

| Slice | Repo | Content | Estimate |
|---|---|---|---|
| PR1 | api | `AuthorizeEvaluationRetry` action, refusal types, participant edge, finalize-lock reset, policy | ~350 |
| PR2 | api | job retry branch, forced `Completed`, dispatch flag, `failed()` (O2), completed+retry no-op, webhook dedupe key | ~400 |
| PR3 | api | operator and M2M endpoints, ability `participants:retry`, `UserAbilities` flag, openapi, neutral opening copy | ~300 |
| PR4 | backoffice | panel, composable, i18n it/en, abilities contract, tests | ~300 |
| PR5 | wrapper | spec, `CLAUDE.md`, `ROADMAP.md`, lifecycle docs | ~120 |
| optional | api | `/v1` endpoint, SPEC, `ExposureCatalogue` (T-EXPOSE-001), SDK | ~350 |

Frontend: probably 0 lines (to verify).

## Approaches

- Reopen invalid competencies only: invalid = project competencies minus `CompetencyResult.valid=true`; reset existing sessions with `ResetSessionForRetry`. Recommended.
- Merge: delete the invalid results and set `processing` at retry-job start in one transaction, then reuse resume-skip (recommended; the spec's "single transaction" wording must be relaxed). Alternatives: per-competency atomic replace with a marker column; stage DTOs and swap (high risk).
- Token: after the flip to `in_attesa` the existing minter, sso-link and session-token surfaces work unchanged; the action returns the minted link.
- Single-retry flag: reuse `evaluations.retry_attempt`, optional `retry_authorized_at` for audit.

## Remaining product decisions (ranked)

1. How the candidate receives the new link (BEAI email, delivery by the caller, or both; legacy placeholder emails cannot be mailed).
2. Link lifetime (30 minutes is short for an emailed link).
3. What happens if the candidate never re-interviews.
4. Webhook semantics after a retry (second `evaluation` webhook always `completed`; extra event at authorization?).
5. What operator and caller see while the retry is in progress.
6. M2M surface: internal `/api/m2m` or public `/v1`.
7. Policy when the retry job fails technically.
8. Roles and abilities allowed to authorize; reason field and audit log.
9. Whether a closed or expired project blocks authorization.
10. Candidate-facing opening wording.
