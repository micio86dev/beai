# Assessment types

The platform supports two interview modes with distinct competency rules and question flows.

> **Display names.** The machine value `standard` is displayed as **Prontezza** (Italian) / **Readiness** (English); `potential` is displayed as **Potenziale** / **Potential**. Only the display name changes: the machine value `standard` stays in the API, the database and every payload.

## Prontezza / Readiness (`standard`)

**Purpose:** assess the classic soft skills associated with the candidate's organizational role.

| Aspect | Behaviour |
|---------|---------------|
| Competencies | The framework set for the role (PRS, STG, INN, …), type `standard` |
| Questions | The first question per competency may be predefined; the following ones are decided by the AI in real time |
| Flow | Adaptive conversation: probe deeper or switch competency |
| Typical target | A "readiness" assessment for an organizational level |

## Potential

**Purpose:** assess dimensions of **leadership potential** (Managing, Leadership Attributes).

| Aspect | Behaviour |
|---------|---------------|
| Competencies | Only **MTG** (Managing) and/or **LAT** (Leadership Attributes) |
| Questions | **Up to N predefined questions** per competency (N is a platform-configured **maximum**, default 4; it is never a fixed count), followed by AI follow-ups |
| Flow | The same adaptive conversation as the Prontezza (Readiness) type: the AI decides in real time whether to probe deeper or move on |
| Typical target | High-potential identification |

## Exclusivity rules

| Type | Admissible competencies |
|------|-------------------|
| Prontezza / Readiness (`standard`) | Classic framework competencies (PRS … INC) |
| Potential | Only MTG and/or LAT |

Prontezza (`standard`) and Potential competencies **cannot** be mixed within the same project.

## Choosing the type

- The type is set at **project creation**.
- Treat it as **immutable** for the lifetime of the project (changing the type on a live project creates inconsistencies for candidates already in progress).

## Impact on project configuration

Beyond role and competencies, a project defines:

| Option | Description |
|---------|-------------|
| Interview language | e.g. `it`, `en` |
| Pauses | How many competencies apart a pause is shown (e.g. every N competencies; `null` = no pause) |
| Nudges | The minimum answer character threshold before prompting for elaboration |
| Assessment type | Prontezza (`standard`) vs Potential |

## Impact on the candidate

- The candidate does **not** choose the type: it is inherited from the project configuration.
- The organizational role (ICO, FLL, …) may be passed at ingress and influence the context or the associated project, at the calling system's discretion.
