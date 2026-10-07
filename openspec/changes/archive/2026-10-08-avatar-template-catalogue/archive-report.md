# Archive Report: avatar-template-catalogue

**Change**: avatar-template-catalogue
**Archived to**: `openspec/changes/archive/2026-10-08-avatar-template-catalogue/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED WITH ONE OPEN VERIFIED-RISK (task 5.2). No verify-report existed; verification was
not run as an SDD phase. `tasks.md` had 38 tasks checked and 2 unchecked at archive time: 5.2 (left unchecked,
below) and 5.3 (this archive; ticked after the merge and the move).

## Summary

The provider voice/avatar/replica catalogue for avatar templates: a cached, admin-only read endpoint, field specs
that name their catalogue resource, and a searchable picker in the backoffice form. Delivered in four PRs.
Observed on disk at archive time:

- api `22a76a2` ("feat(avatar-templates): add cached provider catalogue endpoint", PR 1) and `0a42806`
  ("feat(avatar-templates): add catalogue_resource metadata to field specs", PR 2, merged as #76), both on api
  `develop`. `api/app/Support/AvatarTemplates/AvatarProviderCatalogue.php` exists and
  `api/routes/api.php:610` routes `GET /avatar-templates/catalogue`; `FieldSpec.php` carries
  `catalogue_resource`; `api/tests/Feature/C14/AvatarTemplateCatalogueTest.php` exists.
- backoffice PR 3 (#35) and PR 4 (#36, merge `9735a3b`) merged on backoffice `develop`; later fixes `aebd761`
  and `b168e8b` rebuilt and hardened the picker.

## Specs merged

Composition used `gentle-ai sdd-archive-compose` (exit 0).

| Capability | Requirements before -> after | Delta |
|---|---|---|
| avatar-templates | 13 -> 14 | 1 added ("Provider catalogue is fetchable, cached, admin-only, and never leaks a secret"), 1 modified ("Field specs are served machine-facing, not localized text") |

`git diff --stat`: 129 insertions, 7 deletions. The 7 deleted lines are the modified requirement's old body; the
composer re-wrapped that paragraph from the delta text.

### Observation for human review (not edited)

`openspec/specs/avatar-templates/spec.md` section "Out of Scope (C14)" still lists "An avatar/voice catalogue"
(open item 7.3) as deferred. The merged delta states, in an informational note, that this deferral is answered
by this change. That bullet is now stale; it was left untouched because the delta says "not a requirement
change". Binding a third-party TTS secret (so each provider's catalogue contains an Italian voice) remains a
separate future decision.

## Not delivered / deferred

- **Task 5.2 (left unchecked) - OPEN VERIFIED-RISK.** The residual risk of design decision D5 (whether catalogue
  preview/CDN URLs expire) was never reconfirmed live. It needs provider credentials (a HeyGen/Tavus key) that
  the implementing session could not read. The change proceeded on the earlier recorded observation in
  `design.md` D5 ("plain CDN URLs ... nothing indicated a short expiry"). This is an open gap, not a
  confirmed-safe result.

## Traceability

Mode openspec. Artifacts read from the filesystem: proposal.md, design.md, tasks.md, one delta spec. Absent:
verify-report, apply-progress, exploration.md.

## Copy verification

Moved with `git mv`. After the move, only the 5.3 checkbox in the archived `tasks.md` was ticked (`[ ]` to `[x]`,
same line count); nothing else in the folder was edited. This report is additive.
