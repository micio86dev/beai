# Archive Report: per-project-avatar-template

**Change**: per-project-avatar-template
**Archived to**: `openspec/changes/archive/2026-10-08-per-project-avatar-template/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED BUT DIVERGED FROM THE PROPOSAL (see below). The proposal is a retrospective
document (it says so in its first paragraph); there is no design, no tasks, no delta spec and no verify-report.

## Summary

A project can pin the avatar template it runs on, instead of the organization's single active template per
provider silently deciding. Observed on disk at archive time:

- api `ae6d746` ("feat(projects): let each project choose its own avatar template", 2026-08-31) added the
  `projects.avatar_template_id` column (`2026_08_31_120000_add_avatar_template_id_to_projects.php`, nullable).
- api `5dfe960` ("feat(projects): make the avatar template required on every project", 2026-09-01), an ancestor of
  api `develop`, added `2026_09_01_120000_make_project_avatar_template_required.php`.
- `api/app/Support/AvatarTemplates/ActiveTemplateResolver.php` resolves the pinned template from
  `projects.avatar_template_id` (line 96).

## DIVERGENCE: the proposal's central decision was reversed the next day

The proposal's decision is "Add `projects.avatar_template_id`, **nullable**, with the organization-wide active
template as the fallback", chosen "over mandatory deliberately", and it requires `nullOnDelete` ("Deleting a
template must return its projects to the fallback, not delete them"). The shipped code differs:

- **The column is NOT NULL.** The migration `2026_09_01_120000_make_project_avatar_template_required.php` backfills
  every existing project with the template the fallback would have resolved for it, then runs
  `ALTER COLUMN avatar_template_id SET NOT NULL`. Its own docblock gives the reason: a project must always name
  the template it runs on, because leaving it implicit let the `INTERVIEW_PROVIDER` default silently choose.
- **The foreign key is `restrictOnDelete`, not `nullOnDelete`** (migration line 62; `nullOnDelete` survives only in
  `down()`, line 78). Deleting a template that a project uses is now refused, a real behaviour change the
  migration documents. This contradicts the proposal's "`nullOnDelete`, never cascade" section.
- `down()` cannot restore which rows were null before the backfill (recorded in the migration).

Consequently the proposal's "nullable with organization-active fallback" is NOT the delivered behaviour, and the
proposal text must not be read as the contract. What the proposal got right and still holds: the pin decides the
provider, `is_active` is not required of a pinned template, and tenancy is validated at write time. These were not
re-verified in code in this pass beyond the resolver line cited above.

Not verified: whether `ActiveTemplateResolver` still contains an organization-active fallback branch for a null pin
(the `pinnedFor()` helper returns null for a null id, which the NOT NULL column makes unreachable for real
projects).

## Specs merged

None: no delta spec. One edit to the canonical spec, made because the delivered feature makes it false:
`openspec/specs/avatar-templates/spec.md` "Out of Scope (C14)" no longer lists the "Per-project template
override" bullet (6 lines removed, nothing added; it still carried "Tracked as open item 7.2"). No requirement was
added for the per-project pin: the canonical spec (after the `pluggable-conversation-llm` merge) states "exactly one active template per
organization and provider", and has no requirement describing the pinned, required `projects.avatar_template_id`. That is a gap
for a human to decide.

## Not delivered / deferred

- The proposal's "Not in scope" item stands: `projects.provider_override` stays unexposed in the backoffice.
- A requirement for the project-level pin (required column, restrict-on-delete, precedence) is not written.

## Traceability

Mode openspec. Only proposal.md existed.

## Copy verification

Moved with `git mv` (no file rewritten). This report is additive.
