# Delta for Interview Conversation

## ADDED Requirements

### Requirement: OpeningTextComposer Re-Interview Variant (Neutral)

When a competency is asked again because an evaluation retry (RT-B) reset its session, the
`OpeningTextComposer` MUST compose the opening greeting under a NEW neutral `reinterview`
variant, distinct from the existing `retry` variant. The existing `retry` variant (bounded
single re-offer after a provider error) apologizes for a technical failure and MUST NOT be
used for an evaluation retry: the candidate did nothing wrong and nothing broke. The
`reinterview` variant MUST tell the candidate, neutrally, that they are continuing the interview
with the remaining topics, MUST NOT apologize, MUST NOT mention scores, evaluation results,
"invalid" or "failed" competencies, and MUST NOT read as a first-time greeting. Locale keys MUST
exist for at least `it` and `en` alongside `opening.first` / `.next` / `.resume` / `.retry`.
It MUST respect the existing anti-leak rule (no BARS anchor or indicator text) and MUST carry a
`prompt_version`.

Variant precedence, highest first: `resume` > `retry` > `reinterview` > `first` > `next`. A
session that is being resumed mid-conversation (a live `in_corso` session, which re-issues the
provider session) keeps `resume`; a session that ALSO qualifies for the bounded provider-error
re-offer (it ended in `error` during the re-interview and was re-offered) keeps the existing
`retry` variant; otherwise, whenever the participant's Evaluation has `retry_attempt = true`
(read org-scoped, through the ambient tenant scope), the `reinterview` variant applies. Sessions
of the first interview, and every participant without an authorized retry, MUST keep the
`first` / `next` / `resume` / `retry` selection exactly as before.

This variant needed production code (an additional opening key and a controller arm), which
supersedes the design's earlier claim that the neutral re-interview opening needed none: a
session reset to `pending` otherwise resolves to `next`, the authored primary verbatim with no
greeting. The variant is wording only: it does not change the composed system prompt, and
`conversation.prompt_version` is NOT bumped for it.

#### Scenario: A retry-reset competency composes the reinterview variant

- GIVEN a competency session reset to `pending` by an evaluation retry authorization
- WHEN `OpeningTextComposer.compose()` runs for its `/start`
- THEN the `reinterview` variant is selected, not `first`, `next`, `resume` or `retry`

#### Scenario: The reinterview copy exists in it and en and does not apologize

- GIVEN the `reinterview` variant for a project with `language = 'it'` and, separately, `'en'`
- WHEN `opening_text` is composed
- THEN a non-empty, language-correct string is produced for both locales
- AND it contains no apology wording and no reference to scores, results or failed competencies

#### Scenario: The reinterview copy leaks no BARS content

- GIVEN a competency with BARS indicators, reset by a retry
- WHEN `opening_text` is composed under the `reinterview` variant
- THEN it contains no indicator or anchor text

#### Scenario: A mid-conversation resume inside a retry keeps the resume variant

- GIVEN a competency reset by an evaluation retry whose re-interview session is `in_corso` and is resumed
- WHEN its opening is composed
- THEN the existing `resume` variant is selected, not `reinterview`

#### Scenario: A provider-error re-offer inside a retry keeps the retry variant

- GIVEN a competency reset by an evaluation retry whose session then ended in `error` and was re-offered by the bounded single re-offer
- WHEN its opening is composed
- THEN the existing `retry` variant is selected

#### Scenario: First-interview competencies are unaffected

- GIVEN a participant with no evaluation retry
- WHEN any opening is composed
- THEN the variant is selected exactly as before and is never `reinterview`
