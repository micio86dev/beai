# Delta for admin-backoffice

Change: `live-interview-call-chrome`. One additive input on the existing avatar template form. Ships in the SAME
release as the api change that validates the field (owner decision O3).

## ADDED Requirements

### Requirement: The avatar template form exposes an optional interviewer display name

The avatar template form MUST render a text input for `persona.display_name`, labelled "Nome dell'intervistatore"
(en: "Interviewer display name"), in both the create and the edit flows, in the same section as the other persona
fields. The form MUST:

- state in helper text that the name is shown to candidates before every caption and is optional (when empty the
  candidate sees the generic label "Intervistatore AI" / "AI interviewer");
- limit the input to 60 characters;
- treat a cleared input as **absent** (omit the key from the payload), consistent with how the form treats other cleared
  fields, and never send an empty string;
- load the stored value when editing and round-trip it unchanged, together with the rest of the persona, when the
  operator saves without touching it;
- display the API's validation error keyed on `persona.display_name` next to the input, associated with it for assistive
  technology, without discarding what the operator typed;
- use only `it`/`en` strings from the locale files, with the field label programmatically associated with the input.

The input MUST be available only where the template form already is (admin-only, as for every template write).

#### Scenario: The input is present and labelled in both languages

- GIVEN an admin opens the template form in Italian, then in English
- WHEN the persona section renders
- THEN an input labelled "Nome dell'intervistatore" (en: "Interviewer display name") is present with helper text, and
  its label is associated with the input

#### Scenario: A value is saved and reloaded

- GIVEN an admin enters "Giulia" and saves
- WHEN the template is reopened for editing
- THEN the input shows "Giulia"

#### Scenario: Clearing sends no key

- GIVEN a template saved with "Giulia"
- WHEN the admin clears the input and saves
- THEN the request payload carries no `persona.display_name` key and no empty string

#### Scenario: Saving without touching the field preserves it

- GIVEN a template with a display name and other persona fields
- WHEN the admin edits an unrelated field and saves
- THEN the payload carries the same `persona.display_name` and the other persona fields unchanged

#### Scenario: The input is length-limited

- GIVEN the admin types 80 characters
- WHEN the input is inspected
- THEN it holds at most 60 characters

#### Scenario: A server validation error is shown on the field

- GIVEN the API refuses the save with a validation error on `persona.display_name`
- WHEN the form receives it
- THEN the message is shown next to the input and associated with it, the typed value is kept, and no other field is reset

#### Scenario: No literal strings outside the locale files

- GIVEN the new label, helper text and error copy
- WHEN the locale files and the form source are inspected
- THEN every string resolves from `it` and `en` entries, with a pair for each key
