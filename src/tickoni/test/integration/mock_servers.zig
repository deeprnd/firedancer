const std = @import("std");
const broker_mock = @import("mock_broker_market_server.zig");
const openai_mock = @import("mock_openai_server.zig");

test "integration mock openai server config defaults are stable" {
    const config = openai_mock.Config{};
    try std.testing.expectEqualStrings("mock-openai-model", config.model_id);
    try std.testing.expectEqualStrings("stop", config.finish_reason);
    try std.testing.expectEqual(@as(u32, 28), config.total_tokens);
}

test "integration mock broker server config defaults are stable" {
    const config = broker_mock.Config{};
    try std.testing.expectEqualStrings("ok", config.health_body);
    try std.testing.expect(std.mem.indexOf(u8, config.portfolio_json, "\"account_id\":2001") != null);
    try std.testing.expect(std.mem.indexOf(u8, config.paper_order_json, "\"paper_order_id\":\"mock-paper-order-1\"") != null);
}

test "integration mock server helpers compile and expose startable server types" {
    var openai_server = try openai_mock.Server.init(std.testing.io, .{});
    defer openai_server.listener.deinit(std.testing.io);
    var broker_server = try broker_mock.Server.init(std.testing.io, .{});
    defer broker_server.listener.deinit(std.testing.io);

    try std.testing.expect(openai_server.thread == null);
    try std.testing.expect(broker_server.thread == null);
}
