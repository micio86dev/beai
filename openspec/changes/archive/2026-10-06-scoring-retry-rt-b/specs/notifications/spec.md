# Delta for Notifications

The `notifications` capability today covers operator-facing C12 notifications only and
describes candidate-facing notification as a ratified non-goal. That statement predates
ruling 8 (reversed 2026-09-01: BEAI holds a mandatory candidate email) and ruling 10
(transactional email is standard, static and multilingual). The retry email below is a
TRANSACTIONAL candidate email, not a C12 trigger; the stale Purpose paragraph and Non-Goals
bullet are corrected at archive (see the change's non-requirement edit list).

## ADDED Requirements

### Requirement: The Evaluation Retry Email Is A Static Transactional Candidate Email

When an evaluation retry is authorized and the participant's address is deliverable (not a
placeholder, not a reusable-link visitor's self-declared address), BEAI MUST queue ONE
transactional email to the participant containing the fresh single-use retry link. It belongs
to the same family as the candidate invitation email (ruling 10): the template is static and
multilingual (`it` and `en`), uses placeholders only, and is NOT editable by tenant admins.
Per-tenant branding applies to the CHROME only (organization logo and primary colour); the
WORDS are the same for every tenant. The language MUST be the participant's interview language
(the language the link was minted with), with dates formatted in that language.

The email MUST:
- address the candidate by display name and name the organization and the project;
- explain, neutrally, that the candidate is invited to complete part of the interview again,
  without stating scores, outcomes, competency names or codes, the evaluation status, or any
  free-text `reason` the authorizer supplied;
- carry the retry link as an absolute URL and state that it is single-use and show its absolute
  expiry (24 hours after mint, taken from the token's own `exp`; the email is only sent when
  BEAI emails the link, which is exactly the case where the link has the 24-hour lifetime);
- differ from the first invitation email only in the subject, the intro and the expiry line
  (`candidate_invitation.retry.subject`, `.intro` and `.expiry`); every other line is shared;
- be sent by a queued job (the notification class being a pure renderer, never itself queued),
  registered by the authorization action itself after commit, so a mail-provider failure NEVER
  fails or rolls back the authorization and both HTTP surfaces get the email without any
  controller code. The job carries the link as a scalar; neither the action nor the job logs it.

The email MUST NOT be a C12 operator notification, MUST NOT be recorded in the C12
notification audit table, and MUST NOT introduce any time-triggered reminder (the retry has no
deadline, ratified decision 5). Exactly one email per authorization: a second authorization is
refused, so no second retry email can exist.

#### Scenario: A retry email is queued for a deliverable address

- GIVEN a successful retry authorization for a participant with a real email address and language `it`
- WHEN the authorization commits
- THEN exactly one email job is queued to that address
- AND the Italian template is rendered with the participant's display name, organization, project, link and absolute expiry

#### Scenario: The email follows the interview language

- GIVEN two participants, one with language `en` and one with `it`
- WHEN each retry email is rendered
- THEN the `en` participant receives English copy and the `it` participant Italian copy, and dates are formatted in each language

#### Scenario: Branding is chrome only

- GIVEN an organization with a logo and a primary colour
- WHEN the retry email is rendered
- THEN the logo and primary colour appear in the layout
- AND the body copy is identical to that of an organization with no branding

#### Scenario: The email reveals no evaluation content

- GIVEN a participant with a `pending` evaluation and an authorizer-supplied `reason`
- WHEN the retry email is rendered
- THEN it contains no score, no competency name or code, no evaluation status and no `reason` text

#### Scenario: Placeholder address gets no email

- GIVEN a participant whose email is a placeholder (legacy row or purged row)
- WHEN the retry is authorized
- THEN no email job is queued and the authorization response reports `email_sent: false`
- AND the link is still returned to the authorizer

#### Scenario: Reusable-link visitor gets no email

- GIVEN a participant created by a reusable interview link
- WHEN the retry is authorized
- THEN no email job is queued and `email_sent` is false

#### Scenario: A mail-provider failure does not fail the authorization

- GIVEN the mail transport fails when the queued job runs
- WHEN the job exhausts its bounded attempts
- THEN the participant stays `in_attesa` with the retry authorized and the returned link remains valid
- AND no second authorization is possible

#### Scenario: The retry email is not a C12 notification

- GIVEN a retry authorization
- WHEN the notification audit table is inspected
- THEN no C12 operator notification row exists for it

#### Scenario: Template is not tenant-editable

- GIVEN any organization admin
- WHEN they look for a way to edit the retry email text
- THEN no endpoint or setting exists to change it
