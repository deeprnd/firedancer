# Tickoni Position Documents

## Purpose

This directory separates product management decisions from architecture and tile
implementation details. Each document has one job, and the roadmap should stay
readable instead of becoming a backlog.

The current product direction is consumer finance:

```text
invest -> pay -> move -> hold -> prove
```

Tickoni should feel like a consumer-money product with a finance-native AI
control layer underneath. The user experience leads with investment, payment,
transfer, crypto/stablecoin, cash, and portfolio decisions. The platform
advantage remains deterministic processing, capability-scoped permissions,
audit, replay, bounded inference, signed adapters, and approval-gated
execution.

## Source Of Truth

| Document | Owns | Does not own |
| --- | --- | --- |
| [`positioning.md`](positioning.md) | Market position, differentiation, buyer framing, non-positioning | Delivery sequencing or implementation tasks |
| [`roadmap.md`](roadmap.md) | Consumer-finance version sequence, product narrative, prioritization, strategic tradeoffs | Detailed engineering task ownership |
| [`wbs.md`](wbs.md) | Stories, tasks, acceptance criteria, increment evidence, backlog work | Market narrative or tile topology |
| [`capabilities.md`](capabilities.md) | Finance-native permission model, action classes, policy outcomes, scopes, destination allowlists, and capability roadmap | OS sandbox permissions or implementation-specific tile APIs |
| [`tile-plan.md`](tile-plan.md) | Tile IDs, tile ownership, topology, validator-tile replacement decisions | Product backlog, roadmap sequencing, WBS tasks |

## Product Operating Model

### Planning Cadence

- Roadmap review: update when product priority, version order, or strategic
  scope changes.
- WBS grooming: update when stories split, merge, or change acceptance
  criteria.
- Capability review: update when a financial action class, policy outcome,
  destination allowlist, scope dimension, approval path, or default-deny rule
  changes.
- Tile-plan review: update when a product requirement changes tile ownership,
  link shape, runtime boundary, or Firedancer infrastructure use.

### Decision Rules

1. If the question is "why are we building this?", update `positioning.md`.
2. If the question is "when does this happen?", update `roadmap.md`.
3. If the question is "what exact work remains?", update `wbs.md`.
4. If the question is "which tile owns this?", update `tile-plan.md`.
5. If the question is "which financial action is allowed?", update
   `capabilities.md`.
6. If the question is "which model path is allowed?", update `roadmap.md` and
   `wbs.md` under model/tool governance unless a dedicated governance document
   is restored.

### Senior Product Constraints

- Lead with consumer-money outcomes, not governance-console language.
- Keep the first increments focused on safe decisions: investment intent to
  paper trade, payment/transfer guardrails, cash/portfolio impact, crypto guard,
  sandbox execution, trust, and capability control.
- Make constraints feel useful: buying power, trusted recipients, wallet
  allowlists, amount limits, venue scope, concentration, frequency, holding
  period, approval state, and blocked reasons.
- Prove audit, permissions, telemetry, replay, and no-bypass behavior before
  real financial APIs.
- Prefer deterministic stubs until the product flow and control surface are
  measurable.
- Treat model integration as governed infrastructure, not a feature shortcut.
- Keep autonomous money movement, autonomous ledger posting, autonomous account
  freezing, autonomous payout approval, autonomous compliance decisions, and
  autonomous trading outside V1.

## Current V1 Narrative

V1 proves that Tickoni can turn consumer-money intent into safe, explainable,
replayable financial proposals:

1. Investment intent becomes an explainable basket, trade ticket, affordability
   check, and paper trade.
2. Payment, payout, retry, or transfer intent becomes an allowed, blocked,
   evidence-required, escalated, or approval-required proposal.
3. Portfolio, cash, pending obligation, approval, and drift impact are visible
   before and after action.
4. Crypto and stablecoin proposals are checked against wallet, network, asset,
   custody, chain-risk, travel-rule, and amount scope.
5. Sandbox broker, payment, bank, and crypto actions run only through signed
   adapters, signed envelopes, deterministic action ids, approvals, read-back,
   and kill switch.
6. Trust and capability-control surfaces expose audit timeline, replay capsule,
   policy version/hash, model/tool/adapter attribution, full action classes,
   policy outcomes, scope dimensions, evidence prerequisites, aggregate limits,
   and denied-by-default execution paths.

The active roadmap sequence is:

1. `V1.1` Investment Intent To Paper Trade
2. `V1.2` Pay And Move Money Guard
3. `V1.3` Portfolio And Cash Impact Loop
4. `V1.4` Social Thesis And Money Feed
5. `V1.5` Crypto And Stablecoin Guard
6. `V1.6` Guarded Broker, Payment, And Crypto Sandbox
7. `V1.7` Trust Layer
8. `V1.8` Capability Control Surface

V1 is intentionally not "real API first." It proves the consumer-money product
flow with deterministic fixtures and governed boundaries before broad live
connectors.
