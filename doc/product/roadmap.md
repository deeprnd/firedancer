# Tickoni Roadmap

## V1 Roadmap

V1 should prove the category with a narrow, high-value harness.

### V1 Goal

Build the first usable version of Tickoni as a high-throughput, isolated, cost-controlled, policy-gated AI harness for fintech event operations.

V1 proves four infrastructure advantages:

1. event processing speed
2. financial control-plane isolation
3. inference spend governance
4. forensic audit replay

## V1 Feature Set

The feature set describes the full V1 product. The implementation order is the
phase plan below: Phase 0 proves the runtime shape, Phase 1 processes real
fintech-like events, Phase 2 attaches controlled agents, Phase 3 adds CaseOps,
and Phase 4 packages realistic workflows.

### Runtime: Phase 0/1

- Zig-native event runtime
- tile-based event pipeline
- financial event schema
- event ingestion API
- event normalization
- deduplication
- case creation
- deterministic replay foundation
- backpressure handling
- runtime telemetry

Phase 0 uses a synthetic payment stream to prove bounded flow, event hashing,
audit, replay, telemetry, and supervisor behavior. Case creation and the real
ingestion API are Phase 1.

### Isolation / Control Boundary: Phase 0/2

- memory-isolated agent execution
- no arbitrary shell access
- no unrestricted syscalls from agent logic
- no unrestricted network access
- signed financial adapters only
- capability-scoped execution
- adapter permission manifests
- sensitive-action boundaries
- runtime enforcement independent of prompts

Phase 0 should prove runtime isolation and sandbox failure behavior. Agent,
adapter, and model isolation are Phase 2.

### Agent Harness: Phase 2

- model-provider abstraction
- role-based agents
- payment exception agent
- reconciliation agent
- fraud triage agent
- risk reviewer agent
- controlled tool broker
- model-native function-call and MCP-compatible tool envelopes
- explicit agent identity context
- tool-call audit
- prompt/output capture
- agent budget controls
- per-agent token budgets
- per-case inference budgets
- model routing policies
- context-size controls
- retry-loop limits
- model usage attribution

### Policy: Phase 0/2

- capability-based permission system
- resource and downstream-system scopes
- action allow/deny/approval decisions
- policy versioning
- environment separation
- production-safe defaults
- human approval requirement for money-impacting actions
- denied-action logging

Phase 0 needs allow, deny, and require-approval records for runtime events.
Agent, tool, model, and approval policy checks arrive in Phase 2 and Phase 3.

### Audit: Phase 0/1/2

- append-only audit journal
- hash-chained audit records
- content-addressed evidence storage
- full agent trajectory capture
- policy decision log
- case event timeline
- replay capsule per material case
- audit export as JSONL

Phase 0 proves append-only event audit and replay comparison. Case capsules are
Phase 1. Agent trajectories and model records are Phase 2.

### Inference Governance: Phase 2

- token accounting per case
- token accounting per agent
- model call audit trail
- model routing rules
- context window controls
- inference budget enforcement
- runaway loop prevention
- cached context reuse
- cost attribution by workflow

### Fintech Workflows: Phase 4

#### Payment Exceptions

- ingest failed payment events
- classify failure reason
- retrieve related processor records
- summarize cause
- propose retry/routing path
- draft customer or merchant response

#### Reconciliation Breaks

- ingest accounting ledger mismatch events
- compare source records
- identify likely discrepancy reason
- prepare correction proposal
- route to finance operations
- create evidence packet

#### Fraud/Risk Triage

- ingest suspicious activity events
- assemble related evidence
- summarize risk pattern
- classify severity
- recommend review queue
- propose non-executing risk action

### CaseOps Board: Phase 3

- case lifecycle board
- event-backed cards
- evidence panel
- agent findings panel
- policy decision panel
- approval panel
- audit timeline
- replay status indicator

### TigerBeetle FinanceDB Integration: after Runtime And Policy Boundaries

Goal: integrate TigerBeetle as the finance-native accounting ledger backend without
weakening Tickoni's policy, isolation, audit, or replay boundaries.

TigerBeetle is a specialized financial transaction database, not Tickoni's
general-purpose application database. Tickoni should keep case metadata,
workflow state, evidence, and audit records in their dedicated stores.

Deliverables:

- generic `accounting_ledger_connector` interface
- TigerBeetle connector implementation
- isolated privileged action executor
- no direct TigerBeetle connectivity from agents
- signed action envelopes with deterministic action IDs
- policy and human-approval enforcement before accounting ledger posting
- deterministic `approved_action_id` to TigerBeetle `transfer.id` mapping
- append-only audit records before and after each mutation attempt
- transfer result read-back and reconciliation
- network isolation, mTLS, and scoped executor credentials
- deterministic mock connector for replay
- isolated TigerBeetle environment for integration tests and demos
- finance database telemetry and invariant alerts

Exit criteria:

- only the privileged action executor can reach TigerBeetle
- an agent cannot directly create, modify, or submit a transfer
- retries cannot create duplicate transfers
- every transfer attempt and result is present in the Tickoni audit chain
- reconciliation detects mismatched or missing transfer outcomes
- replay never mutates a production TigerBeetle cluster
- TigerBeetle remains replaceable through the `accounting_ledger_connector` boundary

## V1 Non-Goals

V1 should not include:

- autonomous money movement
- autonomous accounting ledger posting
- autonomous account freezing
- autonomous payout approval
- autonomous compliance decisions
- quant research
- trading strategy generation
- generic coding assistant features
- open plugin marketplace
- browser automation
- email/calendar automation
- arbitrary custom workflows
- full enterprise RBAC
- complex dashboarding
- natural-language policy editing
- unbounded agent swarms

## V1 Success Criteria

Tickoni v1 is successful if it can demonstrate:

1. high-throughput ingestion of fintech events
2. deterministic case creation from event streams
3. agent-assisted case investigation
4. strict capability enforcement
5. full audit capture of agent behavior
6. replayable case decisions
7. human approval gates for sensitive actions
8. useful CaseOps board for operators
9. clear differentiation from generic agent frameworks
10. credible systems architecture for fintech buyers
11. agent execution cannot escape capability boundaries
12. every case has measurable inference cost
13. runaway agent loops are prevented by runtime controls

## Completed Foundation Story: Tickoni Runtime Cutover

Status: completed on 2026-06-01.

As a Tickoni maintainer, I need an Agave-free canonical runtime identity so
new harness work builds on the Tickoni path without depending on the legacy
Frankendancer runtime.

Delivered:

- canonical validator build entry and runtime binary: `tickoni`
- default CI build coverage for `tickoni`
- default `FD_WITH_AGAVE=0` gating for legacy Frankendancer components
- preferred config environment variable: `TICKONI_CONFIG_TOML`
- Tickoni release tag prefix: `tickoni-v<semver>`
- Tickoni container workspace path: `/data/tickoni`

Temporary compatibility debt:

- `firedancer` remains a symlink to `tickoni` until downstream
  consumers are migrated.
- `FIREDANCER_CONFIG_TOML` remains a deprecated fallback for
  `TICKONI_CONFIG_TOML`.
- Both compatibility shims have a removal date of 2026-12-31.
- Some `src/app/firedancer*` paths and Firedancer symbols remain to preserve
  upstream synchronization and internal compatibility.
- Legacy Frankendancer source remains gated and outside the canonical Tickoni
  runtime path.

Follow-up acceptance criteria:

1. remove the `firedancer` runtime alias after downstream migration sign-off
2. remove the `FIREDANCER_CONFIG_TOML` fallback after its deprecation window
3. keep default CI builds compiling `tickoni`
4. prevent new Tickoni harness work from depending on gated Agave paths

## Development Philosophy

Tickoni should be built as serious systems software.

Priorities:

1. correctness
2. isolation
3. auditability
4. deterministic replay
5. policy enforcement
6. spend control
7. operational usefulness
8. throughput
9. latency
10. developer ergonomics
11. extensibility
12. broad agent autonomy

In that order.

## Build Strategy

### Phase 0: Technical Spike

Goal: prove the runtime shape.

Deliverables:

- Zig tile supervisor
- basic event schema
- ingest tile
- normalize tile
- audit tile
- replay prototype
- one synthetic payment event stream
- memory sandbox prototype
- capability enforcement prototype
- token accounting prototype

Exit criteria:

- deterministic replay works
- audit journal is append-only
- tiles can be started, stopped, and monitored
- event hashes are stable
- agent execution cannot access unauthorized capabilities
- inference usage is measurable per event

### Phase 1: V1 Runtime

Goal: process real fintech-like events.

Deliverables:

- event ingestion API
- financial event schema
- tile pipeline
- case creation
- policy decision path
- audit journal
- replay capsule
- runtime telemetry

Exit criteria:

- events produce cases deterministically
- case history is auditable
- replay detects divergence

### Phase 2: Agent Harness

Goal: attach controlled AI agents.

Deliverables:

- model-provider abstraction
- tool broker
- role-based agents
- capability manifests
- prompt/tool audit capture
- denied-action capture
- agent budget controls
- memory sandbox integration
- model spend accounting
- inference budgets
- model routing
- context management
- runaway-loop protection

Exit criteria:

- agent can investigate a case
- agent cannot call forbidden tools
- every tool call is audited
- every output is attached to the case
- agent cannot exceed assigned inference budget
- agent cannot bypass capability boundary

### Phase 3: CaseOps Board

Goal: make operations usable.

Deliverables:

- board UI
- case cards
- evidence panel
- agent findings
- policy decision view
- approval workflow
- audit timeline
- replay status

Exit criteria:

- operator can review a case end-to-end
- operator can approve or reject proposed action
- auditor can inspect full case history

### Phase 4: Fintech Workflow Pack

Goal: prove business value.

Deliverables:

- payment exception workflow
- reconciliation break workflow
- fraud/risk triage workflow
- demo adapters
- replayable sample data
- policy templates
- audit exports

Exit criteria:

- Tickoni can run realistic fintech operations demos
- each workflow produces useful agent output
- every workflow is policy-gated and replayable

## Long-Term Roadmap

### V2

- real processor connectors
- core accounting ledger connectors
- agentic payments protocol evaluation
- MCP server and function-call SDK for signed financial adapters
- developer integration guides for Claude Code and OpenAI Codex
- case assignment
- SLA management
- SIEM export
- role-based access control
- team workflows
- multi-agent review
- evidence graph
- compliance export packs

### V3

- regulated workflow templates
- deployment approval system
- data residency controls
- enterprise secrets integration
- advanced anomaly detection
- on-prem deployment
- private model support
- SOC2/ISO support artifacts

### V4

- full agentic finance control plane
- multi-region event processing
- cross-entity fraud graph
- advanced replay/debugger
- policy simulation
- formal verification of selected policies
- marketplace for signed fintech adapters
- enterprise governance suite

## Design Rules

### Agents

Agents may:

- investigate
- classify
- summarize
- draft
- recommend
- propose
- escalate

Agents may not directly:

- move money
- post accounting ledger adjustments
- delete evidence
- override policy
- approve regulated outcomes
- access secrets
- bypass audit

### Runtime

Runtime must:

- process events deterministically
- isolate critical components
- produce audit records
- support replay
- reject malformed events
- handle backpressure
- expose telemetry

Runtime must not:

- depend on model calls
- use prompts for enforcement
- hide state changes
- allow unaudited mutations
- expose raw system access to agents
- rely on containers as the only isolation layer
- allow unlimited inference loops

### Audit

Audit must:

- be append-only
- be hash-chained
- record policy decisions
- record denied actions
- record agent trajectories
- support replay
- preserve evidence integrity

Audit must not:

- store summaries only
- allow silent deletion
- depend on the UI
- omit failed or denied actions
