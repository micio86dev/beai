# Interview intro phrase (global setting, superadmin only)

Objective: a multilingual intro phrase, set in the backoffice global settings by the superadmin
only, spoken by the avatar at the start of any interview, so the candidate has time to understand
what BEAI is and gets tips for a good interview.

Requested by the owner on 2026-10-13, to start AFTER the in-flight work (owner decisions T1-T6)
is finished and released.

Mode: strict TDD (RED observed before GREEN); runners Pest (api) and Vitest/Playwright
(frontend, backoffice). Delivery: feature branches, native review with the owner's consent,
Git Flow release, Railway deploy, production check.

## Decisions taken

- **Time budget (owner, menu answer):** the intro time COUNTS against `interview_max_seconds`
  (the live clock opens when the provider session is issued; the provider ends the call at the
  template limit). The text has a length cap, about 600 characters per locale (roughly 40 s of
  speech), and the backoffice shows an estimated duration.
- **Storage:** no migration. Key `interview_intro_phrase` in `platform_settings` (JSON value),
  a locale map `{it, en}`. The whole setting is optional (empty or absent = no intro). When present,
  `en` is required, other supported locales optional, non-blank, no edge whitespace
  (`ValidatesLocaleMaps` convention). Locales are the supported ones only (`it`, `en`).
- **Who can write:** superadmin only, through the existing `GET/PATCH admin/settings`
  (`SuperadminController`, gate `platformSettings.viewAny`), with an audit row like currencies.
- **When it is spoken:** only on the true first start of a participant (variant `first`, first
  competency), prepended to the verbatim opening text. Never on `next`, `resume`, `retry`,
  `reinterview`, a Tavus competency handover or a suspend/resume.
- **Fallback:** project language, then `en`, then no intro. A missing text never blocks an interview.
- **LLM prompt:** the system prompt is told through `SpokenOpening` that the intro was already
  delivered, so the model does not repeat or paraphrase it.
- **Guards:** the text must not contain the end phrase or the final phrase of any locale
  (they trigger interview completion on the client).

## Tasks

- [x] F1 `PlatformSettings` accessor + validation for `interview_intro_phrase` (locale map, length cap, forbidden phrases) (api).
- [x] F2 `GET/PATCH admin/settings` expose and update it, superadmin only, audit row, `@scramble-return`, OpenAPI export (api).
- [x] F3 Compose the first opening with the intro (variant `first` only), fallback chain, `SpokenOpening` so the prompt knows it was said (api).
- [x] F4 Verify transcript, scoring and primary-asked count are not disturbed by the extra utterance; fix or flag (api).
- [x] F5 `PlatformSettingsPanel`: per-locale textareas, character counter, estimated duration, i18n it/en (backoffice).
- [x] F6 Candidate app: no change expected (provider speaks `custom_greeting` / `opening_text` verbatim); confirm with tests and one E2E (frontend).
- [x] F7 Release: api, frontend (spec sync), backoffice, wrapper SDK regeneration; deploy and verify.

## Evidence

Closed 2026-10-13 and released: api v0.73.0, frontend v0.26.11 (spec sync only), backoffice v0.52.0, wrapper v0.56.0.

- F1/F2: api 6b6cb8d (setting, validation incl. completion-phrase guard, audit row, transactional PATCH, spec).
- F3: api 2e8205b (optional `opening.intro_spoken` fragment: the sealed active prompt set keeps working, baseline stays at 32 required keys) and 5e499be (intro prepended inside the single opening string, only `first` variant, competency 1, with a primary to follow). Guards a881a73, eff990e, 5b611c3.
- F4: api d7addbe (TurnClassifier suffix match keeps the primary as the tail; primary count and resume unchanged). No production change needed.
- F5: backoffice 3b2faab, 7107503, 7409986, plus 5184f13 and 0bf6141 (counter on trimmed text, exact e2e assertions).
- F6: no frontend code change. The frontend never receives or builds the opening text (`opening_text` / `custom_greeting` appear nowhere in its code): the api hands it to the provider and the frontend only sees the avatar utterance and runs it through `matchesEndPhrase`. Proven by 14 tests in `tests/unit/opening-text-intro.spec.ts` (frontend a1d17fe): long intros with accents and quotes never complete the interview, the exact end/final phrase still does.
- F7: releases above; production: api, worker, scheduler, frontend and backoffice deployments SUCCESS, health 200, environment 0 issues, `GET /api/admin/settings` answers 401 without a token.

Checks observed: api 9511 tests at 98.2 percent (pint, phpstan clean); backoffice 4078 tests at 99.46/95.51/96.42, e2e on Chromium and WebKit; native review approved on every commit.

Not verified: no real interview was run in production with an intro configured (it needs a superadmin login and a live avatar provider session). Known gaps: the caps write in `setMaxQuestionsPerCompetency` is a read-then-write without a row lock (pre-existing); retry and reinterview variants are covered only through the composer unit test.
