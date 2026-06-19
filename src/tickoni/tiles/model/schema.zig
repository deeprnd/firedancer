const std = @import("std");

pub const SamplingParams = struct {
    temperature: f32 = 0,
    top_p: f32 = 1.0,
    max_output_tokens: u32 = 512,
    seed: u64 = 42,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const ModelRequest = struct {
    model_id: []const u8,
    messages: []const Message,
    sampling: SamplingParams = .{},
    budget_id: []const u8 = "",
    policy_version: []const u8 = "",
    capability_envelope_id: []const u8 = "",
};

pub const TokenUsage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
};

// Caller owns all slice fields; call deinit(allocator) when done.
pub const ModelResponse = struct {
    model_id: []const u8,
    content: []const u8,
    finish_reason: []const u8,
    token_usage: TokenUsage,
    latency_ms: u64,

    pub fn deinit(self: ModelResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.model_id);
        allocator.free(self.content);
        allocator.free(self.finish_reason);
    }
};

test "ModelResponse deinit frees all fields" {
    const allocator = std.testing.allocator;
    const resp = ModelResponse{
        .model_id = try allocator.dupe(u8, "test-model"),
        .content = try allocator.dupe(u8, "hello"),
        .finish_reason = try allocator.dupe(u8, "stop"),
        .token_usage = .{ .prompt_tokens = 10, .completion_tokens = 5, .total_tokens = 15 },
        .latency_ms = 100,
    };
    resp.deinit(allocator);
}
