/// Tickoni supervisor: owns tile handles for one topology, starts Phase 0
/// tiles as in-process threads (dev/test mode) or, for V1.14 process mode,
/// as supervisor-managed OS processes over Tango shared memory, and
/// provides start/stop/monitor for either mode.
const std = @import("std");
const rt = @import("runtime");
const tiles_mod = @import("tiles");
const c_abi = @import("c_abi");

const Topology = rt.topology.Topology;
const TileHandle = rt.tile.TileHandle;
const TileState = rt.tile.TileState;
const CrashReason = rt.tile.CrashReason;
const PaymentPipelineConfig = tiles_mod.PaymentPipelineConfig;
const PaymentPipelineState = tiles_mod.PaymentPipelineState;

/// V1.14.S1 process-mode configuration for startPaymentPipelineProcess.
pub const ProcessPipelineConfig = struct {
    /// Directory used for per-tile launch-spec files and as FD_SHMEM_PATH
    /// for the shared Tango workspace. Caller-owned and required — no
    /// silent default, per the fail-closed environment-configuration rule.
    run_dir: []const u8,
    heartbeat_interval_ns: u64 = 20_000_000, // 20ms
    /// Test-only hook (V1.14.S1.T12 crash isolation): tile i self-exits(1)
    /// after this many heartbeats instead of waiting for a halt signal.
    /// 0 means run normally. Indexed by tile_idx.
    crash_after_heartbeats: [8]u32 = [_]u32{0} ** 8,
};

/// Supervisor-owned state for a running V1.14 process-mode pipeline.
const ProcessState = struct {
    wksp: *c_abi.wksp.Wksp,
    workspace_name: []u8,
    run_dir: []u8,
    cnc_gaddrs: [8]usize,
    /// Parent-side cnc joins, used to send the halt signal during stop.
    cncs: [8]?*c_abi.cnc.Cnc,
    children: [8]?std.process.Child,

    /// Kills any still-running children, leaves cnc joins, detaches the
    /// workspace, and frees owned buffers. Safe to call with a partially
    /// populated state (e.g. after a failed start).
    fn deinit(self: *ProcessState, io: std.Io, allocator: std.mem.Allocator) void {
        for (&self.children) |*maybe_child| {
            if (maybe_child.*) |*child| child.kill(io);
        }
        for (&self.cncs) |*maybe_cnc| {
            if (maybe_cnc.*) |cnc| _ = c_abi.cnc.fd_cnc_leave(cnc);
        }
        _ = c_abi.wksp.fd_wksp_detach(self.wksp);
        allocator.free(self.workspace_name);
        allocator.free(self.run_dir);
    }
};

pub const Supervisor = struct {
    allocator: std.mem.Allocator,
    topo: Topology,
    handles: []TileHandle,
    /// Heap-allocated so thread pointers remain stable across supervisor moves.
    pipeline: ?*PaymentPipelineState,
    /// Non-null while a V1.14 process-mode pipeline is running.
    process_state: ?*ProcessState = null,

    pub fn init(allocator: std.mem.Allocator, topo: Topology) !Supervisor {
        const handles = try allocator.alloc(TileHandle, topo.tiles.len);
        for (handles, 0..) |*h, i| h.* = TileHandle.init(@intCast(i));
        return .{
            .allocator = allocator,
            .topo = topo,
            .handles = handles,
            .pipeline = null,
        };
    }

    /// Callers that used startPaymentPipelineProcess must call stopProcess
    /// before deinit; this assert makes a forgotten teardown loud instead of
    /// leaking child processes and shared memory.
    pub fn deinit(self: *Supervisor) void {
        std.debug.assert(self.process_state == null);
        self.stop();
        self.allocator.free(self.handles);
    }

    /// Start all Phase 0 tiles in thread mode.
    ///
    /// Requires topo to be exactly the paymentPipeline shape.
    pub fn startPaymentPipeline(self: *Supervisor, config: PaymentPipelineConfig) !void {
        std.debug.assert(self.pipeline == null);
        std.debug.assert(self.topo.tiles.len == 8);

        const state = try self.allocator.create(PaymentPipelineState);
        var state_owned_by_pipeline = false;
        errdefer if (!state_owned_by_pipeline) self.allocator.destroy(state);

        state.* = try PaymentPipelineState.init(self.allocator, config);
        state_owned_by_pipeline = true;
        self.pipeline = state;
        errdefer self.stop();

        for (self.handles) |*h| h.state = .starting;

        // Dev/test lifecycle only.  The supervisor owns these thread starts;
        // tile modules must not spawn background execution owners themselves.
        self.handles[0].thread = try std.Thread.spawn(.{}, tiles_mod.runIngest, .{state});
        self.handles[0].state = .running;
        self.handles[1].thread = try std.Thread.spawn(.{}, tiles_mod.runNormalize, .{state});
        self.handles[1].state = .running;
        self.handles[2].thread = try std.Thread.spawn(.{}, tiles_mod.runDedupe, .{state});
        self.handles[2].state = .running;
        self.handles[3].thread = try std.Thread.spawn(.{}, tiles_mod.runPolicy, .{state});
        self.handles[3].state = .running;
        self.handles[4].thread = try std.Thread.spawn(.{}, tiles_mod.runAudit, .{state});
        self.handles[4].state = .running;
        self.handles[5].thread = try std.Thread.spawn(.{}, tiles_mod.runReplay, .{state});
        self.handles[5].state = .running;
        self.handles[6].thread = try std.Thread.spawn(.{}, tiles_mod.runMetric, .{state});
        self.handles[6].state = .running;
        self.handles[7].thread = try std.Thread.spawn(.{}, tiles_mod.runDiag, .{state});
        self.handles[7].state = .running;
    }

    /// Start every tile in the topology as a separate OS process connected
    /// by Firedancer Tango shared memory (V1.14.S1). Requires
    /// topo.channels to be a tango_shm topology sharing exactly one
    /// workspace (paymentPipelineProcess() builds this shape).
    pub fn startPaymentPipelineProcess(self: *Supervisor, io: std.Io, config: ProcessPipelineConfig) !void {
        std.debug.assert(self.process_state == null);
        std.debug.assert(self.topo.tiles.len == 8);
        try self.topo.validate();

        // Fail closed on any tile pinned to a CPU id this process cannot
        // actually use, before spawning anything. Pinning more exclusive
        // or shared tiles than real cores exist (or above the process's
        // own affinity mask) has driven this host unresponsive before —
        // the full CPU placement policy (declared-shared vs. undeclared
        // oversubscription diagnostics) lands in V1.14.S1 M5, but this
        // minimal available-CPU guard is required before any process-mode
        // topology with exclusive/shared placement can be started safely.
        var available_cpus: c_abi.process.CpuSet = undefined;
        try c_abi.process.getAffinity(0, &available_cpus);
        for (self.topo.tiles) |tile| {
            switch (tile.cpu_placement) {
                .exclusive, .shared => |cpu| {
                    if (!c_abi.process.isSet(&available_cpus, cpu)) return error.CpuUnavailable;
                },
                .floating => {},
            }
        }

        try c_abi.boot.bootWithSyntheticArgv(config.run_dir);


        const workspace_name_slice = self.topo.channels[0].workspace_name.slice();
        if (workspace_name_slice.len == 0) return error.MissingWorkspaceName;
        for (self.topo.channels) |ch| {
            if (ch.backing != .tango_shm) return error.ProcessModeRequiresTangoShm;
            if (!std.mem.eql(u8, ch.workspace_name.slice(), workspace_name_slice)) return error.MultipleWorkspacesNotSupported;
        }

        // Ensure run_dir and its .normal FD_SHMEM_PATH subdirectory exist;
        // fd_wksp_new_named does not create either for us.
        var run_dir_handle = try std.Io.Dir.cwd().createDirPathOpen(io, config.run_dir, .{});
        run_dir_handle.close(io);
        const normal_dir = try std.fmt.allocPrint(self.allocator, "{s}/.normal", .{config.run_dir});
        defer self.allocator.free(normal_dir);
        var normal_dir_handle = try std.Io.Dir.cwd().createDirPathOpen(io, normal_dir, .{});
        normal_dir_handle.close(io);

        var workspace_name_z_buf: [64]u8 = undefined;
        const workspace_name_z = try std.fmt.bufPrintZ(&workspace_name_z_buf, "{s}", .{workspace_name_slice});
        // Best-effort cleanup of a stale workspace left behind by a prior
        // crashed or killed supervisor; fd_wksp_new_named uses O_EXCL and
        // would otherwise fail closed forever on the same run_dir/name.
        _ = c_abi.wksp.fd_wksp_delete_named(workspace_name_z);

        var sub_page_cnt = [_]usize{256}; // 1 MiB: comfortably covers 8 small cnc allocations
        var sub_cpu_idx = [_]usize{0};
        const rc = c_abi.wksp.fd_wksp_new_named(workspace_name_z, c_abi.wksp.shmem_normal_page_sz, 1, &sub_page_cnt, &sub_cpu_idx, 0o600, 1, 0);
        if (rc != 0) return error.WkspCreateFailed;
        const wksp = c_abi.wksp.fd_wksp_attach(workspace_name_z) orelse return error.WkspAttachFailed;

        const state = try self.allocator.create(ProcessState);
        state.* = .{
            .wksp = wksp,
            .workspace_name = try self.allocator.dupe(u8, workspace_name_slice),
            .run_dir = try self.allocator.dupe(u8, config.run_dir),
            .cnc_gaddrs = [_]usize{0} ** 8,
            .cncs = [_]?*c_abi.cnc.Cnc{null} ** 8,
            .children = [_]?std.process.Child{null} ** 8,
        };
        self.process_state = state;
        errdefer {
            state.deinit(io, self.allocator);
            self.allocator.destroy(state);
            self.process_state = null;
        }

        // Pre-format one cnc per tile inside the shared workspace. The
        // supervisor is the sole creator; tile processes only join.
        for (self.topo.tiles, 0..) |_, i| {
            const footprint = c_abi.cnc.fd_cnc_footprint(64);
            const gaddr = c_abi.wksp.alloc(wksp, c_abi.cnc.cnc_align, footprint, 1);
            if (gaddr == 0) return error.CncAllocFailed;
            const laddr = c_abi.wksp.fd_wksp_laddr(wksp, gaddr) orelse return error.CncLaddrFailed;
            _ = c_abi.cnc.fd_cnc_new(laddr, 64, @intCast(i), c_abi.process.monotonicNanos()) orelse return error.CncNewFailed;
            state.cnc_gaddrs[i] = gaddr;
            state.cncs[i] = c_abi.cnc.fd_cnc_join(laddr) orelse return error.CncJoinFailed;
        }

        var self_exe_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const self_exe_path = try c_abi.process.selfExePath(&self_exe_path_buf);

        for (self.handles, 0..) |*h, i| {
            const tile = self.topo.tiles[i];
            const spec = try rt.launch_spec.LaunchSpec.init(.{
                .tile_idx = @intCast(i),
                .tile_id = tile.id,
                .cpu_placement = tile.cpu_placement,
                .workspace_name = self.topo.channels[0].workspace_name,
                .cnc_gaddr = state.cnc_gaddrs[i],
                .shmem_path = config.run_dir,
                .heartbeat_interval_ns = config.heartbeat_interval_ns,
                .crash_after_heartbeats = config.crash_after_heartbeats[i],
            });
            const spec_path = try std.fmt.allocPrint(self.allocator, "{s}/tile_{d}.spec", .{ config.run_dir, i });
            defer self.allocator.free(spec_path);
            try spec.writeToFile(io, std.Io.Dir.cwd(), spec_path);

            // Minimal explicit child environment: the tile reads its
            // shmem path from the launch spec via --shmem-path (see
            // c_abi/boot.zig), not from an inherited environment,
            // matching the least-privilege posture used elsewhere in the
            // runtime (no inherited PATH, secrets, or parent env state).
            var env = std.process.Environ.Map.init(self.allocator);
            defer env.deinit();

            const child = try std.process.spawn(io, .{
                .argv = &.{ self_exe_path, "__tile-run", spec_path },
                .environ_map = &env,
            });

            h.pid = child.id;
            h.cpu_placement = tile.cpu_placement;
            h.state = .running;
            state.children[i] = child;

            switch (tile.cpu_placement) {
                .exclusive, .shared => |cpu| {
                    var cpu_set: c_abi.process.CpuSet = undefined;
                    c_abi.process.zero(&cpu_set);
                    c_abi.process.set(&cpu_set, cpu);
                    try c_abi.process.setAffinity(@intCast(child.id.?), &cpu_set);
                },
                .floating => {},
            }
        }
    }

    /// Blocks until every spawned tile process exits (without requesting an
    /// early halt) and records final state/exit_code/crashed_because.
    /// Leaves process_state intact; pairs with the thread-mode wait().
    pub fn waitProcess(self: *Supervisor, io: std.Io) void {
        const state = self.process_state orelse return;
        for (&state.children, 0..) |*maybe_child, i| {
            var child = maybe_child.* orelse continue;
            const term = child.wait(io) catch {
                self.handles[i].state = .crashed;
                self.handles[i].crashed_because = .exit_code;
                maybe_child.* = null;
                continue;
            };
            switch (term) {
                .exited => |code| {
                    if (code == 0) {
                        self.handles[i].state = .stopped;
                    } else {
                        self.handles[i].state = .crashed;
                        self.handles[i].exit_code = code;
                        self.handles[i].crashed_because = .exit_code;
                    }
                },
                .signal, .stopped, .unknown => {
                    self.handles[i].state = .crashed;
                    self.handles[i].crashed_because = .exit_code;
                },
            }
            maybe_child.* = null;
        }
    }

    /// Signals every tile to halt via its cnc (crash-only shutdown, not a
    /// POSIX signal — matches fd_cnc's own command/control model), waits
    /// for exit, and fully tears down the shared workspace. Sibling tiles
    /// are not touched by one tile's crash; this only requests a clean
    /// stop of tiles that are still running.
    pub fn stopProcess(self: *Supervisor, io: std.Io) void {
        const state = self.process_state orelse return;
        for (state.cncs) |maybe_cnc| {
            if (maybe_cnc) |cnc| c_abi.cnc.signal(cnc, c_abi.cnc.signal_halt);
        }
        self.waitProcess(io);
        state.deinit(io, self.allocator);
        self.allocator.destroy(state);
        self.process_state = null;
    }

    /// Join all tile threads without requesting early shutdown.  The Phase 0
    /// pipeline closes links as producers finish, so this waits for a complete
    /// deterministic run unless a tile has already requested stop.
    pub fn wait(self: *Supervisor) void {
        self.joinThreads();
    }

    /// Signal all tiles to stop and join their threads.
    pub fn stop(self: *Supervisor) void {
        if (self.pipeline) |state| {
            state.requestStop();
        }
        self.joinThreads();
        if (self.pipeline) |state| {
            state.deinit();
            self.allocator.destroy(state);
            self.pipeline = null;
        }
    }

    fn joinThreads(self: *Supervisor) void {
        for (self.handles) |*h| {
            if (h.thread) |thread| {
                thread.join();
                h.thread = null;
                // Read after join so the release-store in the tile thread is visible.
                const crashed_tile = if (self.pipeline) |state| state.crashed_tile.load(.acquire) else -1;
                if (crashed_tile >= 0 and @as(i32, @intCast(h.tile_idx)) == crashed_tile) {
                    h.state = .crashed;
                    h.exit_code = 1;
                } else {
                    h.state = .stopped;
                }
            }
        }
    }

    /// Returns the current handle slice — a read-only snapshot of tile states.
    pub fn monitor(self: *const Supervisor) []const TileHandle {
        return self.handles;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Supervisor initialises all handles as stopped" {
    const topo = rt.topology.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(TileState.stopped, h.state);
    }
}

test "Supervisor starts and stops Phase 0 pipeline without crashes" {
    const topo = rt.topology.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipeline(.{ .event_count = 16, .queue_depth = 4 });
    sup.wait();

    const state = sup.pipeline.?;
    const metrics = state.snapshotMetrics();
    try std.testing.expectEqual(@as(u64, 16), metrics.produced);
    try std.testing.expectEqual(@as(u64, 16), metrics.audited);
    try std.testing.expectEqual(@as(u64, 1), metrics.duplicates);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expect(metrics.max_queue_depth <= 4);
    try std.testing.expectEqual(@as(u64, 5), metrics.max_latency_hops);
    try std.testing.expect(state.replay_checked.load(.seq_cst));
    try std.testing.expect(state.replay_match.load(.seq_cst));
    try std.testing.expect(state.external_effects_disabled.load(.seq_cst));

    sup.stop();

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(TileState.stopped, h.state);
        try std.testing.expect(!h.isAlive());
    }
}

test "Supervisor monitor returns correct tile count" {
    const topo = rt.topology.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try std.testing.expectEqual(topo.tiles.len, sup.monitor().len);
}

test "Supervisor pipeline state is nil after stop" {
    const topo = rt.topology.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipeline(.{ .event_count = 50, .queue_depth = 8 });
    sup.wait();
    sup.stop();
    try std.testing.expect(sup.pipeline == null);
}

test "Supervisor marks tkings crashed on sandbox failure" {
    const topo = rt.topology.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipeline(.{ .event_count = 20, .queue_depth = 4, .sandbox_fail_at = 2 });
    sup.wait();
    sup.stop();
    try std.testing.expectEqual(TileState.crashed, sup.monitor()[0].state);
    try std.testing.expectEqual(@as(u8, 1), sup.monitor()[0].exit_code);
}
