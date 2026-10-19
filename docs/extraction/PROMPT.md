# Mission: Extract the Avatar Engine out of BEAI into a standalone, reusable service

## Context

You are working inside the BEAI project root. BEAI is an AI-driven avatar interview
platform for HR use cases. It currently has avatar functionality (third-party avatar
providers, LLM brain selection, voice configuration, webhooks, public/private API key
auth) tightly integrated into its own codebase and into an existing SDK living under
`SDKS/embed`.

We are about to run a live demo at a trade fair in a few days showing the interview
experience end-to-end (primarily the front-end). Nothing in this effort may touch
`main`, and nothing may be deployed to production at any point. All work happens on a
new, clearly named branch (e.g. `feature/extract-avatar-service`), created fresh from
the current `main` of each affected repository. The demo must keep working against
the current, unmodified integrated code path until we deliberately cut over — which
will not happen as part of this task.

## Goal

Extract everything that is *only and exclusively* about running an avatar-driven
conversation into a new, independent service, codenamed **HR-Avatar** (placeholder
name — keep it isolated in config/package names so renaming later is a find-and-replace,
not a redesign). HR-Avatar must:

- Expose its functionality purely as an HTTP API plus a client SDK. It has no
  back office / admin UI of its own.
- Be provider-agnostic at the architecture level: today it wraps Tavus and HeyGen
  LiveAvatar (do not assume anything about what either runs underneath — verify by
  reading the actual integration code, do not assume LiveKit, Daily.co, or anything
  else is or isn't present until you've confirmed it in BEAI's codebase).
- Own the mechanics of an avatar conversation: provider session lifecycle, LLM
  "brain" selection/configuration per conversation, voice selection, webhook
  handling from providers, and whatever real-time transport each provider actually
  requires (confirm the real transport layer via code inspection, do not assume).
- Have its own independent authentication: its own public/private API key pair
  system, completely decoupled from BEAI's. A consumer should be able to integrate
  only HR-Avatar, only BEAI, or both together, with no hidden coupling. Reuse
  BEAI's existing API-key design patterns as a reference if they're solid, but
  implement a separate credential space scoped to HR-Avatar.
- Be designed from day one to be integrated by multiple, unrelated front-ends/back
  offices beyond BEAI (an upcoming product will use only the avatar piece, with
  none of BEAI's HR/assessment logic).

BEAI keeps everything that is organization-level configuration and does not belong
to "how an avatar runs": organization/company branding (company name, primary
color, background color), and — for now — the interview front-end templates
(currently fairly static, parameterized mainly by primary color). Flag clearly in
your analysis whether any part of the current front-end template rendering is so
entangled with avatar rendering that it would be cheaper to move it into HR-Avatar
too, but default to keeping templates in BEAI since organizations live in BEAI.

The existing `SDKS/embed` package must be split in two:
1. The parts that are BEAI-specific integration (organization config, template
   rendering, BEAI's own API) stay in (or become) the BEAI embed SDK.
2. The parts that are purely about embedding/controlling an avatar conversation
   move into a new HR-Avatar SDK, published as its own package, consumed by the
   BEAI embed SDK internally (BEAI composes HR-Avatar's SDK rather than
   reimplementing it) and usable completely standalone by other products.

## Non-negotiable constraints

- Do not touch `main` on any repository. Create and work exclusively on a new
  feature branch in each repository you modify.
- Do not deploy anything, anywhere, at any point, including to any staging or
  preview environment. Railway infrastructure for the new HR-Avatar service may be
  scaffolded (IaC/config as code) but must not be applied/deployed.
- The current demo path (BEAI with avatar integrated as-is) must remain fully
  functional and untouched until we explicitly decide to cut over. Do not delete
  or disable the existing integrated avatar code as part of this extraction —
  treat this as additive until a later, separate cutover step.
- Test-Driven Development throughout: write failing tests first for every unit of
  behavior you extract or create, then implement. No implementation code without a
  preceding test.
- Follow Spec-Driven Development: produce specs/design docs before implementation
  for each major component, using our existing Gentle-AI/SDD conventions.
- Use Engram as you always do to persist findings, decisions and context across
  sessions. Record key architectural decisions there as you make them, not only
  at the end.
- Guardian Angel review gates apply as usual before any commit.
- All code, comments, inline documentation, and markdown documentation files must
  be written in English, with no exceptions, regardless of the language used in
  this conversation or in commit messages.
- API documentation on both BEAI and the new HR-Avatar service must be a standard,
  machine-readable format — OpenAPI. Use Scramble (dedoc/scramble) to generate it
  from the Laravel codebases. If BEAI does not yet have Scramble wired in, add it
  as part of this work; if it already does, extend its coverage to any endpoints
  touched by this extraction and add equivalent coverage to the new HR-Avatar
  service.

## Required process — do not skip or reorder phases

### Phase 0 — Analysis (mandatory, do this before proposing any design)

1. Inventory `SDKS/embed` in full: every module, what it talks to, what is
   BEAI-specific vs. avatar-mechanics-specific.
2. Inventory the BEAI backoffice and API code that configures and drives avatar
   sessions: Tavus integration, HeyGen LiveAvatar integration, LLM brain/model
   selection, voice selection, webhook handlers, and the current public/private
   API key implementation.
3. Determine, by reading the actual code and dependency manifests (not by
   assumption), what real-time transport is actually in use for each provider
   (verify whether LiveKit, Daily.co, raw WebRTC, or something else is present —
   treat all prior guesses about this as unverified until confirmed).
4. Map the current data/control flow end to end: what BEAI's front-end sends in,
   what the avatar layer sends back (text, audio, video, events), and where
   organization-level config (branding, templates) currently enters that flow.
5. Identify every existing test around this code, current coverage level, and
   what will need re-homing vs. rewriting.
6. Produce a written findings document (in English, committed to the repo under
   an appropriate docs path) covering all of the above before any architecture
   proposal.

Only after Phase 0 is complete and findings are documented, move to planning.

### Phase 1 — Planning (Opus)

Produce a detailed design covering:

- The HR-Avatar service: API surface, data model, provider abstraction layer,
  the new public/private API key and auth scheme, webhook ingestion, and how
  conversation sessions are created, driven, and torn down.
- The HR-Avatar SDK: its public interface for host applications to embed an
  avatar conversation, independent of any BEAI concept.
- The split of `SDKS/embed`: exact module-by-module disposition (stays in BEAI
  embed SDK / moves to HR-Avatar SDK / becomes a thin BEAI wrapper around the
  HR-Avatar SDK).
- How BEAI's backoffice will configure Tavus/HeyGen settings going forward: via
  calls to the new HR-Avatar API, with BEAI persisting only the organization-level
  association (which avatar config is in use), not the provider credentials or
  mechanics themselves.
- Test strategy per component, with target coverage in line with our usual
  >85% bar.
- Migration plan for existing data (if any avatar/session state must carry over)
  — but no destructive change to current BEAI data as part of this work.
- A rough Railway topology for HR-Avatar for later deployment (service layout,
  env vars, secrets handling) — config only, not applied.
- OpenAPI/Scramble setup for both services.

Present this plan and ask only the questions that are genuinely blocking — do not
ask about things you can determine by reading the code. Batch any necessary
questions into a single round.

### Phase 2 — Implementation (Sonnet)

- Strict TDD: test first, watch it fail, implement, watch it pass, refactor.
- Work only on the dedicated feature branch(es). Commit in small, reviewable
  increments with clear English commit messages.
- Scaffold the new HR-Avatar repository (or directory, per the plan) with its
  own CI-ready test setup, independent of BEAI's.
- Implement the SDK split, keeping the existing BEAI demo path working throughout
  — add the new structure alongside, do not rip out the old path until the plan
  explicitly calls for a cutover (which is out of scope for this task).
- Wire Scramble/OpenAPI generation into both codebases and verify it produces
  valid output for the touched endpoints.
- Document the new HR-Avatar service (README, architecture notes, API usage
  examples for SDK consumers) in English, to the same standard as BEAI's
  documentation.
- At the end, produce a clear summary of what changed, what remains manually
  verified vs. automated, and explicit instructions for how a human would wire up
  BEAI's backoffice to point at the new HR-Avatar API locally (no deploy).

## Autonomy expectations

Run Phase 0 fully autonomously. At the end of Phase 0, ask any blocking questions
in one batch (for example: naming conventions for the new repo if not obvious,
or genuine ambiguity about data ownership that the code doesn't resolve). After
that, proceed through planning and implementation with minimal interruption —
only stop to ask if you hit a decision that would be destructive or irreversible
if guessed wrong (e.g., something that could affect the live demo path, or a
choice that cannot be cheaply undone later).

Remember at every step: branch only, no `main`, no deploys, demo path stays
intact, TDD, SDD, Engram, Guardian Angel, English-only code and docs, OpenAPI via
Scramble on both services.
