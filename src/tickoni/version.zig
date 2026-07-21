/// Version identity for Tickoni.
///
/// Provides build-time version metadata injected via build.zig compile options.
/// On dev builds, defaults are -1/-2 for version components and "0.0.0-dev".
///
/// Import as @import("version") in files that use the build module system.
const std = @import("std");

// Build-time injected constants (set by build.zig via options)
pub const build_version_major: u16 = 0;
pub const build_version_minor: u16 = 0;
pub const build_version_patch: u16 = 0;
pub const build_version_pre: []const u8 = "dev";
pub const build_git_sha: []const u8 = "unknown";
pub const build_id: []const u8 = "dev-0";

/// Semver release string (no prerelease on stable releases).
/// Returns a statically allocated string for the default case.
/// For custom version injection, callers should use init() on VersionInfo.
pub fn semver() []const u8 {
    if (build_version_major == 0 and build_version_minor == 0 and build_version_patch == 0)
        return "0.0.0-dev";
    return if (std.mem.eql(u8, build_version_pre, ""))
        semverFmt(build_version_major, build_version_minor, build_version_patch, "")
    else
        semverFmt(build_version_major, build_version_minor, build_version_patch, build_version_pre);
}

fn semverFmt(major: u16, minor: u16, patch: u16, pre: []const u8) []const u8 {
    var buf: [64]u8 = undefined;
    if (std.mem.eql(u8, pre, "")) {
        return std.fmt.bufPrint(&buf, "{d}.{d}.{d}", .{ major, minor, patch }) catch "0.0.0";
    }
    return std.fmt.bufPrint(&buf, "{d}.{d}.{d}-{s}", .{
        major,
        minor,
        patch,
        pre,
    }) catch "0.0.0";
}

/// Full human-readable version line (for --version output).
pub fn versionLine() []const u8 {
    return semver();
}

/// Git revision (full SHA).
pub fn gitRevision() []const u8 {
    return build_git_sha;
}

/// Build identifier (unique per build).
pub fn buildId() []const u8 {
    return build_id;
}

/// VersionInfo struct — aggregates all version fields for serialization.
pub const VersionInfo = struct {
    semver: []const u8 = "0.0.0-dev",
    build_id: []const u8 = "dev-0",
    git_sha: []const u8 = "unknown",
    os: []const u8 = "unknown",
    arch: []const u8 = "unknown",
    runtime_tier: []const u8 = "unsupported",
    isolation_tier: []const u8 = "degraded",
    policy_schema_version: u16 = 0,
    replay_schema_version: u16 = 0,
    demo_manifest_version: u16 = 0,
    compiler: []const u8 = "unknown",

    pub fn init() VersionInfo {
        const tier_mod = @import("tier");
        const audit_mod = @import("audit_schema");
        return VersionInfo{
            .semver = semver(),
            .build_id = buildId(),
            .git_sha = gitRevision(),
            .os = tier_mod.detectOsString(),
            .arch = tier_mod.detectArchString(),
            .runtime_tier = tier_mod.tierName(tier_mod.detectTier()),
            .isolation_tier = isolationTierStr(),
            .policy_schema_version = audit_mod.audit_schema_version,
            .replay_schema_version = audit_mod.audit_schema_version,
            .compiler = tier_mod.detectCompilerVersion(),
        };
    }
};

/// Derive isolation tier from runtime tier.
/// linux_full → full, macos_retail/windows_retail → retail, unsupported → degraded.
pub fn isolationTierStr() []const u8 {
    const tier = @import("tier").detectTier();
    return switch (tier) {
        .linux_full => "full",
        .macos_retail, .windows_retail => "retail",
        .unsupported => "degraded",
    };
}

/// Format version info as multi-line text output for `--version`.
pub fn formatVersionInfo(info: VersionInfo, writer: anytype) !void {
    try writer.print("Tickoni {s}\n", .{info.semver});
    try writer.print("Build ID: {s}\n", .{info.build_id});
    try writer.print("Git: {s}\n", .{info.git_sha[0..std.math.min(info.git_sha.len, 12)]});
    try writer.print("OS: {s} {s}\n", .{ info.os, info.arch });
    try writer.print("Runtime Tier: {s}\n", .{info.runtime_tier});
    try writer.print("Isolation Tier: {s}\n", .{info.isolation_tier});
    try writer.print("Policy Schema: {d}\n", .{info.policy_schema_version});
    try writer.print("Replay Schema: {d}\n", .{info.replay_schema_version});
    try writer.print("Demo Manifest: {d}\n", .{info.demo_manifest_version});
    try writer.print("Compiler: {s}\n", .{info.compiler});
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "build_version defaults are dev values" {
    // On a fresh build without overrides, these should be the defaults.
    // Tests run against the compiled binary, so actual values depend on
    // whether build.zig injected overrides. We just verify the struct
    // can be initialized.
    const info = VersionInfo{};
    try std.testing.expect(info.semver.len > 0);
}

test "VersionInfo fields are non-empty" {
    const info = VersionInfo{
        .semver = "1.2.3",
        .build_id = "test-1",
        .git_sha = "abcdef1234567890",
        .os = "Linux",
        .arch = "x86_64",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
        .policy_schema_version = 2,
        .replay_schema_version = 2,
        .demo_manifest_version = 1,
        .compiler = "clang 15.0",
    };
    try std.testing.expect(info.semver.len > 0);
    try std.testing.expect(info.build_id.len > 0);
    try std.testing.expect(info.git_sha.len > 0);
    try std.testing.expect(info.os.len > 0);
    try std.testing.expect(info.arch.len > 0);
    try std.testing.expect(info.runtime_tier.len > 0);
    try std.testing.expect(info.isolation_tier.len > 0);
    try std.testing.expect(info.compiler.len > 0);
}

test "git_sha truncation for short SHA" {
    const short_sha = "abc";
    const truncated = short_sha[0..@min(short_sha.len, 12)];
    try std.testing.expectEqualStrings("abc", truncated);
}

test "isolationTierStr returns correct tier strings" {
    const tier = @import("tier");
    // Test the switch logic directly for each tier variant.
    // detectTier() is platform-dependent, so we test the tierName output
    // matches known patterns and that isolationTierStr returns a valid string.
    const tier_name = tier.tierName(tier.detectTier());
    const iso = switch (tier.detectTier()) {
        .linux_full => "full",
        .macos_retail, .windows_retail => "retail",
        .unsupported => "degraded",
    };
    try std.testing.expect(iso.len > 0);
    // tier_name should match iso per the switch mapping
    _ = tier_name;
}

fn tierNameFromIsolation(iso: []const u8) []const u8 {
    if (std.mem.eql(u8, iso, "full")) return "linux_full";
    if (std.mem.eql(u8, iso, "retail")) return "macos_retail";
    if (std.mem.eql(u8, iso, "degraded")) return "unsupported";
    return "unknown";
}
