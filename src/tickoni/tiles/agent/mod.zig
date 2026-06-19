const std = @import("std");
const adapter = @import("adapter");
const basket_mod = @import("basket");
const disp = @import("disp");
const model = @import("model");
const portfolio = @import("portfolio");
const tool = @import("tool");
const trade_ticket = @import("trade_ticket");

/// Result of a normal investment agent run (allowed or oversized-denied).
/// Caller owns model_response; call deinit(allocator) when done.
pub const AgentResult = struct {
    run_id: u64,
    model_response: model.ModelResponse,
    affordability: portfolio.AffordabilityResult,
    quote_snapshot: trade_ticket.QuoteSnapshot,
    ticket: trade_ticket.TradeTicket,
    /// Non-null only when ticket.policy_outcome == .allow.
    paper_result: ?trade_ticket.PaperExecutionResult,

    pub fn deinit(self: AgentResult, allocator: std.mem.Allocator) void {
        self.model_response.deinit(allocator);
    }
};

/// Result of a restricted-instrument denial run.
/// Caller owns model_response; call deinit(allocator) when done.
pub const RestrictedBlockResult = struct {
    run_id: u64,
    model_response: model.ModelResponse,

    pub fn deinit(self: RestrictedBlockResult, allocator: std.mem.Allocator) void {
        self.model_response.deinit(allocator);
    }
};

/// Bounded deterministic agent for normal investment flows (allowed or oversized).
/// Calls tkmodl (model_backend) then tktool/tkadpt (adapter_backend).
/// Invokes paper order only when ticket.policy_outcome == .allow.
pub fn runInvestmentAgent(
    allocator: std.mem.Allocator,
    work_item: disp.WorkItem,
    proposed_basket: *const basket_mod.Basket,
    model_backend: *model.Backend,
    adapter_backend: *adapter.Backend,
    policy_max_notional_per_order_cents: i64,
    ticket_id: []const u8,
) !AgentResult {
    // tkmodl: model recommendation — never call LLM directly
    const model_response = try model_backend.call(allocator, .{
        .model_id = "fixture.ai_infra",
        .messages = &.{.{ .role = "user", .content = "ai infrastructure" }},
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    });
    errdefer model_response.deinit(allocator);

    // tktool -> tkadpt: portfolio snapshot
    const portfolio_result = try adapter_backend.call(
        tool.normalizePortfolioRead(work_item.account_id),
    );
    const account = switch (portfolio_result) {
        .portfolio_snapshot => |s| s,
        else => return error.UnexpectedAdapterResponse,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, proposed_basket);

    // tktool -> tkadpt: quote snapshot
    const quote_result = try adapter_backend.call(
        tool.normalizeQuoteRead(proposed_basket),
    );
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |s| s,
        else => return error.UnexpectedAdapterResponse,
    };

    const ticket = try trade_ticket.buildMarketBuyTicket(
        proposed_basket,
        &quote_snapshot,
        affordability,
        policy_max_notional_per_order_cents,
        ticket_id,
    );

    // tktool -> tkadpt: paper order (only when policy allows)
    var paper_result: ?trade_ticket.PaperExecutionResult = null;
    if (ticket.policy_outcome == .allow) {
        const paper_resp = try adapter_backend.call(tool.normalizePaperOrder(&ticket));
        paper_result = switch (paper_resp) {
            .paper_order => |r| r,
            else => return error.UnexpectedAdapterResponse,
        };
    }

    return .{
        .run_id = work_item.run_id,
        .model_response = model_response,
        .affordability = affordability,
        .quote_snapshot = quote_snapshot,
        .ticket = ticket,
        .paper_result = paper_result,
    };
}

/// Bounded agent for restricted-instrument denial flows.
/// Calls tkmodl for evidence; skips all adapter and ticket work.
pub fn runRestrictedInstrumentDenialAgent(
    allocator: std.mem.Allocator,
    work_item: disp.WorkItem,
    model_backend: *model.Backend,
) !RestrictedBlockResult {
    const model_response = try model_backend.call(allocator, .{
        .model_id = "fixture.ai_infra",
        .messages = &.{.{ .role = "user", .content = "ai infrastructure" }},
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    });
    return .{
        .run_id = work_item.run_id,
        .model_response = model_response,
    };
}

test "runInvestmentAgent blocks oversized trade and skips paper execution" {
    var proposed_basket: basket_mod.Basket = std.mem.zeroes(basket_mod.Basket);
    proposed_basket.account_id = 2001;
    proposed_basket.target_notional_cents = 2_500_000;
    proposed_basket.total_allocated_cents = 2_500_000;
    proposed_basket.instrument_count = 1;
    proposed_basket.instruments[0].ticker_len = 4;
    @memcpy(proposed_basket.instruments[0].ticker[0..4], "NVDA");
    proposed_basket.instruments[0].asset_class = .equity;
    proposed_basket.instruments[0].allocation_cents = 2_500_000;
    proposed_basket.instruments[0].weight_bp = 10_000;
    const work_item = disp.dispatchInvestmentRun(77, proposed_basket.account_id, proposed_basket.target_notional_cents);

    var quote_snapshot: trade_ticket.QuoteSnapshot = std.mem.zeroes(trade_ticket.QuoteSnapshot);
    quote_snapshot.quote_count = 1;
    quote_snapshot.quotes[0].ticker_len = 4;
    @memcpy(quote_snapshot.quotes[0].ticker[0..4], "NVDA");
    quote_snapshot.quotes[0].venue = .nasdaq;
    quote_snapshot.quotes[0].bid_cents = 10_000;
    quote_snapshot.quotes[0].ask_cents = 10_000;
    quote_snapshot.quotes[0].last_cents = 10_000;

    var account: portfolio.BrokerageAccount = std.mem.zeroes(portfolio.BrokerageAccount);
    account.account_id = proposed_basket.account_id;
    account.currency = .usd;
    account.cash_cents = 5_000_000;
    account.buying_power_cents = 5_000_000;
    account.day_notional_limit_cents = 5_000_000;
    account.month_notional_limit_cents = 10_000_000;

    var model_trace = model.MockBackend.CallTrace{};
    var adapter_trace = adapter.MockBackend.CallTrace{};
    var model_backend = model.Backend{ .mock = .{
        .canned_content = "{\"recommended_tickers\":[\"NVDA\"]}",
        .trace = &model_trace,
    } };
    var adapter_backend = adapter.Backend{ .mock = .{
        .portfolio_snapshot = account,
        .quote_snapshot = quote_snapshot,
        .trace = &adapter_trace,
    } };
    const result = try runInvestmentAgent(
        std.testing.allocator,
        work_item,
        &proposed_basket,
        &model_backend,
        &adapter_backend,
        250_000,
        "ticket_v1_1_ai_infra_25000_blocked",
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(work_item.run_id, result.run_id);
    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, result.affordability.outcome);
    try std.testing.expectEqual(trade_ticket.PolicyOutcome.deny, result.ticket.policy_outcome);
    try std.testing.expectEqual(@as(u8, 1), result.ticket.blocked_reason_count);
    try std.testing.expectEqual(trade_ticket.BlockedReasonCode.per_order_notional_exceeded, result.ticket.blocked_reasons[0].code);
    try std.testing.expect(result.paper_result == null);
    try std.testing.expectEqual(@as(usize, 1), model_trace.call_count);
    try std.testing.expectEqual(@as(usize, 1), adapter_trace.portfolio_snapshot_calls);
    try std.testing.expectEqual(@as(usize, 1), adapter_trace.quote_snapshot_calls);
    try std.testing.expectEqual(@as(usize, 0), adapter_trace.paper_order_calls);
}

test "runRestrictedInstrumentDenialAgent has no adapter boundary and calls tkmodl once" {
    const fn_info = @typeInfo(@TypeOf(runRestrictedInstrumentDenialAgent)).@"fn";
    inline for (fn_info.params) |param| {
        try std.testing.expect(param.type != *adapter.Backend);
    }

    var model_trace = model.MockBackend.CallTrace{};
    var model_backend = model.Backend{ .mock = .{
        .canned_content = "{\"thesis_summary\":\"restricted\"}",
        .trace = &model_trace,
    } };
    const work_item = disp.dispatchInvestmentRun(88, 2001, 200_000);
    const result = try runRestrictedInstrumentDenialAgent(
        std.testing.allocator,
        work_item,
        &model_backend,
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(work_item.run_id, result.run_id);
    try std.testing.expectEqual(@as(usize, 1), model_trace.call_count);
    try std.testing.expectEqualStrings("budget.demo_paper.v1_1", model_trace.last_budget_id);
    try std.testing.expectEqualStrings("v1.1", model_trace.last_policy_version);
    try std.testing.expectEqualStrings("capenv.trading_order.propose.demo", model_trace.last_capability_envelope_id);
}
