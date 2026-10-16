# closing-phrase-cut-hotfix

## Objective
The avatar must finish speaking the whole closing greeting (the configured closing phrase plus the final phrase) before the interview tears down. Reported by the owner after a live test on 2026-10-16: the greeting text is correct but is cut before the avatar finishes.

## Root cause (code reading, frontend 0.28.0)
Completion is detected by a contains-match of the final phrase (the LAST words of the closing) and is meant to wait for the avatar to stop speaking. In `frontend/app/providers/tavus.ts`:
- The decision only checks `replicaSpeaking`, not `utterancePending`; the `conversation.utterance` event can precede `started_speaking`, so the end phrase is seen while the avatar is "not yet speaking" and `complete` fires immediately.
- When deferred, the FIRST `stopped_speaking` releases completion with no settle window; a long closing has inter-sentence pauses that emit `stopped_speaking` mid-speech.
- `COMPLETION_FALLBACK_MS` is 12 s, shorter than a typical closing and far below the 3600-character cap.
`frontend/app/providers/heygen.ts` has the same shape (transcription before `avatar.speak_started` completes at once; `avatar.speak_ended` between chunks releases a pending completion; no fallback).

## Fix (frontend only; api and backoffice unchanged)
Both providers: a heard end phrase is held while the avatar is speaking OR an avatar utterance/transcription is pending; completion is released only after the avatar has been continuously silent for a settle window (about 2 s); the fallback grows with the spoken text length. Mock provider and the question flow are unchanged.

## Tasks
- [ ] T1 frontend (branch hotfix/0.28.1 from main): Tavus and HeyGen providers + unit tests (RED first), release 0.28.1.
- [ ] T2 wrapper: pin frontend v0.28.1, release 0.59.2, deploy, verify in prod.

## Constraints
Strict TDD, Vitest via bun. Repo language English. Conventional commits, no AI attribution. Hotfix Git Flow: from main, merge to main with tag, back-merge to develop. Owner asked for an immediate release to retest.

## Route
Delegated direct: one writer (2 provider files plus tests).

## Progress
Root cause identified from code; branch created.
