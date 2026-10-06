# Evaluation rules

## Competency validity threshold

For an evaluation to be considered **valid** (`completed`), the candidate must reach a sufficient number of "valid" competencies (those with enough evidence for reliable scoring).

| Parameter | Current value |
|-----------|----------------|
| Threshold | **90%** of the project's competencies |
| Example | 12 competencies → at least **11** valid |

If the threshold is **not** reached → evaluation status `pending`.

## Evaluation states (webhook / export)

| State | Meaning | Suggested portal action |
|-------|-------------|--------------------------|
| `completed` | Definitive evaluation | Show the results, close the cycle |
| `pending` | Evaluation processed but coverage insufficient | Show the partial data; an admin, an operator or the calling system may authorize the single retry |

**Note:** even in the `pending` state, the evaluation **is still sent** (with the data available). It is not a technical error.

## When `completed` is reached

1. The candidate reaches the minimum threshold of valid competencies; **or**
2. The single retry has run: its outcome is always `completed`, whether or not the threshold is reached.

## Retry handling

| Rule | Value |
|--------|--------|
| Retry attempts per candidate | **1** |
| Retry trigger | An evaluation in the `pending` state, authorized by an admin/operator or by the calling system (never by the candidate) |
| Scope of the retry | Only the competencies that were not valid are re-interviewed |
| Retry outcome | The evaluation is always marked `completed` (definitive, whatever the ratio of valid competencies) |

The full participant-side rules (state transitions, link validity, no expiry) are in `01-candidate-lifecycle.md`.

## Per-competency reliability

Every competency in the report carries a **reliability** indicator (e.g. a percentage or a qualitative value) reflecting:
- the quantity of answers collected;
- the depth of the answers;
- the consistency of the evidence against the BARS indicators.

A competency whose reliability is too low may not count towards the 90% threshold.

## Timing

- The evaluation starts **immediately** after the interview closes;
- Typical processing time: **a few minutes**;
- It is not tied to the exact moment the candidate pressed "finish" (there may be a queue).

## Minimum report content

For every assessed competency, the report must include at least:
- the overall score;
- at least one indicator with score, explanation and excerpt;
- the reliability indicator.

Reference: `../03-ux-reference/evaluation-report-example.json`.
