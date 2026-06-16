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
    "Thesis: I want to invest USD 2,000 in AI infrastructure, but avoid single-name concentration " ++
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
    };
}

test "model tile http: hello round-trip" {
    const allocator = std.testing.allocator;
    var backend = makeBackend();
    const req = model.ModelRequest{
        .model_id = getModelId(),
        .messages = &.{.{ .role = "user", .content = "Reply with the single word: hello" }},
        .sampling = .{ .temperature = 0, .max_output_tokens = 256, .seed = 1 },
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

test "model tile http: ai infrastructure thesis returns non-empty content" {
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
