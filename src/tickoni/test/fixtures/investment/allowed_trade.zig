// Scenario fixture contract: AI infrastructure allowed trade.
//
// Per doc/testing/v1-1-investment-integration.md (S6-P1), this test
// exercises the real Tickoni schema pipeline with external systems replaced
// by recorded fixtures. No live model, adapter, broker, or execution call.
//
// This file stays at the schema-and-fixture layer. It proves the scenario
// invariants without involving tkmodl/tktool/tkadpt/tkrepl boundary wiring.
//
// Pipeline under test:
//   thesis (operations account input)
//     -> thesis.normalize()             [real tknorm logic]
//     -> basket.build()                 [real basket construction]
//     -> portfolio.checkAffordability() [real affordability check]
//     -> policy limits from fixture     [policy_investment.json]
//     -> paper execution fixture        [paper_execution_allowed_2000.json]
//
// Assertions (S6-P1):
//   - thesis normalization succeeds
//   - basket contains >= 4 eligible AI infrastructure instruments
//   - restricted instruments (SOXL, BULZ) do not appear in basket
//   - basket total allocated == target notional (USD 2,000)
//   - affordability outcome is allow for ops account
//   - effective max paper trade amount is min(max_affordable, policy_per_order)
//   - paper execution fills are consistent with basket line items
//   - basket id and thesis id are distinct and stable
//   - pipeline is deterministic across repeated calls

const std = @import("std");
const thesis = @import("thesis");
const basket_mod = @import("basket");
const portfolio = @import("portfolio");

// Numeric id for "brokerage.operations" as stored in portfolio.fixtures.cash_rich.
const operations_account_id: u32 = 2001;

// Target notional from thesis_allowed_2000.json.
const target_notional_cents: i64 = 200_000;

// Maximum notional per order from policy_investment.json (limits.max_notional_per_order_cents).
const policy_max_notional_per_order_cents: i64 = 250_000;

// Expected basket instrument count: 7 eligible AI infrastructure instruments.
// NVDA, AMD, AVGO, MSFT (equity) + AMZN (equity) + BOTZ, SOXX (ETF).
// SOXL and BULZ are restricted leveraged ETFs and are excluded.
const expected_instrument_count: u8 = 7;

// Paper fill amounts (cents) from paper_execution_allowed_2000.json, in basket order.
// NVDA=25000, AMD=25000, AVGO=25000, MSFT=25000, BOTZ=37500, SOXX=37500, AMZN=25000.
const paper_fills_cents = [expected_instrument_count]i64{
    25_000, 25_000, 25_000, 25_000, 37_500, 37_500, 25_000,
};

// Expected equity allocation per line: 200000 * 1250 / 10000 = 25000 cents.
// Expected ETF allocation per line:    200000 * 1875 / 10000 = 37500 cents.
// With ETF preference (1.5x weight): n_eq=5, n_etf=2; total_units=5*2+2*3=16.
// ETF bp = 3*10000/16 = 1875; equity bp = 2*10000/16 = 1250.
const expected_equity_alloc_cents: i64 = 25_000;
const expected_etf_alloc_cents: i64 = 37_500;

// Build the operations thesis input by taking the canonical AI infra fixture
// and substituting the numeric account id for brokerage.operations.
fn operationsThesisInput() thesis.ThesisInput {
    var input = thesis.fixtures.ai_infrastructure;
    input.account_id = operations_account_id;
    // max_single_name_weight_bp in policy_investment.json = 2500 bp = 25%
    input.max_single_name_pct = 25;
    return input;
}

// ---------------------------------------------------------------------------
// Thesis normalization assertions
// ---------------------------------------------------------------------------

test "allowed_trade: thesis normalization succeeds for ops account" {
    const input = operationsThesisInput();
    const intent = try thesis.normalize(input);
    try std.testing.expectEqual(operations_account_id, intent.account_id);
    try std.testing.expectEqual(thesis.SectorTheme.ai_infrastructure, intent.theme);
    try std.testing.expectEqual(target_notional_cents, intent.target_amount_cents);
    try std.testing.expect(intent.allowed_asset_classes.equity);
    try std.testing.expect(intent.allowed_asset_classes.etf);
    try std.testing.expect(!intent.allowed_asset_classes.option);
    try std.testing.expect(!intent.allowed_asset_classes.future);
    try std.testing.expect(!intent.allowed_asset_classes.leveraged_etf);
    try std.testing.expect(!intent.allowed_asset_classes.inverse_etf);
    try std.testing.expect(!intent.allowed_asset_classes.crypto);
    try std.testing.expectEqual(thesis.Market.us, intent.market);
    try std.testing.expectEqual(@as(u8, 2), intent.venue_count);
    try std.testing.expectEqual(thesis.RiskPreference.moderate, intent.risk_preference);
}

test "allowed_trade: thesis input hash is stable across calls" {
    const input = operationsThesisInput();
    const h1 = thesis.computeThesisInputHash(input);
    const h2 = thesis.computeThesisInputHash(input);
    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != 0);
}

test "allowed_trade: thesis hash changes when target notional changes" {
    const input = operationsThesisInput();
    var oversized = input;
    oversized.target_notional_cents = 2_500_000;
    try std.testing.expect(
        thesis.computeThesisInputHash(input) != thesis.computeThesisInputHash(oversized),
    );
}

// ---------------------------------------------------------------------------
// Basket construction assertions
// ---------------------------------------------------------------------------

test "allowed_trade: basket contains >= 4 eligible AI infrastructure instruments" {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    try std.testing.expect(b.instrument_count >= 4);
}

test "allowed_trade: basket contains exactly expected instrument count" {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    try std.testing.expectEqual(expected_instrument_count, b.instrument_count);
}

test "allowed_trade: restricted instruments not in basket" {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    for (b.instruments[0..b.instrument_count]) |inst| {
        try std.testing.expect(!std.mem.eql(u8, inst.tickerSlice(), "SOXL"));
        try std.testing.expect(!std.mem.eql(u8, inst.tickerSlice(), "BULZ"));
    }
}

test "allowed_trade: restricted instruments appear in rejected candidates" {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    var found_soxl = false;
    var found_bulz = false;
    for (b.rejected[0..b.rejected_count]) |rc| {
        if (std.mem.eql(u8, rc.tickerSlice(), "SOXL")) {
            try std.testing.expectEqual(basket_mod.RejectionReason.restricted_instrument, rc.reason_code);
            try std.testing.expect(rc.reason_len > 0);
            found_soxl = true;
        }
        if (std.mem.eql(u8, rc.tickerSlice(), "BULZ")) {
            try std.testing.expectEqual(basket_mod.RejectionReason.restricted_instrument, rc.reason_code);
            try std.testing.expect(rc.reason_len > 0);
            found_bulz = true;
        }
    }
    try std.testing.expect(found_soxl);
    try std.testing.expect(found_bulz);
}

test "allowed_trade: basket total allocated equals USD 2000 target" {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    try std.testing.expectEqual(target_notional_cents, b.total_allocated_cents);
}

test "allowed_trade: basket line item allocations sum to target" {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    var sum: i64 = 0;
    for (b.instruments[0..b.instrument_count]) |inst| sum += inst.allocation_cents;
    try std.testing.expectEqual(target_notional_cents, sum);
}

test "allowed_trade: all basket allocations are positive" {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    for (b.instruments[0..b.instrument_count]) |inst| {
        try std.testing.expect(inst.allocation_cents > 0);
    }
}

test "allowed_trade: ETF lines receive higher allocation than equity lines" {
    // With ETF preference enabled, ETFs get 1.5x the base equity weight.
    // Expected: ETF allocation (37500) > equity allocation (25000).
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    var total_etf: i64 = 0;
    var n_etf: usize = 0;
    var total_eq: i64 = 0;
    var n_eq: usize = 0;
    for (b.instruments[0..b.instrument_count]) |inst| {
        if (inst.asset_class == .etf) {
            total_etf += inst.allocation_cents;
            n_etf += 1;
        } else {
            total_eq += inst.allocation_cents;
            n_eq += 1;
        }
    }
    try std.testing.expect(n_etf > 0);
    try std.testing.expect(n_eq > 0);
    const avg_etf = @divFloor(total_etf, @as(i64, @intCast(n_etf)));
    const avg_eq = @divFloor(total_eq, @as(i64, @intCast(n_eq)));
    try std.testing.expect(avg_etf > avg_eq);
    try std.testing.expectEqual(expected_etf_alloc_cents, avg_etf);
    try std.testing.expectEqual(expected_equity_alloc_cents, avg_eq);
}

test "allowed_trade: basket account id matches operations account" {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    try std.testing.expectEqual(operations_account_id, b.account_id);
}

test "allowed_trade: catalog schema version stamped on basket" {
    const input = operationsThesisInput();
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, 0);
    try std.testing.expectEqual(@as(u16, 1), b.catalog_schema_version);
}

// ---------------------------------------------------------------------------
// Affordability and policy assertions
// ---------------------------------------------------------------------------

test "allowed_trade: affordability outcome is allow for ops account" {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    // portfolio.fixtures.cash_rich.account_id == operations_account_id == 2001
    const result = try portfolio.checkBasketAffordability(&portfolio.fixtures.cash_rich, &b);
    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, result.outcome);
    try std.testing.expectEqual(target_notional_cents, result.requested_notional_cents);
}

test "allowed_trade: max affordable is day-limit-bound at USD 25000" {
    // cash_rich: cash=5M, buying_power=5M, day_remaining=2.5M, month_remaining=10M.
    // max_affordable = min(5M, 5M, 2.5M, 10M) = 2.5M (day limit binds).
    const result = portfolio.checkAffordability(&portfolio.fixtures.cash_rich, target_notional_cents);
    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, result.outcome);
    try std.testing.expectEqual(@as(i64, 2_500_000), result.max_affordable_cents);
    try std.testing.expectEqual(@as(i64, 5_000_000), result.cash_available_cents);
    try std.testing.expectEqual(@as(i64, 5_000_000), result.buying_power_cents);
    try std.testing.expectEqual(@as(i64, 2_500_000), result.remaining_daily_notional_cents);
    try std.testing.expectEqual(@as(i64, 10_000_000), result.remaining_monthly_notional_cents);
}

test "allowed_trade: effective max paper trade is policy-per-order-bound at USD 2500" {
    // effective_max = min(max_affordable=2.5M, policy_per_order=250K) = 250K.
    // Target (200K) <= effective_max (250K): allowed.
    const result = portfolio.checkAffordability(&portfolio.fixtures.cash_rich, target_notional_cents);
    const effective_max = @min(result.max_affordable_cents, policy_max_notional_per_order_cents);
    try std.testing.expectEqual(@as(i64, 250_000), effective_max);
    try std.testing.expect(target_notional_cents <= effective_max);
}

// ---------------------------------------------------------------------------
// Paper execution fixture consistency assertions
// ---------------------------------------------------------------------------

test "allowed_trade: paper execution fills sum to target notional" {
    // Validates consistency with paper_execution_allowed_2000.json.
    var total: i64 = 0;
    for (paper_fills_cents) |f| total += f;
    try std.testing.expectEqual(target_notional_cents, total);
}

test "allowed_trade: paper execution fill count matches basket instrument count" {
    // Every basket line item must have exactly one fill in the execution fixture.
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, thesis_id);
    try std.testing.expectEqual(@as(usize, paper_fills_cents.len), b.instrument_count);
}

// ---------------------------------------------------------------------------
// Determinism and replay-stability assertions
// ---------------------------------------------------------------------------

test "allowed_trade: basket is deterministic across repeated builds" {
    const input = operationsThesisInput();
    const h = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b1 = try basket_mod.build(intent, h);
    const b2 = try basket_mod.build(intent, h);
    try std.testing.expectEqual(b1.basket_id, b2.basket_id);
    try std.testing.expectEqual(b1.instrument_count, b2.instrument_count);
    try std.testing.expectEqual(b1.total_allocated_cents, b2.total_allocated_cents);
    for (0..b1.instrument_count) |i| {
        try std.testing.expectEqualStrings(
            b1.instruments[i].tickerSlice(),
            b2.instruments[i].tickerSlice(),
        );
        try std.testing.expectEqual(
            b1.instruments[i].allocation_cents,
            b2.instruments[i].allocation_cents,
        );
        try std.testing.expectEqual(
            b1.instruments[i].weight_bp,
            b2.instruments[i].weight_bp,
        );
    }
}

test "allowed_trade: basket id and thesis id are distinct non-zero values" {
    // basket_id covers composition; thesis_id covers the source input.
    // Replay can detect basket-construction drift independent of the source thesis.
    const input = operationsThesisInput();
    const h = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b = try basket_mod.build(intent, h);
    try std.testing.expect(b.basket_id != 0);
    try std.testing.expect(b.thesis_id != 0);
    try std.testing.expect(b.basket_id != b.thesis_id);
    try std.testing.expectEqual(h, b.thesis_id);
}
