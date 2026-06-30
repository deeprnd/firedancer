<!--
Tickoni epic issue template.

Use this template for a GitHub issue labeled `epic`.

An epic is a huge new feature or product increment: a group of related stories
that deliver a complete capability across domains. In GitHub, connect `story`
issues as sub-issues of this epic. Do not put implementation task checklists
directly in the epic unless they are epic-level coordination work.

Copy this file into the GitHub issue body or use it to create/update a
doc/strategy/roadmap/stories/VX.Y.md roadmap file. Replace placeholders and
remove HTML comments before closing the issue.

Epic labels:
  Epic:  VX.Y
  Story: VX.Y.SN
  Task:  VX.Y.SN.TN

Where:
  X  = milestone number
  Y  = epic number within that milestone
  SN = story number within that epic
  TN = task number within that story

Example:
  V1.6      = milestone 1, epic 6
  V1.6.S2   = story 2 under epic V1.6
  V1.6.S2.T3 = task 3 under story V1.6.S2

GitHub label guidance for epic creation:
  - Required issue-kind label: `epic`.
  - Add all relevant boundary/domain labels covered by the child stories, such
    as `agents`, `audit`, `crypto`, `investing`, `operations`, `payments`,
    `platform`, `security`, `social`, `trust`, or `documentation`.
  - Epics may carry several boundary/domain labels because they comprise
    several stories across domains.
  - Do not add resolution or triage labels during normal epic creation, such as
    `duplicate`, `invalid`, `question`, or `wontfix`.

Epic quality standard:
  - Describes a complete user/operator outcome.
  - Defines measurable success and non-goals.
  - Breaks work into independently testable stories.
  - Identifies finance, runtime, audit, replay, model/tool/adapter, API/UI, and
    evidence boundaries only where they apply.

Read before filling:
  - doc/strategy/templates/status_template.md for epic, story, and task status
    definitions.
  - doc/strategy/README.md for product identity and what Tickoni is not.
  - doc/knowledge/architecture.md for runtime layers, tile ownership, event
    flow, and attached systems.
  - doc/strategy/capabilities.md for finance-native capability scope and
    policy outcomes.
  - doc/knowledge/tile-topology.md when the epic may affect tile ownership,
    topology, links, or Firedancer reuse.
  - doc/execution/security.md when the epic affects agent authority, tool access,
    secrets, replay divergence, or privileged action boundaries.
  - doc/execution/observability.md and doc/execution/telemetry.md when the epic
    adds or changes runtime/operator signals.
-->

# VX.Y: [Epic Title]

**Status:** [Backlog] upon creation
**Milestone:** [M1 | M2 | M3 | M4 | M5 | M6]
**Labels:** `epic`, [`agents` | `audit` | `crypto` | `documentation` | `enhancement` | `investing` | `operations` | `payments` | `platform` | `security` | `social` | `trust`]

<!-- One paragraph: what complete feature this epic delivers and why now. -->

## Product Intent

<!--
Describe the product/customer problem and the outcome this epic closes. For
Tickoni, lead with consumer-money or operator trust outcomes, then mention
runtime/control-plane consequences.
-->

## Users And Jobs

<!--
List the primary actors and jobs-to-be-done. Keep each line tied to a real
workflow, not an internal component.
-->

- [Actor]: [job/outcome]

## Success Metrics

<!--
Use observable product and engineering measures. Examples: scenario completes
offline, policy denial visible, replay matches, audit chain valid, no external
side effects, bounded latency/queue health exposed.
-->

- ...

## Demo Moment

<!--
Describe the one concrete demo that proves the epic's value. Prefer a local,
offline command or deterministic CaseOps flow.
-->

- Command or flow: `[just target or exact steps]`
- Expected result: ...

## Scope

<!--
Define epic boundaries. This prevents related but separate product work from
landing in the same issue.
-->

### In Scope

- ...

### Out Of Scope

- ...

## Conditional Boundary Checklist

<!--
Mark each boundary as Applies, N/A, or Decision needed. Add links to story
issues or docs where the detail lives. Do not invent policy, storage,
execution, tile ownership, or API semantics inside the epic without a decision.
Use doc/architecture.md and doc/contribution/tickoni.md for runtime boundaries;
use doc/security.md for no-bypass and fail-closed expectations; use
doc/observability.md and doc/telemetry.md for metrics/diagnostics expectations.
-->

| Boundary | Status | Notes / linked story |
| --- | --- | --- |
| Financial capability and policy | [Applies | N/A | Decision needed] | ... |
| Audit records and evidence | [Applies | N/A | Decision needed] | ... |
| Replay and divergence behavior | [Applies | N/A | Decision needed] | ... |
| Runtime topology, tile ownership, or links | [Applies | N/A | Decision needed] | ... |
| Model gateway governance (`tkmodl`) | [Applies | N/A | Decision needed] | ... |
| Tool broker or adapter dispatch (`tktool` / `tkadpt`) | [Applies | N/A | Decision needed] | ... |
| Approved execution (`tkexec`) | [Applies | N/A | Decision needed] | ... |
| CaseOps API/UI (`tkapi`) | [Applies | N/A | Decision needed] | ... |
| Storage role: Markdown, DuckDB, TigerBeetle | [Applies | N/A | Decision needed] | ... |
| Metrics, diagnostics, and operations | [Applies | N/A | Decision needed] | ... |
| Security and fail-closed behavior | [Applies | N/A | Decision needed] | ... |

## Story Breakdown

<!--
Create one GitHub sub-issue per story and label each `story`.
Use doc/strategy/templates/story_template.md for each child story issue.

Story split guidance:
  - Each story must be independently implementable and independently verified.
  - Split by user-visible outcome or domain boundary, not by team preference.
  - Avoid stories that require all other stories to be complete before any
    acceptance criterion can be tested.
  - Include one story or child tasks that close evidence, demo, docs, and
    quality gates for the epic.
  - Point each story to the project docs that are relevant to its implementer:
    doc/execution/build.md, doc/execution/development.md,
    doc/execution/testing-tickoni.md, doc/execution/ci.md,
    doc/execution/security.md, doc/execution/observability.md, and
    doc/execution/telemetry.md.
-->

- [ ] VX.Y.S1: [Self-contained story title] - #[github-story-issue]
- [ ] VX.Y.S2: [Self-contained story title] - #[github-story-issue]
- [ ] VX.Y.SN: [Evidence, demo, and release closure story if needed] - #[github-story-issue]

## Epic Acceptance

<!--
Define what must be true before the epic is accepted. These should roll up from
child story acceptance criteria and evidence gates.
-->

- [ ] All required story issues are done or explicitly deferred with rationale.
- [ ] The demo moment succeeds using deterministic local inputs.
- [ ] Relevant policy, audit, replay, adapter, API/UI, metrics, diagnostics,
      and documentation artifacts are linked from this epic.
- [ ] Non-goals and deferred work are visible in the roadmap.
- [ ] No live model, broker, payment, trading, crypto, TigerBeetle, or execution
      side effects occur unless this epic explicitly enables an approved
      sandbox/live execution path.

## Release / Evidence Gate

<!--
Answer only the questions that apply. Use `N/A - reason` instead of forcing
every epic through topology or tool-broker evidence.
Use doc/strategy/positioning.md to tie the answer back to Tickoni's unique
value proposition: high-throughput agentic finance, consequence isolation,
bounded spend, hard policy gates, and forensic replay.
-->

- What can the user or operator do now that they could not before this epic?
- What changed from the previous roadmap increment?
- What is this epic's wow-effect: the visible moment in this epic's demo or
  workflow that makes Tickoni feel unlike a generic agent harness?
- How does this epic progress Tickoni's unique value proposition from
  doc/strategy/positioning.md: speed, isolation/control, spend governance,
  policy-gated action, and forensic replay?
- Which demo command or CaseOps flow closes the epic?
- Which account, beneficiary, IBAN, wallet, rail, currency, market, venue,
  asset class, instrument, notional, amount, exposure, and frequency checks are
  enforced, if any?
- What happens when the requested action exceeds policy, scope, or evidence?
- Is execution paper-only, draft-only, sandbox, live, or disabled?
- Which fixtures, samples, audit records, replay capsules, screenshots, or API
  examples prove the behavior?
- Can replay run without external side effects when replay applies?
- What intentional blocked-flow or divergence example proves fail-closed behavior?

## Dependencies And Decisions

<!--
List prerequisite epics/stories and unresolved product, policy, architecture,
storage, adapter, execution, or public-contract decisions.
-->

- ...
