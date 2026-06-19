const std = @import("std");

/// One bounded investment work item dispatched to the agent worker.
/// In the implementation this is an in-process deterministic dispatch.
pub const WorkItem = struct {
    run_id: u64,
    account_id: u32,
    target_notional_cents: i64,
};

/// Dispatches exactly one investment work item.
pub fn dispatchInvestmentRun(
    run_id: u64,
    account_id: u32,
    target_notional_cents: i64,
) WorkItem {
    return .{
        .run_id = run_id,
        .account_id = account_id,
        .target_notional_cents = target_notional_cents,
    };
}

test "dispatchInvestmentRun sets all work item fields" {
    const item = dispatchInvestmentRun(42, 2001, 200_000);
    try std.testing.expectEqual(@as(u64, 42), item.run_id);
    try std.testing.expectEqual(@as(u32, 2001), item.account_id);
    try std.testing.expectEqual(@as(i64, 200_000), item.target_notional_cents);
}
