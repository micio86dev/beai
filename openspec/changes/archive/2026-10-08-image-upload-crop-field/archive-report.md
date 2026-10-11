# Archive Report: image-upload-crop-field

**Change**: image-upload-crop-field
**Archived to**: `openspec/changes/archive/2026-10-08-image-upload-crop-field/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED; DELTA SPECS NOT MERGED AT ARCHIVE TIME, merged afterwards as ADDED on 2026-10-08 (see
"Post-hoc merge" below).
No verify-report existed; verification was not run as an SDD phase. `tasks.md` has 29 of 29 tasks checked and its
own `## Verification` section records the observed runs (141 test files, 1393 unit tests green; 2890 api tests,
2883 passed, 7 skipped, 0 failed; Playwright 26/26 on chromium and webkit including the axe pass).

## Summary

One shared image upload field with a crop dialog, used by Settings -> Appearance (logo, square, `contain`) and
Profile (photo, circle, `cover`), plus the server fix that makes `logo_url` absolute. Observed on disk at
archive time:

- backoffice commit `20157a9` ("feat(ui): one image upload control, with cropping", on backoffice `develop`),
  followed by `ad6c108` and `a258ffb`; `backoffice/app/components/molecules/ImageCropDialog.vue` and
  `ImageUploadField.vue` exist.
- api: `Organization::absoluteLogoUrl()` exists (`api/app/Models/Organization.php:146`) and is used by
  `OrganizationResource` (line 70) and `ParticipantResource` (line 112).
- wrapper commit `8e67f0d` carried the change folder.

## Specs merged

None. `gentle-ai sdd-archive-compose` was run against both canonical specs and refused both deltas:

- `organization-settings`: `unapplied MODIFIED delta for requirement "The organization logo is chosen through a framed, previewed upload field": no canonical requirement named ...`
- `user-self-service`: `unapplied MODIFIED delta for requirement "The profile photo is framed before it is uploaded": no canonical requirement named ...`

### Not merged at archive time

Every requirement in the two deltas is filed under `## MODIFIED Requirements` but none of the four titles exists
in `openspec/specs/` (`rg` over `openspec/specs` finds none of them). Per the archive rule, none was guessed:

| Capability | Requirement title in the delta | Why skipped |
|---|---|---|
| organization-settings | The organization logo is chosen through a framed, previewed upload field | MODIFIED title absent from canonical |
| organization-settings | `logo_url` is resolvable from every app that renders it | MODIFIED title absent from canonical |
| user-self-service | The profile photo is framed before it is uploaded | MODIFIED title absent from canonical |
| user-self-service | The crop dialog is operable without a pointer | MODIFIED title absent from canonical |

The behaviour is delivered and tested; only the canonical specs lack it. The likely fix, as `scoring-retry-rt-b`
did for the same situation, is to treat the four blocks as ADDED. That is a spec decision for a human; the
unmodified deltas are preserved in this folder under `specs/`.

### Post-hoc merge (2026-10-08)

Delivery was re-verified on disk (`backoffice/app/components/molecules/ImageCropDialog.vue` and `ImageUploadField.vue`
exist; `BrandingForm.vue` uses `aspect="1:1" fit="contain" shape="square"` and `ProfilePhotoForm.vue` uses
`fit="cover" shape="circle"`; the dialog handles arrow keys, `+`/`-` and a labelled range input;
`Organization::absoluteLogoUrl()` is used by `OrganizationResource` and `ParticipantResource`). The four blocks were
then merged into the canonical specs as ADDED requirements (precedent: `2026-10-06-scoring-retry-rt-b`), composed
with `gentle-ai sdd-archive-compose` from a scratch copy of each delta whose `## MODIFIED Requirements` header was
changed to `## ADDED Requirements`; the archived deltas in this folder are the unmodified originals.

| Capability | Requirements added |
|---|---|
| organization-settings | 2 ("The organization logo is chosen through a framed, previewed upload field", "`logo_url` is resolvable from every app that renders it") |
| user-self-service | 2 ("The profile photo is framed before it is uploaded", "The crop dialog is operable without a pointer") |

Pure additions (organization-settings +69 lines, user-self-service +60 lines, 0 deleted).

## Not delivered / deferred

Nothing in `tasks.md`; all tasks are checked.

## Traceability

Mode openspec. Artifacts read from the filesystem: proposal.md, design.md, tasks.md, two delta specs. Absent:
verify-report, apply-progress, exploration.md.

## Copy verification

Moved with `git mv` (no file rewritten). This report is additive.
