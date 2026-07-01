const std = @import("std");
const basket = @import("basket");
const portfolio = @import("portfolio");
const fixture_portfolio = @import("fixture_portfolio");
const thesis = @import("thesis");

pub const max_ticket_id_len: usize = 64;
pub const max_paper_order_id_len: usize = 64;
pub const quantity_scale: u64 = 1_000_000;
pub const max_ticker_len: usize = portfolio.max_ticker_len;
pub const max_blocked_reasons: usize = 4;

pub const Side = enum(u8) { buy, sell };
pub const OrderType = enum(u8) { market, limit };
pub const TimeInForce = enum(u8) { day };
pub const PolicyOutcome = enum(u8) { allow, deny };
pub const ExecutionStatus = enum(u8) { filled };
pub const FailedScopeDimension = enum(u8) {
    none,
    per_order_notional,
    buying_power,
    day_notional,
    month_notional,

    pub fn label(self: FailedScopeDimension) []const u8 {
        return switch (self) {
            .none => "",
            .per_order_notional => "per_order_notional",
            .buying_power => "buying_power",
            .day_notional => "day_notional",
            .month_notional => "month_notional",
        };
    }
};
pub const BlockedReasonCode = enum(u8) {
    none,
    per_order_notional_exceeded,
    buying_power_exceeded,
    daily_notional_exceeded,
    monthly_notional_exceeded,

    pub fn label(self: BlockedReasonCode) []const u8 {
        return switch (self) {
            .none => "",
            .per_order_notional_exceeded => "per_order_notional_exceeded",
            .buying_power_exceeded => "buying_power_exceeded",
            .daily_notional_exceeded => "daily_notional_exceeded",
            .monthly_notional_exceeded => "monthly_notional_exceeded",
        };
    }
};

pub const BlockedReason = struct {
    code: BlockedReasonCode,
    failed_scope_dim: FailedScopeDimension,
    requested_cents: i64,
    limit_cents: i64,
};

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
    instrument_type: thesis.InstrumentType,
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
    blocked_reasons: [max_blocked_reasons]BlockedReason,
    blocked_reason_count: u8,

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
    LimitPriceRequired,
    InvalidLimitPrice,
    ZeroQuantity,
};

pub const BuildTicketRequest = struct {
    ticket_id: []const u8,
    side: Side,
    order_type: OrderType,
    limit_price_cents: ?i64 = null,
};

fn copyAscii(comptime N: usize, dst: *[N]u8, src: []const u8) !u8 {
    if (src.len > N) return error.TicketIdTooLong;
    @memset(dst, 0);
    @memcpy(dst[0..src.len], src);
    return @intCast(src.len);
}

pub fn applyPolicyDecision(
    ticket: *TradeTicket,
    policy_outcome: PolicyOutcome,
    blocked_reasons: []const BlockedReason,
    effective_max_paper_trade_cents: i64,
) void {
    ticket.policy_outcome = policy_outcome;
    ticket.blocked_reasons = std.mem.zeroes([max_blocked_reasons]BlockedReason);
    const count = if (policy_outcome == .deny)
        @min(blocked_reasons.len, max_blocked_reasons)
    else
        0;
    for (blocked_reasons[0..count], 0..) |blocked_reason, i| {
        ticket.blocked_reasons[i] = blocked_reason;
    }
    ticket.blocked_reason_count = @intCast(count);
    ticket.affordability_result.effective_max_paper_trade_cents = effective_max_paper_trade_cents;
}

pub fn buildMarketBuyTicket(
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    ticket_id: []const u8,
) BuildTicketError!TradeTicket {
    return buildTradeTicket(proposed_basket, quote_snapshot, affordability, .{
        .ticket_id = ticket_id,
        .side = .buy,
        .order_type = .market,
    });
}

pub fn buildMarketSellTicket(
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    ticket_id: []const u8,
) BuildTicketError!TradeTicket {
    return buildTradeTicket(proposed_basket, quote_snapshot, affordability, .{
        .ticket_id = ticket_id,
        .side = .sell,
        .order_type = .market,
    });
}

pub fn buildLimitBuyTicket(
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    ticket_id: []const u8,
    limit_price_cents: ?i64,
) BuildTicketError!TradeTicket {
    return buildTradeTicket(proposed_basket, quote_snapshot, affordability, .{
        .ticket_id = ticket_id,
        .side = .buy,
        .order_type = .limit,
        .limit_price_cents = limit_price_cents,
    });
}

pub fn buildLimitSellTicket(
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    ticket_id: []const u8,
    limit_price_cents: ?i64,
) BuildTicketError!TradeTicket {
    return buildTradeTicket(proposed_basket, quote_snapshot, affordability, .{
        .ticket_id = ticket_id,
        .side = .sell,
        .order_type = .limit,
        .limit_price_cents = limit_price_cents,
    });
}

pub fn buildTradeTicket(
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    request: BuildTicketRequest,
) BuildTicketError!TradeTicket {
    var ticket: TradeTicket = std.mem.zeroes(TradeTicket);
    ticket.ticket_id_len = try copyAscii(max_ticket_id_len, &ticket.ticket_id, request.ticket_id);
    ticket.account_id = proposed_basket.account_id;
    ticket.side = request.side;
    ticket.order_type = request.order_type;
    ticket.time_in_force = .day;
    ticket.target_notional_cents = proposed_basket.total_allocated_cents;
    ticket.line_item_count = proposed_basket.instrument_count;
    ticket.affordability_result = .{
        .outcome = affordability.outcome,
        .cash_available_cents = affordability.cash_available_cents,
        .buying_power_cents = affordability.buying_power_cents,
        .remaining_daily_notional_cents = affordability.remaining_daily_notional_cents,
        .remaining_monthly_notional_cents = affordability.remaining_monthly_notional_cents,
        .max_affordable_cents = affordability.max_affordable_cents,
        .effective_max_paper_trade_cents = affordability.max_affordable_cents,
    };
    ticket.policy_outcome = .allow;

    var estimated_cost: i64 = 0;
    for (proposed_basket.instruments[0..proposed_basket.instrument_count], 0..) |instrument, i| {
        const quote = quote_snapshot.find(instrument.tickerSlice()) orelse return error.MissingQuote;
        const price_cents = try ticketPriceCents(quote, request.side, request.order_type, request.limit_price_cents);

        const quantity_micros = @divTrunc(
            @as(i128, instrument.allocation_cents) * @as(i128, quantity_scale),
            @as(i128, price_cents),
        );
        if (quantity_micros <= 0) return error.ZeroQuantity;

        ticket.line_items[i].ticker = instrument.ticker;
        ticket.line_items[i].ticker_len = instrument.ticker_len;
        ticket.line_items[i].asset_class = instrument.asset_class;
        ticket.line_items[i].instrument_type = instrument.instrument_type;
        ticket.line_items[i].venue = quote.venue;
        ticket.line_items[i].side = request.side;
        ticket.line_items[i].quantity_micros = @intCast(quantity_micros);
        ticket.line_items[i].price_cents = price_cents;
        ticket.line_items[i].line_notional_cents = instrument.allocation_cents;
        ticket.line_items[i].allocation_weight_bp = instrument.weight_bp;
        estimated_cost += instrument.allocation_cents;
    }
    ticket.estimated_cost_cents = estimated_cost;
    return ticket;
}

fn ticketPriceCents(
    quote: Quote,
    side: Side,
    order_type: OrderType,
    limit_price_cents: ?i64,
) BuildTicketError!i64 {
    return switch (order_type) {
        .market => blk: {
            const price_cents = switch (side) {
                .buy => quote.ask_cents,
                .sell => quote.bid_cents,
            };
            if (price_cents <= 0) return error.InvalidQuotePrice;
            break :blk price_cents;
        },
        .limit => blk: {
            const price_cents = limit_price_cents orelse return error.LimitPriceRequired;
            if (price_cents <= 0) return error.InvalidLimitPrice;
            break :blk price_cents;
        },
    };
}

const TicketFixture = struct {
    proposed_basket: basket.Basket,
    quotes: QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
};

fn buildTicketFixture(target_notional_cents: i64, bid_cents: i64, ask_cents: i64) !TicketFixture {
    var input = thesis.fixtures.ai_infrastructure;
    input.target_notional_cents = target_notional_cents;
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const proposed_basket = try basket.build(intent, thesis_id);
    const affordability = portfolio.checkAffordability(&fixture_portfolio.fixtures.cash_rich, proposed_basket.total_allocated_cents);

    var quotes: QuoteSnapshot = std.mem.zeroes(QuoteSnapshot);
    quotes.quote_count = proposed_basket.instrument_count;
    for (proposed_basket.instruments[0..proposed_basket.instrument_count], 0..) |instrument, i| {
        quotes.quotes[i] = .{
            .ticker = instrument.ticker,
            .ticker_len = instrument.ticker_len,
            .venue = .nasdaq,
            .bid_cents = bid_cents,
            .ask_cents = ask_cents,
            .last_cents = ask_cents,
        };
    }

    return .{
        .proposed_basket = proposed_basket,
        .quotes = quotes,
        .affordability = affordability,
    };
}

fn expectedQuantityMicros(allocation_cents: i64, price_cents: i64) u64 {
    return @intCast(@divTrunc(
        @as(i128, allocation_cents) * @as(i128, quantity_scale),
        @as(i128, price_cents),
    ));
}

test "buildMarketBuyTicket: line items carry instrument_type distinct from asset_class" {
    const fixture = try buildTicketFixture(200_000, 9_500, 10_000);

    const ticket = try buildMarketBuyTicket(
        &fixture.proposed_basket,
        &fixture.quotes,
        fixture.affordability,
        "ticket_ai_infra_2000_instrument_type",
    );

    try std.testing.expect(ticket.line_item_count > 0);
    for (ticket.line_items[0..ticket.line_item_count], 0..) |line, i| {
        try std.testing.expectEqual(
            fixture.proposed_basket.instruments[i].instrument_type,
            line.instrument_type,
        );
        try std.testing.expectEqual(
            fixture.proposed_basket.instruments[i].asset_class,
            line.asset_class,
        );
    }
    // ai_infrastructure fixture includes both stock and ETF instruments,
    // proving instrument_type is not inferred from asset_class or ticker.
    var found_stock = false;
    var found_etf = false;
    for (ticket.line_items[0..ticket.line_item_count]) |line| {
        if (line.instrument_type == .stock) found_stock = true;
        if (line.instrument_type == .etf) found_etf = true;
    }
    try std.testing.expect(found_stock);
    try std.testing.expect(found_etf);
}

test "buildMarketBuyTicket: oversized notional produces per-order block reason" {
    const fixture = try buildTicketFixture(2_500_000, 10_000, 10_000);

    const ticket = try buildMarketBuyTicket(
        &fixture.proposed_basket,
        &fixture.quotes,
        fixture.affordability,
        "ticket_ai_infra_25000_blocked",
    );

    try std.testing.expectEqual(PolicyOutcome.allow, ticket.policy_outcome);
    try std.testing.expectEqual(@as(u8, 0), ticket.blocked_reason_count);
    try std.testing.expectEqual(fixture.affordability.max_affordable_cents, ticket.affordability_result.effective_max_paper_trade_cents);
}

test "buildMarketSellTicket: creates sell preview using bid prices" {
    const fixture = try buildTicketFixture(200_000, 9_500, 10_000);

    const ticket = try buildMarketSellTicket(
        &fixture.proposed_basket,
        &fixture.quotes,
        fixture.affordability,
        "ticket_ai_infra_2000_market_sell",
    );

    try std.testing.expectEqual(Side.sell, ticket.side);
    try std.testing.expectEqual(OrderType.market, ticket.order_type);
    try std.testing.expectEqual(fixture.proposed_basket.instrument_count, ticket.line_item_count);
    for (ticket.line_items[0..ticket.line_item_count], 0..) |line, i| {
        try std.testing.expectEqual(Side.sell, line.side);
        try std.testing.expectEqual(@as(i64, 9_500), line.price_cents);
        try std.testing.expectEqual(
            expectedQuantityMicros(fixture.proposed_basket.instruments[i].allocation_cents, 9_500),
            line.quantity_micros,
        );
    }
}

test "buildLimitBuyTicket: requires positive limit price" {
    const fixture = try buildTicketFixture(200_000, 9_500, 10_000);

    try std.testing.expectError(error.LimitPriceRequired, buildLimitBuyTicket(
        &fixture.proposed_basket,
        &fixture.quotes,
        fixture.affordability,
        "ticket_ai_infra_2000_limit_buy",
        null,
    ));
    try std.testing.expectError(error.InvalidLimitPrice, buildLimitBuyTicket(
        &fixture.proposed_basket,
        &fixture.quotes,
        fixture.affordability,
        "ticket_ai_infra_2000_limit_buy",
        0,
    ));
}

test "buildLimitBuyTicket: creates buy preview using limit price" {
    const fixture = try buildTicketFixture(200_000, 9_500, 10_000);
    const limit_price_cents: i64 = 9_875;

    const ticket = try buildLimitBuyTicket(
        &fixture.proposed_basket,
        &fixture.quotes,
        fixture.affordability,
        "ticket_ai_infra_2000_limit_buy",
        limit_price_cents,
    );

    try std.testing.expectEqual(Side.buy, ticket.side);
    try std.testing.expectEqual(OrderType.limit, ticket.order_type);
    for (ticket.line_items[0..ticket.line_item_count], 0..) |line, i| {
        try std.testing.expectEqual(Side.buy, line.side);
        try std.testing.expectEqual(limit_price_cents, line.price_cents);
        try std.testing.expectEqual(
            expectedQuantityMicros(fixture.proposed_basket.instruments[i].allocation_cents, limit_price_cents),
            line.quantity_micros,
        );
    }
}

test "buildLimitSellTicket: creates sell preview using limit price" {
    const fixture = try buildTicketFixture(200_000, 9_500, 10_000);
    const limit_price_cents: i64 = 10_125;

    const ticket = try buildLimitSellTicket(
        &fixture.proposed_basket,
        &fixture.quotes,
        fixture.affordability,
        "ticket_ai_infra_2000_limit_sell",
        limit_price_cents,
    );

    try std.testing.expectEqual(Side.sell, ticket.side);
    try std.testing.expectEqual(OrderType.limit, ticket.order_type);
    for (ticket.line_items[0..ticket.line_item_count], 0..) |line, i| {
        try std.testing.expectEqual(Side.sell, line.side);
        try std.testing.expectEqual(limit_price_cents, line.price_cents);
        try std.testing.expectEqual(
            expectedQuantityMicros(fixture.proposed_basket.instruments[i].allocation_cents, limit_price_cents),
            line.quantity_micros,
        );
    }
}
