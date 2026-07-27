/// Doctor output formatting — text and JSON modes.
const std = @import("std");
const checks = @import("doctor_checks");
const Result = checks.Result;
const Status = checks.Status;
const runAll = checks.runAll;

/// Format doctor results as text output.
pub fn formatText(results: []const Result, platform_tier: []const u8, w: anytype) !void {
    try w.print("tickoni doctor — host report\n", .{});
    try w.print("Platform tier: {s}\n", .{platform_tier});

    // Print OS version and architecture from builtin
    const builtin = @import("builtin");
    const os_tag = builtin.target.os.tag;
    const arch = builtin.target.cpu.arch;
    const os_name = switch (os_tag) {
        .macos => "macOS",
        .windows => "Windows",
        .linux => "Linux",
        else => "Unknown",
    };
    const arch_name = switch (arch) {
        .x86_64 => "x86_64",
        .aarch64 => "ARM64",
        .arm => "ARM",
        else => @tagName(arch),
    };
    try w.print("OS: {s} | arch: {s}\n", .{ os_name, arch_name });

    // Print degraded dimensions for non-Linux-full tiers
    const is_linux_full = std.mem.eql(u8, platform_tier, "linux_full");
    if (!is_linux_full) {
        const parts: [3][2][]const u8 = .{
            .{ "sandboxing", "disabled" },
            .{ "shared memory", "disabled" },
            .{ "networking", "socket path" },
        };
        try w.print("Degradations: ", .{});
        for (parts, 0..) |p, i| {
            if (i > 0) try w.writeAll(", ");
            try w.print("{s} ({s})", .{ p[0], p[1] });
        }
        try w.print("\n", .{});

        // Print tiles excluded count (known value for retail tiers)
        const tiles_excluded: usize = blk: {
            if (std.mem.eql(u8, platform_tier, "unsupported")) {
                break :blk 100; // all tiles excluded
            } else {
                // macOS/Windows retail excludes: replay_proof, sandbox_adapter,
                // full_linux_tile_runtime, and shared-memory-dependent tiles
                break :blk 5;
            }
        };
        try w.print("Tiles excluded: {d}\n", .{tiles_excluded});
    }

    try w.print("---\n", .{});

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
    try w.print("---\n", .{});
    try w.print("Checks: {d} pass, {d} warn, {d} fail\n", .{
        pass_count, warn_count, fail_count,
    });
    if (fail_count > 0) {
        try w.print("RESULT: FAIL\n", .{});
    } else if (warn_count > 0) {
        try w.print("RESULT: WARN\n", .{});
    } else {
        try w.print("RESULT: PASS\n", .{});
    }
}

/// Format doctor results as JSON output.
pub fn formatJson(results: []const Result, platform_tier: []const u8, w: anytype) !void {
    var pass_count: usize = 0;
    var warn_count: usize = 0;
    var fail_count: usize = 0;
    for (results) |r| {
        switch (r.status) {
            .pass => pass_count += 1,
            .warn => warn_count += 1,
            .fail => fail_count += 1,
        }
    }

    try w.writeAll("{\n");
    try w.print("  \"platform_tier\": \"{s}\",\n", .{platform_tier});
    try w.print("  \"result\": \"{s}\",\n", .{
        if (fail_count > 0) "FAIL" else if (warn_count > 0) "WARN" else "PASS",
    });
    try w.print("  \"counts\": {{\"pass\": {d}, \"warn\": {d}, \"fail\": {d}}},\n", .{
        pass_count, warn_count, fail_count,
    });
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
            r.message(),
        });
        if (i < results.len - 1) try w.writeAll(",");
        try w.writeAll("\n");
    }
    try w.writeAll("  ]\n");
    try w.writeAll("}\n");
}

/// Get the platform tier string for reports.
pub fn getPlatformTier() []const u8 {
    const builtin = @import("builtin");
    const os_tag = builtin.target.os.tag;
    const arch = builtin.target.cpu.arch;
    if (os_tag == .macos) return "macos_retail";
    if (os_tag == .windows) return "windows_retail";
    if (os_tag == .linux and arch == .x86_64) return "linux_full";
    if (os_tag == .linux and arch == .aarch64) return "linux_retail";
    return "unsupported";
}

/// Format modes for doctor output.
pub const Format = enum { text, json };

/// Run doctor checks and output in the specified format.
pub fn runAndFormat(io: std.Io, gpa: std.mem.Allocator, fmt: Format, writer: anytype) !void {
    var results: [20]Result = undefined;
    const count = runAll(&results, io, gpa);
    const checked_results = results[0..count];
    const platform_tier = getPlatformTier();

    switch (fmt) {
        .text => try formatText(checked_results, platform_tier, writer),
        .json => try formatJson(checked_results, platform_tier, writer),
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "formatText produces header" {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const results: []const Result = &.{
        Result.initOwnedMessage("os", .pass, "macOS 14.0"),
        Result.initOwnedMessage("zig", .warn, "scaffold"),
    };
    try formatText(results, "macos_retail", &w);
    const output = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, output, "tickoni doctor"));
}

test "formatText includes counts" {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const results: []const Result = &.{
        Result.initOwnedMessage("a", .pass, ""),
        Result.initOwnedMessage("b", .warn, ""),
        Result.initOwnedMessage("c", .pass, ""),
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
        Result.initOwnedMessage("os", .pass, "macOS"),
    };
    try formatJson(results, "macos_retail", &w);
    const output = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, output, "{"));
    try std.testing.expect(std.mem.endsWith(u8, output, "}\n"));
    try std.testing.expect(std.mem.indexOf(u8, output, "\"checks\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"name\": \"os\"") != null);
}

test "formatText with failures shows FAIL result" {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const results: []const Result = &.{
        Result.initOwnedMessage("os", .pass, "Linux"),
        Result.initOwnedMessage("zig", .fail, "not found"),
        Result.initOwnedMessage("git", .pass, "git 2.45"),
    };
    try formatText(results, "linux_full", &w);
    const output = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "RESULT: FAIL") != null);
}

test "runAndFormat text mode produces output" {
    var buf: [4096]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try runAndFormat(std.testing.io, std.testing.allocator, .text, &w);
    const output = w.buffered();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, output, "tickoni doctor"));
}

test "runAndFormat json mode produces output" {
    var buf: [4096]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try runAndFormat(std.testing.io, std.testing.allocator, .json, &w);
    const output = w.buffered();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, output, "{"));
}

test "formatJson contains result field" {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const results: []const Result = &.{
        Result.initOwnedMessage("os", .pass, "macOS"),
    };
    try formatJson(results, "macos_retail", &w);
    const output = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"result\":") != null);
}
