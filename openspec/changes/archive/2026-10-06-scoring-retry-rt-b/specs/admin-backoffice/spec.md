# Delta for Admin Backoffice

## ADDED Requirements

### Requirement: Link Disclosure Never Hard-Codes A Lifetime

Any copy that discloses an entry-link or retry-link expiry MUST render the absolute expiry taken
from the response's `expires_at`, and MUST NOT state a fixed duration ("30 minutes", "24 hours")
in static translation text. A link minted by the operator entry-link action lives 24 hours when
its invitation email is queued and 30 minutes when it is not, so a fixed duration in the
disclosure is false for one of the two cases. The existing single-use statement and the
single-use panel structure remain unchanged (Requirement: Single-Use and Expiry Are Disclosed
Before the Copy). The `it` and `en` strings MUST convey the same meaning.

#### Scenario: Disclosure shows the absolute expiry and no fixed duration

- GIVEN a newly minted entry link whose `expires_at` is 24 hours away
- WHEN the disclosure renders
- THEN it states the link is single-use and shows the absolute expiry
- AND the rendered text contains no fixed "30 minutes" wording

#### Scenario: A link that was not emailed also shows the right expiry

- GIVEN a newly minted entry link with `email_sent = false` and `expires_at` 30 minutes away
- WHEN the disclosure renders
- THEN the absolute expiry shown equals `expires_at`

#### Scenario: Italian and English carry the same meaning

- GIVEN the locale is `it`, then `en`
- WHEN the disclosure renders
- THEN both state single-use and the absolute expiry and neither contains a fixed duration

### Requirement: Operator Evaluation Retry Panel

The participant detail view MUST render an evaluation-retry panel for participants that have a
retry state, and MUST NOT render it for participants with none (a participant whose Evaluation
is `completed` without a retry, or with no Evaluation). The panel states are driven by the
read API's `retry_available`, `retry_attempt`, `retry_authorized_at` and the literal `status`:

| State | Condition | Panel |
|---|---|---|
| Available | `retry_available = true` | Authorize action (see below) |
| Waiting | `retry_attempt = true` and `status = in_attesa` | "Authorized at {date}; waiting for the candidate to re-interview" |
| In progress | `retry_attempt = true` and `status = in_corso` | "Re-interview in progress" |
| Scoring | `retry_attempt = true` and `status = in_valutazione` | "Scoring the re-interview" |
| Finished | `retry_attempt = true` and `status = completato` | "Retry completed; the evaluation is definitive" |

The authorize action MUST be rendered only for `admin` and `operator` (gated by the abilities
contract's retry flag) and MUST NOT be rendered for `viewer`; the API's `403` is still enforced
independent of any UI state. Triggering it MUST open a consequence-driven confirm dialog
(see Requirement: Consequence-Driven Confirmation On State-Changing Actions) stating that: the
candidate will re-answer only the competencies that could not be validated, and any answer already
recorded for those competencies is permanently deleted at authorization; the evaluation is
unreadable until the re-interview is scored; the retry can be authorized only once and cannot be
withdrawn; a single-use link will be created and, when the candidate has a deliverable address,
emailed. The dialog MUST offer an optional free-text `reason` (max 500 characters) bound to the
request body, and no request is sent until the operator confirms.

On success the panel MUST show, in the same view as the copy affordance: the link (with a Copy
control), the single-use statement, the absolute expiry from `expires_at`, and the email status
from `email_sent` ("Email sent to the candidate" / "No email was sent — give the candidate this
link yourself"). The link is shown ONCE: it is never stored, so after the view is dismissed the
panel MUST NOT offer to display it again, and the retry link view itself offers no re-issue
control; a fresh link is obtained through the existing entry-link action of the participant page,
which works while the participant is `in_attesa`. The panel MUST NOT claim that any earlier link
was revoked.

The panel is gated by the retry flag of the abilities contract, delivered to it as a `canRetry`
input that the participant page derives from the shared current-user state.

On a 409 refusal the panel MUST render the refusal with i18n-keyed copy mapped from the response
`reason` (`retry_already_consumed`, `not_completed`, `test_mode_participant`,
`evaluation_not_pending`, `project_inaccessible`; five keys, plus an `unknown` fallback for any
other value), never the raw machine string, and MUST disable the action. All panel
copy MUST exist in `it` and `en`.

#### Scenario: The action appears only for an eligible participant

- GIVEN a participant at `completato` with `retry_available = true`
- WHEN the detail page renders for an admin
- THEN the authorize action is visible
- WHEN the same page is viewed for a participant whose Evaluation is `completed`
- THEN the retry panel is not rendered

#### Scenario: A viewer never sees the action

- GIVEN a signed-in `viewer`
- WHEN they open an eligible participant's detail
- THEN the authorize action is not rendered

#### Scenario: Confirming states the consequences and sends nothing until confirmed

- GIVEN the confirm dialog is open
- WHEN it renders
- THEN it states the invalid-only re-interview, the unreadable evaluation, the single-use-once nature, and the email behavior
- AND no request is sent until the operator confirms

#### Scenario: The optional reason is sent in the request body

- GIVEN the operator types a reason of 40 characters and confirms
- WHEN the request is sent
- THEN the body carries that `reason`
- AND confirming with an empty reason sends no `reason`

#### Scenario: Success shows the link, the expiry and the email status once

- GIVEN a successful authorization returning `entry_url`, `expires_at` and `email_sent: true`
- WHEN the panel updates
- THEN the link, a Copy control, the single-use statement, the absolute expiry and "email sent" are visible together
- AND after the view is dismissed the link cannot be shown again

#### Scenario: No email was sent

- GIVEN a successful authorization returning `email_sent: false`
- WHEN the panel updates
- THEN it tells the operator no email went out and that they must hand the link to the candidate

#### Scenario: Retry state follows the participant status

- GIVEN a participant with `retry_attempt = true` at each of `in_attesa`, `in_corso`, `in_valutazione`, `completato`
- WHEN the detail renders in each case
- THEN the panel shows the Waiting, In progress, Scoring and Finished state respectively
- AND the Waiting state shows the authorization date

#### Scenario: A refused authorization renders its reason

- GIVEN an authorization returns HTTP 409 with `reason: "project_inaccessible"`
- WHEN the response is handled
- THEN the action becomes disabled and shows i18n-keyed copy for that reason

#### Scenario: Every refusal reason has its own copy

- GIVEN the five refusal reasons `retry_already_consumed`, `not_completed`,
  `test_mode_participant`, `evaluation_not_pending` and `project_inaccessible`
- WHEN each is returned as a 409
- THEN each maps to its own i18n key in both locales and none shows the raw machine string

#### Scenario: Retry copy exists in Italian and English

- GIVEN the locale is `it`, then `en`
- WHEN the panel and dialog render in every state
- THEN every string is translated and neither locale falls back to the other

### Requirement: The Abilities Contract Exposes The Retry Capability

The authenticated user's abilities contract (the `UserAbilities` resource consumed by the
backoffice) MUST carry a boolean retry flag derived from `ParticipantPolicy::retry`: true for
`admin` and `operator`, false for `viewer`. The flag is the `participants.retry` entry of the abilities map. The backoffice MUST read it from
the shared current-user state (fetched once) and MUST NOT infer the capability from the role name. The
regenerated typed client MUST contain the new endpoint and the new fields; types are never
hand-maintained.

#### Scenario: Admin and operator get the flag, viewer does not

- GIVEN users with the `admin`, `operator` and `viewer` roles
- WHEN the abilities contract is read for each
- THEN the retry flag is true, true and false respectively

#### Scenario: The UI gate follows the flag

- GIVEN a user whose retry flag is false
- WHEN the participant detail renders for an eligible participant
- THEN the authorize action is absent

#### Scenario: Generated client parity

- GIVEN the API's regenerated `openapi.json` containing the retry route and the read-API fields
- WHEN the backoffice client is regenerated
- THEN the generated types contain them and the parity check passes

### Requirement: The Retry Flow Has End-To-End Coverage

Playwright MUST cover, on Chromium and WebKit, the operator retry journey: an eligible participant,
authorize with a reason, see the link, expiry and email status once, and see the Waiting state
afterwards; and a viewer seeing no action. Vitest MUST cover the panel states, the 409 mapping
and the abilities gate.

#### Scenario: Operator journey

- GIVEN a seeded `pending` evaluation participant and an operator session
- WHEN the operator authorizes the retry through the dialog
- THEN the link panel appears and, after dismissal, the panel shows the Waiting state

#### Scenario: Viewer journey

- GIVEN the same participant and a viewer session
- WHEN the detail page opens
- THEN no authorize action exists
