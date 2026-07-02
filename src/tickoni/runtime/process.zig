/// Zig bindings for CPU affinity, the monotonic clock, and process
/// primitives used by Tickoni's V1.14 process-mode tile supervisor and
/// tiles (src/tickoni/runtime/cpu_placement.zig, src/app/tickoni/*). These
/// are Tickoni's own runtime utilities, not a Firedancer bridge.
///
/// Firedancer has an internal fd_cpuset_t affinity wrapper
/// (src/util/tile/fd_tile_private.h), but that header documents itself as
/// "intended for internal use within fd_tile" and layers a macro-templated
/// bitset (`fd_set.c` with `SET_MAX FD_TILE_MAX`) that has no stable,
/// independently-linkable layout outside fd_tile's own translation unit.
/// Per the "drop to a more explicit lower-level path" guidance in
/// doc/execution/contribution/tickoni.md, this wraps the POSIX
/// sched_getaffinity/sched_setaffinity syscalls directly instead.
///
/// Link requirements: none beyond libc (glibc exposes these directly).
const std = @import("std");

/// Matches glibc's default cpu_set_t size (CPU_SETSIZE=1024 bits).
pub const cpu_set_bytes: usize = 128;
pub const CpuSet = [cpu_set_bytes]u8;

pub fn zero(cpu_set: *CpuSet) void {
    @memset(cpu_set, 0);
}

pub fn set(cpu_set: *CpuSet, cpu: usize) void {
    std.debug.assert(cpu < cpu_set_bytes * 8);
    cpu_set[cpu / 8] |= @as(u8, 1) << @intCast(cpu % 8);
}

pub fn isSet(cpu_set: *const CpuSet, cpu: usize) bool {
    std.debug.assert(cpu < cpu_set_bytes * 8);
    return (cpu_set[cpu / 8] & (@as(u8, 1) << @intCast(cpu % 8))) != 0;
}

pub fn count(cpu_set: *const CpuSet) usize {
    var n: usize = 0;
    for (cpu_set) |byte| n += @popCount(byte);
    return n;
}

/// Monotonic nanosecond clock reading, used for fd_cnc heartbeat values
/// (fd_cnc.h: "typical usage is something that monotonically increases").
/// This Zig build's std.time has no timestamp function of its own (time
/// reads moved behind the std.Io clock abstraction); tile process
/// lifecycle code is not otherwise threaded through an Io instance, so
/// this calls the raw clock_gettime syscall directly instead.
pub fn monotonicNanos() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * std.time.ns_per_s + ts.nsec;
}

/// Resolves the running process's own executable path via /proc/self/exe,
/// for the V1.14 self-exec tile-launch pattern (supervisor re-execs itself
/// as `<self> __tile-run <spec>` per tile). This Zig build's std.fs has no
/// selfExePathAlloc equivalent, so this reads the symlink directly.
pub fn selfExePath(buf: []u8) ![]const u8 {
    const path_z: [*:0]const u8 = "/proc/self/exe";
    const rc: isize = @bitCast(std.os.linux.readlink(path_z, buf.ptr, buf.len));
    if (rc < 0) return error.SelfExePathFailed;
    return buf[0..@intCast(rc)];
}

/// Blocking sleep for the tile heartbeat loop. This Zig build's
/// std.Thread has no sleep of its own (moved behind the std.Io clock
/// abstraction), and tile process lifecycle code is not threaded through
/// an Io instance, so this calls nanosleep directly. May return early on
/// signal delivery; callers loop on their own condition, not on this
/// sleeping for the full requested duration.
pub fn sleepNanos(ns: u64) void {
    const req = std.os.linux.timespec{
        .sec = @intCast(ns / std.time.ns_per_s),
        .nsec = @intCast(ns % std.time.ns_per_s),
    };
    _ = std.os.linux.nanosleep(&req, null);
}

extern "c" fn sched_getaffinity(pid: c_int, cpusetsize: usize, mask: *anyopaque) c_int;
extern "c" fn sched_setaffinity(pid: c_int, cpusetsize: usize, mask: *const anyopaque) c_int;

/// pid==0 means the calling thread.
pub fn getAffinity(pid: c_int, cpu_set: *CpuSet) !void {
    if (sched_getaffinity(pid, cpu_set_bytes, cpu_set) != 0) return error.SchedGetAffinityFailed;
}

/// pid==0 means the calling thread.
pub fn setAffinity(pid: c_int, cpu_set: *const CpuSet) !void {
    if (sched_setaffinity(pid, cpu_set_bytes, cpu_set) != 0) return error.SchedSetAffinityFailed;
}

// ---------------------------------------------------------------------------
// Tests — bit manipulation only; no real syscalls invoked
// ---------------------------------------------------------------------------

test "zero clears all bits" {
    var cs: CpuSet = undefined;
    @memset(&cs, 0xff);
    zero(&cs);
    try std.testing.expectEqual(@as(usize, 0), count(&cs));
}

test "set and isSet round-trip for low and high cpu ids" {
    var cs: CpuSet = undefined;
    zero(&cs);
    set(&cs, 0);
    set(&cs, 63);
    set(&cs, 1023);
    try std.testing.expect(isSet(&cs, 0));
    try std.testing.expect(isSet(&cs, 63));
    try std.testing.expect(isSet(&cs, 1023));
    try std.testing.expect(!isSet(&cs, 1));
    try std.testing.expectEqual(@as(usize, 3), count(&cs));
}
