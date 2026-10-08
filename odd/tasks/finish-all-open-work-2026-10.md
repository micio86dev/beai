# Finish all remaining open work (2026-10-08)

## Objective
The owner wants zero unfinished work: every follow-up left by `close-open-sdd-changes-2026-10` is completed, merged
into `develop` in every repo, and no work branch is left open ("completa tutto, mergia tutto, nessun branch aperto").

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
- [ ] F1 `acting-org-409-contract` (api, backoffice if needed): 409 `organization_context_required` on POST /projects,
      org PATCH, logo store/destroy; keep GET /organization `data:null` (backoffice already handles it); Part B
      ability suppression in `UserAbilities`; arch guard on `$user->organization_id` under `app/Http`; reconcile
      `no_client_selected` vs `organization_context_required`; OpenAPI + clients sync
- [ ] F2 HeyGen live test (a)/(b) via the local api container; record evidence; update the archived
      `pluggable-conversation-llm` report and merge the requirement that was blocked, only if proven
- [ ] F3 `db-driven-conversation-prompts`: rescope design to the current composer, tasks, golden test, tables,
      resolver, composer cut-over, `conversation_prompt_version` stamp (chained PRs, each under the review budget)
- [ ] F4 `tavus-single-session-interview`: tasks.md, api session model + `ReleaseProviderConversation`, frontend
      Tavus data-channel boundary path, 3600 s ceiling handover
- [ ] F5 `native-duplex-conversation`: only if F2 proves it is feasible; otherwise record the proven blocker
- [ ] F6 merge everything into `develop`, delete work branches, restore submodule pins, final status

## Acceptance criteria
- `openspec/changes/` holds only changes that are still genuinely blocked, each with the proven blocker.
- `git branch -a` shows only `main`/`develop` (+ remotes) in every repo; no open PR.
- All suites green per repo; gga PASSED on each slice.

## Progress
F0 done. Starting F1 (api writer) and F2 (live test) in parallel.

## Next step
F1 and F2 reports, verify on disk, then F3.
