const std = @import("std");

const policy_version = "tickoni.v1_1";

/// Derives a deterministic synthetic run id from the thesis input hash and
/// policy version. Every audit event for this run carries this id.
pub fn deriveSyntheticRunId(thesis_hash: u64) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&thesis_hash));
    hasher.update(policy_version);
    return hasher.final();
}

test "deriveSyntheticRunId is deterministic" {
    const h1 = deriveSyntheticRunId(0xdeadbeef_cafebabe);
    const h2 = deriveSyntheticRunId(0xdeadbeef_cafebabe);
    try std.testing.expectEqual(h1, h2);
}

test "deriveSyntheticRunId differs for different thesis hashes" {
    try std.testing.expect(deriveSyntheticRunId(1) != deriveSyntheticRunId(2));
}

test "deriveSyntheticRunId differs from the raw thesis hash" {
    const thesis_hash: u64 = 0x1234_5678_9abc_def0;
    try std.testing.expect(deriveSyntheticRunId(thesis_hash) != thesis_hash);
}
