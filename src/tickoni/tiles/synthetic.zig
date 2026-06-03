/// Synthetic two-tile pipeline for supervisor lifecycle testing.
///
/// Replaces tango mcache with a plain atomic counter so the pipeline can run
/// in-process without hugetlbfs or shared-memory setup. This is not a
/// production tile — it exists only to prove supervisor start/stop/monitor.
const std = @import("std");

/// Shared state wired between the source and sink tiles by the supervisor.
pub const PipelineState = struct {
    /// Total events the source will emit before exiting.
    target: u64,
    /// Events emitted by the source (producer side).
    produced: std.atomic.Value(u64),
    /// Events consumed by the sink (consumer side).
    consumed: std.atomic.Value(u64),
    /// Set to true by the supervisor to request early shutdown.
    stop: std.atomic.Value(bool),

    pub fn init(target: u64) PipelineState {
        return .{
            .target = target,
            .produced = std.atomic.Value(u64).init(0),
            .consumed = std.atomic.Value(u64).init(0),
            .stop = std.atomic.Value(bool).init(false),
        };
    }
};

/// Emits exactly target events then exits. Exits early if stop is set.
pub fn runSource(state: *PipelineState) void {
    var emitted: u64 = 0;
    while (emitted < state.target) {
        if (state.stop.load(.acquire)) break;
        _ = state.produced.fetchAdd(1, .release);
        emitted += 1;
        std.Thread.yield() catch {};
    }
}

/// Drains all produced events then exits. Exits early if stop is set.
pub fn runSink(state: *PipelineState) void {
    while (true) {
        if (state.stop.load(.acquire)) break;
        const produced = state.produced.load(.acquire);
        const consumed = state.consumed.load(.monotonic);
        if (consumed >= produced) {
            if (produced >= state.target) break;
            std.Thread.yield() catch {};
            continue;
        }
        _ = state.consumed.fetchAdd(1, .release);
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "runSource emits exactly target events" {
    var state = PipelineState.init(100);
    runSource(&state);
    try std.testing.expectEqual(@as(u64, 100), state.produced.load(.seq_cst));
}

test "stop flag halts source before target" {
    var state = PipelineState.init(1_000_000);
    state.stop.store(true, .release);
    runSource(&state);
    try std.testing.expect(state.produced.load(.seq_cst) < 1_000_000);
}

test "concurrent pipeline: produced and consumed reach target" {
    var state = PipelineState.init(500);
    const src = try std.Thread.spawn(.{}, runSource, .{&state});
    const snk = try std.Thread.spawn(.{}, runSink, .{&state});
    src.join();
    snk.join();
    try std.testing.expectEqual(state.target, state.produced.load(.seq_cst));
    try std.testing.expectEqual(state.target, state.consumed.load(.seq_cst));
}
