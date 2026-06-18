// Integration tile-boundary test: investment scenarios.
//
// All paths flow through tkcase (run_id derivation), tkdisp (work item dispatch),
// and tkagnt (model + adapter calls) so every assertion touches the tile boundary,
// not the underlying function directly.

const std = @import("std");
const adapter = @import("adapter");
const audit = @import("audit_tile");
const basket_mod = @import("basket");
const investment_audit = @import("investment_audit");
const model = @import("model");
const portfolio = @import("portfolio");
const replay = @import("replay");
const thesis = @import("thesis");
const trade_ticket = @import("trade_ticket");
const tkcase = @import("tkcase");
const tkdisp = @import("tkdisp");
const tkagnt = @import("tkagnt");

const operations_account_id: u32 = 2001;
const target_notional_cents: i64 = 200_000;
const oversized_target_notional_cents: i64 = 2_500_000;
const policy_max_notional_per_order_cents: i64 = 250_000;
const expected_ticket_id = "ticket_v1_1_ai_infra_2000_market";
const expected_blocked_ticket_id = "ticket_v1_1_ai_infra_25000_blocked";
const restricted_ticker = "SOXL";
const tampered_replay_capsule_path = "src/tickoni/test/fixtures/investment/replay_capsule_tampered_paper_fill.json";

const ExpectedLine = struct {
    ticker: []const u8,
    quantity_micros: u64,
    price_cents: i64,
    line_notional_cents: i64,
};

fn operationsThesisInputWithTarget(target_notional_cents_arg: i64) thesis.ThesisInput {
    var input = thesis.fixtures.ai_infrastructure;
    input.account_id = operations_account_id;
    input.target_notional_cents = target_notional_cents_arg;
    input.max_single_name_pct = 25;
    return input;
}

fn operationsThesisInput() thesis.ThesisInput {
    return operationsThesisInputWithTarget(target_notional_cents);
}

fn operationsRestrictedTickerInput() thesis.ThesisInput {
    var input = operationsThesisInput();
    const user_text = "Buy SOXL in the basket.";
    @memset(&input.user_text, 0);
    @memcpy(input.user_text[0..user_text.len], user_text);
    input.user_text_len = user_text.len;
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

fn findRejectedCandidate(
    proposed_basket: *const basket_mod.Basket,
    ticker: []const u8,
) ?basket_mod.RejectedCandidate {
    for (proposed_basket.rejected[0..proposed_basket.rejected_count]) |candidate| {
        if (std.mem.eql(u8, candidate.tickerSlice(), ticker)) return candidate;
    }
    return null;
}

test "allowed_trade_integration: tkcase tkdisp tkagnt build the allowed paper trade" {
    const allocator = std.testing.allocator;
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);
    try std.testing.expect(basketRejects(&basket, "SOXL"));
    try std.testing.expect(basketRejects(&basket, "BULZ"));

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = model.Backend{ .fixture = .{} };
    var adapter_backend = adapter.Backend{ .fixture = .{} };
    const agent_result = try tkagnt.runInvestmentAgent(
        allocator,
        work_item,
        &basket,
        &model_backend,
        &adapter_backend,
        policy_max_notional_per_order_cents,
        expected_ticket_id,
    );
    defer agent_result.deinit(allocator);

    try std.testing.expect(std.mem.indexOf(u8, agent_result.model_response.content, "SOXX") != null);
    try std.testing.expectEqual(@as(u32, 335), agent_result.model_response.token_usage.total_tokens);

    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, agent_result.affordability.outcome);

    try std.testing.expectEqual(trade_ticket.PolicyOutcome.allow, agent_result.ticket.policy_outcome);
    try std.testing.expectEqualStrings(expected_ticket_id, agent_result.ticket.ticketIdSlice());
    try std.testing.expectEqual(target_notional_cents, agent_result.ticket.estimated_cost_cents);
    try std.testing.expectEqual(@as(u8, 7), agent_result.ticket.line_item_count);

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
        const line = findLineItem(&agent_result.ticket, expected.ticker) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(expected.quantity_micros, line.quantity_micros);
        try std.testing.expectEqual(expected.price_cents, line.price_cents);
        try std.testing.expectEqual(expected.line_notional_cents, line.line_notional_cents);
    }

    const execution = agent_result.paper_result orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(trade_ticket.ExecutionStatus.filled, execution.status);
    try std.testing.expectEqual(target_notional_cents, execution.total_filled_cents);
    try std.testing.expectEqualStrings(expected_ticket_id, execution.ticketIdSlice());
    try std.testing.expectEqual(@as(i64, 4_800_000), execution.resulting_account_snapshot.cash_cents);
    try std.testing.expectEqual(@as(i64, 200_000), execution.resulting_account_snapshot.day_notional_used_cents);
}

test "allowed_trade_integration: replay succeeds with fixture substitutions and no live effects" {
    const allocator = std.testing.allocator;
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);
    try std.testing.expect(basketRejects(&basket, "SOXL"));
    try std.testing.expect(basketRejects(&basket, "BULZ"));

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = model.Backend{ .fixture = .{} };
    var adapter_backend = adapter.Backend{ .fixture = .{} };
    const agent_result = try tkagnt.runInvestmentAgent(
        allocator,
        work_item,
        &basket,
        &model_backend,
        &adapter_backend,
        policy_max_notional_per_order_cents,
        expected_ticket_id,
    );
    defer agent_result.deinit(allocator);

    const execution = agent_result.paper_result orelse return error.TestUnexpectedResult;

    const replay_result = try replay.verifyAllowedTrade(
        allocator,
        std.testing.io,
        &model_backend,
        &adapter_backend,
        &basket,
        &agent_result.ticket,
        &execution,
        &agent_result.model_response,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 0), replay_result.divergence_count);
    try std.testing.expectEqualStrings("", replay_result.first_divergent_field);
    try std.testing.expectEqual(@as(u64, 0), replay_result.first_divergent_seq);

    const audit_chain = investment_audit.buildAllowedTradeChain(
        run_id,
        &input,
        &basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &execution,
        &replay_result,
    );
    try std.testing.expectEqual(
        investment_audit.allowed_trade_event_count,
        audit_chain.slice().len,
    );
    try std.testing.expectEqual(audit.RecordType.source_event, std.meta.activeTag(audit_chain.events[0].payload));
    try std.testing.expectEqual(audit.RecordType.deduplication, std.meta.activeTag(audit_chain.events[2].payload));
    try std.testing.expectEqual(audit.RecordType.case_creation, std.meta.activeTag(audit_chain.events[3].payload));
    try std.testing.expectEqual(audit.RecordType.replay_result, std.meta.activeTag(audit_chain.events[10].payload));
    try std.testing.expectEqual(run_id, audit_chain.events[0].header.run_id);
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[0].header.prev_hash);
    for (audit_chain.events[1..], 1..) |event, i| {
        try std.testing.expectEqual(audit_chain.events[i - 1].header.record_hash, event.header.prev_hash);
    }
    try std.testing.expectEqual(
        @as(u64, 0),
        audit_chain.events[10].payload.replay_result.divergences,
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        audit_chain.events[10].payload.replay_result.first_divergent_seq,
    );
}

test "allowed_trade_integration: replay tamper detection reports first divergent hash and sequence" {
    const allocator = std.testing.allocator;
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = model.Backend{ .fixture = .{} };
    var adapter_backend = adapter.Backend{ .fixture = .{} };
    const agent_result = try tkagnt.runInvestmentAgent(
        allocator,
        work_item,
        &basket,
        &model_backend,
        &adapter_backend,
        policy_max_notional_per_order_cents,
        expected_ticket_id,
    );
    defer agent_result.deinit(allocator);

    const execution = agent_result.paper_result orelse return error.TestUnexpectedResult;

    const replay_result = try replay.verifyAllowedTradeWithCapsulePath(
        allocator,
        std.testing.io,
        tampered_replay_capsule_path,
        &model_backend,
        &adapter_backend,
        &basket,
        &agent_result.ticket,
        &execution,
        &agent_result.model_response,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(!replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 1), replay_result.divergence_count);
    try std.testing.expectEqualStrings("adapter_response_hash", replay_result.first_divergent_field);
    try std.testing.expectEqual(@as(u64, 7), replay_result.first_divergent_seq);

    const audit_chain = investment_audit.buildAllowedTradeChain(
        run_id,
        &input,
        &basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &execution,
        &replay_result,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        audit_chain.events[10].payload.replay_result.divergences,
    );
    try std.testing.expectEqual(
        @as(u64, 7),
        audit_chain.events[10].payload.replay_result.first_divergent_seq,
    );
}

test "allowed_trade_integration: oversized trade is blocked before paper execution" {
    const allocator = std.testing.allocator;
    const input = operationsThesisInputWithTarget(oversized_target_notional_cents);
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);
    try std.testing.expect(basketRejects(&basket, "SOXL"));
    try std.testing.expect(basketRejects(&basket, "BULZ"));

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = model.Backend{ .fixture = .{} };
    var adapter_backend = adapter.Backend{ .fixture = .{} };
    const agent_result = try tkagnt.runInvestmentAgent(
        allocator,
        work_item,
        &basket,
        &model_backend,
        &adapter_backend,
        policy_max_notional_per_order_cents,
        expected_blocked_ticket_id,
    );
    defer agent_result.deinit(allocator);

    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, agent_result.affordability.outcome);
    try std.testing.expectEqual(@as(i64, 2_500_000), agent_result.affordability.max_affordable_cents);

    try std.testing.expectEqual(trade_ticket.PolicyOutcome.deny, agent_result.ticket.policy_outcome);
    try std.testing.expectEqualStrings(expected_blocked_ticket_id, agent_result.ticket.ticketIdSlice());
    try std.testing.expectEqual(oversized_target_notional_cents, agent_result.ticket.estimated_cost_cents);
    try std.testing.expectEqual(@as(i64, 250_000), agent_result.ticket.affordability_result.effective_max_paper_trade_cents);
    try std.testing.expectEqual(@as(u8, 1), agent_result.ticket.blocked_reason_count);
    try std.testing.expectEqual(
        trade_ticket.BlockedReasonCode.per_order_notional_exceeded,
        agent_result.ticket.blocked_reasons[0].code,
    );
    try std.testing.expectEqual(
        trade_ticket.FailedScopeDimension.per_order_notional,
        agent_result.ticket.blocked_reasons[0].failed_scope_dim,
    );
    try std.testing.expectEqual(oversized_target_notional_cents, agent_result.ticket.blocked_reasons[0].requested_cents);
    try std.testing.expectEqual(@as(i64, 250_000), agent_result.ticket.blocked_reasons[0].limit_cents);

    // Agent must not place a paper order when the ticket is denied.
    try std.testing.expect(agent_result.paper_result == null);
}

test "allowed_trade_integration: oversized trade replay and audit reproduce the deny" {
    const allocator = std.testing.allocator;
    const input = operationsThesisInputWithTarget(oversized_target_notional_cents);
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = model.Backend{ .fixture = .{} };
    var adapter_backend = adapter.Backend{ .fixture = .{} };
    const agent_result = try tkagnt.runInvestmentAgent(
        allocator,
        work_item,
        &basket,
        &model_backend,
        &adapter_backend,
        policy_max_notional_per_order_cents,
        expected_blocked_ticket_id,
    );
    defer agent_result.deinit(allocator);

    const replay_result = try replay.verifyOversizedTradeBlock(
        allocator,
        std.testing.io,
        &model_backend,
        &adapter_backend,
        &basket,
        &agent_result.ticket,
        &agent_result.model_response,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 0), replay_result.divergence_count);
    try std.testing.expectEqualStrings("", replay_result.first_divergent_field);
    try std.testing.expectEqual(@as(u64, 0), replay_result.first_divergent_seq);

    const audit_chain = investment_audit.buildOversizedTradeBlockedChain(
        run_id,
        &input,
        &basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &replay_result,
    );
    try std.testing.expectEqual(
        investment_audit.oversized_trade_blocked_event_count,
        audit_chain.slice().len,
    );
    try std.testing.expectEqual(audit.RecordType.deduplication, std.meta.activeTag(audit_chain.events[2].payload));
    try std.testing.expectEqual(audit.RecordType.case_creation, std.meta.activeTag(audit_chain.events[3].payload));
    try std.testing.expectEqual(audit.RecordType.policy_decision, std.meta.activeTag(audit_chain.events[4].payload));
    try std.testing.expectEqual(audit.RecordType.limit_check, std.meta.activeTag(audit_chain.events[9].payload));
    try std.testing.expectEqual(audit.RecordType.denial, std.meta.activeTag(audit_chain.events[10].payload));
    try std.testing.expectEqual(audit.RecordType.replay_result, std.meta.activeTag(audit_chain.events[11].payload));
    try std.testing.expectEqual(audit.PolicyOutcome.deny, audit_chain.events[4].payload.policy_decision.outcome);
    try std.testing.expectEqual(audit.PolicyOutcome.deny, audit_chain.events[9].payload.limit_check.outcome);
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(trade_ticket.BlockedReasonCode.per_order_notional_exceeded)),
        audit_chain.events[10].payload.denial.reason_code,
    );
    try std.testing.expectEqual(
        @as(i64, 250_000),
        audit_chain.events[9].payload.limit_check.limit,
    );
    try std.testing.expectEqual(
        oversized_target_notional_cents,
        audit_chain.events[9].payload.limit_check.value,
    );
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[0].header.prev_hash);
    for (audit_chain.events[1..], 1..) |event, i| {
        try std.testing.expectEqual(audit_chain.events[i - 1].header.record_hash, event.header.prev_hash);
    }
}

test "allowed_trade_integration: direct restricted ticker request is denied before adapter work" {
    const allocator = std.testing.allocator;
    const input = operationsRestrictedTickerInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);

    const rejected = findRejectedCandidate(&basket, restricted_ticker) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(basket_mod.RejectionReason.restricted_instrument, rejected.reason_code);
    try std.testing.expect(std.mem.indexOf(u8, rejected.reasonSlice(), "leveraged ETF") != null);
    try std.testing.expect(basketRejects(&basket, restricted_ticker));

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    // Policy denies: only tkmodl is called; no adapter work occurs.
    var model_backend = model.Backend{ .fixture = .{} };
    const block_result = try tkagnt.runRestrictedInstrumentDenialAgent(
        allocator,
        work_item,
        &model_backend,
    );
    defer block_result.deinit(allocator);

    try std.testing.expectEqual(run_id, block_result.run_id);
}

test "allowed_trade_integration: restricted ticker replay and audit reproduce the deny" {
    const allocator = std.testing.allocator;
    const input = operationsRestrictedTickerInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);

    const rejected = findRejectedCandidate(&basket, restricted_ticker) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(basket_mod.RejectionReason.restricted_instrument, rejected.reason_code);

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = model.Backend{ .fixture = .{} };
    const block_result = try tkagnt.runRestrictedInstrumentDenialAgent(
        allocator,
        work_item,
        &model_backend,
    );
    defer block_result.deinit(allocator);

    const replay_result = try replay.verifyRestrictedInstrumentBlock(
        allocator,
        std.testing.io,
        &model_backend,
        &basket,
        restricted_ticker,
        &block_result.model_response,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 0), replay_result.divergence_count);
    try std.testing.expectEqualStrings("", replay_result.first_divergent_field);
    try std.testing.expectEqual(@as(u64, 0), replay_result.first_divergent_seq);

    const audit_chain = investment_audit.buildRestrictedInstrumentBlockedChain(
        run_id,
        &input,
        &basket,
        &block_result.model_response,
        &replay_result,
    );
    try std.testing.expectEqual(
        investment_audit.restricted_instrument_blocked_event_count,
        audit_chain.slice().len,
    );
    try std.testing.expectEqual(audit.RecordType.deduplication, std.meta.activeTag(audit_chain.events[2].payload));
    try std.testing.expectEqual(audit.RecordType.case_creation, std.meta.activeTag(audit_chain.events[3].payload));
    try std.testing.expectEqual(audit.RecordType.policy_decision, std.meta.activeTag(audit_chain.events[4].payload));
    try std.testing.expectEqual(audit.RecordType.denial, std.meta.activeTag(audit_chain.events[6].payload));
    try std.testing.expectEqual(audit.RecordType.replay_result, std.meta.activeTag(audit_chain.events[7].payload));
    try std.testing.expectEqual(audit.PolicyOutcome.deny, audit_chain.events[4].payload.policy_decision.outcome);
    try std.testing.expectEqualStrings(
        "restricted_instrument",
        std.mem.sliceTo(&audit_chain.events[4].payload.policy_decision.failed_scope_dim, 0),
    );
    try std.testing.expectEqualStrings(
        "restricted_instrument",
        std.mem.sliceTo(&audit_chain.events[6].payload.denial.failed_scope_dim, 0),
    );
    for (audit_chain.events) |event| {
        try std.testing.expect(std.meta.activeTag(event.payload) != audit.RecordType.financial_adapter_call);
        try std.testing.expect(std.meta.activeTag(event.payload) != audit.RecordType.proposal);
    }
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[0].header.prev_hash);
    for (audit_chain.events[1..], 1..) |event, i| {
        try std.testing.expectEqual(audit_chain.events[i - 1].header.record_hash, event.header.prev_hash);
    }
}
