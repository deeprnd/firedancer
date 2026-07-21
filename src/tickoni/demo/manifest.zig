/// Demo manifest schema — defines what a demo requires to run.
///
/// Scaffold only — JSON parser returns hardcoded error on any input.
/// T7 implements real parsing and validation.
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
};

/// Required fixture type for manifest validation.
pub const Fixture = struct {
    name: []const u8,
    path: []const u8,
    required: bool,
};

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
    min_tickoni_version: []const u8 = "0.0.0",
    supported_runtime_tiers: []const []const u8 = &[_][]const u8{},
    required_isolation_tier: []const u8 = "retail",
    required_fixtures: []const []const u8 = &[_][]const u8{},
    replay_schema_version: []const u8 = "0.0.0",
    policy_schema_version: []const u8 = "0.0.0",
    expected_no_live_effect: bool = true,
    demo_manifest_version: []const u8 = "1",

    /// Validate the manifest — returns Error on any structural failure.
    pub fn validate(self: *const Manifest) Error!void {
        // T7: implement semver validation for min_tickoni_version
        _ = self.min_tickoni_version;

        // T7: validate supported_runtime_tiers entries are valid Tier labels
        for (self.supported_runtime_tiers) |tier| {
            _ = tier;
            // TODO: validate tier is one of: linux_full, macos_retail, windows_retail, unsupported
        }

        // T7: validate required_isolation_tier is one of: full, retail, degraded
        var valid_tier = false;
        if (std.mem.eql(u8, self.required_isolation_tier, "full") or
            std.mem.eql(u8, self.required_isolation_tier, "retail") or
            std.mem.eql(u8, self.required_isolation_tier, "degraded"))
        {
            valid_tier = true;
        }
        if (!valid_tier) return Error.InvalidTier;

        // T7: validate semver fields
        _ = self.replay_schema_version;
        _ = self.policy_schema_version;
        _ = self.demo_manifest_version;
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

/// Load and parse a manifest from a JSON file.
pub fn loadManifest(gpa: std.mem.Allocator, path: []const u8) Error!Manifest {
    _ = gpa; // T7: implement file reading and JSON parsing
    _ = path;
    return Error.ParseError; // scaffold: reject all inputs
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "default Manifest is valid" {
    var m = Manifest{};
    try m.validate();
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

test "loadManifest returns ParseError (scaffold)" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(Error.ParseError, loadManifest(gpa, "/tmp/nonexistent.manifest.json"));
}
