# Tickoni Overview

## What Tickoni Is

Tickoni is an AI harness for agentic finance.

It is designed as a controlled execution and audit layer for agentic finance:
financial workflows where AI agents investigate events, use tools, and propose
actions across payment systems, accounting ledgers, and risk infrastructure.

It combines:

- a high-throughput event runtime
- AI agent orchestration
- policy-gated tool access
- immutable audit logging
- deterministic replay
- case lifecycle management
- human approval gates
- fintech-native adapters
- MCP-compatible and model-native function-call adapters
- agent identity and capability-scoped policy

The core idea is simple:

> AI agents may investigate, summarize, classify, recommend, draft, and propose.
> They must not directly move money, post accounting ledger adjustments, override controls, or bypass policy.

Tickoni lets financial companies use AI safely in operational workflows without giving autonomous agents uncontrolled access to production systems.

## What Tickoni Is Not

Tickoni is not:

- a generic AI agent framework
- a Claude Code clone
- a personal automation assistant
- a browser automation tool
- a project management app
- a trading strategy generator
- a quant research notebook
- a retail trading bot
- a plugin marketplace
- an autonomous money-moving agent

Tickoni is built for regulated agentic finance workflows where every action must be attributable, policy-checked, and recoverable.

## Positioning

### One-line Positioning

> Tickoni is the Zig-native AI harness for high-throughput fintech operations where every event, decision, and action is policy-gated, replayable, and audit-ready.

### Short Pitch

Financial institutions do not need another chatbot. They need an AI harness that can process millions of financial events, let agents operate on cases safely, and prove exactly what happened afterward.

Tickoni gives fintech teams:

- high-throughput event processing
- controlled AI agent workflows
- forensic auditability
- deterministic replay
- policy enforcement
- human approval gates
- fintech-native case operations

## Why Tickoni Exists

AI agents are becoming useful for operational work, but most current agent frameworks are not designed for financial infrastructure.

They usually lack:

- deterministic replay
- full action provenance
- policy-native permissions
- financial event semantics
- high-throughput runtime design
- audit-grade evidence capture
- strict separation between AI and money movement
- regulated workflow controls

That is unacceptable for fintech.

In financial systems, the hard problem is not asking an AI to summarize a case.

The hard problem is proving:

- which event triggered the case
- what data the agent saw
- which tools it used
- which policy allowed or denied the action
- which human approved it
- what downstream system changed
- whether the decision can be replayed
- whether the agent attempted forbidden behavior

Tickoni is built around those requirements from day one.

## Core Principles

### 1. AI Is Off the Critical Path

AI agents do not sit in the hot path for settlement, accounting ledger posting, account freezing, payout release, or other money-impacting actions.

Agents operate through a controlled tool broker and policy engine.

### 2. Policy Beats Prompting

Security and compliance are enforced by code, not natural-language instructions.

A prompt saying “do not release funds” is not a control.

A capability system that prevents the agent from calling `release_funds` is a control.

### 3. Every Action Is Audited

Tickoni captures complete operational trajectories:

- events
- prompts
- model outputs
- tool calls
- file reads/writes
- policy decisions
- human approvals
- downstream actions
- evidence used
- rejected actions

No summary-only logs.

### 4. Every Case Is Replayable

Material decisions are packaged into replay capsules containing the relevant event data, policy version, agent transcript, tool outputs, evidence, and action history.

Auditors should be able to replay a case and verify whether the same outcome is reproduced.

### 5. Runtime First, Agents Second

Tickoni is not a thin wrapper around LLM APIs.

The foundation is a deterministic, high-throughput tile-based event runtime.

Agents are attached to the runtime. They do not define the runtime.

### 6. Narrow Beats Generic

Tickoni is not trying to automate everything.

It focuses on high-value fintech operations:

- payments
- reconciliation
- fraud
- compliance
- disputes
- accounting ledger exceptions
- financial case operations

## Runtime Foundation

Tickoni is designed as a Zig-native harness/runtime layer built on a high-performance transaction-processing core derived from [Firedancer](https://docs.firedancer.io/), maintained by [Jump Crypto](https://jumpcrypto.com/).

Firedancer is relevant to Tickoni as systems plumbing, not as the harness identity. Its runtime has [demonstrated 1 million transactions per second in testing and replayed production transaction history](https://solana.com/news/network-health-report-june-2025). Its gradual hybrid deployment has processed real production transaction traffic, operated stably since mid-2024, and [demonstrated a 100,000 TPS production burst](https://solana.com/news/blog-internet-capital-markets).

The important point is the transaction-processing architecture:

- high-throughput transaction/event processing
- isolated execution tiles
- shared-memory pipelines
- low-level performance engineering
- restrictive sandboxing
- minimal syscall surfaces
- deterministic processing discipline
- strong observability
- security-reviewed systems design
- proven performance focus

Tickoni applies these ideas to fintech event operations.

**Firedancer architecture pattern:**

- high-throughput transaction pipeline
- isolated tiles
- shared-memory execution
- restrictive sandboxing
- audited systems design

**Tickoni architecture pattern:**

- high-throughput financial event pipeline
- policy-gated AI agents
- forensic audit journal
- deterministic replay
- fintech case operations

The goal is to reuse the architectural lessons of a production-exercised high-throughput runtime and apply them to regulated agentic finance workflows: payments, reconciliation, fraud, disputes, compliance, accounting ledger exceptions, and money-moving workflows.

Firedancer has been performance-tested, designed around restrictive isolation, and exercised against real production transaction traffic through its gradual hybrid deployment. That makes its architectural approach especially relevant for fintech systems where correctness, throughput, isolation, and auditability matter. Tickoni builds on those lessons rather than starting from a generic web-service or chatbot stack.

### Why This Matters for Fintech

Fintech systems need to process large volumes of events while preserving strict control over actions.

Tickoni processes:

- payment authorization events
- settlement events
- payout events
- reconciliation breaks
- fraud alerts
- compliance alerts
- dispute events
- accounting ledger mismatches
- customer risk events
- merchant risk events

Most AI harnesses are built around chat, tools, and workflow automation.

Tickoni is built around financial event integrity.

That means the runtime must be able to answer:

- which event entered the system
- how it was normalized
- which case it created or updated
- which agent saw it
- which tools the agent used
- which policy allowed or denied action
- which human approved it
- which downstream system changed
- whether the entire sequence can be replayed

A Firedancer-style architecture is a strong foundation for this because it treats the system as a high-throughput, explicitly controlled execution pipeline rather than a loose collection of services.

### Developer Integration Surface

Tickoni should be straightforward to extend from modern AI development
environments, including Claude Code and OpenAI Codex. That means explicit
schemas, documented APIs, MCP-compatible tool descriptions, and testable
capability manifests. Development convenience does not grant a coding agent
production credentials or unrestricted capabilities.

### Why Zig

Zig is used for the Tickoni harness/runtime layer because it provides:

- direct C interoperability
- explicit memory management
- no garbage collector
- predictable systems behavior
- strong build tooling
- readable low-level code
- good fit for binary protocols and schemas
- practical integration with C17 components

Zig is not chosen because it is safer than Rust. It is chosen because Tickoni’s v1 architecture sits close to a C17/Firedancer-style substrate.

### Why Not Rust First

Rust is a strong choice for a clean-room fintech infrastructure platform.

However, when building directly on top of C17 systems components, Rust introduces a larger FFI and ownership boundary. Rust’s safety guarantees do not automatically apply across C interfaces, shared memory, allocator boundaries, or externally mutated state.

Tickoni’s v1 bet is:

- C17 substrate where nanoseconds, throughput, and syscall discipline matter
- Zig harness/runtime layer where schemas, adapters, audit, replay, and policy matter
- AI agents outside the critical path

Rust may still be useful later for non-critical-path services, enterprise integrations, policy tooling, or cloud control plane components.

## Users

Tickoni is built for teams operating high-volume financial systems:

- payment processors
- payment service providers
- neobanks
- banking-as-a-service platforms
- card issuers
- acquirers
- remittance companies
- lending platforms
- marketplaces with payment operations
- fintech infrastructure companies
- agentic finance teams
- fraud operations teams
- reconciliation teams
- compliance operations teams

## Vision

Tickoni’s long-term vision is to become the execution and audit layer for AI-operated financial infrastructure.

```text
Every financial event processed.
Every agent action controlled.
Every decision replayable.
Every downstream change attributable.
```

Long-term platform components:

```text
Tickoni Runtime
  high-throughput Zig event pipeline

Tickoni Harness
  agents, tools, policies, approvals

Tickoni CaseOps
  board for payments, fraud, reconciliation, disputes, compliance

Tickoni Audit
  forensic replay journal

Tickoni Connect
  processors, banks, core accounting ledgers, CRMs, risk engines

Tickoni Enterprise
  RBAC, SIEM, compliance exports, data residency
```

## Strategic Differentiation

Most AI harnesses optimize for autonomy.

Tickoni optimizes for accountable autonomy.

The infrastructure differentiation is the combination of:

```text
high-throughput event runtime
+ policy-gated agents
+ forensic audit journal
+ deterministic replay
+ fintech-native case workflows
```

The strongest differentiation:

> Generic agent frameworks show what the agent did.
> Tickoni proves whether the agent was allowed to do it, what evidence it used, what changed, and whether the decision can be replayed.

See [Competitive Positioning](position/positioning.md) for comparisons with adjacent agent harnesses and developer tools.

## Status

The fintech AI harness builds on the Agave-free Tickoni runtime foundation in this repository.

The intended v1 is a narrow, opinionated implementation focused on:

- high-throughput financial event processing
- controlled AI case operations
- strict policy enforcement
- forensic auditability
- deterministic replay
