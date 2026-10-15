# Delta for avatar-templates

Change: `live-interview-call-chrome`. Adds one optional, candidate-facing persona field. Existing requirements
(export/import, activation, provider immutability) are unchanged; this requirement composes with them.

## ADDED Requirements

### Requirement: A template MAY carry an interviewer display name, shown to the candidate

An avatar template's `persona` MAY carry `display_name`: the name the candidate sees for the interviewer on the live
screen (before every caption). It is stored inside the existing `persona` JSON; it requires no new column.

Validation, on every write path (create, update, import):

- the value is optional; an absent, `null`, empty or whitespace-only value MUST be treated as **not set** and stored as
  absent, never as an empty string;
- a set value MUST be plain text of 1 to 60 characters after trimming surrounding whitespace;
- it MUST NOT contain control characters, nor `<` or `>` (no markup);
- because the value is candidate-facing, it MUST NOT name a specific avatar provider or its infrastructure (`HeyGen`,
  `LiveAvatar`, `Tavus`, `Daily`/`daily.co`, `LiveKit`), compared case-insensitively. This extends the provider-opacity
  rule of `interview-frontend` to operator-authored text;
- a violation MUST be reported as a validation error keyed on `persona.display_name`, together with every other field
  error of the same request, and MUST NOT persist the write.

The value MUST be copied unchanged by "duplicate template", MUST be carried by the JSON export, and MUST be validated by
the same rules on import. It is a candidate-facing display value, not an identifier: it need not be unique, and it MUST
NOT be sent to any avatar provider. An update of the template that carries a `persona` MUST change only `display_name` and
MUST keep every other key already stored in `persona` (for example keys an import brought in). The field is returned to
administrators by the admin avatar template resource (admin-only, classified in the exposure catalogue as
`avatar_template.persona.display_name`) and to the candidate only through the authenticated candidate interview outline; it
MUST NOT be added to the `/v1` public API.

#### Scenario: A valid name is stored

- GIVEN an admin saving a template with `persona.display_name = "  Giulia  "`
- WHEN the request is validated
- THEN the template is saved with `persona.display_name = "Giulia"`

#### Scenario: Clearing the field makes it absent

- GIVEN a template with `persona.display_name = "Giulia"`
- WHEN an admin saves it with the field empty
- THEN the stored persona carries no `display_name` key (not an empty string)

#### Scenario: A name that is too long is refused

- GIVEN a value of 61 characters
- WHEN the template is saved
- THEN the write is refused with a validation error on `persona.display_name` and nothing is persisted

#### Scenario: Markup and control characters are refused

- GIVEN the values `<b>Giulia</b>` and `Giu\nlia`
- WHEN each is saved
- THEN each is refused with a validation error on `persona.display_name`

#### Scenario: A provider name is refused in any case

- GIVEN the values `Tavus Coach`, `heygen` and `My LiveKit agent`
- WHEN each is saved
- THEN each is refused with a validation error on `persona.display_name`, and the message does not repeat the
  forbidden vendor name

#### Scenario: The error is reported with the other field errors

- GIVEN a request with an invalid `persona.display_name` and an invalid config field
- WHEN it is validated
- THEN the response lists both errors, each keyed on its own field

#### Scenario: Duplicating keeps the name

- GIVEN a template with `persona.display_name = "Giulia"`
- WHEN an admin duplicates it
- THEN the copy carries `persona.display_name = "Giulia"` and the original is unchanged

#### Scenario: Export and import round-trip the name

- GIVEN a template with `persona.display_name = "Giulia"`
- WHEN an admin exports it and imports the document
- THEN the imported template (inactive) carries `persona.display_name = "Giulia"`

#### Scenario: Import validates the name

- GIVEN a document whose persona carries `display_name = "Tavus"`
- WHEN it is imported
- THEN the import fails with a validation error on `persona.display_name` and no template is created

#### Scenario: The name never reaches the provider

- GIVEN a template with `persona.display_name = "Giulia"`
- WHEN a session is issued for it
- THEN no provider request body or header contains the display name

#### Scenario: The public API does not expose it

- GIVEN a template with `persona.display_name`
- WHEN the `/v1` public API responses are inspected
- THEN none contains the display name; the exposure catalogue (`T-EXPOSE-001`) gains exactly one admin-only entry,
  `avatar_template.persona.display_name`, because the admin avatar template resource is a classified surface, and the
  exposure test stays green

#### Scenario: The admin resource returns the name

- GIVEN a template with `persona.display_name = "Giulia"`
- WHEN an admin reads it through the avatar template resource
- THEN the response carries `persona.display_name = "Giulia"` and no other persona key

#### Scenario: Updating the name keeps the other persona keys

- GIVEN a template whose persona holds `display_name` and another key brought in by an import
- WHEN an admin saves a new `display_name`
- THEN the other key is still stored unchanged
