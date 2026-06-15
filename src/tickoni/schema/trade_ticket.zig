/// Trade ticket schema and paper execution for V1.1.S5.
///
/// TradeTicket: produced by preview() from a Basket and BrokerageAccount.
/// Contains line items (one per basket instrument), guardrail check results,
/// and status (.allowed or .blocked).
///
/// PaperExecutionResult: produced by execute() when status is .allowed.
/// Simulates fills at fixture prices and returns a timestamped cash/holdings
/// snapshot.
///
/// Invariant (T7, T8): execute() rejects any ticket whose status is not
/// .allowed.  There is no path that bypasses ticket validation to reach
/// paper execution.
const std = @import("std");
const basket_mod = @import("basket.zig");
const cat = @import("catalog.zig");
const portfolio = @import("portfolio.zig");
const thesis_cabi = @import("thesis_cabi");

pub const trade_ticket_schema_version: u16 = 1;

/// Maximum guardrail failures recorded per ticket.  All failures are
/// accumulated; execution does not stop at the first failure.
pub const max_guardrail_failures: usize = 16;

// ---------------------------------------------------------------------------
// Types (T1)
// ---------------------------------------------------------------------------

pub const OrderType = enum(u8) {
    market = 0,
    limit = 1,
};

pub const TimeInForce = enum(u8) {
    day = 0,
    gtc = 1,
};

pub const TicketStatus = enum(u8) {
    /// All guardrail checks passed.  The ticket may be paper-executed.
    allowed = 0,
    /// One or more guardrail checks failed.  The ticket cannot be executed.
    blocked = 1,
};

/// A single guardrail failure reason.  Multiple failures may be present on
/// one ticket; all are listed in guardrail_failures[0..guardrail_failure_count].
pub const GuardrailFailure = enum(u8) {
    /// BUY: insufficient cash or buying power for the requested notional.
    insufficient_buying_power = 0,
    /// BUY: day notional limit would be exceeded.
    day_notional_exceeded = 1,
    /// BUY: month notional limit would be exceeded.
    month_notional_exceeded = 2,
    /// BUY: open order slot limit already at capacity.
    open_order_limit = 3,
    /// One or more basket instruments are on the restricted denylist.
    restricted_instrument = 4,
    /// The order would create a same-day round trip for one or more instruments.
    same_day_round_trip = 5,
    /// SELL: one or more instruments have not been held for the minimum period.
    minimum_holding_period = 6,
    /// Limit order type selected but limit_price_cents is zero or negative (T4).
    limit_price_required = 7,
    /// One or more instruments fall outside the supported US market scope.
    unsupported_market = 8,
    /// One or more instruments fall outside the supported NYSE/NASDAQ venue scope.
    unsupported_venue = 9,
    /// One or more instruments fall outside the supported sector/theme scope.
    unsupported_sector = 10,
    /// SELL: the account does not hold enough shares for one or more line items.
    insufficient_holdings = 11,
};

/// One line item in a trade ticket, corresponding to one basket instrument (T1, T2).
pub const TradeTicketLineItem = struct {
    ticker: [cat.max_ticker_len]u8,
    ticker_len: u8,
    asset_class: cat.AssetClass,
    market: cat.Market,
    venue: cat.Venue,
    sector: cat.SectorTheme,
    side: portfolio.Side,
    order_type: OrderType,
    /// Dollar allocation from the basket for this instrument (in cents).
    target_notional_cents: i64,
    /// Deterministic fixture price per share in cents (T2).
    fixture_price_cents: i64,
    /// Floor(target_notional_cents / fixture_price_cents).
    estimated_shares: u32,
    /// estimated_shares * fixture_price_cents.
    estimated_cost_cents: i64,
    /// Per-share limit price in cents; zero for market orders (T4).
    limit_price_cents: i64,

    pub fn tickerSlice(self: *const TradeTicketLineItem) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

/// Trade ticket produced by preview() (T1).
///
/// ticket_id is a content hash of the composition via computeTicketHash().
/// status is .allowed when guardrail_failure_count == 0.
/// max_affordable_cents is valid on BUY orders; it reflects the minimum of
/// cash_available, buying_power, remaining_daily, and remaining_monthly.
pub const TradeTicket = struct {
    ticket_id: u64,
    basket_id: u64,
    account_id: u32,
    side: portfolio.Side,
    order_type: OrderType,
    time_in_force: TimeInForce,
    target_notional_cents: i64,
    estimated_cost_cents: i64,
    line_items: [basket_mod.max_basket_instruments]TradeTicketLineItem,
    line_item_count: u8,
    status: TicketStatus,
    guardrail_failures: [max_guardrail_failures]GuardrailFailure,
    guardrail_failure_count: u8,
    /// Maximum affordable notional on BUY (zero on SELL; computed by affordability check).
    max_affordable_cents: i64,
};

// ---------------------------------------------------------------------------
// Paper execution schema (T6)
// ---------------------------------------------------------------------------

/// One filled line item in a paper execution result (T6).
pub const PaperFilledLineItem = struct {
    ticker: [cat.max_ticker_len]u8,
    ticker_len: u8,
    side: portfolio.Side,
    filled_shares: u32,
    fill_price_cents: i64,
    fill_notional_cents: i64,

    pub fn tickerSlice(self: *const PaperFilledLineItem) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

/// Paper execution result produced by execute() for an allowed ticket (T6).
///
/// executed_at_ns is a caller-supplied deterministic execution timestamp for
/// audit and replay. resulting_cash_cents, resulting_buying_power_cents, and
/// resulting_holdings are post-fill snapshots.
pub const PaperExecutionResult = struct {
    paper_order_id: u64,
    ticket_id: u64,
    account_id: u32,
    executed_at_ns: u64,
    filled_line_items: [basket_mod.max_basket_instruments]PaperFilledLineItem,
    filled_line_item_count: u8,
    total_fill_notional_cents: i64,
    resulting_cash_cents: i64,
    resulting_buying_power_cents: i64,
    resulting_holdings: [portfolio.max_holdings]portfolio.Holding,
    resulting_holding_count: u8,
    paper_seq: u64,
};

// ---------------------------------------------------------------------------
// HoldingRecord: for holding-period and round-trip checks (T5)
// ---------------------------------------------------------------------------

/// A holding annotated with days since purchase, for guardrail checks in
/// preview().
///
/// days_held == 0: purchased today.  On SELL this always triggers the
/// minimum-holding-period check (and the same-day round-trip check when the
/// instrument is also in same_day_opposite).
pub const HoldingRecord = struct {
    ticker: [cat.max_ticker_len]u8,
    ticker_len: u8,
    /// Number of calendar days since purchase.  0 = purchased today.
    days_held: u16,

    pub fn tickerSlice(self: *const HoldingRecord) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

pub const TicketError = error{
    /// basket.account_id does not match account.account_id.
    AccountMismatch,
    /// A basket instrument could not be resolved in the catalog.
    InstrumentNotInCatalog,
};

pub const PaperExecutionError = error{
    /// Ticket status is .blocked; blocked tickets cannot be paper-executed (T7, T8).
    TicketBlocked,
    /// ticket.account_id does not match account.account_id.
    AccountMismatch,
    /// The ticket requires more holdings than the account currently has.
    InsufficientHoldings,
    /// Applying the fills would exceed the bounded holdings snapshot capacity.
    HoldingCapacityExceeded,
};

// ---------------------------------------------------------------------------
// Fixture prices (T2)
// ---------------------------------------------------------------------------

const FixturePrice = struct {
    ticker: []const u8,
    price_cents: i64,
};

/// Deterministic fixture prices for all V1.1 catalog instruments (T2).
/// Prices in cents.  All 24 catalog entries are covered; restricted instruments
/// are included so the table is complete, though they will not appear in baskets.
const fixture_price_table = [_]FixturePrice{
    .{ .ticker = "NVDA", .price_cents = 13_000 }, // USD 130.00
    .{ .ticker = "AMD", .price_cents = 16_500 }, // USD 165.00
    .{ .ticker = "AVGO", .price_cents = 18_000 }, // USD 180.00
    .{ .ticker = "MSFT", .price_cents = 42_000 }, // USD 420.00
    .{ .ticker = "BOTZ", .price_cents = 3_200 }, // USD  32.00
    .{ .ticker = "SOXX", .price_cents = 23_000 }, // USD 230.00
    .{ .ticker = "AMZN", .price_cents = 19_500 }, // USD 195.00
    .{ .ticker = "WCLD", .price_cents = 3_000 }, // USD  30.00
    .{ .ticker = "PANW", .price_cents = 17_500 }, // USD 175.00
    .{ .ticker = "CRWD", .price_cents = 36_000 }, // USD 360.00
    .{ .ticker = "HACK", .price_cents = 5_000 }, // USD  50.00
    .{ .ticker = "CIBR", .price_cents = 6_200 }, // USD  62.00
    .{ .ticker = "SPY", .price_cents = 57_000 }, // USD 570.00
    .{ .ticker = "IVV", .price_cents = 57_000 }, // USD 570.00
    .{ .ticker = "VOO", .price_cents = 52_500 }, // USD 525.00
    .{ .ticker = "VTI", .price_cents = 26_000 }, // USD 260.00
    .{ .ticker = "VYM", .price_cents = 13_000 }, // USD 130.00
    .{ .ticker = "DVY", .price_cents = 12_500 }, // USD 125.00
    .{ .ticker = "SHV", .price_cents = 11_000 }, // USD 110.00
    .{ .ticker = "SGOV", .price_cents = 10_050 }, // USD 100.50
    .{ .ticker = "BIL", .price_cents = 9_150 }, // USD  91.50
    .{ .ticker = "SOXL", .price_cents = 3_700 }, // USD  37.00 (restricted)
    .{ .ticker = "SOXS", .price_cents = 1_500 }, // USD  15.00 (restricted)
    .{ .ticker = "BULZ", .price_cents = 800 }, // USD   8.00 (restricted)
};

// Guard: fixture table must cover the full catalog.
comptime {
    std.debug.assert(fixture_price_table.len == cat.catalog.len);
}

/// Return the fixture price in cents for ticker.  Returns 0 if not found.
pub fn fixturePriceCents(ticker: []const u8) i64 {
    for (fixture_price_table) |p| {
        if (std.mem.eql(u8, p.ticker, ticker)) return p.price_cents;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Content hashes
// ---------------------------------------------------------------------------

/// Compute a stable content hash for a TradeTicket via tk_trade_ticket_hash.
/// Covers schema_version, basket_id, account_id, side, order_type,
/// time_in_force, target_notional_cents, line_item_count, and per line item:
/// ticker (zero-padded), target_notional_cents, limit_price_cents, market,
/// venue, and sector.
pub fn computeTicketHash(ticket: *const TradeTicket) u64 {
    var ticker_data: [basket_mod.max_basket_instruments * cat.max_ticker_len]u8 =
        std.mem.zeroes([basket_mod.max_basket_instruments * cat.max_ticker_len]u8);
    var notional_arr: [basket_mod.max_basket_instruments]i64 = [_]i64{0} ** basket_mod.max_basket_instruments;
    var limit_price_arr: [basket_mod.max_basket_instruments]i64 = [_]i64{0} ** basket_mod.max_basket_instruments;
    var market_arr: [basket_mod.max_basket_instruments]u8 = [_]u8{0} ** basket_mod.max_basket_instruments;
    var venue_arr: [basket_mod.max_basket_instruments]u8 = [_]u8{0} ** basket_mod.max_basket_instruments;
    var sector_arr: [basket_mod.max_basket_instruments]u8 = [_]u8{0} ** basket_mod.max_basket_instruments;
    for (0..ticket.line_item_count) |i| {
        const off = i * cat.max_ticker_len;
        @memcpy(ticker_data[off..][0..cat.max_ticker_len], &ticket.line_items[i].ticker);
        notional_arr[i] = ticket.line_items[i].target_notional_cents;
        limit_price_arr[i] = ticket.line_items[i].limit_price_cents;
        market_arr[i] = @intFromEnum(ticket.line_items[i].market);
        venue_arr[i] = @intFromEnum(ticket.line_items[i].venue);
        sector_arr[i] = @intFromEnum(ticket.line_items[i].sector);
    }
    return thesis_cabi.tk_trade_ticket_hash(
        ticket.basket_id,
        ticket.account_id,
        @intFromEnum(ticket.side),
        @intFromEnum(ticket.order_type),
        @intFromEnum(ticket.time_in_force),
        ticket.target_notional_cents,
        ticket.line_item_count,
        &ticker_data,
        &notional_arr,
        &limit_price_arr,
        &market_arr,
        &venue_arr,
        &sector_arr,
    );
}

/// Compute a stable content hash for a PaperExecutionResult via tk_paper_order_hash.
/// Covers schema_version, ticket_id, account_id, executed_at_ns, filled line
/// items, paper_seq, cash/buying-power snapshots, and the resulting holdings
/// snapshot.
pub fn computePaperOrderHash(result: *const PaperExecutionResult) u64 {
    var filled_ticker_data: [basket_mod.max_basket_instruments * cat.max_ticker_len]u8 =
        std.mem.zeroes([basket_mod.max_basket_instruments * cat.max_ticker_len]u8);
    var filled_shares_arr: [basket_mod.max_basket_instruments]u32 = [_]u32{0} ** basket_mod.max_basket_instruments;
    var fill_price_arr: [basket_mod.max_basket_instruments]i64 = [_]i64{0} ** basket_mod.max_basket_instruments;
    var fill_notional_arr: [basket_mod.max_basket_instruments]i64 = [_]i64{0} ** basket_mod.max_basket_instruments;
    var holding_ticker_data: [portfolio.max_holdings * cat.max_ticker_len]u8 =
        std.mem.zeroes([portfolio.max_holdings * cat.max_ticker_len]u8);
    var holding_share_arr: [portfolio.max_holdings]u32 = [_]u32{0} ** portfolio.max_holdings;
    var holding_market_value_arr: [portfolio.max_holdings]i64 = [_]i64{0} ** portfolio.max_holdings;
    for (0..result.filled_line_item_count) |i| {
        const off = i * cat.max_ticker_len;
        @memcpy(filled_ticker_data[off..][0..cat.max_ticker_len], &result.filled_line_items[i].ticker);
        filled_shares_arr[i] = result.filled_line_items[i].filled_shares;
        fill_price_arr[i] = result.filled_line_items[i].fill_price_cents;
        fill_notional_arr[i] = result.filled_line_items[i].fill_notional_cents;
    }
    for (0..result.resulting_holding_count) |i| {
        const off = i * cat.max_ticker_len;
        @memcpy(holding_ticker_data[off..][0..cat.max_ticker_len], &result.resulting_holdings[i].ticker);
        holding_share_arr[i] = result.resulting_holdings[i].share_count;
        holding_market_value_arr[i] = result.resulting_holdings[i].market_value_cents;
    }
    return thesis_cabi.tk_paper_order_hash(
        result.ticket_id,
        result.account_id,
        result.executed_at_ns,
        result.filled_line_item_count,
        result.paper_seq,
        result.total_fill_notional_cents,
        result.resulting_cash_cents,
        result.resulting_buying_power_cents,
        &filled_ticker_data,
        &filled_shares_arr,
        &fill_price_arr,
        &fill_notional_arr,
        result.resulting_holding_count,
        &holding_ticker_data,
        &holding_share_arr,
        &holding_market_value_arr,
    );
}

fn isSupportedMarket(market: cat.Market) bool {
    return switch (market) {
        .us => true,
    };
}

fn isSupportedVenue(venue: cat.Venue) bool {
    return switch (venue) {
        .nyse, .nasdaq => true,
    };
}

fn isSupportedSector(sector: cat.SectorTheme) bool {
    return switch (sector) {
        .ai_infrastructure,
        .semiconductors,
        .cloud,
        .cyber_security,
        .broad_market,
        .dividends,
        .cash_like,
        => true,
    };
}

// ---------------------------------------------------------------------------
// Guardrail helper
// ---------------------------------------------------------------------------

/// Append a guardrail failure to the ticket's failure list.
/// Silently drops failures beyond max_guardrail_failures (should not occur
/// given the bounded number of distinct failure types).
fn addFailure(ticket: *TradeTicket, f: GuardrailFailure) void {
    if (ticket.guardrail_failure_count < max_guardrail_failures) {
        ticket.guardrail_failures[ticket.guardrail_failure_count] = f;
        ticket.guardrail_failure_count += 1;
    }
}

fn findHoldingIndex(
    holdings: []const portfolio.Holding,
    ticker: []const u8,
) ?usize {
    for (holdings, 0..) |holding, i| {
        if (std.mem.eql(u8, holding.tickerSlice(), ticker)) return i;
    }
    return null;
}

fn removeHoldingAt(
    holdings: *[portfolio.max_holdings]portfolio.Holding,
    holding_count: *u8,
    idx: usize,
) void {
    var i = idx;
    while (i + 1 < @as(usize, holding_count.*)) : (i += 1) {
        holdings[i] = holdings[i + 1];
    }
    holding_count.* -= 1;
    holdings[@as(usize, holding_count.*)] = std.mem.zeroes(portfolio.Holding);
}

fn applyFillToHoldings(
    result: *PaperExecutionResult,
    li: *const TradeTicketLineItem,
    fill_notional_cents: i64,
) PaperExecutionError!void {
    if (li.estimated_shares == 0) return;

    const idx = findHoldingIndex(
        result.resulting_holdings[0..result.resulting_holding_count],
        li.tickerSlice(),
    );
    switch (li.side) {
        .buy => {
            if (idx) |holding_idx| {
                result.resulting_holdings[holding_idx].share_count += li.estimated_shares;
                result.resulting_holdings[holding_idx].market_value_cents += fill_notional_cents;
            } else {
                if (@as(usize, result.resulting_holding_count) >= portfolio.max_holdings) {
                    return error.HoldingCapacityExceeded;
                }
                result.resulting_holdings[@as(usize, result.resulting_holding_count)] = .{
                    .ticker = li.ticker,
                    .ticker_len = li.ticker_len,
                    .share_count = li.estimated_shares,
                    .market_value_cents = fill_notional_cents,
                };
                result.resulting_holding_count += 1;
            }
        },
        .sell => {
            const holding_idx = idx orelse return error.InsufficientHoldings;
            if (result.resulting_holdings[holding_idx].share_count < li.estimated_shares) {
                return error.InsufficientHoldings;
            }
            result.resulting_holdings[holding_idx].share_count -= li.estimated_shares;
            result.resulting_holdings[holding_idx].market_value_cents = @max(
                @as(i64, 0),
                result.resulting_holdings[holding_idx].market_value_cents - fill_notional_cents,
            );
            if (result.resulting_holdings[holding_idx].share_count == 0) {
                removeHoldingAt(
                    &result.resulting_holdings,
                    &result.resulting_holding_count,
                    holding_idx,
                );
            }
        },
    }
}

// ---------------------------------------------------------------------------
// preview(): build a trade ticket from a basket and account (T1–T5)
// ---------------------------------------------------------------------------

/// Build a TradeTicket from a Basket, BrokerageAccount, and order parameters.
///
/// Line items (T2, T3): each basket instrument becomes one line item with a
/// deterministic fixture price, estimated shares (floor division), and estimated
/// cost.  Both BUY and SELL are supported (T3).  Limit orders require a positive
/// limit_price_cents (T4).
///
/// Guardrail checks (T5) — all failures are collected before returning:
///   1. limit_price_required: limit order with non-positive limit_price_cents.
///   2. BUY affordability (cash, buying_power, day/month notional, open order slot).
///   3. market/venue/sector/restricted-instrument scope checks.
///   4. same_day_round_trip: any basket instrument ticker appears in same_day_opposite.
///   5. minimum_holding_period (SELL only): any basket instrument's days_held is
///      below min_holding_days in the holding_records slice.
///   6. insufficient_holdings (SELL only): one or more line items exceed the
///      account's current share count.
///
/// same_day_opposite is the list of tickers traded on the opposite side today:
///   for BUY — tickers of instruments sold today;
///   for SELL — tickers of instruments bought today.
/// Pass an empty slice to skip the round-trip check.
///
/// holding_records is used for the SELL minimum-holding-period check and must
/// contain at least the instruments present in the basket that are held.
/// Pass an empty slice to skip the check.
///
/// Returns TicketError.AccountMismatch when basket.account_id != account.account_id.
/// Returns TicketError.InstrumentNotInCatalog when a basket instrument no longer
/// resolves against the static V1.1 catalog.
pub fn preview(
    proposed_basket: *const basket_mod.Basket,
    account: *const portfolio.BrokerageAccount,
    side: portfolio.Side,
    order_type: OrderType,
    time_in_force: TimeInForce,
    limit_price_cents: i64,
    same_day_opposite: []const [cat.max_ticker_len]u8,
    holding_records: []const HoldingRecord,
    min_holding_days: u16,
) TicketError!TradeTicket {
    if (account.account_id != proposed_basket.account_id) return error.AccountMismatch;

    var ticket: TradeTicket = std.mem.zeroes(TradeTicket);
    ticket.basket_id = proposed_basket.basket_id;
    ticket.account_id = proposed_basket.account_id;
    ticket.side = side;
    ticket.order_type = order_type;
    ticket.time_in_force = time_in_force;
    ticket.target_notional_cents = proposed_basket.total_allocated_cents;

    // Build line items from basket allocations and fixture prices (T2, T3, T4).
    var estimated_total: i64 = 0;
    for (0..proposed_basket.instrument_count) |i| {
        const inst = &proposed_basket.instruments[i];
        const entry = cat.lookupByTicker(inst.tickerSlice()) orelse
            return error.InstrumentNotInCatalog;
        const price = fixturePriceCents(inst.tickerSlice());
        const shares: u32 = if (price > 0)
            @intCast(@min(
                @as(i64, std.math.maxInt(u32)),
                @divTrunc(inst.allocation_cents, price),
            ))
        else
            0;
        const cost: i64 = @as(i64, shares) * price;
        ticket.line_items[i] = .{
            .ticker = inst.ticker,
            .ticker_len = inst.ticker_len,
            .asset_class = inst.asset_class,
            .market = entry.market,
            .venue = entry.venue,
            .sector = entry.sector,
            .side = side,
            .order_type = order_type,
            .target_notional_cents = inst.allocation_cents,
            .fixture_price_cents = price,
            .estimated_shares = shares,
            .estimated_cost_cents = cost,
            .limit_price_cents = if (order_type == .limit) limit_price_cents else 0,
        };
        estimated_total += cost;
    }
    ticket.line_item_count = proposed_basket.instrument_count;
    ticket.estimated_cost_cents = estimated_total;

    // --- Guardrail checks (T5) ---

    // Check 1: limit order must have a positive per-share limit price (T4).
    if (order_type == .limit and limit_price_cents <= 0) {
        addFailure(&ticket, .limit_price_required);
    }

    // Check 2: BUY affordability (cash, buying power, notional, open order slot).
    if (side == .buy) {
        const afford = portfolio.checkAffordability(account, proposed_basket.total_allocated_cents);
        ticket.max_affordable_cents = afford.max_affordable_cents;
        switch (afford.outcome) {
            .allow => {},
            .deny_insufficient_buying_power, .deny_invalid_notional => {
                addFailure(&ticket, .insufficient_buying_power);
            },
            .deny_day_limit_exceeded => {
                addFailure(&ticket, .day_notional_exceeded);
            },
            .deny_month_limit_exceeded => {
                addFailure(&ticket, .month_notional_exceeded);
            },
            .deny_open_order_limit => {
                addFailure(&ticket, .open_order_limit);
            },
        }
    }

    // Check 3: market/venue/sector/restricted-instrument scope.
    for (0..proposed_basket.instrument_count) |i| {
        const li = &ticket.line_items[i];
        if (!isSupportedMarket(li.market)) {
            addFailure(&ticket, .unsupported_market);
            break;
        }
        if (!isSupportedVenue(li.venue)) {
            addFailure(&ticket, .unsupported_venue);
            break;
        }
        if (!isSupportedSector(li.sector)) {
            addFailure(&ticket, .unsupported_sector);
            break;
        }
        if (cat.lookupByTicker(li.tickerSlice())) |entry| {
            if (entry.restricted) {
                addFailure(&ticket, .restricted_instrument);
                break;
            }
        }
    }

    // Check 4: same-day round-trip.
    round_trip: for (0..proposed_basket.instrument_count) |i| {
        const inst = &proposed_basket.instruments[i];
        for (same_day_opposite) |opp| {
            if (std.mem.eql(u8, &inst.ticker, &opp)) {
                addFailure(&ticket, .same_day_round_trip);
                break :round_trip;
            }
        }
    }

    // Check 5: minimum holding period and sufficient holdings — SELL only.
    if (side == .sell) {
        holdings_available: for (ticket.line_items[0..ticket.line_item_count]) |li| {
            if (li.estimated_shares == 0) continue;
            const holding = portfolio.findHolding(account, li.tickerSlice()) orelse {
                addFailure(&ticket, .insufficient_holdings);
                break :holdings_available;
            };
            if (holding.share_count < li.estimated_shares) {
                addFailure(&ticket, .insufficient_holdings);
                break :holdings_available;
            }
        }

        holding_period: for (0..proposed_basket.instrument_count) |i| {
            const inst = &ticket.line_items[i];
            if (inst.estimated_shares == 0) continue;
            for (holding_records) |hr| {
                if (std.mem.eql(u8, inst.tickerSlice(), hr.tickerSlice())) {
                    if (hr.days_held < min_holding_days) {
                        addFailure(&ticket, .minimum_holding_period);
                        break :holding_period;
                    }
                }
            }
        }
    }

    ticket.status = if (ticket.guardrail_failure_count == 0) .allowed else .blocked;
    ticket.ticket_id = computeTicketHash(&ticket);
    return ticket;
}

// ---------------------------------------------------------------------------
// execute(): paper-execute an allowed ticket (T6, T7, T8)
// ---------------------------------------------------------------------------

/// Paper-execute an allowed trade ticket (T7, T8).
///
/// Returns PaperExecutionError.TicketBlocked when ticket.status != .allowed,
/// enforcing that no blocked ticket can be executed (T8).
///
/// Fills are simulated at the line item's fixture_price_cents.  The resulting
/// cash and buying_power snapshots reflect the fill cost:
///   BUY  → cash and buying_power decrease by total_fill_notional_cents.
///   SELL → cash and buying_power increase by total_fill_notional_cents.
///
/// executed_at_ns and paper_seq are caller-supplied deterministic inputs for
/// audit and replay.  paper_order_id is derived from the filled lines and the
/// resulting account snapshot.
pub fn execute(
    ticket: *const TradeTicket,
    account: *const portfolio.BrokerageAccount,
    paper_seq: u64,
    executed_at_ns: u64,
) PaperExecutionError!PaperExecutionResult {
    if (ticket.status != .allowed) return error.TicketBlocked; // T7, T8
    if (ticket.account_id != account.account_id) return error.AccountMismatch;

    var result: PaperExecutionResult = std.mem.zeroes(PaperExecutionResult);
    result.ticket_id = ticket.ticket_id;
    result.account_id = ticket.account_id;
    result.executed_at_ns = executed_at_ns;
    result.paper_seq = paper_seq;
    result.resulting_holding_count = account.holding_count;
    @memcpy(
        result.resulting_holdings[0..portfolio.max_holdings],
        account.holdings[0..portfolio.max_holdings],
    );

    var total_fill: i64 = 0;
    for (0..ticket.line_item_count) |i| {
        const li = &ticket.line_items[i];
        const fill_notional: i64 = @as(i64, li.estimated_shares) * li.fixture_price_cents;
        result.filled_line_items[i] = .{
            .ticker = li.ticker,
            .ticker_len = li.ticker_len,
            .side = li.side,
            .filled_shares = li.estimated_shares,
            .fill_price_cents = li.fixture_price_cents,
            .fill_notional_cents = fill_notional,
        };
        total_fill += fill_notional;
        try applyFillToHoldings(&result, li, fill_notional);
    }
    result.filled_line_item_count = ticket.line_item_count;
    result.total_fill_notional_cents = total_fill;

    // Post-fill cash snapshot.
    const cash_delta: i64 = switch (ticket.side) {
        .buy => -total_fill,
        .sell => total_fill,
    };
    result.resulting_cash_cents = account.cash_cents + cash_delta;
    result.resulting_buying_power_cents = account.buying_power_cents + cash_delta;

    result.paper_order_id = computePaperOrderHash(&result);
    return result;
}

// ---------------------------------------------------------------------------
// Demo fixtures
// ---------------------------------------------------------------------------

/// Comptime helper for fixed-size ticker buffers.
fn tickerBuf(comptime s: []const u8) [cat.max_ticker_len]u8 {
    if (s.len > cat.max_ticker_len) @compileError("ticker exceeds max_ticker_len");
    var buf = [_]u8{0} ** cat.max_ticker_len;
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

/// Demo fixtures for round-trip and holding-period guardrail tests.
pub const fixtures = struct {
    /// Same-day sell list: NVDA was sold today.
    /// Pass to preview() as same_day_opposite on a BUY to trigger round-trip block.
    pub const same_day_sold_nvda = [1][cat.max_ticker_len]u8{tickerBuf("NVDA")};

    /// Same-day buy list: NVDA was bought today.
    /// Pass to preview() as same_day_opposite on a SELL to trigger round-trip block.
    pub const same_day_bought_nvda = [1][cat.max_ticker_len]u8{tickerBuf("NVDA")};

    /// NVDA purchased today (days_held = 0): triggers minimum-holding-period block on SELL.
    pub const holding_nvda_today = HoldingRecord{
        .ticker = tickerBuf("NVDA"),
        .ticker_len = 4,
        .days_held = 0,
    };

    /// NVDA held for 5 days: no holding-period block.
    pub const holding_nvda_5days = HoldingRecord{
        .ticker = tickerBuf("NVDA"),
        .ticker_len = 4,
        .days_held = 5,
    };
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const thesis = @import("thesis.zig");

test "trade_ticket_schema_version is 1" {
    try std.testing.expectEqual(@as(u16, 1), trade_ticket_schema_version);
}

// --- Fixture prices (T2) ---

test "fixturePriceCents: known tickers return positive prices" {
    try std.testing.expect(fixturePriceCents("NVDA") > 0);
    try std.testing.expect(fixturePriceCents("SOXX") > 0);
    try std.testing.expect(fixturePriceCents("SPY") > 0);
    try std.testing.expect(fixturePriceCents("BIL") > 0);
}

test "fixturePriceCents: all catalog tickers have positive prices" {
    for (cat.catalog) |e| {
        try std.testing.expect(fixturePriceCents(e.tickerSlice()) > 0);
    }
}

test "fixturePriceCents: unknown ticker returns 0" {
    try std.testing.expectEqual(@as(i64, 0), fixturePriceCents("ZZZZ"));
    try std.testing.expectEqual(@as(i64, 0), fixturePriceCents(""));
}

// --- Helpers to build a basket with a matching account_id for tests ---

fn buildAiBasket(account_id: u32, target_notional_cents: i64) !basket_mod.Basket {
    var input = thesis.fixtures.ai_infrastructure;
    input.account_id = account_id;
    input.target_notional_cents = target_notional_cents;
    const hash = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    return basket_mod.build(intent, hash);
}

fn countNonZeroShareLineItems(ticket: *const TradeTicket) u8 {
    var count: u8 = 0;
    for (ticket.line_items[0..ticket.line_item_count]) |li| {
        if (li.estimated_shares > 0) count += 1;
    }
    return count;
}

// --- Acceptance: USD 2,000 buy is allowed in cash-rich account ---

test "preview: USD 2,000 AI infrastructure BUY is allowed in cash-rich account" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.allowed, ticket.status);
    try std.testing.expectEqual(@as(u8, 0), ticket.guardrail_failure_count);
    try std.testing.expect(ticket.ticket_id != 0);
}

// --- Acceptance: exact USD 25,000 BUY is blocked when max affordable is lower ---

test "preview: exact USD 25,000 BUY is blocked with day_notional_exceeded and max_affordable" {
    var account = portfolio.fixtures.cash_rich;
    account.day_notional_used_cents = 1; // remaining daily notional = USD 24,999.99

    const b = try buildAiBasket(account.account_id, 2_500_000);
    const ticket = try preview(
        &b,
        &account,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);
    try std.testing.expect(ticket.guardrail_failure_count > 0);
    try std.testing.expectEqual(@as(i64, 2_499_999), ticket.max_affordable_cents);

    var found = false;
    for (ticket.guardrail_failures[0..ticket.guardrail_failure_count]) |f| {
        if (f == .day_notional_exceeded) found = true;
    }
    try std.testing.expect(found);
}

// --- Acceptance: blocked ticket cannot be paper-placed (T7, T8) ---

test "execute: blocked ticket returns TicketBlocked" {
    var account = portfolio.fixtures.cash_rich;
    account.day_notional_used_cents = 1;
    const b = try buildAiBasket(account.account_id, 2_500_000);
    const ticket = try preview(
        &b,
        &account,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);
    try std.testing.expectError(
        PaperExecutionError.TicketBlocked,
        execute(&ticket, &account, 1, 1_720_000_000_000_000_000),
    );
}

// --- Paper execution (T6) ---

test "execute: allowed USD 2,000 BUY produces filled result with cash decrease" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.allowed, ticket.status);
    const result = try execute(&ticket, &portfolio.fixtures.cash_rich, 1, 1_720_000_000_000_000_000);

    try std.testing.expectEqual(ticket.ticket_id, result.ticket_id);
    try std.testing.expectEqual(portfolio.fixtures.cash_rich.account_id, result.account_id);
    try std.testing.expectEqual(@as(u64, 1_720_000_000_000_000_000), result.executed_at_ns);
    try std.testing.expect(result.total_fill_notional_cents > 0);
    // Fills cannot exceed target notional.
    try std.testing.expect(result.total_fill_notional_cents <= ticket.target_notional_cents);
    // Cash decreases on BUY.
    try std.testing.expectEqual(
        portfolio.fixtures.cash_rich.cash_cents - result.total_fill_notional_cents,
        result.resulting_cash_cents,
    );
    try std.testing.expect(result.resulting_cash_cents < portfolio.fixtures.cash_rich.cash_cents);
    try std.testing.expectEqual(
        countNonZeroShareLineItems(&ticket),
        result.resulting_holding_count,
    );
    try std.testing.expect(result.paper_order_id != 0);
}

test "execute: paper_order_id is stable (same inputs produce same hash)" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    const r1 = try execute(&ticket, &portfolio.fixtures.cash_rich, 42, 1_720_000_000_000_000_100);
    const r2 = try execute(&ticket, &portfolio.fixtures.cash_rich, 42, 1_720_000_000_000_000_100);
    try std.testing.expectEqual(r1.paper_order_id, r2.paper_order_id);
}

test "execute: paper_order_id differs when paper_seq differs" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    const r1 = try execute(&ticket, &portfolio.fixtures.cash_rich, 1, 1_720_000_000_000_000_100);
    const r2 = try execute(&ticket, &portfolio.fixtures.cash_rich, 2, 1_720_000_000_000_000_100);
    try std.testing.expect(r1.paper_order_id != r2.paper_order_id);
}

test "execute: paper_order_id differs when executed_at_ns differs" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    const r1 = try execute(&ticket, &portfolio.fixtures.cash_rich, 1, 1_720_000_000_000_000_100);
    const r2 = try execute(&ticket, &portfolio.fixtures.cash_rich, 1, 1_720_000_000_000_000_101);
    try std.testing.expect(r1.paper_order_id != r2.paper_order_id);
}

test "execute: account mismatch on execute returns AccountMismatch" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectError(
        PaperExecutionError.AccountMismatch,
        execute(&ticket, &portfolio.fixtures.low_cash, 1, 1_720_000_000_000_000_000),
    );
}

// --- Sell preview (T3) ---

test "preview: SELL preview builds line items with sell side for owned positions" {
    const b = try buildAiBasket(portfolio.fixtures.technology_heavy.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.technology_heavy,
        .sell,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.allowed, ticket.status);
    for (ticket.line_items[0..ticket.line_item_count]) |li| {
        try std.testing.expectEqual(portfolio.Side.sell, li.side);
    }
}

test "preview: SELL is blocked when the account does not hold the basket positions" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .sell,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);

    var found = false;
    for (ticket.guardrail_failures[0..ticket.guardrail_failure_count]) |f| {
        if (f == .insufficient_holdings) found = true;
    }
    try std.testing.expect(found);
}

test "execute: SELL increases resulting cash and decreases held shares" {
    const b = try buildAiBasket(portfolio.fixtures.technology_heavy.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.technology_heavy,
        .sell,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    const result = try execute(&ticket, &portfolio.fixtures.technology_heavy, 1, 1_720_000_000_000_000_000);
    try std.testing.expect(result.resulting_cash_cents > portfolio.fixtures.technology_heavy.cash_cents);
    if (ticket.line_items[0].estimated_shares > 0) {
        const before = portfolio.findHolding(&portfolio.fixtures.technology_heavy, ticket.line_items[0].tickerSlice()).?;
        const after_idx = findHoldingIndex(
            result.resulting_holdings[0..result.resulting_holding_count],
            ticket.line_items[0].tickerSlice(),
        ).?;
        try std.testing.expectEqual(
            before.share_count - ticket.line_items[0].estimated_shares,
            result.resulting_holdings[after_idx].share_count,
        );
    }
}

// --- Limit orders (T4) ---

test "preview: limit order with positive limit_price_cents is allowed (T4)" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .limit,
        .day,
        14_000, // USD 140 limit price per share
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.allowed, ticket.status);
    // All line items carry the limit price.
    for (ticket.line_items[0..ticket.line_item_count]) |li| {
        try std.testing.expectEqual(OrderType.limit, li.order_type);
        try std.testing.expectEqual(@as(i64, 14_000), li.limit_price_cents);
    }
}

test "preview: limit order with zero limit_price_cents blocks with limit_price_required (T4)" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .limit,
        .day,
        0, // invalid
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);

    var found = false;
    for (ticket.guardrail_failures[0..ticket.guardrail_failure_count]) |f| {
        if (f == .limit_price_required) found = true;
    }
    try std.testing.expect(found);
}

test "preview: limit order with negative limit_price_cents blocks" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .limit,
        .day,
        -1,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);
}

test "computeTicketHash: different limit prices produce different ticket_id" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const t1 = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .limit, .day, 14_000, &.{}, &.{}, 1);
    const t2 = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .limit, .day, 14_500, &.{}, &.{}, 1);
    try std.testing.expect(t1.ticket_id != t2.ticket_id);
}

// --- Affordability guardrails (T5) ---

test "preview: low_cash account blocks BUY with insufficient_buying_power" {
    const b = try buildAiBasket(portfolio.fixtures.low_cash.account_id, 200_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.low_cash,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);

    var found = false;
    for (ticket.guardrail_failures[0..ticket.guardrail_failure_count]) |f| {
        if (f == .insufficient_buying_power) found = true;
    }
    try std.testing.expect(found);
    // max_affordable_cents reflects what the account can actually afford.
    try std.testing.expectEqual(portfolio.fixtures.low_cash.buying_power_cents, ticket.max_affordable_cents);
}

test "preview: restricted_account blocks BUY with open_order_limit" {
    const b = try buildAiBasket(portfolio.fixtures.restricted_account.account_id, 10_000);
    const ticket = try preview(
        &b,
        &portfolio.fixtures.restricted_account,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);

    var found = false;
    for (ticket.guardrail_failures[0..ticket.guardrail_failure_count]) |f| {
        if (f == .open_order_limit) found = true;
    }
    try std.testing.expect(found);
}

test "preview: month limit exceeded blocks BUY with month_notional_exceeded" {
    var account = portfolio.fixtures.cash_rich;
    account.month_notional_used_cents = account.month_notional_limit_cents; // fully used

    const b = try buildAiBasket(account.account_id, 200_000);
    const ticket = try preview(
        &b,
        &account,
        .buy,
        .market,
        .day,
        0,
        &.{},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);

    var found = false;
    for (ticket.guardrail_failures[0..ticket.guardrail_failure_count]) |f| {
        if (f == .month_notional_exceeded) found = true;
    }
    try std.testing.expect(found);
}

// --- Same-day round-trip (T5) ---

test "preview: BUY blocked when instrument was sold today (round-trip)" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    // NVDA should be in the AI infrastructure basket (as an equity or via ETF).
    // We block any basket instrument that appears in same_day_opposite.
    // Find the first instrument in the basket and create a round-trip for it.
    try std.testing.expect(b.instrument_count > 0);
    const first_ticker = b.instruments[0].ticker;

    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .market,
        .day,
        0,
        &[1][cat.max_ticker_len]u8{first_ticker},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);

    var found = false;
    for (ticket.guardrail_failures[0..ticket.guardrail_failure_count]) |f| {
        if (f == .same_day_round_trip) found = true;
    }
    try std.testing.expect(found);
}

test "preview: BUY not blocked when same_day_opposite contains a different ticker" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    // "ZZZZ" is not a real catalog ticker and cannot be in the basket.
    var zzzz: [cat.max_ticker_len]u8 = std.mem.zeroes([cat.max_ticker_len]u8);
    @memcpy(zzzz[0..4], "ZZZZ");
    const ticket = try preview(
        &b,
        &portfolio.fixtures.cash_rich,
        .buy,
        .market,
        .day,
        0,
        &[1][cat.max_ticker_len]u8{zzzz},
        &.{},
        1,
    );
    try std.testing.expectEqual(TicketStatus.allowed, ticket.status);
}

// --- Minimum holding period (T5) ---

test "preview: SELL blocked when holding bought today (minimum_holding_period)" {
    const b = try buildAiBasket(portfolio.fixtures.technology_heavy.account_id, 200_000);
    // Use the first basket instrument to construct a holding with days_held = 0.
    try std.testing.expect(b.instrument_count > 0);
    const first_instrument = &b.instruments[0];
    const holding = HoldingRecord{
        .ticker = first_instrument.ticker,
        .ticker_len = first_instrument.ticker_len,
        .days_held = 0,
    };
    const ticket = try preview(
        &b,
        &portfolio.fixtures.technology_heavy,
        .sell,
        .market,
        .day,
        0,
        &.{},
        &[1]HoldingRecord{holding},
        1, // min 1 day
    );
    try std.testing.expectEqual(TicketStatus.blocked, ticket.status);

    var found = false;
    for (ticket.guardrail_failures[0..ticket.guardrail_failure_count]) |f| {
        if (f == .minimum_holding_period) found = true;
    }
    try std.testing.expect(found);
}

test "preview: SELL allowed when holding exceeds min holding period" {
    const b = try buildAiBasket(portfolio.fixtures.technology_heavy.account_id, 200_000);
    try std.testing.expect(b.instrument_count > 0);
    const first_instrument = &b.instruments[0];
    const holding = HoldingRecord{
        .ticker = first_instrument.ticker,
        .ticker_len = first_instrument.ticker_len,
        .days_held = 5,
    };
    const ticket = try preview(
        &b,
        &portfolio.fixtures.technology_heavy,
        .sell,
        .market,
        .day,
        0,
        &.{},
        &[1]HoldingRecord{holding},
        1, // min 1 day; 5 days held is sufficient
    );
    try std.testing.expectEqual(TicketStatus.allowed, ticket.status);
}

// --- Ticket content hash stability ---

test "computeTicketHash: same inputs produce same ticket_id" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const t1 = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .market, .day, 0, &.{}, &.{}, 1);
    const t2 = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .market, .day, 0, &.{}, &.{}, 1);
    try std.testing.expectEqual(t1.ticket_id, t2.ticket_id);
}

test "computeTicketHash: different side produces different ticket_id" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const buy_ticket = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .market, .day, 0, &.{}, &.{}, 1);
    const sell_ticket = try preview(&b, &portfolio.fixtures.cash_rich, .sell, .market, .day, 0, &.{}, &.{}, 1);
    try std.testing.expect(buy_ticket.ticket_id != sell_ticket.ticket_id);
}

// --- Line item properties ---

test "preview: all line items have non-zero fixture prices and estimated cost >= 0" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .market, .day, 0, &.{}, &.{}, 1);
    for (ticket.line_items[0..ticket.line_item_count]) |li| {
        try std.testing.expect(li.fixture_price_cents > 0);
        try std.testing.expect(li.estimated_cost_cents >= 0);
        try std.testing.expect(li.estimated_cost_cents <= li.target_notional_cents);
    }
}

test "preview: line items carry explicit market, venue, and sector scope" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .market, .day, 0, &.{}, &.{}, 1);
    for (ticket.line_items[0..ticket.line_item_count]) |li| {
        try std.testing.expectEqual(cat.Market.us, li.market);
        try std.testing.expect(isSupportedVenue(li.venue));
        try std.testing.expect(isSupportedSector(li.sector));
    }
}

test "preview: line_item_count matches basket instrument_count" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .market, .day, 0, &.{}, &.{}, 1);
    try std.testing.expectEqual(b.instrument_count, ticket.line_item_count);
}

test "preview: estimated_cost_cents sum does not exceed target_notional_cents" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .market, .day, 0, &.{}, &.{}, 1);
    try std.testing.expect(ticket.estimated_cost_cents <= ticket.target_notional_cents);
}

// --- AccountMismatch ---

test "preview: account_id mismatch returns AccountMismatch" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    try std.testing.expectError(
        TicketError.AccountMismatch,
        preview(&b, &portfolio.fixtures.low_cash, .buy, .market, .day, 0, &.{}, &.{}, 1),
    );
}

// --- PaperFilledLineItem correctness ---

test "execute: filled_shares * fill_price == fill_notional for each line item" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .market, .day, 0, &.{}, &.{}, 1);
    const result = try execute(&ticket, &portfolio.fixtures.cash_rich, 1, 1_720_000_000_000_000_000);
    for (result.filled_line_items[0..result.filled_line_item_count]) |fi| {
        try std.testing.expectEqual(
            @as(i64, fi.filled_shares) * fi.fill_price_cents,
            fi.fill_notional_cents,
        );
    }
}

test "execute: total_fill_notional_cents equals sum of fill_notional_cents" {
    const b = try buildAiBasket(portfolio.fixtures.cash_rich.account_id, 200_000);
    const ticket = try preview(&b, &portfolio.fixtures.cash_rich, .buy, .market, .day, 0, &.{}, &.{}, 1);
    const result = try execute(&ticket, &portfolio.fixtures.cash_rich, 1, 1_720_000_000_000_000_000);
    var sum: i64 = 0;
    for (result.filled_line_items[0..result.filled_line_item_count]) |fi| {
        sum += fi.fill_notional_cents;
    }
    try std.testing.expectEqual(sum, result.total_fill_notional_cents);
}
