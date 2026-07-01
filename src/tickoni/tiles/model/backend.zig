const std = @import("std");
const schema = @import("model_messages");
const mock_model = @import("mock_model");

pub const ProviderRequest = schema.ProviderRequest;
pub const ModelResponse = schema.ModelResponse;

// MockBackend is a pure test double; its definition lives in
// src/tickoni/test/mocks/mock_model.zig, not in this tile.
const MockBackend = mock_model.MockBackend;

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
        const path = try std.fmt.bufPrint(&path_buf, "{s}/fixture_model_response_gemma4.json", .{fixture_dir});
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

    pub fn call(self: FixtureBackend, allocator: std.mem.Allocator, req: ProviderRequest) !ModelResponse {
        _ = req;
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

// ---------------------------------------------------------------------------
// Replay substitution backend
// ---------------------------------------------------------------------------

pub const max_replay_entries: usize = 16;

const replay_model_id_max: usize = 128;
const replay_content_max: usize = 2048;
const replay_finish_reason_max: usize = 32;

// Hash a ProviderRequest to a stable u64 key for replay table lookup.
pub fn hashProviderRequest(req: ProviderRequest) u64 {
    var h = std.hash.Wyhash.init(0);
    h.update(req.model_id);
    for (req.messages) |msg| {
        h.update(msg.role);
        h.update(msg.content);
    }
    h.update(std.mem.asBytes(&req.sampling));
    return h.final();
}

pub const ReplayEntry = struct {
    substitution_id: u64 = 0,
    request_hash: u64 = 0,
    response_hash: u64 = 0,
    model_id: [replay_model_id_max]u8 = [_]u8{0} ** replay_model_id_max,
    model_id_len: u8 = 0,
    content: [replay_content_max]u8 = [_]u8{0} ** replay_content_max,
    content_len: u16 = 0,
    finish_reason: [replay_finish_reason_max]u8 = [_]u8{0} ** replay_finish_reason_max,
    finish_reason_len: u8 = 0,
    token_usage: schema.TokenUsage = .{ .prompt_tokens = 0, .completion_tokens = 0, .total_tokens = 0 },
    latency_ms: u64 = 0,

    fn toModelResponse(self: ReplayEntry, allocator: std.mem.Allocator) std.mem.Allocator.Error!ModelResponse {
        const model_id = try allocator.dupe(u8, self.model_id[0..self.model_id_len]);
        errdefer allocator.free(model_id);
        const content = try allocator.dupe(u8, self.content[0..self.content_len]);
        errdefer allocator.free(content);
        const finish_reason = try allocator.dupe(u8, self.finish_reason[0..self.finish_reason_len]);
        return .{
            .model_id = model_id,
            .content = content,
            .finish_reason = finish_reason,
            .token_usage = self.token_usage,
            .latency_ms = self.latency_ms,
        };
    }
};

pub const ReplayBackend = struct {
    entries: [max_replay_entries]ReplayEntry = [_]ReplayEntry{.{}} ** max_replay_entries,
    entry_count: u8 = 0,

    // Called by the orchestrator with the explicit substitution_id from TkModlRequest.
    pub fn callById(self: ReplayBackend, allocator: std.mem.Allocator, substitution_id: u64) !ModelResponse {
        for (self.entries[0..self.entry_count]) |entry| {
            if (entry.substitution_id == substitution_id) return entry.toModelResponse(allocator);
        }
        return error.ReplaySubstitutionMissing;
    }

    // Called by Backend.call() — looks up by ProviderRequest content hash.
    pub fn call(self: ReplayBackend, allocator: std.mem.Allocator, req: ProviderRequest) !ModelResponse {
        const req_hash = hashProviderRequest(req);
        for (self.entries[0..self.entry_count]) |entry| {
            if (entry.request_hash == req_hash) return entry.toModelResponse(allocator);
        }
        return error.ReplaySubstitutionMissing;
    }
};

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

    pub fn call(self: HttpBackend, allocator: std.mem.Allocator, req: ProviderRequest) !ModelResponse {
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

// Backend dispatches between mock, fixture, http, and replay implementations.
pub const Backend = union(enum) {
    mock: MockBackend,
    fixture: FixtureBackend,
    http: HttpBackend,
    replay: ReplayBackend,

    pub fn call(self: *Backend, allocator: std.mem.Allocator, req: ProviderRequest) anyerror!ModelResponse {
        return switch (self.*) {
            .mock => |m| m.call(allocator, req),
            .fixture => |f| f.call(allocator, req),
            .http => |h| h.call(allocator, req),
            .replay => |r| r.call(allocator, req),
        };
    }

    /// Returns true when no live network calls can occur.
    /// Replay must only run with effect-free backends.
    pub fn isEffectFree(self: Backend) bool {
        return switch (self) {
            .mock, .fixture, .replay => true,
            .http => false,
        };
    }

    /// Replay-path dispatch: looks up a captured response by substitution_id.
    /// Returns error.ReplayBackendRequired when the backend variant is not .replay.
    pub fn callById(self: Backend, allocator: std.mem.Allocator, substitution_id: u64) !ModelResponse {
        return switch (self) {
            .replay => |r| r.callById(allocator, substitution_id),
            else => error.ReplayBackendRequired,
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
    const req = ProviderRequest{ .model_id = "any", .messages = &.{} };
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
    const req = ProviderRequest{ .model_id = "any", .messages = &.{} };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("mock", resp.model_id);
    try std.testing.expectEqualStrings("stop", resp.finish_reason);
}

test "MockBackend is deterministic across calls" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "deterministic output" };
    const req = ProviderRequest{ .model_id = "x", .messages = &.{} };

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
    const req = ProviderRequest{ .model_id = "any", .messages = &.{} };

    const resp = try backend.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("from mock backend", resp.content);
}

test "FixtureBackend returns deterministic response" {
    const allocator = std.testing.allocator;
    const fixture = FixtureBackend{};
    const req = ProviderRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper",
        .policy_version = "v1",
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

test "FixtureBackend.initFromDir loads fixture_model_response_gemma4.json" {
    const allocator = std.testing.allocator;
    const fixture = try FixtureBackend.initFromDir(
        allocator,
        std.testing.io,
        "src/tickoni/test/fixtures/investment/scenarios",
    );
    const req = ProviderRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper",
        .policy_version = "v1",
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
    const req = ProviderRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper",
        .policy_version = "v1",
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
        "UVXY", "SVXY", "LABU", "LABD", "FAS",  "FAZ",
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
    const req = ProviderRequest{
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
    const req = ProviderRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.demo_paper",
        .policy_version = "v1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), trace.call_count);
    try std.testing.expectEqualStrings("fixture.ai_infra", trace.last_model_id);
    try std.testing.expectEqualStrings("budget.demo_paper", trace.last_budget_id);
    try std.testing.expectEqualStrings("v1", trace.last_policy_version);
    try std.testing.expectEqualStrings("capenv.trading_order.propose.demo", trace.last_capability_envelope_id);
}

test "ModelResponse token_usage fields accessible" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "x" };
    const req = ProviderRequest{ .model_id = "any", .messages = &.{} };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.prompt_tokens);
    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.completion_tokens);
    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.total_tokens);
}

test "Backend.isEffectFree tracks live network boundaries" {
    const mock = Backend{ .mock = .{ .canned_content = "mock" } };
    const fixture = Backend{ .fixture = .{} };
    const http = Backend{ .http = .{ .endpoint = "http://127.0.0.1:65535/v1", .io = std.testing.io } };

    try std.testing.expect(mock.isEffectFree());
    try std.testing.expect(fixture.isEffectFree());
    try std.testing.expect(!http.isEffectFree());
}

// ---------------------------------------------------------------------------
// ReplayBackend tests
// ---------------------------------------------------------------------------

fn makeReplayEntry(substitution_id: u64, request_hash: u64, content_str: []const u8) ReplayEntry {
    var entry = ReplayEntry{};
    entry.substitution_id = substitution_id;
    entry.request_hash = request_hash;
    entry.response_hash = std.hash.Wyhash.hash(0, content_str);
    const mid = "replay-model";
    entry.model_id_len = mid.len;
    @memcpy(entry.model_id[0..mid.len], mid);
    entry.content_len = @intCast(content_str.len);
    @memcpy(entry.content[0..content_str.len], content_str);
    const fr = "stop";
    entry.finish_reason_len = fr.len;
    @memcpy(entry.finish_reason[0..fr.len], fr);
    entry.token_usage = .{ .prompt_tokens = 10, .completion_tokens = 20, .total_tokens = 30 };
    entry.latency_ms = 42;
    return entry;
}

test "ReplayBackend.callById succeeds with matching substitution_id" {
    var rb = ReplayBackend{};
    rb.entries[0] = makeReplayEntry(99, 0, "{\"ticker\":\"NVDA\"}");
    rb.entry_count = 1;

    const resp = try rb.callById(std.testing.allocator, 99);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("{\"ticker\":\"NVDA\"}", resp.content);
    try std.testing.expectEqualStrings("replay-model", resp.model_id);
    try std.testing.expectEqualStrings("stop", resp.finish_reason);
    try std.testing.expectEqual(@as(u32, 30), resp.token_usage.total_tokens);
    try std.testing.expectEqual(@as(u64, 42), resp.latency_ms);
}

test "ReplayBackend.callById fails closed when substitution_id not present" {
    const rb = ReplayBackend{};
    try std.testing.expectError(error.ReplaySubstitutionMissing, rb.callById(std.testing.allocator, 1));
}

test "ReplayBackend.callById fails closed when id does not match any entry" {
    var rb = ReplayBackend{};
    rb.entries[0] = makeReplayEntry(10, 0, "response");
    rb.entry_count = 1;
    try std.testing.expectError(error.ReplaySubstitutionMissing, rb.callById(std.testing.allocator, 99));
}

test "ReplayBackend.call succeeds with matching request hash" {
    const req = ProviderRequest{ .model_id = "test-model", .messages = &.{} };
    const req_hash = hashProviderRequest(req);

    var rb = ReplayBackend{};
    rb.entries[0] = makeReplayEntry(0, req_hash, "{\"ticker\":\"AMD\"}");
    rb.entry_count = 1;

    const resp = try rb.call(std.testing.allocator, req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("{\"ticker\":\"AMD\"}", resp.content);
}

test "ReplayBackend.call fails closed when request hash does not match" {
    const req_a = ProviderRequest{ .model_id = "model-a", .messages = &.{} };
    const req_b = ProviderRequest{ .model_id = "model-b", .messages = &.{} };

    var rb = ReplayBackend{};
    rb.entries[0] = makeReplayEntry(0, hashProviderRequest(req_a), "response-a");
    rb.entry_count = 1;

    try std.testing.expectError(error.ReplaySubstitutionMissing, rb.call(std.testing.allocator, req_b));
}

test "ReplayBackend.call fails closed on empty table" {
    const req = ProviderRequest{ .model_id = "any", .messages = &.{} };
    const rb = ReplayBackend{};
    try std.testing.expectError(error.ReplaySubstitutionMissing, rb.call(std.testing.allocator, req));
}

test "Backend.isEffectFree is true for replay variant" {
    const b = Backend{ .replay = .{} };
    try std.testing.expect(b.isEffectFree());
}

test "Backend.call dispatches to ReplayBackend by request hash" {
    const req = ProviderRequest{ .model_id = "replay-test", .messages = &.{} };
    var rb = ReplayBackend{};
    rb.entries[0] = makeReplayEntry(0, hashProviderRequest(req), "{\"ok\":true}");
    rb.entry_count = 1;

    var b = Backend{ .replay = rb };
    const resp = try b.call(std.testing.allocator, req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("{\"ok\":true}", resp.content);
}

test "hashProviderRequest differs for different model ids" {
    const r1 = ProviderRequest{ .model_id = "model-a", .messages = &.{} };
    const r2 = ProviderRequest{ .model_id = "model-b", .messages = &.{} };
    try std.testing.expect(hashProviderRequest(r1) != hashProviderRequest(r2));
}

test "hashProviderRequest is deterministic" {
    const req = ProviderRequest{ .model_id = "m", .messages = &.{.{ .role = "user", .content = "hello" }} };
    try std.testing.expectEqual(hashProviderRequest(req), hashProviderRequest(req));
}
