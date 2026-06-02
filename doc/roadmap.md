# Tickoni Roadmap

## V1 Roadmap

V1 should prove the category with a narrow, high-value harness.

### V1 Goal

Build the first usable version of Tickoni as a high-throughput, policy-gated AI harness for fintech event operations.

V1 should support:

1. payment exception handling
2. reconciliation break handling
3. fraud/risk case triage

## V1 Feature Set

### P0: Runtime

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

### P0: Agent Harness

- model-provider abstraction
- role-based agents
- payment exception agent
- reconciliation agent
- fraud triage agent
- risk reviewer agent
- controlled tool broker
- tool-call audit
- prompt/output capture
- agent budget controls

### P0: Policy

- capability-based permission system
- action allow/deny/approval decisions
- policy versioning
- environment separation
- production-safe defaults
- human approval requirement for money-impacting actions
- denied-action logging

### P0: Audit

- append-only audit ledger
- hash-chained audit records
- content-addressed evidence storage
- full agent trajectory capture
- policy decision log
- case event timeline
- replay capsule per material case
- audit export as JSONL

### P0: CaseOps Board

- case lifecycle board
- event-backed cards
- evidence panel
- agent findings panel
- policy decision panel
- approval panel
- audit timeline
- replay status indicator

### P0: Fintech Workflows

#### Payment Exceptions

- ingest failed payment events
- classify failure reason
- retrieve related processor records
- summarize cause
- propose retry/routing path
- draft customer or merchant response

#### Reconciliation Breaks

- ingest ledger mismatch events
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

## V1 Non-Goals

V1 should not include:

- autonomous money movement
- autonomous ledger mutation
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
2. auditability
3. deterministic replay
4. policy enforcement
5. operational usefulness
6. throughput
7. latency
8. developer ergonomics
9. extensibility
10. broad agent autonomy

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

Exit criteria:

- deterministic replay works
- audit ledger is append-only
- tiles can be started, stopped, and monitored
- event hashes are stable

### Phase 1: V1 Runtime

Goal: process real fintech-like events.

Deliverables:

- event ingestion API
- financial event schema
- tile pipeline
- case creation
- policy decision path
- audit ledger
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

Exit criteria:

- agent can investigate a case
- agent cannot call forbidden tools
- every tool call is audited
- every output is attached to the case

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
- ledger system connectors
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

- full financial operations control plane
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
- mutate ledgers
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
