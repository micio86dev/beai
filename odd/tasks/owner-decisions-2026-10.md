# Owner decisions applied 2026-10-13

Objective: apply the six recommendations the owner accepted ("applica le tue raccomandazioni")
for the open product and security findings left after the coverage push.

Mode: strict TDD (RED observed before GREEN), runner Pest (api) and Vitest (backoffice).
Source of the mode: project configuration. Delivery: feature branches, native review with
the owner's consent per candidate, Git Flow release, Railway deploy, production check.

## Tasks

- [ ] T1 `ComposedOpening` refuses a whitespace-only opening and closing text (api).
- [ ] T2 `RejectStaleCredentials` fails closed: an unreadable token payload or a missing
      numeric `iat` is treated as stale (api). Investigate every guard using it first.
- [ ] T3 `reports/index.vue` keeps the filter bar and offers a retry control in the error state (backoffice).
- [ ] T4 `CompetencyForm`, `RoleForm`, `BarsIndicatorForm` drop the generic save-error banner
      when a 422 field error is already mapped, like the other forms (backoffice).
- [ ] T5 Remove the dead branches: platform-template refusal in `SetTavusMaxCallDurationCommand`
      and the `_blank` branch of `ValidatesLocaleMaps` (api).
- [ ] T6 Public API spec: summaries for operations that have none, `externalId` bound on the create
      field, placeholder `basePath` in the SDK. The `email` query filter is a privacy design question
      and is reported, not changed (api, wrapper SDK generator).

## Routes

Two delegated writers in parallel (api: T1, T2, T5, T6; backoffice: T3, T4) because each
repository has its own worktree and the work is 2+ non-trivial files per writer.

## Evidence

Filled in as each task closes.
