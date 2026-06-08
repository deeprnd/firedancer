# Tickoni V1 Product Requirements

## Summary

Tickoni V1 is a controlled AI harness for fintech event operations. It should
demonstrate that agents can help investigate payment, reconciliation, fraud,
risk, and trading-control events while the runtime enforces finance-native
capability envelopes, records a forensic audit trail, attributes model spend,
and supports replay.

V1 is not a broad automation platform. It is a narrow trust demonstration for
financial systems where unrestricted agent autonomy is unacceptable.

## Target Users

| User | Need |
| --- | --- |
| FinOps operator | Review exceptions, evidence, recommendations, and approval-required actions |
| Risk/compliance reviewer | Verify why an agent recommended an action and whether policy was enforced |
| Engineering operator | Monitor queues, crashes, budgets, replay divergence, and adapter behavior |
| Buyer or evaluator | See credible controls around AI use in financial operations |

## Primary Jobs To Be Done

1. When a financial event arrives, normalize and deduplicate it deterministically.
2. When policy applies, evaluate the financial capability envelope and record allow, deny, or require-approval with reason.
3. When an agent investigates, route all model access and financial adapter access through governed tiles.
4. When a model-native function call, MCP request, or financial adapter call is requested, validate payment, ledger, trading, risk, destination, amount, frequency, and approval scope first and audit the result.
5. When a sensitive action is proposed, require explicit approval and avoid automatic execution.
6. When an auditor reviews a case, provide audit records, evidence, model usage, and replay status.

## V1 Product Requirements

### Runtime Control

- The runtime must process events through deterministic stages.
- The runtime must expose backpressure, queue depth, and crash diagnostics.
- The runtime must fail closed when policy, model, financial adapter, destination allowlist, or limit configuration is invalid.
- The runtime must support replay with external effects disabled.

### Audit And Evidence

- Every source event, policy decision, model call, financial adapter call,
  proposal, destination check, limit check, adapter result, denial,
  approval-required decision, and operator approval must be audited.
- Audit records must be append-only and hash-chained.
- Evidence must be content-addressed before it is attached to a case.
- Replay must report divergence instead of mutating external systems.

### Financial Capability Model

- Every model, financial adapter, and proposed action request must carry a
  finance-native capability envelope.
- Capability envelopes must use financial domains such as payment, ledger,
  trading, fraud/risk, banking destination, crypto destination, and approval
  path instead of OS-style permissions.
- Sensitive capability scopes must support destination allowlists, including
  beneficiary, IBAN, wallet, broker account, market, exchange, sector, and
  instrument constraints where applicable.
- Sensitive capability scopes must support amount, exposure, frequency,
  holding-period, and per-day or per-month limits.
- Policies must return allow, deny, or require-approval.
- Money-impacting and trading-impacting mutations must require approval.
- Trading-control stubs must prove proposal-only scope, including denial for
  direct order placement and denial for proposals outside configured market,
  sector, amount, or frequency limits.
- Agents must not receive raw shell access or direct unrestricted network
  access.

### Inference Governance

- Agents must use `tkmodl` for model access.
- Model calls must be attributed by role, workflow, case or synthetic run, and
  policy version.
- Token, retry, context, and loop limits must be enforceable before and during
  execution.
- Local/dev LLM endpoints may be used for demos only through the same governed
  path as cloud providers.

### Workflows

V1 should demonstrate three workflow families:

- payment exception investigation
- reconciliation break investigation
- fraud/risk triage

Trading-control stubs may be used in Phase 1 to prove financial capability
boundaries, including market, venue, sector, notional, frequency, and
proposal-only controls, but V1 must not perform autonomous trading or order
execution.

## Success Metrics

| Metric | V1 target |
| --- | --- |
| Audit completeness | Every material boundary event has an audit record |
| Replay quality | Replay reports match or precise divergence reason |
| Financial capability enforcement | Forbidden and approval-required payment, ledger, trading, risk, destination, limit, and frequency actions are blocked before execution |
| Inference attribution | Model usage is attributed to workflow, role, and budget |
| Operator usability | A demo case can be reviewed end to end without reading raw logs |
| Demo credibility | Payment, reconciliation, and fraud/risk demos are policy-gated and replayable |

## Non-Goals

V1 does not include:

- autonomous money movement
- autonomous accounting ledger posting
- autonomous trading or order execution
- autonomous account freezing
- autonomous payout approval
- autonomous compliance decisions
- open plugin marketplace
- generic browser automation
- arbitrary custom workflows
- full enterprise RBAC
- unbounded multi-agent swarms

## Release Readiness

V1 is ready to present when:

1. Phase 1 proves the governed control-plane harness with stubs.
2. Phase 2 proves deterministic case and evidence replay.
3. Phase 3 exposes a usable CaseOps review experience.
4. Phase 4 demonstrates the workflow pack with replayable sample data.
5. The financial capability model in [`capabilities.md`](capabilities.md) is
   visibly represented in demos, policy decisions, audit records, and denied
   actions.
6. The non-goals above remain visibly enforced in product behavior.
