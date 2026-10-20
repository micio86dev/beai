# HR-Avatar extraction — final summary

Branch `feature/extract-avatar-service` in every repository. `main` and `develop` are untouched. Nothing
was deployed anywhere; the Railway files for HR-Avatar are configuration as code and were never applied.
Pushed: the `feature/extract-avatar-service` branches of the wrapper, `api`, `frontend`, `backoffice` and
`hr-avatar` (see "Delivery" at the end). `hr-avatar` is public at https://github.com/micio86dev/hr-avatar and
is the wrapper's fifth submodule.

Inputs: `docs/extraction/PROMPT.md` (mission), `FINDINGS.md` (phase 0), `DESIGN.md` (phase 1), the SDD
changes `openspec/changes/hr-avatar-adapter/` (BEAI side) and `hr-avatar/openspec/changes/hr-avatar-engine/`
(service and SDK).

## What was built

| Piece | Where | What |
|---|---|---|
| HR-Avatar service | `hr-avatar/service` | Laravel 13 API, no back office. Own key space: secret keys `hra_sk_{live,test}_…`, publishable keys `hra_pk_{live,test}_…` (origin allowlist), per-conversation `client_secret` JWT. Accounts, provider and LLM credentials (encrypted, env fallback), avatar configs with provider sync, catalogue and voice preview, conversations with a state machine, client connect / events / end, transcript, inbound provider webhooks (Tavus callbacks, LiveAvatar poller), outbound HMAC-signed webhooks with retries, sweeper, delayed release, lost-job relay. Adapters: Tavus, HeyGen LiveAvatar, Mock. |
| `@hr-avatar/sdk` | `hr-avatar/sdk` | Browser SDK harvested from `frontend/app/providers/*`: Daily (Tavus) and LiveAvatar transports, built-in mock transport, transcript outbox, completion phrases, `connect()` / conversation object. ESM/CJS/IIFE, 5.5 KB gz. |
| BEAI api adapter | `api` | `HrAvatarProvider` session service, selected only by a template pinned to `hr_avatar`, fail-closed pre-flight; `hr_avatar {base_url, publishable_key}` in the start response; nullable `avatar_templates.hr_avatar_config_id`; organization-scoped catalogue proxy; `hr-avatar:export-templates` (dry run by default, `--apply`). |
| backoffice | `backoffice` | `hr_avatar` provider option with an HR-Avatar config picker (listed through the BEAI api; the secret key never reaches a browser). |
| frontend | `frontend` | `HrAvatarProvider` adapter over the vendored SDK (`vendor/hr-avatar-sdk-0.0.0.tgz`), behind `NUXT_PUBLIC_HR_AVATAR_ENABLED` — **off by default**; with the flag off the adapter is never loaded and the provider factory behaves as on `develop`. |
| `@beai/embed` | `embed` | **Unchanged** (owner decision 4: the frontend inside the iframe composes the SDK). |

Organization branding and templates stay in BEAI. BEAI stores only the template ↔ HR-Avatar config association.

## Goal criteria and evidence

Evidence is from the second final verification run of 2026-10-20, after all review fixes (full log: the
session scratchpad `final-verification-2.md`; numbers below are copied from it). HEADs verified: hr-avatar
`6ae74f6`, api `324228d`, frontend `887a002`, backoffice `887b249`.

| # | Criterion | Evidence |
|---|---|---|
| 1 | Service and SDK exist; mechanics harvested from `frontend/app/providers/*`; config, provider integrations, webhooks and API-key logic extracted; independent key system | hr-avatar service: `php artisan test --parallel --processes=4` exit 0, **2917 passed**; SDK: 384 tests exit 0, Playwright smoke 2/2 (Chromium, WebKit). Key system: `hra_sk_`/`hra_pk_`/`client_secret`, no shared secret with BEAI. |
| 2 | `@beai/embed` unchanged | `git -C embed diff --exit-code develop -- .` exit 0 (no diff). |
| 3 | Frontend consumes the SDK behind a flag OFF by default; integrated path untouched and default | `frontend/nuxt.config.ts:174` `hrAvatarEnabled: ''` (off). `git diff develop -- app/providers/tavus.ts app/providers/heygen.ts` empty. Flag-off unit and e2e specs pass. |
| 4 | Full suites exit 0, coverage > 85 % on new code | hr-avatar service: coverage `--min=90` exit 0, **100.0 %**; high-integrity `--min=95` exit 0, **100.0 %**. SDK: lines **100 %**, branches **98.65 %**. api: 10170 tests (10161 passed, 9 skipped) exit 0; coverage `--min=98` exit 0, **98.3 %**. backoffice: 4332 tests exit 0, lines **99.45 %** (the first run had one flaky failure in the untouched develop spec `tests/unit/pages/settings/index.spec.ts`, `tabsListVariants is not a function`; it passed alone and the full re-run passed 4332/4332). frontend: 3843 tests exit 0, lines **98.51 %**; Playwright e2e: see "Frontend e2e" below. Lint, typecheck, pint, PHPStan (0 errors), codegen checks: all exit 0. |
| 5 | Scramble generates valid OpenAPI for both services covering touched endpoints | hr-avatar: fresh export identical to committed `service/openapi.json`, Spectral exit 0. api: fresh `openapi.json` export identical to committed; `openapi.v1.json` (public `/v1`) export identical and `git diff --exit-code develop -- openapi.v1.json` exit 0. Touched internal endpoints are in `openapi.json` (+391 −28 vs develop); backoffice and frontend `codegen:check` exit 0 against it. |
| 6 | English docs for HR-Avatar and the SDK; BEAI docs updated | `hr-avatar/README.md`, `service/README.md`, `sdk/README.md`, `docs/architecture.md`, `docs/api-usage.md`, `docs/sdk-usage.md`, `docs/railway.md`; BEAI `docs/dev-setup.md` (HR-Avatar section), `docs/railway-env-guide.md`, this file. |
| 7 | Railway config as code only, nothing applied | `hr-avatar/service/railway.json`, `railway.worker.json`, `railway.scheduler.json`, `hr-avatar/docs/railway.md`. No Railway CLI/API call was made. |
| 8 | No behaviour change in the default demo path | api `TavusProvider.php`/`HeygenProvider.php` and frontend `tavus.ts`/`heygen.ts` have no diff vs develop; golden `/start` fixtures (`start-tavus.json`, `start-heygen.json`, recorded before any change) pass; selection reaches `hr_avatar` only through a template explicitly pinned to it; the frontend flag is off. Every BEAI test that exists on `develop` passes unedited, except the ones listed under "Existing tests edited". |
| 9 | This summary | — |

### Frontend e2e

Full Playwright suite with the flag unset, run exactly as CI
(`env -u NUXT_PUBLIC_HR_AVATAR_ENABLED node node_modules/.bin/playwright test`, Chromium + WebKit + mobile):
- First run, under load from a parallel verification: exit 1, 413 passed, 3 failed, 3 skipped. The 3 were
  WebKit `page.goto` 30 s timeouts in `tests/e2e/unsupported-gate.spec.ts`, a `develop` spec this branch
  does not touch; that file alone on WebKit with `--retries=0` passed.
- Second run on a quiet machine: **exit 0, 416 passed, 3 skipped (3.0 m)**.
- After all review fixes and the SDK re-vendor (frontend `887a002`): **exit 0, 416 passed, 3 skipped, 0 failed
  (3.0 m)** on the first try. This is the result of record.

### Existing tests edited (all owner-authorized)

- backoffice `tests/unit/avatar-template-form.spec.ts` (+11 −8) and
  `tests/unit/components/organisms/AvatarTemplateForm.spec.ts` (+3 −3): localized error copy (`579b149`).
- api `tests/Arch/C11/AdminTenancySafetyArchTest.php` (+13 −1): `Models` added to the guarded roots and
  the two existing `AvatarTemplate` scope strips allowlisted with a reason (`51839c7`). No assertion removed.
- api `tests/Helpers/PublicApi/ExposureCatalogue.php`: one method added for the new field classification.
- hr-avatar (new repo, rulings 57–64): two live-DNS assertions removed as flaky, two assertions reversed to
  fail-closed, one Origin-refusal test inverted, one probabilistic ciphertext assertion removed.

## Verified automatically vs manually

Automatically (CI-equivalent, run locally): every suite, coverage gate, lint, typecheck, static analysis,
OpenAPI drift and Spectral, golden `/start` fixtures, flag-off bundle and e2e checks, SDK size budget and
SDK Playwright smoke. Provider behaviour was exercised against HTTP fakes and the mock transport only.

Not verified, or manual and pending:
- Local wiring smoke (BEAI → HR-Avatar end to end): **run and passed on 2026-10-20**, fully isolated from
  the demo stack (no `beai_*` container or database touched: BEAI api and frontend ran as host processes
  against a throwaway `pgvector` container, HR-Avatar on its own compose with a throwaway database; all
  removed afterwards). Results:
  - a real Chromium interview (flag on, live-mode participant) went consent → device check → start →
    call screen → end, twice (Exit/suspend and server-side `/end`);
  - BEAI `interview_sessions.provider = hr_avatar` with a `conv_…` reference;
  - HR-Avatar lifecycle `created → connecting → live → ended` (`ended_reason` `client` and `api`), transcript
    ready with 3 utterances after the async reconcile; no errors in either log, `failed_jobs` 0;
  - api restarted without `HR_AVATAR_*`: `422 interview_configuration_invalid` (`provider_key_missing`);
  - frontend flag off with the api on: retryable error screen; backoffice picker lists the `org_<id>`
    config, and a key without `avatar_configs:read` degrades to `provider_unauthorized`;
  - Tavus/HeyGen templates on the same stack fail their own provider validation (422) and create no
    HR-Avatar conversation;
  - `hr-avatar:export-templates`: dry run makes no request; `--apply` creates one config per eligible
    template (`sync_status` `pending` for Tavus, `not_required` for HeyGen), links them, reports
    `dropped_key`, `voice_missing` and `already_linked`; a second `--apply` is idempotent (no duplicate).
    The command exits 1 whenever any row is refused (by design: every refused record is reported), so a
    script calling it must not treat exit 1 as a crash.
  Not covered by the smoke: the SDK's browser mock speaks no lines, so utterances were posted from the
  page with the real publishable key and client secret; the `host.docker.internal` step (everything ran on
  the host); a Tavus config reaching `synced` (no provider credentials). Observed behaviour worth knowing:
  with the frontend flag off and the api on, the api still creates an HR-Avatar conversation that stays
  `created` until HR-Avatar's 900 s expiry (roll back `HR_AVATAR_*` first, as step 9 says); a browser closed
  abruptly leaves the conversation `live` until the sweeper ends it.
- Real Tavus and HeyGen LiveAvatar calls: **never made**.
- Railway configuration: **never applied** (by design).
- Backoffice Playwright e2e against a live stack: not run.

## Run BEAI against HR-Avatar locally

1. **HR-Avatar service** (`hr-avatar/service`):
   ```bash
   cp .env.example .env && php artisan key:generate   # set HRA_JWT_SECRET in .env
   docker compose up -d postgres redis                  # host ports 55432 / 56379 (override HRA_DB_PORT, HRA_REDIS_PORT)
   php artisan migrate && php artisan db:seed --class=LlmModelSeeder
   php artisan hra:bootstrap-account "BEAI local" --mode=live   # prints the account id and a secret key once
   php artisan serve --port=8100
   php artisan queue:work      # second terminal
   php artisan schedule:work   # third terminal (sweeper, LiveAvatar poller, relay)
   ```
2. **Keys.** For BEAI, issue a restricted secret key:
   `php artisan hra:issue-key <account_id> --mode=live --scopes=conversations:write,avatar_configs:read,avatar_configs:write`.
   Create a publishable key with `POST /v1/api-keys` (type `publishable`, `allowed_origins: ["http://localhost:3000"]`)
   using the bootstrap key. See `hr-avatar/docs/api-usage.md`.
3. **A config.** `POST /v1/avatar-configs` with the `mock` provider and `external_ref: "org_<beai organization id>"`
   (the backoffice picker lists only configs whose `external_ref` matches the organization).
4. **Reachability.** `HR_AVATAR_BASE_URL` is used by the BEAI api server side (inside its container) and is
   also returned to the browser. `localhost` works for the browser only. Use
   `http://host.docker.internal:8100` and make that name resolve on the host too: Docker Desktop's
   "Add the *.docker.internal names to the host's /etc/hosts file" option, or the line
   `127.0.0.1 host.docker.internal` in `/etc/hosts` (not present on this machine today).
5. **BEAI configuration.** `api/.env`: `HR_AVATAR_BASE_URL`, `HR_AVATAR_SECRET_KEY`, `HR_AVATAR_PUBLISHABLE_KEY`.
   `frontend`: `NUXT_PUBLIC_HR_AVATAR_ENABLED=true`. Rebuild/recreate the BEAI api and frontend containers
   (they are built images) and run the new migration (`php artisan migrate`).
6. **Backoffice.** Create an avatar template with provider `hr_avatar`, pick the config, activate it and pin
   it on a project. Optionally migrate existing templates: `php artisan hr-avatar:export-templates`
   (dry run, prints the mapping and dropped keys) then `--apply`.
7. **Interview.** Use a **live-mode** participant: test-mode participants are forced to BEAI's own mock
   provider and never reach HR-Avatar.
8. **Verify.** BEAI `interview_sessions.provider = hr_avatar` with a `conv_…` reference; HR-Avatar
   `GET /v1/conversations/{id}` and `/transcript` (with a key holding read scopes). Negative check: unset
   `HR_AVATAR_*` and the pinned template answers 422 `interview_configuration_invalid`.
9. **Roll back.** Unset `HR_AVATAR_*`, then the frontend flag. Templates not pinned to `hr_avatar` never
   touched HR-Avatar.

## Reviews

- Native reviews (receipt-driven, owner consent per candidate), all approved and acknowledged:
  - api: A–M, A12, the tail `51839c7..8bc022a`, and every later fix range (`6a4f300..324228d`).
  - backoffice: BO1–BO6, the B4 tail and both later contract syncs.
  - frontend: the whole branch, then every later range up to `887a002`.
  - hr-avatar: **every commit of the repository** — the security slices H1–H6, H8, H10, H12; the full-coverage
    pass rv02..rv28 (all service slices and every SDK commit); the scaffold `c8788a2` reviewed without its
    generated `composer.lock` (10,098 lines) through a tree-identical two-commit split in a detached worktree
    (the only bytes never reviewed); and all fix units SF-1..SF-41 (slices SF1..SF6, sf7..sf14).
- Every review finding at CRITICAL or WARNING level was fixed with a failing-first test, shown already fixed
  or not reproducible (pinned by a test), or accepted with a written ruling (`hr-avatar` rulings 57–96 in
  `reconciliation.md`; BEAI dispositions in `openspec/changes/hr-avatar-adapter/apply-progress*.md`).
  Two late reviewer CRITICALs did not reproduce on the installed versions and are pinned by tests:
  `ReconcileTranscript::fail()` (the Foundation `Queueable` trait includes `InteractsWithQueue`) and the
  `LimitWebhookBody` body re-read (the body is now handed back explicitly anyway).
- Accepted last warnings (no further change): the frontend mic flush gives up a hung adapter call after 5 s
  without cancelling it (a late settle is ignored); the HR-Avatar config-sync double-failure path logs the
  push failure under the "could not be queued" message.
- The hr-avatar lineages H7 (`863d32d`), H9 (`386b7a4`) and H11 (`b33c6ce`) ended `correction_required`.
  Correcting historical commits is not possible; their CRITICAL findings (stuck webhook deliveries, DNS pin
  fail-open, stuck `connecting`, unprocessed provider events) are fixed at HEAD (`d9e92d8`, `7251fe2`,
  `81d3146`) and those fixes were reviewed and approved (SF1–SF3). With the owner's authorization
  (2026-10-20) the three lineages were closed with `gentle-ai review abandon --reason operator_disposition`
  (records committed, no open lineage left) and their worktrees removed.
- No review lineage of this extraction is open in any repository, and every review worktree is removed.
  The api, frontend and backoffice review stores still hold older lineages dated 2026-09-15 to 2026-10-13,
  from earlier features unrelated to this extraction; they were left untouched.
- Guardian Angel ran on every commit; `--no-verify` was never used.

## Open items and owner decisions

Before enabling `hr_avatar` outside local:
1. GDPR retention sign-off covering HR-Avatar data (`conversations.metadata`, transcripts, `provider_session_ref`, webhook payloads). No purge exists yet.
2. SDK non-fatal `error` events → BEAI retryable error screen mapping.
3. LiveAvatar assumptions: transcript cursor semantics (`next_timestamp`), polling latency for end detection.
4. Real provider calls and the local wiring smoke above.
5. Production topology: one `HR_AVATAR_BASE_URL` serves both server-side calls and the browser. On Railway
   a private-network URL for the api and a public URL for the browser would need a second variable.

Operations:
6. Railway config-as-code is deprecated (works until 2026-12-01); move to IaC before then.
7. `HRA_TRUSTED_PROXIES=*` on Railway; healthcheck stays liveness (`/v1/health`).
8. hr-avatar is now public (https://github.com/micio86dev/hr-avatar) and the fifth submodule. Only its
   `feature/extract-avatar-service` branch is published; its `develop` and `main` (still at the init commit)
   are not, so `task submodules:update` cannot advance it until `develop` is published. The api parity
   test still skips in the api's own CI, which checks out `api` alone without its `hr-avatar` sibling. The
   vendored SDK tarball in `frontend/vendor/` must be rebuilt (with `bun.lock` and the version-catalog row)
   whenever the SDK changes.

HR-Avatar limits chosen during the fixes (adjustable):
9. A JSON callback body is decoded by Laravel before middleware, so its memory is bounded by nginx
   `client_max_body_size 1m`, not by the 256 KB middleware limit (ruling 74).
10. The relay re-queues a lost provider receipt for 24 h at most; a conversation holds at most 10,000 events.
11. The DNS check at webhook-endpoint creation has no timeout; endpoint creation is not idempotent.
12. Guard files under `service/tests/Arch` are exempt from the vocabulary scan (CLAUDE.md exemption to confirm).
12a. `DB_SSLMODE` now defaults to `require` outside `local`/`testing`; confirm Railway's PostgreSQL offers TLS
     (otherwise set `DB_SSLMODE=prefer` explicitly). Redis and PostgreSQL connect/read timeouts are bounded.
12b. Paged provider catalogue and voice lists stop at 20 pages or 30 s; a cut list is returned partial,
     cached 5 minutes and logged, but no response field says so (adding one is an `openapi.json` change).
12c. On a synchronous queue (local development only), a provider failure during config create/update now
     answers the job's error instead of a 2xx.

BEAI side:
13. No `name_taken` code for localized name refusals. (The template 422 refusals, including "provider cannot
    be changed", are now localized en/it — `0ba2c71`.)
13a. The platform template DELETE 409 stays documented as the flat develop shape, because the develop test
     `PlatformAvatarTemplateSpecTest` pins it; the organization DELETE 409 is the discriminated shape.
14. Export: dropped keys are reported, not mapped; ambiguous timeouts are reported, not retried; LLM binding and persona are not exported.
15. Latent: `saveQuietly()` on `AvatarTemplate` skips the LLM-binding check (no caller does it today).
16. Found by the smoke, unrelated to the extraction and pre-existing on `develop`: `php artisan db:seed` on a
    fresh database failed (`organizations.public_id` NOT NULL) because `DatabaseSeeder` muted model events.
    Fixed on its own branch `feature/fix-database-seeder-public-id` (api `042bd60`, pushed, reviewed and
    approved, full api suite and PHPStan green), to be merged into `develop` separately. The review notes
    that every model event now fires during seeding; the full-seed test passes.

## Commits

**api** (28): `8f0a10a` `3009330` `4c3b7a5` `a35a91d` `de0ca87` `131c33e` `9e18a96` `0b1b773` `8ec96fa`
`f06b3b2` `b0b0beb` `7f565a2` `fb87863` `e99f5fb` `06ac648` `bad81c5` `8d44cc8` `24c546b` `dfebbfa`
`9fa94c4` `0e6f5a5` `adf9b79` `101a016` `80271a7` `2bd711f` `645226a` `51839c7` `8bc022a` `6a4f300`
`bde7a28` `0ba2c71` `54d4b3d` `324228d`
(`git log --oneline develop..feature/extract-avatar-service` in `api` for subjects).

**backoffice** (13): `99d28e9` `579b149` `06eea64` `b11edae` `80c0332` `f9bf141` `df073cb` `1dae127`
`fcf738d` `a0b646d` `b74b1cf` `2aa7847` `887b249`.

**frontend** (18): `0168bab` `5bf62fa` `2871e94` `86a6128` `3b1c85e` `68292db` `28c03f6` `25b8789` `6281241`
`6cc96c1` `8b6862b` `9f6b4f7` `11a37c3` `3d4cb3a` `b58f992` `8a7ae6b` `65b5fe1` (SDK re-vendored at hr-avatar
`6104726`) `887a002`.

**wrapper**: `dd79d38` (findings, design), `f161e48` (adapter SDD), `72a0eb4` (version catalog), plus the
close-out commit carrying this file, the adapter apply-progress and the docs updates.

**hr-avatar** (112, HEAD `6ae74f6`): repository and SDD (5), SDK (9), service slices 1–40 (44),
security and review fix units SF-1..SF-41 (54). Full list: `git -C hr-avatar log --oneline`; per-slice mapping in
`hr-avatar/openspec/changes/hr-avatar-engine/tasks.md` and `apply-progress.md`, rulings in `reconciliation.md`.

## Delivery

Pushed on 2026-10-20 at the owner's request ("push only to the feature branch, never deploy"), each
verified with `git ls-remote` against the local HEAD:

| Repo | Branch | Commit |
|---|---|---|
| api (`micio86dev/backend`) | `feature/extract-avatar-service` | `324228d` (first push `8bc022a`) |
| frontend (`micio86dev/frontend`) | `feature/extract-avatar-service` | `887a002` (first push `6281241`) |
| backoffice (`micio86dev/backoffice`) | `feature/extract-avatar-service` | `887b249` (first push `b74b1cf`) |
| wrapper | `feature/extract-avatar-service` | the commit that pins the three above |
| hr-avatar (`micio86dev/hr-avatar`, public, created 2026-10-20 at the owner's request after a gitleaks scan of the whole branch history: 37 hits, all fake test/doc fixtures) | `feature/extract-avatar-service` (the only branch) | `6ae74f6` |

CI does not run on `feature/*` pushes in the wrapper, `api`, `frontend` or `backoffice` (workflows trigger on
`develop`, `main`, `release/**`, `hotfix/**`), and Railway deploys only from `main`. In `hr-avatar` the
`service` and `sdk` workflows DO run on this branch push: they are test-only (no deploy step), and their
result is recorded below. No pull request was opened.

Observed after the first push of the new `hr-avatar` repository: GitHub registered 0 workflows and started no
run (Actions is enabled; both workflow files are on the branch). The first later push will register them.
The same gates were run locally on `6ae74f6` (see criteria 1, 4 and 5), all exit 0.
