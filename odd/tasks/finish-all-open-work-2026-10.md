# Finish all remaining open work (2026-10-08)

## Objective
The owner wants zero unfinished work: every follow-up left by `close-open-sdd-changes-2026-10` is completed, merged
into `develop` in every repo, and no work branch is left open (complete everything, merge everything, leave no branch open).

## Scope (owner decisions, 2026-10-08)
1. `db-driven-conversation-prompts`: implement (text is extracted from the current PHP, output stays byte-identical;
   the Italian text already exists in the composer, nothing new to author).
2. Acting-organization 409 contract: do it now (new change `acting-org-409-contract`).
3. HeyGen live questions (a) secret placement and (b) `llm_configuration_id` on `POST /v1/contexts`: the agent runs
   the test itself, using the credential already configured in the local `beai_api` container (no `.env` read, key
   never printed), then closes `pluggable-conversation-llm` P5.12/P5.13 and unblocks `native-duplex-conversation`.
4. `tavus-single-session-interview`: keep and implement to 100%.
5. Leftover local api branches: superseded by develop (potential start covered by `InterviewStartCompositionTest`
   at develop `:717`; the pre-recut docblock commit was re-cut into small commits). Deleted 2026-10-08; tips for
   recovery: `b6bbb47`, `0d8f24e`, `236ad04`.

## Constraints
- Repo language English. Conventional commits, no AI attribution. Bun only for Nuxt apps. Git Flow: `feature/*` off
  `develop`, PR, merge on green CI, delete merged branches. No release, tag or deploy unless the owner asks.
- gga review on every slice (docs-only slices need the temporary `.gga` trick, see memory). Native review consent is
  the owner's, relayed per candidate; a slice over the native budget (`lens_context_budget_exceeded`) is split into
  smaller commits/PRs instead of one big one.
- Strict TDD (RED observed first), runner Pest (api) / Vitest + Playwright (Nuxt apps). Coverage 85%, ~95% on tenant
  scoping and scoring. One api Pest run at a time (shared test DB); one docker build at a time (4 GB).
- T-EXPOSE-001 for any public field. Verify every delegated claim on disk and by re-running tests.
- Live provider calls only as authorized above (HeyGen test now); Tavus live calls need a separate explicit go.

## Tasks
- [x] F0 delete the three superseded local api branches (verified superseded)
- [x] F1 `acting-org-409-contract` (api, backoffice if needed): 409 `organization_context_required` on POST /projects,
      org PATCH, logo store/destroy; keep GET /organization `data:null` (backoffice already handles it); Part B
      ability suppression in `UserAbilities`; arch guard on `$user->organization_id` under `app/Http`; reconcile
      `no_client_selected` vs `organization_context_required`; OpenAPI + clients sync.
      Evidence: merged into `develop` (api PR #143 `e0c30d3`, backoffice PR #83 `05dfea9`, frontend PR #66 `99523a3`,
      wrapper PR #88 with the archive). Native review of the api part APPROVED; the wrapper docs review ended
      `escalated`; `gga` PASSED.
- [x] F2 HeyGen live test (a)/(b) via the local api container; record evidence; update the archived
      `pluggable-conversation-llm` report and merge the requirement that was blocked, only if proven.
      Evidence (2026-10-08): (a) PROVEN, `llm_configuration_id` is a top-level field of `POST /v1/sessions/token`
      (nested under `avatar_persona` it is silently ignored; unknown id passes the token call and fails at
      `/sessions/start` with 400); (b) PROVEN NO, `/v1/contexts` has no LLM field, so P5.12/P5.13 are not applicable;
      the secrets API has no update verb. Bug found and fixed: `HeygenProvider::teardown()` used
      `DELETE /v1/sessions/{ref}` (405); the real stop is `POST /v1/sessions/stop` (api PR #144, merged, `develop`
      `e215c43`). Archive docs, the merged requirements and the native-duplex status are updated in the wrapper.
      Follow-up F2c (HeyGen context cleanup, about 20 `beai-*` contexts left by `issue()`) was still open when this was written; it is ticked below (api #145).
- [x] F2c HeyGen context cleanup: `provider_context_ref` column, `DELETE /v1/contexts/{id}` after a confirmed stop, plus the
      two non-blocking test warnings of the F2b review (branch `feature/heygen-context-cleanup`)
      Evidence: merged into api `develop` as PR #145 (`6c78b77`, 2026-10-08), CI check `Lint · Analyse · Test ·
      OpenAPI · Docker` SUCCESS; the migration `2026_10_08_100000_add_provider_context_ref_to_interview_sessions_table`
      is on `origin/develop`. Per the PR description: full suite 8458 tests, 0 failed, Pint and PHPStan clean; the native
      review lineage ended in `recover` / `scope_changed`, so no native approval exists for it (compensated by an
      independent read-only review and `gga`).
- [x] F3 `db-driven-conversation-prompts`: rescope design to the current composer, tasks, golden test, tables,
      resolver, composer cut-over, `conversation_prompt_version` stamp (chained PRs, each under the review budget)
      Evidence (2026-10-09): rescoped in wrapper PR #90 (`852ec65`); delivered in api `develop` as PRs #146 (goldens),
      #147 (stamp), #148 (vocabulary), #149 and #150 (composer reads fragments), #151 (tables), #152 (resolver), #153
      (publish and activate), #155 (32nd key `opening.continuation`, no second greeting), #156 (bootstrap,
      `baseline-1`), #157 (cut-over, `CONVERSATION_PROMPT_SOURCE=db|baseline`, deploy gate) and #158 (overrides), merge
      commits `c494d31` to `cf1d82a`; each PR's `Lint · Analyse · Test · OpenAPI · Docker` check is SUCCESS (the
      `develop` run for `cf1d82a` was still in progress when this was written). Archived as
      `openspec/changes/archive/2026-10-09-db-driven-conversation-prompts/` with the specs merged
      (`conversation-prompt-templates` new; `interview-conversation` and `framework-catalog` composed). NOT part of
      this tick: no release and no deploy, and the cleanup PR that deletes the baseline PHP after a soak (both listed
      in its `archive-report.md`).
- [ ] F4 `tavus-single-session-interview`: tasks.md, api session model + `ReleaseProviderConversation`, frontend
      Tavus data-channel boundary path, 3600 s ceiling handover
- [ ] F5 `native-duplex-conversation`: only if F2 proves it is feasible; otherwise record the proven blocker
- [ ] F6 merge everything into `develop`, delete work branches, restore submodule pins, final status

## Acceptance criteria
- `openspec/changes/` holds only changes that are still genuinely blocked, each with the proven blocker.
- `git branch -a` shows only `main`/`develop` (+ remotes) in every repo; no open PR.
- All suites green per repo; gga PASSED on each slice.

## Progress
F0, F1, F2, F2c and F3 done (2026-10-09). F2c (HeyGen context cleanup keyed on `provider_context_ref`) is api PR #145,
merged. F3 (`db-driven-conversation-prompts`) is merged in api as #146 to #158 and archived in the wrapper; the
wrapper `api` pointer still pins release 0.68.0 and nothing was released or deployed. F4
(`tavus-single-session-interview`) is pending. F5 is re-scoped: the HeyGen
questions are proven, so `native-duplex-conversation` is no longer blocked on them and needs its proposal amended and
its own question round. F6 is pending.

## Next step
Do F4; amend the `native-duplex-conversation` proposal (F5); then F6 (merge, branch cleanup, submodule pins, final
status). No release, tag or deploy unless the owner asks.
