const std = @import("std");
const basket = @import("basket");
const portfolio = @import("portfolio");
const trade_ticket = @import("trade_ticket");

pub const AdapterOperation = enum(u8) {
    portfolio_snapshot,
    quote_snapshot,
    paper_order,
};

pub const AdapterRequest = struct {
    operation: AdapterOperation,
    account_id: u32 = 0,
    tickers: [basket.max_basket_instruments][portfolio.max_ticker_len]u8 = std.mem.zeroes([basket.max_basket_instruments][portfolio.max_ticker_len]u8),
    ticker_count: u8 = 0,
    ticket: ?*const trade_ticket.TradeTicket = null,
};

pub const AdapterResult = union(AdapterOperation) {
    portfolio_snapshot: portfolio.BrokerageAccount,
    quote_snapshot: trade_ticket.QuoteSnapshot,
    paper_order: trade_ticket.PaperExecutionResult,
};

pub const FixtureAdapterError = error{
    UnknownAccount,
    UnsupportedTicker,
    MissingTicket,
    PolicyBlocked,
};

fn quoteForTicker(ticker: []const u8) ?trade_ticket.Quote {
    const Quote = trade_ticket.Quote;
    const quotes = [_]Quote{
        .{ .ticker = tickerBuf("NVDA"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 12_495, .ask_cents = 12_500, .last_cents = 12_498 },
        .{ .ticker = tickerBuf("AMD"), .ticker_len = 3, .venue = .nasdaq, .bid_cents = 15_990, .ask_cents = 16_000, .last_cents = 15_995 },
        .{ .ticker = tickerBuf("AVGO"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 24_990, .ask_cents = 25_000, .last_cents = 24_995 },
        .{ .ticker = tickerBuf("MSFT"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 49_990, .ask_cents = 50_000, .last_cents = 49_995 },
        .{ .ticker = tickerBuf("AMZN"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 19_990, .ask_cents = 20_000, .last_cents = 19_995 },
        .{ .ticker = tickerBuf("BOTZ"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 2_995, .ask_cents = 3_000, .last_cents = 2_998 },
        .{ .ticker = tickerBuf("SOXX"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 24_990, .ask_cents = 25_000, .last_cents = 24_995 },
    };
    for (quotes) |quote| {
        if (std.mem.eql(u8, quote.tickerSlice(), ticker)) return quote;
    }
    return null;
}

fn tickerBuf(comptime s: []const u8) [portfolio.max_ticker_len]u8 {
    var buf = [_]u8{0} ** portfolio.max_ticker_len;
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

pub const FixtureAdapter = struct {
    pub fn call(_: FixtureAdapter, req: AdapterRequest) FixtureAdapterError!AdapterResult {
        return switch (req.operation) {
            .portfolio_snapshot => blk: {
                if (req.account_id != portfolio.fixtures.cash_rich.account_id) {
                    return error.UnknownAccount;
                }
                break :blk .{ .portfolio_snapshot = portfolio.fixtures.cash_rich };
            },
            .quote_snapshot => blk: {
                var snapshot: trade_ticket.QuoteSnapshot = std.mem.zeroes(trade_ticket.QuoteSnapshot);
                snapshot.as_of_ns = 1_765_792_800_000_000_000;
                snapshot.quote_count = req.ticker_count;
                for (req.tickers[0..req.ticker_count], 0..) |ticker_buf, i| {
                    const ticker = std.mem.sliceTo(&ticker_buf, 0);
                    snapshot.quotes[i] = quoteForTicker(ticker) orelse return error.UnsupportedTicker;
                }
                break :blk .{ .quote_snapshot = snapshot };
            },
            .paper_order => blk: {
                const ticket = req.ticket orelse return error.MissingTicket;
                if (ticket.policy_outcome != .allow) return error.PolicyBlocked;
                var result: trade_ticket.PaperExecutionResult = std.mem.zeroes(trade_ticket.PaperExecutionResult);
                result.paper_order_id_len = @intCast("paper_order_v1_1_ai_infra_2000_0001".len);
                @memcpy(result.paper_order_id[0..result.paper_order_id_len], "paper_order_v1_1_ai_infra_2000_0001");
                result.ticket_id_len = ticket.ticket_id_len;
                @memcpy(result.ticket_id[0..ticket.ticket_id_len], ticket.ticket_id[0..ticket.ticket_id_len]);
                result.account_id = ticket.account_id;
                result.status = .filled;
                result.fill_count = ticket.line_item_count;
                var total_filled: i64 = 0;
                for (ticket.line_items[0..ticket.line_item_count], 0..) |item, i| {
                    result.fills[i].ticker = item.ticker;
                    result.fills[i].ticker_len = item.ticker_len;
                    result.fills[i].quantity_micros = item.quantity_micros;
                    result.fills[i].fill_price_cents = item.price_cents;
                    result.fills[i].filled_notional_cents = item.line_notional_cents;
                    total_filled += item.line_notional_cents;
                }
                result.total_filled_cents = total_filled;
                result.resulting_account_snapshot = .{
                    .cash_cents = portfolio.fixtures.cash_rich.cash_cents - total_filled,
                    .buying_power_cents = portfolio.fixtures.cash_rich.buying_power_cents - total_filled,
                    .day_notional_used_cents = portfolio.fixtures.cash_rich.day_notional_used_cents + total_filled,
                    .month_notional_used_cents = portfolio.fixtures.cash_rich.month_notional_used_cents + total_filled,
                };
                break :blk .{ .paper_order = result };
            },
        };
    }
};
