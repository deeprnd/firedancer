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
    /// Owned by value, not borrowed: AdapterRequest crosses the tktool/tkadpt
    /// boundary, and TradeTicket is already a fixed-size, pointer-free
    /// struct, so there is no reason for this to carry a caller-owned
    /// pointer that would dangle across a process/shared-memory boundary.
    ticket: ?trade_ticket.TradeTicket = null,
};

pub const AdapterResult = union(AdapterOperation) {
    portfolio_snapshot: portfolio.BrokerageAccount,
    quote_snapshot: trade_ticket.QuoteSnapshot,
    paper_order: trade_ticket.PaperExecutionResult,
};

pub const BackendError = error{
    UnknownAccount,
    UnsupportedTicker,
    MissingTicket,
    PolicyBlocked,
};
