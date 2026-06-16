const std = @import("std");
const adapter = @import("adapter");
const audit = @import("audit_tile");
const basket_mod = @import("basket");
const investment_audit = @import("investment_audit");
const model = @import("model");
const portfolio = @import("portfolio");
const replay = @import("replay");
const thesis = @import("thesis");
const tool = @import("tool");
const trade_ticket = @import("trade_ticket");

const demo_ops_account_id: u32 = 2001;
const target_notional_cents: i64 = 200_000;
const policy_max_notional_per_order_cents: i64 = 250_000;
const expected_ticket_id = "ticket_v1_1_ai_infra_2000_market";

const ExpectedLine = struct {
    ticker: []const u8,
    quantity_micros: u64,
    price_cents: i64,
    line_notional_cents: i64,
};

fn demoOpsThesisInput() thesis.ThesisInput {
    var input = thesis.fixtures.ai_infrastructure;
    input.account_id = demo_ops_account_id;
    input.max_single_name_pct = 25;
    return input;
}

fn findLineItem(ticket: *const trade_ticket.TradeTicket, ticker: []const u8) ?trade_ticket.TicketLineItem {
    for (ticket.line_items[0..ticket.line_item_count]) |line| {
        if (std.mem.eql(u8, line.tickerSlice(), ticker)) return line;
    }
    return null;
}

fn basketRejects(proposed_basket: *const basket_mod.Basket, ticker: []const u8) bool {
    for (proposed_basket.rejected[0..proposed_basket.rejected_count]) |candidate| {
        if (std.mem.eql(u8, candidate.tickerSlice(), ticker)) return true;
    }
    return false;
}

test "v1_1_allowed_2000_e2e: tkmodl tktool tkadpt build the allowed paper trade" {
    const allocator = std.testing.allocator;
    const input = demoOpsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);
    try std.testing.expect(basketRejects(&basket, "SOXL"));
    try std.testing.expect(basketRejects(&basket, "BULZ"));

    var model_backend = model.Backend{ .fixture = .{} };
    const model_request = model.ModelRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{.{ .role = "user", .content = "ai infrastructure demo" }},
    };
    const model_response = try model_backend.call(allocator, model_request);
    defer model_response.deinit(allocator);

    try std.testing.expect(std.mem.indexOf(u8, model_response.content, "SOXX") != null);
    try std.testing.expectEqual(@as(u32, 335), model_response.token_usage.total_tokens);

    const fixture_adapter = adapter.FixtureAdapter{};

    const portfolio_req = tool.normalizePortfolioRead(demo_ops_account_id);
    const portfolio_result = try fixture_adapter.call(portfolio_req);
    const account = switch (portfolio_result) {
        .portfolio_snapshot => |snapshot| snapshot,
        else => unreachable,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, &basket);
    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, affordability.outcome);

    const quote_req = tool.normalizeQuoteRead(&basket);
    const quote_result = try fixture_adapter.call(quote_req);
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |snapshot| snapshot,
        else => unreachable,
    };

    const ticket = try trade_ticket.buildMarketBuyTicket(
        &basket,
        &quote_snapshot,
        affordability,
        policy_max_notional_per_order_cents,
        expected_ticket_id,
    );

    try std.testing.expectEqual(trade_ticket.PolicyOutcome.allow, ticket.policy_outcome);
    try std.testing.expectEqualStrings(expected_ticket_id, ticket.ticketIdSlice());
    try std.testing.expectEqual(target_notional_cents, ticket.estimated_cost_cents);
    try std.testing.expectEqual(@as(u8, 7), ticket.line_item_count);

    const expected_lines = [_]ExpectedLine{
        .{ .ticker = "NVDA", .quantity_micros = 2_000_000, .price_cents = 12_500, .line_notional_cents = 25_000 },
        .{ .ticker = "AMD", .quantity_micros = 1_562_500, .price_cents = 16_000, .line_notional_cents = 25_000 },
        .{ .ticker = "AVGO", .quantity_micros = 1_000_000, .price_cents = 25_000, .line_notional_cents = 25_000 },
        .{ .ticker = "MSFT", .quantity_micros = 500_000, .price_cents = 50_000, .line_notional_cents = 25_000 },
        .{ .ticker = "AMZN", .quantity_micros = 1_250_000, .price_cents = 20_000, .line_notional_cents = 25_000 },
        .{ .ticker = "BOTZ", .quantity_micros = 12_500_000, .price_cents = 3_000, .line_notional_cents = 37_500 },
        .{ .ticker = "SOXX", .quantity_micros = 1_500_000, .price_cents = 25_000, .line_notional_cents = 37_500 },
    };
    for (expected_lines) |expected| {
        const line = findLineItem(&ticket, expected.ticker) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(expected.quantity_micros, line.quantity_micros);
        try std.testing.expectEqual(expected.price_cents, line.price_cents);
        try std.testing.expectEqual(expected.line_notional_cents, line.line_notional_cents);
    }

    const paper_req = tool.normalizePaperOrder(&ticket);
    const paper_result = try fixture_adapter.call(paper_req);
    const execution = switch (paper_result) {
        .paper_order => |result| result,
        else => unreachable,
    };

    try std.testing.expectEqual(trade_ticket.ExecutionStatus.filled, execution.status);
    try std.testing.expectEqual(target_notional_cents, execution.total_filled_cents);
    try std.testing.expectEqualStrings(expected_ticket_id, execution.ticketIdSlice());
    try std.testing.expectEqual(@as(i64, 4_800_000), execution.resulting_account_snapshot.cash_cents);
    try std.testing.expectEqual(@as(i64, 200_000), execution.resulting_account_snapshot.day_notional_used_cents);
}

test "v1_1_allowed_2000_e2e: replay succeeds with fixture substitutions and no live effects" {
    const allocator = std.testing.allocator;
    const input = demoOpsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);
    try std.testing.expect(basketRejects(&basket, "SOXL"));
    try std.testing.expect(basketRejects(&basket, "BULZ"));

    var model_backend = model.Backend{ .fixture = .{} };
    const model_response = try model_backend.call(allocator, .{
        .model_id = "fixture.ai_infra",
        .messages = &.{.{ .role = "user", .content = "ai infrastructure demo" }},
    });
    defer model_response.deinit(allocator);

    const fixture_adapter = adapter.FixtureAdapter{};
    const account_result = try fixture_adapter.call(tool.normalizePortfolioRead(demo_ops_account_id));
    const account = switch (account_result) {
        .portfolio_snapshot => |snapshot| snapshot,
        else => unreachable,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, &basket);
    const quote_result = try fixture_adapter.call(tool.normalizeQuoteRead(&basket));
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |snapshot| snapshot,
        else => unreachable,
    };
    const ticket = try trade_ticket.buildMarketBuyTicket(
        &basket,
        &quote_snapshot,
        affordability,
        policy_max_notional_per_order_cents,
        expected_ticket_id,
    );
    const paper_result = try fixture_adapter.call(tool.normalizePaperOrder(&ticket));
    const execution = switch (paper_result) {
        .paper_order => |result| result,
        else => unreachable,
    };

    const replay_result = try replay.verifyAllowedTrade(
        allocator,
        std.testing.io,
        &basket,
        &ticket,
        &execution,
        &model_response,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 0), replay_result.divergence_count);

    const audit_chain = investment_audit.buildAllowedTradeChain(
        &input,
        &basket,
        &quote_snapshot,
        affordability,
        &model_response,
        &ticket,
        &execution,
        &replay_result,
    );
    try std.testing.expectEqual(
        investment_audit.allowed_trade_event_count,
        audit_chain.slice().len,
    );
    try std.testing.expectEqual(audit.RecordType.source_event, std.meta.activeTag(audit_chain.events[0].payload));
    try std.testing.expectEqual(audit.RecordType.replay_result, std.meta.activeTag(audit_chain.events[8].payload));
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[0].header.prev_hash);
    for (audit_chain.events[1..], 1..) |event, i| {
        try std.testing.expectEqual(audit_chain.events[i - 1].header.record_hash, event.header.prev_hash);
    }
    try std.testing.expectEqual(
        @as(u64, 0),
        audit_chain.events[8].payload.replay_result.divergences,
    );
}
