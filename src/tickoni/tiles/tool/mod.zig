const std = @import("std");
const adapter = @import("adapter");
const basket = @import("basket");
const portfolio = @import("portfolio");
const portfolio_fixtures = @import("portfolio_fixtures");
const trade_ticket = @import("trade_ticket");

pub const ToolName = enum {
    portfolio_read,
    quote_read,
    paper_order,

    pub fn fromString(s: []const u8) error{UnknownTool}!ToolName {
        return std.meta.stringToEnum(ToolName, s) orelse error.UnknownTool;
    }
};

pub const ToolArgs = union(ToolName) {
    portfolio_read: u32,
    quote_read: *const basket.Basket,
    paper_order: *const trade_ticket.TradeTicket,
};

pub fn dispatch(args: ToolArgs) adapter.AdapterRequest {
    return switch (args) {
        .portfolio_read => |account_id| normalizePortfolioRead(account_id),
        .quote_read => |b| normalizeQuoteRead(b),
        .paper_order => |t| normalizePaperOrder(t),
    };
}

pub fn normalizePortfolioRead(account_id: u32) adapter.AdapterRequest {
    return .{
        .operation = .portfolio_snapshot,
        .account_id = account_id,
    };
}

pub fn normalizeQuoteRead(proposed_basket: *const basket.Basket) adapter.AdapterRequest {
    var req = adapter.AdapterRequest{
        .operation = .quote_snapshot,
        .account_id = proposed_basket.account_id,
        .ticker_count = proposed_basket.instrument_count,
    };
    for (proposed_basket.instruments[0..proposed_basket.instrument_count], 0..) |instrument, i| {
        @memcpy(req.tickers[i][0..instrument.ticker_len], instrument.tickerSlice());
    }
    return req;
}

pub fn normalizePaperOrder(ticket: *const trade_ticket.TradeTicket) adapter.AdapterRequest {
    return .{
        .operation = .paper_order,
        .account_id = ticket.account_id,
        .ticket = ticket,
    };
}

test "normalizePortfolioRead sets account and operation" {
    const req = normalizePortfolioRead(portfolio_fixtures.fixtures.cash_rich.account_id);
    try std.testing.expectEqual(adapter.AdapterOperation.portfolio_snapshot, req.operation);
    try std.testing.expectEqual(portfolio_fixtures.fixtures.cash_rich.account_id, req.account_id);
}

test "ToolName.fromString accepts known tools" {
    try std.testing.expectEqual(ToolName.portfolio_read, try ToolName.fromString("portfolio_read"));
    try std.testing.expectEqual(ToolName.quote_read, try ToolName.fromString("quote_read"));
    try std.testing.expectEqual(ToolName.paper_order, try ToolName.fromString("paper_order"));
}

test "ToolName.fromString rejects unknown tool names" {
    try std.testing.expectError(error.UnknownTool, ToolName.fromString("unknown_tool"));
    try std.testing.expectError(error.UnknownTool, ToolName.fromString(""));
    try std.testing.expectError(error.UnknownTool, ToolName.fromString("PORTFOLIO_READ"));
}
