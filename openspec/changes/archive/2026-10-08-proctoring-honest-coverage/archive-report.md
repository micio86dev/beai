# Archive Report: proctoring-honest-coverage

**Change**: proctoring-honest-coverage
**Archived to**: `openspec/changes/archive/2026-10-08-proctoring-honest-coverage/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED WITH ONE QUESTION CARRIED FORWARD (OQ-3). Proposal-only change: no delta specs,
no design, no tasks, no verify-report. No spec merge was performed.

## Summary

Proctoring now states what it did not measure instead of reporting "low risk" for an unobserved session: the
frontend stops shipping Git LFS pointers and emits `proctor_unavailable` when a detector fails to initialise;
the api accepts that kind and `IntegritySummarizer` carries coverage and withholds a reassuring band; the
backoffice renders "not measured". Observed on disk at archive time (all on the respective `develop`):

- api `adde060` ("feat(proctoring): stop reporting "low risk" for a session nobody observed", 2026-08-25).
- frontend `4cb73d7` ("fix(proctoring): stop shipping LFS pointers, and say so when a detector dies",
  2026-08-25).
- backoffice `dd36bd2` ("feat(review): render "not measured" instead of a risk band nobody measured",
  2026-08-25).

## Specs merged

None: the change has no delta spec.

## Carried forward (not closed)

- **OQ-3 - left open, deliberately.** `phone_detected` carries no weight in `IntegritySummarizer`. Re-read at
  archive time: `api/app/Services/Proctoring/IntegritySummarizer.php` `WEIGHT_PER_SECOND` still contains only
  `tab_hidden`, `face_absent`, `looking_away`, `multiple_faces` and `second_voice`, and a comment at line 86
  still places `phone_detected` and `looking_down` in the timeline but not the score. Whether that is still
  intended is a product decision about what the score means; it needs an owner.
- The proposal's out-of-scope excerpt relocation (requested by the owner the same day) is a separate change.

## Traceability

Mode openspec. Only proposal.md existed. Not verified in this pass: OQ-2's pinned and checksummed model
download in the frontend build was not re-inspected; the three commit subjects above were read, not their
diffs.

## Copy verification

Moved with `git mv` (no file rewritten). This report is additive.
