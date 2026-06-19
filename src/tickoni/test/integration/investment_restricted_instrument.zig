const std = @import("std");
const audit = @import("audit_tile");
const basket_mod = @import("basket");
const investment_audit = @import("investment_audit");
const model = @import("model");
const replay = @import("replay");
const thesis = @import("thesis");
const support = @import("investment_support");
const tkagnt = @import("tkagnt");
const tkcase = @import("tkcase");
const tkdisp = @import("tkdisp");

test "investment_restricted_instrument_integration: direct restricted ticker request is denied before adapter work" {
    const allocator = std.testing.allocator;
    const input = support.operationsRestrictedTickerInput();
    try std.testing.expectEqual(@as(u8, 1), input.requested_ticker_count);
    try std.testing.expectEqualSlices(u8, support.restricted_ticker, input.requested_tickers[0][0..support.restricted_ticker.len]);

    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    try std.testing.expectEqual(@as(u8, 1), intent.requested_ticker_count);
    try std.testing.expectEqualSlices(u8, support.restricted_ticker, intent.requested_tickers[0][0..support.restricted_ticker.len]);

    const basket = try basket_mod.build(intent, thesis_id);
    const rejected = support.findRejectedCandidate(&basket, support.restricted_ticker) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(basket_mod.RejectionReason.restricted_instrument, rejected.reason_code);
    try std.testing.expect(std.mem.indexOf(u8, rejected.reasonSlice(), "leveraged ETF") != null);
    try std.testing.expect(support.basketRejects(&basket, support.restricted_ticker));

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    try std.testing.expect(basket.hasRestrictedRejections());

    var model_backend = model.Backend{ .fixture = .{} };
    const block_result = try tkagnt.runRestrictedInstrumentDenialAgent(
        allocator,
        work_item,
        &model_backend,
    );
    defer block_result.deinit(allocator);

    try std.testing.expectEqual(run_id, block_result.run_id);
}

test "investment_restricted_instrument_integration: restricted ticker replay and audit reproduce the deny" {
    const allocator = std.testing.allocator;
    const input = support.operationsRestrictedTickerInput();
    try std.testing.expectEqual(@as(u8, 1), input.requested_ticker_count);
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    try std.testing.expectEqual(@as(u8, 1), intent.requested_ticker_count);
    const basket = try basket_mod.build(intent, thesis_id);

    const rejected = support.findRejectedCandidate(&basket, support.restricted_ticker) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(basket_mod.RejectionReason.restricted_instrument, rejected.reason_code);
    try std.testing.expect(basket.hasRestrictedRejections());

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
        support.restricted_ticker,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 0), replay_result.divergence_count);
    try std.testing.expectEqualStrings("", replay_result.first_divergent_field);
    try std.testing.expectEqual(@as(u64, 0), replay_result.first_divergent_seq);

    const audit_chain = investment_audit.buildRestrictedInstrumentBlockedChain(
        run_id,
        "ops_reviewer",
        "trading_control",
        &input,
        &basket,
        &block_result.model_response,
        &replay_result,
    );
    try std.testing.expectEqual(investment_audit.restricted_instrument_blocked_event_count, audit_chain.slice().len);
    try std.testing.expectEqual(audit.RecordType.deduplication, std.meta.activeTag(audit_chain.events[2].payload));
    try std.testing.expectEqual(audit.RecordType.case_creation, std.meta.activeTag(audit_chain.events[3].payload));
    try std.testing.expectEqual(audit.RecordType.policy_decision, std.meta.activeTag(audit_chain.events[4].payload));
    try std.testing.expectEqual(audit.RecordType.denial, std.meta.activeTag(audit_chain.events[6].payload));
    try std.testing.expectEqual(audit.RecordType.replay_result, std.meta.activeTag(audit_chain.events[7].payload));
    try std.testing.expectEqual(audit.PolicyOutcome.deny, audit_chain.events[4].payload.policy_decision.outcome);
    try std.testing.expectEqualStrings("restricted_instrument", std.mem.sliceTo(&audit_chain.events[4].payload.policy_decision.failed_scope_dim, 0));
    try std.testing.expectEqualStrings("restricted_instrument", std.mem.sliceTo(&audit_chain.events[6].payload.denial.failed_scope_dim, 0));
    for (audit_chain.events) |event| {
        try std.testing.expect(std.meta.activeTag(event.payload) != audit.RecordType.financial_adapter_call);
        try std.testing.expect(std.meta.activeTag(event.payload) != audit.RecordType.proposal);
    }
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[0].header.prev_hash);
    for (audit_chain.events[1..], 1..) |event, i| {
        try std.testing.expectEqual(audit_chain.events[i - 1].header.record_hash, event.header.prev_hash);
    }
}
