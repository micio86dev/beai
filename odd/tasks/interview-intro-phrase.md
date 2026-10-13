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

- [ ] F1 `PlatformSettings` accessor + validation for `interview_intro_phrase` (locale map, length cap, forbidden phrases) (api).
- [ ] F2 `GET/PATCH admin/settings` expose and update it, superadmin only, audit row, `@scramble-return`, OpenAPI export (api).
- [ ] F3 Compose the first opening with the intro (variant `first` only), fallback chain, `SpokenOpening` so the prompt knows it was said (api).
- [ ] F4 Verify transcript, scoring and primary-asked count are not disturbed by the extra utterance; fix or flag (api).
- [ ] F5 `PlatformSettingsPanel`: per-locale textareas, character counter, estimated duration, i18n it/en (backoffice).
- [ ] F6 Candidate app: no change expected (provider speaks `custom_greeting` / `opening_text` verbatim); confirm with tests and one E2E (frontend).
- [ ] F7 Release: api, frontend (spec sync), backoffice, wrapper SDK regeneration; deploy and verify.

## Evidence

Filled in as each task closes.
