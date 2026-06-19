const std = @import("std");
const basket = @import("basket");
const catalog = basket.catalog;
const portfolio = @import("portfolio");
const thesis = @import("thesis");
const trade_ticket = @import("trade_ticket");

pub const BasketScreening = struct {
    candidates: [basket.max_basket_instruments]*const catalog.InstrumentEntry = undefined,
    candidate_count: u8 = 0,
    rejected: [basket.max_rejected_instruments]basket.RejectedCandidate = std.mem.zeroes([basket.max_rejected_instruments]basket.RejectedCandidate),
    rejected_count: u8 = 0,

    pub fn candidateSlice(self: *const BasketScreening) []const *const catalog.InstrumentEntry {
        return self.candidates[0..self.candidate_count];
    }

    pub fn rejectedSlice(self: *const BasketScreening) []const basket.RejectedCandidate {
        return self.rejected[0..self.rejected_count];
    }
};

pub const TradeGuardrailDecision = struct {
    policy_outcome: trade_ticket.PolicyOutcome,
    blocked_reasons: [trade_ticket.max_blocked_reasons]trade_ticket.BlockedReason = std.mem.zeroes([trade_ticket.max_blocked_reasons]trade_ticket.BlockedReason),
    blocked_reason_count: u8 = 0,
    effective_max_paper_trade_cents: i64,
};

pub fn buildBasket(intent: thesis.InvestorIntent, thesis_id: u64) basket.BasketError!basket.Basket {
    const screening = screenBasketIntent(intent);
    return basket.buildFromScreening(
        intent,
        thesis_id,
        screening.candidateSlice(),
        screening.rejectedSlice(),
    );
}

pub fn screenBasketIntent(intent: thesis.InvestorIntent) BasketScreening {
    var theme_buf: [catalog.catalog.len]*const catalog.InstrumentEntry = undefined;
    const theme_n = catalog.filterByTheme(intent.theme, &theme_buf);

    var screening = BasketScreening{};

    for (intent.requested_tickers[0..@as(usize, intent.requested_ticker_count)]) |slot| {
        const ticker_str = std.mem.sliceTo(&slot, 0);
        if (ticker_str.len == 0) continue;
        if (isAlreadyRejected(&screening, ticker_str)) continue;
        const entry = catalog.lookupByTicker(ticker_str) orelse continue;
        if (entry.restricted) {
            addRejected(&screening, entry, .restricted_instrument, restrictionMsg(entry.restriction_reason));
        }
    }

    for (theme_buf[0..theme_n]) |entry| {
        if (entry.restricted) {
            if (!isAlreadyRejected(&screening, entry.ticker[0..entry.ticker_len])) {
                addRejected(&screening, entry, .restricted_instrument, restrictionMsg(entry.restriction_reason));
            }
            continue;
        }
        if (!intent.allowed_asset_classes.has(entry.asset_class)) {
            addRejected(&screening, entry, .wrong_asset_class, "Asset class not eligible (equity/ETF only)");
            continue;
        }
        if (entry.market != intent.market) {
            addRejected(&screening, entry, .wrong_market, "Market not in US scope");
            continue;
        }
        if (!venueAllowed(entry.venue, intent.venues[0..@as(usize, intent.venue_count)])) {
            addRejected(&screening, entry, .wrong_venue, "Venue not NYSE or NASDAQ");
            continue;
        }
        if (screening.candidate_count < basket.max_basket_instruments) {
            screening.candidates[screening.candidate_count] = entry;
            screening.candidate_count += 1;
        }
    }

    return screening;
}

pub fn evaluateTradeGuardrails(
    requested_notional_cents: i64,
    affordability: portfolio.AffordabilityResult,
    policy_max_notional_per_order_cents: i64,
) TradeGuardrailDecision {
    const effective_max = @min(
        affordability.max_affordable_cents,
        policy_max_notional_per_order_cents,
    );
    var decision = TradeGuardrailDecision{
        .policy_outcome = if (requested_notional_cents <= effective_max) .allow else .deny,
        .effective_max_paper_trade_cents = effective_max,
    };
    if (decision.policy_outcome == .deny) {
        if (deriveBlockedReason(
            requested_notional_cents,
            affordability,
            policy_max_notional_per_order_cents,
        )) |reason| {
            decision.blocked_reasons[0] = reason;
            decision.blocked_reason_count = 1;
        }
    }
    return decision;
}

pub fn applyTradeGuardrails(
    ticket: *trade_ticket.TradeTicket,
    affordability: portfolio.AffordabilityResult,
    policy_max_notional_per_order_cents: i64,
) void {
    const decision = evaluateTradeGuardrails(
        ticket.target_notional_cents,
        affordability,
        policy_max_notional_per_order_cents,
    );
    trade_ticket.applyPolicyDecision(
        ticket,
        decision.policy_outcome,
        decision.blocked_reasons[0..decision.blocked_reason_count],
        decision.effective_max_paper_trade_cents,
    );
}

fn deriveBlockedReason(
    requested_notional_cents: i64,
    affordability: portfolio.AffordabilityResult,
    policy_max_notional_per_order_cents: i64,
) ?trade_ticket.BlockedReason {
    if (requested_notional_cents > policy_max_notional_per_order_cents and
        affordability.outcome == .allow)
    {
        return .{
            .code = .per_order_notional_exceeded,
            .failed_scope_dim = .per_order_notional,
            .requested_cents = requested_notional_cents,
            .limit_cents = policy_max_notional_per_order_cents,
        };
    }

    return switch (affordability.outcome) {
        .allow => null,
        .deny_open_order_limit,
        .deny_invalid_notional,
        => null,
        .deny_insufficient_buying_power => .{
            .code = .buying_power_exceeded,
            .failed_scope_dim = .buying_power,
            .requested_cents = requested_notional_cents,
            .limit_cents = affordability.max_affordable_cents,
        },
        .deny_day_limit_exceeded => .{
            .code = .daily_notional_exceeded,
            .failed_scope_dim = .day_notional,
            .requested_cents = requested_notional_cents,
            .limit_cents = affordability.remaining_daily_notional_cents,
        },
        .deny_month_limit_exceeded => .{
            .code = .monthly_notional_exceeded,
            .failed_scope_dim = .month_notional,
            .requested_cents = requested_notional_cents,
            .limit_cents = affordability.remaining_monthly_notional_cents,
        },
    };
}

fn venueAllowed(venue: catalog.Venue, allowed: []const thesis.Venue) bool {
    for (allowed) |allowed_venue| {
        if (allowed_venue == venue) return true;
    }
    return false;
}

fn isAlreadyRejected(screening: *const BasketScreening, ticker_str: []const u8) bool {
    for (screening.rejected[0..screening.rejected_count]) |*rejected| {
        if (std.mem.eql(u8, rejected.ticker[0..rejected.ticker_len], ticker_str)) return true;
    }
    return false;
}

fn addRejected(
    screening: *BasketScreening,
    entry: *const catalog.InstrumentEntry,
    code: basket.RejectionReason,
    reason_str: []const u8,
) void {
    if (screening.rejected_count >= basket.max_rejected_instruments) return;
    const rejected = &screening.rejected[screening.rejected_count];
    rejected.ticker = entry.ticker;
    rejected.ticker_len = entry.ticker_len;
    rejected.reason_code = code;
    rejected.reason = std.mem.zeroes([basket.max_reason_len]u8);
    const len = @min(reason_str.len, basket.max_reason_len);
    @memcpy(rejected.reason[0..len], reason_str[0..len]);
    rejected.reason_len = @intCast(len);
    screening.rejected_count += 1;
}

fn restrictionMsg(reason: catalog.RestrictionReason) []const u8 {
    return switch (reason) {
        .none => "Restricted (unexpected reason code)",
        .leveraged_etf => "Restricted: leveraged ETF",
        .inverse_etf => "Restricted: inverse ETF",
        .options_contract => "Restricted: options contract",
        .futures_contract => "Restricted: futures contract",
        .non_us_venue => "Restricted: non-US venue",
        .manual_denylist => "Restricted: manual denylist",
    };
}

test "screenBasketIntent rejects restricted products and keeps eligible AI infrastructure instruments" {
    const intent = try thesis.normalize(thesis.fixtures.ai_infrastructure);
    const screening = screenBasketIntent(intent);

    try std.testing.expect(screening.candidate_count >= 4);
    try std.testing.expect(screening.rejected_count >= 2);

    var found_soxl = false;
    var found_bulz = false;
    for (screening.rejectedSlice()) |rejected| {
        if (std.mem.eql(u8, rejected.tickerSlice(), "SOXL")) found_soxl = true;
        if (std.mem.eql(u8, rejected.tickerSlice(), "BULZ")) found_bulz = true;
    }
    try std.testing.expect(found_soxl);
    try std.testing.expect(found_bulz);
}

test "evaluateTradeGuardrails returns per-order denial for oversized allowed account" {
    const affordability = portfolio.checkAffordability(&portfolio.fixtures.cash_rich, 2_500_000);
    const decision = evaluateTradeGuardrails(2_500_000, affordability, 250_000);

    try std.testing.expectEqual(trade_ticket.PolicyOutcome.deny, decision.policy_outcome);
    try std.testing.expectEqual(@as(u8, 1), decision.blocked_reason_count);
    try std.testing.expectEqual(trade_ticket.BlockedReasonCode.per_order_notional_exceeded, decision.blocked_reasons[0].code);
    try std.testing.expectEqual(@as(i64, 250_000), decision.effective_max_paper_trade_cents);
}
