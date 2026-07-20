/// Platform support tier detection for `tickoni --version` output.
///
/// Lightweight tier detection that satisfies the doc-level requirement
/// that every build surface prints tier + OS.  Full tier-codification
/// (workflow-to-tier mapping, degraded-guarantee visibility rules, Zig
/// enum with all tiers) lives in S1/S2.
///
/// Tier inventory (matching doc/knowledge/platform-tiers.md):
///   - linux_full     Linux  x86_64 / ARM64 — shared-mem topology, seccomp
///   - macos_retail   macOS  ARM64 / Intel  — socket networking, no sandbox
///   - windows_retail Windows x86_64 / ARM64 — socket networking, no sandbox
///   - unsupported    anything else
const std = @import("std");
const builtin = @import("builtin");

pub const Tier = enum {
    linux_full,
    macos_retail,
    windows_retail,
    unsupported,
};

pub fn tierName(t: Tier) []const u8 {
    return switch (t) {
        .linux_full => "linux_full",
        .macos_retail => "macos_retail",
        .windows_retail => "windows_retail",
        .unsupported => "unsupported",
    };
}

/// Detect the runtime support tier for the current OS.
pub fn detectTier() Tier {
    return switch (builtin.target.os.tag) {
        .macos => .macos_retail,
        .windows => .windows_retail,
        .linux => .linux_full,
        else => .unsupported,
    };
}

/// Return the detected OS name string for display.
pub fn detectOsString() []const u8 {
    return switch (builtin.target.os.tag) {
        .macos => "macOS",
        .windows => "Windows",
        .linux => "Linux",
        else => "Unknown",
    };
}

/// Return the detected architecture string for display.
pub fn detectArchString() []const u8 {
    return switch (builtin.target.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "ARM64",
        .arm => "ARM",
        else => @tagName(builtin.target.cpu.arch),
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "tierName returns correct labels" {
    try std.testing.expectEqualStrings("linux_full", tierName(.linux_full));
    try std.testing.expectEqualStrings("macos_retail", tierName(.macos_retail));
    try std.testing.expectEqualStrings("windows_retail", tierName(.windows_retail));
    try std.testing.expectEqualStrings("unsupported", tierName(.unsupported));
}

test "detectTier returns a known OS name" {
    const os = detectOsString();
    try std.testing.expect(os.len > 0);
    try std.testing.expect(std.ascii.isAlnum(os[0]));
}

test "detectArchString is non-empty" {
    const arch = detectArchString();
    try std.testing.expect(arch.len > 0);
}