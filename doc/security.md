# Tickoni Security

## Guiding Principle

Tickoni retains a Firedancer-derived runtime foundation.

Agent harness code should live above that foundation instead of being mixed into low-level networking, shared-memory channel, tile runtime, or kernel-interface code.

Changes to the runtime foundation require explicit review. They are not routine agent-harness implementation work.

The rule: **keep agent harness code above the engine boundary unless a reviewed runtime change is necessary.**

## Isolation Model

Tickoni adopts Firedancer's process-oriented isolation principles.

The agent pipeline follows the same general shape:

```text
tickoni run
  ├─ ingest:0
  ├─ normalize:0
  ├─ policy:0
  ├─ agent-dispatch:0
  ├─ audit:0
  └─ case-router:0
```

Each process has:

- one responsibility
- owned state
- bounded resources
- explicit capabilities
- no shared mutable state outside designated channels
- if any tile dies, all tiles come down

Agent tiles follow these requirements:

- one agent tile = one process
- capabilities are declared, not assumed
- agent tiles communicate through channels, not direct calls
- the harness enforces resource and permission boundaries before execution reaches the model
- denied actions are recorded, not silently dropped

## Security Model

Tickoni assumes agents are not inherently trustworthy.

Security posture:

- agents are untrusted by default
- tools are capability-scoped
- production actions require policy checks
- money-impacting actions require approval
- secrets are never exposed directly to agents
- audit records are immutable
- deleted history is not allowed
- policy decisions are logged
- denied actions are logged
- replay divergence is treated as a serious event

## Agent Identity and Capability Boundaries

Every tool request must resolve to an agent identity, case scope, policy
version, and explicit capability. Model-native function calls and
MCP-compatible requests are untrusted input until the broker validates that
envelope.

High-impact actions are proposals routed to a separate privileged executor.
Policy can constrain action type, resource scope, value, rate, environment,
and required approval before any downstream change is executed.

## Agent Capability Manifest

```yaml
agent: payment_exception_agent
environment: production

allowed:
  - read_payment_event
  - read_processor_log
  - read_case_history
  - draft_merchant_response
  - propose_retry_path
  - route_case

requires_approval:
  - send_merchant_response
  - retry_payment
  - change_payment_route

denied:
  - release_payout
  - post_ledger_adjustment
  - freeze_account
  - approve_refund
  - delete_audit_record
```
