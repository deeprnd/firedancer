const std = @import("std");
const model_messages = @import("model_messages");

const ProviderRequest = model_messages.ProviderRequest;
const ModelResponse = model_messages.ModelResponse;

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

    pub fn call(self: MockBackend, allocator: std.mem.Allocator, req: ProviderRequest) error{OutOfMemory}!ModelResponse {
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
