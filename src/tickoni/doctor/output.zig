/// Doctor output formatting — text and JSON modes.
///
/// Scaffold only — formats hardcoded Result values. T6 implements real logic.
const std = @import("std");
const checks = @import("checks.zig");
const Result = checks.Result;
const Status = checks.Status;

/// Format doctor results as text output.
pub fn formatText(results: []const Result, platform_tier: []const u8, w: *std.Io.Writer) !void {
    try w.print("tickoni doctor — host report\n", .{});
    var pass_count: usize = 0;
    var warn_count: usize = 0;
    var fail_count: usize = 0;
    for (results) |r| {
        try r.toString(w);
        switch (r.status) {
            .pass => pass_count += 1,
            .warn => warn_count += 1,
            .fail => fail_count += 1,
        }
    }
    try w.print("Platform tier: {s}\n", .{platform_tier});
    try w.print("Checks: {d} pass, {d} warn, {d} fail\n", .{
        pass_count, warn_count, fail_count,
    });
}

/// Format doctor results as JSON output.
pub fn formatJson(results: []const Result, platform_tier: []const u8, w: *std.Io.Writer) !void {
    try w.writeAll("{\n");
    try w.print("  \"platform_tier\": \"{s}\",\n", .{platform_tier});
    try w.writeAll("  \"checks\": [\n");
    for (results, 0..) |r, i| {
        const status_str = switch (r.status) {
            .pass => "pass",
            .warn => "warn",
            .fail => "fail",
        };
        try w.print("    {{\"name\": \"{s}\", \"status\": \"{s}\", \"message\": \"{s}\"}}", .{
            r.name,
            status_str,
            r.message,
        });
        if (i < results.len - 1) try w.writeAll(",");
        try w.writeAll("\n");
    }
    try w.writeAll("  ]\n");
    try w.writeAll("}\n");
}

/// Run doctor and output in the specified format.
pub fn runAndFormat(
    gpa: std.mem.Allocator,
    fmt: enum { text, json },
    writer: anytype,
) !void {
    // Scaffold: run checks, collect results, format output
    var results_list = std.ArrayList(Result).initCapacity(gpa, 0) catch unreachable;
    defer results_list.deinit(gpa);

    for (0..11) |i| {
        // Scaffold: create placeholder results
        var r = Result{
            .name = "placeholder",
            .status = .warn,
            .message = "scaffold — not implemented",
        };
        switch (i) {
            0 => r.name = "os",
            1 => r.name = "architecture",
            2 => r.name = "environment",
            3 => r.name = "zig",
            4 => r.name = "git",
            5 => r.name = "make",
            6 => r.name = "fixtures",
            7 => r.name = "model_mode",
            8 => r.name = "storage",
            9 => r.name = "live_execution",
            10 => r.name = "source_build",
            else => break,
        }
        try results_list.append(gpa, r);
    }

    const results = results_list.items;
    const platform_tier = "macos_retail"; // TODO: wire to detectTier() in T6

    switch (fmt) {
        .text => try formatText(results, platform_tier, writer),
        .json => try formatJson(results, platform_tier, writer),
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "formatText produces header" {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const results: []const Result = &.{
        .{ .name = "os", .status = .pass, .message = "macOS 14.0" },
        .{ .name = "zig", .status = .warn, .message = "scaffold" },
    };
    try formatText(results, "macos_retail", &w);
    const output = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, output, "tickoni doctor"));
}

test "formatText includes counts" {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const results: []const Result = &.{
        .{ .name = "a", .status = .pass, .message = "" },
        .{ .name = "b", .status = .warn, .message = "" },
        .{ .name = "c", .status = .pass, .message = "" },
    };
    try formatText(results, "linux_full", &w);
    const output = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "2 pass") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1 warn") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "0 fail") != null);
}

test "formatJson produces valid JSON structure" {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const results: []const Result = &.{
        .{ .name = "os", .status = .pass, .message = "macOS" },
    };
    try formatJson(results, "macos_retail", &w);
    const output = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, output, "{"));
    try std.testing.expect(std.mem.endsWith(u8, output, "}\n"));
    try std.testing.expect(std.mem.indexOf(u8, output, "\"checks\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"name\": \"os\"") != null);
}

test "runAndFormat text mode produces output" {
    var buf: [2048]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try runAndFormat(std.testing.allocator, .text, &w);
    const output = w.buffered();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, output, "tickoni doctor"));
}

test "runAndFormat json mode produces output" {
    var buf: [2048]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try runAndFormat(std.testing.allocator, .json, &w);
    const output = w.buffered();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, output, "{"));
}
