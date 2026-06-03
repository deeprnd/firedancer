/// Narrow Zig bindings over src/util/sandbox/fd_sandbox.h.
///
/// Extern declarations here; C substrate is linked only in the supervisor
/// binary build. Step 1 tests validate SandboxConfig defaults only.
///
/// Link requirements: -lfd_util (built by GNUmakefile).
const std = @import("std");

/// Configuration for entering a tile sandbox via fd_sandbox_enter.
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

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_util at link time
// ---------------------------------------------------------------------------

pub extern fn fd_sandbox_requires_cap_sys_admin(desired_uid: u32, desired_gid: u32) c_int;

/// Enter the sandbox. The seccomp_filter pointer must point to an array of
/// struct sock_filter compiled from a policy by contrib/generate_filters.py.
/// Not called from Zig in Step 1; declared here for type-checking.
pub extern fn fd_sandbox_enter(
    desired_uid: u32,
    desired_gid: u32,
    keep_host_networking: c_int,
    allow_connect: c_int,
    allow_renameat: c_int,
    keep_controlling_terminal: c_int,
    dumpable: c_int,
    rlimit_file_cnt: u64,
    rlimit_address_space: u64,
    rlimit_data: u64,
    rlimit_nproc: u64,
    allowed_file_descriptor_cnt: u64,
    allowed_file_descriptor: [*]const c_int,
    seccomp_filter_cnt: u64,
    seccomp_filter: *anyopaque,
) void;

pub extern fn fd_sandbox_switch_uid_gid(desired_uid: u32, desired_gid: u32) void;
pub extern fn fd_sandbox_getpid() c_int;
pub extern fn fd_sandbox_gettid() c_int;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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
