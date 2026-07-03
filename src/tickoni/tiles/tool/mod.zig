const std = @import("std");
const adapter = @import("adapter");
const basket = @import("basket");
const portfolio = @import("portfolio");
const fixture_portfolio = @import("fixture_portfolio");
const trade_ticket = @import("trade_ticket");

pub const ToolName = enum {
    portfolio_read,
    quote_read,
    paper_order,

    pub fn fromString(s: []const u8) error{UnknownTool}!ToolName {
        return std.meta.stringToEnum(ToolName, s) orelse error.UnknownTool;
    }
};

/// Owned by value, not borrowed: ToolArgs is the tktool dispatch boundary,
/// and Basket/TradeTicket are already fixed-size, pointer-free structs, so
/// there is no reason for this to carry a caller-owned pointer.
pub const ToolArgs = union(ToolName) {
    portfolio_read: u32,
    quote_read: basket.Basket,
    paper_order: trade_ticket.TradeTicket,
};

pub fn dispatch(args: ToolArgs) adapter.AdapterRequest {
    return switch (args) {
        .portfolio_read => |account_id| normalizePortfolioRead(account_id),
        .quote_read => |*b| normalizeQuoteRead(b),
        .paper_order => |*t| normalizePaperOrder(t),
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
        .ticket = ticket.*,
    };
}

test "normalizePortfolioRead sets account and operation" {
    const req = normalizePortfolioRead(fixture_portfolio.fixtures.cash_rich.account_id);
    try std.testing.expectEqual(adapter.AdapterOperation.portfolio_snapshot, req.operation);
    try std.testing.expectEqual(fixture_portfolio.fixtures.cash_rich.account_id, req.account_id);
}

test "normalizeQuoteRead copies basket tickers and account scope" {
    var proposed_basket: basket.Basket = std.mem.zeroes(basket.Basket);
    proposed_basket.account_id = fixture_portfolio.fixtures.cash_rich.account_id;
    proposed_basket.instrument_count = 2;
    proposed_basket.instruments[0].ticker_len = 4;
    @memcpy(proposed_basket.instruments[0].ticker[0..4], "NVDA");
    proposed_basket.instruments[1].ticker_len = 4;
    @memcpy(proposed_basket.instruments[1].ticker[0..4], "SOXX");

    const req = normalizeQuoteRead(&proposed_basket);
    try std.testing.expectEqual(adapter.AdapterOperation.quote_snapshot, req.operation);
    try std.testing.expectEqual(proposed_basket.account_id, req.account_id);
    try std.testing.expectEqual(@as(u8, 2), req.ticker_count);
    try std.testing.expectEqualStrings("NVDA", std.mem.sliceTo(&req.tickers[0], 0));
    try std.testing.expectEqualStrings("SOXX", std.mem.sliceTo(&req.tickers[1], 0));
}

test "normalizePaperOrder preserves account and ticket contents" {
    var ticket: trade_ticket.TradeTicket = std.mem.zeroes(trade_ticket.TradeTicket);
    ticket.account_id = fixture_portfolio.fixtures.cash_rich.account_id;
    ticket.ticket_id_len = 9;
    @memcpy(ticket.ticket_id[0..9], "ticket-01");

    const req = normalizePaperOrder(&ticket);
    try std.testing.expectEqual(adapter.AdapterOperation.paper_order, req.operation);
    try std.testing.expectEqual(ticket.account_id, req.account_id);
    try std.testing.expect(std.meta.eql(req.ticket.?, ticket));
}

test "dispatch routes quote and paper-order tool names to adapter requests" {
    var proposed_basket: basket.Basket = std.mem.zeroes(basket.Basket);
    proposed_basket.account_id = fixture_portfolio.fixtures.cash_rich.account_id;
    proposed_basket.instrument_count = 1;
    proposed_basket.instruments[0].ticker_len = 4;
    @memcpy(proposed_basket.instruments[0].ticker[0..4], "NVDA");

    var ticket: trade_ticket.TradeTicket = std.mem.zeroes(trade_ticket.TradeTicket);
    ticket.account_id = proposed_basket.account_id;

    const quote_req = dispatch(.{ .quote_read = proposed_basket });
    const paper_req = dispatch(.{ .paper_order = ticket });

    try std.testing.expectEqual(adapter.AdapterOperation.quote_snapshot, quote_req.operation);
    try std.testing.expectEqual(adapter.AdapterOperation.paper_order, paper_req.operation);
    try std.testing.expect(std.meta.eql(paper_req.ticket.?, ticket));
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
