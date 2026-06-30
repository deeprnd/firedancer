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
    // Collect theme-matching instruments: union over all intent themes, dedup by pointer.
    var theme_candidates: [catalog.catalog.len]*const catalog.InstrumentEntry = undefined;
    var theme_n: usize = 0;
    for (intent.themes.values[0..intent.themes.count]) |theme_id| {
        var buf: [catalog.catalog.len]*const catalog.InstrumentEntry = undefined;
        const m = catalog.filterByTheme(theme_id, &buf);
        for (buf[0..m]) |entry| {
            var already = false;
            for (theme_candidates[0..theme_n]) |existing| {
                if (existing == entry) { already = true; break; }
            }
            if (!already and theme_n < catalog.catalog.len) {
                theme_candidates[theme_n] = entry;
                theme_n += 1;
            }
        }
    }

    var screening = BasketScreening{};

    // Check explicitly requested tickers for restriction and theme membership.
    for (intent.requested_tickers[0..@as(usize, intent.requested_ticker_count)]) |slot| {
        const ticker_str = std.mem.sliceTo(&slot, 0);
        if (ticker_str.len == 0) continue;
        if (isAlreadyRejected(&screening, ticker_str)) continue;
        const entry = catalog.lookupByTicker(ticker_str) orelse continue;
        if (entry.restricted) {
            addRejected(&screening, entry, .restricted_instrument, restrictionMsg(entry.restriction_reason));
        } else if (!isInThemeCandidates(theme_candidates[0..theme_n], entry)) {
            addRejected(&screening, entry, .wrong_theme, "Ticker does not match any intent theme");
        }
    }

    for (theme_candidates[0..theme_n]) |entry| {
        if (entry.restricted) {
            if (!isAlreadyRejected(&screening, entry.ticker[0..entry.ticker_len])) {
                addRejected(&screening, entry, .restricted_instrument, restrictionMsg(entry.restriction_reason));
            }
            continue;
        }
        if (!intent.allowed_asset_classes.has(entry.asset_class)) {
            addRejected(&screening, entry, .wrong_asset_class, "Asset class not eligible");
            continue;
        }
        if (!intent.allowed_instrument_types.has(entry.instrument_type)) {
            addRejected(&screening, entry, .wrong_instrument_type, "Instrument type not eligible (stock/ETF only)");
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
        if (intent.sectors.count > 0 and !sectorAllowed(entry, intent.sectors)) {
            addRejected(&screening, entry, .wrong_sector, "Sector not in intent sector filter");
            continue;
        }
        if (intent.industries.count > 0 and !industryAllowed(entry, intent.industries)) {
            addRejected(&screening, entry, .wrong_industry, "Industry not in intent industry filter");
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

fn sectorAllowed(entry: *const catalog.InstrumentEntry, sectors: thesis.ClassificationRefList) bool {
    for (sectors.values[0..sectors.count]) |sector| {
        if (entry.sectors.has(sector)) return true;
    }
    return false;
}

fn industryAllowed(entry: *const catalog.InstrumentEntry, industries: thesis.ClassificationRefList) bool {
    for (industries.values[0..industries.count]) |industry| {
        if (entry.industries.has(industry)) return true;
    }
    return false;
}

fn isInThemeCandidates(candidates: []*const catalog.InstrumentEntry, entry: *const catalog.InstrumentEntry) bool {
    for (candidates) |existing| {
        if (existing == entry) return true;
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

test "screenBasketIntent: unknown classification in sector filter causes no candidates to match" {
    // A sector filter with a code that no catalog entry carries → all theme candidates rejected.
    var input = thesis.fixtures.ai_infrastructure;
    var sector_refs = thesis.ClassificationRefList{};
    sector_refs.append(
        thesis.ClassificationRef.init("gics_sector", 2025, "real_estate") catch unreachable,
    ) catch unreachable;
    input.sector_filters = sector_refs;
    const intent = try thesis.normalize(input);
    const screening = screenBasketIntent(intent);

    // No AI infrastructure instruments are in real_estate sector.
    try std.testing.expectEqual(@as(u8, 0), screening.candidate_count);
    // All non-restricted theme candidates should be rejected with wrong_sector.
    var found_wrong_sector = false;
    for (screening.rejectedSlice()) |rejected| {
        if (rejected.reason_code == basket.RejectionReason.wrong_sector) {
            found_wrong_sector = true;
        }
    }
    try std.testing.expect(found_wrong_sector);
}
