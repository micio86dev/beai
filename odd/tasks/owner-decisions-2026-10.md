# Owner decisions applied 2026-10-13

Objective: apply the six recommendations the owner accepted ("applica le tue raccomandazioni")
for the open product and security findings left after the coverage push.

Mode: strict TDD (RED observed before GREEN), runner Pest (api) and Vitest (backoffice).
Source of the mode: project configuration. Delivery: feature branches, native review with
the owner's consent per candidate, Git Flow release, Railway deploy, production check.

## Tasks

- [x] T1 `ComposedOpening` refuses a whitespace-only opening and closing text (api).
- [x] T2 `RejectStaleCredentials` fails closed: an unreadable token payload or a missing
      numeric `iat` is treated as stale (api). Investigate every guard using it first.
- [x] T3 `reports/index.vue` keeps the filter bar and offers a retry control in the error state (backoffice).
- [x] T4 `CompetencyForm`, `RoleForm`, `BarsIndicatorForm` drop the generic save-error banner
      when a 422 field error is already mapped, like the other forms (backoffice).
- [x] T5 Remove the dead branches: platform-template refusal in `SetTavusMaxCallDurationCommand`
      and the `_blank` branch of `ValidatesLocaleMaps` (api).
- [x] T6 Public API spec: summaries for operations that have none, `externalId` bound on the create
      field, placeholder `basePath` in the SDK. The `email` query filter is a privacy design question
      and is reported, not changed (api, wrapper SDK generator).

## Routes

Two delegated writers in parallel (api: T1, T2, T5, T6; backoffice: T3, T4) because each
repository has its own worktree and the work is 2+ non-trivial files per writer.

## Evidence

All six tasks closed 2026-10-13 and released: api v0.72.7, frontend v0.26.10, backoffice v0.51.10, wrapper v0.55.9.

- T1: api 184ce93, hardened by a945d2c (Unicode whitespace) and 9049125 (NUL-only); tests in ComposedOpeningTest.
- T2: api 2c9b3cc, warning log c6b02e5, log failure never turns the 401 into a 500 (9049125); RejectStaleCredentialsFailClosedTest.
- T3: backoffice 3419ea7 + 40ec0fe (retry in-flight guard, summary without data); e2e reports-index.
- T4: backoffice ab3bf4f + 40ec0fe (BarsIndicatorForm edit-mode errors), 88ed109 restores an assertion.
- T5: api 2b5bfcc, 2f6ecf7 (explicit null-organization refusal), 32089ce, 25c9099 + 98ccf07 (whitespace-only locale value is a 422 with exact keys).
- T6: api d82b1eb (all /v1 operations documented, external_id bound, PUBLIC_API_SPEC_SERVER_URL knob); hotfix d6a8ce3 (interview project optional); SDKs regenerated in wrapper v0.55.9.

Checks observed: api 9411 tests at 98.2 percent, pint and phpstan clean; backoffice 4046 tests at 99.45/95.47/96.37 with lint and typecheck at 0; native review approved on every commit (advisories remain, finding text is not shown by the tool); production: api, worker, scheduler and backoffice deployments SUCCESS, health 200.

Open owner items: email query filter on GET /v1/interviews (privacy), ExposureCatalogue has no Export block, real public URL for the spec server, by_status annotation in EvaluationIndexController.
