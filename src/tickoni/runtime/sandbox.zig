const std = @import("std");

/// Unprivileged nobody uid/gid, used as the default sandbox identity.
pub const nobody_uid: u32 = 65534;
pub const nobody_gid: u32 = 65534;

/// Default cap on open file descriptors for a sandboxed tile.
pub const default_rlimit_file_cnt: u64 = 64;

/// Default virtual address-space cap for a sandboxed tile.
pub const default_rlimit_address_space: u64 = 1 << 30; // 1 GiB

/// Minimum virtual address-space cap tests and callers may rely on.
pub const min_rlimit_address_space: u64 = 1 << 28; // 256 MiB

/// Default resident data-segment cap for a sandboxed tile.
pub const default_rlimit_data: u64 = 1 << 28; // 256 MiB

/// Configuration for entering a tile sandbox via c_abi.sandbox.enter.
/// Defaults are the most restrictive safe values.
pub const SandboxConfig = struct {
    desired_uid: u32 = nobody_uid,
    desired_gid: u32 = nobody_gid,
    keep_host_networking: bool = false,
    allow_connect: bool = false,
    allow_renameat: bool = false,
    keep_controlling_terminal: bool = false,
    dumpable: bool = false,
    rlimit_file_cnt: u64 = default_rlimit_file_cnt,
    rlimit_address_space: u64 = default_rlimit_address_space,
    rlimit_data: u64 = default_rlimit_data,
    rlimit_nproc: u64 = 0,
};

test "SandboxConfig defaults are least-privilege" {
    const cfg = SandboxConfig{};
    try std.testing.expectEqual(nobody_uid, cfg.desired_uid);
    try std.testing.expectEqual(nobody_gid, cfg.desired_gid);
    try std.testing.expect(!cfg.keep_host_networking);
    try std.testing.expect(!cfg.allow_connect);
    try std.testing.expect(!cfg.allow_renameat);
    try std.testing.expect(!cfg.dumpable);
    try std.testing.expectEqual(@as(u64, 0), cfg.rlimit_nproc);
}

test "SandboxConfig rlimit_address_space is at least the documented minimum" {
    const cfg = SandboxConfig{};
    try std.testing.expect(cfg.rlimit_address_space >= min_rlimit_address_space);
}
