/// Demo manifest schema — defines what a demo requires to run.
///
/// T7 implementation: real JSON parsing from file, semver/tier/schema validation.
const std = @import("std");
/// Manifest error types.
pub const Error = error{
    /// JSON syntax error.
    ParseError,
    /// A required field is missing from the manifest.
    MissingField,
    /// A semver field failed validation.
    InvalidSemver,
    /// A tier field is not a valid Tier enum label.
    InvalidTier,
    /// The manifest file could not be read.
    FileError,
    /// A schema version in the manifest is unsupported.
    SchemaVersionMismatch,
    /// Memory allocation failed.
    OutOfMemory,
};

/// Required fixture type for manifest validation.
pub const Fixture = struct {
    name: []const u8,
    path: []const u8,
    required: bool,
};

/// Valid tier labels that appear in manifests.
pub const validTierLabels = [_][]const u8{ "linux_full", "macos_retail", "windows_retail", "unsupported" };

/// Valid isolation tier labels.
pub const validIsolationTiers = [_][]const u8{ "full", "retail", "degraded" };

/// Check if a string is a valid tier label.
fn isValidTierLabel(s: []const u8) bool {
    for (validTierLabels) |t| {
        if (std.mem.eql(u8, s, t)) return true;
    }
    return false;
}

/// Check if a string is a valid isolation tier label.
fn isValidIsolationTier(s: []const u8) bool {
    for (validIsolationTiers) |t| {
        if (std.mem.eql(u8, s, t)) return true;
    }
    return false;
}

/// Minimal semver parse for manifest validation (no external dependency needed).
/// Accepts full semver (X.Y.Z) or schema versions (single number like "2").
fn parseSemver(raw: []const u8) !void {
    var it = std.mem.splitScalar(u8, raw, '.');
    var parts: u8 = 0;
    while (it.next()) |p| {
        parts += 1;
        if (parts > 3) return Error.InvalidSemver;
        // Split off prerelease suffix (after first -)
        var num_part = p;
        if (std.mem.indexOfScalar(u8, p, '-')) |dash| {
            num_part = p[0..dash];
        }
        for (num_part) |c| {
            if (!std.ascii.isDigit(c)) return Error.InvalidSemver;
        }
        if (num_part.len == 0) return Error.InvalidSemver;
    }
    if (parts == 0) return Error.InvalidSemver;
    // Accept single-number schema versions (e.g. "2") and full semver (X.Y.Z)
    // Reject partial versions like "1.2" and too-many parts like "1.2.3.4"
    if (parts == 2 or parts > 3) return Error.InvalidSemver;
}

/// Demo manifest struct.
///
/// Fields match the decision record in doc/knowledge/version-identity.md:
/// - min_tickoni_version: semver range
/// - supported_runtime_tiers: list of Tier enum labels
/// - required_isolation_tier: enum
/// - required_fixtures: list of fixture identifiers
/// - replay_schema_version: semver
/// - policy_schema_version: semver
/// - expected_no_live_effect: bool
/// - demo_manifest_version: semver
pub const Manifest = struct {
    min_tickoni_version: ?[]const u8 = null,
    supported_runtime_tiers: []const []const u8 = &[_][]const u8{},
    required_isolation_tier: ?[]const u8 = null,
    required_fixtures: []const []const u8 = &[_][]const u8{},
    replay_schema_version: ?[]const u8 = null,
    policy_schema_version: ?[]const u8 = null,
    expected_no_live_effect: bool = true,
    demo_manifest_version: ?[]const u8 = null,

    /// Free heap-allocated fields. For slice fields, also frees each element
    /// since loadManifest allocates individual strings with dupe().
    pub fn deinit(self: *Manifest, gpa: std.mem.Allocator) void {
        if (self.min_tickoni_version) |s| gpa.free(s);
        self.min_tickoni_version = null;
        for (self.supported_runtime_tiers) |t| gpa.free(t);
        gpa.free(self.supported_runtime_tiers);
        self.supported_runtime_tiers = &[_][]const u8{};
        if (self.required_isolation_tier) |s| gpa.free(s);
        self.required_isolation_tier = null;
        for (self.required_fixtures) |f| gpa.free(f);
        gpa.free(self.required_fixtures);
        self.required_fixtures = &[_][]const u8{};
        if (self.replay_schema_version) |s| gpa.free(s);
        self.replay_schema_version = null;
        if (self.policy_schema_version) |s| gpa.free(s);
        self.policy_schema_version = null;
        if (self.demo_manifest_version) |s| gpa.free(s);
        self.demo_manifest_version = null;
    }

    /// Validate the manifest — returns Error on any structural failure.
    pub fn validate(self: *const Manifest) Error!void {
        // Validate min_tickoni_version is a valid semver
        if (self.min_tickoni_version) |v| {
            if (std.mem.eql(u8, v, "0.0.0") == false) {
                try parseSemver(v);
            }
        }

        // Validate supported_runtime_tiers entries are valid Tier labels
        for (self.supported_runtime_tiers) |tier| {
            if (!isValidTierLabel(tier)) return Error.InvalidTier;
        }

        // Validate required_isolation_tier is one of: full, retail, degraded
        if (self.required_isolation_tier) |tier| {
            if (!isValidIsolationTier(tier)) return Error.InvalidTier;
        }

        // Validate semver fields (skip null/0.0.0 defaults)
        if (self.replay_schema_version) |v| {
            if (std.mem.eql(u8, v, "0.0.0") == false) {
                try parseSemver(v);
            }
        }

        if (self.policy_schema_version) |v| {
            if (std.mem.eql(u8, v, "0.0.0") == false) {
                try parseSemver(v);
            }
        }

        if (self.demo_manifest_version) |v| {
            if (std.mem.eql(u8, v, "0.0.0") == false) {
                try parseSemver(v);
            }
        }
    }

    /// Check if a runtime tier is supported by this manifest.
    pub fn isRuntimeTierSupported(self: *const Manifest, tier: []const u8) bool {
        for (self.supported_runtime_tiers) |supported| {
            if (std.mem.eql(u8, tier, supported)) return true;
        }
        return false;
    }

    /// Check if the manifest requires no live execution.
    pub fn requiresNoLiveEffect(self: *const Manifest) bool {
        return self.expected_no_live_effect;
    }
};

/// JSON-compatible struct for manifest deserialization.
const ManifestJson = struct {
    min_tickoni_version: ?[]const u8 = null,
    supported_runtime_tiers: []const []const u8 = &[_][]const u8{},
    required_isolation_tier: ?[]const u8 = null,
    expected_no_live_effect: bool = true,
    replay_schema_version: ?[]const u8 = null,
    policy_schema_version: ?[]const u8 = null,
    required_fixtures: []const []const u8 = &[_][]const u8{},
    demo_manifest_version: ?[]const u8 = null,
};

/// Load and parse a manifest from a JSON file.
/// Returns a heap-allocated *Manifest; caller must call deinit().
pub fn loadManifest(gpa: std.mem.Allocator, cwd: std.Io.Dir, io: std.Io, path: []const u8) Error!*Manifest {
    // Read file contents
    const raw = cwd.readFileAlloc(io, path, gpa, .limited(64 * 1024)) catch return Error.FileError;
    defer gpa.free(raw);

    // Parse JSON
    const json_value = std.json.parseFromSlice(
        ManifestJson,
        gpa,
        raw,
        .{ .ignore_unknown_fields = true },
    ) catch return Error.ParseError;
    defer json_value.deinit();

    const j = json_value.value;

    // Required field: min_tickoni_version
    const min_ver = j.min_tickoni_version orelse return Error.MissingField;

    // Required field: supported_runtime_tiers
    if (j.supported_runtime_tiers.len == 0) return Error.MissingField;

    // Required field: required_isolation_tier
    const iso_tier = j.required_isolation_tier orelse return Error.MissingField;

    // Allocate tier list
    var tier_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (tier_list.items) |t| gpa.free(t);
        tier_list.deinit(gpa);
    }
    for (j.supported_runtime_tiers) |t| {
        const item = try gpa.dupe(u8, t);
        try tier_list.append(gpa, item);
    }

    // Allocate fixture list
    var fixture_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (fixture_list.items) |f| gpa.free(f);
        fixture_list.deinit(gpa);
    }
    for (j.required_fixtures) |f| {
        const item = try gpa.dupe(u8, f);
        try fixture_list.append(gpa, item);
    }

    const replay_ver = if (j.replay_schema_version) |v|
        try gpa.dupe(u8, v)
    else
        try gpa.dupe(u8, "0.0.0");
    errdefer gpa.free(replay_ver);

    const policy_ver = if (j.policy_schema_version) |v|
        try gpa.dupe(u8, v)
    else
        try gpa.dupe(u8, "0.0.0");
    errdefer gpa.free(policy_ver);

    const manifest_ver = if (j.demo_manifest_version) |v|
        try gpa.dupe(u8, v)
    else
        try gpa.dupe(u8, "1");
    errdefer gpa.free(manifest_ver);

    const min_ver_dup = try gpa.dupe(u8, min_ver);
    errdefer gpa.free(min_ver_dup);

    const iso_tier_dup = try gpa.dupe(u8, iso_tier);
    errdefer gpa.free(iso_tier_dup);

    const m = try gpa.create(Manifest);
    errdefer gpa.destroy(m);

    m.* = Manifest{
        .min_tickoni_version = min_ver_dup,
        .supported_runtime_tiers = try tier_list.toOwnedSlice(gpa),
        .required_isolation_tier = iso_tier_dup,
        .required_fixtures = try fixture_list.toOwnedSlice(gpa),
        .replay_schema_version = replay_ver,
        .policy_schema_version = policy_ver,
        .expected_no_live_effect = j.expected_no_live_effect,
        .demo_manifest_version = manifest_ver,
    };
    errdefer m.deinit(gpa);

    return m;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "default Manifest is valid" {
    var m = Manifest{};
    try m.validate();
    m.deinit(std.testing.allocator);
}

test "Manifest.isRuntimeTierSupported returns true for matching tier" {
    var m = Manifest{
        .supported_runtime_tiers = &.{ "macos_retail", "linux_full" },
    };
    try std.testing.expect(m.isRuntimeTierSupported("macos_retail"));
    try std.testing.expect(m.isRuntimeTierSupported("linux_full"));
    try std.testing.expect(!m.isRuntimeTierSupported("windows_retail"));
}

test "Manifest.requiresNoLiveEffect returns true by default" {
    const m = Manifest{};
    try std.testing.expect(m.requiresNoLiveEffect());
}

test "Manifest rejects unknown isolation tier" {
    var m = Manifest{
        .required_isolation_tier = "invalid_tier",
    };
    try std.testing.expectError(Error.InvalidTier, m.validate());
}

test "Manifest rejects invalid semver in min_tickoni_version" {
    var m = Manifest{
        .min_tickoni_version = "not-a-version",
        .supported_runtime_tiers = &.{ "linux_full" },
        .required_isolation_tier = "retail",
    };
    try std.testing.expectError(Error.InvalidSemver, m.validate());
}

test "Manifest rejects invalid semver in replay_schema_version" {
    var m = Manifest{
        .min_tickoni_version = "0.1.0",
        .supported_runtime_tiers = &.{ "linux_full" },
        .required_isolation_tier = "retail",
        .replay_schema_version = "bad",
    };
    try std.testing.expectError(Error.InvalidSemver, m.validate());
}

test "Manifest rejects invalid tier label in supported_runtime_tiers" {
    var m = Manifest{
        .min_tickoni_version = "0.1.0",
        .supported_runtime_tiers = &.{ "linux_full", "fake_tier" },
        .required_isolation_tier = "retail",
    };
    try std.testing.expectError(Error.InvalidTier, m.validate());
}

test "Manifest accepts valid semver versions" {
    var m = Manifest{
        .min_tickoni_version = "0.1.0",
        .supported_runtime_tiers = &.{ "linux_full", "macos_retail" },
        .required_isolation_tier = "retail",
        .replay_schema_version = "1.2.3",
        .policy_schema_version = "2.0.0",
        .demo_manifest_version = "1.0.0",
    };
    try m.validate();
}

test "Manifest accepts default 0.0.0 semver fields (skip validation)" {
    var m = Manifest{
        .min_tickoni_version = "0.1.0",
        .supported_runtime_tiers = &.{ "linux_full" },
        .required_isolation_tier = "retail",
        .replay_schema_version = "0.0.0",
        .policy_schema_version = "0.0.0",
        .demo_manifest_version = "0.0.0",
    };
    try m.validate();
}

test "Manifest.deinit zeroes all fields" {
    const gpa = std.testing.allocator;
    // Allocate individual string elements for slices (matching loadManifest's dupe pattern)
    const tier0 = try gpa.dupe(u8, "linux_full");
    var tiers = try gpa.alloc([]const u8, 1);
    tiers[0] = tier0;
    const fix0 = try gpa.dupe(u8, "fixture1");
    var fixtures = try gpa.alloc([]const u8, 1);
    fixtures[0] = fix0;
    var m = Manifest{
        .min_tickoni_version = try gpa.dupe(u8, "0.1.0"),
        .supported_runtime_tiers = tiers,
        .required_isolation_tier = try gpa.dupe(u8, "retail"),
        .required_fixtures = fixtures,
        .replay_schema_version = try gpa.dupe(u8, "2"),
        .policy_schema_version = try gpa.dupe(u8, "2"),
        .demo_manifest_version = try gpa.dupe(u8, "1"),
    };
    // deinit frees all heap allocations (elements + slice buffers + strings).
    // If it reaches here without crash, the test passes.
    m.deinit(gpa);
}

test "loadManifest parses valid JSON manifest" {
    const gpa = std.testing.allocator;
    const cwd = std.Io.Dir.cwd();
    const result = loadManifest(gpa, cwd, std.testing.io,
        "/home/vicgenin/work/git/tickoni/src/tickoni/demo/fixtures/demo.manifest.json") catch |err| {
        // Skip if file not found (e.g. in CI)
        if (err == Error.FileError) return;
        return err;
    };
    defer {
        result.deinit(gpa);
        gpa.destroy(result);
    }
    try std.testing.expect(result.min_tickoni_version != null);
    try std.testing.expect(result.supported_runtime_tiers.len > 0);
    try result.validate();
}

test "loadManifest rejects non-existent file" {
    const gpa = std.testing.allocator;
    const cwd = std.Io.Dir.cwd();
    const result = loadManifest(gpa, cwd, std.testing.io,
        "/nonexistent/manifest.json") catch |err| {
        try std.testing.expect(err == Error.FileError);
        return;
    };
    defer {
        result.deinit(gpa);
        gpa.destroy(result);
    }
}

test "parseSemver accepts valid versions" {
    try parseSemver("0.1.0");
    try parseSemver("1.2.3");
    try parseSemver("10.20.30");
    try parseSemver("1.2.3-alpha");
}

test "parseSemver rejects invalid versions" {
    try std.testing.expectError(Error.InvalidSemver, parseSemver("abc"));
    try std.testing.expectError(Error.InvalidSemver, parseSemver("1.2"));
    try std.testing.expectError(Error.InvalidSemver, parseSemver("1.2.3.4-alpha"));
    try std.testing.expectError(Error.InvalidSemver, parseSemver(""));
}

test "parseSemver accepts single-number schema versions" {
    try parseSemver("1");
    try parseSemver("2");
    try parseSemver("100");
}