const std = @import("std");
const File = std.Io.File;
const adapter = @import("adapter");
const basket_mod = @import("basket");
const investment_audit = @import("investment_audit");
const model = @import("model");
const replay = @import("replay");
const thesis = @import("thesis");
const tkagnt = @import("tkagnt");
const tkcase = @import("tkcase");
const tkdisp = @import("tkdisp");

const operations_account_id: u32 = 2001;
const target_notional_cents: i64 = 200_000;
const oversized_target_notional_cents: i64 = 2_500_000;
const policy_max_notional_per_order_cents: i64 = 250_000;
const expected_ticket_id = "ticket_v1_1_ai_infra_2000_market";
const expected_blocked_ticket_id = "ticket_v1_1_ai_infra_25000_blocked";
const restricted_ticker = "SOXL";
const tampered_replay_capsule_path = "src/tickoni/test/fixtures/investment/replay_capsule_tampered_paper_fill.json";

pub fn main(init: std.process.Init) !void {
    try writeLine(init.io, "tickoni_s1_6_demo scenarios=4 mode=deterministic external_effects=disabled_by_fixture\n", .{});
    try runAllowedTradeScenario(init.gpa, init.io);
    try runOversizedTradeScenario(init.gpa, init.io);
    try runRestrictedInstrumentScenario(init.gpa, init.io);
    try runReplayTamperScenario(init.gpa, init.io);
}

fn runAllowedTradeScenario(allocator: std.mem.Allocator, io: std.Io) !void {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const proposed_basket = try basket_mod.build(intent, thesis_id);
    _ = findRejectedCandidate(&proposed_basket, "SOXL") orelse return error.UnexpectedDemoResult;
    _ = findRejectedCandidate(&proposed_basket, "BULZ") orelse return error.UnexpectedDemoResult;

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = fixtureModelBackend();
    var adapter_backend = fixtureAdapterBackend();
    const agent_result = try tkagnt.runInvestmentAgent(
        allocator,
        work_item,
        &proposed_basket,
        &model_backend,
        &adapter_backend,
        policy_max_notional_per_order_cents,
        expected_ticket_id,
    );
    defer agent_result.deinit(allocator);

    const execution = agent_result.paper_result orelse return error.UnexpectedDemoResult;
    const replay_result = try replay.verifyAllowedTrade(
        allocator,
        io,
        &model_backend,
        &adapter_backend,
        &proposed_basket,
        &agent_result.ticket,
        &execution,
        &agent_result.model_response,
    );
    if (!replay_result.external_effects_disabled or !replay_result.replay_match) {
        return error.UnexpectedDemoResult;
    }

    const audit_chain = investment_audit.buildAllowedTradeChain(
        run_id,
        &input,
        &proposed_basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &execution,
        &replay_result,
    );

    try writeLine(
        io,
        "scenario=allowed_trade_usd_2000 outcome={s} paper_status={s} ticket_id={s} total_filled_cents={d} audit_events={d} replay={s} run_id={d}\n",
        .{
            @tagName(agent_result.ticket.policy_outcome),
            @tagName(execution.status),
            agent_result.ticket.ticketIdSlice(),
            execution.total_filled_cents,
            audit_chain.slice().len,
            replayStatus(replay_result),
            run_id,
        },
    );
}

fn runOversizedTradeScenario(allocator: std.mem.Allocator, io: std.Io) !void {
    const input = operationsThesisInputWithTarget(oversized_target_notional_cents);
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const proposed_basket = try basket_mod.build(intent, thesis_id);

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = fixtureModelBackend();
    var adapter_backend = fixtureAdapterBackend();
    const agent_result = try tkagnt.runInvestmentAgent(
        allocator,
        work_item,
        &proposed_basket,
        &model_backend,
        &adapter_backend,
        policy_max_notional_per_order_cents,
        expected_blocked_ticket_id,
    );
    defer agent_result.deinit(allocator);

    if (agent_result.paper_result != null or agent_result.ticket.blocked_reason_count == 0) {
        return error.UnexpectedDemoResult;
    }

    const replay_result = try replay.verifyOversizedTradeBlock(
        allocator,
        io,
        &model_backend,
        &adapter_backend,
        &proposed_basket,
        &agent_result.ticket,
        &agent_result.model_response,
    );
    if (!replay_result.external_effects_disabled or !replay_result.replay_match) {
        return error.UnexpectedDemoResult;
    }

    const audit_chain = investment_audit.buildOversizedTradeBlockedChain(
        run_id,
        &input,
        &proposed_basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &replay_result,
    );
    const blocked_reason = agent_result.ticket.blocked_reasons[0];

    try writeLine(
        io,
        "scenario=oversized_trade_usd_25000 outcome={s} reason={s} failed_scope_dim={s} requested_cents={d} limit_cents={d} max_affordable_cents={d} effective_max_paper_trade_cents={d} audit_events={d} replay={s} run_id={d}\n",
        .{
            @tagName(agent_result.ticket.policy_outcome),
            blocked_reason.code.label(),
            blocked_reason.failed_scope_dim.label(),
            blocked_reason.requested_cents,
            blocked_reason.limit_cents,
            agent_result.affordability.max_affordable_cents,
            agent_result.ticket.affordability_result.effective_max_paper_trade_cents,
            audit_chain.slice().len,
            replayStatus(replay_result),
            run_id,
        },
    );
}

fn runRestrictedInstrumentScenario(allocator: std.mem.Allocator, io: std.Io) !void {
    const input = operationsRestrictedTickerInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const proposed_basket = try basket_mod.build(intent, thesis_id);
    if (!proposed_basket.hasRestrictedRejections()) return error.UnexpectedDemoResult;
    const rejected = findRejectedCandidate(&proposed_basket, restricted_ticker) orelse return error.UnexpectedDemoResult;

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = fixtureModelBackend();
    const block_result = try tkagnt.runRestrictedInstrumentDenialAgent(
        allocator,
        work_item,
        &model_backend,
    );
    defer block_result.deinit(allocator);

    const replay_result = try replay.verifyRestrictedInstrumentBlock(
        allocator,
        io,
        &model_backend,
        &proposed_basket,
        restricted_ticker,
        &block_result.model_response,
    );
    if (!replay_result.external_effects_disabled or !replay_result.replay_match) {
        return error.UnexpectedDemoResult;
    }

    const audit_chain = investment_audit.buildRestrictedInstrumentBlockedChain(
        run_id,
        &input,
        &proposed_basket,
        &block_result.model_response,
        &replay_result,
    );

    try writeLine(
        io,
        "scenario=restricted_instrument_soxl outcome=deny failed_scope_dim=restricted_instrument rejection_reason=\"{s}\" adapter_calls=0 audit_events={d} replay={s} run_id={d}\n",
        .{
            rejected.reasonSlice(),
            audit_chain.slice().len,
            replayStatus(replay_result),
            run_id,
        },
    );
}

fn runReplayTamperScenario(allocator: std.mem.Allocator, io: std.Io) !void {
    const input = operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const proposed_basket = try basket_mod.build(intent, thesis_id);

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend = fixtureModelBackend();
    var adapter_backend = fixtureAdapterBackend();
    const agent_result = try tkagnt.runInvestmentAgent(
        allocator,
        work_item,
        &proposed_basket,
        &model_backend,
        &adapter_backend,
        policy_max_notional_per_order_cents,
        expected_ticket_id,
    );
    defer agent_result.deinit(allocator);

    const execution = agent_result.paper_result orelse return error.UnexpectedDemoResult;
    const replay_result = try replay.verifyAllowedTradeWithCapsulePath(
        allocator,
        io,
        tampered_replay_capsule_path,
        &model_backend,
        &adapter_backend,
        &proposed_basket,
        &agent_result.ticket,
        &execution,
        &agent_result.model_response,
    );
    if (!replay_result.external_effects_disabled or replay_result.replay_match or replay_result.divergence_count == 0) {
        return error.UnexpectedDemoResult;
    }

    const audit_chain = investment_audit.buildAllowedTradeChain(
        run_id,
        &input,
        &proposed_basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &execution,
        &replay_result,
    );

    try writeLine(
        io,
        "scenario=replay_tamper outcome=diverged divergence_count={d} first_divergent_field={s} first_divergent_seq={d} audit_events={d} external_effects_disabled={s} run_id={d}\n",
        .{
            replay_result.divergence_count,
            replay_result.first_divergent_field,
            replay_result.first_divergent_seq,
            audit_chain.slice().len,
            boolStr(replay_result.external_effects_disabled),
            run_id,
        },
    );
}

fn fixtureModelBackend() model.Backend {
    return .{ .fixture = .{} };
}

fn fixtureAdapterBackend() adapter.Backend {
    return .{ .fixture = .{} };
}

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
    input.requested_ticker_count = 1;
    @memset(&input.requested_tickers[0], 0);
    @memcpy(input.requested_tickers[0][0..restricted_ticker.len], restricted_ticker);
    return input;
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

fn replayStatus(result: replay.ReplayVerification) []const u8 {
    return if (result.replay_match) "match" else "diverged";
}

fn boolStr(value: bool) []const u8 {
    return if (value) "true" else "false";
}

fn writeLine(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buf: [2048]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, fmt, args);
    try File.writeStreamingAll(File.stdout(), io, msg);
}
