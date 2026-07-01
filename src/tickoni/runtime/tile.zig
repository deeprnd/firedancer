const std = @import("std");
const topology = @import("topology.zig");

pub const TileState = enum {
    stopped,
    starting,
    running,
    stopping,
    /// Tile exited with a non-zero status; topology is unhealthy.
    crashed,
};

/// Identifies why a tile transitioned to .crashed, for supervisor
/// diagnostics and crash-isolation tests (V1.14.S1.T12).
pub const CrashReason = enum {
    none,
    /// Process exited with a non-zero status (or thread-mode equivalent).
    exit_code,
    /// The tile's cnc object reached FD_CNC_SIGNAL_FAIL or stopped
    /// heartbeating (process mode only).
    cnc_fail,
    /// Process was terminated by a signal (e.g. SIGKILL), process mode
    /// only. Distinct from exit_code because the tile never got to exit
    /// on its own terms — a forced-kill/OOM-style death rather than a
    /// self-detected failure.
    signal,
};

/// Runtime handle for one tile managed by the supervisor.
pub const TileHandle = struct {
    tile_idx: u32,
    state: TileState,
    /// Non-null when the tile runs as an in-process thread (test/dev mode).
    thread: ?std.Thread,
    /// Meaningful only when state == .crashed.
    exit_code: u8,
    /// Non-null when the tile runs as a supervisor-managed OS process
    /// (V1.14 process mode).
    pid: ?std.process.Child.Id = null,
    /// Effective CPU placement for this tile, copied from the topology at
    /// start time so diagnostics do not need to re-consult the topology.
    cpu_placement: topology.CpuPlacement = .floating,
    /// Meaningful only when state == .crashed.
    crashed_because: CrashReason = .none,

    pub fn init(idx: u32) TileHandle {
        return .{ .tile_idx = idx, .state = .stopped, .thread = null, .exit_code = 0 };
    }

    pub fn isAlive(self: TileHandle) bool {
        return switch (self.state) {
            .starting, .running, .stopping => true,
            .stopped, .crashed => false,
        };
    }
};

test "TileHandle initialises in stopped state" {
    const h = TileHandle.init(0);
    try std.testing.expectEqual(TileState.stopped, h.state);
    try std.testing.expectEqual(@as(u32, 0), h.tile_idx);
    try std.testing.expect(!h.isAlive());
}

test "TileHandle isAlive is true for running" {
    var h = TileHandle.init(1);
    h.state = .running;
    try std.testing.expect(h.isAlive());
}

test "TileHandle isAlive is true for starting and stopping" {
    var h = TileHandle.init(2);
    h.state = .starting;
    try std.testing.expect(h.isAlive());
    h.state = .stopping;
    try std.testing.expect(h.isAlive());
}

test "TileHandle isAlive is false for crashed" {
    var h = TileHandle.init(3);
    h.state = .crashed;
    try std.testing.expect(!h.isAlive());
}
