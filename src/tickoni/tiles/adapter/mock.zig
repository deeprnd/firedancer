const std = @import("std");
const portfolio = @import("portfolio");
const portfolio_fixtures = @import("portfolio_fixtures");
const trade_ticket = @import("trade_ticket");
const schema = @import("schema.zig");

pub const MockBackend = struct {
    portfolio_snapshot: ?portfolio.BrokerageAccount = null,
    quote_snapshot: ?trade_ticket.QuoteSnapshot = null,
    paper_order: ?trade_ticket.PaperExecutionResult = null,

    pub fn call(self: MockBackend, req: schema.AdapterRequest) error{MissingMockResponse}!schema.AdapterResult {
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
};

test "MockBackend returns configured response for requested operation" {
    const expected = portfolio_fixtures.fixtures.cash_rich;
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
