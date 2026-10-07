# Delta for M2M Auth

## MODIFIED Requirements

### Requirement: Ability Model

`ApiClient` MUST carry a flat JSONB `abilities` array. Abilities MUST be stored
**lowercase-canonical** and MUST be validated at creation against the allowed base set:
`participants:create`, `participants:read`, `participants:retry`, `evaluations:read`,
`progress:read`, `projects:read`, `sso_link:generate`. Abilities outside this set MUST be rejected with
HTTP 422 at the controller/service layer. The system MUST provide a
`$client->can($ability)` helper that returns `true` if `$ability` is present using
strict `in_array` on the canonical `abilities` array. Abilities MUST be strictly
separate from Spatie human roles (`admin`/`operator`/`viewer`) and BEAI domain roles
(`ICO`/`FLL`/`MLL`/`BUL`/`SRX`). M2M clients MUST NOT have Spatie roles and MUST NOT
interact with the Spatie permission tables. The `CheckAbility` (`ability:{name}`)
middleware MUST sit BEFORE `SubstituteBindings` in the M2M stack to prevent a missing
ability from triggering a resource-existence lookup before the 403 is returned.
`CheckAbility` MUST be inserted into the application middleware priority list in
`bootstrap/app.php` IMMEDIATELY BEFORE `SubstituteBindings` via
`$middleware->prependToPriorityList(SubstituteBindings::class, CheckAbility::class)`,
so that per-route `ability:{name}` is guaranteed to run before route-model binding
regardless of declaration order. **Do NOT use `priority([...])`** — that method REPLACES
the entire default priority list and requires reproducing it in full to preserve all
other ordering guarantees. The `ability` alias MUST also be registered via
`$middleware->alias(['ability' => \App\Http\Middleware\CheckAbility::class])` in the
same `withMiddleware` closure — without it, per-route `ability:{name}` middleware
declarations will fail with "middleware not found" at runtime. `CheckAbility` is applied
PER-ROUTE on individual M2M business routes; `GET /api/m2m/whoami` requires NO ability.
(Previously: the base set did not include `participants:retry`.)

#### Scenario: Ability present — allowed

- GIVEN an `ApiClient` with `abilities = ["participants:read", "projects:read"]`
- WHEN the controller checks `$client->can('participants:read')`
- THEN it returns `true` and the request proceeds

#### Scenario: Ability absent — 403

- GIVEN an `ApiClient` with `abilities = ["participants:read"]` (does NOT have `participants:create`)
- WHEN a route protected by `ability:participants:create` is requested
- THEN the controller checks `$client->can('participants:create')` returns `false`
- AND the response is HTTP 403

#### Scenario: Unknown ability rejected at creation — 422

- GIVEN an admin sends `POST /api/m2m/clients` with `abilities: ["webhooks:send"]`
- WHEN the request is processed
- THEN HTTP 422 is returned
- AND no `ApiClient` record is created

#### Scenario: participants:retry is an accepted ability

- GIVEN an admin sends `POST /api/m2m/clients` with `abilities: ["participants:retry"]`
- WHEN the request is processed
- THEN the client is created with that ability stored lowercase-canonical

## ADDED Requirements

### Requirement: M2M Evaluation Retry Endpoint

`POST /api/m2m/participants/{id}/retry` MUST be reachable only by M2M clients authenticated on
the `api-m2m` guard and holding the `participants:retry` ability, enforced per-route by
`ability:participants:retry` BEFORE route-model binding (a client without the ability gets
HTTP 403 regardless of whether the id exists). The participant MUST be resolved scoped to the
client's own organization; an id belonging to another organization MUST return HTTP 404. The
endpoint MUST be a thin controller over the shared evaluation-retry authorization action
(`participant-sso`: Requirement: Evaluation Retry Authorization Action), so it shares every
refusal guard (409 `retry_already_consumed`, `not_completed`, `test_mode_participant`,
`evaluation_not_pending`, `project_inaccessible`, evaluated in that order), the link lifetime
rule (24 hours only when BEAI emails the retry link, 30 minutes when the link is only returned,
as for a placeholder address or a reusable-link visitor), the candidate email and the response
shape `{status, entry_url, expires_at, email_sent, competencies_reset}`. The request body MAY
carry an optional `reason` (max 500 characters; surrounding whitespace is trimmed and an empty
value is treated as absent), recorded in the interim `participant.retry_authorized` log and in
the `evaluation.retry_authorized` audit row with the client as actor. The audit row's `actor_id`
column is null for an M2M caller (the authenticated principal is an API client, not a user);
the client id travels in the row's payload.

The operation documents HTTP 403 (missing ability) in the exported OpenAPI contract.

This is the INTERNAL `/api/m2m` surface only. A public `/v1` retry endpoint, its SPEC entry,
its `ExposureCatalogue` (`T-EXPOSE-001`) entry and its SDK are explicitly DEFERRED to a
follow-up change; this change MUST NOT add any public or export field.

#### Scenario: Client with the ability authorizes a retry

- GIVEN an `ApiClient` with `participants:retry` and an eligible participant of its organization
- WHEN `POST /api/m2m/participants/{id}/retry` is called
- THEN HTTP 200 is returned with `status`, `entry_url`, `expires_at`, `email_sent` and
  `competencies_reset`
- AND the participant is `in_attesa` with `retry_attempt = true` on its Evaluation
- AND one `evaluation.retry_authorized` audit row names the client in its payload

#### Scenario: Client without the ability is denied before resolution

- GIVEN an `ApiClient` whose abilities do not include `participants:retry`
- WHEN the endpoint is called with an id that belongs to another organization
- THEN HTTP 403 is returned, not 404

#### Scenario: Cross-organization id is not found

- GIVEN an `ApiClient` of Org A with `participants:retry`
- WHEN the endpoint is called with a participant id belonging to Org B
- THEN HTTP 404 is returned

#### Scenario: Refusals surface as 409 with the shared reasons

- GIVEN an `ApiClient` with `participants:retry` and a participant whose Evaluation is `completed`
- WHEN the endpoint is called
- THEN HTTP 409 `reason: "evaluation_not_pending"` is returned

#### Scenario: Test-mode participant is refused

- GIVEN an `ApiClient` with `participants:retry` and a test-mode participant at `completato`
- WHEN the endpoint is called
- THEN HTTP 409 `reason: "test_mode_participant"` is returned

#### Scenario: Racing the backoffice operator

- GIVEN an operator and an M2M client authorize the same eligible participant simultaneously
- WHEN both are processed
- THEN exactly one succeeds and the other gets 409 `retry_already_consumed`

#### Scenario: No public exposure change

- GIVEN the OpenAPI export and the `ExposureCatalogue` after this change
- WHEN the exposure test (`T-EXPOSE-001`) runs
- THEN it passes without a new catalogue entry and no `/v1` retry path exists
