# Delta for Framework Catalog

## ADDED Requirements

### Requirement: Prompt Overrides Are Keyed By Role And Competency Code, Not By Catalogue Row

Per-role and per-competency prompt overrides (owned by `conversation-prompt-templates`) MUST reference the catalogue
by `role_code` (nullable: a competency-wide override) and `competency_code`, never by a foreign key to
`framework_roles`, `framework_competencies` or `framework_bars_indicators`. Catalogue roles and competencies are cloned
per catalogue revision with new ids, so a code-keyed override survives a new revision unchanged, and opening, editing,
publishing or discarding a catalogue revision MUST NOT copy, remap, invalidate or require any override. The override
tables are global like the catalogue (no `organization_id`) and add no framework-version pin of their own: they inherit
the same versioning limits as the anchors they sit beside.

#### Scenario: The override schema has no foreign key into the catalogue and no organization

- GIVEN the prompt-override table
- WHEN its columns and constraints are inspected
- THEN it holds `role_code` and `competency_code` as plain strings, has no foreign key to any `framework_*` table, and has no `organization_id`

#### Scenario: A new catalogue revision does not touch overrides

- GIVEN an override for role FLL and competency INN and a draft revision opened from the baseline
- WHEN the draft is opened, edited and published
- THEN the override rows are unchanged and still resolve for the cloned FLL and INN
