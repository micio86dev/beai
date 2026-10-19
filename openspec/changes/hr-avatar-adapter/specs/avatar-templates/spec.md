# Delta for Avatar Templates

Adds `hr_avatar` as a third template provider, gated on the integration being available, plus the nullable
`hr_avatar_config_id`. Existing HeyGen and Tavus requirements are not changed except for the immutability
requirement, which names the set of providers. See `hr-avatar-integration` for availability, the proxy
and the export command.

## ADDED Requirements

### Requirement: hr_avatar is a template provider only while HR-Avatar is available

`hr_avatar` MUST be accepted as a template `provider` on create and import only when the HR-Avatar
integration is available. When it is unavailable, `provider = 'hr_avatar'` MUST be rejected with 422
exactly like an unknown provider name, and nothing MUST be persisted.

The field-specs endpoint (`GET /api/avatar-templates/field-specs`) MUST contain an `hr_avatar` key if and
only if the integration is available. That key is the capability signal consumed by the backoffice. Its
value is an empty field list: an `hr_avatar` template accepts no provider knobs, and any key submitted in
its `config` MUST be reported as `unknown` (keyed `config.{knob}`, with every error at once). When the
integration is unavailable the endpoint MUST return exactly the object it returned before this change
(keys `heygen` and `tavus` only).

On create, `config` MUST remain required for `heygen` and `tavus` exactly as today (same 422 key,
status and message text) and MUST be optional for `hr_avatar`, where an omitted `config` is stored as
`{}` (amendment A6). All field errors of an `hr_avatar` create, including the config-id format and
every `unknown` config key, MUST be returned together in one 422.

An existing `hr_avatar` template MUST remain readable, editable (name and persona), duplicable and
deletable while the integration is unavailable. Its activation MUST be refused with 422 while the
integration is unavailable, because a session on it would fail closed.

#### Scenario: Create is accepted when available

- GIVEN the integration is available
- WHEN an admin posts a template with `provider = 'hr_avatar'` and a valid `hr_avatar_config_id`
- THEN the response is 201 and the template is inactive

#### Scenario: Create is refused when unavailable

- GIVEN the integration is unavailable
- WHEN an admin posts a template with `provider = 'hr_avatar'`
- THEN the response is 422 on `provider` and no row is created

#### Scenario: Field specs expose the capability only when available

- GIVEN the integration is available
- WHEN an admin reads the field specs
- THEN the data object has keys `heygen`, `tavus` and `hr_avatar`, and `hr_avatar` is an empty list

#### Scenario: Field specs are unchanged when unavailable

- GIVEN the integration is unavailable
- WHEN an admin reads the field specs
- THEN the data object has exactly the keys `heygen` and `tavus` and equals its pre-change value

#### Scenario: Config may be omitted for hr_avatar only

- GIVEN the integration is available
- WHEN an admin creates an `hr_avatar` template without `config`, and separately a `tavus` template without `config`
- THEN the first is 201 with `config` stored as `{}`, and the second is 422 on `config` with the same message text as before this change

#### Scenario: hr_avatar config accepts no knobs

- GIVEN an `hr_avatar` template payload whose `config` contains `{"avatarId": "x", "nonsense": 1}`
- WHEN it is submitted
- THEN the response is 422 carrying `config.avatarId` and `config.nonsense` as separate `unknown` entries

#### Scenario: Activation is refused while unavailable

- GIVEN an existing `hr_avatar` template and the integration unavailable
- WHEN an admin activates it
- THEN the response is 422 and `is_active` remains false

#### Scenario: Existing hr_avatar template stays manageable while unavailable

- GIVEN an existing `hr_avatar` template and the integration unavailable
- WHEN an admin renames it, a superadmin duplicates it (duplication is superadmin-only), then the copy is deleted
- THEN each request succeeds

### Requirement: An hr_avatar template stores an opaque HR-Avatar config id

`avatar_templates` MUST gain a nullable string column `hr_avatar_config_id`: the opaque `avc_…` id of an
HR-Avatar avatar config. It MUST have no foreign key (it points into another service). A write that
carries the field MUST validate it as null or a string matching `^avc_[0-9A-Za-z]+$` of at most 64
characters, reported as `hr_avatar_config_id` together with every other field error of the request. For a
template whose provider is `hr_avatar` the field MUST be required on create and import, and an update MUST
NOT be able to clear it. For `heygen` and `tavus` templates the field MAY be present (the export command
fills it), is ignored by provider behaviour, and its presence MUST NOT change the HeyGen or Tavus payload.

BEAI-side LLM binding does not apply to `hr_avatar` templates: a non-null `llm_model_id` or
`llm_credential_id` on an `hr_avatar` template MUST be refused with 422 keyed on that field.

The column MUST be tenant-scoped like the rest of the row: another organization's template, and therefore
its id, MUST resolve as 404 and MUST never appear in a listing, export or duplicate. Writing the field
MUST NOT make any HTTP request (no existence check against HR-Avatar).

The value MUST be exposed by the admin `AvatarTemplateResource` and carried by the JSON export, and MUST
be validated by the same rule on import, but only when it is not null: a null value MUST omit the member
from the resource and the export document, so existing outputs are unchanged. The export schema
identifier is unchanged; the member is optional. "Duplicate template" MUST copy the value.

#### Scenario: Valid id is stored and returned

- GIVEN an `hr_avatar` template payload with `hr_avatar_config_id = "avc_01HXYZ"`
- WHEN an admin creates it
- THEN the response resource carries `hr_avatar_config_id = "avc_01HXYZ"`

#### Scenario: Config id is required for hr_avatar

- GIVEN a payload with `provider = 'hr_avatar'` and no `hr_avatar_config_id`
- WHEN it is submitted
- THEN the response is 422 keyed on `hr_avatar_config_id`

#### Scenario: Malformed id is refused with the other errors

- GIVEN a payload with `hr_avatar_config_id = "cfg_1"` and an unknown config key
- WHEN it is submitted
- THEN the response lists `hr_avatar_config_id` and the config error, each under its own key

#### Scenario: An update cannot clear the id

- GIVEN an `hr_avatar` template with an id
- WHEN an admin PATCHes `hr_avatar_config_id` to null
- THEN the response is 422 and the stored id is unchanged

#### Scenario: LLM binding is refused

- GIVEN a payload with `provider = 'hr_avatar'` and a non-null `llm_model_id`
- WHEN it is submitted
- THEN the response is 422 keyed on `llm_model_id`

#### Scenario: No outbound request on write

- GIVEN `Http::preventStrayRequests()`
- WHEN an `hr_avatar` template is created, updated, activated, duplicated and deleted
- THEN no HTTP request is sent to HR-Avatar, Tavus, HeyGen or any voice provider (no PAL sync, no voice or LLM registration)

#### Scenario: Null id is omitted from outputs

- GIVEN a tavus template with null `hr_avatar_config_id`
- WHEN it is read through the resource and exported
- THEN the member `hr_avatar_config_id` is absent from both

#### Scenario: Tavus template can carry an id without changing its payload

- GIVEN a tavus template whose `hr_avatar_config_id` was set by the export command
- WHEN a session is issued for it
- THEN the Tavus request body is identical to that of the same template without the id

#### Scenario: Export and import round-trip the id

- GIVEN an `hr_avatar` template with an id, and the integration available
- WHEN an admin exports it and imports the document
- THEN the imported template (inactive) carries the same `hr_avatar_config_id`

#### Scenario: Import refuses an hr_avatar block when unavailable

- GIVEN a document with an `hr_avatar` provider block and the integration unavailable
- WHEN it is imported
- THEN the import fails with a validation error and no template is created

#### Scenario: Duplicate keeps the id

- GIVEN an `hr_avatar` template with an id
- WHEN an admin duplicates it
- THEN the copy carries the same id and the original is unchanged

#### Scenario: Another tenant's id is never readable

- GIVEN organization B has an `hr_avatar` template with id `avc_B`
- WHEN an admin of organization A lists, reads, duplicates and exports templates, and requests B's template by id
- THEN `avc_B` appears nowhere and B's template by id is a 404

### Requirement: The backoffice template form offers hr_avatar and a config picker only when the api reports it

The backoffice avatar template form MUST derive its provider options from the keys of the served field
specs instead of a hardcoded list. The `hr_avatar` option MUST be shown if and only if the field specs
contain an `hr_avatar` key; when it does not, the option list MUST be exactly the existing `heygen` and
`tavus` options in their existing order.

When the selected provider is `hr_avatar`, the form MUST render an HR-Avatar config picker fed by the
catalogue proxy (`provider=hr_avatar`, `resource=avatar_config`) and MUST store only the chosen `avc_…`
id as `hr_avatar_config_id`. It MUST render no provider knob controls and no LLM binding controls. When
the proxy answers with `status` other than `ok` (including `empty`), the picker MUST degrade to manual
entry of the id, so the form is never blocked. The provider remains immutable after creation, so the
option is selectable only on create. All new copy MUST be i18n-keyed in both `it` and `en`.

#### Scenario: Option hidden when not reported

- GIVEN field specs with keys `heygen` and `tavus` only
- WHEN the form renders
- THEN the provider options are exactly `heygen` and `tavus`, in that order, and no picker is rendered

#### Scenario: Option and picker shown when reported

- GIVEN field specs with keys `heygen`, `tavus` and `hr_avatar`
- WHEN an admin selects `hr_avatar`
- THEN the picker is rendered, lists the catalogue items, and selecting one sets `hr_avatar_config_id` to its `id`

#### Scenario: Only the association is stored

- GIVEN the admin picked a config labelled "Interviewer"
- WHEN the form is submitted
- THEN the payload carries `provider`, `name` and `hr_avatar_config_id` and no copy of the config's label or settings

#### Scenario: Degraded proxy falls back to manual entry

- GIVEN the proxy answers `status = provider_error`
- WHEN the picker renders
- THEN a text control accepts an `avc_…` id and submission is possible

#### Scenario: Server validation errors are placed per field

- GIVEN the api answers 422 keyed on `hr_avatar_config_id`
- WHEN the form handles it
- THEN the message renders under the picker control via the shared mapper, without parsing message text

#### Scenario: Provider cannot be changed on edit

- GIVEN an existing `hr_avatar` template
- WHEN the edit form renders
- THEN the provider is shown but not editable

## MODIFIED Requirements

### Requirement: Provider is immutable after creation

Once a template is created with a `provider` (`heygen`, `tavus` or `hr_avatar`), that value
MUST NOT be changeable via `PATCH /api/avatar-templates/{id}`. A request that
includes a `provider` field differing from the template's current provider
MUST be rejected with 422, and the stored provider MUST remain unchanged.

Changing the provider on an existing template would leave the config validated
and populated for the OLD provider's field names (e.g. `avatarId`, `voiceId`)
sitting under the new provider's spec, where none of those keys are recognised
— the config would validate as effectively empty and the session would
silently fall back to environment defaults with no error surfaced anywhere.
Creating a new template instead is one click and leaves an audit trail; PATCHing
the provider in place would not.
(Previously: named only `heygen` and `tavus`.)

#### Scenario: A PATCH cannot change the provider

- GIVEN a template with `provider = 'heygen'`
- WHEN `PATCH /api/avatar-templates/{id}` is called with `{"provider": "tavus"}`
- THEN the response is 422 and the template's `provider` remains `'heygen'`

#### Scenario: A PATCH cannot convert a template to or from hr_avatar

- GIVEN a template with `provider = 'tavus'`, and separately one with `provider = 'hr_avatar'`
- WHEN `PATCH /api/avatar-templates/{id}` is called with `{"provider": "hr_avatar"}` on the first and `{"provider": "tavus"}` on the second
- THEN both responses are 422 and both stored providers are unchanged
