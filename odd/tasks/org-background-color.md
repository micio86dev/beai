# org-background-color

## Objective
An organization can set a candidate-page background colour in Settings, in addition to the primary colour. The candidate frontend paints its canvas with it. When unset the canvas is DARK (default `#0f172a`). The primary colour stays the accent of active states (current step, who is speaking, toggles on, buttons, progress). Backoffice gets a quick Light/Dark selector (two presets) plus a free colour field.

## Problem
There is no background colour: `organizations` has only `primary_color` and `logo_path`; the candidate canvas is `bg-primary text-on-primary` and every on-canvas token is derived from the primary (`useBrandTheme.ts`). Mapped end to end (api -> candidate branding payload -> frontend tokens -> backoffice `BrandingForm.vue`).

## Decisions (owner-confirmed 2026-10-16)
- Default canvas is dark, not the Quint purple. Orgs without a background change appearance on purpose.
- Primary colour = accent for active states, everywhere. Speaking ring moves from fixed white to the primary with a contrast guard on the dark canvas (lightened variant when needed). Toggles on use the primary accent.
- Presets: Dark `#0f172a`, Light `#f1f5f9`. Free colour via the same native picker + hex text as primary. Clear = back to default (null = dark).
- Emails stay on the primary colour only (light chrome). Public API v1 untouched.

## Tasks
- [x] T0 docs (da4cf1c) (wrapper, branch feature/org-background-color): DESIGN.md §3.1 canvas section (+ token table: on-canvas, on-canvas-muted, canvas, canvas-tone; usage rules 3 and the text-primary rule), §7.0.1 shell legend/bullets, §3.4/§3.5 wording, §7.3 speaking ring now primary-with-contrast; CLAUDE.md "Product decisions" item 9 (background colour, nullable permanently, default dark). No code.
- [x] T1 api (70d866f; stacked on feature/answer-time-range): migration (`background_color` varchar(7) nullable + CHECK `organizations_background_color_hex`), Organization model, UpdateOrganizationRequest + UpdateManagedOrganizationRequest rules/messages (`background_color_invalid`), OrganizationController/AdminOrganizationController allow-lists, Admin OrganizationResource + Scramble, ParticipantResource/ParticipantEnrolmentResource `branding.background_color` + shapes, T-EXPOSE-001 entry, tests (BrandingTest key set etc.), openapi export (Postgres) + copies.
- [x] T2 backoffice (66d7ccf; stacked on feature/answer-time-range): `BrandingForm.vue` background field with Light/Dark preset buttons + picker + hex + clear, payload, server error map, i18n it/en, tests, regenerate types.
- [x] T3 frontend (7b6d7ec 916a663 f5ef72d 555865c; after the answer-time-range frontend task is committed): `--color-canvas` token (default dark), `applyBrandCanvas`/useBrandTheme derive `on-canvas`, `on-canvas-muted`, `canvas-tone` from the background, `BrandCanvas` and every on-canvas usage swapped, `useCandidateBranding.prime/reset`, accent states on primary (toggles, speaking ring with contrast guard, current step), fixtures, tests, darwin baselines.

## Constraints
Strict TDD, repo language English (i18n it/en excepted), conventional commits without AI attribution, one work-unit commit per task with tests, exposure rule T-EXPOSE-001, push allowed (standing order), no deploy until told. Advisory ~400 lines/task.

## Route
Delegated direct, one writer per repo. T0 and T1 in parallel; T2 parallel with T1 once openapi is copied; T3 last.

## Progress
T0-T3 committed. api/backoffice/frontend branches pushed (api pending full-suite result). Open: the interviewer tile (#0f172a) equals the default canvas, so its edge disappears; fix with a hairline band on the tile. DESIGN.md defaults corrected to real derivations (speaking ring #9c59c5, on-canvas-muted #caccd0, canvas-tone #080d17, new --color-primary-edge).
