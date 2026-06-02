# Tickoni Observability

## Principle

No black boxes.

Every tile, every agent, every tool call, every policy decision exposes runtime state.

Observability is not a logging layer added after the fact. It is a first-class property of the tile-based execution model. Each tile emits its own metrics. The harness aggregates them. Operators see the full picture without needing to infer state from log text.

## What Is Exposed

| Signal            | What It Tells You                                             |
| ----------------- | ------------------------------------------------------------- |
| Throughput        | Events and tool calls processed per second, per tile          |
| Latency           | Time from event ingestion to agent dispatch, per stage        |
| Queue depth       | Backpressure between tiles; leading indicator of saturation   |
| Execution time    | Per-agent run duration, per-tool call duration                |
| Resource usage    | Memory, CPU, and file descriptor usage per tile process       |
| Token usage       | Model tokens consumed per agent run and per case              |
| Tool activity     | Call rate, success rate, error rate per tool                  |
| Policy decisions  | Allow/deny/require-approval counts and rates per policy       |
| Failures          | Tile crashes, tool errors, agent errors, policy engine errors |
| Replay divergence | Rate and reason of replay mismatches                          |

## Per-Tile Visibility

Observability follows the tile boundary.

Each tile process exposes its own counters:

```text
ingest_tile
  events_received
  events_dropped
  parse_errors
  latency_ns_p50 / p99

policy_tile
  checks_total
  allow_total
  deny_total
  require_approval_total
  latency_ns_p50 / p99

agent_dispatch_tile
  runs_started
  runs_completed
  runs_failed
  tokens_in
  tokens_out
  latency_ns_p50 / p99

audit_tile
  records_written
  hash_chain_errors
  write_latency_ns_p50 / p99
```

Aggregating across tiles gives a full pipeline view.

Drilling into a single tile isolates the source of saturation or failure without guessing.

## Tool-Level Metrics

Every tool call through the broker is measured individually:

```text
tool: read_processor_log
  calls_total
  success_total
  error_total
  denied_total
  latency_ns_p50 / p99
  last_error
```

This makes it possible to answer:

- which tools are slow
- which tools are failing
- which tools are being denied frequently
- whether a specific tool is a bottleneck for agent latency

## Agent Run Metrics

Each agent execution emits:

```text
agent: payment_exception_agent
  runs_total
  runs_completed
  runs_failed
  runs_timed_out
  tool_calls_per_run_avg
  tokens_in_total
  tokens_out_total
  latency_ns_p50 / p99
```

Token usage is tracked per run and rolled up per case to support cost attribution.

## Failure Visibility

Failures are not silent.

The runtime follows Firedancer's crash-only model: if a tile process exits unexpectedly, the entire process tree comes down. There is no partial degraded state that is invisible to operators.

Failure categories:

- tile exit (unexpected process termination)
- tool error (external call failed)
- policy engine error (capability check failed to evaluate)
- agent error (model returned an unexpected result)
- audit write failure (hash-chain append failed)
- replay divergence (replay does not match recorded outcome)

Each category has a dedicated counter and is surfaced in the runtime telemetry.

## Replay Divergence

Replay divergence is treated as a serious event, not a background statistic.

When a replay does not match:

```text
replay_divergence_total        (count)
replay_divergence_last_case    (case_id)
replay_divergence_last_reason  (policy_version_mismatch | evidence_hash_mismatch | tool_output_mismatch | ...)
```

Divergence means either the environment changed (expected) or something is wrong with the audit record or policy state (not expected). Both require investigation.
