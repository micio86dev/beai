# Tasks: Acting-Organization 409 Contract

Strict TDD (Pest, Vitest). One commit per concern. Mechanism: `TenantResolver::getOrgId()` + `org.context`.
Review heuristic: about 400 authored changed lines per commit. Tick a box only for an observed outcome.

## 1. Routes: 409 organization_context_required (api)

- [x] 1.1 RED: tests for `POST /api/projects`, `PATCH /api/organization`, `POST` and `DELETE /api/organization/logo`
      with a real superadmin (`organization_id = null`, `is_superadmin = true`) and no acting organization expect 409
      `organization_context_required` and no write; observe them fail with the current 422/404/403.
- [x] 1.2 GREEN pin: `GET /api/organization` with no acting organization stays `200 {"data": null}` (passes before and after).
- [x] 1.3 RED: with an acting organization the same routes are served; org A's admin can never read or write org B.
- [x] 1.4 GREEN: add `org.context` to the routes (split `apiResource` so only `store` carries it); keep route names.
- [x] 1.5 Mutation proof: remove the middleware from one route, observe its test fail, restore.
- [x] 1.6 Rewrite the stale route and controller docblocks that say the organization resolves from the user column.

## 2. M2M credential controller reconciliation (api)

- [x] 2.1 RED: `POST` and `GET /api/m2m/clients` with no acting organization expect 409 `organization_context_required`
      (`message`), no `no_client_selected`, no row; update the existing no-client tests that pinned the old shape.
- [x] 2.2 GREEN: `org.context` on the two routes; remove the bespoke guards from `ApiClientController`.
- [x] 2.3 Mutation proof: remove the middleware from `POST /m2m/clients`, observe RED, restore.

## 3. Ability suppression (api)

- [x] 3.1 RED: `/auth/me` for a superadmin with no acting organization expects the four groups all `false` and the
      platform groups unchanged; with an acting organization expects the admin answers; org-bound roles unchanged.
- [x] 3.2 GREEN: `UserAbilities::for()` derives the effective organization (own column, then resolver) and suppresses
      `organization`, `apiClients`, `projects`, `participants` when there is none.
- [x] 3.3 Backoffice: confirm no client change is needed (Vitest/typecheck); change it only if a test proves otherwise.
      Existing Vitest coverage of the admin-backoffice scenarios: `backoffice/tests/unit/utils/nav-visibility.spec.ts`
      and `nav-items.spec.ts` (sidebar scope for a superadmin with and without a client) and
      `backoffice/tests/unit/pages/settings/index.spec.ts` (Settings rail: platform sections kept, API keys section
      hidden with no client and shown when acting as a client).

## 4. Arch guard (api)

- [x] 4.1 RED: matcher self-test (positive and negative fixtures) and the tree scan with a temporary violation in
      `app/Http`; observe the failure naming file and line, then remove the violation.
- [x] 4.2 GREEN: `tests/Arch/Tenancy` guard with the justified occurrence-budget allowlist; passes on the tree.

## 5. Contracts

- [x] 5.1 Re-export `openapi.json` on Postgres; confirm only the intended operations changed.
- [x] 5.2 Confirm `openapi.v1.json` is byte-identical after a fresh export.
- [x] 5.3 Sync `frontend/openapi.json` and `backoffice/openapi.json`, regenerate both `types/api.ts`;
      `codegen:check` and `scripts/verify-openapi-parity.sh` pass.

## 6. Verification

- [x] 6.1 Touched and new Pest files, `tests/Arch`, `pint --test`, `phpstan analyse`.
- [x] 6.2 Full api Pest suite once (duration and totals recorded).
- [x] 6.3 Backoffice and frontend (touched by the 5.3 sync): `codegen:check`, lint, unit tests.

## Observed results (2026-10-08)

- api `feature/acting-org-409-contract`: commits `299f559` (routes), `cb33968` (abilities), `e6289f1` (arch guard),
  `b733222` (openapi.json), `5fb4097` (stale test), `d86f683` (PHPStan type fix).
- Wrapper-side merge and syncs: api merge `e0c30d3` (PR #143); backoffice sync commit `22c0f1e` and frontend sync
  commit `891652f` (both "chore(api): sync openapi.json and the typed client with the 409
  organization_context_required contract").
- Full api suite (`php artisan test --parallel`): 8398 tests, 8386 passed, 12 skipped, 205 s; `phpstan analyse`: 0 errors;
  `pint --test`: passed; fresh Postgres export of `openapi.json` and `openapi.v1.json`: no diff.
- backoffice and frontend: `codegen:check` OK, lint 0 errors, unit suites 3647 and 2455 passed;
  `scripts/verify-openapi-parity.sh` OK.
- Deviation from the archived design: four groups suppressed, not seven (see the proposal table).
