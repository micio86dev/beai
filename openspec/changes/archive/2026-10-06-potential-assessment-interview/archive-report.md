# Archive Report: potential-assessment-interview

**Change**: potential-assessment-interview
**Archived to**: `openspec/changes/archive/2026-10-06-potential-assessment-interview/`
**Archive date**: 2026-10-06
**Status**: CLOSED WITH OPEN FOLLOW-UPS (see below). Verification: no verify-report existed; not run as an SDD phase.

## Summary

A `potential` project now composes and starts its interview through the same adaptive engine as
`standard` (role-less BARS lookup, no new template, `prompt_version` unchanged), the
assessment-type guard denies only unknown types, and a `potential` interview runs through the shared
scoring and completion gate. Owner decision: ADAPTIVE (the per-competency question count is a maximum).

## Final state at close (authoritative; outranks the stale unchecked boxes in `tasks.md`)

- api #124 (unlock, merge commit 682209a) and api #125 (end-to-end test, d858a34) are merged on develop.
- The below-gate `potential` retry end-to-end test was made real in api #135 (8b9a297).
- Docs aligned in wrapper #73 (20242ad).
- Tasks 4.5, 5.4 and 5.5 are unchecked in the archived `tasks.md` (a snapshot taken before those PRs
  merged); the work they describe landed in #124 and #125. The checkboxes were NOT rewritten.
- Tasks 6.4, 6.5 and 6.6 (archive-time spec edits) were applied by this archive pass.

## Specs merged

| Capability | Action | Requirements before -> after |
|---|---|---|
| interview-conversation | MERGED via `gentle-ai sdd-archive-compose` (exit 0) | 17 -> 23 as an intermediate count of this pass (6 added, 1 modified, 0 removed; the retry change then adds 1 more, final 24) |

Non-requirement edits applied (scripted, each with an exact one-match assertion): Purpose now reads
`standard` AND `potential`; the Out of Scope section (the deferred `potential` / SA-08 entry) is removed
in full; the Coverage Note gains role-less `potential` and the two ~95% paths (role-less `compose()`
path, assessment-type default-deny on fresh-start and resume); the clause "corrects this capability's
Out of Scope note" in "Potential Question Cap Is A Maximum, Never A Fixed Count" is trimmed to refer to
the earlier "4 fixed questions" phrasing, normative text and scenarios unchanged. "A Zero-Primary
Competency Never Reaches Interview" is byte-unchanged.

## Unfinished at archive (recorded, not done)

- **7.1** Wrapper submodule pointer bump (api) and **7.3** version / release: no release or tag is
  made until the owner asks. Pinned release tags are not recorded.
- **7.2 / 7.4**: not confirmed. Branch deletion of merged feature branches was not verified here.
- The HeyGen branches are unrelated and not yet published.

## Traceability

Mode openspec (no Engram observation IDs were read; artifacts were read from the filesystem).
proposal.md, exploration.md, design.md, tasks.md and one delta spec were present; no verify-report and
no apply-progress artifact were available.

## Copy verification

`cp -R` from the main checkout (original left in place) then `diff -r source destination`: empty
output, exit 0. This report is additive and excluded from that comparison.
