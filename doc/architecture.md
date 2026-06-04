# Tickoni Architecture

Tickoni is a high-throughput AI harness for agentic finance. The architecture
starts from financial event integrity, then adds controlled agents after the
runtime can prove bounded processing, audit, replay, and isolation.

The implementation rule is:

```text
runtime first
cases second
agents third
privileged actions last
```

AI is not part of the deterministic event critical path. A financial event must
be ingestible, normalized, audited, and replayable before any agent investigates
the resulting case.

## Product Shape

```text
Financial event streams
  payments / accounting ledger / fraud / compliance / disputes
        |
        v
Tickoni event runtime
  Zig + Firedancer-style tile pipeline
  bounded queues, deterministic processing, explicit ownership
        |
        v
Policy and audit boundary
  capability checks, denials, append-only records, replay capsules
        |
        v
Controlled agent harness
  role agents, model gateway, tool broker, signed adapters
        |
        v
CaseOps board
  case lifecycle, evidence, approvals, audit timeline
        |
        v
Privileged action executor
  disabled by default, approved mutations only
```

## Phase 0 Runtime Spike

Current implementation status: the Zig supervisor runs the Phase 0 financial
event spike in dev/test mode:

```text
synthetic payment stream
  -> tkings
  -> tknorm
  -> tkdedu
  -> tkpoly
  -> tkaudt

tkrepl -> deterministic re-injection path
tkmetr -> runtime metrics
tkdiag -> process and queue diagnostics
```

The spike proves:

- bounded channel depths
- stable event hashes
- append-only audit records
- deterministic replay comparison
- visible backpressure and queue health
- audited malformed-event rejection
- crash-only supervisor behavior
- no Solana validator tiles in the Tickoni topology

The current implementation uses heap-backed in-process bounded queues. The
next runtime hardening step is to replace those spike rings with the selected
shared-memory backing while keeping the same tile identities and link answers.

## Runtime Model

Tickoni follows Firedancer's topology discipline: tiles, links, workspaces,
mapping modes, and queue depths are explicit. A design is not ready until each
link can answer:

1. Which tile owns the state?
2. Which workspace holds it?
3. Which process maps it, and in what mode?
4. Which fields are written concurrently, and by whom?
5. What happens on overrun, restart, and shutdown?
6. Which metrics or logs expose unhealthy behavior?

For the Phase 0 pipeline, the default ownership model is one producer per link
and one owning tile for every mutable state object. Consumers read from bounded
links and publish their own progress counters.

### Phase 0 Tiles

| Runtime ID | Logical name | Responsibility |
| --- | --- | --- |
| `tkings` | `ingest_tile` | Receive synthetic payment events, validate framing, assign source offsets, and apply ingress backpressure |
| `tknorm` | `normalize_tile` | Convert source events into the canonical financial event schema |
| `tkdedu` | `dedupe_tile` | Deduplicate events by idempotency key and content hash |
| `tkpoly` | `policy_tile` | Evaluate versioned capability policy for runtime-visible decisions |
| `tkaudt` | `audit_tile` | Own append-only hash-chain ordering and JSONL export |
| `tkrepl` | `replay_tile` | Re-inject replay capsules with external effects disabled and report divergence |
| `tkmetr` | `metric_tile` | Export queue, tile, and runtime metrics |
| `tkdiag` | `diag_tile` | Export process, queue, crash, and supervisor diagnostics |

### Link Shape

Phase 0 links are implemented with this shape:

| Link | Producer | Consumer | Reliability | Payload |
| --- | --- | --- | --- | --- |
| `tkings_tknorm` | `tkings` | `tknorm` | reliable until ingress backpressure trips | canonicalizable payment event |
| `tknorm_tkdedu` | `tknorm` | `tkdedu` | reliable | normalized financial event |
| `tkdedu_tkpoly` | `tkdedu` | `tkpoly` | reliable | deduplicated event decision input |
| `tkpoly_tkaudt` | `tkpoly` | `tkaudt` | reliable | policy decision and event envelope |
| `tkrepl_tkings` | `tkrepl` | `tkings` or replay entrypoint | reliable in replay mode | replay capsule event |
| `*_tkmetr` | tile-local producers | `tkmetr` | unreliable where safe | metrics samples |
| `*_tkdiag` | tile-local producers | `tkdiag` | unreliable where safe | diagnostics samples |

Correctness-bearing event and audit links should prefer bounded reliable flow
control. Telemetry links may be unreliable if loss is counted and visible.

## Financial Event Schema

The first schema should be intentionally small. It only needs enough structure
to prove hashing, normalization, deduplication, policy decisions, and audit.

Required fields:

```text
source_system
source_offset
source_event_id
event_type
occurred_at_ns
received_at_ns
subject_id
amount
currency
idempotency_key
payload_hash
schema_version
```

The normalized event hash should be stable across process restarts and replay.
Fields that depend on local runtime receipt, such as `received_at_ns`, must be
handled explicitly so replay can distinguish source facts from runtime facts.

## Policy Boundary

Policy is a runtime control layer, not prompt guidance. Every meaningful action
is checked against:

- actor or service identity
- event or case scope
- environment
- data classification
- requested capability
- policy version
- action risk level
- required approvals

Phase 0 only needs enough policy machinery to prove allow, deny, and
require-approval records. Full agent and tool policy arrives in Phase 2.

Example:

```yaml
requested_action: create_case_candidate
event_type: payment.failed
environment: development
decision: allow
reason: phase0_non_mutating_runtime_event
policy_version: policy_2026_06_01
```

## Audit Journal

Tickoni's audit layer is a first-class system, not log text. `tkaudt` owns
append-only ordering for material runtime events.

Phase 0 audit records should include:

```text
audit_event_id
previous_hash
record_hash
timestamp_ns
source_system
source_offset
source_event_id
normalized_event_hash
policy_version
decision
reason
tile_id
schema_version
```

Later phases add case IDs, agent IDs, model IDs, prompt hashes, tool calls,
approval IDs, downstream action IDs, signatures, and evidence references.

Large payloads should be content-addressed instead of duplicated into every
audit record.

## Replay

Replay is a deterministic comparison path. It is not allowed to invoke
privileged external mutations.

Phase 0 replay must answer:

- Did normalized event hashes match?
- Did deduplication decisions match?
- Did policy decisions match?
- Did audit chain hashes match?
- What was the first divergent event?

Replay command concept:

```bash
tickoni replay capsule phase0-payment-001
```

Expected result shape:

```text
Replay: phase0-payment-001
Event hashes: matched
Dedup decisions: matched
Policy decisions: matched
Audit chain: matched

Result: REPLAY MATCH
```

## Agent Harness

Agents are Phase 2. They operate as controlled workers, not unrestricted actors.

Agents may:

- read permitted evidence
- classify events
- summarize cases
- call approved tools
- draft responses
- propose actions
- request human review

Agents may not directly:

- move money
- post accounting ledger adjustments
- release payouts
- freeze accounts
- change compliance status
- override policy
- access secrets
- delete audit records

Agent workers should be networkless. Model-provider network access belongs
behind `tkmodl`. Tool access belongs behind `tktool` and signed `tkadpt`
instances.

## Tool Broker And Adapters

The tool broker is Phase 2. It normalizes model-native function calls and
MCP-compatible tool requests into the same capability envelope. MCP is an
integration protocol, not a trust boundary.

The broker enforces:

- capability scopes
- environment boundaries
- input validation
- output validation
- rate limits
- data access controls
- audit logging
- policy checks

Signed adapters expand integration reach without expanding agent authority.

## CaseOps Board

The CaseOps Board is Phase 3. It is Tickoni's operational control plane, not a
generic Kanban board.

Each card represents a financial case backed by event data, evidence, agent
actions, policy decisions, approvals, and audit records.

Default V1 columns:

```text
New Event
-> Enriched
-> Agent Reviewed
-> Policy Decision
-> Human Review
-> Action Proposed
-> Resolved
-> Audited
```

## Privileged Actions

Privileged execution is last. Agents never receive direct authority to mutate
money-adjacent systems.

`tkexec` may be added only after policy, audit, replay, approval, and adapter
boundaries are already proven. For accounting ledger integrations such as
TigerBeetle, only `tkexec` receives ledger network credentials. Replay uses
deterministic mock connector results and never invokes production mutation.

## Sandboxing

Tickoni avoids using Docker as the primary security model for the runtime.
Docker may be useful for development and packaging, but the runtime security
model should be lower-level and explicit.

Runtime isolation:

- small tile processes
- seccomp profiles
- dropped capabilities
- restricted filesystem access
- explicit network permissions
- shared-memory channels
- bounded resources
- crash-only process design

Agent and adapter isolation:

- no production secrets by default
- no direct database mutation from agents
- no direct financial action from agents
- read-only access unless explicitly granted
- writable temporary workspace only
- capability-scoped envelopes
- full tool-call logging
- network access controlled per tile or adapter

## Related Docs

- [Development](./development.md)
- [Build](./build.md)
- [Testing](./testing-tickoni.md)
- [Observability](./observability.md)
- [Telemetry](./telemetry.md)
- [Security](./security.md)
- [Contribution Guide](./contribution/tickoni.md)
