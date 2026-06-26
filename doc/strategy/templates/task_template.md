<!--
Tickoni task issue template.

Use this template for a GitHub issue labeled `task`.

A task is a sub-issue of one `story`. It is the smallest tracked work item that
implements part of the story. Tasks should be split by domain ownership so the
story can be implemented cleanly: runtime, policy, audit/replay, API/UI,
fixtures, tests, docs, evidence, release gate, and similar boundaries.

Copy this file into the GitHub issue body. Replace placeholders and remove HTML
comments before closing the issue.

Task labels:
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

Task quality standard:
  - Implements one domain slice of one story.
  - Links to the story acceptance criteria it closes.
  - Has explicit verification.
  - Does not introduce unrelated scope or hidden policy decisions.

Read before implementing:
  - doc/position/templates/status_template.md for task lifecycle status.
  - doc/architecture.md for runtime/source-of-truth boundaries.
  - doc/contribution/tickoni.md for Tickoni Zig runtime style, Firedancer reuse,
    C ABI rules, and separation constraints.
  - doc/build.md and doc/development.md for build/run commands and justfile
    command policy.
  - doc/testing-tickoni.md and doc/ci.md for local and CI verification choices.
  - doc/security.md for fail-closed validation, no-bypass behavior, and
    capability boundaries.
  - doc/observability.md and doc/telemetry.md when changing metrics,
    diagnostics, labels, alerts, or operator-visible runtime state.
-->

# VX.Y.SN.TN: [Task Title]

**Status:** [Backlog] upon creation
**Parent story:** #[github-story-issue]
**Parent epic:** #[github-epic-issue]
**Labels:** `task`, [`runtime` | `policy` | `audit` | `replay` | `api` | `ui` | `fixtures` | `tests` | `docs` | `evidence` | `quality`]

<!-- One sentence: the domain slice this task completes. -->

## Task Type

<!--
Pick the closest type. Use one primary type unless the work is deliberately a
combined evidence/quality task.
-->

- [ ] Runtime / tile / topology
- [ ] Capability / policy
- [ ] Audit / evidence
- [ ] Replay / divergence
- [ ] Model gateway (`tkmodl`)
- [ ] Tool broker / adapter (`tktool` / `tkadpt`)
- [ ] Approved execution (`tkexec`)
- [ ] CaseOps API / UI (`tkapi`)
- [ ] Fixtures / sample data
- [ ] Tests / quality gate
- [ ] Documentation / roadmap
- [ ] Other: ...

## Story Acceptance Covered

<!--
Paste or reference the exact parent story acceptance criteria this task helps
close. If it does not close an acceptance criterion, it probably belongs in a
different issue or should be folded into another task.
-->

- [ ] [Story acceptance criterion link or text]

## Implementation Notes

<!--
State the intended files, modules, fixtures, or docs. Keep this narrow. If the
task would change tile ownership, capability semantics, audit schema, replay
capsule shape, storage role, public API contract, or execution authority, mark
it blocked until the parent story or epic records the decision.

Implementation reference by domain:
  - Runtime/tile/topology: doc/architecture.md, doc/contribution/tickoni.md,
    doc/knowledge/tile-topology.md.
  - Build/run/tooling: doc/build.md and doc/development.md. Keep repo-facing
    commands in the justfile.
  - Tests/fixtures: doc/testing-tickoni.md. Use the narrowest relevant check
    first, then broaden for shared boundaries.
  - CI impact: doc/ci.md. Keep workflow commands aligned with justfile recipes.
  - Security/config/capability: doc/security.md. Missing or malformed runtime
    config must fail closed.
  - Metrics/diagnostics: doc/observability.md and doc/telemetry.md. Keep metric
    labels low-cardinality.
-->

- Expected touch points: ...
- Important constraints: ...

## Conditional Requirements

<!--
Keep only the requirements that apply to this task. Use `N/A - reason` for
review-sensitive boundaries that are intentionally untouched.
-->

**Validation and fail-closed behavior**

- [ ] [N/A - reason, or validation requirement]

**Security / no-bypass behavior**

- [ ] [N/A - reason, or forbidden direct access / shell / network / execution test]

**Audit / replay artifacts**

- [ ] [N/A - reason, or artifact requirement]

**Config / manifest handling**

- [ ] [N/A - reason, or required env/config/manifest validation]

**Docs / roadmap reconciliation**

- [ ] [N/A - reason, or docs requirement]

## Verification

<!--
List the exact checks needed before this task is done. Prefer focused tests.
Add broader gates only when the changed surface warrants it.
-->

- [ ] `[focused command or test target]`
- [ ] `just test-unit-tk` if Tickoni runtime code changes.
- [ ] `just test-integration-tk` if cross-tile, API, replay, adapter, or
      fixture behavior changes.
- [ ] `[demo command]` if this task changes user/operator-visible flow.

## Evidence To Attach

<!--
Attach or link concise proof in the GitHub issue: test output, demo output,
fixture path, audit sample path, replay sample path, screenshot, API example,
or docs diff. For long logs, link artifacts instead of pasting everything.
-->

- ...

## Done Criteria

<!--
The task is done only when implementation, verification, and evidence are
complete. If work is discovered outside this task's domain, create/link a new
task instead of expanding this one silently.
-->

- [ ] The scoped domain change is implemented.
- [ ] Parent story acceptance criteria listed above are satisfied or updated.
- [ ] Verification commands pass or known failures are documented with owner.
- [ ] Evidence is attached or linked.
- [ ] No unrelated files, policy semantics, tile ownership, public contracts, or
      financial authority changed as part of this task.
