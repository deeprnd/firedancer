/// Preflight checker — compares installed Tickoni against manifest requirements.
///
/// Checks (all real, no stubs):
///   1. Runtime tier support
///   2. Version >= min_tickoni_version
///   3. Isolation tier matches requirement
///   4. expected_no_live_effect is satisfied
///   5. Replay schema version matches
///   6. Policy schema version matches
///   7. All required fixtures present on disk
///
/// Fail-closed: if any check fails, the demo command does not run and produces
/// an explicit error with diagnostic. No proposal/audit artifacts are created.
const std = @import("std");
const demo_manifest = @import("demo_manifest");
const diagnostic = @import("diagnostic");
const Semver = @import("demo_semver").Semver;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Manifest = demo_manifest.Manifest;

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
};

/// Preflight result — contains all checks and an overall status.
pub const PreflightResult = struct {
    checks: []const Check,
    passed: bool,
    manifest_path: []const u8 = "",
};

fn appendOwnedCheck(
    checks: *std.ArrayList(Check),
    allocator: Allocator,
    name: []const u8,
    passed: bool,
    required: []const u8,
    found: []const u8,
    detail: []const u8,
) PreflightError!void {
    const owned_name = allocator.dupe(u8, name) catch return PreflightError.OutOfMemory;
    errdefer allocator.free(owned_name);
    const owned_required = allocator.dupe(u8, required) catch return PreflightError.OutOfMemory;
    errdefer allocator.free(owned_required);
    const owned_found = allocator.dupe(u8, found) catch return PreflightError.OutOfMemory;
    errdefer allocator.free(owned_found);
    const owned_detail = allocator.dupe(u8, detail) catch return PreflightError.OutOfMemory;
    errdefer allocator.free(owned_detail);
    checks.append(allocator, .{
        .name = owned_name,
        .passed = passed,
        .required = owned_required,
        .found = owned_found,
        .detail = owned_detail,
    }) catch return PreflightError.OutOfMemory;
}

/// Error set for preflight failures.
pub const PreflightError = error{
    PreflightFailed,
    ManifestLoadFailed,
    OutOfMemory,
};

fn parseSchemaVersion(raw: []const u8) ?u32 {
    var start: usize = 0;
    while (start < raw.len and (raw[start] == 'v' or raw[start] == 'V')) start += 1;
    const clean = raw[start..];
    if (clean.len == 0) return null;
    for (clean) |c| {
        if (!std.ascii.isDigit(c)) return null;
    }
    return std.fmt.parseInt(u32, clean, 10) catch null;
}

/// Append a string slice into a buffer at the given offset, capped by remaining space.
/// Returns new offset.
/// Run all preflight checks and return the full result regardless of pass/fail.
pub fn evaluate(
    allocator: Allocator,
    io: Io,
    m: *const demo_manifest.Manifest,
    cwd: std.Io.Dir,
    installed_version: []const u8,
    installed_runtime_tier: []const u8,
    installed_isolation_tier: []const u8,
    fixture_root: []const u8,
) PreflightError!PreflightResult {
    var checks: std.ArrayList(Check) = .empty;
    errdefer checks.deinit(allocator);

    // 1. Runtime tier check
    {
        const supported = m.isRuntimeTierSupported(installed_runtime_tier);
        var tier_list_buf: [256]u8 = undefined;
        var tier_written: usize = 0;
        var first = true;
        for (m.supported_runtime_tiers) |t| {
            if (!first) {
                if (tier_written + 2 <= 256) {
                    tier_list_buf[tier_written] = ',';
                    tier_list_buf[tier_written + 1] = ' ';
                    tier_written += 2;
                }
            }
            if (tier_written + t.len <= 256) {
                @memcpy(tier_list_buf[tier_written .. tier_written + t.len], t);
                tier_written += t.len;
            }
            first = false;
        }
        try appendOwnedCheck(&checks, allocator, "runtime_tier", supported, tier_list_buf[0..tier_written], installed_runtime_tier, if (!supported) "tier not in manifest supported list" else "");
    }

    // 2. Version check (semver >= min)
    {
        if (m.min_tickoni_version) |min_ver| {
            if (std.mem.eql(u8, min_ver, "0.0.0") == false) {
                const installed_sv = Semver.parse(installed_version) catch {
                    try appendOwnedCheck(&checks, allocator, "version", false, min_ver, installed_version, "could not parse installed version as semver");
                    return PreflightError.PreflightFailed;
                };
                const required_sv = Semver.parse(min_ver) catch {
                    try appendOwnedCheck(&checks, allocator, "version", false, min_ver, installed_version, "could not parse manifest min version as semver");
                    return PreflightError.PreflightFailed;
                };
                const ver_passed = installed_sv.gte(required_sv);
                try appendOwnedCheck(&checks, allocator, "version", ver_passed, min_ver, installed_version, if (!ver_passed) "installed version is below minimum required" else "");
            }
        }
    }

    // 3. Isolation tier check
    {
        const iso = m.requiredIsolationTierFor(installed_runtime_tier) orelse "retail";
        const matches = std.mem.eql(u8, installed_isolation_tier, iso);
        try appendOwnedCheck(&checks, allocator, "isolation_tier", matches, iso, installed_isolation_tier, if (!matches) "isolation tier does not match manifest requirement" else "");
    }

    // 4. No live effect check
    {
        const no_live = m.requiresNoLiveEffect();
        try appendOwnedCheck(&checks, allocator, "no_live_effect", no_live, "true", if (no_live) "true" else "false", if (!no_live) "manifest requires no live execution" else "");
    }

    // 5. Replay schema version check
    {
        if (m.replay_schema_version) |rv| {
            if (std.mem.eql(u8, rv, "0.0.0") == false) {
                const required_schema = parseSchemaVersion(rv);
                if (required_schema == null) {
                    try appendOwnedCheck(&checks, allocator, "replay_schema", false, rv, "(unparseable)", "could not parse replay schema version");
                } else {
                    const installed_schema = parseSchemaVersion("2");
                    if (installed_schema == null) {
                        try appendOwnedCheck(&checks, allocator, "replay_schema", false, rv, "(unparseable)", "could not parse installed replay schema version");
                    } else {
                        const pass = installed_schema.? == required_schema.?;
                        try appendOwnedCheck(&checks, allocator, "replay_schema", pass, rv, "2", if (!pass) "replay schema version mismatch" else "");
                    }
                }
            }
        }
    }

    // 6. Policy schema version check
    {
        if (m.policy_schema_version) |pv| {
            if (std.mem.eql(u8, pv, "0.0.0") == false) {
                const required_schema = parseSchemaVersion(pv);
                if (required_schema == null) {
                    try appendOwnedCheck(&checks, allocator, "policy_schema", false, pv, "(unparseable)", "could not parse policy schema version");
                } else {
                    const installed_schema = parseSchemaVersion("2");
                    if (installed_schema == null) {
                        try appendOwnedCheck(&checks, allocator, "policy_schema", false, pv, "(unparseable)", "could not parse installed policy schema version");
                    } else {
                        const pass = installed_schema.? == required_schema.?;
                        try appendOwnedCheck(&checks, allocator, "policy_schema", pass, pv, "2", if (!pass) "policy schema version mismatch" else "");
                    }
                }
            }
        }
    }

    // 7. Fixture check
    if (m.required_fixtures.len > 0) {
        var present: usize = 0;
        var missing_buf: [512]u8 = undefined;
        var mw: usize = 0;
        var first = true;
        for (m.required_fixtures) |fixture| {
            const fixture_path = std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ fixture_root, fixture }) catch return PreflightError.OutOfMemory;
            const exists = blk: {
                std.Io.Dir.access(cwd, io, fixture_path, .{}) catch break :blk false;
                break :blk true;
            };
            if (exists) {
                present += 1;
            } else {
                if (!first) {
                    if (mw + 2 <= 512) {
                        missing_buf[mw] = ',';
                        missing_buf[mw + 1] = ' ';
                        mw += 2;
                    }
                }
                if (mw + fixture.len <= 512) {
                    @memcpy(missing_buf[mw .. mw + fixture.len], fixture);
                    mw += fixture.len;
                }
                first = false;
            }
            allocator.free(fixture_path);
        }
        var found_str: []const u8 = "all present";
        if (present != m.required_fixtures.len) {
            const missing_text = missing_buf[0..mw];
            var fb: [512]u8 = undefined;
            found_str = std.fmt.bufPrint(&fb, "{d}/{d} (missing: {s})", .{
                present, m.required_fixtures.len, missing_text,
            }) catch "unknown";
        }
        try appendOwnedCheck(&checks, allocator, "fixtures", present == m.required_fixtures.len, "all required fixtures", found_str, if (present != m.required_fixtures.len) "missing fixtures required by manifest" else "");
    }

    const checks_items = try checks.toOwnedSlice(allocator);
    const any_failed = !isAllPassed(checks_items);

    return PreflightResult{
        .checks = checks_items,
        .passed = !any_failed,
    };
}

fn isAllPassed(checks: []const Check) bool {
    for (checks) |c| {
        if (!c.passed) return false;
    }
    return true;
}

/// Free a PreflightResult's checks slice using the allocator that created it.
pub fn deinit(result: PreflightResult, allocator: std.mem.Allocator) void {
    for (result.checks) |check| {
        allocator.free(check.name);
        allocator.free(check.required);
        allocator.free(check.found);
        allocator.free(check.detail);
    }
    allocator.free(result.checks);
}

/// Run all preflight checks and fail closed when any check fails.
pub fn run(
    allocator: Allocator,
    io: Io,
    m: *const demo_manifest.Manifest,
    cwd: std.Io.Dir,
    installed_version: []const u8,
    installed_runtime_tier: []const u8,
    installed_isolation_tier: []const u8,
    fixture_root: []const u8,
) PreflightError!PreflightResult {
    const result = try evaluate(
        allocator,
        io,
        m,
        cwd,
        installed_version,
        installed_runtime_tier,
        installed_isolation_tier,
        fixture_root,
    );
    if (!result.passed) {
        deinit(result, allocator);
        return PreflightError.PreflightFailed;
    }
    return result;
}

fn firstFailureDiagnostic(result: PreflightResult) ?diagnostic.BlockedFlowDiagnostic {
    const CheckName = enum {
        runtime_tier,
        version,
        isolation_tier,
        no_live_effect,
        replay_schema,
        policy_schema,
        fixtures,
    };

    for (result.checks) |check| {
        if (!check.passed) {
            const check_name = std.meta.stringToEnum(CheckName, check.name);
            return switch (check_name orelse .version) {
                .runtime_tier => .{
                    .code = .unsupported_runtime_tier,
                    .message = "runtime tier is not supported by the manifest",
                    .field = check.name,
                    .expected = check.required,
                    .found = check.found,
                },
                .version, .replay_schema, .policy_schema => .{
                    .code = .stale_manifest,
                    .message = "manifest version requirements do not match this build",
                    .field = check.name,
                    .expected = check.required,
                    .found = check.found,
                },
                .isolation_tier => .{
                    .code = .missing_isolation_prerequisite,
                    .message = "runtime isolation tier does not satisfy the manifest",
                    .field = check.name,
                    .expected = check.required,
                    .found = check.found,
                },
                .no_live_effect => .{
                    .code = .attempted_live_execution,
                    .message = "manifest does not allow live effects for this demo",
                    .field = check.name,
                    .expected = check.required,
                    .found = check.found,
                },
                .fixtures => .{
                    .code = .missing_fixture,
                    .message = "required fixture material is missing",
                    .field = check.name,
                    .expected = check.required,
                    .found = check.found,
                },
            };
        }
    }
    return null;
}

/// Format preflight failure as human-readable error message.
pub fn formatFailure(result: PreflightResult, writer: anytype) !void {
    try writer.writeAll("Preflight failure:\n");
    if (firstFailureDiagnostic(result)) |diag| {
        try diag.writePlain(writer);
    }
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

/// Load a manifest JSON file from disk.
pub const ManifestLoadError = demo_manifest.Error;

pub fn loadManifest(allocator: Allocator, io: Io, cwd: std.Io.Dir, path: []const u8) ManifestLoadError!*Manifest {
    return demo_manifest.loadManifest(allocator, cwd, io, path);
}

/// Free a parsed Manifest.
pub fn deinitManifest(m: *Manifest, gpa: Allocator) void {
    m.deinit(gpa);
    gpa.destroy(m);
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

test "runtime tier check fails on mismatch" {
    var m = demo_manifest.Manifest{
        .supported_runtime_tiers = &.{"linux_full"},
        .required_isolation_tier = "retail",
        .expected_no_live_effect = true,
        .required_fixtures = &[_][]const u8{},
    };
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    try std.testing.expectError(PreflightError.PreflightFailed, run(gpa, io, &m, cwd, "0.1.0", "macos_retail", "retail", "/tmp/fixtures"));
}

test "runtime tier check passes on match" {
    var m = demo_manifest.Manifest{
        .supported_runtime_tiers = &.{ "linux_full", "macos_retail" },
        .required_isolation_tier = "retail",
        .expected_no_live_effect = true,
        .required_fixtures = &[_][]const u8{},
    };
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    const result = run(gpa, io, &m, cwd, "0.1.0", "linux_full", "retail", "/tmp/fixtures") catch unreachable;
    try std.testing.expect(result.passed);
    deinit(result, gpa);
}

test "version check fails when installed < min" {
    var m = demo_manifest.Manifest{
        .min_tickoni_version = "0.2.0",
        .supported_runtime_tiers = &.{"linux_full"},
        .required_isolation_tier = "retail",
        .expected_no_live_effect = true,
        .required_fixtures = &[_][]const u8{},
    };
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    try std.testing.expectError(PreflightError.PreflightFailed, run(gpa, io, &m, cwd, "0.1.0", "linux_full", "retail", "/tmp/fixtures"));
}

test "isolation tier mismatch fails" {
    var m = demo_manifest.Manifest{
        .supported_runtime_tiers = &.{"linux_full"},
        .required_isolation_tier = "full",
        .expected_no_live_effect = true,
        .required_fixtures = &[_][]const u8{},
    };
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    try std.testing.expectError(PreflightError.PreflightFailed, run(gpa, io, &m, cwd, "0.1.0", "linux_full", "retail", "/tmp/fixtures"));
}

test "no_live_effect=false fails" {
    var m = demo_manifest.Manifest{
        .supported_runtime_tiers = &.{"linux_full"},
        .required_isolation_tier = "retail",
        .expected_no_live_effect = false,
        .required_fixtures = &[_][]const u8{},
    };
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    try std.testing.expectError(PreflightError.PreflightFailed, run(gpa, io, &m, cwd, "0.1.0", "linux_full", "retail", "/tmp/fixtures"));
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
    try std.testing.expect(std.mem.indexOf(u8, output, "blocked_code: unsupported_runtime_tier") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "runtime_tier") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "macos_retail") != null);
}

test "fixtures check detects missing fixtures" {
    var m = demo_manifest.Manifest{
        .min_tickoni_version = "0.1.0",
        .supported_runtime_tiers = &.{"linux_full"},
        .required_isolation_tier = "retail",
        .expected_no_live_effect = true,
        .required_fixtures = &[_][]const u8{"nonexistent_fixture"},
    };
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    try std.testing.expectError(PreflightError.PreflightFailed, run(gpa, io, &m, cwd, "0.1.0", "linux_full", "retail", "/tmp/fixtures"));
}

test "per-tier isolation requirement lets linux_full require full" {
    var m = demo_manifest.Manifest{
        .min_tickoni_version = "0.1.0",
        .supported_runtime_tiers = &.{ "linux_full", "macos_retail" },
        .required_isolation_tier = "retail",
        .required_isolation_by_tier = .{
            .linux_full = "full",
            .macos_retail = "retail",
        },
        .expected_no_live_effect = true,
        .required_fixtures = &[_][]const u8{},
    };
    const result = try run(std.testing.allocator, std.testing.io, &m, std.Io.Dir.cwd(), "0.1.0", "linux_full", "full", "/tmp/fixtures");
    defer deinit(result, std.testing.allocator);
    try std.testing.expect(result.passed);
}

test "preflight passes on windows_retail" {
    var m = demo_manifest.Manifest{
        .min_tickoni_version = "0.1.0",
        .supported_runtime_tiers = &.{ "linux_full", "macos_retail", "windows_retail" },
        .required_isolation_tier = "retail",
        .required_isolation_by_tier = .{
            .linux_full = "full",
            .macos_retail = "retail",
            .windows_retail = "retail",
        },
        .expected_no_live_effect = true,
        .required_fixtures = &[_][]const u8{},
    };
    const result = run(std.testing.allocator, std.testing.io, &m, std.Io.Dir.cwd(), "0.1.0", "windows_retail", "retail", "/tmp/fixtures") catch unreachable;
    defer deinit(result, std.testing.allocator);
    try std.testing.expect(result.passed);
}

test "preflight fails on unsupported tier" {
    var m = demo_manifest.Manifest{
        .min_tickoni_version = "0.1.0",
        .supported_runtime_tiers = &.{ "linux_full", "macos_retail" },
        .required_isolation_tier = "retail",
        .expected_no_live_effect = true,
        .required_fixtures = &[_][]const u8{},
    };
    try std.testing.expectError(PreflightError.PreflightFailed, run(std.testing.allocator, std.testing.io, &m, std.Io.Dir.cwd(), "0.1.0", "unsupported", "degraded", "/tmp/fixtures"));
}
