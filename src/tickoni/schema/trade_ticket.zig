const std = @import("std");
const basket = @import("basket");
const portfolio = @import("portfolio");
const thesis = @import("thesis");

pub const max_ticket_id_len: usize = 64;
pub const max_paper_order_id_len: usize = 64;
pub const quantity_scale: u64 = 1_000_000;
pub const max_ticker_len: usize = portfolio.max_ticker_len;

pub const Side = enum(u8) { buy, sell };
pub const OrderType = enum(u8) { market, limit };
pub const TimeInForce = enum(u8) { day };
pub const PolicyOutcome = enum(u8) { allow, deny };
pub const ExecutionStatus = enum(u8) { filled };

pub const Quote = struct {
    ticker: [max_ticker_len]u8,
    ticker_len: u8,
    venue: thesis.Venue,
    bid_cents: i64,
    ask_cents: i64,
    last_cents: i64,

    pub fn tickerSlice(self: *const Quote) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

pub const QuoteSnapshot = struct {
    as_of_ns: u64,
    quotes: [basket.max_basket_instruments]Quote,
    quote_count: u8,

    pub fn find(self: *const QuoteSnapshot, ticker: []const u8) ?Quote {
        for (self.quotes[0..self.quote_count]) |quote| {
            if (std.mem.eql(u8, quote.tickerSlice(), ticker)) return quote;
        }
        return null;
    }
};

pub const TicketLineItem = struct {
    ticker: [max_ticker_len]u8,
    ticker_len: u8,
    asset_class: thesis.AssetClass,
    venue: thesis.Venue,
    side: Side,
    quantity_micros: u64,
    price_cents: i64,
    line_notional_cents: i64,
    allocation_weight_bp: u32,

    pub fn tickerSlice(self: *const TicketLineItem) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

pub const TicketAffordability = struct {
    outcome: portfolio.AffordabilityOutcome,
    cash_available_cents: i64,
    buying_power_cents: i64,
    remaining_daily_notional_cents: i64,
    remaining_monthly_notional_cents: i64,
    max_affordable_cents: i64,
    effective_max_paper_trade_cents: i64,
};

pub const TradeTicket = struct {
    ticket_id: [max_ticket_id_len]u8,
    ticket_id_len: u8,
    account_id: u32,
    side: Side,
    order_type: OrderType,
    time_in_force: TimeInForce,
    target_notional_cents: i64,
    estimated_cost_cents: i64,
    line_items: [basket.max_basket_instruments]TicketLineItem,
    line_item_count: u8,
    affordability_result: TicketAffordability,
    policy_outcome: PolicyOutcome,

    pub fn ticketIdSlice(self: *const TradeTicket) []const u8 {
        return self.ticket_id[0..self.ticket_id_len];
    }
};

pub const PaperFill = struct {
    ticker: [max_ticker_len]u8,
    ticker_len: u8,
    quantity_micros: u64,
    fill_price_cents: i64,
    filled_notional_cents: i64,

    pub fn tickerSlice(self: *const PaperFill) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

pub const PaperExecutionAccountSnapshot = struct {
    cash_cents: i64,
    buying_power_cents: i64,
    day_notional_used_cents: i64,
    month_notional_used_cents: i64,
};

pub const PaperExecutionResult = struct {
    paper_order_id: [max_paper_order_id_len]u8,
    paper_order_id_len: u8,
    ticket_id: [max_ticket_id_len]u8,
    ticket_id_len: u8,
    account_id: u32,
    status: ExecutionStatus,
    total_filled_cents: i64,
    fills: [basket.max_basket_instruments]PaperFill,
    fill_count: u8,
    resulting_account_snapshot: PaperExecutionAccountSnapshot,

    pub fn paperOrderIdSlice(self: *const PaperExecutionResult) []const u8 {
        return self.paper_order_id[0..self.paper_order_id_len];
    }

    pub fn ticketIdSlice(self: *const PaperExecutionResult) []const u8 {
        return self.ticket_id[0..self.ticket_id_len];
    }
};

pub const BuildTicketError = error{
    TicketIdTooLong,
    MissingQuote,
    InvalidQuotePrice,
    ZeroQuantity,
};

fn copyAscii(comptime N: usize, dst: *[N]u8, src: []const u8) !u8 {
    if (src.len > N) return error.TicketIdTooLong;
    @memset(dst, 0);
    @memcpy(dst[0..src.len], src);
    return @intCast(src.len);
}

pub fn buildMarketBuyTicket(
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    policy_max_notional_per_order_cents: i64,
    ticket_id: []const u8,
) BuildTicketError!TradeTicket {
    var ticket: TradeTicket = std.mem.zeroes(TradeTicket);
    ticket.ticket_id_len = try copyAscii(max_ticket_id_len, &ticket.ticket_id, ticket_id);
    ticket.account_id = proposed_basket.account_id;
    ticket.side = .buy;
    ticket.order_type = .market;
    ticket.time_in_force = .day;
    ticket.target_notional_cents = proposed_basket.total_allocated_cents;
    ticket.line_item_count = proposed_basket.instrument_count;

    const effective_max = @min(
        affordability.max_affordable_cents,
        policy_max_notional_per_order_cents,
    );
    ticket.affordability_result = .{
        .outcome = affordability.outcome,
        .cash_available_cents = affordability.cash_available_cents,
        .buying_power_cents = affordability.buying_power_cents,
        .remaining_daily_notional_cents = affordability.remaining_daily_notional_cents,
        .remaining_monthly_notional_cents = affordability.remaining_monthly_notional_cents,
        .max_affordable_cents = affordability.max_affordable_cents,
        .effective_max_paper_trade_cents = effective_max,
    };
    ticket.policy_outcome = if (ticket.target_notional_cents <= effective_max) .allow else .deny;

    var estimated_cost: i64 = 0;
    for (proposed_basket.instruments[0..proposed_basket.instrument_count], 0..) |instrument, i| {
        const quote = quote_snapshot.find(instrument.tickerSlice()) orelse return error.MissingQuote;
        if (quote.ask_cents <= 0) return error.InvalidQuotePrice;

        const quantity_micros = @divTrunc(
            @as(i128, instrument.allocation_cents) * @as(i128, quantity_scale),
            @as(i128, quote.ask_cents),
        );
        if (quantity_micros <= 0) return error.ZeroQuantity;

        ticket.line_items[i].ticker = instrument.ticker;
        ticket.line_items[i].ticker_len = instrument.ticker_len;
        ticket.line_items[i].asset_class = instrument.asset_class;
        ticket.line_items[i].venue = quote.venue;
        ticket.line_items[i].side = .buy;
        ticket.line_items[i].quantity_micros = @intCast(quantity_micros);
        ticket.line_items[i].price_cents = quote.ask_cents;
        ticket.line_items[i].line_notional_cents = instrument.allocation_cents;
        ticket.line_items[i].allocation_weight_bp = instrument.weight_bp;
        estimated_cost += instrument.allocation_cents;
    }
    ticket.estimated_cost_cents = estimated_cost;
    return ticket;
}
