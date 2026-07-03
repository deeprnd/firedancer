SWEPT REFACTORING PLAN: Reuse Firedancer Harness for Tickoni Defences
    
    Three Audit Findings, Three Layers of Fix
    
    Audit 8 — stuck/blocked tiles, no heartbeat during work()
    Audit 7-20-24 — tile identity duplicated in 4 places, no single source of truth
    Audit 11-23 — single-link cardinality, last-match-wins, domain bleed into generic spec
    
    The overarching principle from all three audits is the same: Tickoni built its own abstractions that duplicate what Firedancer already does, without reusing the infrastructure primitives it already wraps. Firedancer's harness is Solana-shaped at the topology-builder layer, but its primitives (mcache/dcache/fseq/cnc/wksp/stem/sandbox) are Solana-free. The c_abi bridge already exposes those primitives. The plan is to stop reinventing and start reusing.
    
    
    
    LAYER 1: Tile Lifecycle Defences (Audit 8)
    
    Problem: work() in tile_process.zig:80 runs synchronously. No heartbeat, no halt check mid-execution. If a tile blocks in consume()/publish(), the supervisor sees stale heartbeats and the tile is indistinguishable from dead.
    
    Firedancer does this (3 layers):
    - Layer 1: Process isolation — each tile is a child process. If it dies, supervisor kills the rest. Tickoni already does this via supervisor-managed child processes.
    - Layer 2: SHOULD_SHUTDOWN callback — checked at the top of every stem loop iteration. Tile defines the check; stem checks it every cycle.
    - Layer 3: Metrics-based health — FD_MGAUGE_SET writes heartbeat timestamp every housekeeping interval. Supervisor monitors this in a loop.
    
    What Tickoni must build:
    
    1. Move heartbeat inside work(): Instead of one heartbeat before work() and one per loop iteration after work() returns, the work() function itself needs to emit periodic heartbeats. This means the WorkFn signature changes from *const fn(work, spec, cnc, alloc) anyerror!void to accept a heartbeat callback or the work function calls c_abi.cnc.heartbeat() directly in its own loop.
    
    2. Add a SHOULD_SHUTDOWN analog: Firecancer's stem loop checks STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) at the top of every iteration. Tickoni tiles should check halted(cnc) at the top of their own inner loops, not just between iterations. This is per-tile but the pattern must be documented and enforced.
    
    3. Add tempo/fctl to the c_abi bridge: Firedancer's fd_tempo.c handles timing/housekeeping, and fd_fctl.c handles credit-based backpressure. Neither is currently in c_abi. These are Solana-free infrastructure — add tk_tempo_* and tk_fctl_* shims so tiles can:
       - Check how long since last heartbeat (tempo)
       - Apply credit-based backpressure instead of blocking (fctl)
    
    4. Supervisor metrics timeout: The supervisor's snapshotProcessMetrics() currently reads counters but doesn't detect stale heartbeats. Add a timeout check: if a tile's fd_cnc_heartbeat_query() timestamp hasn't advanced beyond N heartbeats, mark it as potentially stuck. This is the external boundary Firedancer's ready.c uses.

Firedancer primitives to reuse through c_abi:
    - fd_cnc_heartbeat_query() — already wrapped, just use more aggressively
    - fd_tempo_* — new shim needed
    - fd_fctl_* — new shim needed
    - fd_metrics_tile pattern — reference for per-tile metrics, don't copy validator names
    
    
    
    LAYER 2: Tile Registry (Audit 7-20-24)
    
    Problem: Tile identity → capabilities is independently computed in 4 places:
    - supervisor.zig:134-148 — thread-mode spawn (index-based: handles[0] = runIngest)
    - supervisor.zig:372-393 — metrics snapshot (string-based: if id == "tkings")
    - tile_main.zig:34-73 — process-mode dispatch (string-based if/else)
    - process.zig — counter indices (index 0 = produced/normalized/duplicates/allowed/audited depending on tile)
    
    Firedancer does this: One null-terminated TILES[] array + one dispatcher function fdctl_tile_run(). Every consumer calls it. Each tile owns its own fd_tile_* struct defining its name, footprint, callbacks, seccomp, fds.
    
    What Tickoni must build:
    
    1. Create src/app/tickoni/tile_registry.zig with:
       - TileEntry struct: { id: TileId, name: []const u8, run_fn: fn(PaymentPipelineState) anyerror!void, process_fn: ?fn(...) anyerror!void, counter_schema: [8]struct { idx, name }, counter_count: usize }
       - TileRegistry with findById(), findByIdx(), validate(topo)
       - Init function registering all 8 Phase 0 tiles
    
    2. Replace supervisor thread-mode spawn: handles[0] = spawn(runIngest) becomes a loop: for (handles, 0..) |*h, i| { const entry = registry.findByIdx(i); h.thread = spawn(.{}, entry.run_fn, .{state}); }
    
    3. Replace supervisor metrics snapshot: snapshotProcessMetrics iterates entry.counter_schema instead of string matching. Reads counter index from schema, maps to snapshot field by name.
    
    4. Replace tile_main.zig dispatch: if (id == "tkings") becomes const entry = registry.findById(spec.tile_id); entry.process_fn(...).
    
    5. Compile-time validation: registry.validate(topo) asserts every topology tile is registered and every registered tile exists in the topology.
    
    Firedancer primitives to reuse:
    - The TILES[] + fdctl_tile_run() pattern — exact same structure
    - Per-tile struct ownership — each tile module registers its own entry
    - Position-indexed metrics via topology position (Firedancer avoids the string-matching problem by using topo->tiles[tile_idx].metrics)

LAYER 3: Topology-Driven Link Model (Audit 11-23)
    
    Problem A: LaunchSpec carries exactly one input_link and one output_link. Current topologies are linear chains so this works today. Any fan-in (e.g., tkaudt receiving from tkings AND tkpoly) would silently lose all but one link because the channel-selection loop (supervisor.zig:262-265) is last-match-wins.
    
    Problem B: LaunchSpec mixes generic runtime bootstrap (tile_idx, cpu_placement, workspace_name, cnc_gaddr) with payment-pipeline test config (event_count, policy_limit_cents, inject_duplicate, inject_malformed).
    
    Firedancer has no LaunchSpec. It passes the full topology pointer to the tile's run callback. The tile reads its own section from the shared topology: in_cnt + in_link_id[] arrays, out_cnt + out_link_id[] arrays. The topology owns the graph; the tile discovers its links at boot time from shmem.

    The right move is to kill the serialized handoff and adopt the topology-driven model:
    
    - Build a Tickoni-owned topology struct in the workspace (finance-oriented, not fd_topo_t). It carries the tile graph: tile descriptors, channel definitions, and per-tile link arrays (in_cnt + in_link_id[], out_cnt + out_link_id[]).
    - Supervisor writes the topology into shared memory at boot (same workspace as cnc/mcache/dcache/fseq triplets).
    - Tile execs, joins workspace, reads its own topo section from shmem, discovers its links from the topology arrays, joins each link handle.
    - Whatever replaces LaunchSpec carries only identity/heartbeat params (tile_id, cpu_placement, heartbeat_interval_ns). No links, no payment fields.
    
    This single change simultaneously fixes:
    - Multi-link: topology carries in_cnt + in_link_id[] arrays, not single fields
    - Last-match-wins: topology declares cardinality explicitly (no iterative loop)
    - Hybrid payload: topology carries links, bootstrap carries identity, they're separate data structures
    - Domain bleed: payment config stays in ProcessConfig, not the bootstrap record
    
    LAYER 4: c_abi Bridge Expansion
    
    Currently c_abi wraps: wksp, mcache/dcache/fseq/cnc (via tango shim), sandbox. Missing but necessary for the above fixes:
    
    1. Add `tk_tempo_*` shim over src/tango/tempo/fd_tempo.c:
       - tk_tempo_new(), tk_tempo_join(), tk_tempo_query()
       - Provides timing/housekeeping intervals for heartbeat throttling
    
    2. Add `tk_fctl_*` shim over src/tango/fctl/fd_fctl.c:
       - tk_fctl_new(), tk_fctl_join(), tk_fctl_consume_credit(), tk_fctl_produce_credit()
       - Credit-based flow control for tiles that need non-blocking publish/consume
    
    3. Add `tk_metrics_*` shim over src/disco/metrics/fd_metrics.c:
       - tk_metrics_register(), tk_metrics_tile()
       - Per-tile metrics access for supervisor health monitoring
    
    4. Verify existing shims are Solana-free: firedancer.h currently only wraps siphash, protobuf, and JSON primitives. The tango.c shim wraps mcache/dcache/fseq/cnc. Neither embeds Solana semantics. Good.
    
    
    
    EXECUTION ORDER (Dependencies)
    
    Phase 1 — Registry (unblocks everything)
    - Create tile_registry.zig with all 8 Phase 0 tiles
    - Replace tile_main.zig dispatch (simplest win — removes 40 lines of if/else)
    - Replace supervisor thread-mode spawn (loop over registry)
    - Add registry.validate(topo) and test it
    
    Phase 2 — Metrics (follows registry)
    - Replace snapshotProcessMetrics string matching with counter_schema iteration
    - Add heartbeat staleness detection to supervisor
    - Test with existing integration tests (behavioral contract unchanged)
    
    Phase 3 — c_abi bridge expansion
    - Add tempo, fctl, metrics shims
    - Add tempo/fctl/Zig bindings in c_abi module
    - Build and link against Firedancer infrastructure
    
    Phase 4 — Topology-driven link model (replaces LaunchSpec for links)
    - Build Tickoni-owned topology struct in shmem: tile descriptors, channel definitions, per-tile link arrays (in_cnt + in_link_id[], out_cnt + out_link_id[])
    - Supervisor writes topology into workspace at boot alongside cnc/mcache/dcache/fseq
    - Tile execs, joins workspace, reads its own topo section from shmem, discovers links from topology arrays
    - LaunchSpec retains only identity/heartbeat params; payment/test config moves to ProcessConfig
    - Fix channel-selection loop by removing it (topology declares cardinality explicitly, no iteration needed)
    - Update all tile join code to iterate topology link arrays instead of LaunchSpec fields
    - Update launch_spec.zig tests to reflect trimmed spec
    
    Phase 5 — Stuck-tile defense (depends on tempo/fctl + registry)
    - Add heartbeat callback inside WorkFn
    - Document SHOULD_SHUTDOWN pattern for tile authors
    - Add supervisor-level heartbeat timeout detection
    - Add integration test: force a tile to block, verify supervisor detects staleness
    
    
    
    WHAT NOT TO REUSE (per all three audits)
    
    - fd_topob.c topology builder — Solana-shaped (Agave core pinning, Solana tile kinds). Build a Tickoni-owned topology builder.
    - fd_stem.c stem loop — wrong abstraction for Tickoni tiles (designed for Solana's multi-input multiplexer, not single-input financial pipelines). Use Tickoni's own loops with the SHOULD_SHUTDOWN pattern.
    - Firedancer supervisor (run.c) — tightly coupled to fdctl, fd_topo_t, PID namespace, clone(). Keep Tickoni's self-exec supervisor.
    - Firedancer metrics names/schemas — per-Solana-tile generated names. Use Tickoni-owned counter names.
    - clone(CLONE_NEWPID) — Linux-specific. Keep Tickoni's execve model.
    
    BOTTOM LINE
    
    The Firedancer primitives in src/tango/ (mcache, dcache, fseq, cnc, fctl, tempo) and src/util/sandbox/ are Solana-free infrastructure. The c_abi bridge already wraps some of them. The refactoring plan is:
    
    1. Reuse the primitives through c_abi (add missing shims)
    2. Reuse Firedancer's patterns (TILES[] registry, multi-link arrays, SHOULD_SHUTDOWN at loop top, position-indexed metrics)
    3. Keep Tickoni's own orchestration (tile_process.zig runner, supervisor, self-exec model)
    
    This gives Tickoni Firedancer's defensive infrastructure without the Solana-shaped topology builder, stem loop, or supervisor coupling that the audits identified as blockers.
