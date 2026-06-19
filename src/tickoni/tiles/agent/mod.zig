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

    var model_backend = model.Backend{ .fixture = .{} };
    var adapter_backend = adapter.Backend{ .fixture = .{} };
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
    try std.testing.expect(std.mem.indexOf(u8, result.model_response.content, "NVDA") != null);
}

test "runRestrictedInstrumentDenialAgent stays model-only for restricted ticker flows" {
    var model_backend = model.Backend{ .fixture = .{} };
    const work_item = disp.dispatchInvestmentRun(88, 2001, 200_000);
    const result = try runRestrictedInstrumentDenialAgent(
        std.testing.allocator,
        work_item,
        &model_backend,
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(work_item.run_id, result.run_id);
    try std.testing.expect(std.mem.indexOf(u8, result.model_response.content, "recommended_tickers") != null);
}
