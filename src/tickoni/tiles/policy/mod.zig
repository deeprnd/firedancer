const std = @import("std");
const basket = @import("basket");
const catalog = basket.catalog;
const portfolio = @import("portfolio");
const thesis = @import("thesis");
const trade_ticket = @import("trade_ticket");

pub const BasketScreening = basket.BasketScreening;

pub const TradeGuardrailDecision = struct {
    policy_outcome: trade_ticket.PolicyOutcome,
    blocked_reasons: [trade_ticket.max_blocked_reasons]trade_ticket.BlockedReason = std.mem.zeroes([trade_ticket.max_blocked_reasons]trade_ticket.BlockedReason),
    blocked_reason_count: u8 = 0,
    effective_max_paper_trade_cents: i64,
};

pub fn buildBasket(intent: thesis.InvestorIntent, thesis_id: u64) basket.BasketError!basket.Basket {
    return basket.build(intent, thesis_id);
}

pub fn screenBasketIntent(intent: thesis.InvestorIntent) BasketScreening {
    return basket.screenIntent(intent);
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

test "screenBasketIntent rejects ETFs when intent allows only stocks" {
    var input = thesis.fixtures.ai_infrastructure;
    input.asset_class_prefs = thesis.assetClassList(.{.equity});
    input.instrument_type_prefs = thesis.instrumentTypeList(.{.stock});
    const intent = try thesis.normalize(input);
    const screening = screenBasketIntent(intent);

    try std.testing.expect(screening.candidate_count > 0);
    for (screening.candidateSlice()) |entry| {
        try std.testing.expectEqual(catalog.InstrumentType.stock, entry.instrument_type);
    }

    var found_wrong_type = false;
    for (screening.rejectedSlice()) |rejected| {
        if (std.mem.eql(u8, rejected.tickerSlice(), "BOTZ") or
            std.mem.eql(u8, rejected.tickerSlice(), "SOXX"))
        {
            try std.testing.expectEqual(basket.RejectionReason.wrong_instrument_type, rejected.reason_code);
            found_wrong_type = true;
        }
    }
    try std.testing.expect(found_wrong_type);
}

test "evaluateTradeGuardrails returns per-order denial for oversized allowed account" {
    const affordability = portfolio.checkAffordability(&portfolio.fixtures.cash_rich, 2_500_000);
    const decision = evaluateTradeGuardrails(2_500_000, affordability, 250_000);

    try std.testing.expectEqual(trade_ticket.PolicyOutcome.deny, decision.policy_outcome);
    try std.testing.expectEqual(@as(u8, 1), decision.blocked_reason_count);
    try std.testing.expectEqual(trade_ticket.BlockedReasonCode.per_order_notional_exceeded, decision.blocked_reasons[0].code);
    try std.testing.expectEqual(@as(i64, 250_000), decision.effective_max_paper_trade_cents);
}

test "screenBasketIntent: multi-theme union finds more candidates than single theme" {
    // ai_and_semiconductors covers two themes; must include at least what ai_infrastructure alone covers.
    const multi_intent = try thesis.normalize(thesis.fixtures.ai_and_semiconductors);
    const ai_intent = try thesis.normalize(thesis.fixtures.ai_infrastructure);

    const multi = screenBasketIntent(multi_intent);
    const single = screenBasketIntent(ai_intent);

    // Multi-theme union must have at least as many eligible candidates as single.
    try std.testing.expect(multi.candidate_count >= single.candidate_count);
}

test "screenBasketIntent: sector filter rejects instruments outside the allowed sector" {
    const intent = try thesis.normalize(thesis.fixtures.ai_infrastructure_it_sector);
    const screening = screenBasketIntent(intent);

    // All candidates must be in the information_technology sector.
    const it_ref = catalog.ClassificationRef.init("gics_sector", 2025, "information_technology") catch unreachable;
    for (screening.candidateSlice()) |entry| {
        try std.testing.expect(entry.sectors.has(it_ref));
    }

    // At least one rejection must have wrong_sector code.
    var found_wrong_sector = false;
    for (screening.rejectedSlice()) |rejected| {
        if (rejected.reason_code == basket.RejectionReason.wrong_sector) {
            found_wrong_sector = true;
        }
    }
    try std.testing.expect(found_wrong_sector);
}

test "screenBasketIntent: industry filter rejects instruments outside the allowed industry" {
    var input = thesis.fixtures.ai_infrastructure;
    var industry_refs = thesis.ClassificationRefList{};
    industry_refs.append(
        thesis.ClassificationRef.init("gics_industry", 2025, "semiconductors") catch unreachable,
    ) catch unreachable;
    input.industry_filters = industry_refs;
    const intent = try thesis.normalize(input);
    const screening = screenBasketIntent(intent);

    // All candidates must be in the semiconductors industry.
    const semi_ref = catalog.ClassificationRef.init("gics_industry", 2025, "semiconductors") catch unreachable;
    for (screening.candidateSlice()) |entry| {
        try std.testing.expect(entry.industries.has(semi_ref));
    }

    // BOTZ (robotics_and_ai industry) must be rejected with wrong_industry.
    var found_botz_wrong_industry = false;
    for (screening.rejectedSlice()) |rejected| {
        if (std.mem.eql(u8, rejected.tickerSlice(), "BOTZ")) {
            try std.testing.expectEqual(basket.RejectionReason.wrong_industry, rejected.reason_code);
            found_botz_wrong_industry = true;
        }
    }
    try std.testing.expect(found_botz_wrong_industry);
}

test "screenBasketIntent: sector and industry are distinct dimensions — sector pass does not imply industry pass" {
    // Use a sector filter (information_technology) with an industry filter (semiconductors).
    // MSFT is IT sector but systems_software industry — should be rejected by industry filter.
    var input = thesis.fixtures.ai_infrastructure;
    var sector_refs = thesis.ClassificationRefList{};
    sector_refs.append(
        thesis.ClassificationRef.init("gics_sector", 2025, "information_technology") catch unreachable,
    ) catch unreachable;
    var industry_refs = thesis.ClassificationRefList{};
    industry_refs.append(
        thesis.ClassificationRef.init("gics_industry", 2025, "semiconductors") catch unreachable,
    ) catch unreachable;
    input.sector_filters = sector_refs;
    input.industry_filters = industry_refs;
    const intent = try thesis.normalize(input);
    const screening = screenBasketIntent(intent);

    // MSFT must not appear in candidates (systems_software industry, not semiconductors).
    for (screening.candidateSlice()) |entry| {
        try std.testing.expect(!std.mem.eql(u8, entry.tickerSlice(), "MSFT"));
    }

    // MSFT must appear in rejected with wrong_industry.
    var found_msft_wrong_industry = false;
    for (screening.rejectedSlice()) |rejected| {
        if (std.mem.eql(u8, rejected.tickerSlice(), "MSFT")) {
            try std.testing.expectEqual(basket.RejectionReason.wrong_industry, rejected.reason_code);
            found_msft_wrong_industry = true;
        }
    }
    try std.testing.expect(found_msft_wrong_industry);
}

test "screenBasketIntent: wrong_theme rejection for requested ticker not matching any intent theme" {
    var input = thesis.fixtures.broad_market;
    const wcld = "WCLD";
    @memset(&input.requested_tickers[0], 0);
    @memcpy(input.requested_tickers[0][0..wcld.len], wcld);
    input.requested_ticker_count = 1;
    const intent = try thesis.normalize(input);
    const screening = screenBasketIntent(intent);

    // WCLD (cloud theme) is not in broad_market theme — must appear rejected with wrong_theme.
    var found_wrong_theme = false;
    for (screening.rejectedSlice()) |rejected| {
        if (std.mem.eql(u8, rejected.tickerSlice(), "WCLD")) {
            try std.testing.expectEqual(basket.RejectionReason.wrong_theme, rejected.reason_code);
            found_wrong_theme = true;
        }
    }
    try std.testing.expect(found_wrong_theme);
}

test "screenBasketIntent: unknown classification in sector filter fails closed during normalize" {
    var input = thesis.fixtures.ai_infrastructure;
    var sector_refs = thesis.ClassificationRefList{};
    sector_refs.append(
        thesis.ClassificationRef.init("gics_sector", 2025, "real_estate") catch unreachable,
    ) catch unreachable;
    input.sector_filters = sector_refs;
    try std.testing.expectError(thesis.ThesisError.MalformedClassification, thesis.normalize(input));
}

test "screenBasketIntent: unknown requested ticker fails closed during normalize" {
    var input = thesis.fixtures.ai_infrastructure;
    input.requested_ticker_count = 1;
    @memset(&input.requested_tickers[0], 0);
    @memcpy(input.requested_tickers[0][0..4], "ZZZZ");
    try std.testing.expectError(thesis.ThesisError.MalformedClassification, thesis.normalize(input));
}
