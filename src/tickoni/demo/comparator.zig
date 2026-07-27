const std = @import("std");
const conformance = @import("conformance");

pub const Mismatch = struct {
    field: []const u8,
    expected: []const u8,
    found: []const u8,
};

pub const ComparisonReport = struct {
    matches: bool = true,
    mismatch_count: usize = 0,
    mismatches: [12]Mismatch = undefined,

    fn push(self: *ComparisonReport, field: []const u8, expected: []const u8, found: []const u8) void {
        self.matches = false;
        if (self.mismatch_count < self.mismatches.len) {
            self.mismatches[self.mismatch_count] = .{ .field = field, .expected = expected, .found = found };
        }
        self.mismatch_count += 1;
    }
};

fn pushBoolMismatch(report: *ComparisonReport, field: []const u8, expected: bool, found: bool) void {
    report.push(field, if (expected) "true" else "false", if (found) "true" else "false");
}

fn pushU64Mismatch(report: *ComparisonReport, field: []const u8, expected: u64, found: u64) void {
    var expected_buf: [32]u8 = undefined;
    var found_buf: [32]u8 = undefined;
    const expected_text = std.fmt.bufPrint(&expected_buf, "{d}", .{expected}) catch unreachable;
    const found_text = std.fmt.bufPrint(&found_buf, "{d}", .{found}) catch unreachable;
    report.push(field, expected_text, found_text);
}

pub fn compare(lhs: conformance.Artifact, rhs: conformance.Artifact) ComparisonReport {
    var report = ComparisonReport{};
    if (!std.mem.eql(u8, lhs.manifest_id, rhs.manifest_id)) report.push("manifest_id", lhs.manifest_id, rhs.manifest_id);
    if (!std.mem.eql(u8, lhs.manifest_version, rhs.manifest_version)) report.push("manifest_version", lhs.manifest_version, rhs.manifest_version);
    if (!std.mem.eql(u8, lhs.tickoni_version, rhs.tickoni_version)) report.push("tickoni_version", lhs.tickoni_version, rhs.tickoni_version);
    if (!std.mem.eql(u8, lhs.fixture_set_id, rhs.fixture_set_id)) report.push("fixture_set_id", lhs.fixture_set_id, rhs.fixture_set_id);
    if (!std.mem.eql(u8, lhs.scenario, rhs.scenario)) report.push("scenario", lhs.scenario, rhs.scenario);
    if (!std.mem.eql(u8, lhs.normalized_event_hash[0..], rhs.normalized_event_hash[0..])) report.push("normalized_event_hash", lhs.normalized_event_hash[0..], rhs.normalized_event_hash[0..]);
    if (!std.mem.eql(u8, lhs.policy_outcome, rhs.policy_outcome)) report.push("policy_outcome", lhs.policy_outcome, rhs.policy_outcome);
    if (!std.mem.eql(u8, lhs.proposal_hash[0..], rhs.proposal_hash[0..])) report.push("proposal_hash", lhs.proposal_hash[0..], rhs.proposal_hash[0..]);
    if (!std.mem.eql(u8, lhs.audit_jsonl_sha256[0..], rhs.audit_jsonl_sha256[0..])) report.push("audit_jsonl_sha256", lhs.audit_jsonl_sha256[0..], rhs.audit_jsonl_sha256[0..]);
    if (!std.mem.eql(u8, lhs.replay_capsule_sha256[0..], rhs.replay_capsule_sha256[0..])) report.push("replay_capsule_sha256", lhs.replay_capsule_sha256[0..], rhs.replay_capsule_sha256[0..]);
    if (lhs.replay_result.replay_match != rhs.replay_result.replay_match) pushBoolMismatch(&report, "replay_match", lhs.replay_result.replay_match, rhs.replay_result.replay_match);
    if (lhs.replay_result.divergence_count != rhs.replay_result.divergence_count) pushU64Mismatch(&report, "divergence_count", lhs.replay_result.divergence_count, rhs.replay_result.divergence_count);
    if (lhs.external_effects_disabled != rhs.external_effects_disabled) pushBoolMismatch(&report, "external_effects_disabled", lhs.external_effects_disabled, rhs.external_effects_disabled);
    return report;
}

fn makeArtifact(runtime_tier: []const u8, proposal_seed: []const u8) conformance.Artifact {
    return .{
        .manifest_id = "demo.investment.v1",
        .manifest_version = "1.0.0",
        .tickoni_version = "0.1.1",
        .runtime_tier = runtime_tier,
        .isolation_tier = if (std.mem.eql(u8, runtime_tier, "linux_full")) "full" else "retail",
        .fixture_set_id = "investment_sample",
        .scenario = "allowed",
        .normalized_event_hash = conformance.sha256Hex("normalized"),
        .policy_outcome = "allow",
        .proposal_hash = conformance.sha256Hex(proposal_seed),
        .audit_jsonl_path = "audit.jsonl",
        .audit_jsonl_sha256 = conformance.sha256Hex("audit"),
        .replay_capsule_path = "replay.json",
        .replay_capsule_sha256 = conformance.sha256Hex("replay"),
        .replay_result = .{ .replay_match = true, .divergence_count = 0 },
        .external_effects_disabled = true,
    };
}

test "comparator ignores runtime and isolation tier differences" {
    const lhs = makeArtifact("linux_full", "proposal");
    const rhs = makeArtifact("macos_retail", "proposal");
    const report = compare(lhs, rhs);
    try std.testing.expect(report.matches);
    try std.testing.expectEqual(@as(usize, 0), report.mismatch_count);
}

test "comparator reports deterministic field mismatch" {
    const lhs = makeArtifact("linux_full", "proposal-a");
    const rhs = makeArtifact("macos_retail", "proposal-b");
    const report = compare(lhs, rhs);
    try std.testing.expect(!report.matches);
    try std.testing.expect(report.mismatch_count >= 1);
    try std.testing.expectEqualStrings("proposal_hash", report.mismatches[0].field);
}
