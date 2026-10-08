# Tasks: Acting-Organization 409 Contract

Strict TDD (Pest, Vitest). One commit per concern. Mechanism: `TenantResolver::getOrgId()` + `org.context`.
Review heuristic: about 400 authored changed lines per commit. Tick a box only for an observed outcome.

## 1. Routes: 409 organization_context_required (api)

- [ ] 1.1 RED: tests for `POST /api/projects`, `PATCH /api/organization`, `POST` and `DELETE /api/organization/logo`
      with a real superadmin (`organization_id = null`, `is_superadmin = true`) and no acting organization expect 409
      `organization_context_required` and no write; observe them fail with the current 422/404/403.
- [ ] 1.2 RED: `GET /api/organization` with no acting organization stays `200 {"data": null}` (pin test, passes today).
- [ ] 1.3 RED: with an acting organization the same routes are served; org A's admin can never read or write org B.
- [ ] 1.4 GREEN: add `org.context` to the routes (split `apiResource` so only `store` carries it); keep route names.
- [ ] 1.5 Mutation proof: remove the middleware from one route, observe its test fail, restore.
- [ ] 1.6 Rewrite the stale route and controller docblocks that say the organization resolves from the user column.

## 2. M2M credential controller reconciliation (api)

- [ ] 2.1 RED: `POST` and `GET /api/m2m/clients` with no acting organization expect 409 `organization_context_required`
      (`message`), no `no_client_selected`, no row; update the existing no-client tests that pinned the old shape.
- [ ] 2.2 GREEN: `org.context` on the two routes; remove the bespoke guards from `ApiClientController`.
- [ ] 2.3 Mutation proof: remove the middleware from `POST /m2m/clients`, observe RED, restore.

## 3. Ability suppression (api)

- [ ] 3.1 RED: `/auth/me` for a superadmin with no acting organization expects the four groups all `false` and the
      platform groups unchanged; with an acting organization expects the admin answers; org-bound roles unchanged.
- [ ] 3.2 GREEN: `UserAbilities::for()` derives the effective organization (own column, then resolver) and suppresses
      `organization`, `apiClients`, `projects`, `participants` when there is none.
- [ ] 3.3 Backoffice: confirm no client change is needed (Vitest/typecheck); change it only if a test proves otherwise.

## 4. Arch guard (api)

- [ ] 4.1 RED: matcher self-test (positive and negative fixtures) and the tree scan with a temporary violation in
      `app/Http`; observe the failure naming file and line, then remove the violation.
- [ ] 4.2 GREEN: `tests/Arch/Tenancy` guard with the justified occurrence-budget allowlist; passes on the tree.

## 5. Contracts

- [ ] 5.1 Re-export `openapi.json` on Postgres; confirm only the intended operations changed.
- [ ] 5.2 Confirm `openapi.v1.json` is byte-identical after a fresh export.
- [ ] 5.3 Sync `frontend/openapi.json` and `backoffice/openapi.json`, regenerate both `types/api.ts`;
      `codegen:check` and `scripts/verify-openapi-parity.sh` pass.

## 6. Verification

- [ ] 6.1 Touched and new Pest files, `tests/Arch`, `pint --test`, `phpstan analyse`.
- [ ] 6.2 Full api Pest suite once (duration and totals recorded).
- [ ] 6.3 Backoffice and frontend (only if touched): `codegen:check`, lint, unit tests.
