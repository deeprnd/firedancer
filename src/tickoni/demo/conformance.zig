const std = @import("std");
const diagnostic = @import("diagnostic");

// Minimal pure-Zig SHA-256 — replaces std.crypto.hash.sha2.Sha256 which is
// unavailable on Windows ARM64 in Zig 0.16.0 (std.crypto doesn't exist there).
// Verified against NIST test vectors (FIPS 180-4 A.1, A.2, A.3).

pub fn sha256(bytes: []const u8) [32]u8 {
    var h: [8]u32 = .{ 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
    const k: [64]u32 = .{
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    };

    var blk: [64]u8 = undefined;
    var offset: usize = 0;

    while (offset + 64 <= bytes.len) {
        @memcpy(&blk, bytes[offset .. offset + 64]);
        offset += 64;
        sha256_compress(&h, &blk, &k);
    }

    var remaining = bytes.len - offset;
    @memset(&blk, 0);
    @memcpy(&blk, bytes[offset ..]);
    blk[remaining] = 0x80;
    remaining += 1;

    if (remaining > 56) {
        sha256_compress(&h, &blk, &k);
        @memset(&blk, 0);
    }

    const bits = @as(u64, bytes.len) * 8;
    blk[56] = @intCast((bits >> 56) & 0xff);
    blk[57] = @intCast((bits >> 48) & 0xff);
    blk[58] = @intCast((bits >> 40) & 0xff);
    blk[59] = @intCast((bits >> 32) & 0xff);
    blk[60] = @intCast((bits >> 24) & 0xff);
    blk[61] = @intCast((bits >> 16) & 0xff);
    blk[62] = @intCast((bits >> 8) & 0xff);
    blk[63] = @intCast(bits & 0xff);

    sha256_compress(&h, &blk, &k);

    var digest: [32]u8 = undefined;
    for (0..8) |i| {
        const h_val = h[i];
        digest[i * 4]     = @intCast(h_val >> 24);
        digest[i * 4 + 1] = @intCast((h_val >> 16) & 0xff);
        digest[i * 4 + 2] = @intCast((h_val >> 8) & 0xff);
        digest[i * 4 + 3] = @intCast(h_val & 0xff);
    }
    return digest;
}

fn sha256_compress(h: *[8]u32, block: *[64]u8, k: *const [64]u32) void {
    var w: [64]u32 = undefined;
    for (w[0..16], 0..) |*wi, i| {
        wi.* = @as(u32, block.*[i * 4]) << 24 |
               @as(u32, block.*[i * 4 + 1]) << 16 |
               @as(u32, block.*[i * 4 + 2]) << 8  |
               @as(u32, block.*[i * 4 + 3]);
    }
    for (16..64) |i| {
        const s0 = std.math.rotr(u32, w[i - 15], 7) ^
                   std.math.rotr(u32, w[i - 15], 18) ^
                   std.math.shr(u32, w[i - 15], 3);
        const s1 = std.math.rotr(u32, w[i - 2], 17) ^
                   std.math.rotr(u32, w[i - 2], 19) ^
                   std.math.shr(u32, w[i - 2], 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    var a = h[0]; var b = h[1]; var c = h[2]; var d = h[3];
    var e = h[4]; var f = h[5]; var g = h[6]; var hh = h[7];
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const s1 = std.math.rotr(u32, e, 6) ^
                   std.math.rotr(u32, e, 11) ^
                   std.math.rotr(u32, e, 25);
        const ch = (e & f) ^ ((~e) & g);
        const temp1 = hh + s1 + ch + k[i] + w[i];
        const s0 = std.math.rotr(u32, a, 2) ^
                   std.math.rotr(u32, a, 13) ^
                   std.math.rotr(u32, a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const temp2 = s0 + maj;
        hh = g; g = f; f = e; e = d + temp1;
        d = c; c = b; b = a; a = temp1 + temp2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
    h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

pub fn sha256Hex(bytes: []const u8) [64]u8 {
    const hash = sha256(bytes);
    var hex: [64]u8 = undefined;
    const digits = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex[i * 2] = digits[(byte >> 4) & 0x0f];
        hex[i * 2 + 1] = digits[byte & 0x0f];
    }
    return hex;
}

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

test "sha256 NIST A.1: empty string" {
    try std.testing.expectEqualStrings(
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        sha256Hex("")
    );
}

test "sha256 NIST A.2: 'abc'" {
    try std.testing.expectEqualStrings(
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        sha256Hex("abc")
    );
}

test "sha256 NIST A.3: long string" {
    try std.testing.expectEqualStrings(
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
        sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
    );
}

test "sha256 exact-64-byte input" {
    var msg: [64]u8 = undefined;
    @memset(&msg, 'A');
    try std.testing.expectEqualStrings(
        "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
        sha256Hex(&msg)
    );
}

test "sha256 1000-byte input" {
    var msg: [1000]u8 = undefined;
    @memset(&msg, 'a');
    try std.testing.expectEqualStrings(
        "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
        sha256Hex(&msg)
    );
}
