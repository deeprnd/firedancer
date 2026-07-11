# Tickoni ⏱️👹

<table>
  <tr>
    <td>
      <!-- badge:build:start -->
<img alt="Build" src="https://img.shields.io/badge/build-passing-brightgreen?style=flat-square" />
<!-- badge:build:end -->
    </td>
    <td>
      <!-- badge:quality:start -->
<img alt="Quality" src="https://img.shields.io/badge/quality-passing-brightgreen?style=flat-square" />
<!-- badge:quality:end -->
    </td>
    <td>
      <!-- badge:security:start -->
<img alt="Security" src="https://img.shields.io/badge/security-unknown-lightgrey?style=flat-square" />
<!-- badge:security:end -->
    </td>
  </tr>
  <tr>
    <td>
      <!-- badge:unit:start -->
<img alt="Unit Tests" src="https://img.shields.io/badge/unit%20tests-passing-brightgreen?style=flat-square" />
<!-- badge:unit:end -->
    </td>
    <td>
      <!-- badge:integration:start -->
<img alt="Integration Tests" src="https://img.shields.io/badge/integration%20tests-passing-brightgreen?style=flat-square" />
<!-- badge:integration:end -->
    </td>
    <td>
      <!-- badge:system:start -->
<img alt="System Tests" src="https://img.shields.io/badge/system%20tests-passing-brightgreen?style=flat-square" />
<!-- badge:system:end -->
    </td>
    <td>
      <!-- badge:e2e:start -->
<img alt="E2E Tests" src="https://img.shields.io/badge/e2e%20tests-passing-brightgreen?style=flat-square" />
<!-- badge:e2e:end -->
    </td>
  </tr>
  <tr>
    <td>
      <!-- badge:cov-fd:start -->
<img alt="HFT Engine Coverage" src="https://img.shields.io/badge/engine%20coverage-unknown-lightgrey?style=flat-square" />
<!-- badge:cov-fd:end -->
    </td>
    <td>
      <!-- badge:cov-tk:start -->
<img alt="AI Harness Coverage" src="https://img.shields.io/badge/harness%20coverage-90.2%25-brightgreen?style=flat-square" />
<!-- badge:cov-tk:end -->
    </td>
    <td></td>
  </tr>
</table>

![Tickoni](assets/banner.png)

**High-throughput AI harness for agentic finance.**

Fast runtime first. Agents second.

Tickoni turns AI agents into controlled, observable execution units running on a high-performance event engine.

For agentic finance, that means agents can inspect payment and accounting ledger
events, prepare payment retries, propose ledger corrections, and recommend
trading actions without receiving unrestricted control of a production system.

Generic harnesses ask whether an agent can read a file, call a tool, open a
browser, or run a shell command.

Tickoni asks the financial questions:

- Which payment rail, beneficiary, IBAN, wallet, broker account, or exchange is in scope?
- Which ledger book, settlement batch, asset class, market, sector, side, and order type is allowed?
- How much can the agent recommend or propose per case, day, month, destination, or instrument?
- How frequently can it propose retries, transfers, corrections, or trades?
- Which actions are observe-only, proposal-only, approval-required, or executable by a privileged path?

Built for:

- ⚡ speed
- 🧱 bounded financial authority
- 🛡️ destination, limit, and approval controls
- 🔎 case-level cost and consequence visibility
- 📜 forensic evidence
- ⏪ replay

AI models are probabilistic.

The systems running them should not be.

## Why Tickoni?

> Tickoni is named for `tick` and `oni`. The `tick` is the clock: every agent action advances on an explicit timeline you can measure, gate, and replay. The `oni` is the daemon: fast, tireless, and always executing. A powerful engine built for precision and control. Underneath, powered by Firedancer's trading-engine architecture, running a supercharged C-based event engine, Tickoni layers agent execution, embeddings, memory, and a plugin system on top of deterministic systems infrastructure.

Agents are getting more powerful.

The runtimes around them are still mostly:

prompt → OS permission → tool call → response

Tickoni treats AI execution as a financial control-plane problem.

Every agent action becomes an event:

financial event → capability envelope → policy decision → proposal or execution path → evidence → replay

The goal:

Know exactly:

- what happened
- why it happened
- what financial consequence was proposed or attempted
- which destination, limit, venue, account, or approval scope applied
- how to reproduce it

No mystery state.

## What You Get

| Capability             | Description                                                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------------ |
| ⚡ Execution Engine    | High-throughput event runtime forked from Firedancer's systems core and evolved for AI workloads |
| 🧱 Tile Runtime        | Small isolated execution units communicating through explicit shared-memory channels             |
| 🤖 Agent Harness       | Run payment, reconciliation, fraud, risk, and trading agents as controlled financial operators   |
| 🛠️ Financial Tool Broker | Every adapter call is checked against payment, ledger, trading, risk, destination, and limit scope |
| 🛡️ Capability Security | Agents receive financial authority envelopes instead of broad tool or system access              |
| 🔑 Agent Identity       | Every action is bound to an agent role, workflow, case, policy version, and capability scope      |
| 📜 Evidence Engine      | Capture events, prompts, responses, adapter calls, proposals, approvals, failures, and decisions |
| ⏪ Replay Capsules     | Reconstruct previous executions for debugging, testing, and verification                         |
| 📊 Runtime Telemetry   | Monitor throughput, latency, queues, resources, capabilities, policies, costs, and failures      |
| 🔌 Model Agnostic      | Connect different model providers without coupling execution logic to the model                  |
| 🧩 Extensible Runtime  | Add custom agents, signed financial adapters, policy templates, and execution tiles              |

## Architecture

Tickoni is built on a high-throughput execution engine forked from Firedancer's systems core.

The original engine was designed around:

- million TPS-class throughput goals
- isolated execution components
- shared-memory communication
- predictable resource usage
- low-level performance engineering

Tickoni evolves this foundation into an AI execution runtime.

### Runtime

The runtime coordinates:

- event flow
- agent execution
- financial adapter scheduling
- state transitions
- resource boundaries
- destination, exposure, and approval boundaries

Everything is an event.

Everything has ownership.

## Financial Control

Tickoni follows a tile-based execution model.

Each tile has:

- one responsibility
- owned state
- bounded resources
- explicit capabilities
- controlled communication
- observable execution

Tiles communicate through shared-memory channels.

Every interaction follows the same path:

agent → financial capability check → adapter/proposal path → evidence → replay

Model-native function calls and MCP-compatible tools terminate at the same
broker boundary. The runtime treats protocol compatibility as an integration
surface, not as permission to bypass policy.

Tickoni's capability model is finance-native. It can express constraints like:

- payment retries only on approved rails and processors
- ledger corrections as proposals, not postings
- crypto transfers only to allowlisted wallets and networks
- trading recommendations only for approved accounts, venues, sectors, and instruments
- maximum notional per order, day, month, destination, customer, or portfolio
- minimum order intervals and holding periods to prevent day-trading behavior
- human approval before money-impacting execution

Every financial adapter call or proposal captures:

- input
- output
- financial capability
- destination and scope
- limits and frequency checks
- approval state
- execution metadata
- timing
- resource usage
- token usage
- result

Allowed actions are recorded.

Denied actions are recorded too.

## Built with Zig

Zig gives Tickoni:

- clean Zig abstractions over high-performance C primitives
- predictable execution with explicit memory and resource ownership
- low-overhead runtime boundaries for agents, tools, and tiles
- simple integration with sandboxing and isolation primitives

This keeps the message around the three pillars:

throughput → consequence control → replay

## Evidence & Replay

Execution history is structured financial evidence, not log text.

| Captured            | Purpose                                   |
| ------------------- | ----------------------------------------- |
| ⚡ Events           | Reconstruct execution flow                |
| 🤖 Agent runs       | Track every agent decision                |
| 🧠 Prompts          | Know exactly what context was provided    |
| 💬 Model responses  | Inspect generated output                  |
| 🛠️ Adapter calls     | See every payment, ledger, trading, risk, or compliance interaction |
| 🛡️ Policy decisions | Verify why actions were allowed, denied, or approval-required |
| 💸 Financial scope   | Record destination, account, rail, market, sector, instrument, and limit checks |
| 🔢 Token usage      | Measure cost by case, workflow, agent, and policy version |
| ⏱️ Timing           | Track latency and bottlenecks             |
| 💾 State changes    | Understand what changed                   |
| ❌ Failures         | Debug broken execution paths              |
| ⏪ Replay data      | Reproduce previous runs                   |

Replay turns agent execution into a deterministic artifact:

previous input → same environment → comparable output

Debug behavior.

Measure changes.

Find divergence.

## Observability

Expose the runtime:

- throughput
- latency
- queues
- execution time
- resource usage
- tool activity
- policy decisions
- failures
- replay divergence

No black boxes.

## Documentation

- [Strategy](doc/strategy/README.md)
- [Architecture](doc/knowledge/architecture.md)
- [Development](doc/execution/development.md)
- [Build](doc/execution/build.md)
- [Testing](doc/execution/testing-tickoni.md)
- [Observability](doc/execution/observability.md)
- [Telemetry](doc/execution/telemetry.md)
- [Security](doc/execution/security.md)
- [Roadmap](doc/strategy/positioning.md)

## License

Apache-2.0
