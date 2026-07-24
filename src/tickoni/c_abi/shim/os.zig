/// Zig extern declarations for os.c cross-platform OS operations shim.
/// All platform-specific code is in os.c behind #if FD_HAS_LINUX guards.
pub const c = struct {
    pub extern fn tk_monotonic_nanos() i64;
    pub extern fn tk_sleep_nanos(ns: u64) void;
    pub extern fn tk_self_exe_path(buf: [*]u8, buf_len: usize) c_int;
    pub extern fn tk_parent_pid(pid: c_int) c_int;
    pub extern fn tk_kill_process(pid: c_int) c_int;
    pub extern fn tk_write(fd: c_int, buf: [*]const u8, count: usize) usize;
};

pub fn monotonicNanos() i64 {
    return c.tk_monotonic_nanos();
}

pub fn sleepNanos(ns: u64) void {
    c.tk_sleep_nanos(ns);
}

pub fn selfExePath(buf: []u8) ![]const u8 {
    const n = c.tk_self_exe_path(buf.ptr, @intCast(buf.len));
    if (n < 0) return error.SelfExePathFailed;
    return buf[0..@as(usize, @intCast(n))];
}

pub fn parentPid(pid: c_int) !c_int {
    const r = c.tk_parent_pid(pid);
    if (r < 0) return error.PPidNotFound;
    return r;
}

pub fn killProcess(pid: c_int) void {
    _ = c.tk_kill_process(pid);
}

pub fn write(fd: c_int, buf: []const u8) usize {
    return c.tk_write(fd, buf.ptr, buf.len);
}
