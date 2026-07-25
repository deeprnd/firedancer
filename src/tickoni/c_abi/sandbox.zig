/// Narrow Zig bindings over src/util/sandbox/fd_sandbox.h.
///
/// Extern declarations here; C substrate is linked only in the supervisor
/// binary build. Sandbox policy defaults (SandboxConfig) live in
/// src/tickoni/runtime/sandbox.zig. Current process-mode policy keeps macOS
/// and every other non-Linux target at explicit sandbox=none.
///
/// Link requirements: -lfd_util (built by GNUmakefile).
// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_util at link time
// ---------------------------------------------------------------------------

extern fn tk_sandbox_requires_cap_sys_admin(desired_uid: u32, desired_gid: u32) c_int;

/// Enter the sandbox. The seccomp_filter pointer must point to an array of
/// struct sock_filter compiled from a policy by contrib/generate_filters.py.
/// Not called from Zig in Step 1; declared here for type-checking.
extern fn tk_sandbox_enter(
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

extern fn tk_sandbox_switch_uid_gid(desired_uid: u32, desired_gid: u32) void;
extern fn tk_sandbox_getpid() c_int;
extern fn tk_sandbox_gettid() c_int;

pub fn requiresCapSysAdmin(desired_uid: u32, desired_gid: u32) bool {
    return tk_sandbox_requires_cap_sys_admin(desired_uid, desired_gid) != 0;
}

pub fn enter(
    desired_uid: u32,
    desired_gid: u32,
    keep_host_networking: bool,
    allow_connect: bool,
    allow_renameat: bool,
    keep_controlling_terminal: bool,
    dumpable: bool,
    rlimit_file_cnt: u64,
    rlimit_address_space: u64,
    rlimit_data: u64,
    rlimit_nproc: u64,
    allowed_file_descriptor_cnt: u64,
    allowed_file_descriptor: [*]const c_int,
    seccomp_filter_cnt: u64,
    seccomp_filter: *anyopaque,
) void {
    tk_sandbox_enter(
        desired_uid,
        desired_gid,
        @intFromBool(keep_host_networking),
        @intFromBool(allow_connect),
        @intFromBool(allow_renameat),
        @intFromBool(keep_controlling_terminal),
        @intFromBool(dumpable),
        rlimit_file_cnt,
        rlimit_address_space,
        rlimit_data,
        rlimit_nproc,
        allowed_file_descriptor_cnt,
        allowed_file_descriptor,
        seccomp_filter_cnt,
        seccomp_filter,
    );
}

pub fn switchUidGid(desired_uid: u32, desired_gid: u32) void {
    tk_sandbox_switch_uid_gid(desired_uid, desired_gid);
}

pub fn getpid() c_int {
    return tk_sandbox_getpid();
}

pub fn gettid() c_int {
    return tk_sandbox_gettid();
}
