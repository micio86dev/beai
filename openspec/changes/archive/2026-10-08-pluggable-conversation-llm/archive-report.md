# Archive Report: pluggable-conversation-llm

**Change**: pluggable-conversation-llm
**Archived to**: `openspec/changes/archive/2026-10-08-pluggable-conversation-llm/`
**Archive date**: 2026-10-08
**Status**: CLOSED, DELIVERED WITH LIVE-PROVIDER GATES STILL OPEN. The `managed`-mode chain (registry, credentials,
binding, Tavus wire, HeyGen wire as far as the evidence allowed, session snapshot, usage estimator, cost views) is
on `develop`. Tasks P5.0, P5.12, P5.13, 0.3 and F.6 are NOT done and need a human with live HeyGen/Tavus
credentials. No verify-report existed; verification was not run as an SDD phase and no test suite was run by this
archive. `tasks.md` was corrected against the code (see below).

## Summary

Bring-your-own-model for avatar templates: a global `llm_models` registry, an encrypted credential vault, a binding on
`avatar_templates` (both-or-neither, enforced in `AvatarTemplate::booted()` and by a CHECK), Tavus and HeyGen wiring,
a write-once session snapshot, an append-only usage aggregate with a context-resend estimator, and backoffice
credential, picker and cost views. Observed on disk at archive time:

- api: models/enums/services under `app/Services/ConversationLlm/` (`LlmBindingResolver`, `ManagedLlmPayload`,
  `ConversationLlmUsageEstimator`, `InterviewSessionLlmSnapshot`), `LlmCapability::mode()`, migrations
  `2026_08_26_000002..000006`, `beai:sync-llm-registry` (`SyncLlmRegistryCommand`), `beai:reconcile-llm-usage`
  (`ReconcileLlmUsage`), `config/conversation_llm.php`, per-provider active index
  (`2026_08_26_050000_avatar_templates_active_index.php`).
- backoffice: P9 delivered in `c129cb8` (2026-08-28): `SessionReviewPanel.vue` (two labelled estimate lines, no
  combined total, no per-minute rate, Actual only when non-null), per-template forecast in
  `pages/avatar-templates/index.vue`, `en`/`it` keys, credentials panel mounted in Settings.
- Later changes on `develop` superseded parts of this design (see "Not merged"): `263dca5` (2026-09-14) made
  credentials PLATFORM rows, superadmin-only; `ddeba8e` made template management a platform action; `76eb18c` renamed
  HeyGen configurations without an organization; the seed registry now has five models, not four.

## Specs merged

Composition used `gentle-ai sdd-archive-compose` (exit 0) except where noted.

| Capability | Requirements before -> after | Delta applied |
|---|---|---|
| admin-backoffice | 80 -> 83 | 3 added (model picker with disabled Live group; credentials panel masking and 409 explanation; cost as labelled estimate, never combined, never $/minute) |
| interview-session | 47 -> 48 | 1 added (session snapshots its LLM binding at issue) |
| observability | 20 -> 22 | 2 added (append-only usage aggregate with rate-card snapshot; actual usage permanently null in managed mode) |
| avatar-templates | 14 -> 16 | 2 modified (see below), 2 added ("Active template resolution requires an explicit provider and never crosses providers"; "Unbinding a template clears only that template's binding") |
| conversation-llm (NEW) | 0 -> 6 | 6 of the 10 delta requirements: registry sync via console command; credential in use cannot be deleted; mode derivation and `native_duplex` refusal; Tavus wire merge; usage estimator; per-template forecast |

`git diff --stat` of `openspec/specs`: 299 insertions, 45 deletions in the four modified files, plus the new
`conversation-llm/spec.md` (150 lines).

Notes on how the merge was done, all of them deviations a reviewer should know about:

- **avatar-templates, two MODIFIED blocks were renames.** The delta's titles ("...per organization and provider...",
  "Activation swaps the active template within the same provider...") do not exist canonically; the canonical titles
  are "Exactly one active template per organization, enforced at the database" and "Activation swaps the
  organization's active template atomically and re-validates". The composer refused them. They were composed from a
  scratch copy of the canonical spec with those two headings renamed to the delta's titles (scratch only), then
  replaced by the delta text. The delta's replacement dropped the scenario "Deleting the active template is
  refused"; it is still true (`AvatarTemplateController::destroy()` answers 409 `template_active`), so it was
  re-inserted verbatim from the previous canonical text at the end of the Activation requirement. The delta also
  dropped some rationale prose of the old text; that prose was not kept.
- **Index wording**: the delta says `WHERE is_active`; the live index is `WHERE is_active AND deleted_at IS NULL`
  (soft-delete migration `2026_09_01_160000`). Same behaviour for live rows; the requirement says "partial" and
  does not forbid the extra predicate. Not edited.
- **The resolver requirement is ADDED, not MODIFIED**: the canonical spec had no requirement for
  `ActiveTemplateResolver`. The live `resolve()` takes an optional second `?int $projectId` (pinned template wins)
  and also requires a non-null `organization_id`; the delta's statements (required `$provider`, no default, filters
  on provider, returns null, never crosses tenants) all still hold.
- **conversation-llm**: a new capability file written from the delta. The six kept requirement blocks are
  byte-identical to the delta (checked by substring). The `Purpose` text was rewritten minimally (removed "org-owned",
  "bring-your-own-key" and the dangling pointer to the unmerged binding requirement; added a scope note pointing here).
- A `## Out of Scope (C14)` heading in `avatar-templates` is now empty after the earlier removal of the catalogue
  bullet (previous commit); left in place.

### Not merged - contradicted by later changes (needs a human rewrite, not a re-submit)

| Capability | Requirement | Why not merged |
|---|---|---|
| conversation-llm | The model registry is global, upserted, and carries a per-request context pricing tier | "The seed set MUST be exactly these four `key` values": `llm_models.php` now seeds five (adds `gemini-3.1-flash-lite-preview`) |
| conversation-llm | Org credentials are encrypted at rest and never leave the API as plaintext | "Credentials are tenant-scoped... cross-org id MUST resolve as 404": credentials are platform rows since `263dca5` |
| conversation-llm | Credential validation returns a stable code... | "reachable only through a stored, admin-owned credential": credentials are superadmin-only now; not re-verified otherwise |
| avatar-templates | A template may bind one conversation model and one credential, both or neither | the cross-org paragraph and scenario ("a credential belonging to another organization is unresolvable under `TenantScoped`") were removed from `AvatarTemplate::saving()` by `263dca5`; the rest (columns, CHECK, vendor mismatch, `llmModel` rejected) is delivered |
| avatar-templates | Portability export and import never carry a credential id or key | says import resolves `credential_name` against "its own credentials" of the importing organization; credentials are platform rows now. Not re-verified otherwise |
| audit-log | Credential and LLM-binding mutations are audited with the key value always redacted | requires `llm_credential.verified` and a "verifying a credential is audited" scenario: no such action or endpoint exists (`created`, `rotated`, `deleted`, `llm_bound`, `llm_unbound` do exist) |

### Not merged - blocked on live provider evidence

| Capability | Requirement | Why not merged |
|---|---|---|
| conversation-llm | HeyGen's secret and configuration lifecycle is lazy, synchronous, and leaves no orphan | states as fact that `llm_configuration_id` enters the session-token body at the provider-owned (top-level) position and the secret lifecycle (`/v1/secrets`): open question (a) is UNVERIFIED live (a control experiment returned 200 for a bogus id, so status code cannot discriminate placement); also names secrets `beai-org{orgId}-cred{credId}`, since changed by `76eb18c` |

## Not delivered / deferred

- **P5.12 and P5.13 remain open.** Whether `POST /v1/contexts` also takes `llm_configuration_id` (open question (b))
  was never answered; `HeygenProvider::buildContextBody()` is unchanged. **They are the prerequisite of the
  still-open change `native-duplex-conversation`.**
- **The live smoke-check remains open**: tasks 0.3, P5.0 and F.6 need `interview:smoke-check` (class
  `ProviderSmokeCheck`) run against live HeyGen/Tavus with credentials, recording (a) the placement of
  `llm_configuration_id` in `POST /v1/sessions/token`, (b) the `/v1/contexts` question, and confirming the secrets
  host and verbs. (c) Tavus not retaining `api_key` was answered live (P4.0); (d) `secret_name` non-unique and
  `/v1/secrets` immutable was answered partially (P5.0). `apply-progress.md` and P8c record that an earlier "live
  evidence" claim for `api.heygen.com/v1/secrets` was not reproducible (the real host is `api.liveavatar.com`):
  recorded smoke evidence is a claim until re-run.
- **P9.4 Model column**: DROPPED (not required by the delta spec); forecast rendering on template rows is done.
- **Final verification F.1-F.5 and F.7, and P9.8**: NOT RE-RUN at archive time (2026-10-08).

## Task corrections (tasks.md)

Only checkboxes and trailing notes were edited; line count unchanged (725 before and after). Ticked with evidence:
0.1, 0.2 (moot: landed on `develop`, no feature branch remains), 0.4 (rate-card verification dates present in
`llm_models.php`), P9.1, P9.2, P9.3 (except the Model column), P9.5, P9.6, P9.7. Left unchecked and annotated: 0.3,
P5.0, P5.12, P5.13, F.6 (`NOT DONE (needs live provider credentials / human)`), P9.4 (partial), P9.8 and F.1-F.5,
F.7 (`NOT RE-RUN at archive time`).

## Traceability

Mode openspec. Artifacts read from the filesystem: proposal.md, design.md, tasks.md, apply-progress.md, six delta
specs. Absent: verify-report, exploration.md.

## Copy verification

Moved with `git mv`. Original file counts and line counts are identical after the move (apply-progress.md 1254,
design.md 1434, proposal.md 661, tasks.md 725, and the six delta specs 78/38/238/306/45/72). The only edit was the
`tasks.md` checkbox and note change above. This report is additive.
