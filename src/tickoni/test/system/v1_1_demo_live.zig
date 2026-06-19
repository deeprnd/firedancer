const std = @import("std");
const adapter = @import("adapter");
const basket_mod = @import("basket");
const model = @import("model");
const portfolio = @import("portfolio");
const replay = @import("replay");
const thesis = @import("thesis");
const tool = @import("tool");
const trade_ticket = @import("trade_ticket");
const support = @import("investment_support");

const default_endpoint = "http://127.0.0.1:8080/v1";
const default_model_id = "unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL";

const restricted_tickers = [_][]const u8{
    "SOXL", "SOXS", "TQQQ", "SQQQ", "UPRO", "SPXS",
    "UVXY", "SVXY", "LABU", "LABD", "FAS",  "FAZ",
};

const system_prompt =
    "You are a structured financial research assistant. " ++
    "Summarize the thesis and recommend only US-listed large-cap equities and ETFs. " ++
    "Respond with JSON only using keys thesis_summary, recommended_tickers, and rationale. " ++
    "Do not recommend leveraged ETFs, inverse ETFs, options, futures, or crypto.";

const user_prompt =
    "Thesis: I want to invest USD 2,000 in AI infrastructure, but avoid single-name concentration " ++
    "and keep it to US-listed ETFs or large-cap equities.\n" ++
    "Target notional: USD 2,000\n" ++
    "Asset classes: equity, etf\n" ++
    "Market: US\n" ++
    "Sector theme: ai_infrastructure\n" ++
    "Risk preference: moderate\n" ++
    "Max single-name weight: 25%";

const live_actor_role = "trading_ops_reviewer";
const live_workflow = "trading_control";
const live_capability = "trading_order.propose";
const live_capability_envelope_id = "capenv.trading_order.propose.demo";
const live_policy_version = "v1.1";
const live_budget_id = "budget.demo_paper.v1_1.live";

const LiveModelResult = struct {
    excerpt: []u8,
    matched_ticker: []u8,

    fn deinit(self: *LiveModelResult, allocator: std.mem.Allocator) void {
        allocator.free(self.excerpt);
        allocator.free(self.matched_ticker);
    }
};

fn envOrDefault(allocator: std.mem.Allocator, name: []const u8, fallback: []const u8) ![]u8 {
    const name_z = try allocator.dupeZ(u8, name);
    defer allocator.free(name_z);
    const raw = std.c.getenv(name_z.ptr) orelse return allocator.dupe(u8, fallback);
    return allocator.dupe(u8, std.mem.span(raw));
}

fn makeLiveConfig(allowed_model_id: []const u8) model.TkModlConfig {
    var config = model.TkModlConfig{
        .live_provider_enabled = true,
        .hard_max_context_tokens = 4096,
        .hard_max_output_tokens = 1024,
        .hard_max_retry_count = 1,
        .hard_timeout_ms = 30_000,
        .per_run_token_budget = 4096,
    };
    config.allowed_model_ids[0] = allowed_model_id;
    config.allowed_model_id_count = 1;
    return config;
}

fn makeLiveRequest(model_id: []const u8) model.TkModlRequest {
    return .{
        .request_id = 1,
        .run_id = 1,
        .actor_id = 2001,
        .actor_role = live_actor_role,
        .workflow = live_workflow,
        .account_id = 2001,
        .capability = live_capability,
        .capability_envelope_id = live_capability_envelope_id,
        .policy_version = live_policy_version,
        .policy_decision_id = 0,
        .budget_id = live_budget_id,
        .model_id = model_id,
        .messages = &.{
            .{ .role = "system", .content = system_prompt },
            .{ .role = "user", .content = user_prompt },
        },
        .sampling = .{
            .temperature = 0,
            .top_p = 1.0,
            .max_output_tokens = 768,
            .seed = 42,
        },
        .max_context_tokens = 2048,
        .max_output_tokens = 768,
        .retry_limit = 0,
        .timeout_ms = 30_000,
        .replay_mode = .live,
    };
}

fn excerptForPrint(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    const excerpt_len = @min(content.len, 160);
    var buf = try allocator.alloc(u8, excerpt_len);
    for (content[0..excerpt_len], 0..) |c, i| {
        buf[i] = switch (c) {
            '\n', '\r', '\t' => ' ',
            else => c,
        };
    }
    return buf;
}

fn assertLiveModelResponse(
    allocator: std.mem.Allocator,
    response: *const model.ModelResponse,
) !LiveModelResult {
    try std.testing.expect(response.content.len > 0);
    try std.testing.expect(response.token_usage.total_tokens > 0);
    try std.testing.expect(response.finish_reason.len > 0);

    const allowed_tickers = [_][]const u8{
        "NVDA", "AMD", "AVGO", "MSFT", "AMZN", "GOOGL", "SOXX", "SMH", "QQQ", "VGT",
    };
    var matched_ticker: ?[]const u8 = null;
    for (allowed_tickers) |ticker| {
        if (std.mem.indexOf(u8, response.content, ticker) != null) {
            matched_ticker = ticker;
            break;
        }
    }
    try std.testing.expect(matched_ticker != null);

    for (restricted_tickers) |restricted| {
        try std.testing.expect(std.mem.indexOf(u8, response.content, restricted) == null);
    }

    if (std.mem.indexOf(u8, response.content, "<|channel>thought") != null) {
        const guidance_markers = [_][]const u8{
            "AI infrastructure",
            "single-name concentration",
            "US-listed",
        };
        for (guidance_markers) |marker| {
            try std.testing.expect(std.mem.indexOf(u8, response.content, marker) != null);
        }
    }

    return .{
        .excerpt = try excerptForPrint(allocator, response.content),
        .matched_ticker = try allocator.dupe(u8, matched_ticker.?),
    };
}

fn runAllowedTradeScenario() !struct {
    basket: basket_mod.Basket,
    ticket: trade_ticket.TradeTicket,
} {
    const input = support.operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);
    try std.testing.expect(support.basketRejects(&basket, "SOXL"));
    try std.testing.expect(support.basketRejects(&basket, "BULZ"));

    var adapter_backend = adapter.Backend{ .fixture = .{} };
    const portfolio_result = try adapter_backend.call(tool.normalizePortfolioRead(input.account_id));
    const account = switch (portfolio_result) {
        .portfolio_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, &basket);
    const quote_result = try adapter_backend.call(tool.normalizeQuoteRead(&basket));
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };
    const ticket = try trade_ticket.buildMarketBuyTicket(
        &basket,
        &quote_snapshot,
        affordability,
        support.policy_max_notional_per_order_cents,
        support.expected_ticket_id,
    );
    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, affordability.outcome);
    try std.testing.expectEqual(trade_ticket.PolicyOutcome.allow, ticket.policy_outcome);

    const paper_result = try adapter_backend.call(tool.normalizePaperOrder(&ticket));
    const execution = switch (paper_result) {
        .paper_order => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(trade_ticket.ExecutionStatus.filled, execution.status);
    try std.testing.expectEqual(support.target_notional_cents, execution.total_filled_cents);

    std.debug.print(
        "=== Allowed USD 2,000 ===\naccount={d} ticket={s} cost_cents={d} fills={d}\n",
        .{ ticket.account_id, ticket.ticketIdSlice(), ticket.estimated_cost_cents, execution.fill_count },
    );

    return .{
        .basket = basket,
        .ticket = ticket,
    };
}

fn runOversizedTradeScenario() !void {
    const input = support.operationsThesisInputWithTarget(support.oversized_target_notional_cents);
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);

    var adapter_backend = adapter.Backend{ .fixture = .{} };
    const portfolio_result = try adapter_backend.call(tool.normalizePortfolioRead(input.account_id));
    const account = switch (portfolio_result) {
        .portfolio_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, &basket);
    const quote_result = try adapter_backend.call(tool.normalizeQuoteRead(&basket));
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };
    const ticket = try trade_ticket.buildMarketBuyTicket(
        &basket,
        &quote_snapshot,
        affordability,
        support.policy_max_notional_per_order_cents,
        support.expected_blocked_ticket_id,
    );
    try std.testing.expectEqual(trade_ticket.PolicyOutcome.deny, ticket.policy_outcome);
    try std.testing.expectEqual(@as(u8, 1), ticket.blocked_reason_count);
    try std.testing.expectEqual(
        trade_ticket.BlockedReasonCode.per_order_notional_exceeded,
        ticket.blocked_reasons[0].code,
    );
    try std.testing.expectEqual(@as(i64, 250_000), ticket.affordability_result.effective_max_paper_trade_cents);

    std.debug.print(
        "=== Blocked USD 25,000 ===\nticket={s} reason={s} effective_max_cents={d}\n",
        .{
            ticket.ticketIdSlice(),
            ticket.blocked_reasons[0].code.label(),
            ticket.affordability_result.effective_max_paper_trade_cents,
        },
    );
}

fn runRestrictedScenario() !void {
    const input = support.operationsRestrictedTickerInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try basket_mod.build(intent, thesis_id);
    const rejected = support.findRejectedCandidate(&basket, support.restricted_ticker) orelse return error.TestUnexpectedResult;

    try std.testing.expect(basket.hasRestrictedRejections());
    try std.testing.expectEqual(basket_mod.RejectionReason.restricted_instrument, rejected.reason_code);

    std.debug.print(
        "=== Restricted Instrument ===\nrequested={s} rejected_reason={s}\n",
        .{ support.restricted_ticker, rejected.reasonSlice() },
    );
}

fn runReplayScenario(
    allocator: std.mem.Allocator,
    allowed_basket: *const basket_mod.Basket,
    allowed_ticket: *const trade_ticket.TradeTicket,
) !void {
    var replay_model_backend = model.Backend{ .fixture = .{} };
    var replay_adapter_backend = adapter.Backend{ .fixture = .{} };
    const replay_result = try replay.verifyAllowedTrade(
        allocator,
        std.testing.io,
        &replay_model_backend,
        &replay_adapter_backend,
        allowed_basket,
        allowed_ticket,
    );

    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 0), replay_result.divergence_count);

    std.debug.print(
        "=== Replay ===\nmatch={s} external_effects_disabled={s}\n",
        .{
            if (replay_result.replay_match) "true" else "false",
            if (replay_result.external_effects_disabled) "true" else "false",
        },
    );
}

test "system demo live: real tkmodl plus V1.1 allowed blocked restricted replay proof" {
    const allocator = std.testing.allocator;
    const endpoint = try envOrDefault(allocator, "TK_LLM_ENDPOINT", default_endpoint);
    defer allocator.free(endpoint);
    const request_model_id = try envOrDefault(allocator, "TK_LLM_MODEL_ID", default_model_id);
    defer allocator.free(request_model_id);

    var live_model_backend = model.Backend{ .http = .{
        .endpoint = endpoint,
        .io = std.testing.io,
    } };
    var tkmodl_result = try model.runTkModlRequest(
        allocator,
        makeLiveConfig(request_model_id),
        &live_model_backend,
        makeLiveRequest(request_model_id),
    );
    defer tkmodl_result.deinit(allocator);
    try std.testing.expectEqual(model.TkModlDecision.allow_live, tkmodl_result.outcome);
    const response = tkmodl_result.response orelse return error.TestUnexpectedResult;
    tkmodl_result.response = null;
    defer response.deinit(allocator);

    var live_result = try assertLiveModelResponse(allocator, &response);
    defer live_result.deinit(allocator);
    std.debug.print(
        "=== Live tkmodl ===\nendpoint={s}\nmodel={s}\nmatched_ticker={s}\nexcerpt={s}\n",
        .{ endpoint, response.model_id, live_result.matched_ticker, live_result.excerpt },
    );

    const allowed = try runAllowedTradeScenario();
    try runOversizedTradeScenario();
    try runRestrictedScenario();
    try runReplayScenario(allocator, &allowed.basket, &allowed.ticket);
}
