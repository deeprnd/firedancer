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
