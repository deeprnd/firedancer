<!--
Tickoni story issue template.

Use this template for a GitHub issue labeled `story`.

A story is a single implementable deliverable that can be independently
verified. It should be small enough to complete without splitting across
multiple unrelated outcomes, but large enough to produce a user-visible or
operator-visible change. In GitHub, connect it as a sub-issue of one `epic`
issue and connect domain `task` issues as sub-issues of this story.

Copy this file into the GitHub issue body or into the relevant
doc/strategy/roadmap/stories/VX.Y.md section, replace placeholders, and remove
HTML comments before closing the issue.

Story labels:
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

Required for every story:
  - Product outcome
  - Actor/user story
  - Acceptance criteria
  - Evidence and quality gate tasks as child task issues after the story is
    Ready

GitHub label guidance for story creation:
  - Required issue-kind label: `story`.
  - Related issue-kind labels: parent issues use `epic`; child issues use
    `task`.
  - Add exactly one boundary/domain label for the story's primary ownership:
    `agents`, `audit`, `crypto`, `investing`, `operations`, `payments`,
    `platform`, `security`, `social`, `trust`, or `documentation`.
  - If a story needs several boundary/domain labels, split it into smaller
    stories under the same epic.
  - Add `enhancement` for a new product/runtime capability when useful.
  - Do not add resolution or triage labels during normal story creation, such
    as `duplicate`, `invalid`, `question`, or `wontfix`.

Conditional guidance:
  - Include topology/link acceptance only when the story changes Tickoni tile
    ownership, queues, workspaces, links, lifecycle, or Firedancer integration.
  - Include capability/policy acceptance only when the story changes financial
    authority, policy outcomes, approval rules, limits, or scope dimensions.
  - Include audit/replay acceptance only when the story changes material events,
    evidence, replay capsules, divergence checks, or append-only records.
  - Include model/tool/adapter acceptance only when the story touches tkmodl,
    tktool, tkadpt, model providers, local agent CLI routing, or financial
    adapter calls.
  - Include UI/API acceptance only when the story changes tkapi, CaseOps, HTTP,
    WebSocket, ingestion, review, approval, or external contract behavior.
  - Mark a conditional section `N/A - reason` when reviewers may otherwise
    expect it.

Read before filling:
  - doc/strategy/templates/status_template.md for status definitions and the
    rule that task sub-issues are created only after the story is Ready.
  - doc/strategy/README.md for product identity, supported workflows, and
    non-goals.
  - doc/knowledge/architecture.md for the runtime model, source-of-truth
    boundaries, tile responsibilities, and replay/audit constraints.
  - doc/execution/contribution/tickoni.md for Zig runtime style, Firedancer
    substrate reuse, C ABI boundaries, and separation rules.
  - doc/execution/build.md and doc/execution/development.md for repo-facing
    build/run commands and justfile command policy.
  - doc/execution/testing-tickoni.md and doc/execution/ci.md for test layer
    selection and CI gates.
  - doc/execution/security.md for fail-closed behavior, no-bypass expectations,
    and agent/tool capability boundaries.
  - doc/execution/observability.md and doc/execution/telemetry.md for metrics,
    diagnostics, labels, and operator-visible evidence.
-->

# VX.Y.SN: [Story Title]

**Status:** [Backlog] upon creation
**Epic:** #[github-epic-issue]
**Parent roadmap item:** [VX.Y: Epic title]
**Labels:** `story`, [exactly one of: `agents` | `audit` | `crypto` | `documentation` | `investing` | `operations` | `payments` | `platform` | `security` | `social` | `trust`], [`enhancement` if applicable]

<!-- One sentence: the independently verifiable deliverable. -->

## Product Outcome

<!--
Describe the outcome in user/operator language. Avoid implementation-only
phrasing unless this is an infrastructure story. State what becomes possible or
safer after this story is done.
-->

## User Story

<!--
Use standard product format:
As a [actor], I want [capability], so that [benefit].

Tickoni actors are usually consumer-money user, CaseOps operator, reviewer,
agent operator, developer/operator, compliance/risk reviewer, or runtime owner.
-->

As a [actor], I want [capability], so that [benefit].

## Scope

<!--
List the exact deliverable boundaries. Keep this story self-contained. Move
unrelated work into separate stories under the same epic.
-->

- In scope: ...
- Out of scope: ...

## Preconditions And Assumptions

<!--
State dependencies, fixture assumptions, known policy decisions, and existing
runtime behavior this story relies on. If the story requires a policy,
capability, storage, tile ownership, or API contract decision that is not
already documented, stop and create/raise that decision before implementation.
-->

- ...

## Acceptance Criteria

<!--
Write testable acceptance criteria in Given/When/Then or concrete observable
form. Each criterion should be independently verifiable by a task, test, demo,
fixture, or artifact.

Use the project docs to make acceptance concrete:
  - Product behavior: doc/strategy/README.md.
  - Runtime/tile behavior: doc/knowledge/architecture.md and
    doc/execution/contribution/tickoni.md.
  - Build/run behavior: doc/execution/build.md and doc/execution/development.md.
  - Tests and CI impact: doc/execution/testing-tickoni.md and
    doc/execution/ci.md.
  - Security/fail-closed behavior: doc/execution/security.md.
  - Metrics/diagnostics evidence: doc/execution/observability.md and
    doc/execution/telemetry.md.
-->

- [ ] Given [context], when [action], then [observable result].
- [ ] Given [invalid or blocked condition], when [action], then [fail-closed result].

### Conditional Acceptance

<!--
Keep only the subsections that apply. Use `N/A - reason` for boundaries that
are commonly relevant to this story's domain but intentionally untouched.
-->

**Financial capability and policy**

<!-- Applies when changing tkpoly behavior, capability envelopes, limits,
approval state, denied-by-default behavior, or financial scope. -->

- [ ] [N/A - reason, or policy acceptance criterion]

**Audit and replay**

<!-- Applies when adding/changing material events, evidence, audit JSONL,
hash-chain behavior, replay capsules, divergence checks, or replay substitution. -->

- [ ] [N/A - reason, or audit/replay acceptance criterion]

**Runtime topology and tile ownership**

<!-- Applies when changing tile IDs, tile ownership, links, workspaces, queue
depths, reliability, overrun behavior, restart behavior, shutdown behavior, or
Firedancer infrastructure integration. -->

- [ ] [N/A - reason, or topology acceptance criterion]

**Model, tool, adapter, or execution boundary**

<!-- Applies when changing tkmodl, tktool, tkadpt, tkexec, agent daemon behavior,
provider config, adapter manifests, broker/payment/trading/crypto/risk/compliance
API access, or replay substitution for external calls. -->

- [ ] [N/A - reason, or boundary acceptance criterion]

**CaseOps API or UI**

<!-- Applies when changing tkapi, HTTP/WebSocket behavior, CaseOps screens,
operator review, approval flows, external ingestion, or partner review APIs. -->

- [ ] [N/A - reason, or API/UI acceptance criterion]

## Child Task Issues

<!--
Create one GitHub sub-issue per task and label each `task` only after this
story's Status is `Ready`.

Before `Ready`, use this section to describe the likely task split in prose
or leave placeholders. Do not create GitHub task sub-issues while the story is
still being shaped; otherwise task work can start before the story boundary,
acceptance criteria, and evidence gates are stable.

Task split guidance:
  - Split by domain/ownership, not by arbitrary activity.
  - Prefer tasks such as runtime, policy, audit/replay, API/UI, fixtures,
    tests, docs, and evidence gate.
  - Once Ready, every story must include evidence and quality gate tasks,
    even when the implementation is documentation-only.
  - Evidence tasks should cover the applicable subset of demo command,
    product checklist, fixtures, sample configs, audit JSONL, approval/rejection
    samples, metrics, diagnostics, replay samples, blocked-flow fixtures, and
    artifact links.
  - Quality tasks should cover the applicable subset of focused tests,
    fail-closed validation, forbidden direct access, malformed envelope/hook
    handling, provider config validation, adapter manifest validation, API
    integration tests, and roadmap/docs reconciliation.
  - Implementation tasks should name the docs the implementer must follow. Use
    doc/contribution/tickoni.md for Tickoni Zig/runtime style, doc/build.md and
    doc/development.md for command surfaces, doc/testing-tickoni.md and
    doc/ci.md for verification, doc/security.md for security-sensitive work,
    and doc/observability.md or doc/telemetry.md for operator signals.
  - Keep tasks implementable by one owner without requiring unrelated changes.
  - Each task should point back to the acceptance criteria it helps close.
-->

- [ ] VX.Y.SN.T1: [Domain task title] - #[github-task-issue]
- [ ] VX.Y.SN.T2: [Evidence gate task] - #[github-task-issue]
- [ ] VX.Y.SN.T3: [Quality gate task] - #[github-task-issue]

## Evidence Plan

<!--
State how this story will prove completion. Evidence is not limited to tasks;
it may include tests, demo output, fixtures, audit samples, replay samples,
screenshots, API examples, generated artifacts, or docs.
-->

- Demo or command: `[just target or exact command]`
- Tests: `[focused test targets]`
- Fixtures or samples: `[paths or planned artifacts]`
- Audit/replay evidence: `[N/A - reason, or planned artifacts]`
- Blocked-flow evidence: `[N/A - reason, or planned fixture/test]`

## Quality Gate

<!--
Use the narrowest meaningful checks. Add broader gates when the story touches
shared runtime behavior, security boundaries, or public contracts.

Use doc/testing-tickoni.md for test selection. Use doc/ci.md to understand
which GitHub Actions lanes are expected to cover the changed paths. Use
doc/development.md for the rule that repo-facing commands belong in the
justfile, not upstream Firedancer Makefiles.
-->

- [ ] Focused tests for changed behavior pass.
- [ ] `just test-unit-tk` passes when Tickoni runtime code changes.
- [ ] `just test-integration-tk` passes when cross-tile, API, replay, adapter,
      or fixture behavior changes.
- [ ] `just demo-tk` or the story-specific demo command prints the required
      scenario when this story changes a demoable product flow.
- [ ] Documentation and roadmap status are updated when user-visible scope,
      non-goals, or evidence gates change.

## Notes And Open Questions

<!--
List unresolved decisions. Do not hide ambiguity in implementation tasks. Raise
architecture, policy, storage, execution authority, or API contract questions
before implementation starts.
-->

- ...
