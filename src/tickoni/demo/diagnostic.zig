const std = @import("std");

pub const Code = enum {
    unsupported_runtime_tier,
    missing_fixture,
    stale_manifest,
    attempted_live_execution,
    tampered_replay_artifact,
    tampered_proposal_artifact,
    missing_isolation_prerequisite,

    pub fn label(self: Code) []const u8 {
        return switch (self) {
            .unsupported_runtime_tier => "unsupported_runtime_tier",
            .missing_fixture => "missing_fixture",
            .stale_manifest => "stale_manifest",
            .attempted_live_execution => "attempted_live_execution",
            .tampered_replay_artifact => "tampered_replay_artifact",
            .tampered_proposal_artifact => "tampered_proposal_artifact",
            .missing_isolation_prerequisite => "missing_isolation_prerequisite",
        };
    }
};

pub const BlockedFlowDiagnostic = struct {
    code: Code,
    message: []const u8,
    field: ?[]const u8 = null,
    expected: ?[]const u8 = null,
    found: ?[]const u8 = null,

    pub fn writePlain(self: BlockedFlowDiagnostic, writer: anytype) !void {
        try writer.print("blocked_code: {s}\nmessage: {s}\n", .{ self.code.label(), self.message });
        if (self.field) |field| try writer.print("field: {s}\n", .{field});
        if (self.expected) |expected| try writer.print("expected: {s}\n", .{expected});
        if (self.found) |found| try writer.print("found: {s}\n", .{found});
    }
};

test "all blocked diagnostic codes have stable labels" {
    const cases = [_]struct { code: Code, label: []const u8 }{
        .{ .code = .unsupported_runtime_tier, .label = "unsupported_runtime_tier" },
        .{ .code = .missing_fixture, .label = "missing_fixture" },
        .{ .code = .stale_manifest, .label = "stale_manifest" },
        .{ .code = .attempted_live_execution, .label = "attempted_live_execution" },
        .{ .code = .tampered_replay_artifact, .label = "tampered_replay_artifact" },
        .{ .code = .tampered_proposal_artifact, .label = "tampered_proposal_artifact" },
        .{ .code = .missing_isolation_prerequisite, .label = "missing_isolation_prerequisite" },
    };
    for (cases) |case| {
        try std.testing.expectEqualStrings(case.label, case.code.label());
    }
}

test "blocked diagnostic plain formatter emits optional fields" {
    const diagnostic = BlockedFlowDiagnostic{
        .code = .missing_fixture,
        .message = "fixture file is absent",
        .field = "required_fixtures",
        .expected = "investment_sample",
        .found = "",
    };

    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try diagnostic.writePlain(&writer);
    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "missing_fixture") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "required_fixtures") != null);
}
