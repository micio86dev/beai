# Candidate lifecycle

## States

State identifiers are literal enum values and are kept verbatim.

| State | Description | Typical transitions |
|-------|-------------|---------------------|
| *(null / not created)* | The candidate is not registered yet | → `in_attesa` on first SSO or API creation |
| `in_attesa` | Registered, interview not started | → `in_corso` |
| `in_corso` | Interview active | → `in_valutazione` |
| `in_valutazione` | Interview closed, scoring job running | → `completato` or `errore` |
| `completato` | Evaluation finished (definitive state, or a resolved pending) | → `in_attesa` only through the single evaluation retry (see below); otherwise none |
| `errore` | Technical or unrecoverable failure | → `in_attesa` only through the admin recovery action |

```
null ──► in_attesa ──► in_corso ──► in_valutazione ──► completato
             ▲  ▲          │              │               │
             │  └──────────┴──── errore ◄─┘               │
             │        (recovery action: errore → in_attesa)│
             └──────── evaluation retry (once, pending) ───┘
```

`completato` is therefore not terminal in exactly one case: a participant whose evaluation is
`pending` can be sent back to `in_attesa` by the retry authorization, and then runs the ordinary
lifecycle once more. No other path leaves `completato`.

> The state names are indicative. The supplier may use different naming as long as the semantics are equivalent.

## Data-read gates

| Resource | Minimum required state |
|---------|------------------------|
| Transcript | `in_valutazione` or `completato` |
| Structured evaluation | `completato` (with evaluation sub-state `completed` or `pending`) |

## Candidate uniqueness

- The **candidate identifier** must be unique within the defined context (globally or per project — to be documented in the technical specification);
- An attempt at duplicate creation → conflict error.

## Interview retry

- A retry is offered only for a participant in `completato` whose evaluation is in the `pending` state; exactly **one** retry is allowed per evaluation;
- The retry is **authorized** by an admin or operator in the backoffice, or by the calling system through the M2M API, through one shared action; it is never started by the candidate;
- Only the competencies that were **not valid** are re-interviewed; the valid results are kept as they are;
- Authorization moves the participant from `completato` back to `in_attesa` and gives the candidate a fresh single-use link. When BEAI emails the link (a real address) it is valid for 24 hours and is also returned to the authorizer; a link that is only returned (for example to a placeholder address) is valid for 30 minutes;
- While the retry is in progress the structured evaluation stays unreadable (it is readable only at `completato`);
- The outcome of the retry is **always** `completed` (definitive), whatever the ratio of valid competencies, the participant returns to `completato`, and the resulting evaluation webhook is delivered separately from the first `pending` one;
- There is no expiry or reminder: a retry that is authorized and never taken leaves the evaluation `pending` and the participant `in_attesa`.

## Deletion and retention

- Deleting an organization/project → cascade to candidates and assessment data (hard delete recommended for compliance);
- Retention policy for audio/transcripts: to be agreed with the client (GDPR).

## Relation to progress webhooks

Every significant transition (a new answer, a competency change) may generate a progress event towards external systems.
