// Integration tests for the tkmodl tile against a real llama.cpp server.
//
// These tests require a running llama.cpp OpenAI-compatible server.
// Start one with: just infra-run-llamacpp-cpu
//
// If the server is not reachable, tests are skipped (not failed) so they
// do not block unit-test CI lanes.
//
// The endpoint is read from TK_LLM_ENDPOINT (default http://127.0.0.1:8080/v1).
// The model id is read from TK_LLM_MODEL_ID
// (default unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL).

const std = @import("std");
const model = @import("model");

const default_endpoint = "http://127.0.0.1:8080/v1";
const default_model_id = "unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL";

// System prompt from model_request.json.
const system_prompt =
    "You are a structured financial research assistant. " ++
    "Your task is to analyze an investor thesis and recommend a basket of US-listed equities and ETFs. " ++
    "Respond with a JSON object containing: thesis_summary (string), recommended_tickers (array of strings), " ++
    "rationale (object mapping ticker to rationale string). " ++
    "Only recommend instruments appropriate for the given sector theme. " ++
    "Do not recommend leveraged ETFs, inverse ETFs, options, futures, or crypto.";

// User prompt from model_request.json.
const user_prompt =
    "Thesis: I want to invest USD 2,000 in sector, but avoid single-name concentration " ++
    "and keep it to US-listed ETFs or large-cap equities.\n" ++
    "Target notional: USD 2,000\n" ++
    "Asset classes: equity, etf\n" ++
    "Market: US\n" ++
    "Sector theme: ai_infrastructure\n" ++
    "Risk preference: moderate\n" ++
    "Max single-name weight: 25%";

fn getEndpoint() []const u8 {
    if (std.c.getenv("TK_LLM_ENDPOINT")) |val| return std.mem.span(val);
    return default_endpoint;
}

fn getModelId() []const u8 {
    if (std.c.getenv("TK_LLM_MODEL_ID")) |val| return std.mem.span(val);
    return default_model_id;
}

fn makeBackend() model.Backend {
    return .{ .http = .{ .endpoint = getEndpoint(), .io = std.testing.io } };
}

fn makeAiInfraRequest(model_id: []const u8) model.ModelRequest {
    return .{
        .model_id = model_id,
        .messages = &.{
            .{ .role = "system", .content = system_prompt },
            .{ .role = "user", .content = user_prompt },
        },
        .sampling = .{
            .temperature = 0,
            .top_p = 1.0,
            .max_output_tokens = 2048,
            .seed = 42,
        },
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    };
}

test "model tile http: hello round-trip" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = model.ModelRequest{
        .model_id = getModelId(),
        .messages = &.{.{ .role = "user", .content = "Reply with the single word: hello" }},
        .sampling = .{ .temperature = 0, .max_output_tokens = 256, .seed = 1 },
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    };

    const resp = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => {
            std.log.info("skipping: llama.cpp not reachable at {s} (run: just infra-run-llamacpp-cpu)", .{getEndpoint()});
            return error.SkipZigTest;
        },
        else => return err,
    };
    defer resp.deinit(allocator);

    try std.testing.expect(resp.content.len > 0);
    try std.testing.expect(resp.token_usage.total_tokens > 0);
}

test "model tile http: thesis returns non-empty content" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = makeAiInfraRequest(getModelId());

    const resp = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => {
            std.log.info("skipping: llama.cpp not reachable at {s} (run: just infra-run-llamacpp-cpu)", .{getEndpoint()});
            return error.SkipZigTest;
        },
        else => return err,
    };
    defer resp.deinit(allocator);

    try std.testing.expect(resp.content.len > 0);
}

test "model tile http: response has valid finish reason" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = makeAiInfraRequest(getModelId());

    const resp = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => return error.SkipZigTest,
        else => return err,
    };
    defer resp.deinit(allocator);

    // finish_reason is "stop" when model completed normally, "length" when truncated.
    const ok = std.mem.eql(u8, resp.finish_reason, "stop") or
        std.mem.eql(u8, resp.finish_reason, "length");
    try std.testing.expect(ok);
}

test "model tile http: token usage is non-zero" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = makeAiInfraRequest(getModelId());

    const resp = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => return error.SkipZigTest,
        else => return err,
    };
    defer resp.deinit(allocator);

    try std.testing.expect(resp.token_usage.total_tokens > 0);
    try std.testing.expect(resp.token_usage.prompt_tokens > 0);
}

test "model tile http: model_id is populated" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = makeAiInfraRequest(getModelId());

    const resp = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => return error.SkipZigTest,
        else => return err,
    };
    defer resp.deinit(allocator);

    try std.testing.expect(resp.model_id.len > 0);
}

test "model tile http: deinit does not leak" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = makeAiInfraRequest(getModelId());

    const resp = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => return error.SkipZigTest,
        else => return err,
    };
    resp.deinit(allocator);
    // std.testing.allocator will report leaks at end of test
}

test "model tile http: two sequential calls both succeed" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = makeAiInfraRequest(getModelId());

    const r1 = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => return error.SkipZigTest,
        else => return err,
    };
    defer r1.deinit(allocator);

    const r2 = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => return error.SkipZigTest,
        else => return err,
    };
    defer r2.deinit(allocator);

    try std.testing.expect(r1.content.len > 0);
    try std.testing.expect(r2.content.len > 0);
}

// Leveraged ETFs and inverse ETFs prohibited by the system prompt.
const restricted_tickers = [_][]const u8{
    "SOXL", "SOXS", "TQQQ", "SQQQ", "UPRO", "SPXS",
    "UVXY", "SVXY", "LABU", "LABD", "FAS",  "FAZ",
};

// ---------------------------------------------------------------------------
// Fixture-based tests: deterministic substitution and captured-response replay.
// These do not require a running llama.cpp server.
// ---------------------------------------------------------------------------

test "model tile fixture: replay substitution content is deterministic" {
    const allocator = std.testing.allocator;
    const req = makeAiInfraRequest("fixture.ai_infra");

    var b1 = model.Backend{ .fixture = .{} };
    const r1 = try b1.call(allocator, req);
    defer r1.deinit(allocator);

    var b2 = model.Backend{ .fixture = .{} };
    const r2 = try b2.call(allocator, req);
    defer r2.deinit(allocator);

    try std.testing.expectEqualStrings(r1.content, r2.content);
    try std.testing.expectEqualStrings(r1.model_id, r2.model_id);
    try std.testing.expectEqualStrings(r1.finish_reason, r2.finish_reason);
    try std.testing.expectEqual(r1.token_usage.prompt_tokens, r2.token_usage.prompt_tokens);
    try std.testing.expectEqual(r1.token_usage.completion_tokens, r2.token_usage.completion_tokens);
    try std.testing.expectEqual(r1.token_usage.total_tokens, r2.token_usage.total_tokens);
}

test "model tile fixture: captured response JSON matches fixture tickers and usage" {
    const allocator = std.testing.allocator;
    var backend = model.Backend{ .fixture = .{} };
    const req = makeAiInfraRequest("fixture.ai_infra");
    const resp = try backend.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("stop", resp.finish_reason);
    try std.testing.expectEqual(@as(u32, 148), resp.token_usage.prompt_tokens);
    try std.testing.expectEqual(@as(u32, 187), resp.token_usage.completion_tokens);
    try std.testing.expectEqual(@as(u32, 335), resp.token_usage.total_tokens);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.content, .{});
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |o| o,
        else => return error.TestUnexpectedResult,
    };

    const summary_v = root.get("thesis_summary") orelse return error.TestUnexpectedResult;
    const summary = switch (summary_v) {
        .string => |s| s,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expect(summary.len > 0);

    const tickers_v = root.get("recommended_tickers") orelse return error.TestUnexpectedResult;
    const tickers = switch (tickers_v) {
        .array => |a| a,
        else => return error.TestUnexpectedResult,
    };

    // All tickers from the captured fixture must be present.
    const expected = [_][]const u8{ "NVDA", "AMD", "AVGO", "MSFT", "AMZN", "BOTZ", "SOXX" };
    for (expected) |sym| {
        var found = false;
        for (tickers.items) |item| {
            switch (item) {
                .string => |s| {
                    if (std.mem.eql(u8, s, sym)) found = true;
                },
                else => {},
            }
        }
        try std.testing.expect(found);
    }

    // Captured fixture must not contain restricted instruments.
    for (tickers.items) |item| {
        const ticker = switch (item) {
            .string => |s| s,
            else => return error.TestUnexpectedResult,
        };
        for (restricted_tickers) |r| {
            if (std.mem.eql(u8, ticker, r)) {
                std.log.err("restricted ticker in captured fixture: {s}", .{ticker});
                return error.TestUnexpectedResult;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Live server tests: structured JSON, restricted ticker exclusion, rationale.
// Skipped when llama.cpp is not reachable.
// ---------------------------------------------------------------------------

test "model tile http: response is valid JSON with required fields" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = makeAiInfraRequest(getModelId());
    const resp = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => return error.SkipZigTest,
        else => return err,
    };
    defer resp.deinit(allocator);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.content, .{});
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |o| o,
        else => return error.TestUnexpectedResult,
    };

    const summary_v = root.get("thesis_summary") orelse return error.TestUnexpectedResult;
    const summary = switch (summary_v) {
        .string => |s| s,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expect(summary.len > 0);

    const tickers_v = root.get("recommended_tickers") orelse return error.TestUnexpectedResult;
    const tickers = switch (tickers_v) {
        .array => |a| a,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expect(tickers.items.len > 0);

    const rationale_v = root.get("rationale") orelse return error.TestUnexpectedResult;
    const rationale = switch (rationale_v) {
        .object => |o| o,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expect(rationale.count() > 0);
}

test "model tile http: recommended tickers exclude restricted instruments" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = makeAiInfraRequest(getModelId());
    const resp = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => return error.SkipZigTest,
        else => return err,
    };
    defer resp.deinit(allocator);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.content, .{});
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |o| o,
        else => return error.TestUnexpectedResult,
    };
    const tickers_v = root.get("recommended_tickers") orelse return error.TestUnexpectedResult;
    const tickers = switch (tickers_v) {
        .array => |a| a,
        else => return error.TestUnexpectedResult,
    };

    for (tickers.items) |item| {
        const ticker = switch (item) {
            .string => |s| s,
            else => return error.TestUnexpectedResult,
        };
        for (restricted_tickers) |r| {
            if (std.mem.eql(u8, ticker, r)) {
                std.log.err("restricted instrument in response: {s}", .{ticker});
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "model tile http: rationale covers all recommended tickers" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = makeAiInfraRequest(getModelId());
    const resp = backend.call(allocator, req) catch |err| switch (err) {
        error.ServerUnreachable => return error.SkipZigTest,
        else => return err,
    };
    defer resp.deinit(allocator);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.content, .{});
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |o| o,
        else => return error.TestUnexpectedResult,
    };

    const tickers_v = root.get("recommended_tickers") orelse return error.TestUnexpectedResult;
    const tickers = switch (tickers_v) {
        .array => |a| a,
        else => return error.TestUnexpectedResult,
    };

    const rationale_v = root.get("rationale") orelse return error.TestUnexpectedResult;
    const rationale = switch (rationale_v) {
        .object => |o| o,
        else => return error.TestUnexpectedResult,
    };

    for (tickers.items) |item| {
        const ticker = switch (item) {
            .string => |s| s,
            else => return error.TestUnexpectedResult,
        };
        try std.testing.expect(rationale.contains(ticker));
    }
}
