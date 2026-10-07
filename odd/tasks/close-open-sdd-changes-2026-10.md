# Close the open SDD changes (2026-10-08)

## Objective
Leave no SDD change in `openspec/changes/` in an unknown state. Each one is either archived with an honest record of
what was delivered, deferred or dropped, or explicitly kept open with the reason and the remaining work.

## Problem
A review on 2026-10-08 found 17 non-archived change folders. Exploration against `develop` showed most "open" work is
already delivered (often through a different mechanism than the design) and only the bookkeeping is stale; a few
items are genuinely unstarted or blocked on a human.

## Findings (verified in code, not from checkboxes)
- Complete, unarchived: `docker-disk-guard`, `image-upload-crop-field`, `scoring-audit-jev`, `stale-interview-reaper`.
- `scoring-role-scoped-indicators`: the production defect is fixed by `6087bbd` + `RoleScopedIndicatorsTest`; checked
  tasks 1a.2/1a.9/1a.10/1b.4/1b.5 are NOT in code (loader never relocated, `roleId: 0` sentinel remains); arch guard,
  spec edits and purge (4.x) not done.
- `superadmin-acting-organization-context`: user-visible bug fixed by `c9096df` via `TenantResolver::getOrgId()`;
  `EffectiveOrganization` was never created. Residual gaps: no-acting-org states answer 404/403/422 instead of 409 on
  `POST /projects`, org PATCH and logo routes; ability suppression (part B); arch guard.
- `pluggable-conversation-llm`: P9 backoffice is delivered (`c129cb8`) except a Model label on template rows; delta
  specs not merged; P5.12/P5.13/0.3/P5.0/F.6 need a human with live HeyGen credentials.
- `avatar-template-catalogue`: 5.2 (live CDN-URL check) needs credentials; 5.3 spec merge/archive pending.
- `platform-user-management`: only 6.4 (E2E needing a superadmin client-switch fixture) open.
- `db-driven-conversation-prompts`: not implemented; design stale (section map, line refs, "revision" name clash with
  the catalogue); ~2k lines; rewrites the live interview prompt; Italian seed text needs a human author.
- Seven proposal-only changes: triage in task C6.

## Decisions
- NOT implemented unattended: `db-driven-conversation-prompts` (product decision, live-prompt risk, human-authored
  Italian text) and the acting-org 409/part-B hardening (API error-code contract change, OpenAPI + SDK regeneration,
  release); both recorded as explicit follow-ups, not silently dropped.
- Code written: only the scoring arch guard (test-only, no behaviour change, no release).
- No deploy, no release, no tag. Docs/test changes go through Git Flow to `develop` only.

## Constraints
- Repo language English. Conventional commits, no AI attribution. Bun only for Nuxt apps.
- Feature branch `feature/close-open-sdd-changes` (wrapper) and `feature/scoring-bars-role-scope-arch-guard` (api).
- Never delete unmerged branches; keep the three local api backup/feature branches (superseded but unmerged).
- Verify every delegated claim on disk (phase reports are claims): line counts, no placeholder text, files moved.
- TDD strict, source: project instructions; runner: Pest (api). Wrapper docs: structural readback + ci-guards.
- Route: delegated writer for multi-file spec merges/moves (one writer at a time), inline for single small edits.

## Tasks
Route per task: C1-C5, C8 delegated writer (multi-file spec merges / test authoring, mapping triggers fired); C6, C7 inline (single-line status edits).
- [x] C1 archive the 4 complete changes — commits 1383e0a docker-disk-guard, d73dfc6 image-upload-crop-field,
      165af82 stale-interview-reaper, efb332e scoring-audit-jev; 4 skipped MODIFIED reqs of image-upload-crop-field
      merged afterwards as ADDED in 63736fb
- [x] C2 `avatar-template-catalogue` (c09422a, 5.2 live CDN check left open and recorded) + `platform-user-management`
      (2dca9c9, 6.4 E2E left open and recorded; skipped req merged in 63736fb)
- [x] C3 `scoring-role-scoped-indicators` archived 5b71492: checkboxes corrected (1a.2/1a.7/1a.9/1a.10/1b.4/1b.5/1b.8
      unchecked), purge 4.x dropped, one MODIFIED req merged into interview-conversation
- [x] C4 `superadmin-acting-organization-context` archived f7ac023: nothing merged (deltas describe the never-built
      EffectiveOrganization / 409 contract); follow-up section in the archive report
- [x] C5 `pluggable-conversation-llm` archived 1751dd5: Model column dropped, verified items ticked, 6 contradicted
      reqs + HeyGen lifecycle req not merged, P5.12/P5.13/0.3/P5.0/F.6 left open (need live credentials)
- [x] C6 seven proposal-only changes: 5 archived (backoffice-same-origin-api 521cf95, frontend-same-origin-api ea3bce5,
      proctoring-honest-coverage e6ffa7b, potential-competencies-and-authored-questions 01c554e,
      per-project-avatar-template 6e68973); native-duplex-conversation and tavus-single-session-interview kept open
      with a STATUS note
- [x] C7 `db-driven-conversation-prompts` kept open with a STATUS note (rescope list)
- [x] C8 api `BarsIndicatorRoleScopeArchTest` — api branch feature/scoring-bars-role-scope-arch-guard, commit 26b4350
      (139 lines): RED observed (matcher stubbed, 3 fail), GREEN 10/10 (re-run by the parent), mutation proof RED,
      pint + phpstan clean. Assessed: medium, under_budget, no review due
- [ ] C9 publish via Git Flow to `develop` (api PR + wrapper PR), restore submodule pins, close memory

## Follow-ups NOT done (explicit, need a human or a release)
1. `db-driven-conversation-prompts`: rescope + decide + author Italian seed text (see STATUS note in its proposal).
2. Acting-org hardening: 409 on POST /projects, org PATCH, logo store/destroy; Part B ability suppression in
   `UserAbilities`; arch guard on `$user->organization_id` under `app/Http`; reconcile `no_client_selected` vs
   `organization_context_required`. API error-contract change: OpenAPI + SDK regen + release.
3. `pluggable-conversation-llm` live gates: smoke-check, HeyGen (a) secret placement, (b) contexts
   `llm_configuration_id`; then `native-duplex-conversation` can start.
4. `tavus-single-session-interview`: keep/defer decision.
5. Optional scoring cleanups: `roleId: 0` sentinel in `ScoreCompetency`/`PromptBuilder`, `orderBy('id')` tiebreaker,
   loader relocation. Purge of mis-scored evaluations only after checking production data.
6. `scoring-audit-jev` F.9 production activation was gated on legal sign-off; not verified.
7. `platform-user-management` 6.4 E2E (superadmin client-switch fixture); `avatar-template-catalogue` 5.2 live CDN
   URL expiry check.
8. Local api branches `feature/potential-assessment-start`, `backup/potential-start-0d8f24e`,
   `backup/api-pre-recut-236ad04`: superseded by develop (role-less potential start landed differently) but unmerged,
   so kept per the owner rule.

## Acceptance criteria
- `openspec/changes/` lists only intentionally open changes, each with a STATUS note. (met: 3 remain)
- No archived file contains placeholder text; archived folders keep all original artifacts. (met, line/file counts
  re-checked on disk by the parent after each wave)
- Arch test fails on an unscoped `BarsIndicator` query and passes on the current tree. (met)

## Progress
2026-10-08: all local work done and verified; nothing pushed yet. 16 archive/merge commits + 1 api commit + this
document and the status notes.

## Next step
C9: push, open PRs into `develop`, merge on green CI, restore submodule pins.
