# Tickoni Consumer Finance Milestones

## Purpose

This document groups the consumer-finance roadmap into three higher-level
milestones. It does not replace or revise [`roadmap.md`](roadmap.md). The
roadmap remains the source of truth for version order, product narrative,
priority tradeoffs, and increment detail.

Use this document when the question is:

```text
Which larger product milestones do the roadmap epics roll up into?
```

An "epic" here means a named roadmap increment such as `V1.1` or a
carried-forward platform backlog item such as `P1`.

## Milestone Summary

| Milestone | Included roadmap epics | Product result |
| --- | --- | --- |
| M1: Safe Money Decisions | `V1.1`, `V1.2`, `V1.3`, supported by `P2`, `P3`, `P4`, `P8` | Consumer intent becomes safe investing, payment, cash, and portfolio decisions |
| M2: Governed Expansion And Sandbox Action | `V1.4`, `V1.5`, `V1.6`, supported by `P5`, `P6`, `P8` | The product expands to social templates, crypto/stablecoin guardrails, and approved sandbox execution |
| M3: Partner Trust And Control Plane | `V1.7`, `V1.8`, supported by `P1`, `P2`, `P4`, `P5`, `P6`, `P7`, `P8` | Partners can inspect proof, replay decisions, and understand the finance-native control model |

## M1: Safe Money Decisions

### Description

M1 proves the first consumer-money loop:

```text
invest -> pay -> move -> see impact
```

The user can turn an investment thesis into a basket, trade ticket,
affordability result, and paper trade. The same product can inspect a failed
payment, payout, retry, or transfer and produce an allowed, blocked,
evidence-required, escalated, or approval-required proposal. The user can then
see how those proposals affect cash, buying power, portfolio exposure, pending
obligations, approval state, and drift.

### Included Epics

Product increments:

- `V1.1`: Investment Intent To Paper Trade
- `V1.2`: Pay And Move Money Guard
- `V1.3`: Portfolio And Cash Impact Loop

Supporting platform epics:

- `P2`: Model And Tool Governance
- `P3`: Runtime Hooks
- `P4`: Case, Evidence, And Replay Capsule
- `P8`: Build, Quality, Security, And Release Hygiene

### Why This Is A Milestone

This is more than a set of screens or schemas. It establishes the core product
promise: a user can express financial intent and Tickoni can turn it into a
bounded, explainable, replayable money decision before financial consequence.

It deserves milestone status because it joins three domains that are usually
separate in consumer finance:

- investing intent and paper trade construction
- payment, payout, retry, and transfer guardrails
- cash, portfolio, obligation, approval, and drift impact

When M1 is complete, Tickoni is no longer only a runtime proof. It is a
consumer-money product that demonstrates safe action without live execution.

### Completion Signal

M1 is complete when a user can run the roadmap demos for `V1.1`, `V1.2`, and
`V1.3` from deterministic fixtures and get replayable evidence for allowed,
blocked, resized, approval-required, evidence-required, and escalated flows.

## M2: Governed Expansion And Sandbox Action

### Description

M2 expands the safe-decision product beyond the first private money loop:

```text
copy -> crypto/stablecoin guard -> approved sandbox action
```

The user can browse shareable thesis or money-decision cards and copy them into
their own account, recipient, wallet, and policy limits. Crypto and stablecoin
flows add wallet, network, custody account, asset, chain-risk, travel-rule, and
amount checks. Approved sandbox connectors then prove that small broker,
payment, bank, or crypto actions can pass through signed adapters, signed
action envelopes, deterministic action ids, read-back, reconciliation, and kill
switch controls.

### Included Epics

Product increments:

- `V1.4`: Social Thesis And Money Feed
- `V1.5`: Crypto And Stablecoin Guard
- `V1.6`: Guarded Broker, Payment, And Crypto Sandbox

Supporting platform epics:

- `P5`: External Ingestion And Partner API
- `P6`: Approval And Execution Trust
- `P8`: Build, Quality, Security, And Release Hygiene

### Why This Is A Milestone

This milestone changes the product from a single-user safe-decision demo into a
governed product surface that can support copied intent, additional asset
classes, and approved sandbox effects.

It deserves milestone status because it introduces three substantial new
control dimensions:

- account-specific resizing for copied thesis and money templates
- crypto and stablecoin destination safety, not just brokerage and payment
  checks
- sandbox execution through signed adapters and read-back, without granting
  agents autonomous authority

When M2 is complete, Tickoni can show that the same finance-native safety model
works across investment, payment, bank-transfer, crypto, and sandbox connector
lanes.

### Completion Signal

M2 is complete when copied thesis or money-template flows cannot bypass the
user's own limits, crypto/stablecoin proposals are policy-checked and
replayable, and approved sandbox actions are submitted only through signed,
audited, read-back-verified adapter paths.

## M3: Partner Trust And Control Plane

### Description

M3 turns the consumer-money product into something a regulated partner can
inspect and trust:

```text
prove -> replay -> govern
```

Partners can inspect the audit timeline, replay capsule, policy version and
hash, model/tool/adapter attribution, approval state, signed records, and
money-decision export for investing, payment, transfer, crypto, and sandbox
flows. They can also inspect the finance-native capability catalog by action
class, policy outcome, scope dimension, evidence prerequisite, aggregate
limit, approval path, and denied-by-default execution or override path.

### Included Epics

Product increments:

- `V1.7`: Trust Layer
- `V1.8`: Capability Control Surface

Supporting platform epics:

- `P1`: Durable Runtime Proof
- `P2`: Model And Tool Governance
- `P4`: Case, Evidence, And Replay Capsule
- `P5`: External Ingestion And Partner API
- `P6`: Approval And Execution Trust
- `P7`: Non-Investment Workflow Shelf
- `P8`: Build, Quality, Security, And Release Hygiene

### Why This Is A Milestone

This milestone is the credibility boundary for fintech, brokerage, payments,
crypto, treasury, risk, and compliance partners. It makes the proof behind
money decisions inspectable without requiring reviewers to read raw tile logs
or audit JSONL by hand.

It deserves milestone status because it consolidates the platform advantage
that makes Tickoni more than a consumer UI:

- durable audit and replay for material money decisions
- clear attribution for models, tools, adapters, actors, and policy versions
- explicit capability control across action classes, outcomes, scopes, limits,
  evidence, approval paths, and denied execution classes
- a shelf for later operations-heavy workflows without distracting from the
  consumer-money V1 path

When M3 is complete, Tickoni can support partner review and product governance
as first-class surfaces while keeping agents proposal-first and execution
approval-gated.

### Completion Signal

M3 is complete when a partner can inspect an exported money-decision record,
replay the decision without external effects, understand why it was allowed,
blocked, resized, approval-required, evidence-required, or escalated, and see
which financial capabilities and controls governed the result.

