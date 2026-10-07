# Archive Report: potential-competencies-and-authored-questions

**Change**: potential-competencies-and-authored-questions
**Archived to**: `openspec/changes/archive/2026-10-08-potential-competencies-and-authored-questions/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED. Proposal-only change: no delta specs, no design, no tasks, no verify-report. No
spec merge was performed.

## Summary

`assessment_type: potential` became usable (MTG and LAT authored; `framework_bars_indicators.role_id` made
nullable, meaning "not role-scoped"), and the predefined interview questions became stored, editable, ordered
data per project and competency. Observed on disk at archive time:

- api `b7f0268` ("feat(framework): author MTG and LAT, and let potential projects exist", 2026-09-02) and
  `3018782` ("feat(projects): store, edit and reorder the predefined interview questions", 2026-09-02), both
  ancestors of api `develop`.
- `api/database/migrations/2026_09_02_170332_make_bars_indicator_role_nullable.php` makes `role_id` nullable and
  handles the uniqueness index for role-less rows.

## Specs merged

None: the change has no delta spec. Its requirements already live in the canonical specs, which were checked by
requirement title, not re-read in full: `project-config` ("Project Questions Layer" at line 615, "Deselecting A
Competency Soft-Deletes Its Questions; Reselecting Restores Them" at line 741), `interview-conversation`,
`admin-backoffice` and `catalogue-authoring` ("Catalogue-Level Default Questions Per Competency" at line 69).

## Candidate follow-up (not done)

The nullable `framework_bars_indicators.role_id` has no explicit requirement of its own. The only canonical
mention is a read-side one, `framework-catalog/spec.md:589` (`bars_available` for a potential competency is true
when it has at least one indicator row with `role_id IS NULL`). No requirement states the storage rule itself
(role-less indicators are legal, the uniqueness constraint for them, or that a role-bound row does not satisfy a
potential competency). It is a candidate for a small `framework-catalog` spec change; it was not written here.

## Traceability

Mode openspec. Only proposal.md existed.

## Copy verification

Moved with `git mv` (no file rewritten). This report is additive.
