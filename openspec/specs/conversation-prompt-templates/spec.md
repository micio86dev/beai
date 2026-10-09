# Conversation Prompt Templates Specification

## Purpose

Platform-level, immutable, locale-keyed storage for the prose `SystemPromptComposer` renders (Layer 1: the global
prompt set of 32 fragments) and for per-role and per-competency prompt overrides appended into the composed prompt
(Layer 2). This capability governs storage, the placeholder contract, resolution, activation, the content seal and
the bootstrap; composition itself, the byte-identity gate and the durable stamp belong to `interview-conversation`.

The word **prompt set** is used everywhere. "Revision" is reserved for `FrameworkCatalogRevision`.

## Non-Goals

- Backoffice authoring UI (publishing is console-only in this change)
- Per-organization prompt sets (platform-level only)
- REPLACE-mode overrides (APPEND only)
- Localised interviewer directives and any Italian re-authoring: the `it` fragment rows are verbatim copies of `en`
- `api/lang/{en,it}/interview.php` (`end_phrase`, `final_phrase`) and `OpeningTextComposer`
- An activation ledger or any platform audit trail

## Requirements

### Requirement: A Prompt Set Holds Exactly The Fragment Key Set, For Every Locale It Serves

A prompt set MUST hold one fragment row per (`fragment_key`, `locale`) for EVERY key of `PromptFragmentKey`, for each
locale it serves. The key set is these 32 keys: `header`; `label.opening`, `label.coverage`, `label.override`,
`label.star`, `label.follow_up`, `label.nudge`, `label.primary`, `label.advance`; `star`, `budget`, `nudge`;
`opening.resumed_notice`, `opening.fallback`, `opening.quoted`, `opening.spoken_reask_all`, `opening.spoken_resumed`,
`opening.spoken_fresh`, `opening.closing`, `opening.continuation`; `primary.none`, `primary.intro`, `primary.asked_before_one`,
`primary.asked_before_many`, `primary.progress_all_asked`, `primary.progress_last`, `primary.progress_next`;
`advance.floor_one`, `advance.floor_many`, `advance.floor_with_primaries`, `advance.with_phrase`,
`advance.without_phrase`. A set with a missing key, or with a key outside this set, MUST be refused at publish and
MUST NOT be resolvable at composition. Branch selection, the minimum clamp, line joins, the `N. question` numbering and
the coverage line format are NOT fragments and stay in code.

The `it` rows of the baseline set MUST be byte-identical copies of the `en` rows: the interviewer directives are
English in every locale by decision (see `interview-conversation`, "i18n - Composed Prompt in Project Language").

#### Scenario: A complete set is publishable

- GIVEN a payload with all 32 keys for `en` and for `it`, each passing the placeholder contract
- WHEN it is published
- THEN the set, 64 fragment rows and a content seal are stored in one transaction, inactive

#### Scenario: A set with a missing key is refused at publish

- GIVEN a payload lacking `advance.floor_one` for `en`
- WHEN it is published
- THEN publishing is refused and nothing is persisted

#### Scenario: A set with an unknown key is refused

- GIVEN a payload containing a key that is not in `PromptFragmentKey`
- WHEN it is published, or when such a row is found in the active set at composition
- THEN publishing is refused, or resolution throws; the unknown key is never ignored

#### Scenario: Two locales of one set are independent rows

- GIVEN a set with `budget` rows for `en` and `it`
- WHEN each locale is resolved
- THEN each returns its own body

---

### Requirement: Fragment Placeholder Contract

Fragments MUST use the `{{token}}` delimiter. Each key declares its allowed tokens, and a fragment MUST contain every
required token at least once. The contract is:

| Key | Required tokens |
|---|---|
| `header` | `{{competency_code}}` |
| `budget` | `{{budget}}` |
| `nudge` | `{{nudge_min_chars}}` |
| `opening.quoted` | `{{number}}`, `{{question}}` |
| `opening.spoken_reask_all`, `opening.spoken_resumed`, `opening.spoken_fresh` | `{{quoted}}` |
| `primary.asked_before_many` | `{{count}}` |
| `primary.progress_last` | `{{spoken}}` |
| `primary.progress_next` | `{{spoken}}`, `{{next}}` |
| `advance.floor_many` | `{{min_questions}}` |
| `advance.floor_with_primaries` | `{{floor}}` |
| `advance.with_phrase` | `{{floor}}`, `{{advance_phrase}}` (its surrounding double quotes are part of the template) |
| `advance.without_phrase` | `{{floor}}` |
| every other key | none |

A fragment MUST NOT contain a `{{x}}` token outside its allowed set, a stray `{{` or `}}`, or leading or trailing
whitespace. An override body MUST contain no placeholder at all. The contract validates TEMPLATES only, at publish and
again at composition; it MUST NOT be applied to rendered text. Rendering MUST be a single pass, so a value that itself
contains `{{budget}}` renders literally.

This contract is a load-bearing substitute for the code-review gate that database-driven prompts remove: an advance
fragment without the advance phrase reproduces a defect that has already shipped once (the avatar never speaks the
closing phrase, completion detection never fires, and the provider session dies with `MAX_DURATION_REACHED`).

#### Scenario: advance.with_phrase without its advance phrase is refused at publish

- GIVEN an `advance.with_phrase` body containing `{{floor}}` but not `{{advance_phrase}}`
- WHEN the set is published
- THEN publishing is refused and no row is persisted

#### Scenario: A fragment with an unknown token is refused

- GIVEN a `budget` body containing `{{budget}}` and `{{nope}}`
- WHEN the set is published
- THEN publishing is refused

#### Scenario: A value containing a token renders literally

- GIVEN an advance phrase whose text contains `{{budget}}` and a primary question containing `Re:think` and `:budget`
- WHEN the fragments are rendered
- THEN those characters appear in the output unchanged and nothing is substituted inside them

#### Scenario: An override body with a placeholder is refused

- GIVEN an override body containing `{{budget}}`
- WHEN the set is published
- THEN publishing is refused

---

### Requirement: Exactly One Active Prompt Set, Activated Atomically

At most one prompt set MUST be active, enforced by the database (a partial unique index on `is_active`). Activating a
set MUST first verify it with the checks a composition runs (seal, key set and placeholder contract for every locale it
holds, and every override body), MUST deactivate the incumbent first and activate the new set in the same transaction,
and MUST record `activated_at`. Activating the already active set changes nothing. Activation affects only the NEXT composition; a session already composed keeps the set it was
stamped with (see `interview-conversation`, "Durable Conversation Prompt Stamp").

#### Scenario: A second active set is refused by the database

- GIVEN set S1 is active
- WHEN a row for set S2 is inserted with `is_active = true` directly
- THEN PostgreSQL raises a unique violation (`23505`) on the one-active index

#### Scenario: Activation swaps the active set atomically

- GIVEN S1 is active
- WHEN S2 is activated
- THEN S2 is the only active set, `activated_at` of S2 is set, and S1 is no longer active

#### Scenario: A set that does not verify is not activated

- GIVEN S1 is active and S2 was altered out-of-band so that its seal no longer matches
- WHEN S2 is activated
- THEN the activation is refused and S1 is still active

#### Scenario: A failed activation leaves the incumbent active

- GIVEN S1 is active
- WHEN activating S2 fails after the deactivation step
- THEN the transaction rolls back and S1 is still active

---

### Requirement: The Database Refuses To Rewrite A Published Set

A trigger MUST refuse UPDATE and DELETE on `conversation_prompt_fragments` and `conversation_prompt_overrides`, and
MUST refuse any UPDATE on `conversation_prompt_sets` that changes a column other than `is_active`, `activated_at` and
`updated_at`. A set with fragments MUST NOT be deletable (foreign keys restrict deletion). Publishing new text MUST
create a new set. Seeders and raw SQL are bound by the same rule.

#### Scenario: Editing a fragment is refused

- GIVEN a stored fragment
- WHEN its body is updated directly
- THEN PostgreSQL raises a check violation (`23514`) naming the table

#### Scenario: Deleting a fragment or override is refused

- GIVEN a stored fragment or override
- WHEN it is deleted directly
- THEN PostgreSQL raises a check violation (`23514`)

#### Scenario: Changing a set's label or seal is refused, flipping activation is not

- GIVEN a stored set
- WHEN its `label` or `content_sha256` is updated
- THEN the update is refused
- AND an update that changes only `is_active`, `activated_at` or `updated_at` succeeds

---

### Requirement: Content Seal Verified On Resolution

Each set MUST carry `content_sha256`: the SHA-256 of the canonical JSON of its fragments (sorted by key, then locale)
and its overrides (sorted by role code with NULL first, then competency code, then locale), computed from the
validated payload before the set is inserted. The resolver MUST recompute the seal from the loaded rows when it fills
its cache and MUST throw on a mismatch. A row inserted into an existing set after publication is therefore detected.

#### Scenario: A tampered set is not composed

- GIVEN an active set whose fragment row was altered out-of-band (trigger disabled by a superuser)
- WHEN the resolver loads it
- THEN it throws and no prompt is composed from it

#### Scenario: The seal is deterministic

- GIVEN the same payload published twice under different labels
- WHEN both seals are compared
- THEN they are equal

---

### Requirement: Per-Code Prompt Overrides

The system MUST support at most one override body per (prompt set, `role_code`, `competency_code`, `locale`), with
`role_code` OPTIONAL: a null role scopes the override to the competency across every role. Overrides MUST be keyed by
CODE, never by foreign-key id, because catalogue roles and competencies are cloned per catalogue revision. Uniqueness
MUST be enforced by two partial unique indexes (role NOT NULL, role NULL). Resolution MUST select at most one
override: a role-specific row wins over a role-less row, and they are never concatenated. A `potential` assessment
(no role) MUST resolve only role-less rows.

#### Scenario: A duplicate role-specific override is refused

- GIVEN an override for (S, FLL, INN, en)
- WHEN a second row for the same tuple is inserted
- THEN PostgreSQL raises `23505`

#### Scenario: A duplicate role-less override is refused

- GIVEN an override for (S, null, INN, en)
- WHEN a second row for the same tuple is inserted
- THEN PostgreSQL raises `23505`

#### Scenario: A role-specific override does not apply to another role

- GIVEN an override for (S, FLL, INN, en)
- WHEN resolution runs for role MLL, competency INN, `en`
- THEN no override is returned

#### Scenario: A role-less override applies to every role, and a role-specific one wins

- GIVEN a role-less override and a role-specific override for INN in `en`
- WHEN resolution runs for the role
- THEN only the role-specific body is returned, and for any other role only the role-less body

#### Scenario: A competency with no override resolves to none

- GIVEN no override row for the tuple
- WHEN resolution runs
- THEN the override is null and only the default fragments are available to compose

#### Scenario: An override keeps matching after the catalogue is cloned

- GIVEN an override for (S, FLL, INN, en) and a new catalogue revision whose roles and competencies have new ids
- WHEN resolution runs for the cloned FLL and INN
- THEN the override is found

---

### Requirement: Resolution Fails Loudly

`PromptSetResolver::resolveActive(locale, competencyCode, roleCode)` MUST throw
`PromptTemplateUnresolvableException` (a `CompositionException`) when there is no active set, when a key is missing or
unknown, when the active set has no rows for the locale, when the seal does not match, when more than one set is active, when a
set holds two rows for one identity or no rows at all, or when an override body breaks its contract. It MUST NOT fall
back to another set, another locale or the baseline text. Each failure MUST carry one machine-readable reason and a
message that names sets, keys and locales and never a template body. A failure of the infrastructure (for example a
database error) is not a resolution failure and MUST NOT be reported as one. The active set MUST be read with one indexed query on every
resolution; its fragments MAY be cached by (set id, locale) with no invalidation, because a set is immutable.

#### Scenario: No active set

- GIVEN no set is active
- WHEN the resolver runs
- THEN it throws `PromptTemplateUnresolvableException`

#### Scenario: Missing locale

- GIVEN the active set has no `it` rows
- WHEN the resolver runs for `it`
- THEN it throws; no `en` fragment is used instead

#### Scenario: Two active sets

- GIVEN two sets are active because the one-active index was bypassed
- WHEN the resolver runs
- THEN it throws and picks neither

#### Scenario: A duplicated row

- GIVEN the active set holds two rows for one (key, locale), or two overrides for one identity, inserted around the unique indexes
- WHEN the resolver runs
- THEN it throws

#### Scenario: Activating another set takes effect without clearing a cache

- GIVEN a resolution under S1 filled the cache and S2 is then activated
- WHEN the resolver runs again
- THEN it returns S2's fragments

---

### Requirement: Publishing And Activation Are Console Operations

A prompt set MUST be published with `beai:prompt-set:publish <file>` (options `--label`, `--notes`, `--dry-run`) and
activated with `beai:prompt-set:activate <label>`; both MUST run the placeholder contract and the completeness check,
and no HTTP route MUST exist for either in this change. Publishing MUST store the set inactive and MUST NOT activate
it; after inserting the set and its children it MUST read them back and verify them like a composition does, rolling
the transaction back on a mismatch. Console output MUST NOT print a template body.
`beai:prompt-set:dump-baseline` MUST write the baseline set as `database/prompt-sets/<label>.json` from
`BaselinePromptFragments`, deterministically, and MUST refuse to overwrite a file whose content differs: a stored set
is immutable, so a changed baseline is dumped under a new label.

#### Scenario: Publish refuses an invalid payload without side effects

- GIVEN an invalid payload
- WHEN `beai:prompt-set:publish` runs
- THEN it exits non-zero and no set, fragment or override row exists

---

### Requirement: The Baseline Set Is Bootstrapped By A Data Migration

A migration MUST insert the baseline set (label `baseline-1`), its fragments and its seal, and activate it when no
other set is active, so that every environment (including every `RefreshDatabase` test database) has an active set
after `migrate`; when another set is already active it MUST insert the baseline inactive and leave the incumbent
active. The migration MUST be idempotent keyed on the unique `label`: when the set exists it checks the stored seal
against the file and the stored rows, throws on any mismatch, and otherwise writes nothing. It MUST refuse a baseline
file that carries overrides, because the seal it freezes covers fragments only. It MUST NOT depend on a
seeder, because production never runs `DatabaseSeeder`. The baseline set MUST equal `BaselinePromptFragments` for `en`
and `it`, and the seal algorithm frozen in the migration MUST equal `PromptSetSeal`.

#### Scenario: A fresh database has an active baseline set

- GIVEN a database migrated from scratch
- WHEN the active set is read
- THEN the baseline set is active, complete for `en` and `it`, and its seal verifies

#### Scenario: Re-running the bootstrap writes nothing

- GIVEN the baseline set already exists
- WHEN the migration logic runs again
- THEN no row is inserted or changed and the seal is verified

#### Scenario: An operator's active set is not replaced by the migration

- GIVEN a set other than the baseline is already active
- WHEN the bootstrap migration runs
- THEN the baseline set is inserted inactive and the incumbent stays active

#### Scenario: The migrated set equals the baseline text

- GIVEN the migrated active set
- WHEN its fragments are compared with `BaselinePromptFragments`
- THEN they are equal for `en` and `it`

---

### Requirement: A Deploy Is Refused Without An Intact Active Prompt Set

`beai:deploy` MUST, right after its migrations and before any seeder, verify the active prompt set when
`conversation.prompt_source` is `db`, and MUST fail the deploy (fatal, non-zero exit) when the check fails. The check
MUST run the resolution `/start` runs for every locale in `app.supported_locales` and then verify the single active set
(seal, key set, placeholder contract, every override body). It MUST be skipped, with a warning, when the source is
`baseline`, and an unknown source value MUST fail the deploy. Adding a supported locale without publishing its
fragments therefore fails the deploy.

#### Scenario: A deploy with no active set is refused

- GIVEN the source is `db` and no set is active
- WHEN `beai:deploy` runs
- THEN it exits non-zero after the migrations and none of the seeders that follow runs

#### Scenario: A deploy with a tampered or incomplete set is refused

- GIVEN the active set fails its seal, lacks a supported locale, is active twice, or holds a broken override body
- WHEN `beai:deploy` runs
- THEN it exits non-zero and the output names the reason without printing a template body

#### Scenario: The baseline source skips the check

- GIVEN `CONVERSATION_PROMPT_SOURCE=baseline` and no stored set
- WHEN `beai:deploy` runs
- THEN the prompt set check is skipped with a warning and the deploy continues

#### Scenario: An unknown source value refuses the deploy

- GIVEN `CONVERSATION_PROMPT_SOURCE` holds a value that is neither `db` nor `baseline`
- WHEN `beai:deploy` runs
- THEN it exits non-zero rather than choosing a source

---

### Requirement: Prompt Tables Are Global

`conversation_prompt_sets`, `conversation_prompt_fragments` and `conversation_prompt_overrides` MUST carry no
`organization_id`, and their models MUST be listed in the exclusions of the tenant-model architecture test. Prompt
content is institutional interviewer instruction, identical for every tenant.

#### Scenario: No table carries organization_id

- GIVEN the three tables
- WHEN their columns are inspected
- THEN none is named `organization_id`
