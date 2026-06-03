/// Tickoni supervisor: owns tile handles for one topology, starts tiles as
/// in-process threads (dev/test mode), and provides start/stop/monitor.
///
/// Production mode (spawning sandboxed child processes) is Step 2+.
const std = @import("std");
const rt = @import("runtime");
const tiles_mod = @import("tiles");

const Topology = rt.topology.Topology;
const TileHandle = rt.tile.TileHandle;
const TileState = rt.tile.TileState;
const PipelineState = tiles_mod.PipelineState;

pub const Supervisor = struct {
    allocator: std.mem.Allocator,
    topo: Topology,
    handles: []TileHandle,
    /// Heap-allocated so thread pointers remain stable across supervisor moves.
    pipeline: ?*PipelineState,

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

    /// Start all tiles in thread mode using the synthetic source/sink runners.
    /// Requires topo to be exactly the two-tile syntheticPipeline shape.
    /// event_count: how many events the source will emit before the pipeline drains.
    pub fn startSynthetic(self: *Supervisor, event_count: u64) !void {
        std.debug.assert(self.pipeline == null);
        std.debug.assert(self.topo.tiles.len == 2);

        const state = try self.allocator.create(PipelineState);
        state.* = PipelineState.init(event_count);
        self.pipeline = state;

        for (self.handles) |*h| h.state = .starting;

        self.handles[0].thread = try std.Thread.spawn(.{}, tiles_mod.runSource, .{state});
        self.handles[0].state = .running;

        self.handles[1].thread = try std.Thread.spawn(.{}, tiles_mod.runSink, .{state});
        self.handles[1].state = .running;
    }

    /// Signal all tiles to stop and join their threads.
    pub fn stop(self: *Supervisor) void {
        if (self.pipeline) |state| {
            state.stop.store(true, .release);
        }
        for (self.handles) |*h| {
            if (h.thread) |thread| {
                thread.join();
                h.thread = null;
                h.state = .stopped;
            }
        }
        if (self.pipeline) |state| {
            self.allocator.destroy(state);
            self.pipeline = null;
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
    const topo = rt.topology.syntheticPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(TileState.stopped, h.state);
    }
}

test "Supervisor starts and stops synthetic pipeline without crashes" {
    const topo = rt.topology.syntheticPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startSynthetic(200);
    sup.stop();

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(TileState.stopped, h.state);
        try std.testing.expect(!h.isAlive());
    }
}

test "Supervisor monitor returns correct tile count" {
    const topo = rt.topology.syntheticPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try std.testing.expectEqual(topo.tiles.len, sup.monitor().len);
}

test "Supervisor pipeline state is nil after stop" {
    const topo = rt.topology.syntheticPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startSynthetic(50);
    sup.stop();
    try std.testing.expect(sup.pipeline == null);
}
