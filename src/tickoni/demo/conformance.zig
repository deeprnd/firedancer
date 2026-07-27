const std = @import("std");
const diagnostic = @import("diagnostic.zig");

pub const ReplayResult = struct {
    replay_match: bool,
    divergence_count: u64,
    first_divergent_seq: ?u64 = null,
};

pub const Artifact = struct {
    manifest_id: []const u8,
    manifest_version: []const u8,
    tickoni_version: []const u8,
    runtime_tier: []const u8,
    isolation_tier: []const u8,
    fixture_set_id: []const u8,
    scenario: []const u8,
    normalized_event_hash: [64]u8,
    policy_outcome: []const u8,
    proposal_hash: [64]u8,
    audit_jsonl_path: []const u8,
    audit_jsonl_sha256: [64]u8,
    replay_capsule_path: []const u8,
    replay_capsule_sha256: [64]u8,
    replay_result: ReplayResult,
    blocked_diagnostic: ?diagnostic.BlockedFlowDiagnostic = null,
    external_effects_disabled: bool,
};

pub fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var hex: [64]u8 = undefined;
    const digits = "0123456789abcdef";
    for (digest, 0..) |byte, i| {
        hex[i * 2] = digits[(byte >> 4) & 0x0f];
        hex[i * 2 + 1] = digits[byte & 0x0f];
    }
    return hex;
}

pub fn allocJson(allocator: std.mem.Allocator, artifact: Artifact) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .manifest_id = artifact.manifest_id,
        .manifest_version = artifact.manifest_version,
        .tickoni_version = artifact.tickoni_version,
        .runtime_tier = artifact.runtime_tier,
        .isolation_tier = artifact.isolation_tier,
        .fixture_set_id = artifact.fixture_set_id,
        .scenario = artifact.scenario,
        .normalized_event_hash = artifact.normalized_event_hash[0..],
        .policy_outcome = artifact.policy_outcome,
        .proposal_hash = artifact.proposal_hash[0..],
        .audit_jsonl_path = artifact.audit_jsonl_path,
        .audit_jsonl_sha256 = artifact.audit_jsonl_sha256[0..],
        .replay_capsule_path = artifact.replay_capsule_path,
        .replay_capsule_sha256 = artifact.replay_capsule_sha256[0..],
        .replay_result = .{
            .replay_match = artifact.replay_result.replay_match,
            .divergence_count = artifact.replay_result.divergence_count,
            .first_divergent_seq = artifact.replay_result.first_divergent_seq,
        },
        .blocked_diagnostic = if (artifact.blocked_diagnostic) |blocked| .{
            .code = blocked.code.label(),
            .message = blocked.message,
            .field = blocked.field,
            .expected = blocked.expected,
            .found = blocked.found,
        } else null,
        .external_effects_disabled = artifact.external_effects_disabled,
    }, .{});
}

pub fn writePlain(writer: anytype, artifact: Artifact) !void {
    try writer.print(
        "manifest_id: {s}\nmanifest_version: {s}\ntickoni_version: {s}\nruntime_tier: {s}\nisolation_tier: {s}\nfixture_set_id: {s}\nscenario: {s}\nnormalized_event_hash: {s}\npolicy_outcome: {s}\nproposal_hash: {s}\naudit_jsonl_path: {s}\naudit_jsonl_sha256: {s}\nreplay_capsule_path: {s}\nreplay_capsule_sha256: {s}\nreplay_match: {s}\ndivergence_count: {d}\nexternal_effects_disabled: {s}\n",
        .{
            artifact.manifest_id,
            artifact.manifest_version,
            artifact.tickoni_version,
            artifact.runtime_tier,
            artifact.isolation_tier,
            artifact.fixture_set_id,
            artifact.scenario,
            artifact.normalized_event_hash,
            artifact.policy_outcome,
            artifact.proposal_hash,
            artifact.audit_jsonl_path,
            artifact.audit_jsonl_sha256,
            artifact.replay_capsule_path,
            artifact.replay_capsule_sha256,
            if (artifact.replay_result.replay_match) "true" else "false",
            artifact.replay_result.divergence_count,
            if (artifact.external_effects_disabled) "true" else "false",
        },
    );
    if (artifact.blocked_diagnostic) |blocked| {
        try blocked.writePlain(writer);
    }
}

test "sha256Hex is stable" {
    const actual = sha256Hex("tickoni-demo");
    try std.testing.expectEqualStrings("bb0c8815440097944b9002383728aee8a17e1d558d21e172f01b4b50d3b69af7", actual[0..]);
}

test "conformance JSON contains required schema fields" {
    const artifact = Artifact{
        .manifest_id = "demo.investment.v1",
        .manifest_version = "1.0.0",
        .tickoni_version = "0.1.1",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
        .fixture_set_id = "investment_sample",
        .scenario = "allowed",
        .normalized_event_hash = sha256Hex("normalized-events"),
        .policy_outcome = "allow",
        .proposal_hash = sha256Hex("proposal"),
        .audit_jsonl_path = "audit.jsonl",
        .audit_jsonl_sha256 = sha256Hex("audit"),
        .replay_capsule_path = "replay.json",
        .replay_capsule_sha256 = sha256Hex("replay"),
        .replay_result = .{ .replay_match = true, .divergence_count = 0 },
        .external_effects_disabled = true,
    };

    const json = try allocJson(std.testing.allocator, artifact);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "normalized_event_hash") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "proposal_hash") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "external_effects_disabled") != null);
}
