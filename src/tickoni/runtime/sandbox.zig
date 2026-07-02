const std = @import("std");

/// Configuration for entering a tile sandbox via c_abi.sandbox.enter.
/// Defaults are the most restrictive safe values.
pub const SandboxConfig = struct {
    desired_uid: u32 = 65534, // nobody
    desired_gid: u32 = 65534, // nogroup
    keep_host_networking: bool = false,
    allow_connect: bool = false,
    allow_renameat: bool = false,
    keep_controlling_terminal: bool = false,
    dumpable: bool = false,
    rlimit_file_cnt: u64 = 64,
    rlimit_address_space: u64 = 1 << 30, // 1 GiB
    rlimit_data: u64 = 1 << 28, // 256 MiB
    rlimit_nproc: u64 = 0,
};

test "SandboxConfig defaults are least-privilege" {
    const cfg = SandboxConfig{};
    try std.testing.expectEqual(@as(u32, 65534), cfg.desired_uid);
    try std.testing.expectEqual(@as(u32, 65534), cfg.desired_gid);
    try std.testing.expect(!cfg.keep_host_networking);
    try std.testing.expect(!cfg.allow_connect);
    try std.testing.expect(!cfg.allow_renameat);
    try std.testing.expect(!cfg.dumpable);
    try std.testing.expectEqual(@as(u64, 0), cfg.rlimit_nproc);
}

test "SandboxConfig rlimit_address_space is at least 256 MiB" {
    const cfg = SandboxConfig{};
    try std.testing.expect(cfg.rlimit_address_space >= 1 << 28);
}
