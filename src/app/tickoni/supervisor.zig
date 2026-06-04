/// Tickoni supervisor: owns tile handles for one topology, starts Phase 0
/// tiles as in-process threads (dev/test mode), and provides
/// start/stop/monitor.
const std = @import("std");
const rt = @import("runtime");
const tiles_mod = @import("tiles");

const Topology = rt.topology.Topology;
const TileHandle = rt.tile.TileHandle;
const TileState = rt.tile.TileState;
const PaymentPipelineConfig = tiles_mod.PaymentPipelineConfig;
const PaymentPipelineState = tiles_mod.PaymentPipelineState;

pub const Supervisor = struct {
    allocator: std.mem.Allocator,
    topo: Topology,
    handles: []TileHandle,
    /// Heap-allocated so thread pointers remain stable across supervisor moves.
    pipeline: ?*PaymentPipelineState,

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

    pub fn deinit(self: *Supervisor) void {
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
        const crashed_tile = if (self.pipeline) |state| state.crashed_tile.load(.acquire) else -1;
        for (self.handles) |*h| {
            if (h.thread) |thread| {
                thread.join();
                h.thread = null;
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
