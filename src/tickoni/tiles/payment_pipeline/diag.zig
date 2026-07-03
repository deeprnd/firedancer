/// tkdiag: polls and snapshots pipeline crash/sandbox-failure diagnostics
/// until tkrepl finishes its check, then takes one final snapshot.
const std = @import("std");
const runtime = @import("runtime.zig");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runDiag(state: *PaymentPipelineState) void {
    while (!state.replay_checked.load(.acquire) and !state.stop.load(.acquire)) {
        _ = state.snapshotDiag();
        _ = state.diag_snapshots.fetchAdd(1, .release);
        std.Thread.yield() catch {};
    }
    _ = state.snapshotDiag();
    _ = state.diag_snapshots.fetchAdd(1, .release);
}
