const std = @import("std");
const schema = @import("schema.zig");

pub const ModelRequest = schema.ModelRequest;
pub const ModelResponse = schema.ModelResponse;

// MockBackend returns a pre-set canned response. Used in unit tests.
pub const MockBackend = struct {
    pub const CallTrace = struct {
        call_count: usize = 0,
        last_model_id: []const u8 = "",
        last_budget_id: []const u8 = "",
        last_policy_version: []const u8 = "",
        last_capability_envelope_id: []const u8 = "",
    };

    canned_content: []const u8,
    canned_model_id: []const u8 = "mock",
    canned_finish_reason: []const u8 = "stop",
    trace: ?*CallTrace = null,

    pub fn call(self: MockBackend, allocator: std.mem.Allocator, req: ModelRequest) error{OutOfMemory}!ModelResponse {
        if (self.trace) |trace| {
            trace.call_count += 1;
            trace.last_model_id = req.model_id;
            trace.last_budget_id = req.budget_id;
            trace.last_policy_version = req.policy_version;
            trace.last_capability_envelope_id = req.capability_envelope_id;
        }
        return .{
            .model_id = try allocator.dupe(u8, self.canned_model_id),
            .content = try allocator.dupe(u8, self.canned_content),
            .finish_reason = try allocator.dupe(u8, self.canned_finish_reason),
            .token_usage = .{ .prompt_tokens = 0, .completion_tokens = 0, .total_tokens = 0 },
            .latency_ms = 0,
        };
    }
};

const fixture_allowed_model_ids = [_][]const u8{
    "fixture.ai_infra",
};

const fixture_model_id_max: usize = 128;
const fixture_content_max: usize = 2048;
const fixture_finish_reason_max: usize = 32;

const default_model_id_str = "unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL";
const default_content_str = "{\"thesis_summary\":\"USD 2,000 into AI infrastructure via diversified US-listed large-cap equities and ETFs.\",\"recommended_tickers\":[\"NVDA\",\"AMD\",\"AVGO\",\"MSFT\",\"AMZN\",\"BOTZ\",\"SOXX\"]}";
const default_finish_reason_str = "stop";

const default_model_id_buf: [fixture_model_id_max]u8 = blk: {
    var buf = [_]u8{0} ** fixture_model_id_max;
    for (default_model_id_str, 0..) |c, i| buf[i] = c;
    break :blk buf;
};
const default_content_buf: [fixture_content_max]u8 = blk: {
    var buf = [_]u8{0} ** fixture_content_max;
    for (default_content_str, 0..) |c, i| buf[i] = c;
    break :blk buf;
};
const default_finish_reason_buf: [fixture_finish_reason_max]u8 = blk: {
    var buf = [_]u8{0} ** fixture_finish_reason_max;
    for (default_finish_reason_str, 0..) |c, i| buf[i] = c;
    break :blk buf;
};

const ModelResponseFileWire = struct {
    model_id: []const u8,
    token_usage: schema.TokenUsage,
    latency_ms: u64,
    finish_reason: []const u8,
    content: std.json.Value,
};

pub const FixtureBackend = struct {
    model_id: [fixture_model_id_max]u8 = default_model_id_buf,
    model_id_len: u8 = default_model_id_str.len,
    content: [fixture_content_max]u8 = default_content_buf,
    content_len: u16 = default_content_str.len,
    finish_reason: [fixture_finish_reason_max]u8 = default_finish_reason_buf,
    finish_reason_len: u8 = default_finish_reason_str.len,
    token_usage: schema.TokenUsage = .{ .prompt_tokens = 148, .completion_tokens = 187, .total_tokens = 335 },
    latency_ms: u64 = 842,

    pub fn initFromDir(
        allocator: std.mem.Allocator,
        io: std.Io,
        fixture_dir: []const u8,
    ) !FixtureBackend {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/model_response_gemma4.json", .{fixture_dir});
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(32 * 1024));
        defer allocator.free(raw);
        const parsed = try std.json.parseFromSlice(ModelResponseFileWire, allocator, raw, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const w = parsed.value;
        var self = FixtureBackend{};
        if (w.model_id.len > fixture_model_id_max) return error.ModelIdTooLong;
        self.model_id_len = @intCast(w.model_id.len);
        @memcpy(self.model_id[0..w.model_id.len], w.model_id);
        if (w.finish_reason.len > fixture_finish_reason_max) return error.FinishReasonTooLong;
        self.finish_reason_len = @intCast(w.finish_reason.len);
        @memcpy(self.finish_reason[0..w.finish_reason.len], w.finish_reason);
        self.token_usage = w.token_usage;
        self.latency_ms = w.latency_ms;
        const content_json = try std.json.Stringify.valueAlloc(allocator, w.content, .{});
        defer allocator.free(content_json);
        if (content_json.len > fixture_content_max) return error.ContentTooLarge;
        self.content_len = @intCast(content_json.len);
        @memcpy(self.content[0..content_json.len], content_json);
        return self;
    }

    pub fn call(self: FixtureBackend, allocator: std.mem.Allocator, req: ModelRequest) !ModelResponse {
        var model_allowed = false;
        for (fixture_allowed_model_ids) |id| {
            if (std.mem.eql(u8, req.model_id, id)) {
                model_allowed = true;
                break;
            }
        }
        if (!model_allowed) return error.ModelNotAllowed;
        if (req.budget_id.len == 0) return error.MissingBudgetId;
        if (req.policy_version.len == 0) return error.MissingPolicyVersion;
        if (req.capability_envelope_id.len == 0) return error.MissingCapabilityEnvelopeId;
        return .{
            .model_id = try allocator.dupe(u8, self.model_id[0..self.model_id_len]),
            .content = try allocator.dupe(u8, self.content[0..self.content_len]),
            .finish_reason = try allocator.dupe(u8, self.finish_reason[0..self.finish_reason_len]),
            .token_usage = self.token_usage,
            .latency_ms = self.latency_ms,
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
// allowed_model_ids: non-empty slice restricts which model IDs are accepted; empty allows any.
pub const HttpBackend = struct {
    endpoint: []const u8,
    io: std.Io,
    allowed_model_ids: []const []const u8 = &.{},

    pub fn call(self: HttpBackend, allocator: std.mem.Allocator, req: ModelRequest) !ModelResponse {
        if (req.budget_id.len == 0) return error.MissingBudgetId;
        if (req.policy_version.len == 0) return error.MissingPolicyVersion;
        if (self.allowed_model_ids.len > 0) {
            var model_allowed = false;
            for (self.allowed_model_ids) |id| {
                if (std.mem.eql(u8, req.model_id, id)) {
                    model_allowed = true;
                    break;
                }
            }
            if (!model_allowed) return error.ModelNotAllowed;
        }
        // Arena for HTTP transport intermediates (url, body, client, response buffer,
        // parsed wire types). Only the three returned strings use the caller's
        // allocator so GPA never sees connection-pool state that std.http.Client
        // leaves behind after deinit in Zig 0.16.
        var http_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer http_arena.deinit();
        const http_alloc = http_arena.allocator();

        const url = try std.fmt.allocPrint(http_alloc, "{s}/chat/completions", .{self.endpoint});

        const wire_req = WireRequest{
            .model = req.model_id,
            .messages = req.messages,
            .temperature = req.sampling.temperature,
            .top_p = req.sampling.top_p,
            .max_tokens = req.sampling.max_output_tokens,
            .seed = req.sampling.seed,
            .stream = false,
        };

        const json_body = try std.json.Stringify.valueAlloc(http_alloc, wire_req, .{});

        var client = std.http.Client{ .allocator = http_alloc, .io = self.io };
        defer client.deinit();

        var resp_writer: std.Io.Writer.Allocating = .init(http_alloc);

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

        const parsed = try std.json.parseFromSlice(WireResponse, http_alloc, resp_bytes, .{
            .ignore_unknown_fields = true,
        });

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

    /// Returns true when no live network calls can occur.
    /// Replay must only run with effect-free backends.
    pub fn isEffectFree(self: Backend) bool {
        return switch (self) {
            .mock, .fixture => true,
            .http => false,
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
    const req = ModelRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    };

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

test "FixtureBackend rejects unknown model_id" {
    const allocator = std.testing.allocator;
    const fixture = FixtureBackend{};
    const req = ModelRequest{
        .model_id = "unknown-model",
        .messages = &.{},
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
    };
    try std.testing.expectError(error.ModelNotAllowed, fixture.call(allocator, req));
}

test "FixtureBackend rejects empty budget_id" {
    const allocator = std.testing.allocator;
    const fixture = FixtureBackend{};
    const req = ModelRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "",
        .policy_version = "v1.1",
    };
    try std.testing.expectError(error.MissingBudgetId, fixture.call(allocator, req));
}

test "FixtureBackend rejects empty policy_version" {
    const allocator = std.testing.allocator;
    const fixture = FixtureBackend{};
    const req = ModelRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "",
    };
    try std.testing.expectError(error.MissingPolicyVersion, fixture.call(allocator, req));
}

test "FixtureBackend rejects empty capability_envelope_id" {
    const allocator = std.testing.allocator;
    const fixture = FixtureBackend{};
    const req = ModelRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
        .capability_envelope_id = "",
    };
    try std.testing.expectError(error.MissingCapabilityEnvelopeId, fixture.call(allocator, req));
}

test "FixtureBackend.initFromDir loads model_response_gemma4.json" {
    const allocator = std.testing.allocator;
    const fixture = try FixtureBackend.initFromDir(
        allocator,
        std.testing.io,
        "src/tickoni/test/fixtures/investment",
    );
    const req = ModelRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    };
    const resp = try fixture.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL", resp.model_id);
    try std.testing.expectEqualStrings("stop", resp.finish_reason);
    try std.testing.expectEqual(@as(u32, 335), resp.token_usage.total_tokens);
    try std.testing.expectEqual(@as(u64, 842), resp.latency_ms);
    try std.testing.expect(std.mem.indexOf(u8, resp.content, "NVDA") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.content, "rationale") != null);
}

test "FixtureBackend response JSON matches expected tickers and excludes restricted products" {
    const allocator = std.testing.allocator;
    const fixture = FixtureBackend{};
    const req = ModelRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    };
    const resp = try fixture.call(allocator, req);
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

    const restricted = [_][]const u8{
        "SOXL", "SOXS", "TQQQ", "SQQQ", "UPRO", "SPXS",
        "UVXY", "SVXY", "LABU", "LABD", "FAS", "FAZ",
    };
    for (tickers.items) |item| {
        const ticker = switch (item) {
            .string => |s| s,
            else => return error.TestUnexpectedResult,
        };
        for (restricted) |denied| {
            try std.testing.expect(!std.mem.eql(u8, ticker, denied));
        }
    }
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

test "MockBackend traces the model request scope fields" {
    const allocator = std.testing.allocator;
    var trace = MockBackend.CallTrace{};
    const mock = MockBackend{
        .canned_content = "fixed",
        .trace = &trace,
    };
    const req = ModelRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper.v1_1",
        .policy_version = "v1.1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), trace.call_count);
    try std.testing.expectEqualStrings("fixture.ai_infra", trace.last_model_id);
    try std.testing.expectEqualStrings("budget.demo_paper.v1_1", trace.last_budget_id);
    try std.testing.expectEqualStrings("v1.1", trace.last_policy_version);
    try std.testing.expectEqualStrings("capenv.trading_order.propose.demo", trace.last_capability_envelope_id);
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

test "Backend.isEffectFree tracks live network boundaries" {
    const mock = Backend{ .mock = .{ .canned_content = "mock" } };
    const fixture = Backend{ .fixture = .{} };
    const http = Backend{ .http = .{
        .endpoint = "http://127.0.0.1:65535/v1",
        .io = std.testing.io,
    } };

    try std.testing.expect(mock.isEffectFree());
    try std.testing.expect(fixture.isEffectFree());
    try std.testing.expect(!http.isEffectFree());
}
