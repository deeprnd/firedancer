<!--
Tickoni release notes template.

Use this template for roadmap release documents under
`doc/strategy/roadmap/releases/`.

This template is based on `doc/strategy/roadmap/releases/m1.md`, which is the
current source of truth for how Tickoni release notes are written:

1. Start with a short "What Progressed In The Story" recap.
2. State plainly what the user can do now.
3. Offer a jump link for readers who want the changelog first.
4. Continue the Tickoni story with an "Episode" section.
5. Switch into concrete release notes with grouped sections:
   - Headline Features
   - Governance and Safety
   - Platform Work
   - Demo
   - What Comes Next

This is not a generic engineering changelog template. It is a product release
template with a story layer first and a factual release-note layer second.

Release label conventions:
  - Milestone release: `M{N}`
  - Epic release: `VX.Y`
  - Story release: `VX.Y.SN`
  - Task release: `VX.Y.SN.TN` (rare; usually too small for this template)
  - Hotfix release: use `Hotfix` or the approved patch label

Examples:
  - `M1 — The Paper Moon`
  - `V4.1 — Portfolio Guardrails`
  - `V5.6.S2 — Snapshot Review Surface`
  - `Hotfix — Replay Hash Repair`

How to build the content from roadmap work:
  - "What Progressed In The Story" should summarize what changed across the
    shipped stories, not list internal tasks.
  - "The user can now" bullets should be direct, observable outcomes.
  - "Headline Features" should group the biggest user-visible capabilities from
    the included stories. Keep this to 2-4 main features.
  - "Governance and Safety" should capture policy, audit, replay, no-bypass,
    approval, boundary, and fail-closed improvements. Keep this to 2-4 main
    improvements.
  - "Platform Work" should capture runtime, topology, tooling, setup, and
    infrastructure hardening that materially supports the release. Keep this to
    2-4 main improvements.
  - "Demo" should give one concrete command or flow that proves the release.
  - "What Comes Next" should point to the next major milestone and explain the
    next qualitative step in the product story.

Writing rules:
  - Keep the opening progress recap short and user-facing.
  - Keep the story episode as a continuation of the Tickoni lore, not as a
    marketing slogan dump.
  - Keep the release notes concrete and evidence-friendly.
  - Do not get lost in detail. Highlight only the most important, wow-level
    shipped outcomes.
  - Tie every section back to shipped roadmap stories, milestone scope, or
    observable product/runtime behavior.
  - Do not invent future execution authority, policy outcomes, or product
    capabilities that are not already decided in strategy docs.

Read before filling:
  - `doc/strategy/README.md`
  - `doc/strategy/roadmap/milestones/m{N}.md` for the release's milestone
  - included roadmap epic/story docs
  - `doc/knowledge/architecture.md`
  - `doc/knowledge/tile-topology.md` when platform/runtime work is included
  - `doc/execution/development.md`
  - `doc/execution/testing-tickoni.md`
-->

## What Progressed In The Story

[One short paragraph describing what changed in this release in plain
user-facing language.]

The user can now:

* [do a new meaningful thing]
* [see or inspect a new outcome]
* [understand why something was allowed, denied, resized, or blocked]
* [replay, review, approve, or verify a result]

**Want the changelog first? [Skip the Tickoni story and jump to the release notes ↓](#actual-release-notes)**

## Episode [XX]: [Release Name]

[Continue the Tickoni story here. Keep it short-to-medium length and connected
to the actual release outcome.]

[Suggested shape:
Previously, in the [prior story location or state]...

[Set the scene.]
[Show the user's old frustration or limit.]
[Introduce what Tickoni can do differently now.]
[End on the specific contract this release proves.]
]

<a name="actual-release-notes"></a>

# Release Notes

## Release: [M{N} milestone | VX.Y epic | VX.Y.SN story | Hotfix] — [Release Name]

[One paragraph explaining what this release completes.]

```text
[input] -> [gate or transformation] -> [observable outcome]
```

[One short paragraph on what is now true for the user or operator, what still
does not execute or bypass policy, and what evidence now exists.]

## Headline Features

<!--
List 2-4 main shipped user-visible capabilities only.
Choose the most impressive, user-visible outcomes.
Each subsection should map to one or more included stories.
Do not try to cover every shipped detail.
-->

### 1. [Feature name]

[What the user can now do.]

Examples of what to include:

* [new user action]
* [new visible object, view, or decision artifact]
* [new explanation, validation, or consequence view]

### 2. [Feature name]

[What changed and why it matters.]

Examples of what to include:

* [allowed path]
* [blocked or denied path with clear reason]
* [proposal, ticket, case, card, or review outcome]

### 3. [Feature name]

[Describe another major story-derived capability.]

Examples of what to include:

* [before/after state]
* [scope or limit enforcement]
* [saved object, review object, or replay object]

<!-- Add more numbered feature sections as needed. -->

## Governance and Safety

<!--
Capture governance, audit, replay, no-bypass, fail-closed, approval, and
security-relevant work that shipped in the release. List only 2-4 main trust
or control wins. Keep this section even if brief. If there was no material
change, state that explicitly.
-->

### 1. [Governance or safety improvement]

[What boundary now exists or improved.]

Examples of what to include:

* [policy gate or capability scope]
* [audit record or evidence trail]
* [replay substitution or divergence detection]
* [approval, denial, or no-bypass rule]
* [model/tool/adapter boundary hardening]

### 2. [Governance or safety improvement]

[Describe another material trust/control improvement.]

## Platform Work

<!--
Capture runtime, topology, process isolation, setup, tooling, observability,
performance, compatibility, or developer experience work that materially
supports the release. List only 2-4 main platform wins. Keep this tied to
shipped behavior, not internal churn.
-->

### 1. [Platform improvement]

[What hardened underneath the release and why it matters.]

Examples of what to include:

* [runtime/process isolation]
* [shared-memory or topology work]
* [UI or local-run support]
* [developer workflow or demo reliability]
* [metrics, diagnostics, or crash visibility]

### 2. [Platform improvement]

[Describe another supporting platform change.]

## Demo

[State the one command, flow, or review path that proves the release.]

```bash
[just target or exact command]
```

[Describe the expected observable output or steps.]

1. [step or checkpoint]
2. [step or checkpoint]
3. [step or checkpoint]

## What Comes Next: [Next major milestone]

[One paragraph connecting this release to the next milestone.]

[Explain what qualitative shift the next milestone brings.]

* [next user-visible step]
* [next platform or product step]
* [next trust, UI, workflow, or availability step]
