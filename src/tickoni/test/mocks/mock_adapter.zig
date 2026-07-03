const std = @import("std");
const portfolio = @import("portfolio");
const fixture_portfolio = @import("fixture_portfolio");
const trade_ticket = @import("trade_ticket");
const schema = @import("adapter_messages");

pub const MockBackend = struct {
    pub const CallTrace = struct {
        portfolio_snapshot_calls: usize = 0,
        quote_snapshot_calls: usize = 0,
        paper_order_calls: usize = 0,
        last_account_id: u32 = 0,
        last_ticket: ?trade_ticket.TradeTicket = null,
    };

    portfolio_snapshot: ?portfolio.BrokerageAccount = null,
    quote_snapshot: ?trade_ticket.QuoteSnapshot = null,
    paper_order: ?trade_ticket.PaperExecutionResult = null,
    trace: ?*CallTrace = null,

    pub fn call(self: MockBackend, req: schema.AdapterRequest) error{MissingMockResponse}!schema.AdapterResult {
        if (self.trace) |trace| {
            trace.last_account_id = req.account_id;
            trace.last_ticket = req.ticket;
            switch (req.operation) {
                .portfolio_snapshot => trace.portfolio_snapshot_calls += 1,
                .quote_snapshot => trace.quote_snapshot_calls += 1,
                .paper_order => trace.paper_order_calls += 1,
            }
        }
        return switch (req.operation) {
            .portfolio_snapshot => .{
                .portfolio_snapshot = self.portfolio_snapshot orelse return error.MissingMockResponse,
            },
            .quote_snapshot => .{
                .quote_snapshot = self.quote_snapshot orelse return error.MissingMockResponse,
            },
            .paper_order => .{
                .paper_order = self.paper_order orelse return error.MissingMockResponse,
            },
        };
    }

    /// Builds `BackendType` (production tiles' adapter.Backend vtable
    /// interface) from this mock, via BackendType's own `from()`
    /// constructor. Generic over BackendType instead of importing adapter's
    /// Backend type directly, so this test double never pulls a specific
    /// production module instance into its own module graph.
    pub fn asBackend(comptime BackendType: type, self: *MockBackend) BackendType {
        return BackendType.from(MockBackend, true, self);
    }
};

test "MockBackend returns configured response for requested operation" {
    const expected = fixture_portfolio.fixtures.cash_rich;
    const result = try (MockBackend{
        .portfolio_snapshot = expected,
    }).call(.{
        .operation = .portfolio_snapshot,
        .account_id = expected.account_id,
    });

    const snapshot = switch (result) {
        .portfolio_snapshot => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(expected.account_id, snapshot.account_id);
}

test "MockBackend traces adapter operation calls" {
    var trace = MockBackend.CallTrace{};
    const expected = fixture_portfolio.fixtures.cash_rich;
    _ = try (MockBackend{
        .portfolio_snapshot = expected,
        .trace = &trace,
    }).call(.{
        .operation = .portfolio_snapshot,
        .account_id = expected.account_id,
    });

    try std.testing.expectEqual(@as(usize, 1), trace.portfolio_snapshot_calls);
    try std.testing.expectEqual(@as(usize, 0), trace.quote_snapshot_calls);
    try std.testing.expectEqual(@as(usize, 0), trace.paper_order_calls);
    try std.testing.expectEqual(expected.account_id, trace.last_account_id);
}
