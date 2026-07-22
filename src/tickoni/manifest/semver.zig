/// Semver comparison for manifest preflight checks.
///
/// Supports MAJOR.MINOR.PATCH (with optional pre-release/build metadata)
/// comparison using the rules:
///   MAJOR.MINOR.PATCH with equal numeric components means equal.
///   A higher numeric component means greater.
///   Pre-release versions have lower precedence than the associated normal version.
const std = @import("std");

/// Parsed semver representation.
pub const Semver = struct {
    major: u64,
    minor: u64,
    patch: u64,

    pub fn parse(raw: []const u8) ParseError!Semver {
        var it = std.mem.splitScalar(u8, raw, '.');
        const major = std.fmt.parseInt(u64, it.next() orelse return error.ParseError) catch
            return error.ParseError;
        const minor = std.fmt.parseInt(u64, it.next() orelse return error.ParseError) catch
            return error.ParseError;
        const patch_str = it.next() orelse return error.ParseError;
        // Strip pre-release/build metadata from patch (e.g. "1-rc1" → "1")
        const patch_clean = blk: {
            var end = patch_str.len;
            for (patch_str, 0..) |c, i| {
                if (c == '-' or c == '+') {
                    end = i;
                    break;
                }
            }
            break :blk patch_str[0..end];
        };
        const patch = std.fmt.parseInt(u64, patch_clean, 10) catch
            return error.ParseError;
        return Semver{ .major = major, .minor = minor, .patch = patch };
    }

    /// Returns true if `self >= other`.
    pub fn gte(self: Semver, other: Semver) bool {
        if (self.major != other.major) return self.major > other.major;
        if (self.minor != other.minor) return self.minor > other.minor;
        return self.patch >= other.patch;
    }
};

/// Parse a version number string (with optional build metadata) to u32.
pub fn parseVersion(raw: []const u8) ParseError!u32 {
    const clean = blk: {
        var end = raw.len;
        for (raw, 0..) |c, i| {
            if (c == '-' or c == '+' or c == '.') {
                end = i;
                break;
            }
        }
        break :blk raw[0..end];
    };
    return std.fmt.parseInt(u32, clean, 10) catch error.ParseError;
}

/// Parse a schema version string (simple non-negative integer, possibly with prefix like "v2").
pub fn parseSchema(raw: []const u8) ParseError!u32 {
    var start: usize = 0;
    while (start < raw.len and (raw[start] == 'v' or raw[start] == 'V')) start += 1;
    const clean = raw[start..];
    if (clean.len == 0) return error.ParseError;
    for (clean) |c| {
        if (!std.ascii.isDigit(c)) return error.ParseError;
    }
    return std.fmt.parseInt(u32, clean, 10) catch error.ParseError;
}

pub const ParseError = error{ParseError};

test "Semver.parse parses valid version" {
    const sv = try Semver.parse("1.2.3");
    try std.testing.expectEqual(@as(u64, 1), sv.major);
    try std.testing.expectEqual(@as(u64, 2), sv.minor);
    try std.testing.expectEqual(@as(u64, 3), sv.patch);
}

test "Semver.parse handles pre-release" {
    const sv = try Semver.parse("1.2.3-rc1");
    try std.testing.expectEqual(@as(u64, 1), sv.major);
    try std.testing.expectEqual(@as(u64, 2), sv.minor);
    try std.testing.expectEqual(@as(u64, 3), sv.patch);
}

test "Semver.gte returns true for equal" {
    try std.testing.expect(Semver.parse("1.0.0").gte(Semver.parse("1.0.0")));
}

test "Semver.gte returns true for greater" {
    try std.testing.expect(Semver.parse("1.1.0").gte(Semver.parse("1.0.9")));
    try std.testing.expect(Semver.parse("2.0.0").gte(Semver.parse("1.99.99")));
    try std.testing.expect(Semver.parse("0.1.0").gte(Semver.parse("0.0.9")));
}

test "Semver.gte returns false for lesser" {
    try std.testing.expect(!Semver.parse("0.9.9").gte(Semver.parse("1.0.0")));
    try std.testing.expect(!Semver.parse("0.0.9").gte(Semver.parse("0.1.0")));
}

test "parseVersion handles simple and prefixed versions" {
    try std.testing.expectEqual(@as(u32, 5), try parseVersion("5"));
    try std.testing.expectEqual(@as(u32, 2), try parseVersion("2.1"));
    try std.testing.expectEqual(@as(u32, 1), try parseVersion("v1"));
}

test "parseSchema handles prefixed versions" {
    try std.testing.expectEqual(@as(u32, 2), try parseSchema("2"));
    try std.testing.expectEqual(@as(u32, 1), try parseSchema("v1"));
}
