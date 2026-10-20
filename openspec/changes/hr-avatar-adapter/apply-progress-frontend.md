# Apply progress: frontend (F1, F2a, F2b, F3)

> Mode: Strict TDD. Store: hybrid (this file + Engram `sdd/hr-avatar-adapter/apply-progress`). Repo `frontend`, branch
> `feature/extract-avatar-service` (parent `e85f59b` = develop). Local commits only, no push, no PR. The wrapper
> `docs/version-catalog.md` row is written but NOT committed (orchestrator).

## Batch 3 (frontend): F1, F2a, F2b, F3 - DONE (tasks 10.1-13.4); 10.8a (wrapper commit) and 13.5 (full Playwright) PARTIAL

### Commits (in order)

| Unit | SHA | Message | Authored lines (generated excluded) |
|---|---|---|---|
| F1 | `0168bab` | `feat(frontend): vendor the HR-Avatar SDK and map the hr_avatar start response` | 240 (Dockerfile 4, session 9, factory 17, types 8, nuxt.config 3, package.json 1, spec 198). Excluded: `bun.lock` 3, `openapi.json` 15, `types/api.ts` 4, tarball |
| F2a | `5bf62fa` | `feat(frontend): add HrAvatarProvider adapter core` | 673 = 190 production + 421 spec + 62 fake-SDK fixture. Over 400: see "Size" |
| F2b | `2871e94` | `feat(frontend): complete hr_avatar interviews on the end and final phrases` | 381 = 74 production + 307 spec |
| F3 | `86a6128` | `feat(frontend): gate the hr_avatar provider behind a default-off runtime flag` | 586 = 71 production + 515 tests (282 factory + 160 connect-retry + 73 Playwright). Over 400: see "Size" |

Size: F2a (673) and F3 (586) exceed the ~400 budget. In both, production code is 190 and 71 lines; the rest is the test plan the tasks
prescribe (about 35 adapter scenarios; 22 factory scenarios plus the retry and Playwright specs). No cohesive split exists (a test
file without the code it proves is not a work unit), nothing was trimmed. `size:exception` recommended for F2a and F3.

### TDD Cycle Evidence

| Unit / task | RED (observed) | GREEN | REFACTOR |
|---|---|---|---|
| F1 10.5-10.6 | `hr-avatar-start-config.spec.ts`: 1 failed (the `hrAvatar` mapping, `toEqual` missing the key), 5 passed (characterization of the unchanged invariants: key absent for heygen/tavus, no `live_conversation_id`, valid body); exit 1 | 6/6 | `factory.ts` needed a compile-time change as soon as `ProviderName` gained `hr_avatar` (the `never` binding): the throw moved after the `switch` with the same text, and the `hr_avatar` case `break`s into it (behaviour identical to before) |
| F2a 11.1-11.2 | `hr-avatar-provider.spec.ts`: suite failed to load (`~/app/providers/hr-avatar` missing), 0 tests; exit 1 | 35/35 after fixing two real defects found by the tests: (1) `import.meta.client` is undefined in Vitest (the `define` in `vitest.config.ts` is not applied to it), so a `!import.meta.client` guard in the default loader threw in tests; replaced by `if (import.meta.server)`; (2) the package entry exports `HrAvatar.connect`, not a top-level `connect`, found by `bun run typecheck` against the real `.d.ts`, so the adapter, the fake SDK and the `doMock` use `HrAvatar.connect` | gga note (stale deferred `stopped` after a restart) closed in F2b |
| F2b 12.1-12.2 | `hr-avatar-provider-completion.spec.ts`: 20 failed, 4 passed (incidental); exit 1 | 24/24 (one test bug fixed: it called a `silent()` resolver that no SDK wait had registered). Mutations observed failing: removing the stale-generation check (1 test), making `stopped` synchronous (3 tests) | none |
| F3 13.1, 13.1a, 13.2 | `hr-avatar-factory.spec.ts` + `hr-avatar-connect-retry.spec.ts`: 10 failed (the 9 flag-on / deferred-handle cases and one that asserted `stop` on a wrapped provider, a test bug fixed by asserting the original), 15 passed (flag-off characterization and the existing retry path); exit 1 | 25/25, then 26/26 with one extra case for a subscription made after the load (coverage of `on()`) | none |
| F3 13.3a | New Playwright spec passes with the arm as implemented (chromium and webkit). Mutation: a static `import { HrAvatarProvider }` in `factory.ts` returned from the arm made both projects FAIL with `scripts carrying "forwardTranscript"` (3 scripts, e.g. `/_nuxt/DpPYWfTt.js`); reverted, `git diff` of `factory.ts` shows only the 13.2 change | pass | none |

### Work Unit Evidence

| Unit | Focused test command and result | Runtime harness | Rollback boundary |
|---|---|---|---|
| F1 | `bun run test:unit tests/unit/hr-avatar-start-config.spec.ts tests/unit/interview-provider-types.spec.ts tests/unit/provider-factory.spec.ts tests/unit/provider-anonymity.spec.ts` exit 0, 4 files, 44 tests | Bare clone (`git clone` of the committed `frontend` into the scratchpad, no sibling repo): `bun install --frozen-lockfile` exit 0 (`+ @hr-avatar/sdk@./vendor/hr-avatar-sdk-0.0.0.tgz`, 1093 packages) and `bun run build` exit 0 ("Build complete") | `package.json`, `bun.lock`, `vendor/`, `Dockerfile`, `nuxt.config.ts`, `openapi.json`, `types/api.ts`, the `useInterviewSession.ts` hunk, the `ProviderName` / `StartConfig` hunks, the `factory.ts` rearrangement, the spec, and the wrapper catalog row |
| F2a | `bun run test:unit tests/unit/hr-avatar-provider.spec.ts` exit 0, 35 tests | Fake SDK through the injected `sdkLoader`, plus the default loader through `vi.doMock('@hr-avatar/sdk')` (lazy import observed) | `app/providers/hr-avatar.ts`, its spec and `tests/unit/fixtures/hr-avatar-fake-sdk.ts`; unreferenced until F3 |
| F2b | `bun run test:unit tests/unit/hr-avatar-provider-completion.spec.ts tests/unit/hr-avatar-provider.spec.ts` exit 0, 59 tests | Fake SDK emitting transcript, state and `ended` events under fake timers | the completion section of `hr-avatar.ts` and the completion spec |
| F3 | `bun run test:unit tests/unit/hr-avatar-factory.spec.ts tests/unit/hr-avatar-connect-retry.spec.ts tests/unit/provider-factory.spec.ts tests/unit/provider-anonymity.spec.ts tests/unit/interview-provider-types.spec.ts` exit 0, 5 files, 63 tests; `bun run test:e2e tests/e2e/interview-default-provider-path.spec.ts --project=chromium --project=webkit` exit 0, 2 passed | `bun run build` exit 0, then the SSR/client bundle checks below, and Playwright against the production build with the flag unset | `factory.ts` hunk, `hr-avatar-factory.spec.ts`, `hr-avatar-connect-retry.spec.ts`, the Playwright spec; adapter and SDK become unreachable |

### Verification results (run directly, exit codes read from the shell)

| After | Full `bun run test:unit` | Coverage (`bun run test:unit:coverage`) | `bun run lint` | `bun run typecheck` |
|---|---|---|---|---|
| baseline (before F1) | exit 0, 143 files, 3713 tests | not run | - | - |
| F1 | exit 0, 144 files, 3719 tests | exit 0; all files 98.44 / 94.2 / 96.72 / 98.44 (stmts/branch/funcs/lines) | exit 0 | exit 0 (after the `factory.ts` change) |
| F2a | exit 0, 145 files, 3754 tests | exit 0; all files 98.47 / 94.32 / 96.79; `hr-avatar.ts` 100 / 100 / 100 / 100 | exit 0 | exit 0 |
| F2b | exit 0, 146 files, 3778 tests | exit 0; all files 98.47 / 94.36 / 96.81; `hr-avatar.ts` 100 across | exit 0 | exit 0 |
| F3 | exit 0, 148 files, 3804 tests | exit 0; all files 98.49 / 94.44 / 96.85 / 98.49 (thresholds 98 / 93 / 96); `factory.ts` 100 stmts, 98.24 branch, 89.28 funcs, line 272 is the pre-existing `window` guard of the E2E mock hook | exit 0 | exit 0 |

All four commits passed gga (`STATUS: PASSED`); none used `--no-verify`.

FULL Playwright (`bun run test:e2e`, task 13.5): not a clean exit 0 on this host, see "Full Playwright" below.

### Bundle checks (task 13.3)

- `bun run build` exit 0 (twice: once on the unmutated tree, once after reverting the mutation check).
- `rg -l '@hr-avatar/sdk' .output/server` matches ONE file, `.output/server/chunks/build/client.precomputed.mjs`: the CLIENT chunk
  manifest the server keeps for preload hints (it lists `dynamicImports` of the interview chunk and equally lists
  `@heygen/liveavatar-web-sdk` and `@mediapipe/tasks-vision`). No server chunk imports the SDK or the adapter:
  `rg -l '@hr-avatar/sdk' .output/server --glob '!**/client.precomputed.mjs'` prints nothing (exit 1), and
  `rg -l 'forwardTranscript|completionPhrases|HrAvatarProvider' .output/server` prints nothing. In the server build the deferred
  handle's `start()` compiles to a bare `throw` (dead-code eliminated; read from `InterviewSession-*.mjs`).
- On the client the adapter and the SDK are two separate async chunks (`.output/public/_nuxt/VWhylEjh.js`, `JigbQHJD.js`), the only
  files containing `forwardTranscript` / `completionPhrases`. The Playwright spec proves the default interview page fetches neither.

### Default-path invariance evidence

- No existing test file edited: `git diff --name-status develop...HEAD -- tests` lists only `A` (7 files). The existing
  `interview-provider-types.spec.ts`, `provider-factory.spec.ts`, `provider-anonymity.spec.ts` ran green and unedited at F1, F2a, F2b and F3.
- Flag read only inside the `hr_avatar` arm: `hr-avatar-factory.spec.ts` asserts `useRuntimeConfig` is not called for `heygen`, `tavus`
  or `mock`, with the flag true or false. Unknown-provider text identical (asserted verbatim for `hr_avatar` off and for another name).
- Flag off values tested: `undefined`, `''`, `1`, `'1'`, `'yes'`, `false`, `'false'`; adapter module and SDK `vi.doMock` factories never
  evaluated. On: `true` and `'true'` return synchronously with neither evaluated.
- Playwright (chromium + webkit), flag unset: the call stage renders and no fetched script contains the adapter markers; the same spec
  fails when `factory.ts` imports the adapter statically (mutation, reverted, not committed).
- `nuxt.config.ts` adds one default-empty `public.hrAvatarEnabled`; the Docker image gains `COPY vendor ./vendor` only. The running
  `beai_*` containers were not touched, rebuilt or restarted (no Docker command was run).

### Dependency (task 10.2, design open question 3)

- Produced without any git operation in `hr-avatar`: `bun install --frozen-lockfile` (exit 0, 212 packages), `bun run build` (exit 0),
  `bun pm pack --destination frontend/vendor` (exit 0) giving `vendor/hr-avatar-sdk-0.0.0.tgz` (11.8 KB, 12 files, shasum
  `085de31bc72ea38c8327c5e50ad182f9fc67785a`, integrity `sha512-E7gu5gsHHR7GcITi4cGsaOB1wNVzZu1yiwQekm04yPEaHYGJWqLtX3SrsvcPE0tWK2TwcTFdvSSeVzWfY8UW5Q==`).
- SDK version is `0.0.0` and the package is `private: true`; `bun pm pack` accepted both. The tarball holds `dist/` only.
- `package.json` carries `"@hr-avatar/sdk": "file:./vendor/hr-avatar-sdk-0.0.0.tgz"`. Bun normalises the entry in `bun.lock` to
  `./vendor/hr-avatar-sdk-0.0.0.tgz` (no `file:` prefix) and records the sha512 integrity; `bun install --frozen-lockfile` accepts the pair.
- Peers are EXACT in the SDK (`@daily-co/daily-js` `0.91.0`, `@heygen/liveavatar-web-sdk` `0.0.18`); `frontend` resolves `^0.91.0` and
  `^0.0.18` to exactly those (checked in `bun.lock`). The design text said `^0.91` / `^0.0.18`; the catalog row states the exact peers.

### Wrapper (NOT committed, for the orchestrator)

`docs/version-catalog.md`: one row added under "Runtimes and frameworks" (`@hr-avatar/sdk`, `0.0.0`, vendored, integrity, peers,
loaded only behind the default-off flag). Verified with `rg -n 'hr-avatar/sdk' docs/version-catalog.md`. Suggested commit, staging only
that path: `docs(version-catalog): record the vendored @hr-avatar/sdk`. Task 10.8a stays unchecked until that commit exists.

### Deviations and notes

1. **SDK entry shape.** The task brief and design say `connect({...})`; the package's public entry exports `HrAvatar` (an object with
   `connect`), not a bare `connect` (the IIFE global exposes the bare one). The adapter calls `sdk.HrAvatar.connect(...)`. Types come
   from `typeof import('@hr-avatar/sdk')` as designed.
2. **`import.meta.client` is not defined in Vitest** despite `vitest.config.ts`. The default loader and the deferred handle use
   `if (import.meta.server) throw` instead of `if (!import.meta.client) throw`; in the Nuxt client build `import.meta.server` is false, in
   the server build true (the throw makes the import unreachable and it is eliminated, observed in the built server chunk).
3. **`rg -l '@hr-avatar/sdk' .output/server` is not empty** because of the client manifest (see Bundle checks). The check was applied
   with that one manifest file excluded, plus a marker scan; the intent (no server code imports the SDK) holds.
4. **SDK `error` event** is mapped to a provider `error` for every occurrence, as the design table says. The SDK also emits `error` for
   non-fatal conditions (a lifecycle post that fails, a mic toggle that fails, a failed `end` request), so a flaky network can show the
   retryable error screen mid-interview. Not changed (binding design); worth deciding before the flag is ever enabled outside local.
5. **`factory.ts` in F1.** Adding `'hr_avatar'` to `ProviderName` broke the exhaustive `never` binding, so F1 already rearranged the
   `switch` (throw text unchanged, `hr_avatar` falls into it). F3 then replaced the `break` with the flag-gated arm.
6. **Stopped-while-connecting** is handled beyond the written tests of the design: `HrAvatarProvider.stop()` during `connect()` ends the
   conversation as soon as `connect` resolves, and the deferred handle's `stop()` before the adapter loads keeps the adapter from
   starting (both tested).
7. The F2a size and the gga non-blocking notes about stale comments in `factory.ts` (file header mentions the E2E fixture module; the
   error text lists two providers) were left as they are: the error text is bound by the spec to stay identical.

### Open items for the orchestrator

- Commit the wrapper catalog row (task 10.8a). Peers in the row are exact.
- W1 (14.x) is unblocked on the frontend side: the version in `frontend/package.json` is `0.0.0`, equal to the row.
- The exact `HrAvatarError` codes for connect-time refusals remain assumed (`provider_concurrency_limited`, `provider_credential_missing`,
  `provider_error`); every non-origin code maps to `sdk_error`, so a rename changes nothing at runtime.
- The relative order of SDK `state ended` and `ended` was read from `hr-avatar/sdk/src/conversation.ts`: the state is set first, then
  `ended` is emitted in the same tick, which is the order the one-macrotask defer was designed for.

## Full Playwright (task 13.5) - NOT a clean exit 0 on this host; reported as such

`bun run test:e2e` (the config builds and serves the app itself; chromium, webkit, mobile), host Mac, no Docker, other writers running
test suites at the same time (load average 7 to 22 during the runs):

| Run | Result | Failures |
|---|---|---|
| 1, default workers (8) | exit 1: 412 passed, 4 failed, 3 skipped, 5.0 min | 4 webkit `page.goto` timeouts (30 s, "waiting until load"): `reusable-link.spec.ts:1607`, `root-landing.spec.ts:46`, `unsupported-gate.spec.ts:46`, `unsupported-gate.spec.ts:146`. Zero chromium failures |
| 1b, those three files, webkit, `--workers=2` | exit 0: 83 passed, 1 skipped | none |
| 2, `--workers=2` | exit 1: 413 passed, 3 failed, 3 skipped, 6.4 min | 3 different webkit timeouts: `interview-flow.spec.ts:418` and `:537` (`page.goto` 30 s), `unsupported-gate.spec.ts:127` (`browserContext.close`). Zero chromium failures |
| 2b, `interview-flow.spec.ts` + `unsupported-gate.spec.ts`, webkit, `--workers=2` | exit 0: 34 passed, 1 skipped | none |

The failing tests differ from run to run, all are webkit navigation or context-close timeouts on pages that involve no provider, and each
file passes when run alone; this reads as host contention (CI runs `workers: 1`, `retries: 2`, `failOnFlakyTests`), not a regression, but it
is NOT claimed as a green full run. The new `interview-default-provider-path.spec.ts` passed in chromium and webkit in both full runs and
in its own run. Baseline comparison against `develop` was not made (it would need a second build under the same load); the orchestrator
may want a quiet-machine run, or the CI run, as the proof of record. No screenshot baseline failed (the darwin baselines exist).

## F-sync (contract sync with api `adf9b79`) - DONE

Commit `3b1c85e` `chore(frontend): sync api contract` (generated files only: `openapi.json` +378/-, `types/api.ts` +101/-; 0 authored lines). gga ran and reported "No matching files staged" (`types/api.ts` is excluded from gga; the snapshot is JSON), no `--no-verify`.

- Mechanism: `openapi.json` (snapshot) -> `bun run codegen` (`openapi-typescript`) -> `types/api.ts`; `bun run codegen:check` (`scripts/check-client-drift.sh`) compares the snapshot with `../api/openapi.json` and regenerates.
- Source: `git -C ../api status --porcelain openapi.json` empty (0 lines), then `git -C ../api show HEAD:openapi.json > openapi.json`.
- Content of the sync: documentation-only for the avatar-template endpoints, `hr_avatar` / `avatar_config` enum values, `hr_avatar_config_id`, typed catalogue items, `FieldType`, narrowed `status`/`code` enums. No type consumed by existing frontend code broke.

| Gate | Result |
|---|---|
| `bun run codegen` | exit 0 |
| `bun run codegen:check` | exit 0 (snapshot matches api; client matches snapshot) |
| `bun run lint` | exit 0 |
| `bun run typecheck` | exit 0 (only the pre-existing `UiSonner` duplicate-name warning) |
| `bun run test:unit:coverage` | exit 0; 148 files, 3804 tests passed; all files 98.49 / 94.44 / 96.85 / 98.49 (stmts/branch/funcs/lines) |
| `git diff --name-status develop...HEAD -- tests` | 7 entries, all `A` |

Playwright e2e NOT run in this unit (deferred to a quiet machine). The flag `NUXT_PUBLIC_HR_AVATAR_ENABLED` default is untouched (off). No failing-first test was needed: nothing failed because of the sync.

## Contract sync after api `2bd711f` - DONE

Commit in `frontend`: `68292db` chore(frontend): sync the api contract (`openapi.json` copied from the clean api working file, `bun run codegen`; `types/api.ts` +/-27 lines: the organization template destroy now documents 204 and a 409 with `template_active|template_in_use`, `project_count?`, `organization_count?`).

| Gate | Result |
|------|--------|
| `bun run lint` | exit 0 |
| `bun run typecheck` | exit 0 |
| `bun run codegen:check` | exit 0 |
| `bun run test:unit:coverage` | exit 0; 148 files, 3804 tests; 98.49 / 94.44 / 96.85 |
| `git diff develop --name-status -- tests` | empty-of-non-`A` (no `M`/`D`) |

No frontend code reads the changed schema, so no failing-first test applied. e2e not run.

## F1-cleanup (approved-review warnings R3-001..R3-006) - DONE

Strict TDD, failing test first for every code change. Tasks 10.21-10.25 in `tasks.md`.

| Warning | Outcome | Commit |
|---------|---------|--------|
| R3-001 lockfile specifier | No change: bun normalizes `file:./vendor/...` to `./vendor/...` in `bun.lock`; frozen and plain installs leave the lock byte-identical (scratchpad copy), in-place dry run exit 0. Version pin and tarball untouched. | none |
| R3-002 join object | `hrAvatarJoinOf()` drops a partial `hr_avatar` object; the adapter's absent-input guard fails the start via the existing provider error path | `28c03f6` |
| R3-003 stale connect | generation guard: a superseded connect is ended and never wired; its failure is silent | `25b8789` |
| R3-004 transient states | only SDK state `error` is terminal; union is `connecting \| live \| ended \| error` | `25b8789` |
| R3-005 early mic choice | the deferred handle remembers it and applies it once after `start()` resolves | `6281241` |
| R3-006 exhaustiveness | `never` check restored (develop shape) with an `hr_avatar` arm; mutation proved the compile error | `6281241` |

### TDD cycle evidence

| Task | RED | GREEN |
|------|-----|-------|
| R3-002 | `hr-avatar-start-config.spec.ts`: 7 failed / 14 | 14 / 14 |
| R3-003, R3-004 | `hr-avatar-provider-stale-start.spec.ts`: 6 failed / 6 | 6 / 6 |
| R3-005, R3-006 | `hr-avatar-factory-mic.spec.ts`: 4 failed of 6 (3 early-mic cases, 1 exhaustiveness text guard; 2 regression guards passed before) | 6 / 6 |

### Gates (final tree)

| Gate | Result |
|------|--------|
| `bun run lint` | exit 0 |
| `bun run typecheck` | exit 0 |
| `bun run codegen:check` | exit 0 |
| `bun run test:unit:coverage` | exit 0; 150 files, 3824 tests; 98.50 / 94.48 / 96.86 |
| `bun install --frozen-lockfile --dry-run --ignore-scripts` | exit 0 |
| `git diff develop --name-status -- tests` | 9 entries, all `A` |

e2e not run. Deviation: the factory flag-off path now throws through a shared `unknownProviderError()` helper; the message text is unchanged (pinned by `hr-avatar-factory.spec.ts`).

## F2-cleanup (approved-review findings, contract sync) - DONE

Commits: `6cc96c1` chore(frontend): sync the api contract (api `6a4f300`); `8b6862b` fix(frontend): queue a mic choice made while an hr_avatar re-start is connecting; `9f6b4f7` test(frontend): assert a partial hr_avatar join object fails the real adapter start; `11a37c3` docs(frontend): describe the inline mock provider the factory actually returns.

| Item | RED / mutation (observed) | GREEN |
|------|---------------------------|-------|
| deferred handle `started` latch never reset | `hr-avatar-factory-mic.spec.ts`, 4 new cases with a gated fake adapter: 3 failed (re-start mute, re-start toggle, newest start only), re-observed against the unfixed file; the 4th is a regression guard | 10/10; per-start generation, latch reset on every `start()` |
| start-config cases only checked the absent key | behaviour present, no RED possible; mutation: dropping `!cfg.hrAvatar` from the adapter guard fails 7 of 7 (`sdkLoader` called), reverted | 14/14; cases drive the real `HrAvatarProvider` and assert `sdk_error` and no SDK load |

Gates (final tree): lint 0; typecheck 0; `codegen:check` 0; `test:unit:coverage` 0 (150 files, 3828 tests; 98.5 / 94.49 / 96.86); tests diff vs develop 9 entries, all `A`. gga passed on every commit. Accepted, no change: R3-002 (the SDK `state` union is closed and versioned with the vendored tarball; a new state only arrives with a tarball update, which must update the adapter), R3-004 (suggestion). gga non-blocking notes left: a failed post-connect `setMicMuted` is swallowed; a toggle before connect assumes the adapter starts unmuted. e2e not run.

## F3 follow-up (gga notes on the deferred handle) - DONE

Commit `3d4cb3a` fix(frontend): apply a queued mic toggle as a flip and log a refused queued mic choice.

| Item | RED (observed) | GREEN |
|------|----------------|-------|
| a refused queued mic choice was swallowed | `hr-avatar-factory-mic.spec.ts`: 2 cases (explicit choice, toggle) with an adapter that throws: `warn` called 0 times | logged once with a stable reason, no `error` event, start still resolves `{}` |
| a queued toggle assumed an unmuted start | stateful fake adapter that starts muted: the toggle ended muted (3 failures with the two updated expectations) | the toggle is kept as a flip and applied through the adapter's own `toggleMic()` after any queued explicit choice; an explicit choice supersedes earlier flips |

Why not `error`: a provider `error` moves the session to the error state; a mic is not worth ending the interview. Why a flip instead of reading the adapter: neither the adapter nor the SDK conversation exposes the mute state. The two toggle expectations in the branch-added `hr-avatar-factory-mic.spec.ts` changed from `setMicMuted:true` to `toggleMic` (not a develop test).

Gates: lint 0; typecheck 0; `codegen:check` 0; `test:unit:coverage` 0 (150 files, 3834 tests; 98.5 / 94.5 / 96.86; `sentry-scrub.spec.ts` linear-time timing test failed once under load, passes alone and on rerun); tests diff vs develop 9 entries, all `A`. gga passed on the first attempt (non-blocking note: the unknown-provider text still says only heygen/tavus, pinned by tests, unchanged). e2e not run.

## Unit F4: the deferred hr_avatar handle after a failed re-start and during the flush - DONE

Strict TDD. Commits `b58f992` (contract sync, api `54d4b3d`) and `8a7ae6b` on `feature/extract-avatar-service`; details in task 13.7.

| Defect | RED (`hr-avatar-factory-mic.spec.ts`) | GREEN |
|---|---|---|
| a rejected re-start left `started` false while the first adapter was connected | a mic call after the rejection reached no adapter; a choice queued during the failing start never applied; an older start connecting after the newest failed was ignored | `live` + `newestFailed`: the mic goes back to the connected adapter, the queue is applied there |
| the flush ran beside a user toggle | the toggle was forwarded while the queued mute was still pending; an explicit unmute made during the flush hung behind it | `flushing` queues new controls; a loop drains them after the queued choice |

Characterizations that already held: no connected adapter keeps the choice for the retry; an older start failing late does not take the mic from a newer one.

Gates: lint 0; typecheck 0; `codegen:check` 0; `test:unit:coverage` 0 (150 files, 3842 tests; 98.51 / 94.5 / 96.88); tests diff vs develop 9 entries, all `A`.

## Unit F6: a queued hr_avatar mic step that never settles - DONE

Strict TDD. Commit `887a002` on `feature/extract-avatar-service`; details in task 13.8.

| Defect (fe3 R3-001) | RED (`hr-avatar-factory-mic.spec.ts`, fake timers) | GREEN |
|---|---|---|
| `flushing` cleared only after `flushQueued()` settled, so one adapter mic call that never settled queued every later control forever | an adapter whose first `setMicMuted` never settles: after 5 s the warning was logged 0 times and `start()` never resolved | each flush iteration races a 5000 ms timeout (`MIC_APPLY_TIMEOUT_MS`); on timeout it logs once with `reason: 'mic_apply_timeout'`, clears its timer, drains what queued behind it, clears `flushing`, and later controls are forwarded directly |

Accepted, no change: fe3 R3-002 (the `error` event `message`): the server emits `message` equal to the error code (verified in A16), so the handle's `{ code: 'sdk_error', message: 'provider_unavailable' }` is consistent with it. gga non-blocking notes left: the unknown-provider text still lists only heygen/tavus (pinned by tests, unchanged).

Gates: lint 0; typecheck 0; `codegen:check` 0; `test:unit:coverage` 0 (150 files, 3843 tests; 98.51 / 94.51 / 96.88); tests diff vs develop 9 entries, all `A`. e2e not run.
