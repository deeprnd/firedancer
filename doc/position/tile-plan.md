# Tickoni V1 Tile Plan

## Purpose

This document maps the validator tiles currently present in the repository and
defines a separate V1 tile topology for Tickoni's fintech event harness.

The main design decision is:

> Do not morph Solana validator tiles into Tickoni product tiles. Add a new
> Tickoni topology with new tile names, stop linking validator tiles into the
> canonical `tickoni` binary, then delete validator-only source from the product
> branch.

This keeps Tickoni product work out of upstream-hot Firedancer paths and avoids
giving unrelated concepts the same tile identity.

## Current Repository State

The repository now has two Tickoni-relevant runtime paths:

1. The compatibility `tickoni` validator binary is still derived from the full
   Firedancer application. Its main program lives in
   [`src/app/firedancer/main.c`](../../src/app/firedancer/main.c), and its
   topology lives in
   [`src/app/firedancer/topology.c`](../../src/app/firedancer/topology.c).
2. The new Zig-native Tickoni scaffold exists under
   [`src/app/tickoni/`](../../src/app/tickoni/) and
   [`src/tickoni/`](../../src/tickoni/). It currently builds
   `tickoni-supervisor` through [`build.zig`](../../build.zig).

The legacy Frankendancer topology remains in
[`src/app/fdctl/topology.c`](../../src/app/fdctl/topology.c). It is gated behind
`FD_WITH_AGAVE=1` and is outside the canonical runtime path.

The Zig scaffold has moved past the Step 1 synthetic lifecycle. Phase 0 now
runs a synthetic payment pipeline:

```text
tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
tkrepl, tkmetr, tkdiag
```

That path starts, stops, and monitors Tickoni-owned non-Solana tiles in
dev/test mode. It proves bounded in-process queues, stable event hashes,
append-only audit hashing, deterministic replay comparison, runtime metrics,
diagnostics, audited malformed-event rejection, and simulated sandbox failure
behavior.
It does not yet implement real shared-memory queues, sandboxed child processes,
durable audit storage, production telemetry export, a full capability envelope,
model integration, stub financial adapters, case routing, evidence storage,
external ingestion, or agents.

The inherited C topology ABI stores tile names in `char name[ 7UL ]`, so any
tile name registered through that ABI is limited to six characters. The
proposed runtime IDs below use a `tk` prefix and fit that limit. Configuration
and documentation should expose longer descriptive aliases.

## Existing Validator Topologies

### Frankendancer

Frankendancer is the hybrid Rust/C validator. Its C topology is smaller because
Agave still supplies validator functionality.

| Tile | Count | Ownership | Role |
| --- | --- | --- | --- |
| `net` or `sock` | configurable | Firedancer C | Network packets |
| `netlnk` | conditional | Firedancer C | Kernel route and neighbor updates for XDP |
| `quic` | configurable | Firedancer C | Solana TPU transaction ingress |
| `verify` | configurable | Firedancer C | Solana transaction signature verification |
| `dedup` | 1 | Firedancer C | Solana transaction duplicate filter |
| `pack` | 1 | Firedancer C | Leader transaction scheduler |
| `shred` | configurable | Firedancer C | Solana shred receive, transmit, and retransmit |
| `sign` | 1 | Firedancer C | Validator keyguard |
| `metric` | 1 | Firedancer C | Prometheus metrics endpoint |
| `diag` | 1 | Firedancer C | Runtime diagnostics |
| `resolh` | configurable | Agave-hosted | Address lookup resolution |
| `bank` | configurable | Agave-hosted | Scheduled transaction execution |
| `pohh` | 1 | Agave-hosted | Proof-of-history and Agave bridge |
| `store` | 1 | Agave-hosted | Blockstore bridge |
| `bundle` | optional | Firedancer C | Jito bundle client |
| `plugin` | optional | Firedancer C | Feeds validator data to the GUI |
| `gui` | optional | Firedancer C | Validator GUI HTTP endpoint |

The older fifteen-tile list in [`book/guide/tuning.md`](../../book/guide/tuning.md)
is useful historical context for this topology, but it is not the complete map
of the current full Firedancer application.

### Full Firedancer

Full Firedancer replaces the Agave-hosted validator path with native tiles.

| Group | Tiles | Notes |
| --- | --- | --- |
| Network support | `net` or `sock`, conditional `netlnk` | Added through `fd_topos_net_tiles()` |
| Runtime visibility | `metric`, `diag` | Always present |
| Bootstrap | `genesi`, `ipecho` | Genesis and shred-version bootstrap |
| Cluster traffic | `gossvf`, `gossip`, `shred`, `repair`, `txsend` | Solana cluster protocol |
| Replay and consensus | `replay`, `execrp`, `tower` | Solana fork replay, execution, and voting |
| Key handling | `sign` | Validator keyguard |
| Leader path | `quic`, `verify`, `dedup`, `resolv`, `pack`, `execle`, `poh` | Present when block production is enabled |
| Snapshot restore | `snapct`, `snapld`, `snapdc`, `snapin` | Present when snapshots are enabled |
| Optional services | `rpc`, `solcap`, `event`, `bundle`, `gui` | Enabled by configuration |

Full Firedancer also allocates Solana-specific shared objects such as `funk`,
`funk_locks`, `progcache`, `fec_sets`, `txncache`, `banks`, and `store`.
These are not tiles and should not become Tickoni's application database.

The existing `event` tile is not a Tickoni fintech ingestion tile. It exports
Solana shreds and transactions to an external event service. It should remain
an upstream-owned validator tile.

## Reuse Boundary

Tickoni should reuse stable systems substrate, not validator semantics.

### Reuse or wrap

| Foundation | Use in Tickoni |
| --- | --- |
| `src/tango` | Shared-memory queues and flow control |
| `src/util/sandbox` | Process sandboxing, namespaces, file descriptor checks, Landlock, and seccomp |
| `src/disco/topo` | Reference for process lifecycle and workspace construction; wrap only the generic parts needed by Zig |
| `src/disco/stem` | Reference for bounded polling loops and backpressure |
| `src/disco/metrics` | Reference for low-overhead per-tile metrics |
| Crash-only process model | Keep: unexpected tile failure tears down the runtime |

### Do not reuse as product tiles

Do not repurpose `event`, `dedup`, `pack`, `replay`, `sign`, `store`, `rpc`,
`gui`, or any Solana protocol tile. Their schemas, state, and security
assumptions are validator-specific.

If generic code is extracted later, place the extraction behind a narrow C ABI
under `src/tickoni/c_abi/`. Avoid adding Tickoni fields to
`src/disco/topo/fd_topo.h`, which is a likely upstream synchronization hotspot.

## Proposed Tickoni V1 Topology

Use the product tree that is now being introduced:

```text
src/app/tickoni/          Zig supervisor and CLI
src/tickoni/runtime/      Process lifecycle, topology, channels, backpressure
src/tickoni/c_abi/        Narrow wrappers around selected Firedancer C substrate
src/tickoni/schema/       Financial events, cases, capabilities, audit envelopes
src/tickoni/tiles/        Tickoni-owned tile implementations
src/tickoni/connectors/   Signed adapter manifests and connector implementations
```

`src/app/tickoni/`, `src/tickoni/runtime/`, `src/tickoni/c_abi/`, and
`src/tickoni/tiles/` already exist. `schema/` and `connectors/` should be added
only when Phase 0 and later phase work needs them.

### Runtime IDs

| Runtime ID | Logical name | Phase | Responsibility |
| --- | --- | --- | --- |
| `tkings` | `ingest_tile` | Phase 0 | Receive the configured event source, synthetic or external, validate framing, assign source offsets, and apply ingress backpressure |
| `tknorm` | `normalize_tile` | Phase 0 | Convert adapter-specific input into the canonical financial event schema |
| `tkdedu` | `dedupe_tile` | Phase 0 | Deduplicate canonical financial events by stable idempotency key and content hash |
| `tkcase` | `case_router_tile` | Phase 2 | Deterministically create or update cases and emit case lifecycle transitions |
| `tkpoly` | `policy_tile` | Phase 0 | Evaluate versioned finance-native capability policy, including destination allowlists, amount/exposure/frequency limits, and allow, deny, or require-approval decisions |
| `tkaudt` | `audit_tile` | Phase 0 | Own append-only hash-chain ordering and JSONL export |
| `tkevid` | `evidence_tile` | Phase 2 | Store and retrieve content-addressed evidence blobs |
| `tkrepl` | `replay_tile` | Phase 0 | Re-inject replay capsules with external effects disabled and report divergence |
| `tkmetr` | `metric_tile` | Phase 0 | Export Tickoni runtime metrics |
| `tkdiag` | `diag_tile` | Phase 0 | Export process, queue, and crash diagnostics |
| `tkdisp` | `agent_dispatch_tile` | Phase 1 | Schedule bounded stub agent runs by role, synthetic case, priority, and remaining budget |
| `tkagnt` | `agent_worker_tile` | Phase 1 | Run memory-isolated role agents without direct shell, unrestricted syscall, or unrestricted network access |
| `tkmodl` | `model_gateway_tile` | Phase 1 | Own model-provider or LLM-server network access, in-process GPU inference, routing, context limits, retry limits, token accounting, and spend caps. Supported providers: OpenAI, Anthropic (Claude), Qwen, DeepSeek, and a configured local/dev LLM endpoint. |
| `tktool` | `tool_broker_tile` | Phase 1 | Normalize model-native function calls and MCP requests into finance-native adapter or proposal envelopes, validate capability scope, and route approved requests to signed or stub adapters |
| `tkadpt` | `adapter_tile` | Phase 1 | Run a signed, manifest-scoped financial adapter or local stub adapter with narrowly allowed destinations, rails, accounts, venues, instruments, and network access |
| `tkapi` | `caseops_api_tile` | Phase 3 | Serve CaseOps board queries, evidence reads, approvals, and audit timeline reads |
| `tkexec` | `action_executor_tile` | Phase 4 / TigerBeetle P1 | Execute only approved, signed downstream financial mutations within destination, amount, frequency, and approval scope; own privileged accounting ledger credentials |

`tkagnt` and `tkadpt` are tile classes and may have multiple instances. Start
with one instance of each needed role or adapter and scale only after queue
metrics justify it.

### Event Flow

```text
configured event source
  -> tkings
  -> tknorm
  -> tkdedu
  -> tkpoly
  -> tkaudt

tkdisp -> tkagnt                          stub investigation, Phase 1
tkcase -> tkdisp -> tkagnt                case-scoped investigation, Phase 2+

tkagnt -> tkmodl                    model calls
tkagnt -> tktool -> tkadpt          finance-capability-scoped reads and proposals
tkapi  -> tkpoly -> tkexec          approved sensitive actions only

all boundary events -> tkaudt
Phase 2+ evidence  -> tkevid
replay capsule      -> tkrepl -> deterministic pipeline with tkexec disabled
all tile metrics    -> tkmetr
```

AI is not part of the deterministic event critical path. In Phase 2 and later,
a case can be created, audited, and replayed before an agent runs. Model
outputs and external adapter results are captured as evidence and substituted
from the capsule during forensic replay.

Financial capability semantics are owned by
[`capabilities.md`](capabilities.md). Tiles enforce that product contract:

- `tkpoly` decides whether a financial capability envelope is allowed, denied,
  approval-required, evidence-required, or escalated.
- `tktool` converts model-native function calls and MCP requests into
  finance-native requests such as `payment_retry.propose`,
  `ledger_correction.propose`, and `trading_order.propose`.
- `tkadpt` executes only adapter calls that stay inside the approved financial
  scope, such as payment rail, beneficiary, IBAN hash, wallet, broker account,
  venue, sector, instrument, amount, and frequency limits.
- `tkexec` remains disabled until approved execution phases and must never
  execute outside signed proposal, policy, approval, and destination scope.

## Existing Tile Decisions

In this table, "exclude" means do not register or link the tile in the new
Tickoni product topology. Validator-only source should be deleted after the new
runtime no longer depends on it.

| Existing tile or group | V1 decision | Tickoni replacement |
| --- | --- | --- |
| `net`, `netlnk`, `sock` | Exclude from the initial product topology. Start with a conventional sandboxed API socket; add specialized packet ingress only if benchmarks justify it. | `tkings` |
| `quic` | Exclude. TPU QUIC is Solana-specific. | `tkings` protocol adapter if ever needed |
| `verify` | Exclude. Solana signature verification is not financial adapter verification. | Manifest and envelope verification in `tktool`, `tkadpt`, and `tkexec` |
| `dedup` | Replace, do not morph. The existing tile understands Solana transaction packets. | `tkdedu` |
| `pack` | Replace, do not morph. The useful idea is bounded scheduling and backpressure, not leader packing. | `tkdisp` |
| `bank`, `execle`, `execrp` | Exclude. Solana transaction execution is unrelated to agent execution. | `tkagnt`, `tktool`, `tkexec` |
| `poh`, `pohh` | Exclude. Tickoni ordering comes from stable event offsets, deterministic IDs, and audit hashes. | `tkaudt` |
| `shred`, `gossip`, `gossvf`, `repair`, `tower`, `txsend` | Exclude. These are Solana network and consensus tiles. | None |
| `genesi`, `ipecho`, snapshot tiles | Exclude. These bootstrap and restore a Solana validator. | Tickoni config and replay capsule loading |
| `sign` | Replace, do not morph. Validator keyguard policy is not a fintech action-signing policy. | Narrow signing support owned by `tkexec`; split a `tksign` tile later if needed |
| `store`, `funk`, `progcache`, `txncache`, `banks` | Exclude. They are Solana runtime state. | Dedicated case, evidence, audit, and connector stores |
| `event` | Exclude. It is an outbound Solana telemetry exporter. | `tkings`, `tkaudt` |
| `metric`, `diag` | Reimplement with Tickoni IDs while reusing the generic metrics and sandbox substrate where practical. | `tkmetr`, `tkdiag` |
| `rpc`, `gui`, `plugin` | Exclude. The validator RPC and GUI data model do not fit CaseOps. V1 explicitly excludes an open plugin marketplace. | `tkapi` and a separate CaseOps frontend |
| `bundle` | Exclude. Jito bundles are Solana-specific. | None |
| `resolh`, `resolv` | Exclude. Solana lookup resolution is unrelated to financial entity enrichment. | Add a new `tkenty` enrichment tile only when a workflow requires it |
| `solcap` | Exclude. It captures Solana execution state. | `tkaudt`, `tkevid`, `tkrepl` |

## Tile Delivery Status

### Product boundary

Status: complete for the current boundary.

Tile-relevant facts:

1. `src/app/tickoni/` and `src/tickoni/` exist.
2. The Zig supervisor starts a Tickoni-only topology in dev/test mode.
3. Narrow C ABI declarations exist for selected queue and sandbox primitives.
4. Phase 0 still maps tiles to in-process threads and heap-backed queues.
5. The temporary `firedancer -> tickoni` compatibility behavior remains outside
   the product tile topology until the deprecation window in
   [`roadmap/stories/v1.11.md`](roadmap/stories/v1.11.md) is complete.

### Phase 0 topology

Status: complete as an in-process tile spike.

Implemented topology:

```text
tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
tkrepl
tkmetr
tkdiag
```

Implemented in
[`src/tickoni/tiles/payment_pipeline.zig`](../../src/tickoni/tiles/payment_pipeline.zig),
with supervisor wiring in
[`src/app/tickoni/supervisor.zig`](../../src/app/tickoni/supervisor.zig) and the
static topology in
[`src/tickoni/runtime/topology.zig`](../../src/tickoni/runtime/topology.zig).

Tile behaviors proven by the Phase 0 topology:

1. `tkings` owns synthetic source offsets and ingress backpressure.
2. `tknorm` owns canonical payment normalization and malformed-event rejection.
3. `tkdedu` owns idempotency and content-hash duplicate memory.
4. `tkpoly` owns allow, deny, malformed-drop, and duplicate-drop decisions.
5. `tkaudt` owns append-only audit ordering and hash chaining.
6. `tkrepl` owns deterministic replay comparison with external effects disabled.
7. `tkmetr` owns runtime metric snapshots.
8. `tkdiag` owns crash, sandbox, audit, and replay diagnostics.

The Firedancer-style topology answers for Phase 0 links are:

| Link | Owner tile | Backing allocation | Mapping mode | Depth / MTU | Reliability | Overrun, restart, shutdown | Metrics and diagnostics |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `tkings -> tknorm` | `tkings` owns source offsets and writes the link; `tknorm` owns framing rejection. | Heap-backed bounded SPSC ring in `PaymentPipelineState`; future shared-memory workspace. | Single producer writes; single consumer reads; in-process thread mapping for spike. | 64 entries / 128-byte payment envelope. | Reliable until shutdown; producer backpressures when full. | Overrun increments wait pressure instead of dropping; restart regenerates from source offset; shutdown closes the link. | Produced, invalid, max depth, backpressure waits, latency hops, crash tile. |
| `tknorm -> tkdedu` | `tknorm` owns canonical hash generation and malformed-drop decisions. | Heap-backed bounded SPSC ring in `PaymentPipelineState`; future shared-memory workspace. | Single producer writes normalized events or malformed-drop envelopes; single consumer reads. | 64 entries / 128-byte normalized event. | Reliable until shutdown. | Overrun backpressures normalization; restart recomputes stable hashes; shutdown drains then closes. | Normalized count, malformed-drop count, queue depth, waits, latency hops. |
| `tkdedu -> tkpoly` | `tkdedu` owns idempotency key and content-hash memory. | Heap-backed bounded SPSC ring plus `tkdedu`-owned seen-key arrays. | Single producer writes dedupe decisions; single consumer reads. | 64 entries / 128-byte decision input. | Reliable until shutdown. | Overrun backpressures dedupe; restart rebuilds seen-key state from source order; shutdown drains then closes. | Duplicate count, queue depth, waits, latency hops. |
| `tkpoly -> tkaudt` | `tkpoly` owns policy decision; `tkaudt` owns final ordering. | Heap-backed bounded SPSC ring in `PaymentPipelineState`; future audit workspace. | Single producer writes policy envelopes; single consumer appends. | 64 entries / 128-byte audit envelope. | Reliable until shutdown. | Overrun backpressures policy; restart re-evaluates policy version; shutdown drains then closes. | Allow, deny, duplicate-drop, audited count, queue depth, waits, latency hops. |
| `tkaudt` audit log | `tkaudt` owns append-only sequence and hash chain. | Heap-backed fixed audit record array; future append-only file or shared audit workspace. | Only `tkaudt` writes; replay reads after audit completion. | Capacity equals configured event count. | Reliable; full audit allocation is a crash condition. | Full allocation marks `tkaudt` crashed and stops the runtime; restart replays from source facts; shutdown preserves completed records in memory for replay. | Audited count, audit hash, replay divergence, latency hops, crash tile. |
| `tkrepl` replay path | `tkrepl` owns replay comparison and external-effects-disabled mode. | Reads completed audit records and regenerates deterministic synthetic events. | Replay reads audit after `tkaudt` signals completion; no producer mutates audit during compare. | Same event envelope as the main path. | Reliable comparison; reports divergence instead of mutating state. | Replay never invokes external effects; mismatch increments divergence count; shutdown exits after comparison or crash signal. | Replay checked, replay match, divergence count. |
| `tkmetr` telemetry | `tkmetr` owns metric snapshots. | Atomic counters and queue-watermark reads in `PaymentPipelineState`. | All tiles publish counters; `tkmetr` reads snapshots. | No correctness queue in the spike. | Observational; future telemetry may be lossy with counted drops. | Shutdown takes a final snapshot. | Produced, normalized, invalid, duplicates, allowed, denied, audited, depth, waits, max latency hops. |
| `tkdiag` diagnostics | `tkdiag` owns diagnostic snapshots. | Atomic crash, sandbox, audit, and replay fields in `PaymentPipelineState`. | Tiles publish diagnostics; `tkdiag` reads snapshots. | No correctness queue in the spike. | Observational; crash state is reliable. | Sandbox failure marks the owning tile crashed and requests runtime stop; shutdown takes a final snapshot. | Sandbox failures, crashed tile, audit count, replay status. |

Before the topology leaves the in-process spike, replace the heap-backed rings
with the selected shared-memory queue backing and keep these link answers
current:

1. owner tile
2. workspace or backing allocation
3. producer and consumer mapping mode
4. queue depth and MTU
5. reliable or unreliable behavior
6. overrun, restart, and shutdown behavior
7. queue, drop, latency, and crash metrics

### Future tile additions

Phase 1 adds control-plane tiles around the Phase 0 stream:

```text
tkdisp -> tkagnt -> tkmodl
tkagnt -> tktool -> tkadpt
```

Phase 2 adds deterministic case and evidence tiles:

```text
tkcase
tkevid
```

Phase 3 adds the CaseOps API tile:

```text
tkapi
```

Phase 4 may add privileged execution:

```text
tkexec
```

The product work, acceptance criteria, and delivery sequencing for those phases
live in [`roadmap/`](roadmap/) and [`phase-plan.md`](phase-plan.md). This document
only records tile identity, ownership, and topology.

## Tile Synchronization Debt

Once the new product topology is canonical:

1. Remove validator tile registrations from the Tickoni product binary.
2. Remove Tickoni-only changes from upstream-owned Firedancer files where the
   new app makes them unnecessary.
3. Delete Agave and Frankendancer code: `src/app/fdctl/`, `src/app/fddev/`, and
   `src/discoh/`.
4. Delete full Firedancer validator applications after the compatibility window:
   `src/app/firedancer/` and `src/app/firedancer-dev/`.
5. Delete Solana-only tile implementations from `src/disco/` and `src/discof/`,
   including consensus, TPU, shred, repair, replay, PoH, snapshot, validator
   RPC, validator GUI, bundle, and validator telemetry code.
6. Delete Solana runtime roots such as `src/choreo/`, `src/flamenco/`,
   `src/funk/`, `src/groove/`, `src/vinyl/`, and `src/wiredancer/` once no
   retained Tickoni substrate depends on them.
7. Keep only the dependency-proven substrate used by Tickoni, primarily
   `src/tango/`, selected `src/util/` code, and narrow wrappers around any
   retained topology, sandbox, metrics, or networking primitives.

Do not keep merging the complete Firedancer tree into the pruned product
branch. A whole-tree merge would turn upstream edits to intentionally deleted
files into modify/delete conflicts. Keep an unmodified Firedancer mirror branch
or external reference and selectively import reviewed substrate changes into
the retained Tickoni boundary.

## V1 Completion Gate

V1 has the right tile shape when:

1. The canonical `tickoni` binary starts no Solana validator tiles.
2. Every Tickoni tile has a `tk*` runtime ID and a Tickoni-owned source path.
3. Agent workers have no direct shell or unrestricted network access.
4. Model access is isolated behind `tkmodl`.
5. Tool use is isolated behind `tktool` and converted into finance-native
   adapter or proposal requests before reaching signed `tkadpt` instances.
6. Financial capabilities enforce destination allowlists, amount/exposure
   limits, frequency limits, and approval state according to
   [`capabilities.md`](capabilities.md).
7. Privileged accounting ledger posting, money movement, crypto transfer, and
   trading order placement are isolated behind disabled-by-default `tkexec`.
8. Every material event, denial, model call, adapter call, proposal, approval,
   destination/limit/frequency check, and external result is appended through
   `tkaudt`.
9. Replay can execute with external mutation disabled and report divergence.
10. Queue depth and backpressure are visible through `tkmetr`.
11. The validator mirror can be synchronized without editing Tickoni product
    tiles.
