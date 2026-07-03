# Tickoni Tile Orchestration

## Decision

Tickoni uses a Tickoni-owned tile orchestration boundary with a
Firedancer-backed Linux full-runtime implementation.

The public orchestration model is Tickoni-owned:

- Tickoni tile ids and roles
- Tickoni topology descriptors and link contracts
- Tickoni support tiers
- Tickoni capability, audit, replay, evidence, model, tool, adapter, and
  execution contracts
- Tickoni runtime diagnostics and operator-facing status

The Linux full-runtime implementation should reuse Firedancer orchestration
semantics through an adapter instead of rebuilding a parallel harness. The
adapter may map Tickoni runtime descriptors to the Firedancer topology/run
surface internally, but product code must not depend on Firedancer validator
topology types, Solana tile kinds, validator config stages, validator metrics,
or validator schemas.

For macOS and Windows retail runtimes, the same Tickoni orchestration boundary
applies. The implementation may use portable substitutes or fail-closed
unsupported operations. Native retail builds must not assume that
`libfd_tango.a`, `libfd_util.a`, or `libfd_ballet.a` compile, link, or export
the same symbols as the Linux build. Target-specific `c_abi` implementations
select the correct behavior at compile/link time, not only at runtime.

## Scope

This document describes how tile orchestration is meant to work at the
architecture boundary.

It owns launch lifecycle, Firedancer harness adapter semantics, runtime-tier
implementation boundaries, registry responsibility, link discovery,
health/staleness behavior, shutdown behavior, and crash visibility.

It does not own the canonical list of Tickoni tile IDs, product event flow, or
reuse/exclude decisions for validator tiles. Those are owned by
[`tile-topology.md`](tile-topology.md).

It does not decide product policy, financial capability semantics, audit
schema, replay capsule format, model-provider behavior, adapter authority, or
execution approval rules. Those remain owned by the relevant Tickoni product
and schema documents.

It also does not evaluate alternatives. The option analysis lives in:

- `doc/knowledge/rant/firedancer-orchestration-reuse.md`
- `doc/knowledge/rant/static-inline-and-ffi.md`

## Core Model

Tickoni has one orchestration contract with multiple implementation tiers:

```text
Tickoni product topology
  tile ids, roles, link descriptors, placement, support tier
        |
        v
Tickoni orchestration boundary
  registry, callbacks, lifecycle, link discovery, diagnostics contract
        |
        +--> Linux full runtime
        |     Firedancer-backed adapter
        |     real process isolation, real Firedancer shared memory,
        |     real sandbox/metrics/lifecycle semantics where supported
        |
        +--> macOS / Windows retail runtime
              portable or reduced-isolation implementation,
              deterministic paper/sandbox demos, visible degraded guarantees,
              fail-closed unsupported live effects
```

The boundary is stable. The implementation behind it is selected by target and
runtime tier.

## Firedancer Orchestration Mechanics

Firedancer's useful orchestration machinery is not a single primitive. It is a
stack of conventions and guardrails:

1. A topology describes tiles, workspaces, links, per-tile input link arrays,
   per-tile output link arrays, metrics storage, CPU placement, memory
   footprint, and sandbox-relevant details.
2. A tile run descriptor provides callbacks and resource policy:
   footprint/alignment, privileged init, unprivileged init, run callback,
   allowed file descriptors, seccomp policy, file/address-space/process
   limits, and shutdown rules.
3. The runner joins tile workspaces, runs privileged init, enters sandbox,
   fills link pointers from topology, registers metrics, runs unprivileged
   init, calls the tile run loop, and checks shutdown expectations when the
   run callback returns.
4. The stem pattern provides the hot-loop discipline used by many Firedancer
   tiles: loop-top shutdown check, periodic housekeeping, credit/backpressure
   handling, input polling, fragment processing, output publication, and
   heartbeat/metric visibility.
5. The supervisor path owns process/thread launch, child tracking, crash
   visibility, and crash-only shutdown behavior.

The Firedancer shape to preserve is the semantics of that lifecycle:

```text
tile selected from topology
  -> join required workspaces
  -> privileged_init
  -> enter sandbox
  -> fill/join input and output links
  -> register metrics or equivalent health surface
  -> unprivileged_init
  -> run tile loop
  -> enforce shutdown/exit expectations
```

The Linux full-runtime adapter must preserve the ordering, guard intent, and
failure behavior of these steps unless an explicit Tickoni substitute is
documented and tested.

## What Tickoni Reuses

Tickoni reuses Firedancer infrastructure in two forms.

### Linux Full Runtime

The Linux full-runtime tier reuses Firedancer orchestration as deeply as the
Tickoni boundary allows:

- topology construction via `fd_topob.c` (the real Firedancer topology builder)
- workspace creation and join via `fd_wksp_*`
- link filling for `mcache`, `dcache`, `fseq`, and related state
- sandbox entry and allowed-fd/seccomp discipline where supported
- metrics registration or equivalent per-tile health visibility
- process/thread launch semantics where the selected Linux mode uses them
- crash and shutdown semantics
- stem-loop guard patterns for shutdown, housekeeping, credit, and heartbeat
- per-tile CPU placement via `fd_topo_cpus_init()` +
  `fd_topob_auto_layout_cpus()` with Tickoni name arrays in priority slots

The adapter should follow Firedancer harness hooks, guards, ordering, and
failure semantics. If Tickoni replaces one of those pieces, the replacement
must preserve the same orchestration guarantee at the Tickoni boundary.

### Topology Builder Adapter

`fd_topob.c` is the real Firedancer topology builder — it is NOT Solana-shaped.
Tickoni calls it directly rather than maintaining a parallel builder. The adapter
pattern is:

1. **Build the topology:** `fd_topob_new(topo, "tickoni")` — allocates and
   `memset`-zeros the entire `fd_topo_t`, zeroing every field including Solana
   union fields (xdp, sock, gossip, quic, etc.).

2. **Create workspaces:** `fd_topob_wksp(topo, name, footprint, ...)` for each
   workspace (tickoni_wksp, metrics_wksp, etc.).

3. **Create links:** `fd_topob_link(topo, name, ...)` for each inter-tile link.

4. **Create tiles:** `fd_topob_tile(topo, name, wksp, metrics_wksp, cpu_idx,
   is_agave, uses_id_keyswitch, uses_av_keyswitch)` for each Tile — with
   **`0` for all three Solana flags**:
   - `is_agave=0` — Tickoni does not run in Agave/single-process mode
   - `uses_id_keyswitch=0` — no validator identity key rotation
   - `uses_av_keyswitch=0` — no validator authority key rotation

5. **Wire links:** `fd_topob_tile_in(topo, tile_idx, link_idx, ...)` and
   `fd_topob_tile_out()` to attach each link to its tile.

6. **Validate:** `fd_topob_finish(topo)` runs structural validation (free check,
   link connectivity, workspace coverage) — pure generic, no Solana dependency.

7. **CPU placement:** `fd_topo_cpus_init()` → `fd_topob_auto_layout_cpus()`
   assigns each tile to a CPU core using priority phase arrays. The 4 arrays
   (`CRITICAL_TILES[]`, `ALWAYS[]`, `STARTUP[]`, `FLOATING[]`) are the only
   Solana-specific part — they contain hardcoded tile name strings matched
   against `fd_topo_tile_t.name` via `strcmp`. Tickoni replaces these arrays
   with Tickoni tile names:

   ```c
   // Patched in fd_topob.c — CRITICAL (no HT sharing)
   static char const * CRITICAL_TILES[] = {
     "pack", "poh", "pohh", "gui", "guih",
     "tkings", "tknorm",
     NULL
   };

   // Patched — ALWAYS (continuous pipeline)
   static char const * ALWAYS[] = {
     "backt", "benchg", "net", "sock", "quic", "bundle",
     "verify", "dedup", "pack", "sign", "shred", "pktgen",
     "tkdedu", "tkpoly", "tkaudt",
     NULL
   };

   // Patched — FLOATING (monitoring, kernel-scheduled)
   static char const * FLOATING[] = {
     "netlnk", "metric", "diag", "bencho",
     "tkmetr", "tkdiag", "tkdisp",
     NULL
   };
   ```

   The algorithm (`fd_topo_cpus_init` → `auto_tile_cpu` → `auto_layout_cpus`)
   is fully generic: NUMA-aware core scanning, hyperthread-pair exclusion for
   latency-sensitive tiles, 4-phase priority ordering, and "floating" fallback
   for unmatched tiles (logged as warning, left to kernel scheduler). Only the
   name strings change.

8. **Launch:** Pass `topo` and `topo->tiles[]` to `fd_topo_run_tile()` — the
   harness joins workspaces, fills link pointers, enters sandbox, runs the tile,
   and checks shutdown state.

**Why `0` for Solana flags is safe:** `fd_topob_new()` does `memset(topo, 0)`,
so all Solana union fields in `fd_topo_t` are already zero. The launch path
(`fd_topo_run_tile` in `fd_topo_run.c` lines 49–140) reads only `name`,
`kind_id`, `cpu_idx`, `allow_shutdown`, and `metrics` — none are Solana union
fields. `fd_topo_run_single_process()` reads `is_agave` (lines 326, 335) but
Tickoni uses per-process `execve` mode, not single-process mode.

**Keyswitch objects (the 3 params):** Each keyswitch is a 128-byte shared memory
object with a state machine: `SWITCH_PENDING` → tile reads new bytes →
`COMPLETED` or `FAILED`. While Solana uses these for validator identity/authority
key rotation, the mechanism is generic and can be repurposed for Tickoni:
GCP/GCS OAuth tokens, AWS credential rotation, LLM provider API keys, or
adapter secrets stored in `bytes[64]`. For Phase 0 tiles that need no runtime
auth rotation, pass `0` and no keyswitch object is allocated.

**What changes in upstream `fd_topob.c`:** Only the 4 name arrays get Tickoni
tile names appended. No logic changes, no new functions, no struct modifications.
The file set is tracked by `engine-check-changes` to catch any upstream drift.

### C ABI Substrate

Tickoni-owned Zig code crosses into Firedancer or vendored C only through
Tickoni-owned `tk_*` shims and Zig wrappers under `src/tickoni/c_abi/**`.

Current and expected substrate categories include:

- Tango queues and control state:
  `mcache`, `dcache`, `fseq`, `cnc`, and, where justified, `fctl` and `tempo`
- workspace and shared-memory mechanics
- sandbox primitives on Linux
- low-level metrics/diagnostics mechanics or patterns
- Ballet protobuf/hash primitives and vendored JSON where Tickoni deliberately
  reuses them

The C ABI is not a place for financial policy, product topology, capability
rules, adapter authority, or audit/replay semantics.

### Patterns

Tickoni also reuses Firedancer orchestration patterns even where the exact C
implementation is not used:

- topology owns graph cardinality
- tile registry is the single answer for what a tile id does
- input and output links are arrays, not one-off fields
- shutdown is checked inside tile work, not only outside it
- heartbeat and health are updated during work/housekeeping
- reliable links backpressure or fail closed instead of silently dropping
- crash-only behavior keeps failure handling explicit
- operator diagnostics must identify which tile, workspace, link, and process
  is unhealthy

## What Tickoni Owns

Tickoni owns all product and framework semantics above the generic engine
layer.

### Tile Identity

Tickoni tile identities are product topology concepts, not aliases for
validator tiles. The canonical tile ID list and tile responsibility table live
in [`tile-topology.md`](tile-topology.md). This document uses those IDs only to
describe orchestration behavior.

### Topology And Links

Tickoni topology owns:

- which Tickoni tiles exist in a product topology
- tile instance ids and logical names
- channel direction
- channel backing
- depth, MTU, reliability, and overrun behavior
- workspace ownership
- input and output link cardinality
- CPU placement policy at the Tickoni support tier

Topology is the graph. Bootstrap records are not the graph.

Process boot may carry identity and minimal startup data, but the topology is
the source of truth for link cardinality and link ownership. Fan-in and fan-out
are represented as per-tile link arrays:

```text
tile
  in_cnt
  in_link_id[]
  out_cnt
  out_link_id[]
```

A single-link launch field is not a valid long-term representation of Tickoni
topology. It can exist only as a compatibility lane for a topology that is
explicitly validated as linear.

### Registry

The tile registry is the single product-facing answer to:

- this tile id's logical name
- supported runtime tiers
- thread/dev run callback, if any
- Linux full-runtime run callback or adapter entry, if any
- process/retail run callback, if any
- expected link cardinality
- counter/metric schema
- diagnostics naming

No supervisor, process dispatcher, metrics reader, or test harness should
recreate tile identity mappings independently.

### Financial Correctness

Tickoni owns the financial correctness layer:

- capability envelopes
- policy outcomes
- destination, account, rail, venue, market, sector, instrument, amount,
  exposure, frequency, holding-period, environment, and approval dimensions
- audit records and hash chaining
- evidence references
- replay substitution
- model/tool/adapter routing
- approved execution authority

These contracts must not be represented as Firedancer topology fields.

## Linux Full-Runtime Adapter Contract

The Linux full-runtime adapter is allowed to know about Firedancer topology and
run types. It is the only layer that may translate from Tickoni descriptors to
Firedancer-compatible structures.

The adapter owns:

- mapping Tickoni topology into the minimal Firedancer topology/run surface
  required by the reused harness code
- mapping Tickoni tile registry entries into Firedancer-style tile run
  descriptors
- mapping Tickoni link descriptors into Firedancer link arrays and link
  backing objects
- mapping Tickoni placement policy into supported Linux placement behavior
- preserving Firedancer lifecycle ordering and failure semantics
- reporting adapter-private failures through Tickoni diagnostics

The adapter does not own:

- financial event schemas
- policy semantics
- audit schemas
- replay capsule semantics
- model/tool/adapter authority
- operator approval behavior
- public product topology vocabulary

If the adapter needs fake or unrelated validator values to satisfy Firedancer
structures, those values are adapter-private compatibility fields. They must
not become Tickoni product concepts.

## Retail Runtime Contract

macOS and Windows retail runtimes implement the same Tickoni orchestration
boundary but are not expected to provide Linux-equivalent engine guarantees.

Retail runtimes may support:

- deterministic paper/sandbox demos
- policy decisions over fixtures
- audit JSONL output
- replay proof
- CaseOps review of supported demo artifacts
- mocked, fixture-backed, or replay-substituted model/tool/adapter effects

Retail runtimes must fail closed for unsupported behavior:

- live trading
- live payment or transfer execution
- TigerBeetle writes
- direct model-provider bypass
- direct adapter bypass
- privileged execution
- unsupported sandbox or isolation claims

Target-specific bridges decide at compile/link time whether a `tk_*` symbol is:

- Linux-Firedancer
- portable-Firedancer
- Tickoni substitute
- unsupported/fail-closed
- decision-needed

Runtime checks remain necessary for operator diagnostics, but they are not
sufficient when a Firedancer symbol cannot compile or link on the target.

## Health, Shutdown, And Crash Semantics

Every runtime tier must expose enough health information to answer:

- which tile is running, halted, failed, or stale
- which process/thread owns that tile
- which workspace or allocation backs its state
- which links it consumes and produces
- which heartbeat or health timestamp is advancing
- whether shutdown was requested and observed
- whether a failure was crash-only, clean halt, unsupported tier, or startup
  validation failure

Linux full-runtime tiles should preserve Firedancer-style lifecycle behavior:

- heartbeat or equivalent health state advances during work
- shutdown is checked inside tile loops and waits
- reliable consumers/producers do not block forever without a visible stale
  health state
- one tile crash is visible to the supervisor
- crash-only policy tears down or marks the topology according to the selected
  support-tier semantics

Retail runtimes must expose degraded guarantees explicitly. If they cannot
provide process isolation, namespace sandboxing, CPU pinning, or shared-memory
equivalence, the missing guarantee is part of the runtime tier and must be
visible in diagnostics and evidence.

## Orchestration Drift Guard

The Linux adapter depends on Firedancer harness behavior staying understood.
Tickoni should maintain a watched Firedancer harness file set and a repo gate
that detects changes relative to the previous commit. The intended command is:

```text
just engine-check-changes
```

That gate belongs in `just tests-all` once implemented. It should force human
review or explicit acknowledgement when watched harness files change.

The initial watched set is:

- `src/disco/topo/fd_topo_run.c`
- `src/disco/topo/fd_topo.h`
- `src/disco/topo/fd_topo.c`
- `src/disco/stem/fd_stem.c`
- `src/app/shared/commands/run/run.c`
- `src/app/shared/commands/run/run1.c`
- `src/app/shared/boot/fd_boot.c`
- `src/util/sandbox/fd_sandbox.c`
- `src/util/sandbox/fd_sandbox.h`
- `src/util/sandbox/fd_sandbox_private.h`
- `src/disco/metrics/fd_metrics.c`
- `src/disco/metrics/fd_metrics.h`
- `src/disco/metrics/fd_metrics_base.h`

The list is conservative and may be refined when the Linux adapter's exact
dependency surface is known. The guard does not freeze Firedancer. It prevents
silent drift in orchestration semantics Tickoni relies on.

## Non-Negotiable Boundaries

- Do not rename or repurpose Solana validator tiles as Tickoni tiles.
- Do not add Tickoni product fields to upstream Firedancer topology structs.
- Do not encode financial policy or approval behavior in orchestration
  bootstrap state.
- Do not treat Markdown, DuckDB, TigerBeetle, model providers, or financial
  adapters as direct dependencies of the orchestration layer.
- Do not let agents, UI, model tiles, tool brokers, adapters, or future
  execution paths bypass `tkpoly`, `tkaudt`, and replay boundaries.
- Do not claim macOS or Windows Linux-equivalent isolation, performance, or
  shared-memory behavior without explicit support-tier evidence.

## Summary

Tickoni's orchestration architecture is a boundary decision:

```text
Tickoni owns the product topology and financial semantics.
Firedancer powers the Linux full-runtime implementation where reusable.
Retail runtimes implement the same Tickoni boundary with explicit guarantees.
```

The architecture should make it hard to accidentally rebuild Firedancer in
parallel, and equally hard to let Firedancer validator semantics leak into
Tickoni's financial product model.
