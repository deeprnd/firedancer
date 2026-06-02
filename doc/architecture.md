# Tickoni Architecture

## Harness Architecture

```text
Financial Event Streams
  payments / ledger / fraud / compliance / disputes
        |
        v
Tickoni Runtime
  Zig + Firedancer-style tile pipeline
  high-throughput deterministic event processing
        |
        v
Policy Engine
  capability checks
  environment rules
  approval gates
  action constraints
        |
        v
Agent Harness
  investigator
  reconciler
  payment ops assistant
  fraud reviewer
  compliance preparer
        |
        v
CaseOps Board
  event lifecycle
  evidence
  decisions
  approvals
  outcomes
        |
        v
Audit Ledger
  immutable event chain
  replay capsules
  exportable evidence
```

## Technical Architecture

### 1. Event Runtime

The runtime processes financial events through isolated tiles.

Core tiles:

```text
ingest_tile
normalize_tile
dedupe_tile
entity_resolution_tile
risk_signal_tile
policy_tile
agent_dispatch_tile
audit_tile
case_router_tile
action_tile
```

Each tile has:

- a single responsibility
- explicit input/output schema
- bounded resources
- isolated process boundary where appropriate
- deterministic behavior
- auditable event emission
- replay support

### 2. Shared-Memory Event Pipeline

Tickoni uses a high-throughput pipeline inspired by Firedancer’s tile architecture.

The goal is to support:

- high event volume
- low latency
- predictable backpressure
- deterministic replay
- crash isolation
- explicit performance measurement

Event flow:

```text
processor_webhook
  -> ingest_tile
  -> normalize_tile
  -> dedupe_tile
  -> policy_tile
  -> case_router_tile
  -> agent_dispatch_tile
  -> audit_tile
```

### 3. Agent Harness

Agents operate as controlled workers, not unrestricted actors.

Agent roles:

```text
payment_exception_agent
reconciliation_agent
fraud_triage_agent
compliance_case_agent
risk_reviewer_agent
security_reviewer_agent
```

Agents can:

- read permitted evidence
- classify events
- summarize cases
- call approved tools
- draft responses
- propose actions
- request human review

Agents cannot directly:

- move money
- mutate ledgers
- release payouts
- freeze accounts
- change compliance status
- override policy
- access secrets
- delete audit records

### 4. Tool Broker

All agent tool use goes through a tool broker.

The broker enforces:

- capability scopes
- environment boundaries
- input validation
- output validation
- rate limits
- data access controls
- audit logging
- policy checks

Tool capabilities:

```text
read_payment_event
read_processor_log
read_ledger_entry
read_case_history
draft_customer_response
propose_ledger_correction
route_case_to_queue
request_human_approval
```

Restricted capabilities:

```text
release_payout
mutate_ledger
freeze_account
approve_refund
close_compliance_case
```

Restricted capabilities require explicit policy and human approval, and may be disabled entirely in v1.

### 5. Policy Engine

Tickoni uses policy as the central control layer.

Every meaningful action is checked against:

- actor identity
- agent role
- case type
- environment
- event severity
- data classification
- allowed capabilities
- policy version
- required approvals
- action risk level

Allowed policy decision:

```yaml
requested_action: propose_ledger_correction
case_type: reconciliation_break
agent: reconciliation_agent
environment: production
decision: allow
reason: proposal_only_no_downstream_mutation
policy_version: policy_2026_06_01
```

Denied policy decision:

```yaml
requested_action: release_payout
case_type: suspicious_payout
agent: fraud_triage_agent
environment: production
decision: deny
reason: agent_cannot_release_funds
policy_version: policy_2026_06_01
```

### 6. CaseOps Board

The CaseOps Board is Tickoni’s operational control plane.

It is not a generic Kanban board.

Each card represents a financial case backed by event data, evidence, agent actions, policy decisions, approvals, and audit records.

Default v1 columns:

```text
New Event
→ Enriched
→ Agent Reviewed
→ Policy Decision
→ Human Review
→ Action Proposed
→ Resolved
→ Audited
```

Case card:

```yaml
case_id: PAY-84721
type: reconciliation_break
amount: 184230.22
currency: USD
merchant: M_38291
processor: stripe
severity: high

evidence:
  processor_batch: hash://a11
  ledger_entries: hash://b22
  bank_statement: hash://c33

agent_findings:
  likely_reason: duplicate_capture_reversed_after_batch_cutoff
  confidence: 0.82

policy:
  allowed_actions:
    - draft_correction
    - route_finance_ops
  denied_actions:
    - mutate_ledger
    - release_funds

audit:
  replay_capsule: capsule://PAY-84721
  event_chain: audit://PAY-84721
```

### 7. Audit Ledger

Tickoni’s audit layer is a first-class system, not a logging feature.

Every meaningful event is recorded into an append-only, hash-chained ledger.

Audit records include:

```text
event_id
previous_hash
timestamp_ns
source_system
actor_id
agent_id
model_id
prompt_hash
tool_call_hash
input_hash
output_hash
policy_version
case_id
capability
decision
approval_id
downstream_action
result_hash
signature
```

Large payloads are stored in content-addressed storage:

```text
prompt bodies
model responses
tool outputs
evidence bundles
case files
policy documents
approval packets
replay capsules
```

The audit system must answer:

- what happened
- why it happened
- who or what caused it
- what data was used
- which policy allowed it
- which actions were denied
- who approved it
- what changed downstream
- whether it can be replayed

### 8. Replay Capsules

Every material case gets a replay capsule.

A replay capsule contains:

```text
normalized event stream
source event hashes
case state
policy version
agent transcript
tool outputs
evidence snapshots
approval records
downstream action records
expected outcome
```

Replay command concept:

```bash
tickoni replay case PAY-84721
```

Expected output:

```text
Replay: PAY-84721

Event chain: verified
Policy version: matched
Evidence hashes: matched
Agent tool calls: matched
Decision path: matched
Downstream action: matched

Result: REPLAY MATCH
```

If replay diverges:

```text
Result: DIVERGED

First divergent event:
  audit_event_id: EVT-99182
  expected_policy_decision: deny
  actual_policy_decision: require_approval

Reason:
  policy version mismatch
```

### 9. Sandboxing

Tickoni avoids using Docker as the primary security model for the runtime.

Docker may be useful for development and deployment packaging, but Tickoni’s core security model should be lower-level and explicit.

Runtime isolation:

- small tile processes
- seccomp profiles
- dropped capabilities
- restricted filesystem access
- explicit network permissions
- shared-memory channels
- bounded resources
- crash-only process design

Agent tool isolation:

- no production secrets by default
- no direct database mutation
- no direct financial action
- read-only access unless explicitly granted
- writable temporary workspace only
- tool-level capability tokens
- full tool-call logging
- network access controlled per tool
