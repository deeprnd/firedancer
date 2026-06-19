const std = @import("std");
const adapter = @import("adapter");
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

test "investment_replay_integration: succeeds with fixture substitutions and no live effects" {
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);
    try std.testing.expect(support.basketRejects(&basket, "SOXL"));
    try std.testing.expect(support.basketRejects(&basket, "BULZ"));

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
        support.policy_max_notional_per_order_cents,
        support.expected_ticket_id,
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
    try std.testing.expectEqual(investment_audit.allowed_trade_event_count, audit_chain.slice().len);
    try std.testing.expectEqual(audit.RecordType.source_event, std.meta.activeTag(audit_chain.events[0].payload));
    try std.testing.expectEqual(audit.RecordType.deduplication, std.meta.activeTag(audit_chain.events[2].payload));
    try std.testing.expectEqual(audit.RecordType.case_creation, std.meta.activeTag(audit_chain.events[3].payload));
    try std.testing.expectEqual(audit.RecordType.replay_result, std.meta.activeTag(audit_chain.events[10].payload));
    try std.testing.expectEqual(run_id, audit_chain.events[0].header.run_id);
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[0].header.prev_hash);
    for (audit_chain.events[1..], 1..) |event, i| {
        try std.testing.expectEqual(audit_chain.events[i - 1].header.record_hash, event.header.prev_hash);
    }
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[10].payload.replay_result.divergences);
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[10].payload.replay_result.first_divergent_seq);
}

test "investment_replay_integration: tamper detection reports first divergent hash and sequence" {
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInput();
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
        support.policy_max_notional_per_order_cents,
        support.expected_ticket_id,
    );
    defer agent_result.deinit(allocator);

    const execution = agent_result.paper_result orelse return error.TestUnexpectedResult;

    const replay_result = try replay.verifyAllowedTradeWithCapsulePath(
        allocator,
        std.testing.io,
        support.tampered_replay_capsule_path,
        &model_backend,
        &adapter_backend,
        &basket,
        &agent_result.ticket,
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
    try std.testing.expectEqual(@as(u64, 1), audit_chain.events[10].payload.replay_result.divergences);
    try std.testing.expectEqual(@as(u64, 7), audit_chain.events[10].payload.replay_result.first_divergent_seq);
}
