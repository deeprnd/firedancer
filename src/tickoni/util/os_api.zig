/// Cross-platform OS abstraction — re-exports c_abi.os shim.
/// All platform-specific code is in os.c behind #if FD_HAS_LINUX guards.
/// Zig callers just call these — no platform forks in .zig files.
const std = @import("std");
pub const c = @import("c_abi").os;

pub fn monotonicNanos() i64 { return c.monotonicNanos(); }
pub fn sleepNanos(ns: u64) void { c.sleepNanos(ns); }
pub fn selfExePath(buf: []u8) ![]const u8 { return c.selfExePath(buf); }
pub fn parentPid(pid: c_int) c_int { return c.parentPid(pid) catch -1; }
pub fn kill(pid: std.posix.pid_t) void { c.killProcess(@intCast(pid)); }
pub fn write(fd: std.posix.fd_t, buf: []const u8) usize { return c.write(@intCast(fd), buf); }