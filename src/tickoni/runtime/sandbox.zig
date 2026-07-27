/// v2.14.S8.T5: this struct is defined and tested, but not yet wired into
/// the process-mode harness call path (c_abi/shim/tile_run.c's
/// tk_topo_run_tile_simple keeps sandbox=0 throughout v2.14). Real entry
/// via c_abi.sandbox.enter needs unshare(CLONE_NEWUSER) to drop to this
/// struct's default nobody uid/gid, which is not guaranteed to be
/// available — confirmed by a concrete EPERM failure under this
/// implementation's own sandboxed environment despite the kernel allowing
/// unprivileged user namespaces (host LSM/AppArmor policy can still deny
/// it). Requiring that privilege in the harness path would make Linux
/// full-runtime process mode depend on something consumer-tier hosts
/// (V1.21) and hardened hosts may not have — process isolation here comes
/// from supervisor-managed OS processes and crash-only teardown, not
/// namespace confinement, so v2.14 does not need this to hold. Wiring
/// real sandbox entry (including a documented fail-closed-with-diagnostic
/// path when namespaces are unavailable, never escalating privileges) is
/// scoped to a future V1.21 support-tier story. See
/// doc/strategy/roadmap/stories/v2.14.md's v2.14.S8.T5 entry.
const builtin = @import("builtin");
const std = @import("std");
const util = @import("util");
const sandbox_defaults = util.sandbox_defaults;

/// Process-mode sandbox policy tier. v2.14 keeps the retail/consumer path on
/// explicit `none` across every platform: no sudo, no capabilities, and no
/// namespace dependency. A future Linux-only support tier can add a real
/// namespace sandbox mode without changing macOS semantics.
pub const SandboxMode = enum {
    none,
    linux_namespaces,
};

pub fn defaultProcessModeForOs(os_tag: std.Target.Os.Tag) SandboxMode {
    _ = os_tag;
    return .none;
}

pub fn defaultProcessMode() SandboxMode {
    return defaultProcessModeForOs(builtin.os.tag);
}

pub fn processModeUsesSandbox(mode: SandboxMode) bool {
    return mode != .none;
}

/// Configuration for entering a tile sandbox via c_abi.sandbox.enter.
/// Defaults are the most restrictive safe values.
pub const SandboxConfig = struct {
    desired_uid: u32 = sandbox_defaults.nobody_uid,
    desired_gid: u32 = sandbox_defaults.nobody_gid,
    keep_host_networking: bool = false,
    allow_connect: bool = false,
    allow_renameat: bool = false,
    keep_controlling_terminal: bool = false,
    dumpable: bool = false,
    rlimit_file_cnt: u64 = sandbox_defaults.rlimit_file_cnt,
    rlimit_address_space: u64 = sandbox_defaults.rlimit_address_space,
    rlimit_data: u64 = sandbox_defaults.rlimit_data,
    rlimit_nproc: u64 = 0,
};

test "default process mode is explicit none on this build" {
    try std.testing.expectEqual(SandboxMode.none, defaultProcessMode());
    try std.testing.expect(!processModeUsesSandbox(defaultProcessMode()));
}

test "macOS process mode remains none" {
    try std.testing.expectEqual(SandboxMode.none, defaultProcessModeForOs(.macos));
    try std.testing.expect(!processModeUsesSandbox(defaultProcessModeForOs(.macos)));
}

test "linux process mode stays none until a future support-tier story wires namespaces" {
    try std.testing.expectEqual(SandboxMode.none, defaultProcessModeForOs(.linux));
    try std.testing.expect(!processModeUsesSandbox(defaultProcessModeForOs(.linux)));
}

test "SandboxConfig defaults are least-privilege" {
    const cfg = SandboxConfig{};
    try std.testing.expectEqual(sandbox_defaults.nobody_uid, cfg.desired_uid);
    try std.testing.expectEqual(sandbox_defaults.nobody_gid, cfg.desired_gid);
    try std.testing.expect(!cfg.keep_host_networking);
    try std.testing.expect(!cfg.allow_connect);
    try std.testing.expect(!cfg.allow_renameat);
    try std.testing.expect(!cfg.dumpable);
    try std.testing.expectEqual(sandbox_defaults.rlimit_file_cnt, cfg.rlimit_file_cnt);
    try std.testing.expectEqual(sandbox_defaults.rlimit_data, cfg.rlimit_data);
    try std.testing.expectEqual(@as(u64, 0), cfg.rlimit_nproc);
}

test "SandboxConfig rlimit_address_space is at least the documented minimum" {
    const cfg = SandboxConfig{};
    try std.testing.expectEqual(sandbox_defaults.rlimit_address_space, cfg.rlimit_address_space);
    try std.testing.expect(cfg.rlimit_address_space >= sandbox_defaults.min_rlimit_address_space);
}
