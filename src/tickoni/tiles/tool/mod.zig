const std = @import("std");
const adapter = @import("adapter");
const basket = @import("basket");
const portfolio = @import("portfolio");
const portfolio_fixtures = @import("portfolio_fixtures");
const trade_ticket = @import("trade_ticket");

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
