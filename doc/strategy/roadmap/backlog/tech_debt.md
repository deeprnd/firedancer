# Tech Debt Tasks

Readable backlog for small cleanup work in the Tickoni runtime and supervisor.

## 1. Extract sandbox defaults into named constants

**Files:** `src/tickoni/runtime/sandbox.zig`

**Task:** Replace hardcoded sandbox defaults such as `65534`, `64`, `1 << 30`,
and `1 << 28` with named constants. If there are standard sizes the runtime
will reuse, define them once and reference them from `SandboxConfig` and tests.

**Done when:**

- `SandboxConfig` defaults use shared constant names.
- Tests assert against the shared constants instead of repeating literals.

## 2. Replace numeric tile phases with an enum

**Files:** `src/tickoni/runtime/topology.zig`

**Task:** Replace `TileDescriptor.phase: u8` with a dedicated enum for the tile
plan phases (`core`, `case`, `agent`, `api`, `exec`) so the topology is typed
and self-explanatory.

**Done when:**

- `TileDescriptor.phase` is an enum, not a raw integer.
- Comments no longer need to explain what `0..4` means.

## 3. Stop repeating raw tile-id strings in topology tests

**Files:** `src/tickoni/runtime/topology.zig`

**Task:** Update tests like `TileId equality` to use shared tile-id constants
instead of repeating `"tknorm"` and `"tkdedu"` string literals inline.

**Done when:**

- Topology tests use shared constants or helpers for known tile ids.
- The same tile id is not duplicated as raw text in multiple assertions.

## 4. Use shared constants for sandbox limit tests

**Files:** `src/tickoni/runtime/sandbox.zig`

**Task:** The test for minimum address-space limits should reference named size
constants instead of open-coded shifts like `1 << 28`.

**Done when:**

- Memory-size tests use shared constants.
- The file has one clear source of truth for sandbox size defaults.

## 5. Rework the busy-wait sleep in shared-memory consumer loops

**Files:** `src/tickoni/runtime/shm_link.zig`,
`src/tango/mcache/fd_mcache.h`, `src/disco/stem/fd_stem.c`

**Task:** Review `Consumer.consume()` and related loops that call
`process.sleepNanos(100_000)` while polling for data. Compare the implementation
against Firedancer's fragment-consumer path before changing it.

Firedancer's hot shared-memory receive path does not use a fixed nanosleep for
normal mcache polling. `FD_MCACHE_WAIT` in `src/tango/mcache/fd_mcache.h` polls
up to `poll_max`, uses `FD_SPIN_PAUSE()` between polls, and times out so the
run loop can do housekeeping. `src/disco/stem/fd_stem.c` similarly polls input
mcaches and uses `FD_SPIN_PAUSE()` when backpressured. Sleep/yield behavior
does exist elsewhere, such as `fd_cnc_wait()` for OS-friendly command/control
waiting, but that is not the hot fragment-consumer pattern.

Replace the Tickoni fixed sleep with a deliberate wait strategy that follows
the Firedancer pattern where appropriate: bounded polling, spin pause or a
Tickoni wrapper around it, explicit housekeeping/stop checks, and measured
backpressure/idle counters.

**Done when:**

- The consumer loop no longer relies on an unexplained fixed sleep.
- The code or task notes cite the Firedancer behavior that the Tickoni loop is
  intentionally following or intentionally not following.
- The chosen wait behavior is documented in code comments or tests.

## 6. Reuse Firedancer-backed workspace constants where appropriate

**Files:** `src/tickoni/c_abi/wksp.zig`

**Task:** Review `shmem_normal_page_sz: usize = 4096` and use the shared
Firedancer value if the runtime is meant to follow the same workspace page-size
contract. Keep a local constant only if there is a clear boundary reason.

**Done when:**

- The page-size value comes from the correct shared source of truth, or
- The file documents why Tickoni intentionally keeps its own constant.

## 7. Remove payment-pipeline knowledge from the generic supervisor

**Files:** `src/app/tickoni/supervisor.zig`

**Task:** Replace hardcoded tile-id dispatch in `snapshotProcessMetrics()` and
the named payment-pipeline thread spawning in `startPaymentPipeline()` with a
registry-driven approach. The supervisor should stay generic; payment-specific
field names and tile behavior should live in payment-pipeline code, not in the
generic process supervisor.

**Done when:**

- Supervisor logic does not branch on tile ids with `if/else` chains.
- Tile startup and metric collection are driven by a registry or descriptor
  table.
- Payment-specific metrics/config are moved out of generic supervisor types.


# To process

High: [tile_process.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/tile_process.zig:69) does not actually own the live tile lifecycle during work. It heartbeats once, signals `RUN`, runs `work` synchronously, then only heartbeats after `work` returns. Long-running or blocked tile work will look non-heartbeating even though the tile is alive, and halt handling is delegated into tile-specific code instead of the generic process lifecycle.

- High: [tile_process.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/tile_process.zig:70) documents a real stop race instead of fixing it. A supervisor HALT sent during boot can be clobbered by the child’s unconditional `RUN` signal at line 78. That makes shutdown correctness depend on caller timing, which is the opposite of clear lifecycle ownership.

- Medium: CPU placement ownership is split across modules. [topology.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/topology.zig:28) defines `CpuPlacement`, [topology.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/topology.zig:116) validates placement conflicts, [cpu_placement.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/cpu_placement.zig:41) re-validates topology plus host availability, and [tile.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/tile.zig:42) imports topology just to store effective placement. This makes `Topology.validate()` look sufficient even though malformed/unavailable CPU IDs only fail through `cpu_placement.validate()`.

- Medium: `Topology` allows a general graph, but process launch currently supports only one input and one output link per tile. [topology.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/topology.zig:80) models channels generally, while `LaunchSpec` has single `input_link`/`output_link` slots and supervisor selection is effectively last-match-wins. That is fragile for anything beyond the current linear payment chain.

- Medium: [topology.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/topology.zig:63) embeds product roadmap phase semantics as a raw `u8` in the generic runtime schema. It is already easy to drift: product topology definitions assign phases by integer elsewhere, with no enum or validation tying them to documented tile ownership.

- Low: [tile.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/tile.zig:15) declares `CrashReason.cnc_fail`, but the current supervisor path only records exit/signal style failures. The status model promises CNC heartbeat failure classification that is not implemented, so diagnostics ownership is aspirational.
