# Brand-colour candidate canvas

Feature: restyle the candidate-facing `frontend` so the CLIENT organization's primary colour is the page background, with a modern, carefully designed UI/UX.

## Objective
The candidate app renders on a full-bleed canvas in the client's primary colour (Quint `#771aaf` when the client configured none), with every piece of text, link and control legible on it, and a polished, modern look across the whole candidate flow.

## Problem
- Branding today reaches the UI only as `--color-primary*` tokens, applied in `NoticeShell` and a few accents. Most pages sit on `bg-background` (white).
- `--primary-foreground` is never recomputed per tenant, so any text placed on a tenant colour can be unreadable. `readableForeground()` exists only in `backoffice/app/utils/brand-color.ts`.
- `text-primary` links and `bg-primary/10 text-primary` chips would be invisible on a primary-coloured canvas.

## Why
The owner asked for the client colour to be the background and for strong UI/UX care. A white-label canvas is the visible half of the 2026-09-01 white-label ruling (logo + primary colour only).

## Scope
In: `frontend` candidate flow (landing, hosted/reusable/embed entry, device check, consent banner, interview screen chrome, done, error, terminal, unsupported), the shared shell, tokens, `DESIGN.md` amendment, tests.
Out: backoffice, api, the interview avatar/video panel internals, per-tenant copy or layout, the FR-006 multi-test portal (parked).

## Constraints
- `DESIGN.md` is authoritative and currently says strong purple/orange stay for accents only and the page background is a light gradient: it MUST be amended BEFORE any UI contradicting it (task F1).
- Tenant colour is mixed in JS to concrete hex, never `color-mix()`; contrast is guaranteed by code, not by the operator (DESIGN.md 7.3.2, 9.1). Text 4.5:1, large text and UI components 3:1.
- Text colour on the canvas uses the SAME `readableForeground` logic as the backoffice (white or black by higher WCAG contrast; tie and invalid go to white).
- Motion only under `prefers-reduced-motion: no-preference`. Lighthouse: Performance >= 90, Accessibility 100, Best Practices 100; CLS < 0.1. Desktop only (1280x800 minimum); mobile keeps the SA-11 gate.
- Bun only. No hardcoded user-facing text (i18n it/en). Open Sans self-hosted. English in code and docs.
- Artifacts in English. Conventional commits, no attribution trailers.

## Mode and delivery
- TDD: enabled. Source: session configuration (Strict TDD mode). Runner: Vitest (`bun run test:unit`) and Playwright (`bun run test:e2e`) in `frontend`; Pest in `api` is not involved.
- Delivery strategy: `ask-on-risk` (default). Forecast: about 1200 to 1800 authored changed lines across wrapper and frontend; chain strategy to be asked before the first push if the running count passes about 400 per PR.
- Worktrees: wrapper `../beai-worktrees/wrapper-brand-canvas`, frontend `../beai-worktrees/frontend-brand-canvas`, both on `feature/brand-colour-canvas` from `origin/develop`.
- Reference mapping of the current state: DESIGN.md 61-90, 572-605, 1072-1101; `frontend/app/composables/useBrandTheme.ts`; `frontend/app/utils/brand-color.ts`; `frontend/app/assets/css/main.css`; `frontend/app/components/molecules/NoticeShell.vue`.

## Tasks
- [ ] F1 Amend `DESIGN.md`: brand canvas as the candidate-flow background, on-primary foreground token, elevated surface rules, motion and contrast rules. Route: delegated writer (wrapper).
- [x] F2 Port `readableForeground` to `frontend/app/utils/brand-color.ts`; make `applyBrandColor` also set the on-primary foreground tokens, with parity tests against the backoffice fixtures. Route: delegated writer (frontend).
- [ ] F3 Shared canvas shell (full-bleed primary, logo, elevated content surface, typography scale, subtle motion) used by every candidate page. Route: delegated writer.
- [ ] F4 Restyle the candidate pages and components on the canvas; fix every `text-primary` or white-assumption that becomes invisible. Route: delegated writer.
- [ ] F5 Interview screen chrome coherent with the canvas (header, progress, controls, captions) without touching the avatar panel internals. Route: delegated writer.
- [ ] F6 Verification: unit, typecheck, lint, Playwright (Chromium + WebKit) with axe, screenshots under light, dark, mid-tone and no-colour brands, snapshot refresh, Lighthouse run. Route: fresh verifier worker.

## Acceptance criteria
- With a light brand (`#ffd400`), a dark brand (`#771aaf`), a mid-tone brand and no brand, every candidate page is fully legible (axe 0 contrast violations, text >= 4.5:1).
- The same `readableForeground` fixtures pass in `frontend` and `backoffice`.
- `DESIGN.md` describes the new background rule and the tokens it introduces.
- Existing unit and e2e suites pass; screenshots are refreshed and reviewed.

## Progress
Created 2026-10-06.
- F2 done (frontend 2f8b192): `readableForeground` ported; `applyBrandColor` sets `--color-on-primary`, `--color-on-primary-muted`, `--color-primary-surface`, `--color-on-primary-surface` (concrete hex, 4.5:1 guaranteed, removed on the no-colour path); Quint defaults in `main.css` pinned to the runtime derivation by `token-parity.spec.ts`. Values for `#771aaf`: `#ffffff`, `#e1cded`, `#f4edf9`, `#0f172a`; for `#ffd400`: `#000000`, `#382f00`, `#fffceb`, `#0f172a`.

## Verification evidence
- F2: RED 38 failed then GREEN; parent spot check `bun run test:unit brand-color brand-theme token-parity`: 60 passed. Full unit suite after `bun run proctor:assets` (the 8 `proctor-assets` failures were only the gitignored MediaPipe binaries missing in the fresh worktree): 82 files, 2105 tests passed. Lint 0 errors, typecheck clean. Playwright not run yet (F6).

## Route declaration
Mapping delegated (2 read-only explorers, findings recorded above). Implementation delegated per task; one writer at a time per repository.

## Next step
F1 (DESIGN.md), then F3 and F4 (one writer, in progress).
