/// Monotonic clock, self-exe path resolution, and blocking sleep for
/// Tickoni's V1.14 process-mode tile supervisor and tiles
/// (src/app/tickoni/*). Tickoni-owned runtime utilities, not a
/// Firedancer bridge. CPU affinity and CPU placement policy live in
/// src/tickoni/runtime/cpu.zig.
const std = @import("std");

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
