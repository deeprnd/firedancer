const std = @import("std");
const schema = @import("schema.zig");

pub const ModelRequest = schema.ModelRequest;
pub const ModelResponse = schema.ModelResponse;

// MockBackend returns a pre-set canned response. Used in unit tests.
pub const MockBackend = struct {
    canned_content: []const u8,
    canned_model_id: []const u8 = "mock",
    canned_finish_reason: []const u8 = "stop",

    pub fn call(self: MockBackend, allocator: std.mem.Allocator, req: ModelRequest) error{OutOfMemory}!ModelResponse {
        _ = req;
        return .{
            .model_id = try allocator.dupe(u8, self.canned_model_id),
            .content = try allocator.dupe(u8, self.canned_content),
            .finish_reason = try allocator.dupe(u8, self.canned_finish_reason),
            .token_usage = .{ .prompt_tokens = 0, .completion_tokens = 0, .total_tokens = 0 },
            .latency_ms = 0,
        };
    }
};

pub const FixtureBackend = struct {
    pub fn call(_: FixtureBackend, allocator: std.mem.Allocator, req: ModelRequest) error{OutOfMemory}!ModelResponse {
        _ = req;
        return .{
            .model_id = try allocator.dupe(u8, "unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL"),
            .content = try allocator.dupe(
                u8,
                "{\"thesis_summary\":\"USD 2,000 into AI infrastructure via diversified US-listed large-cap equities and ETFs.\",\"recommended_tickers\":[\"NVDA\",\"AMD\",\"AVGO\",\"MSFT\",\"AMZN\",\"BOTZ\",\"SOXX\"]}",
            ),
            .finish_reason = try allocator.dupe(u8, "stop"),
            .token_usage = .{ .prompt_tokens = 148, .completion_tokens = 187, .total_tokens = 335 },
            .latency_ms = 842,
        };
    }
};

// Strip thinking-channel prefix emitted by some models (e.g. Gemma-4):
//   <|channel>thought\n...<channel|>ACTUAL_CONTENT
// Returns the slice starting after <channel|>, or the original string.
fn stripThinkingChannel(s: []const u8) []const u8 {
    const delim = "<channel|>";
    if (std.mem.indexOf(u8, s, delim)) |pos| {
        return s[pos + delim.len ..];
    }
    return s;
}

// Strip ```json or ``` fences when they wrap the entire content.
fn stripMarkdownFence(s: []const u8) []const u8 {
    const prefixes = [_][]const u8{ "```json\n", "```\n" };
    const suffix = "\n```";
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, s, prefix) and std.mem.endsWith(u8, s, suffix)) {
            return s[prefix.len .. s.len - suffix.len];
        }
    }
    return s;
}

fn normalizeModelContent(raw: []const u8) []const u8 {
    const after_channel = std.mem.trim(u8, stripThinkingChannel(raw), " \t\r\n");
    return stripMarkdownFence(after_channel);
}

// Wire types for the OpenAI-compatible chat completions API.
const WireRequest = struct {
    model: []const u8,
    messages: []const schema.Message,
    temperature: f32,
    top_p: f32,
    max_tokens: u32,
    seed: u64,
    stream: bool,
};

const WireChoice = struct {
    message: struct {
        content: []const u8,
    },
    finish_reason: ?[]const u8 = null,
};

const WireUsage = struct {
    prompt_tokens: u32 = 0,
    completion_tokens: u32 = 0,
    total_tokens: u32 = 0,
};

const WireResponse = struct {
    model: ?[]const u8 = null,
    choices: []const WireChoice,
    usage: WireUsage = .{},
};

// HttpBackend calls an OpenAI-compatible llama.cpp server.
// endpoint must be a base URL like "http://127.0.0.1:8080/v1".
// io is the std.Io instance for TCP connections (use std.testing.io in tests).
pub const HttpBackend = struct {
    endpoint: []const u8,
    io: std.Io,

    pub fn call(self: HttpBackend, allocator: std.mem.Allocator, req: ModelRequest) !ModelResponse {
        const url = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.endpoint});
        defer allocator.free(url);

        const wire_req = WireRequest{
            .model = req.model_id,
            .messages = req.messages,
            .temperature = req.sampling.temperature,
            .top_p = req.sampling.top_p,
            .max_tokens = req.sampling.max_output_tokens,
            .seed = req.sampling.seed,
            .stream = false,
        };

        const json_body = try std.json.Stringify.valueAlloc(allocator, wire_req, .{});
        defer allocator.free(json_body);

        var client = std.http.Client{ .allocator = allocator, .io = self.io };
        defer client.deinit();

        var resp_writer: std.Io.Writer.Allocating = .init(allocator);
        defer resp_writer.deinit();

        const fetch_result = client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
            .payload = json_body,
            .response_writer = &resp_writer.writer,
        }) catch |err| switch (err) {
            error.ConnectionRefused, error.NetworkUnreachable, error.HostUnreachable => return error.ServerUnreachable,
            else => return err,
        };

        if (fetch_result.status != .ok) return error.HttpStatusError;

        const resp_bytes = resp_writer.written();

        var parsed = try std.json.parseFromSlice(WireResponse, allocator, resp_bytes, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return error.EmptyChoices;

        const choice = parsed.value.choices[0];

        const model_id = try allocator.dupe(u8, parsed.value.model orelse req.model_id);
        errdefer allocator.free(model_id);

        const content = try allocator.dupe(u8, normalizeModelContent(choice.message.content));
        errdefer allocator.free(content);

        const finish_reason = try allocator.dupe(u8, choice.finish_reason orelse "unknown");

        return .{
            .model_id = model_id,
            .content = content,
            .finish_reason = finish_reason,
            .token_usage = .{
                .prompt_tokens = parsed.value.usage.prompt_tokens,
                .completion_tokens = parsed.value.usage.completion_tokens,
                .total_tokens = parsed.value.usage.total_tokens,
            },
            .latency_ms = 0,
        };
    }
};

// Backend dispatches between mock and http implementations.
// Use .mock in unit tests, .http in integration tests.
pub const Backend = union(enum) {
    mock: MockBackend,
    fixture: FixtureBackend,
    http: HttpBackend,

    pub fn call(self: *Backend, allocator: std.mem.Allocator, req: ModelRequest) anyerror!ModelResponse {
        return switch (self.*) {
            .mock => |m| m.call(allocator, req),
            .fixture => |f| f.call(allocator, req),
            .http => |h| h.call(allocator, req),
        };
    }
};

// ---------------------------------------------------------------------------
// Unit tests: MockBackend and Backend dispatch. No network calls.
// ---------------------------------------------------------------------------

test "normalizeModelContent strips json fence" {
    try std.testing.expectEqualStrings("{}", normalizeModelContent("```json\n{}\n```"));
}

test "normalizeModelContent strips plain fence" {
    try std.testing.expectEqualStrings("{}", normalizeModelContent("```\n{}\n```"));
}

test "normalizeModelContent passes through plain JSON" {
    try std.testing.expectEqualStrings("{\"a\":1}", normalizeModelContent("{\"a\":1}"));
}

test "normalizeModelContent strips thinking channel then fence" {
    const input = "<|channel>thought\nsome reasoning<channel|>```json\n{\"k\":\"v\"}\n```";
    try std.testing.expectEqualStrings("{\"k\":\"v\"}", normalizeModelContent(input));
}

test "normalizeModelContent strips thinking channel plain text" {
    const input = "<|channel>thought\nsome reasoning<channel|>hello";
    try std.testing.expectEqualStrings("hello", normalizeModelContent(input));
}

test "MockBackend returns canned response" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{
        .canned_content = "test response",
        .canned_model_id = "mock-v1",
    };
    const req = ModelRequest{ .model_id = "any", .messages = &.{} };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("test response", resp.content);
    try std.testing.expectEqualStrings("mock-v1", resp.model_id);
    try std.testing.expectEqualStrings("stop", resp.finish_reason);
    try std.testing.expectEqual(@as(u64, 0), resp.latency_ms);
    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.total_tokens);
}

test "MockBackend default model_id and finish_reason" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "hello" };
    const req = ModelRequest{ .model_id = "any", .messages = &.{} };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("mock", resp.model_id);
    try std.testing.expectEqualStrings("stop", resp.finish_reason);
}

test "MockBackend is deterministic across calls" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "deterministic output" };
    const req = ModelRequest{ .model_id = "x", .messages = &.{} };

    const r1 = try mock.call(allocator, req);
    defer r1.deinit(allocator);
    const r2 = try mock.call(allocator, req);
    defer r2.deinit(allocator);

    try std.testing.expectEqualStrings(r1.content, r2.content);
    try std.testing.expectEqualStrings(r1.model_id, r2.model_id);
    try std.testing.expectEqualStrings(r1.finish_reason, r2.finish_reason);
    try std.testing.expectEqual(r1.token_usage.total_tokens, r2.token_usage.total_tokens);
}

test "Backend union dispatches to mock" {
    const allocator = std.testing.allocator;
    var backend = Backend{ .mock = .{ .canned_content = "from mock backend" } };
    const req = ModelRequest{ .model_id = "any", .messages = &.{} };

    const resp = try backend.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("from mock backend", resp.content);
}

test "FixtureBackend returns deterministic response" {
    const allocator = std.testing.allocator;
    const fixture = FixtureBackend{};
    const req = ModelRequest{ .model_id = "fixture", .messages = &.{} };

    const resp = try fixture.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings(
        "unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL",
        resp.model_id,
    );
    try std.testing.expect(std.mem.indexOf(u8, resp.content, "NVDA") != null);
    try std.testing.expectEqual(@as(u32, 335), resp.token_usage.total_tokens);
    try std.testing.expectEqual(@as(u64, 842), resp.latency_ms);
}

test "MockBackend ignores request model_id and messages" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "fixed" };
    const messages = [_]schema.Message{
        .{ .role = "user", .content = "hello" },
    };
    const req = ModelRequest{
        .model_id = "gpt-999",
        .messages = &messages,
        .sampling = .{ .temperature = 0.8, .max_output_tokens = 1024 },
    };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("fixed", resp.content);
}

test "ModelResponse token_usage fields accessible" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "x" };
    const req = ModelRequest{ .model_id = "any", .messages = &.{} };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.prompt_tokens);
    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.completion_tokens);
    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.total_tokens);
}
