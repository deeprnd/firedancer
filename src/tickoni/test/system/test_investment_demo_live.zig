const demo = @import("investment_demo");
const std = @import("std");

test "system demo live: real tkmodl, allowed, blocked, restricted, replay proof" {
    const allocator = std.testing.allocator;
    const endpoint = try demo.envOrDefault(allocator, "TK_LLM_ENDPOINT", demo.default_endpoint);
    defer allocator.free(endpoint);
    const model_id = try demo.envOrDefault(allocator, "TK_LLM_MODEL_ID", demo.default_model_id);
    defer allocator.free(model_id);

    try demo.runSystemSuite(allocator, std.testing.io, .{
        .endpoint = endpoint,
        .model_id = model_id,
    });
}
