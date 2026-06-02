# Tickoni ⏱️😈

**High-throughput execution harness for AI agents.**

Fast runtime first. Agents second.

Tickoni turns AI agents into controlled, observable execution units running on a high-performance event engine.

Built for:

- ⚡ speed
- 🧱 isolation
- 🛡️ controlled execution
- 🔎 observability
- 📜 auditability
- ⏪ replay

AI models are probabilistic.

The systems running them should not be.

## Why

Agents are getting more powerful.

The runtimes around them are still mostly:

prompt → tool call → response

Tickoni treats AI execution as a systems problem.

Every agent action becomes an event:

event → policy → execution → audit → replay

The goal:

Know exactly:

- what happened
- why it happened
- what changed
- how to reproduce it

No mystery state.

## What You Get

| Capability             | Description                                                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------------ |
| ⚡ Execution Engine    | High-throughput event runtime forked from Firedancer's systems core and evolved for AI workloads |
| 🧱 Tile Runtime        | Small isolated execution units communicating through explicit shared-memory channels             |
| 🤖 Agent Harness       | Run AI agents as controlled workers with scoped capabilities instead of unrestricted access      |
| 🛠️ Tool Broker         | Every tool call is authorized, executed, measured, and recorded                                  |
| 🛡️ Capability Security | Agents receive explicit permissions instead of owning the environment                            |
| 📜 Audit Engine        | Capture events, prompts, responses, tool calls, state transitions, failures, and decisions       |
| ⏪ Replay Capsules     | Reconstruct previous executions for debugging, testing, and verification                         |
| 📊 Runtime Telemetry   | Monitor throughput, latency, queues, resources, tools, policies, and failures                    |
| 🔌 Model Agnostic      | Connect different model providers without coupling execution logic to the model                  |
| 🧩 Extensible Runtime  | Add custom agents, tools, policies, and execution tiles                                          |

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
- tool scheduling
- state transitions
- resource boundaries

Everything is an event.

Everything has ownership.

## Isolation

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

agent → capability check → tool execution → audit → replay

Every tool call captures:

- input
- output
- permissions
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

throughput → control → isolation

## Audit & Replay

Execution history is structured data, not log text.

| Captured            | Purpose                                   |
| ------------------- | ----------------------------------------- |
| ⚡ Events           | Reconstruct execution flow                |
| 🤖 Agent runs       | Track every agent decision                |
| 🧠 Prompts          | Know exactly what context was provided    |
| 💬 Model responses  | Inspect generated output                  |
| 🛠️ Tool calls       | See every external interaction            |
| 🛡️ Policy decisions | Verify why actions were allowed or denied |
| 🔢 Token usage      | Measure cost of every execution           |
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

- [Overview](doc/overview.md)
- [Competitive positioning](doc/positioning.md)
- [Architecture](doc/architecture.md)
- [Workflows](doc/workflows.md)
- [Observability](doc/observability.md)
- [Security](doc/security.md)
- [Audit and replay](doc/audit.md)
- [Roadmap](doc/roadmap.md)
- [Build system](doc/build-system.md)
- [Testing](doc/testing.md)

## License

Apache-2.0
