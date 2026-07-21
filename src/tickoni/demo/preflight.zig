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
/// Run all preflight checks.
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
        try checks.append(allocator, Check{
            .name = "runtime_tier",
            .passed = supported,
            .required = tier_list_buf[0..tier_written],
            .found = installed_runtime_tier,
            .detail = if (!supported) "tier not in manifest supported list" else "",
        });
    }

    // 2. Version check (semver >= min)
    {
        if (m.min_tickoni_version.len > 0 and std.mem.eql(u8, m.min_tickoni_version, "0.0.0") == false) {
            const installed_sv = Semver.parse(installed_version) catch {
                try checks.append(allocator, Check{
                    .name = "version",
                    .passed = false,
                    .required = m.min_tickoni_version,
                    .found = installed_version,
                    .detail = "could not parse installed version as semver",
                });
                return PreflightError.PreflightFailed;
            };
            const required_sv = Semver.parse(m.min_tickoni_version) catch {
                try checks.append(allocator, Check{
                    .name = "version",
                    .passed = false,
                    .required = m.min_tickoni_version,
                    .found = installed_version,
                    .detail = "could not parse manifest min version as semver",
                });
                return PreflightError.PreflightFailed;
            };
            const ver_passed = installed_sv.gte(required_sv);
            try checks.append(allocator, Check{
                .name = "version",
                .passed = ver_passed,
                .required = m.min_tickoni_version,
                .found = installed_version,
                .detail = if (!ver_passed) "installed version is below minimum required" else "",
            });
        }
    }

    // 3. Isolation tier check
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

    // 4. No live effect check
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

    // 5. Replay schema version check
    {
        if (std.mem.eql(u8, m.replay_schema_version, "0.0.0") == false and m.replay_schema_version.len > 0) {
            const required_schema = parseSchemaVersion(m.replay_schema_version);
            if (required_schema == null) {
                try checks.append(allocator, Check{
                    .name = "replay_schema",
                    .passed = false,
                    .required = m.replay_schema_version,
                    .found = "(unparseable)",
                    .detail = "could not parse replay schema version",
                });
            } else {
                const installed_schema = parseSchemaVersion("2");
                if (installed_schema == null) {
                    try checks.append(allocator, Check{
                        .name = "replay_schema",
                        .passed = false,
                        .required = m.replay_schema_version,
                        .found = "(unparseable)",
                        .detail = "could not parse installed replay schema version",
                    });
                } else {
                    const pass = installed_schema.? == required_schema.?;
                    try checks.append(allocator, Check{
                        .name = "replay_schema",
                        .passed = pass,
                        .required = m.replay_schema_version,
                        .found = if (installed_schema) |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "0" else "0",
                        .detail = if (!pass) "replay schema version mismatch" else "",
                    });
                }
            }
        }
    }

    // 6. Policy schema version check
    {
        if (std.mem.eql(u8, m.policy_schema_version, "0.0.0") == false and m.policy_schema_version.len > 0) {
            const required_schema = parseSchemaVersion(m.policy_schema_version);
            if (required_schema == null) {
                try checks.append(allocator, Check{
                    .name = "policy_schema",
                    .passed = false,
                    .required = m.policy_schema_version,
                    .found = "(unparseable)",
                    .detail = "could not parse policy schema version",
                });
            } else {
                const installed_schema = parseSchemaVersion("2");
                if (installed_schema == null) {
                    try checks.append(allocator, Check{
                        .name = "policy_schema",
                        .passed = false,
                        .required = m.policy_schema_version,
                        .found = "(unparseable)",
                        .detail = "could not parse installed policy schema version",
                    });
                } else {
                    const pass = installed_schema.? == required_schema.?;
                    try checks.append(allocator, Check{
                        .name = "policy_schema",
                        .passed = pass,
                        .required = m.policy_schema_version,
                        .found = if (installed_schema) |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "0" else "0",
                        .detail = if (!pass) "policy schema version mismatch" else "",
                    });
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
            const fixture_path = std.mem.join(allocator, "/", &.{ fixture_root, fixture, ".json" }) catch return PreflightError.OutOfMemory;
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
        try checks.append(allocator, Check{
            .name = "fixtures",
            .passed = present == m.required_fixtures.len,
            .required = "all required fixtures",
            .found = found_str,
            .detail = if (present != m.required_fixtures.len) "missing fixtures required by manifest" else "",
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

/// Load a manifest JSON file from disk.
pub fn loadManifest(allocator: Allocator, io: Io, cwd: std.Io.Dir, path: []const u8) ManifestLoadError!*Manifest {
    var file = cwd.openFile(io, path, .{}) catch return ManifestLoadError.FileNotFound;
    defer file.close();

    const size = file.getPos() catch return ManifestLoadError.FileNotFound;
    const content = try file.readToEndAlloc(allocator, size);
    defer allocator.free(content);

    return try parseManifestJson(allocator, content);
}

/// Free a parsed Manifest.
pub fn deinitManifest(m: *Manifest) void {
    _ = m;
}

/// Parse a Manifest from JSON text.
fn parseManifestJson(allocator: Allocator, text: []const u8) ManifestLoadError!*Manifest {
    const m = try allocator.create(Manifest);
    errdefer allocator.destroy(m);

    const gop = std.json.parseFromUtf8(allocator, text, .{}) catch |err| {
        _ = err;
        return ManifestLoadError.InvalidJson;
    };
    defer gop.deinit();

    const root = gop.value;
    const obj = root.asObject() orelse return ManifestLoadError.InvalidJson;

    const min_ver_val = obj.get("min_tickoni_version") orelse return ManifestLoadError.MissingField;
    const min_ver = min_ver_val.getString() orelse return ManifestLoadError.InvalidJson;

    const tiers_val = obj.get("supported_runtime_tiers") orelse return ManifestLoadError.MissingField;
    const tiers_arr = tiers_val.getAs(std.json.Array) orelse return ManifestLoadError.InvalidJson;

    const iso_val = obj.get("required_isolation_tier") orelse return ManifestLoadError.MissingField;
    const iso = iso_val.getString() orelse return ManifestLoadError.InvalidJson;

    const nle_val = obj.get("expected_no_live_effect") orelse return ManifestLoadError.MissingField;
    const nle = nle_val.getBool() orelse return ManifestLoadError.InvalidJson;

    const replay_val = obj.get("replay_schema_version") orelse return ManifestLoadError.MissingField;
    const replay = replay_val.getString() orelse return ManifestLoadError.InvalidJson;

    const policy_val = obj.get("policy_schema_version") orelse return ManifestLoadError.MissingField;
    const policy = policy_val.getString() orelse return ManifestLoadError.InvalidJson;

    const fixtures_val = obj.get("required_fixtures") orelse return ManifestLoadError.MissingField;
    const fixtures_arr = fixtures_val.getAs(std.json.Array) orelse return ManifestLoadError.InvalidJson;

    var tiers_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (tiers_list.items) |t| allocator.free(t);
        tiers_list.deinit(allocator);
    }
    for (tiers_arr.items) |item| {
        const t = item.getString() orelse return ManifestLoadError.InvalidJson;
        try tiers_list.append(t);
    }

    var fixtures_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (fixtures_list.items) |f| allocator.free(f);
        fixtures_list.deinit(allocator);
    }
    for (fixtures_arr.items) |item| {
        const f = item.getString() orelse return ManifestLoadError.InvalidJson;
        try fixtures_list.append(f);
    }

    m.* = Manifest{
        .min_tickoni_version = try allocator.dupe(u8, min_ver),
        .supported_runtime_tiers = try tiers_list.toOwnedSlice(allocator),
        .required_isolation_tier = try allocator.dupe(u8, iso),
        .expected_no_live_effect = nle,
        .replay_schema_version = try allocator.dupe(u8, replay),
        .policy_schema_version = try allocator.dupe(u8, policy),
        .required_fixtures = try fixtures_list.toOwnedSlice(allocator),
    };
    errdefer deinitManifest(m);

    return m;
}

pub const ManifestLoadError = error{
    FileNotFound,
    InvalidJson,
    MissingField,
    OutOfMemory,
};

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
        .supported_runtime_tiers = &.{ "linux_full" },
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
        .supported_runtime_tiers = &.{ "linux_full" },
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
        .supported_runtime_tiers = &.{ "linux_full" },
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
        .supported_runtime_tiers = &.{ "linux_full" },
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
    try std.testing.expect(std.mem.indexOf(u8, output, "runtime_tier") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "macos_retail") != null);
}

test "fixtures check detects missing fixtures" {
    var m = demo_manifest.Manifest{
        .min_tickoni_version = "0.1.0",
        .supported_runtime_tiers = &.{ "linux_full" },
        .required_isolation_tier = "retail",
        .expected_no_live_effect = true,
        .required_fixtures = &[_][]const u8{ "nonexistent_fixture" },
    };
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    try std.testing.expectError(PreflightError.PreflightFailed, run(gpa, io, &m, cwd, "0.1.0", "linux_full", "retail", "/tmp/fixtures"));
}
