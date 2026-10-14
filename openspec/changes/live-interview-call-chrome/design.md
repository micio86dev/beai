# Design: Live Interview Call Chrome (Header, Interview Panel, Captions)

> **Status: Design 2026-10-14, corrective revision 2026-10-14.** Input: `proposal.md` (owner points O1-O4
> resolved), Engram `sdd/live-interview-call-chrome/explore`, plan `solo-durante-l-intervista-live-cozy-knuth.md`,
> the independent validator findings and the owner decisions of 2026-10-14 (approximate remaining minutes kept
> beside the exact countdown; panel 22rem; `feature-branch-chain`). Every file and symbol cited below was read in
> the working trees on 2026-10-14. The frontend tree was read on branch `feature/seamless-primary-transition`
> (checked out in `frontend/`, open as frontend PR #95 against `develop`), so `boundaryInFlight` and
> `whenAvatarSilent` are cited as they exist there (see R8 and the slice plan).

## Technical Approach

One new read-only candidate endpoint feeds a presentation-only rework of the `live` state. How the interview
runs (timeout, `/end`, `next_action`, handovers, proctoring, scoring) does not change.

- **api (slices A.i-A.iii):** `GET /api/candidate/interview/outline` (new `Candidate\OutlineController` + action
  `BuildInterviewOutline`). The competency order and the "which competency is next" decision move out of
  `InterviewController` into one shared helper, `App\Support\Interview\CompetencyProgress`, so `/start` and
  the outline can never disagree about which competency is current. `/utterance` 202 gains `primary_index`.
  `persona.display_name` becomes writable, readable and validated by ONE rule on create, update and import.
- **backoffice (slice A2):** one input on `AvatarTemplateForm`, sent as `persona.display_name`.
- **frontend data (slices B.i, B.ii):** `useInterviewOutline`, `answerBudget()`, `primaryIndex`, a microphone
  intent that survives competency changes with a single restore choke point inside `useInterviewSession` and a
  seed-time re-apply in `AvatarPlayer`, `useAnswerTimer`, a persisted captions flag.
- **frontend UI (slices C1a, C1b, C2a, C2b):** `BrandCanvas` plate opt-out and a `CallHeader` organism in the
  existing `header-end` slot; `CallQuestion` re-placed as the captions overlay on the interviewer tile with a
  dedicated caption-prefix colour token; a reworked `CallPanel` ("Intervista") with two new molecules; a
  single-row `CallStage` grid.

`DESIGN.md` §3.3, §7.0.1 and §7.3 are amended first (slice 0); the rules it states today (empty live header,
no status pill, no min/ideal/max band, no competency name) are what this change reverses.

## Corrections to the proposal found while verifying the code

| # | Proposal says | Code says | Design consequence |
|---|---|---|---|
| V1 | "the form already round-trips `persona`" (Approach 3) | `templateStoreRules()`/`templateUpdateRules()` (`ValidatesAvatarTemplateWrites.php:32-67`) have no `persona` key, so `$request->validate()` drops it; `AvatarTemplateResource::toArray()` (`AvatarTemplateResource.php:72-94`) does not return it; `AvatarTemplateForm.vue:1124-1132` does not send it; the import path (`AvatarTemplatePortabilityController::import()` → `TemplateDocument::flatten()` → `create()`, `:186`) stores `persona` with no validation at all | Slice A.iii must add the rule, a merge-on-write, the import check and a read field; slice A2 must add the field, the payload key and the 422 mapping. Still small, no longer "one input". |
| V2 | `ParticipantResource` `display_name` kept by `useExitRedirect` | `useExitRedirect` is per-instance and redirect-only (`useExitRedirect.ts:81-117`) | The candidate name rides on the outline instead (D4). `useExitRedirect` is untouched. |
| V3 | Outline returns `competencies[].code` | No consumer needs it; the panel must not carry machine codes | `code` is not returned, and is never a fallback label either (D4). |
| V4 | `InterviewTimer` is "the per-question timer" | It counts down the WHOLE interview and its `expired` drives the `timeout` end (`InterviewSession.vue:822-847`, `CallPanel.vue:42-49`); it is the only `role="timer"` in the app (`InterviewTimer.vue:12`) | It stays mounted unchanged as the enforcement, shown in the duration section beside the approximate sentence (D11), and stays the ONLY `role="timer"` (D18). |
| V5 | "a `pending`-retry competency reports `retry`" | Two re-ask mechanisms exist: an `error` session with attempts left (re-offer, `InterviewController.php:1031-1035`) and the evaluation-retry run, which resets invalid sessions to `pending` (`AuthorizeEvaluationRetry.php:265-286`) | One rule covers both (D3). |

## Architecture Decisions

### D1. A dedicated outline endpoint, not a field on `/start` or `/session`

**Choice:** `GET /api/candidate/interview/outline`, registered inside the nested `interview` group
(`routes/api.php:930-953`), so it inherits `auth:api-candidate → TenantContextCandidate → SubstituteBindings`
and adds `ParticipantStatusGuard` (terminal participants refused, as for every interview sub-route). Handled by
a new `App\Http\Controllers\Candidate\OutlineController::show()` (Scramble operation id `outline.show`) that
delegates to `App\Actions\Interview\BuildInterviewOutline::handle(Participant): array`.

**Alternatives considered:**
- Extend `ParticipantResource`: rejected. It also feeds `ParticipantEnrolmentResource` (operator and M2M
  surfaces, pinned by `ParticipantArchTest`); a candidate chrome field would leak into those contracts.
- Extend `/start` (`BuildInterviewSessionResponse`): rejected. `/start` is a write with provider side effects;
  re-calling it to refresh a storyboard is not possible, and the storyboard must refresh after each boundary.
- A method on `InterviewController`: rejected. That class is ~1,900 lines and owns writes; a read belongs in its
  own controller.

**Rationale:** additive, read-only, owned by the candidate JWT, no route parameter (nothing to forge: the
participant comes only from the token).

### D2. `CompetencyProgress`: one owner of the order and of "which competency is open"

**Choice:** new `App\Support\Interview\CompetencyProgress` (container-resolved, no state):

```php
/** @return Collection<int, object{competency_id: int, competency_code: string, position: int}> */
public function ordered(int $projectId): Collection;            // the pc ⋈ fc join, by pc.position

/** null, pending, in_corso, or error with attempts left (< InterviewSession::MAX_ERROR_ATTEMPTS) */
public static function isOpen(?InterviewSession $session): bool;

/** @return array{competency_code: string, question_index: int, competency_ordinal: int, total_competencies: int, reoffer?: bool}|null */
public function resolveNext(int $participantId, int $projectId): ?array;   // MOVED, behaviour byte-identical
```

`InterviewController::resolveNextCompetency()` and `competencyPayload()` (`InterviewController.php:1003-1068`)
are **moved** into `resolveNext()` (the controller calls `$this->competencyProgress->resolveNext(...)` at its
one call site, `:241`). `freshRemainingCompetencies()` (`:897-920`) stays in the controller and replaces its
inline join with `ordered()`. `resolveNext()` is rewritten as "first row where `isOpen()`", which is exactly the
existing loop (null → return; pending|in_corso → return; error with attempts left → return with `reoffer`;
anything else → skip). The existing feature tests that pin `/start` ordering (`QuestionIndexZeroBasedTest`,
`CompletionCasTest`, `RecoverFailedParticipantTest`, `DraftContentIsolationTest`) are the regression net and
must stay green unmodified.

**Alternatives considered:** duplicate the join and the loop in the action (rejected: two copies of the
"current competency" rule drift, the classic failure this codebase documents); extract only the join (rejected:
the outline needs the open/closed decision too, and re-implementing it is the duplication).

**Rationale:** the storyboard's "current" is by construction the competency the next `/start` serves.

### D3. Outline status derivation

For each row of `ordered()` (array index `i`, `ordinal = i + 1`, dense like `competency_ordinal`), with the
participant's sessions on this project loaded once
(`InterviewSession::where('participant_id', $pid)->where('project_id', $projectId)->get([...])->keyBy('competency_code')`):

| Condition (evaluated in order) | `status` |
|---|---|
| the row is the FIRST row with `isOpen(session)` | `current` |
| `isOpen(session)` and a session row exists | `retry` |
| no session row | `upcoming` |
| otherwise (completed, timeout, skipped, error with attempts exhausted) | `done` |

This covers both re-ask mechanisms of V5 with one rule: a competency that already has a session row and will be
asked again is `retry`, whether it is an errored session awaiting re-offer or an evaluation-retry reset to
`pending`. Rows are created lazily (`AdvanceOnLiveConversation.php:111` and `createOrResumeSession`), so a
never-reached competency has no row and is `upcoming`. When every row is closed there is no `current`. A
`current` competency that is itself a re-offer or a retry still reports `current` (the candidate is doing it
now); the label distinction is not shown. `isOpen` is unit-tested once and shared.

### D4. Response contract (snake_case, no `data` envelope, like `/start`)

```php
/**
 * @scramble-return array{assessment_type: 'standard'|'potential', role_name: string|null, avatar_name: string|null, candidate_name: string|null, primary_total_all: int, competencies: list<array{name: string|null, ordinal: int, status: 'done'|'current'|'upcoming'|'retry', primary_total: int}>}
 */
```

| Field | Source | Null / edge rule |
|---|---|---|
| `assessment_type` | raw `projects.assessment_type` via `AssessmentType::tryFrom` | an unknown stored value answers `422 assessment_type_not_supported`, the same refusal `/start` gives (`InterviewController.php:249-254`) |
| `role_name` | `potential` → `null`. `standard` → `Role::where('code', $project->role_code)->where('revision_id', $revisionResolver->tryForProject($project))->first()`, then the name by the D4 name rule below | `null` for `potential`, for a null `role_code`, for an unresolvable pin (`tryForProject` never throws), or when both translations are blank |
| `avatar_name` | `$project->avatarTemplate?->personaDisplayName()` (pinned template, `Project::avatarTemplate()` uses `availableToTenant()`) | `null` when unset, not a string, or failing the D7 rule (a value stored before this change is re-checked on read) |
| `candidate_name` | `trim($participant->display_name)` | `null` when blank |
| `competencies[].name` | `Competency::whereIn('id', $ids)` by the pinned `project_competencies.competency_id`, then the D4 name rule | ids are revision-unique, so no code lookup and no resolver call is needed (resolver class docblock); `null` when both translations are blank, and the client renders the generic label |
| `competencies[].primary_total` | the session's `primary_questions` snapshot count when a session row with a non-null snapshot exists (what the classifier counts against); otherwise `count(ResolvePrimaryQuestions::handle($project, $competencyId))` | `0` for a competency with no authored primaries |
| `primary_total_all` | sum of `primary_total` over all rows | `0` hides the budget bar on the client |

**Name rule (roles and competencies, one private helper in the action):**
`getTranslation('name', $project->language, false)`; when blank, `getTranslation('name', config('app.fallback_locale'), false)`
(the catalogue default language, `en`, `config/app.php:83`); when still blank, `null`. The client turns a
`null` competency name into `interview.call.storyboard.unnamed` ("Competenza {ordinal}") and a `null` role name
into the generic title. **The competency code is never a fallback** (V3): a machine code on the candidate's
screen is exactly what this change keeps out of the panel.

Not returned: `code` (V3), `organization_id`, ids. The candidate's own name to the candidate's own JWT is the
same disclosure `/candidate/session` already makes.

`primary_total` calls `ResolvePrimaryQuestions` once per competency without a snapshot (at most 18 small
indexed queries). `// ponytail: per-competency primaries query, batch into one grouped read if the outline shows up in p95.`

**Scramble:** the public docblock prose describes the endpoint; implementation notes go under `@internal`
(the convention at `InterviewController.php:110-125`). Export against PostgreSQL only.

### D5. Tenant scoping (every query explicit)

| Read | Scope |
|---|---|
| participant | `auth('api-candidate')->user()`; `TenantContextCandidate` stamps the tenant from it |
| project | `$participant->project` (tenant-scoped `TenantModel`) |
| `project_competencies ⋈ framework_competencies` | raw `DB::table`, NOT globally scoped: filtered by `pc.project_id` = the participant's own project id, exactly as today's join |
| sessions | `InterviewSession` tenant scope + explicit `participant_id` and `project_id` |
| roles, competencies | platform catalogue (not tenant data), pinned by revision / revision-unique id |
| avatar template | `availableToTenant()` (own rows plus platform rows) through the project's pinned FK |

RED tests: two organizations holding the same competency codes and sessions; org A's candidate sees statuses
derived only from A's sessions; a terminal participant is refused by `ParticipantStatusGuard`; an
unauthenticated request is 401.

### D6. `primary_index` on `/utterance`

**Choice:** after the transaction commits, compute once
`$primaryIndex = $this->turnClassifier->matchedCount($session);`, pass it to `recordUtteranceEvent()` (which
today calls `matchedCount()` itself, `UtteranceController.php:270`, and becomes `max(0, $primaryIndex - 1)`),
and return `['boundary_due' => ..., 'primary_index' => $primaryIndex]`. The `#[Response(202, ...)]` attribute
at `:95` becomes `type: 'array{boundary_due: bool, primary_index: int}'` (kept as an attribute, not
`@scramble-return`, so the documented 409 and 503 survive, per the comment at `:93-94`).

**Semantics:** the number of DISTINCT operator primaries of THIS session's competency asked so far (`0..n`),
i.e. the 1-based index of the latest primary asked. Follow-ups never move it; a verbatim re-ask on resume does
not move it (`TurnClassifier` docblock `:70-79`), so a resumed competency reports the true count. A retry
re-offer discards the transcript (`ResetSessionForRetry`) and the count restarts at 0. A competency with no
primaries or no snapshot always returns `0` (`matchedCount()` returns 0 for an empty list). Returned for
candidate and avatar turns alike. How the client renders it is D14 (clamped, never "domanda 0 di n").

**Cost:** one extra indexed read for avatar follow-up turns (they skipped `matchedCount()` before); outside the
Z16 lock, so the locked section is still exactly three statements.

**Alternatives considered:** counting `primary` rows (wrong: re-asks are `primary` but do not advance);
computing it on the client (impossible: classification is server-side).

### D7. `persona.display_name`: one rule on create, update and import

- **One rule, one class:** new `App\Rules\PersonaDisplayName` (a `ValidationRule`, sibling of the existing
  `App\Rules\NoCompletionPhrase` and `SafeWebhookUrl`) with `public static function problem(mixed $value): ?string`
  that the rule's `validate()` delegates to. It refuses a value that is:
  1. not a string, or longer than `PersonaDisplayName::MAX = 60` characters (`mb_strlen`, after trim);
  2. carrying `<` or `>`, or any control/format character (`\p{C}`);
  3. naming a technology provider: case-insensitive, word-bounded
     `/\b(?:hey\s*gen|live\s*avatar|tavus|daily|live\s*kit)\b/iu` (HeyGen, LiveAvatar, Tavus, Daily, LiveKit).
     The list is the one constant to extend when a provider is added.

  **The error message never repeats the matched word** ("The display name must not name a technology
  provider."), and neither does the backoffice copy (`errors.personaDisplayNameInvalid`). A message that echoes
  the vendor name back is itself a provider-opacity leak into logs and screenshots. 60 characters fits the chip
  and the caption prefix; angle brackets and control characters are refused because the value is
  candidate-facing (R7).
- **Form (store AND update, `ValidatesAvatarTemplateWrites`):**
  `'persona' => ['sometimes', 'nullable', 'array:display_name']`,
  `'persona.display_name' => ['nullable', new PersonaDisplayName]`. Both rule methods' docblocks widen from
  `array<string, list<string>>` to `array<string, list<string|ValidationRule>>`. Strings are trimmed and empty
  becomes null by the global middleware.
- **Import:** `TemplateDocument::flatten()` (`TemplateDocument.php:74`) normalizes the persona it already
  extracts: a string `display_name` is trimmed, and a blank one is UNSET (same shape as the form). Then
  `AvatarTemplatePortabilityController::reject()` (`:117`) returns `"persona.display_name: {problem}"` when the
  key is present and `PersonaDisplayName::problem()` is not null, so a file can never install a name the form
  would refuse (the same "one validator, no drift" principle the comment at `:127-130` states for `config`).
- **Write is a merge, and clearing UNSETS the key:** one trait helper
  `mergePersona(?array $current, array $validated): ?array`, applied in `AvatarTemplateController::store()`/`update()`
  (`:224`, `:256`) and `Api\PlatformAvatarTemplateController::store()`/`update()` (`:145`, `:188`):
  - `persona` absent from the request → the column is untouched;
  - a non-empty `display_name` → set, every other key an import brought in is kept;
  - `display_name` null/empty (the operator cleared the field) → `unset($persona['display_name'])`, never a
    stored `null`; when nothing is left the column becomes `null`.
- **Read:** `AvatarTemplateResource` adds `persona: array{display_name: string|null}` (only that key, never the
  raw JSON) to both `toArray()` and its `@scramble-return`; `PlatformAvatarTemplateResource` inherits it
  (`PlatformAvatarTemplateResource.php:39`). `T-EXPOSE-001`: `avatar_template.persona.display_name` is added to
  `ExposureCatalogue::exclusions()['Project']` (admin-only; `/v1` `ProjectSerializer` never reads `persona`,
  `ProjectSerializer.php:21`) in the same PR.
- **Model accessor:** `AvatarTemplate::personaDisplayName(): ?string` returns the trimmed value, or `null` when
  `PersonaDisplayName::problem()` refuses it, so a value stored before this change degrades to the fallback
  label instead of rendering.
- **Duplicate / export:** already carry `persona` (`DuplicateAvatarTemplate.php:61`, `TemplateDocument.php:48`);
  covered by a test each, no code change.

### D8. The captions overlay IS `CallQuestion`, moved onto the interviewer tile

**Choice:** no new `CallCaptions` file. `CallQuestion` keeps its contract (one persistent `aria-live="polite"`
`aria-atomic` region, `focusOnBoundary()`, scroll when long) and changes place and look:

- Rendered inside the `avatar-layer` div (`InterviewSession.vue:74-107`) after `CallTile`, `v-if="live"`, as
  `absolute left-3 bottom-11 right-[calc(clamp(9rem,18%,14rem)+1.5rem)]` so it never covers the interviewer's
  name chip (bottom-left) or the self-view tile (bottom-right, same percentage base: the layer cell). The keyed
  player layer is not re-parented; only a sibling is added.
- Box `bg-avatar-bg` (opaque), text `text-white text-xl leading-8 font-medium`, `max-h-[6rem] overflow-y-auto`.
  Opaque, because any translucency would composite against unknown video and void every contrast guarantee.
- **Speaker prefix colour: a dedicated token, `--color-primary-caption`**, used only here:
  `<span class="text-primary-caption font-semibold">{{ speakerName }}:</span>`. It is held to **4.5:1** against
  the caption backing (`--color-avatar-bg`), so the prefix passes as normal-size text, not only as large text.
  - Tenant brands: `useBrandTheme.ts` adds it to `BRAND_DERIVED_TOKENS` (`:96`) with
    `DERIVE['--color-primary-caption'] = (color) => ensureContrast(mix(color, '#ffffff', 0.7), AVATAR_PANEL, 4.5)`
    beside the existing entries (`:193-214`): the same hue step as `--color-primary-light`, lifted only as far
    as 4.5:1 needs.
  - Quint default: an authored hex in `main.css` beside `--color-primary-light` (`main.css:37`), equal to
    `ensureContrast('#c222d3', '#0f172a', 4.5)` (the product's own light shade, which measures 3.79:1, lifted to
    4.5:1); a `brand-theme.spec.ts` case pins the value and the ratio, and `canvas-brand-fallbacks.spec.ts`
    picks the new token up through the list.
  - **`--color-primary-light` is NOT changed.** It is the ribbon edge (`VoiceVisualizer.client.vue:247`) whose
    binding floor is the 3:1 graphical-object ratio (`useBrandTheme.ts:194-197`); raising it to 4.5:1 would
    restyle the waveform and every `bg-primary-light/30` notice surface (`useBrandTheme.ts:19-23`) for a
    requirement that only the caption prefix has.
- New props: `speakerName: string`, `visible: boolean` (default `true`).
- **Captions off (O4):** the region gets `sr-only`, loses `tabindex`, and `focusOnBoundary()` returns early. The
  text is still written into the region, so screen readers keep hearing every question (no WCAG 1.2.4
  regression); the hint text still appears there before the first question.
- `CallStage`'s `#question` slot and grid area are removed (the band no longer exists).

**Alternatives considered:** a separate overlay plus the band (rejected: two copies of the question, the
proposal's own "show one or the other"); a separate `CallCaptions` with the band kept as the live region
(rejected: splits one region across two components and keeps a white band O4 says must hide anyway); relying on
the large-text 3:1 exemption with `--color-primary-light` (rejected: it ties the guarantee to a font size a
later restyle can silently drop below 18.66 px bold); reusing `--color-lavender`, which is also 4.5:1 on
avatar-bg (rejected: it couples the caption to the ribbon's centre colour, so a waveform change would recolour
captions).

### D9. Microphone toggle: intent vs forced mutes (R4)

**State owned by `useInterviewSession`:** `micMuted: Readonly<Ref<boolean>>` (the candidate's intent, default
`false`) and `setMicMuted(muted: boolean): void`. The intent lives as long as the `useInterviewSession` instance:
**it is reset only by a page reload**, never by a `sessionId` change, a new competency, a re-offer, a
continuation or a resume within the page.

**Precedence rules:**

1. **Forced mutes win.** They stay owned by the boundary and handover logic and are unchanged: `beginHandover`
   (`useInterviewSession.ts:1182`) and `assertBoundary` (`:1566`) still call `provider.setMicMuted(true)`. While
   either is active (`handoverInFlight || boundaryInFlight`), `setMicMuted(m)` records the intent only and does
   not touch any provider.
2. **One restore choke point.** Every place that RE-OPENS the uplink after a forced mute calls one internal
   `restoreMic(handle)`, which is `handle.provider.setMicMuted(micMuted.value)`. Call sites changed: `:1280`
   (incoming promotion), `:1506` and `:1518` (handover directives), `:1582` (`assertBoundary` finally),
   `:1616` and `:1620` (`applyContinuation`). So a candidate who muted before a boundary stays muted after it,
   whatever the boundary's outcome.
3. **Every new handle re-applies the intent at its seed.** A new provider session is seeded with an uplink state
   exactly once, right after `provider.start()` resolves (`AvatarPlayer.client.vue:258`,
   `props.provider.setMicMuted(props.muted)`), and that seed would otherwise reopen a muted candidate's mic at
   every new competency. `AvatarPlayer` gains an uplink-only prop `micMuted?: boolean` (default `false`) and the
   seed becomes `setMicMuted(props.muted || props.micMuted)`; the page binds `:mic-muted="session.micMuted.value"`.
   - `muted` keeps its meaning (handover-role downlink + the hidden incoming's closed mic) and is still NEVER
     bound to the candidate's mic (its doc rule, `AvatarPlayer.client.vue:109-111`); the new prop is separate
     precisely to honour that rule.
   - A hidden incoming handover player has `muted = true`, so it is seeded closed regardless of intent (forced
     mute wins) and is opened to the intent by promotion's `restoreMic` (rule 2).
   - The prop is read at the seed moment, after `start()` resolves, so it carries the intent as it is then: no
     second write races the seed.
4. `setMicMuted(m)`, with no forced mute active, sets the intent and applies it to `activeSession`'s provider.
5. **The toggle is disabled during a handover** (`aria-disabled`, not hidden, like the Exit loading state) and
   its **visual state is `micMuted || handoverInFlight`**: during a handover the mic is really closed, so the
   control shows muted and cannot be changed; afterwards `restoreMic` reapplies the candidate's own choice and
   the control shows it again. During a boundary (short, `boundaryInFlight`) the toggle stays enabled and shows
   the intent; a change is recorded and applied by the boundary's `restoreMic`.

**Known behaviour, accepted and documented:** muting during an answer is silence to the provider's turn
detection, so it can end the answer, exactly like the candidate falling silent ("An answer ends by silence only"
is unchanged). The `DESIGN.md` bullet says so.

**Mute and the rest of the screen:** muting does NOT freeze or alter the answer timer (D10). The persistent
muted indication is the header control (pressed state + slashed icon) plus a text hint in the answer-time
section (D14), shown while the intent is muted. The self tile ring is lit only when
`speaker === 'candidate' && !micMuted` (the RMS reader reads the device-check stream, which a provider mute does
not necessarily silence: `useSpeakerTurn.ts:259`).

**Alternatives considered:** reset the intent on `sessionId` change (the previous revision; rejected by the
validator: a candidate who muted is silently unmuted at the next competency, the worst direction for a privacy
control); re-apply after the provider reports `connected` (rejected: the seed at `:258` runs after `start()`
resolves and can land after that event, overwriting the re-apply); binding `muted` to the intent (rejected: it
would also mute the interviewer's audio, the defect the comment at `AvatarPlayer.client.vue:9-18` records).

### D10. Answer timer: `useAnswerTimer`

New composable `app/composables/useAnswerTimer.ts`, owned by `InterviewSession.vue`:

```ts
export type AnswerPhase = 'idle' | 'listening' | 'waiting' | 'answering'
export function useAnswerTimer(o: {
  speaker: Readonly<Ref<Speaker>>, sessionId: Readonly<Ref<number | null>>, live: () => boolean,
}): { phase: Readonly<Ref<AnswerPhase>>, seconds: Readonly<Ref<number>> }
```

The count starts when the interviewer STOPS speaking (`avatar → none`) and runs on through the candidate's
answer: twelve seconds of silence after a question read `00:12` with the chip "In attesa della tua risposta",
and the candidate starting to speak does not reset it.

| Event | Transition |
|---|---|
| `speaker` becomes `avatar` (from any phase) | `listening`, `seconds = 0`, interval stopped (a new question or follow-up starts) |
| `speaker` becomes `none` while `listening` | `waiting`, `seconds = 0`, interval starts |
| `speaker` becomes `candidate` while `waiting` | `answering`, interval continues, `seconds` NOT reset |
| `speaker` becomes `candidate` while `idle` or `listening` | `answering`, `seconds = 0`, interval starts (no gap after the question) |
| `speaker` becomes `none` while `answering` | stays `answering`, interval continues (a pause in speech is not the end) |
| `sessionId` changes, or `live()` false | `idle`, `seconds = 0`, interval stopped |

One `setInterval(1000)` runs only while `waiting` or `answering`. There is no `muted` phase and no mic input:
muting changes nothing here (D9). Never drives `/end`.

**Alternatives considered:** a `muted` phase that freezes the count (the previous revision; rejected: muting is
silence to the provider, so a frozen count misstates how long the answer has really been running, and the
header control already states the mute); counting from the first candidate word (rejected: the time a candidate
spends thinking is part of the answer budget, and a timer at `00:00` during a long silence reads as broken).

### D11. `answerBudget()` and the interview limit

`app/utils/answer-budget.ts`:

```ts
export const ANSWER_BUDGET_FRACTIONS = { min: 0.25, idealFrom: 0.375, idealTo: 0.75 } as const // O1
export interface AnswerBudget { min: number; idealFrom: number; idealTo: number; max: number } // whole seconds
export function answerBudget(interviewMaxSeconds: number | null | undefined,
                             primaryTotalAll: number | null | undefined): AnswerBudget | null
```

`null` when either input is missing, non-finite or ≤ 0, or when `max = Math.floor(interviewMaxSeconds / primaryTotalAll)`
is < 1; otherwise each threshold is `Math.round(max * fraction)`. Inputs: `session.interviewMaxSeconds` (from
`/start`) and `outline.primary_total_all`. The total is stable across the interview (all competencies), so the
budget never shifts mid-interview. Guidance only (R1, R2): the bar never ends an answer.

**Remaining time (owner decision 2026-10-14): both renderings, side by side.** The duration section shows the
approximate sentence "Restano circa {N} minuti" with `N = Math.ceil(remaining / 60)`, AND the exact
`InterviewTimer` countdown beside it, labelled "Tempo rimanente".
- `remaining` is the page-owned `interviewRemaining`, already bound as `question-seconds` and updated on every
  `tick` (`InterviewSession.vue:119-122`); `CallPanel` derives `N` from that prop, no second clock.
- The sentence is a vue-i18n plural (`… {n} minuto | … {n} minuti`), plain text, not a live region; it is hidden
  when `remaining ≤ 0`.
- `InterviewTimer` (whole-interview countdown, V4) is unchanged, stays the only timeout enforcement and the only
  `role="timer"` (assertive in its last 10 s), and stays rendered whenever `questionSeconds` is defined,
  outside every visibility gate: the enforcement must never depend on a display condition.

### D12. Outline fetch lifecycle (client)

`app/composables/useInterviewOutline.ts`, per page instance (not module state):
`{ outline: Readonly<Ref<Outline | null>>, refresh(): Promise<void> }`, `Outline` derived from
`operations['outline.show']['responses'][200]['content']['application/json']`.

- `refresh()` is single-flight with one trailing re-run: a call while a request is in flight marks it dirty and
  the request re-runs once when it settles (a boundary during the first fetch is never lost).
- Called by `InterviewSession.vue`: when `callStageLive` first becomes true, and on every `sessionId` change while
  live (a boundary, a continuation, a re-offer). Not per utterance: `primary_index` covers "domanda k di n".
- Failure keeps the previous value (or `null`); never throws, never blocks the interview. With `null` the
  storyboard and the budget bar are hidden and every name falls back to its i18n label.
- **No server caching.** The payload changes at each boundary and costs a handful of indexed reads; a cache
  would need invalidation on `/end`, `/start` and retry authorization for no measurable gain.

`primaryIndex: Readonly<Ref<number | null>>` lives in `useInterviewSession`: set from the 202 body in both
`sendUtterance` (`:988-992`) and `deliverUtterance` (`:889-896`) only when the line's `dbSessionId` equals the
current `sessionId`; reset to `null` on a successful `/start` and on `sessionId` change. Sends are serialized
(`directUtterancesInFlight`), so last-write order is spoken order.

### D13. Header: `BrandCanvas` plate opt-out and `CallHeader`

- `BrandCanvas` gains `plate?: boolean` (default `true`). `false` renders the `<img>` without the white plate
  (D6 trade-off accepted). The `header-end` wrapper changes from `ml-auto flex items-center gap-3` to
  `ml-auto flex min-w-0 flex-1 items-center justify-end gap-3`: pre-interview `InterviewSteps` stays at the same
  right edge (pixel-unchanged, pinned by the existing screenshot matrix), and the live header can span the row.
- `InterviewSession.vue` passes `:plate="!callStageLive"` and renders `<CallHeader>` in `#header-end` when
  `callStageLive` (the existing `v-if="preInterviewStep"` branch is untouched).
- **`CallHeader`** (new organism, `components/organisms/CallHeader.vue`), presentational, props:
  `title: string` (already localized), `elapsedSeconds: number`, `captionsEnabled: boolean`,
  `micMuted: boolean` (the VISUAL state, computed by the page as `session.micMuted || session.handoverInFlight`,
  D9 rule 5), `micDisabled: boolean` (`session.handoverInFlight`); emits `toggle-captions`, `toggle-mic`; slot
  `exit` (the page puts `CallExitDialog` there, moved out of `CallPanel`).
- **Layout:** title `mr-auto min-w-0 line-clamp-2 text-base font-semibold text-on-primary`; then the clock;
  then the three controls, each 44 px (`h-(--spacing-control)`), so the header content stays ≤ 2.75 rem and
  `IntegrityToaster`'s `OFFSET.top` (`5.25rem`, `components/molecules/IntegrityToaster.vue:61-62`) still clears
  it: no toaster change.
- **Clock: has an accessible name, is not a live region.** `<p data-testid="call-header-clock"><span class="sr-only">{{ t('interview.call.header.elapsed_sr') }}</span> <time class="font-mono tabular-nums text-on-primary">{{ formatClock(elapsedSeconds) }}</time></p>`:
  a screen-reader user reaching it hears "Tempo trascorso 03:12"; no `aria-live`, no `role="timer"` (D18), so
  it never announces each second. It does not rely on the panel's "03:12 / 25:00", which is hidden until the
  server states a maximum: the header clock is the elapsed time that is always available.
- **Controls:** white outline buttons (card tokens on white keep their measured contrast on any brand canvas),
  `aria-pressed` toggles with a constant visible label ("Sottotitoli", "Microfono"), an icon that swaps (on /
  slashed) so state is never colour alone; pressed = feature on. The microphone control is `aria-disabled` (not
  `disabled`, so it stays focusable and its state is still announced) while `micDisabled`, and shows unpressed
  + slashed icon while `micMuted`. Canvas focus rule: 2 px `--color-on-primary` outline (§7.0.1).
- **Exit:** `CallExitDialog`'s trigger (`CallExitDialog.vue:4-11`) shows the short visible label
  `interview.call.exit.short` ("Esci" / "Exit") and carries `aria-label="$t('interview.call.exit.label')"`, whose
  value is unchanged ("Esci, riprenderai dopo" / "Exit, you can resume later"): the accessible name starts with
  the visible text (WCAG 2.5.3 Label in Name) and keeps the resume hint. The dialog body is unchanged.
- **Title (O2):** `interview.call.header.title_with_subject` with `subject` = `role_name` for `standard`, the
  localized `interview.call.header.potential` for `potential`; `interview.call.header.title` alone when the
  outline is missing or a `standard` role name is null.
- Tab order: Sottotitoli, Microfono, Esci (header, before `<main>`), the captions region, the help link.

### D14. "Intervista" panel

`CallPanel` stays the organism (filename kept, arch-guarded), restructured into three sections, each
`<section aria-labelledby>` with a small uppercase `<p>` label (no headings, so the page's heading outline is
unchanged):

1. **Tempo di risposta** → new molecule `CallAnswerTimer.vue`, props `seconds`, `phase`, `budget`, `micMuted`
   (the candidate's INTENT, not the visual state: the hint tells the candidate to unmute, which they cannot do
   during a handover):
   - a big plain `<time>` (`formatClock(seconds)`), **no `role="timer"` and no `aria-live`** (D18: exactly one
     timer role on the page, the enforcement countdown);
   - the phase chip (`Badge`, not a live region: announcing each phase would bury the question), text from
     `interview.call.answer.status.{listening|waiting|answering}`: "L'intervistatore sta parlando",
     "In attesa della tua risposta", "Stai rispondendo"; no chip while `idle`;
   - while `micMuted`, a text hint `interview.call.answer.muted_hint` ("Microfono disattivato: l'intervistatore
     non ti sente"), plain text with the slashed-mic icon `aria-hidden`;
   - when `budget !== null`, the bar: a track `aria-hidden="true"` with zones `[0,min)`, `[min,idealFrom)`,
     `[idealFrom,idealTo]`, `(idealTo,max]`, the elapsed fill in `--color-primary-ink` (≥ 3:1 on white), clamped
     at `max`; under it real text labels "Min 1:15 · Ideale 1:52–3:45 · Max 5:00" carrying the same information.
2. **Percorso** → two parts:
   - **Competency progress**, kept from today's panel (`CallPanel.vue:7-21`, same `ended`/`total` props, same
     clamp `n = min(max(ended,0)+1, total)`): the text "Competenza {n} di {total}" and the `ProgressBar` with the
     same string as its value text. The denominator is the server's `total_competencies` (`session.totalCompetencies`,
     fed by `/end`, `useInterviewSession.ts:1082-1084`), **never the outline's length**, so the count and the
     server's completion rule cannot disagree. Hidden while `total` is null or 0, as today. The wording
     ("Competenza … di …") is deliberately distinct from the storyboard's "domanda k di n", so the two counters
     are never confused.
   - **Storyboard** → new molecule `CallStoryboard.vue`: an `<ol>`, `aria-current="step"` on the current item;
     done = check glyph + sr "completata"; upcoming = the ordinal numeral; retry = a circular-arrow glyph +
     "Da ripetere"; current = ring + the question line below. Accents `--color-primary-ink` on white. Prop items
     carry `{ name, ordinal, status, primaryTotal }`, never a code. The list scrolls inside the panel (`min-h-0
     flex-1 overflow-y-auto`, `tabindex="0"` when it overflows).
     - **Name:** `item.name`, which the page builds as `outline.name ?? t('interview.call.storyboard.unnamed', { ordinal })`
       ("Competenza {ordinal}"); the D4 server rule already tried the project language and the catalogue default
       language. Never the code.
     - **Question line (current item only), with `k = primaryIndex`, `n = primaryTotal`:** when `k` is a number
       and `n ≥ 1`, "In corso · domanda {clamp(k, 1, n)} di {n}"; when `k` is `null` or `n = 0`, "In corso" with
       no counts. So `0` reads "domanda 1 di n" (the first primary is being asked) and an overshoot reads "n di n";
       "domanda 0 di n" and "domanda 4 di 3" cannot render.
3. **Durata dell'intervista** (inline): "03:12 / 25:00" (existing keys, shown under the existing condition),
   `ProgressBar` of elapsed over max, then the remaining time: the approximate sentence "Restano circa {N}
   minuti" with `InterviewTimer` ("Tempo rimanente", exact) beside it (D11). Then the help link slot.

Removed from the panel: the `exit` slot (moved to the header) and the label "Domanda {n} di {total}" (its value
moves to the "Competenza {n} di {total}" wording above). `ended`/`total` props are kept.

### D15. `CallStage` grid and sizing (1024-1440)

- **≥ 1280 (`xl`):** one row, `grid-cols-[minmax(0,1fr)_var(--spacing-call-panel)]`,
  `[grid-template-areas:'layer_panel']`. The panel cell is `xl:h-0 xl:min-h-full`, so it never sets the row
  height and fills whatever the row is; the storyboard scrolls inside it.
- **Hosted** (`HOSTED_HEIGHT_CAP`, still the only viewport-height place): the width cap's chrome term becomes
  `9rem` beside the panel (header `pt-6` 1.5 + controls 2.75 + `main lg:py-8` 4 = 8.25 rem, plus slack) and
  `22rem` when the panel is a strip; and the stage gains `xl:min-h-[calc(100dvh_-_9rem)]`, so the panel gets the
  viewport height even when the 16:9 tile is width-limited. These two numbers are the calibration knob; the
  e2e "fits the viewport" gate at 1280x800, 1440x900, 1920x1080 is what sets them.
- **Embedded:** no viewport unit (arch rule 1 unchanged); the panel equals the tile height and scrolls.
- **< 1280 (1024-1279):** one column, `'layer' 'panel'`; the panel is a strip: answer timer and duration side
  by side, the progress and storyboard below them, wrapping. Vertical scroll is allowed here, as today; the
  existing 1024 px "layout valid" gate stays.
- `--spacing-call-panel`: `18rem` → **`22rem`** (owner-confirmed 2026-10-14; `main.css:121`, `DESIGN.md` §3.3).
  At 1280 the tile is then 1200 − 352 − 24 = 824 px wide (463 px tall); at 1440, 984 px (553 px tall).
- `components/molecules/IntegrityToaster.vue`: unchanged (D13); its top-left position still lands on the tile's
  top-left corner, the captions are at the bottom.

### D16. Tile name chips

`CallTile`'s chip changes from `bg-avatar-bg/80` to `bg-black/60 text-white` for both tiles (one class: white on
black/60 over a white frame composites to about #666, 5.7:1). `CallTile` keeps `name` as a prop. The interviewer
name is `outline.avatar_name ?? t('interview.call.interviewer_name')`; `CallSelfView` gains `name?: string`,
defaulting to `t('interview.call.you')`, and the page passes `outline.candidate_name`.
`call-tile-contrast.spec.ts` is updated to the new pair.

### D17. Captions preference

`captionsEnabled = useLocalStorage('beai:interview:captions', true)` (`@vueuse/core` 14, already a dependency;
SSR-safe), in `InterviewSession.vue`. A UI preference, not personal data, so no consent gate. (The microphone
intent is deliberately NOT persisted: D9, a reload starts unmuted.)

### D18. Architecture test rewrite (`tests/unit/arch/call-ui-arch.spec.ts`), stricter where it changes

| Rule | Today | After |
|---|---|---|
| Component inventory | 7 `Call*.vue` | 10: adds `organisms/CallHeader.vue`, `molecules/CallAnswerTimer.vue`, `molecules/CallStoryboard.vue` |
| Viewport-height units | only `HOSTED_HEIGHT_CAP`, one use | unchanged (the new `min-h` lives inside the same array) |
| Panel and competencies | "names no competency", imports only 4 modules | **The panel names competencies but never carries a code**: no `/\bcode\b/` and no `competency_code` in `CallPanel`, `CallStoryboard`; no session or outline composable import in any `Call*.vue` (`useInterviewSession`, `useInterviewOutline`, `useCandidateSession`); `CallPanel` imports exactly `vue`, `InterviewTimer`, `ProgressBar`, `useInterviewClock`, `CallAnswerTimer`, `CallStoryboard` |
| Page bindings | 8 named bindings on `<CallPanel>` | an exact new list on `<CallPanel>`: `ended`, `total`, `elapsed-seconds`, `max-seconds`, `question-seconds`, `timer-key`, `tick`, `expired`, `answer-seconds`, `answer-phase`, `mic-muted`, `budget`, `storyboard`, `primary-index`; and an exact list on `<CallHeader>`: `title`, `elapsed-seconds`, `captions-enabled`, `mic-muted`, `mic-disabled`, `toggle-captions`, `toggle-mic` |
| Literals | no literal word in any `Call*.vue` | unchanged, applies to the 3 new files |
| Timer role | — | **exactly one `role="timer"`** under `app/components/**`, in `InterviewTimer.vue` (V4); `CallAnswerTimer` and `CallHeader` use plain `<time>` |
| Captions | — | `CallQuestion` is rendered inside the `avatar-layer` element and nowhere else (the captions region is unique) |

## Data Flow

```
Live entry and boundaries
 InterviewSession.vue        useInterviewOutline        api OutlineController → BuildInterviewOutline
   callStageLive=true ─────→ refresh() ───GET /candidate/interview/outline──→ CompetencyProgress.ordered()
   sessionId changes ──────→ refresh() (single-flight,       + sessions (participant, project)
                              trailing re-run)               + Role (revision via resolver), Competency by id
                         ←── outline {assessment_type, role_name, avatar_name, candidate_name,
                                       primary_total_all, competencies[{name|null, ...}]}

Every transcript line
 provider 'transcript' → useInterviewSession.sendUtterance ──POST /utterance──→ UtteranceController
                                                            ←── 202 {boundary_due, primary_index}
   primaryIndex = primary_index (if line.session == sessionId)
   boundary_due → assertBoundary (unchanged)

Render
 outline + primaryIndex ──→ CallStoryboard   (status, "domanda clamp(k,1,n) di n")
 /end ended/total_competencies ──→ CallPanel "Competenza n di N" + bar
 interviewMaxSeconds + outline.primary_total_all ──→ answerBudget() ──→ CallAnswerTimer bar
 useSpeakerTurn.speaker + sessionId ──→ useAnswerTimer ──→ CallAnswerTimer <time> + chip
 micMuted (intent) ──→ CallAnswerTimer hint; AvatarPlayer seed; restoreMic
 micMuted || handoverInFlight ──→ CallHeader mic visual; handoverInFlight ──→ mic disabled
 interviewRemaining (unchanged owner) ──→ "Restano circa N minuti" + InterviewTimer (expired → timeout /end)
 currentCaption + avatar name + captionsEnabled ──→ CallQuestion (overlay / sr-only region)
```

Sequence at a competency boundary (single-session Tavus continuation), candidate muted beforehand:

```
candidate     useInterviewSession            api                      useInterviewOutline
   |  toggle → setMicMuted(true): intent=true, provider muted
   |  (silence) → /utterance ───────────────→ 202 {boundary_due:true, primary_index:3}
   |          assertBoundary: whenAvatarSilent → provider.setMicMuted(true) [forced]
   |          /end ─────────────────────────→ 200 continue
   |          /start ───────────────────────→ 200 continuation (new session row)
   |          sessionId := new → primaryIndex:=null, answer timer idle; intent STAYS true
   |          applyContinuation ack → restoreMic → setMicMuted(intent=true) ─────→ refresh()
   |                                          GET /outline ←───────────────┘
   |                                          next competency now `current`
```

A boundary that ends with a NEW provider handle (handover or restart): the new `AvatarPlayer` seeds its uplink
with `muted || micMuted` (`AvatarPlayer.client.vue:258`), so the intent is re-applied by the seed itself.

## File Changes

| File | Action | Description |
|---|---|---|
| `DESIGN.md` | Modify | §3.3 token 22rem; §3.1 `--color-primary-caption` (4.5:1 on avatar-bg); §7.0.1 header bullet (bare logo while live, `header-end` spans the row, `CallHeader`, clock with accessible name); §7.3 diagram and bullets: header controls and title, captions overlay replaces the question band, "Intervista" panel sections, answer bands as guidance only, answer timer counts from the end of the question, approximate + exact remaining time, storyboard names competencies (reversal recorded) with generic fallback, competency progress kept, persona name with fallback, `bg-black/60` chips, mute-is-silence note and mute persistence, Exit visible "Esci" with resume hint as accessible name |
| `api/app/Support/Interview/CompetencyProgress.php` | Create | `ordered()`, `isOpen()`, `resolveNext()` (D2) |
| `api/app/Http/Controllers/Candidate/InterviewController.php` | Modify | `resolveNextCompetency`/`competencyPayload` moved out; `freshRemainingCompetencies` uses `ordered()`; constructor injects `CompetencyProgress` |
| `api/app/Actions/Interview/BuildInterviewOutline.php` | Create | D3/D4, including the name rule |
| `api/app/Http/Controllers/Candidate/OutlineController.php` | Create | `show()`, `@scramble-return` |
| `api/routes/api.php` | Modify | `Route::get('/outline', [OutlineController::class, 'show'])` in the `interview` group |
| `api/app/Http/Controllers/Candidate/UtteranceController.php` | Modify | D6 |
| `api/app/Rules/PersonaDisplayName.php` | Create | D7: the one rule (`problem()`, `MAX`, provider denylist) |
| `api/app/Http/Controllers/Concerns/ValidatesAvatarTemplateWrites.php` | Modify | persona rules on store and update + `mergePersona()` (unset on clear) |
| `api/app/Http/Controllers/AvatarTemplateController.php`, `Api/PlatformAvatarTemplateController.php` | Modify | apply `mergePersona()` on store and update |
| `api/app/Support/AvatarTemplates/TemplateDocument.php` | Modify | `flatten()` trims `persona.display_name` and unsets a blank one |
| `api/app/Http/Controllers/AvatarTemplatePortabilityController.php` | Modify | `reject()` refuses an entry whose `persona.display_name` fails `PersonaDisplayName::problem()` |
| `api/app/Models/AvatarTemplate.php` | Modify | `personaDisplayName()` |
| `api/app/Http/Resources/AvatarTemplateResource.php` | Modify | `persona.display_name` in array and `@scramble-return` (inherited by `PlatformAvatarTemplateResource`) |
| `api/tests/Helpers/PublicApi/ExposureCatalogue.php` | Modify | classify `avatar_template.persona.display_name` (`T-EXPOSE-001`) |
| `api/openapi.json`, `frontend/openapi.json`, `backoffice/openapi.json`, `*/types/api.ts` | Regenerate | Scramble export (PostgreSQL) + `bun run codegen` |
| `api/tests/Feature/Candidate/InterviewOutlineTest.php` | Create | shape, language and name fallback, potential, retry/re-offer, primaries snapshot, tenant isolation, status guard |
| `api/tests/Unit/Support/Interview/CompetencyProgressTest.php` | Create | `isOpen` truth table |
| `api/tests/Unit/Rules/PersonaDisplayNameTest.php` | Create | rule truth table, message never echoes the vendor |
| `api/tests/Feature/C7a/...Utterance...` | Modify/Create | `primary_index` on primary, follow-up, re-ask, no primaries |
| `api/tests/Feature/AvatarTemplates/...` | Modify/Create | persona validation on create/update/import, merge, unset on clear, resource, duplicate, export/import |
| `backoffice/app/components/organisms/AvatarTemplateForm.vue` | Modify | draft field, input, `persona` in `submit`, 422 key `persona.display_name` |
| `backoffice/app/types/avatar-template.ts` | Modify | follows the generated type |
| `backoffice/i18n/locales/{it,en}.json` | Modify | `avatar_templates.form.persona_display_name`, `_hint`, `errors.personaDisplayNameInvalid` (generic, names no vendor) |
| `frontend/app/composables/useInterviewOutline.ts` | Create | D12 |
| `frontend/app/utils/answer-budget.ts` | Create | D11 |
| `frontend/app/composables/useAnswerTimer.ts` | Create | D10 |
| `frontend/app/composables/useInterviewSession.ts` | Modify | `primaryIndex`, `micMuted`/`setMicMuted` (no reset on `sessionId`), `restoreMic` at the six re-open sites |
| `frontend/app/components/AvatarPlayer.client.vue` | Modify | `micMuted` prop; seed at `:258` becomes `props.muted \|\| props.micMuted` (D9 rule 3) |
| `frontend/app/components/organisms/BrandCanvas.vue` | Modify | `plate` prop, `header-end` wrapper classes |
| `frontend/app/components/organisms/CallHeader.vue` | Create | D13 |
| `frontend/app/components/molecules/CallExitDialog.vue` | Modify | trigger shows `exit.short`, `aria-label` = `exit.label` |
| `frontend/app/components/molecules/CallQuestion.vue` | Modify | overlay look, `speakerName`, `visible`, `text-primary-caption` prefix (D8) |
| `frontend/app/composables/useBrandTheme.ts` | Modify | `--color-primary-caption` in `BRAND_DERIVED_TOKENS` + `DERIVE` |
| `frontend/app/components/molecules/CallTile.vue` | Modify | chip `bg-black/60` |
| `frontend/app/components/molecules/CallSelfView.client.vue` | Modify | `name` prop |
| `frontend/app/components/organisms/CallPanel.vue` | Modify | three sections, competency progress kept, approximate + exact remaining (D14, D11) |
| `frontend/app/components/molecules/CallAnswerTimer.vue`, `CallStoryboard.vue` | Create | D14 |
| `frontend/app/components/organisms/CallStage.vue` | Modify | grid, cap, no `#question` (D15) |
| `frontend/app/assets/css/main.css` | Modify | `--spacing-call-panel: 22rem`; `--color-primary-caption` Quint default |
| `frontend/app/components/InterviewSession.vue` | Modify | composition, outline refresh watchers, captions flag, `:mic-muted` on `AvatarPlayer`, header/panel bindings |
| `frontend/i18n/locales/{it,en}.json` | Modify | keys below |
| `frontend/tests/unit/**`, `frontend/tests/e2e/interview-call.spec.ts`, `browser-gate-middleware.spec.ts` | Modify | see Testing |
| `ParticipantResource`, `/v1`, `useExitRedirect.ts`, `components/molecules/IntegrityToaster.vue`, `InterviewTimer.vue`, `--color-primary-light` | Unchanged | — |

### i18n keys (`frontend`, `interview.call.*`)

| Key | it | en |
|---|---|---|
| `header.title` | Colloquio di assessment | Assessment interview |
| `header.title_with_subject` | Colloquio di assessment · {subject} | Assessment interview · {subject} |
| `header.potential` | Potenziale | Potential |
| `header.captions` | Sottotitoli | Captions |
| `header.microphone` | Microfono | Microphone |
| `header.controls_label` | Controlli del colloquio | Interview controls |
| `header.elapsed_sr` | Tempo trascorso | Elapsed time |
| `panel_label` (value changed) | Intervista | Interview |
| `answer.label` | Tempo di risposta | Answer time |
| `answer.status.listening` | L'intervistatore sta parlando | The interviewer is speaking |
| `answer.status.waiting` | In attesa della tua risposta | Waiting for your answer |
| `answer.status.answering` | Stai rispondendo | You are answering |
| `answer.muted_hint` | Microfono disattivato: l'intervistatore non ti sente | Microphone off: the interviewer cannot hear you |
| `answer.bands` | Min {min} · Ideale {from}–{to} · Max {max} | Min {min} · Ideal {from}–{to} · Max {max} |
| `answer.bands_note` | Tempi suggeriti, non vincolanti | Suggested times, not enforced |
| `storyboard.label` | Percorso | Path |
| `storyboard.competency_progress` | Competenza {n} di {total} | Competency {n} of {total} |
| `storyboard.unnamed` | Competenza {ordinal} | Competency {ordinal} |
| `storyboard.current` | In corso | In progress |
| `storyboard.current_question` | In corso · domanda {k} di {n} | In progress · question {k} of {n} |
| `storyboard.done_sr` | completata | completed |
| `storyboard.retry` | Da ripetere | To be repeated |
| `duration.label` | Durata dell'intervista | Interview duration |
| `duration.remaining_approx` | Resta circa {n} minuto \| Restano circa {n} minuti | About {n} minute left \| About {n} minutes left |
| `remaining_label` | Tempo rimanente | Time remaining |
| `exit.short` | Esci | Exit |
| `exit.label` (value unchanged, now the accessible name) | Esci, riprenderai dopo | Exit, you can resume later |

Removed: `progress` (replaced by `storyboard.competency_progress`), `question_timer_label` (replaced by
`remaining_label`), `duration_label` (replaced by `duration.label`). There is no `answer.status.muted` key. Kept:
`question_region`, `duration_value`, `duration_sr`, `interviewer_name`, `you`, speaking labels, `exit.*`,
`help.*`.

## Interfaces / Contracts

```ts
// frontend: useInterviewSession additions
primaryIndex: Readonly<Ref<number | null>>
micMuted: Readonly<Ref<boolean>>          // intent; reset only by a reload
setMicMuted(muted: boolean): void

// frontend: AvatarPlayer addition (uplink-only, read once at the seed)
micMuted?: boolean                        // default false; seed = muted || micMuted

// frontend: storyboard item handed to CallPanel/CallStoryboard (no code by contract)
interface StoryboardItem { name: string; ordinal: number; status: 'done' | 'current' | 'upcoming' | 'retry'; primaryTotal: number }
// `name` is already resolved by the page: outline name ?? t('interview.call.storyboard.unnamed', { ordinal })
```

```php
// api: utterance 202
#[Response(202, description: '...', type: 'array{boundary_due: bool, primary_index: int}')]
// api: AvatarTemplateResource adds
'persona' => ['display_name' => $template->personaDisplayName()],
// api: the one display-name rule
final class PersonaDisplayName implements ValidationRule {
    public const MAX = 60;
    public static function problem(mixed $value): ?string; // null = acceptable; message never names the vendor
}
```

## Testing Strategy

Strict TDD: every slice starts from the RED tests named here.

| Layer | What | Approach |
|---|---|---|
| Pest unit | `CompetencyProgress::isOpen` truth table; `resolveNext` equals the old method on the existing fixtures; `PersonaDisplayName::problem()`: 60 ok / 61 refused, `<`, `>`, a control char, each of the five provider names in mixed case and spaced ("Hey Gen", "live kit"), a non-vendor word containing none of them accepted, and the message never contains the matched word | pure + DB fixtures |
| Pest feature | outline: project-language names in `position` order; name falls back to `en` when the project-language translation is blank, and is `null` when both are blank (never the code); `role_name` null for `potential`; `retry` for an errored-with-attempts session and for an evaluation-retry reset; `upcoming` with no row; snapshot vs live primaries; `avatar_name` null for an invalid stored value; cross-tenant (two orgs, same codes) and terminal-status refusal; 401 | `actingAs` candidate JWT, factories |
| Pest feature | `/utterance` `primary_index`: 1 after the first primary, unchanged after a follow-up and a verbatim re-ask, 0 with no primaries; `question_asked` event index unchanged | existing C7a fixtures |
| Pest feature | persona: 422 on create AND update for 61 chars, `<`, a control char, a provider name, an unknown persona key; the 422 body does not contain the vendor name; import refuses the same values per entry; clearing the field removes the key (no stored `null`) and keeps imported keys; merge keeps imported keys; resource returns it; duplicate and export/import keep it; `ExposureTest` green with the new entry | — |
| Contract | `ResourceMatchesSpecTest`, `scramble:export` diff clean, frontend/backoffice `check-client-drift.sh` | CI |
| Vitest | `answerBudget` (O1 values, `(1200, 0)` → null, rounding); `useAnswerTimer` table with fake timers (12 s of silence after the question reads 12 in `waiting`; candidate speech continues the count without reset; avatar resets; `sessionId` change → idle); `useInterviewOutline` single-flight + trailing re-run + failure keeps value; `useInterviewSession` mic precedence (intent survives a `noop` boundary AND a `sessionId` change; `restoreMic` re-applies it after a handover; `setMicMuted` during a forced mute touches no provider), `primaryIndex` stale-session guard; `AvatarPlayer` seeds `true` when `micMuted` is true with `muted` false, and `true` when `muted` is true with `micMuted` false | `vi.useFakeTimers`, provider fakes |
| Vitest | `BrandCanvas` plate on/off (`brand-canvas.spec.ts:286-301` extended, not replaced); `CallHeader` (title variants O2, `aria-pressed`, mic shows muted and is `aria-disabled` while `micDisabled`, clock has its sr label and no `aria-live`/`role`); `CallExitDialog` visible "Esci" with accessible name containing it and the resume hint; `CallQuestion` captions off keeps the live region text and drops `tabindex`; `brand-theme.spec.ts`: `--color-primary-caption` ≥ 4.5:1 on `#0f172a` for the fixture colours and the Quint default; `CallStoryboard` statuses, the `k` clamp table (`null`, `0`, `k > n`, `n = 0`), the generic name fallback; `CallPanel` "Competenza n di N" from `ended`/`total`, approximate minutes `ceil` and plural, `InterviewTimer` rendered whatever the other gates; `CallAnswerTimer` hides the bar with a null budget, shows the muted hint, has no `role`; `CallTile` contrast pair; arch rules (D18) including exactly one `role="timer"` | Vue Test Utils |
| Playwright (Chromium + WebKit) | tab order Sottotitoli → Microfono → Esci → question region → help; axe zero violations on live, exit dialog, suspended, at `#ffd400` and `#771aaf`; no vertical scroll at 1280x800, 1440x900, 1920x1080; panel width 22 rem at 1440; layout valid at 1024 (`browser-gate-middleware.spec.ts`); captions off hides the overlay and keeps the region; mute persists across a competency boundary (mock provider); pre-interview screenshots unchanged; 1440x900 live snapshots regenerated on purpose | mock provider |

## Threat Matrix

N/A — no shell, subprocess, VCS/PR automation, executable-file classification or process-integration boundary.
The HTTP trust boundary this change touches (one candidate GET, one admin write, one admin import) is covered by
D5 (tenant scoping, no route parameter) and D7 (one input rule at all three write boundaries, read-side
degradation).

## Migration / Rollout

No migration: `avatar_templates.persona` is an existing nullable JSON column. All api changes are additive.

### Delivery: `feature-branch-chain` (owner decision 2026-10-14)

- **One tracker branch per repo**, `feature/live-interview-call-chrome`, in the wrapper, `api`, `backoffice` and
  `frontend`. Only the tracker merges to `develop` (Git Flow), through one tracker PR per repo.
- **Child PRs:** the first slice of a repo targets that repo's tracker; every later slice targets the
  immediately previous slice's branch. If GitHub shows earlier slices in a child diff, retarget/rebase until the
  diff is clean.
- Budget: ~400 authored lines (additions + deletions) per child PR; generated `openapi.json`, `types/api.ts` and
  Playwright snapshot images excluded.

| Order | Slice | Repo | Branch | Base | Content | ~Lines |
|---|---|---|---|---|---|---|
| 0 | Docs | wrapper | `feature/licc-0-design-docs` | wrapper tracker | `DESIGN.md` §3.1, §3.3, §7.0.1, §7.3 + this change's artifacts. Merged before C1a. | ~170 |
| 1 | A.i | api | `feature/licc-a1-competency-progress` | api tracker | `CompetencyProgress` extraction (`ordered`, `isOpen`, `resolveNext`), controller rewiring, unit test; existing `/start` tests unmodified | ~200 |
| 2 | A.ii | api | `feature/licc-a2-outline` | `feature/licc-a1-competency-progress` | outline action (status, name rule), controller, route, feature tests, `openapi.json` export | ~330 |
| 3 | A.iii | api | `feature/licc-a3-utterance-persona` | `feature/licc-a2-outline` | `primary_index`; `PersonaDisplayName` rule, form rules, `mergePersona` (unset on clear), import (`TemplateDocument`, `reject()`), accessor, resource, `ExposureCatalogue`, tests, `openapi.json` export | ~360 |
| — | api release | api | api tracker → `develop` → `release/*` | — | one minor release containing A.i-A.iii (api-first recipe) | — |
| 4 | A2 | backoffice | `feature/licc-bo-persona-name` | backoffice tracker | `openapi.json` + codegen, form field, payload, 422 mapping, i18n, test. Released in the SAME release window as the api (O3). | ~140 |
| 5 | B.i | frontend | `feature/licc-b1-outline-data` | frontend tracker | `openapi.json` + codegen, `useInterviewOutline`, `answerBudget`, `primaryIndex`, tests | ~260 |
| 6 | B.ii | frontend | `feature/licc-b2-mic-answer-timer` | `feature/licc-b1-outline-data` | mic intent + `restoreMic` + `AvatarPlayer` `micMuted` seed, `useAnswerTimer`, captions preference, tests | ~320 |
| 7 | C1a | frontend | `feature/licc-c1a-call-header` | `feature/licc-b2-mic-answer-timer` | `BrandCanvas` plate + `header-end`, `CallHeader` (title, clock sr label, captions/mic controls with handover visual state), `CallExitDialog` labels, header i18n, unit tests, arch D18 (inventory for `CallHeader`, header bindings, single `role="timer"`) | ~340 |
| 8 | C1b | frontend | `feature/licc-c1b-captions-overlay` | `feature/licc-c1a-call-header` | `CallQuestion` overlay, `--color-primary-caption` (`useBrandTheme`, `main.css`, tests), `CallTile` chips + contrast spec, `CallSelfView` name, `CallStage` `#question` removal, arch captions placement, e2e captions off + tab order + axe on live | ~330 |
| 9 | C2a | frontend | `feature/licc-c2a-interview-panel` | `feature/licc-c1b-captions-overlay` | `CallPanel` three sections (competency progress kept, approximate + exact remaining), `CallAnswerTimer` (chip, `<time>`, muted hint, bands), `CallStoryboard` (clamp, generic name), panel i18n, unit tests, arch D18 panel rules + inventory | ~390 |
| 10 | C2b | frontend | `feature/licc-c2b-stage-sizing` | `feature/licc-c2a-interview-panel` | `CallStage` grid/cap, `--spacing-call-panel: 22rem`, e2e fit/width/1024 layout, mute-across-boundary e2e, snapshot regeneration | ~200 |

No child slice exceeds ~400; C2a is the tightest and is split again (storyboard / answer timer) if its
forecast at `sdd-tasks` exceeds the budget.

**R8 dependency (restated):** frontend PR #95 (`feature/seamless-primary-transition`, open against `develop`)
adds `boundaryInFlight` and the `whenAvatarSilent` gate that D9 relies on, and touches the same lines of
`InterviewSession.vue` (`:88`) and `useInterviewSession.ts`. The frontend chain therefore either:
- **starts after #95 merges:** the frontend tracker branches from `develop` once it contains #95; or
- **stacks on #95:** the frontend tracker branches from `feature/seamless-primary-transition`; B.i … C2b chain
  on it as above; when #95 merges, the tracker is rebased onto `develop` so its PR shows only this change.

The frontend tracker never starts from a `develop` that lacks #95, and its PR to `develop` is never merged
before #95.

**Release order:** api (A.i-A.iii) → backoffice (A2) and frontend (B.i … C2b), each consumer folding the
`openapi.json` sync into its own release. Rollback per slice as in the proposal; slice 0 reverts together with
C1a-C2b.

## Open Questions

- [ ] Evaluation-retry runs: `primary_total_all` counts every competency (stable budget), so the suggested time
      per answer is conservative when only some competencies are re-interviewed. Non-blocking; owner may prefer
      "competencies still to ask".
- [ ] "Competenza n di N" stays hidden during the first competency, because `total_competencies` reaches the
      client only from `/end` today (`useInterviewSession.ts:1082-1084`), although `/start` already returns it
      under `question_context` (`BuildInterviewSessionResponse.php:105`). Seeding it from `/start` is a one-line
      change but also alters the embed page (`pages/embed/[token].vue:282`); left out of scope unless the owner
      wants it. Non-blocking.
