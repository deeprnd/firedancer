---
adr: "{NN}"
title: "{short-title}"
status: "{proposed | accepted | rejected | deprecated | superseded}"
date: "{YYYY-MM-DD}"
authors:
  - "{name/team}"
tags:
  - "{system-area}"
  - "{quality-attribute}"
supersedes: []
superseded_by: []
related: []
---

# ADR-{NN}: {Short title naming the problem and chosen direction}

> Use one ADR for one architectural or technically significant decision. Prefer a precise, concrete record over a broad design essay. Remove instructional text before committing the final ADR.

## Decision Summary

In the context of {system, subsystem, project, or use case}, facing {main concern, constraint, or force}, we decided to {chosen option} and not {main alternatives}, to achieve {desired qualities or outcomes}, accepting {known downside or tradeoff}, because {decisive rationale}.

## Context and Problem Statement

{Describe the situation that forced a decision. Include the current design, missing capability, operational constraint, portability issue, performance requirement, security concern, upstream dependency, or organizational constraint.}

**Decision question:** {Write the decision as a question. Example: "How should callers from another language invoke a function that has no linkable symbol?"}

This decision matters now because {what changed, what work is blocked, what risk is accumulating, or what repeated local choice needs to become a shared default}.

## Scope

### In scope

- {System/component/API/build/runtime behavior covered by this ADR}
- {Decision boundary this ADR controls}

### Out of scope

- {Related topic deliberately excluded}
- {Separate decision that needs its own ADR}

## Decision Drivers

List the criteria that should determine the choice. Prefer concrete forces over generic preferences.

- {Driver 1: e.g., preserve upstream behavior exactly}
- {Driver 2: e.g., avoid permanent forks or recurring sync burden}
- {Driver 3: e.g., keep call sites stable across supported platforms}
- {Driver 4: e.g., minimize ABI/API surface area}
- {Driver 5: e.g., maintain performance on the hot path}

Quality attributes affected:

- Correctness: {impact}
- Maintainability: {impact}
- Portability: {impact}
- Performance: {impact}
- Operability/testability: {impact}
- Security/compliance: {impact, if applicable}

## Constraints and Assumptions

- {Hard constraint: ownership, upstream policy, platform support, compiler/toolchain behavior, budget, timeline, regulatory rule, etc.}
- {Assumption that must be true for this decision to remain valid}
- {Unknown that should be verified before or during implementation}

## Considered Options

List every option that was seriously considered. Name each option in a way that reveals the mechanism, not just the preference.

1. **{Option 1 title}.** {One-sentence description.}
2. **{Option 2 title}.** {One-sentence description.}
3. **{Option 3 title}.** {One-sentence description.}

## Option Analysis

### Option 1: {Option title}

{Describe the option. Include how it would be implemented and who would own it.}

Good, because:

- {Benefit}
- {Benefit}

Bad, because:

- {Cost, risk, or tradeoff}
- {Cost, risk, or tradeoff}

Neutral or conditional:

- {Fact that matters but is neither clearly positive nor negative}

Validation needed:

- {Test, spike, benchmark, compile check, design review, migration dry run, etc.}

### Option 2: {Option title}

{Describe the option. Include how it would be implemented and who would own it.}

Good, because:

- {Benefit}
- {Benefit}

Bad, because:

- {Cost, risk, or tradeoff}
- {Cost, risk, or tradeoff}

Neutral or conditional:

- {Fact that matters but is neither clearly positive nor negative}

Validation needed:

- {Test, spike, benchmark, compile check, design review, migration dry run, etc.}

### Option 3: {Option title}

{Describe the option. Include how it would be implemented and who would own it.}

Good, because:

- {Benefit}
- {Benefit}

Bad, because:

- {Cost, risk, or tradeoff}
- {Cost, risk, or tradeoff}

Neutral or conditional:

- {Fact that matters but is neither clearly positive nor negative}

Validation needed:

- {Test, spike, benchmark, compile check, design review, migration dry run, etc.}

## Comparison

Use this table when the tradeoff is not obvious from prose. Add or remove criteria as needed.

| Criterion | Weight | Option 1 | Option 2 | Option 3 |
| --- | ---: | --- | --- | --- |
| {Criterion 1} | {High/Med/Low} | {score or note} | {score or note} | {score or note} |
| {Criterion 2} | {High/Med/Low} | {score or note} | {score or note} | {score or note} |
| {Criterion 3} | {High/Med/Low} | {score or note} | {score or note} | {score or note} |

## Decision

**We will {chosen option}.**

This is the standing/default choice when {conditions under which this ADR applies}. It is not merely preferred as a tie-breaker; it should be used unless one of the deviation criteria below applies.

The decisive factor is {the strongest reason this option wins, expressed as a tradeoff, not a slogan}.

Rejected alternatives:

- {Rejected option}: rejected because {specific reason}.
- {Rejected option}: rejected because {specific reason}.

## Consequences

### Positive consequences

- {Expected improvement or preserved property}
- {Expected improvement or preserved property}

### Negative consequences

- {Accepted cost, maintenance burden, compatibility issue, performance tradeoff, or organizational cost}
- {Accepted cost, maintenance burden, compatibility issue, performance tradeoff, or organizational cost}

### Neutral consequences

- {Observable change that is neither primarily good nor bad}

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- |
| {Risk} | {Low/Med/High} | {Low/Med/High} | {Mitigation} | {Owner} |

## Implementation Plan

- {Implementation step 1}
- {Implementation step 2}
- {Implementation step 3}

Migration/backward compatibility:

- {How existing users, data, APIs, build artifacts, or deployments are affected}

Operational impact:

- {Monitoring, alerting, runbook, deployment, rollback, security review, or support implications}

## Confirmation

Describe how compliance with the ADR will be checked after implementation.

- Tests: {unit/integration/property/compatibility/performance tests}
- Review gates: {design review, code owners, architecture review, security review}
- Build/CI checks: {lint, compiler checks, generated symbol checks, ABI checks, dependency checks}
- Observability: {metrics, logs, dashboards, SLOs, manual checks}

## Deviation Criteria

A future implementation may deviate from this decision only when at least one of these conditions applies:

- {Condition 1 under which the default is wrong}
- {Condition 2 under which a different option is required}
- {Condition 3 requiring a separate ADR}

Each deviation must record:

- why the default does not apply;
- which alternative is being used;
- who approved the deviation;
- how correctness and compatibility are verified;
- whether the deviation is temporary or permanent.

## Related Decisions and References

- {ADR-0000: related decision}
- {Issue/PR/design doc/link}
- {External standard, upstream documentation, benchmark, or experiment}

## Authoring Checklist

Before accepting the ADR, verify that:

- the decision question is explicit;
- all seriously considered options are named;
- the chosen option is stated as an actionable rule;
- rejected options are rejected for specific reasons;
- consequences include real costs, not just benefits;
- deviations are explicit when the default is not universal;
- validation/confirmation is concrete enough to test;
- links to superseded or related ADRs are included;
- instructional placeholder text has been removed.
