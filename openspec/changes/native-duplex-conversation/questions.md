# Question Round: native-duplex-conversation

Prepared 2026-10-10 for the owner. Companion to `proposal.md` (see "Amendment 2026-10-10"). Answer by number, e.g.
"1 yes, 2 ok, 3 B". **Anything left unanswered takes the RECOMMENDED default**, except Q1: without an explicit yes
nothing live is ever run.

Rules for reading this: questions Q1 to Q3 **block `sdd-design`** (design cannot be written honestly without them).
Q4 to Q9 do not block; their default is taken if you stay silent. Section B lists engineering decisions already taken,
with rationale, so you can overrule one by number.

## A. Needs the owner

### Q1. Do you authorize the Gemini Live spike, and with what spend cap? (BLOCKING)

- **Why it matters.** The Connector's behaviour (transcripts, end-phrase, prompt, voice, placement) has never been
  exercised. Design written without it is written against a hypothesis, and a negative on transcripts kills the
  change. Running it spends real money on two vendors and creates immutable HeyGen secrets.
- **Needs from you:** destination (`api.liveavatar.com`, Google Gemini Live), operation (3 to 5 short sessions, one
  deliberate failure, one forced drop; items S1 to S10 in the proposal), credentials (which HeyGen key, which Gemini key
  with Live access), and a cap.
- **Options.**
  - A. Authorize now with a cap. Trade-off: unblocks everything; costs roughly $1 to $3 Google and 15 to 50 LiveAvatar
    credits (estimates; the credit price is unverified).
  - B. Authorize later. Trade-off: no spend, but the change stays frozen and the next release proceeds without it.
  - C. Do not run it; drop `native_duplex`. Trade-off: removes a maintained-but-inert registry entry and the disabled
    picker group; loses the latency option.
- **RECOMMENDED: B** until you are ready to say A in a separate message. Silence means "do not run": a live spend
  authorization must be explicit and separate from this document.

### Q2. Is a Live interview without a spoken "please wrap up" nudge acceptable? (BLOCKING)

- **Why it matters.** On `managed` sessions the avatar says a wrap-up line about 20 s before expiry. On
  `gemini-3.1-flash-live-preview` mid-session client content breaks the session (AD-6), so Live is cut by a client
  timer with no spoken warning. A candidate may be cut mid-sentence. Rejecting this reopens the default model (AD-5).
- **Options.**
  - A. Accept: timer is the contract, completion stays on the transcript end-phrase. Trade-off: abrupt end possible;
    simplest and keeps the supported model.
  - B. Accept with a visual countdown in the call UI in the last 30 s (no audio). Trade-off: about 60 more frontend
    lines; softens the cut without touching the model.
  - C. Require the nudge: default to `gemini-2.5-flash-native-audio` (deprecated). Trade-off: a deprecated default.
- **RECOMMENDED: B.** A is the floor; B costs little, needs no model change, and is the humane version of A.

### Q3. What does a candidate see and can they continue if Gemini drops mid-interview? (BLOCKING)

- **Why it matters.** Resumption is handled by the Connector, if at all (spike S8). The answer is a
  candidate-facing behaviour change that belongs in the `interview-conversation` spec.
- **Options.**
  - A. Use the existing degraded/error path and the existing resume flow (a new session, transcript so far kept).
    Trade-off: the model does not remember the conversation; the interview resumes by competency, as it does today.
  - B. State "Live interviews are not resumable": a drop ends the interview as `errore` for operator action.
    Trade-off: honest and simple, bad for the candidate.
  - C. Wait for the spike: if the Connector resumes, expose it; otherwise fall back to A.
- **RECOMMENDED: C, falling back to A.** A is already the product's behaviour for `managed`; do not invent a new one
  before S8 says what is possible.

### Q4. Does Live ship with cost capture, and in what shape? (default if silent)

- **Why it matters.** Question 1 of the old round (depend on or absorb P6a/P6b) is moot: they shipped. What is left is
  what Live adds to the existing usage aggregate, which is per-minute arithmetic (`live_seconds` times seeded rates,
  about $0.023/min), never a token estimate.
- **Options.**
  - A. Ship Live without cost capture first (operators see no Live cost line). Trade-off: smaller, but the most
    expensive mode would be the one with no cost visibility.
  - B. Ship the per-minute path in the same change (about 150 to 250 lines). Trade-off: bigger change, no blind spot.
- **RECOMMENDED: B.** The infrastructure exists now, so the old reason to skip it (a second change's scope) is gone.

### Q5. Which voice wins: the template's, or the Connector's `voice`? (default if silent; settled by spike S6)

- **Why it matters.** Two writers on one property is the same last-one-wins shape change 1 refused for the model.
- **Options.** A. The template's voice, mapped onto the Connector field. B. A separate Live voice field on Live
  templates (reintroduces a second source). C. Connector default voice, template voice ignored for Live.
- **RECOMMENDED: A.** If the Connector's voice set has no equivalent, Live templates offer a different voice list;
  record that asymmetry in the spec.

### Q6. Is Live opt-in per template, or the recommended default for new HeyGen templates? (default if silent)

- **Why it matters.** Live is lower latency (NFR < 2 to 3 s) and materially more expensive.
- **Options.** A. Opt-in; `managed` stays the default. B. Live recommended for new HeyGen templates.
- **RECOMMENDED: A.** An operator should choose the costly mode deliberately; revisit with real latency numbers.

### Q7. Should a Live-bound template show an estimated cost at bind time, and in which shape? (default if silent)

- **Why it matters.** Change 1 shows "about $X for a typical 15-minute, 60-turn interview" and never $/minute, because
  per-minute is dishonest for text. For Live, per-minute is arithmetically honest.
- **Options.** A. Same shape and reference parameters as `managed` (one consistent display). B. For Live, also show the
  per-minute rate.
- **RECOMMENDED: A.** Consistency across modes; the per-minute rate is already visible in the registry.

### Q8. What does the candidate see when the session fails to start (stale binding, start-time 400)? (default if silent)

- **Why it matters.** The failure is seen only by the browser; the amendment reports it to the API, but the candidate
  still needs a message and a next step.
- **Options.** A. The existing generic degraded message plus an automatic single retry that re-issues the token.
  Trade-off: a retry cannot fix a stale binding, so it only helps transient faults. B. Generic message, no automatic
  retry, operator is alerted. C. Fall back to the template's `managed` binding for that session.
- **RECOMMENDED: B.** A retry loop on a deterministic failure wastes the candidate's time; C silently changes the
  assessed experience and the cost line, which this product has refused before.

### Q9. Is audio going to Google under the tenant key covered by the GDPR sign-off? (default if silent; blocks go-live, not design)

- **Why it matters.** In `managed` mode Google receives text. In Live the candidate's voice goes to Google. The
  retention sign-off (ruling 2) lists specific columns; a vendor audio path is a different processing step, and the
  data controller decides, not engineering.
- **Options.** A. Add "candidate audio sent to Google (Gemini Live) under the tenant's key, and HeyGen's handling of
  it" to the controller's sign-off list before any production Live use. B. Treat it as covered by the existing HeyGen
  single-account disclosure. 
- **RECOMMENDED: A.** B is a legal conclusion nobody here is entitled to draw. Live stays behind the opt-in (Q6)
  and off in production until the controller answers.

## B. Engineering decisions I took (overrule by number)

- **E1. Report the start-time 400 through a new narrow endpoint plus a Sentry tag, not `/integrity`.** Rationale:
  `/integrity` is proctoring and feeds the risk score; a provider fault is a statement about us. Detail and size in
  the proposal, Amendment section 3 (about 330 to 340 changed lines, one slice, independently shippable).
- **E2. Persist faults in an append-only table**, not a column on the session. Rationale: a resumed session can fault
  repeatedly; the history is the diagnostic.
- **E3. No pre-flight `GET /v1/llm-configurations/{id}` at token time for now.** Rationale: it costs one provider call
  per session start; revisit after the spike measures start latency.
- **E4. The LLM binding stays off the context.** The context carries only the prompt. Rationale: proven (C1).
- **E5. Tavus stays deferred (AD-3).** Rationale: nothing in the 2026-10-08 evidence touches Tavus; not re-examined.
- **E6. Default Live model is `gemini-3.1-flash-live-preview`; the 2.5 native-audio model stays selectable with a
  deprecation warning (AD-5).** Subject to Q2.
- **E7. `secret_type` and the placement of `gemini_realtime_config` are settled by the spike (S2, S5), not guessed.**
- **E8. `SystemPromptComposer` is no longer a "diff-free" file.** Live adds no composition code and consumes the active
  stored prompt set output unchanged. Rationale: the composer legitimately moved (stored sets, overrides,
  `composeMany`).
- **E9. Chain strategy `feature-branch-chain`, delivery `ask-on-risk`, as in the proposal.** The fault-report slice
  (E1) goes first because it also repairs `managed`.
