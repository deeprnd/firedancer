/// Preflight check logic — compare installed Tickoni against manifest requirements.
///
/// Scaffold only — always returns failure with placeholder diagnostics.
/// T8 implements real comparison logic.
const std = @import("std");
const manifest = @import("manifest.zig");
const Manifest = manifest.Manifest;
const Error = manifest.Error;

/// Single preflight check result.
pub const Check = struct {
    name: []const u8,
    passed: bool,
    required: []const u8,
    found: []const u8,
    detail: []const u8,

    pub fn summary(self: Check) []const u8 {
        return self.name;
    }

    pub fn detailMessage(self: Check) []const u8 {
        if (self.passed) return "ok";
        // Allocate a buffer for the combined message
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Required: {s}\n  Found: {s}", .{
            self.required,
            self.found,
        }) catch "check failed";
        // Append detail if present (buffer should be large enough)
        if (self.detail.len > 0) {
            const detail_with_prefix = std.fmt.bufPrint(&buf, "{s}\n  {s}", .{ msg, self.detail }) catch "check failed";
            return detail_with_prefix;
        }
        return msg;
    }
};

/// Preflight result — contains all checks and an overall status.
pub const PreflightResult = struct {
    checks: []const Check,
    passed: bool,
    manifest_path: []const u8 = "",
};

/// Error set for preflight failures.
pub const PreflightError = error{
    /// Preflight failed — manifest requirements not met.
    PreflightFailed,
    /// Could not load the manifest.
    ManifestLoadFailed,
    /// Could not allocate memory for checks.
    OutOfMemory,
};

/// Run all preflight checks.
///
/// Checks:
/// 1. Runtime tier support
/// 2. Isolation tier match
/// 3. No live effect enabled
/// 4. Version (stub)
/// 5. Replay schema (stub)
/// 6. Policy schema (stub)
/// 7. Fixture availability (stub)
///
/// Any failure → return PreflightFailed with all failure details.
pub fn run(
    allocator: std.mem.Allocator,
    m: *const Manifest,
    installed_runtime_tier: []const u8,
    installed_isolation_tier: []const u8,
) PreflightError!PreflightResult {
    var checks: std.ArrayList(Check) = .empty;
    defer checks.deinit(allocator);

    // 1. Runtime tier check (T8: real logic)
    {
        const supported = m.isRuntimeTierSupported(installed_runtime_tier);
        var tier_list_buf: [256]u8 = undefined;
        const tier_list = if (supported)
            "any supported tier"
        else blk: {
            var w = std.Io.Writer.fixed(&tier_list_buf);
            for (m.supported_runtime_tiers, 0..) |t, i| {
                if (i > 0) w.writeAll(", ") catch unreachable;
                w.print("{s}", .{t}) catch unreachable;
            }
            break :blk w.buffer[0..w.end];
        };
        try checks.append(allocator, Check{
            .name = "runtime_tier",
            .passed = supported,
            .required = tier_list,
            .found = installed_runtime_tier,
            .detail = if (!supported) "tier not in manifest supported list" else "",
        });
    }

    // 2. Isolation tier check (T8: real logic)
    {
        const matches = std.mem.eql(u8, installed_isolation_tier, m.required_isolation_tier);
        try checks.append(allocator, Check{
            .name = "isolation_tier",
            .passed = matches,
            .required = m.required_isolation_tier,
            .found = installed_isolation_tier,
            .detail = if (!matches) "isolation tier does not match manifest requirement" else "",
        });
    }

    // 3. No live effect check (T8: real logic)
    {
        const no_live = m.requiresNoLiveEffect();
        try checks.append(allocator, Check{
            .name = "no_live_effect",
            .passed = no_live,
            .required = "true",
            .found = if (no_live) "true" else "false",
            .detail = if (!no_live) "manifest requires no live execution" else "",
        });
    }

    // 4. Version check (T8: semver comparison)
    try checks.append(allocator, Check{
        .name = "version",
        .passed = false, // scaffold: always fail
        .required = m.min_tickoni_version,
        .found = "0.0.0-dev", // scaffold: unknown version
        .detail = "scaffold — version comparison not implemented",
    });

    // 5. Replay schema check (T8: semver comparison)
    try checks.append(allocator, Check{
        .name = "replay_schema",
        .passed = false, // scaffold: always fail
        .required = m.replay_schema_version,
        .found = "0", // scaffold: unknown schema version
        .detail = "scaffold — replay schema comparison not implemented",
    });

    // 6. Policy schema check (T8: semver comparison)
    try checks.append(allocator, Check{
        .name = "policy_schema",
        .passed = false, // scaffold: always fail
        .required = m.policy_schema_version,
        .found = "0", // scaffold: unknown schema version
        .detail = "scaffold — policy schema comparison not implemented",
    });

    // 7. Fixture check (T8: file existence validation)
    if (m.required_fixtures.len > 0) {
        try checks.append(allocator, Check{
            .name = "fixtures",
            .passed = false, // scaffold: always fail
            .required = "all required fixtures",
            .found = "0/0",
            .detail = "scaffold — fixture validation not implemented",
        });
    }

    const checks_items = try checks.toOwnedSlice(allocator);
    const any_failed = !isAllPassed(checks_items);

    if (any_failed) {
        allocator.free(checks_items);
        return PreflightError.PreflightFailed;
    }

    return PreflightResult{
        .checks = checks_items,
        .passed = true,
    };
}

/// Check if all preflight checks passed.
fn isAllPassed(checks: []const Check) bool {
    for (checks) |c| {
        if (!c.passed) return false;
    }
    return true;
}

/// Format preflight failure as human-readable error message.
pub fn formatFailure(result: PreflightResult, writer: anytype) !void {
    try writer.writeAll("Preflight failure:\n");
    for (result.checks) |c| {
        if (!c.passed) {
            try writer.print("  {s}\n    Required: {s}\n    Found: {s}", .{
                c.summary(), c.required, c.found,
            });
            if (c.detail.len > 0) {
                try writer.print("\n    {s}", .{c.detail});
            }
            try writer.writeAll("\n");
        }
    }
}

/// Free a PreflightResult's checks slice using the allocator that created it.
pub fn deinit(result: PreflightResult, allocator: std.mem.Allocator) void {
    allocator.free(result.checks);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "isAllPassed returns true for all-pass checks" {
    const checks = [_]Check{
        .{ .name = "a", .passed = true, .required = "", .found = "", .detail = "" },
        .{ .name = "b", .passed = true, .required = "", .found = "", .detail = "" },
    };
    try std.testing.expect(isAllPassed(&checks));
}

test "isAllPassed returns false if any check fails" {
    const checks = [_]Check{
        .{ .name = "a", .passed = true, .required = "", .found = "", .detail = "" },
        .{ .name = "b", .passed = false, .required = "x", .found = "y", .detail = "mismatch" },
        .{ .name = "c", .passed = true, .required = "", .found = "", .detail = "" },
    };
    try std.testing.expect(!isAllPassed(&checks));
}

test "run returns PreflightFailed on scaffold (tier mismatch)" {
    var m = Manifest{
        .supported_runtime_tiers = &.{"linux_full"},
        .required_isolation_tier = "full",
    };
    const gpa = std.testing.allocator;
    const result = run(gpa, &m, "macos_retail", "retail");
    try std.testing.expectError(PreflightError.PreflightFailed, result);
}

test "run returns PreflightFailed on scaffold (version check)" {
    var m = Manifest{
        .supported_runtime_tiers = &.{"macos_retail"},
        .required_isolation_tier = "retail",
    };
    const gpa = std.testing.allocator;
    try std.testing.expectError(PreflightError.PreflightFailed, run(gpa, &m, "macos_retail", "retail"));
}

test "formatFailure includes check details" {
    const checks = [_]Check{
        .{
            .name = "runtime_tier",
            .passed = false,
            .required = "[linux_full]",
            .found = "macos_retail",
            .detail = "tier not in manifest supported list",
        },
    };
    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const result = PreflightResult{
        .checks = &checks,
        .passed = false,
        .manifest_path = "",
    };
    try formatFailure(result, &w);
    const output = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Preflight failure") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "runtime_tier") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "macos_retail") != null);
}
