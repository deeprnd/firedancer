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

## 8. Make `tile_process` own live heartbeat and halt handling

**Files:** `src/tickoni/runtime/tile_process.zig`, `src/app/tickoni/tile_main.zig`, `src/tickoni/tiles/payment_pipeline/process.zig`

**Task:** Refactor process-mode tile work so the generic lifecycle keeps
heartbeating and checking for HALT while tile work is still running. The
current `run()` path heartbeats once, signals `RUN`, calls `work`
synchronously, and only heartbeats again after `work` returns. That makes a
long-running or blocked tile look dead even when it is alive, and pushes halt
responsiveness into tile-specific loops instead of the generic process
lifecycle.

**Done when:**

- [ ] A process-mode tile continues to advance CNC heartbeats while its work is
      still in progress.
- [ ] HALT handling for normal tile execution is owned by the generic
      `tile_process` lifecycle instead of requiring each tile implementation to
      poll for it independently.
- [ ] Tests cover a long-running or multi-step tile work path and prove the
      tile remains heartbeating until it halts or finishes.

## 9. Make the BOOT-to-RUN transition halt-safe

**Files:** `src/tickoni/runtime/tile_process.zig`, `src/app/tickoni/supervisor.zig`, `src/tickoni/test/integration/test_process_topology.zig`

**Task:** Remove the documented boot-time stop race in process mode. Today a
supervisor HALT sent during child boot can be clobbered by the child's
unconditional `RUN` signal. The lifecycle should preserve a supervisor stop
request sent during boot instead of relying on caller timing to avoid the race.

**Done when:**

- [ ] `tile_process.run()` no longer blindly overwrites a pre-existing HALT
      with `RUN`.
- [ ] A boot-time supervisor stop request causes the child to exit cleanly
      instead of entering normal work and waiting on upstream progress.
- [ ] Process-mode test coverage reproduces the race and proves it is fixed.

## 10. Make CPU placement validation ownership explicit

**Files:** `src/tickoni/runtime/topology.zig`, `src/tickoni/runtime/cpu_placement.zig`, `src/tickoni/runtime/tile.zig`, `src/tickoni/test/integration/test_process_cpu_placement.zig`

**Task:** Consolidate CPU placement validation behind one explicit runtime
boundary. Static placement conflicts, host-aware availability checks, and
effective placement storage are split across different modules with overlapping
ownership. Refactor the API so callers can tell whether they are performing
structural-only validation or full fail-closed runtime validation.

**Done when:**

- [ ] The public API makes the difference between structural placement
      validation and host-aware placement validation explicit.
- [ ] Malformed and unavailable CPU ids fail through the documented owner path,
      not by call-order convention.
- [ ] Tests cover duplicate placement conflicts, malformed ids, and
      unavailable ids through the intended validation entrypoints.

## 11. Fail closed on unsupported multi-link process topologies

**Files:** `src/tickoni/runtime/launch_spec.zig`, `src/app/tickoni/supervisor.zig`, `src/app/tickoni/tile_main.zig`, `src/tickoni/test/integration/test_process_topology.zig`

**Task:** Align the process-mode launch contract with the generic topology
graph. `Topology` allows arbitrary channel graphs, but `LaunchSpec` currently
has only one `input_link` and one `output_link`, and supervisor selection is
effectively last-match-wins. Replace that silent truncation with explicit
validation for the supported cardinality, or deliberately extend the launch
contract if process mode must support fan-in or fan-out now.

**Done when:**

- [ ] Process-mode startup does not silently discard extra input or output
      links for a tile.
- [ ] Unsupported fan-in or fan-out fails with a clear error before any child
      process is spawned, unless the launch contract is deliberately extended
      to represent multiple links.
- [ ] Tests cover at least one multi-input or multi-output topology and assert
      the chosen behavior.

## 12. Type tile-plan phases end to end

**Files:** `src/tickoni/runtime/tile.zig`, `src/tickoni/runtime/topology.zig`, `src/app/tickoni/topologies.zig`, `src/tickoni/test/integration/test_process_cpu_placement.zig`, `src/tickoni/test/integration/test_process_demo_parity.zig`

**Task:** Replace raw integer phase values in the generic runtime descriptor
and product topology definitions with a dedicated enum for the documented tile
plan phases (`core`, `case`, `agent`, `api`, `exec`). This removes the current
integer drift risk between topology declarations and the documented tile plan.

**Done when:**

- [ ] `TileDescriptor.phase` is a named enum rather than a raw `u8`.
- [ ] Product topology definitions and related tests assign named phases
      instead of raw integers.
- [ ] Validation or tests fail if a topology attempts to encode an unknown
      phase value.

## 13. Align crash-reason reporting with implemented supervisor checks

**Files:** `src/tickoni/runtime/tile.zig`, `src/app/tickoni/supervisor.zig`, `src/tickoni/test/integration/test_process_topology.zig`

**Task:** Align the generic crash taxonomy with the supervisor behavior that
actually exists. `CrashReason.cnc_fail` is part of the public runtime status
model, but the current process-mode supervisor only classifies exit-code and
signal-style failures. Either wire CNC signal or heartbeat failure into the
implemented monitoring path, or remove/de-scope the unused crash reason until
that detection exists.

**Done when:**

- [ ] Every retained `CrashReason` value can be produced by an implemented
      supervisor path.
- [ ] The code clearly documents whether CNC signal or heartbeat failure is
      classified today or intentionally deferred.
- [ ] Tests cover each retained crash classification that process mode can
      emit.

## 14. Define one runtime hash-boundary contract

**Files:** `src/tickoni/tiles/case/mod.zig`, `src/tickoni/schema/consumer_money/drift.zig`, `src/tickoni/tiles/replay/mod.zig`, `src/tickoni/tiles/model/backend.zig`, `src/tickoni/tiles/model/run.zig`, `src/tickoni/tiles/payment_pipeline/runtime.zig`, `src/tickoni/schema/consumer_money/thesis.zig`, `src/tickoni/schema/consumer_money/basket.zig`, `src/tickoni/codec/audit/hash.zig`

**Task:** Define and apply an explicit hash-boundary rule for runtime-facing
stable identifiers, replay lookup keys, proposal/result hashes, and local-only
lightweight hashes. The codebase currently mixes Firedancer-backed SipHash,
Wyhash, and ad hoc byte mixing without a clear contract for when each is
allowed. Move stable runtime identifiers to the shared boundary unless a
different primitive is explicitly justified.

**Done when:**

- [ ] Runtime-facing hash sites either use the shared Firedancer-backed hash
      boundary or clearly justify a different primitive for that use case in
      code comments or module docs.
- [ ] The codebase has one obvious source of truth for canonical hashes,
      replay lookup hashes, proposal/result hashes, and lightweight local/test
      hashes.
- [ ] `deriveSyntheticRunId()` and any retained stable runtime hash helper use
      explicit domain/version constants instead of unexplained local hash
      choices.
- [ ] Tests prove the chosen runtime hash derivations stay deterministic and
      change only when the intended inputs change.
