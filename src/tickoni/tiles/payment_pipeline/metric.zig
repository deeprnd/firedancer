/// tkmetr: polls and snapshots pipeline throughput/backpressure metrics
/// until tkrepl finishes its check, then takes one final snapshot.
const std = @import("std");
const runtime = @import("runtime.zig");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runMetric(state: *PaymentPipelineState) void {
    while (!state.replay_checked.load(.acquire) and !state.stop.load(.acquire)) {
        _ = state.snapshotMetrics();
        _ = state.metric_snapshots.fetchAdd(1, .release);
        std.Thread.yield() catch {};
    }
    _ = state.snapshotMetrics();
    _ = state.metric_snapshots.fetchAdd(1, .release);
}
