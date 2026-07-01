/// Narrow Zig bindings over src/tango/cnc/fd_cnc.h.
///
/// `fd_cnc_t` owns tile boot/heartbeat/halt/fail state for V1.14 process
/// mode. Only real (non-`static inline`) C symbols are declared as
/// `extern fn` below. The header's tiny inline accessors
/// (`fd_cnc_signal`, `fd_cnc_signal_query`, `fd_cnc_heartbeat`,
/// `fd_cnc_heartbeat_query`, `fd_cnc_app_laddr`, `fd_cnc_close`) have no
/// linkable symbol, so they are mirrored here as direct volatile
/// field/offset access — the same precedent as
/// src/tickoni/c_abi/queue.zig's `fd_mcache_seq_laddr`. The field offsets
/// and the `+64` app-region offset are pinned by the layout test below
/// against the `struct fd_cnc_private` declaration in the header.
const std = @import("std");

// ---------------------------------------------------------------------------
// Constants (from fd_cnc.h)
// ---------------------------------------------------------------------------

pub const cnc_align: usize = 128;
pub const cnc_app_align: usize = 64;
/// fd_cnc_app_laddr returns `((ulong)cnc) + 64UL` literally, not a
/// sizeof-derived offset — mirrored here as the same literal.
pub const cnc_app_offset: usize = 64;

pub const signal_run: u64 = 0;
pub const signal_boot: u64 = 1;
pub const signal_fail: u64 = 2;
pub const signal_halt: u64 = 3;

pub const err_success: i32 = 0;
pub const err_unsup: i32 = -1;
pub const err_inval: i32 = -2;
pub const err_again: i32 = -3;
pub const err_fail: i32 = -4;

/// Layout-only mirror of `struct fd_cnc_private` (fd_cnc.h) for offset
/// tests. Not used to allocate memory in Zig; `fd_cnc_new`/`fd_cnc_join`
/// own the real region.
pub const CncPrivate = extern struct {
    magic: u64,
    app_sz: u64,
    type: u64,
    heartbeat0: i64,
    heartbeat: i64,
    lock: u64,
    signal: u64,
};

pub const cnc_magic: u64 = 0xf17eda2c37c2c000;

/// Opaque handle returned by fd_cnc_join.
pub const Cnc = opaque {};

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_tango at link time
// ---------------------------------------------------------------------------

pub extern fn fd_cnc_align() usize;
pub extern fn fd_cnc_footprint(app_sz: usize) usize;
pub extern fn fd_cnc_new(shmem: *anyopaque, app_sz: usize, cnc_type: u64, now: i64) ?*anyopaque;
pub extern fn fd_cnc_join(shcnc: *anyopaque) ?*Cnc;
pub extern fn fd_cnc_leave(cnc: *const Cnc) ?*anyopaque;
pub extern fn fd_cnc_delete(shcnc: *anyopaque) ?*anyopaque;
pub extern fn fd_cnc_open(cnc: *Cnc) c_int;
pub extern fn fd_cnc_wait(cnc: *const Cnc, test_signal: u64, dt: i64, opt_now: ?*i64) u64;
pub extern fn fd_cnc_strerror(err: c_int) [*:0]const u8;
pub extern fn fd_cstr_to_cnc_signal(cstr: [*:0]const u8) u64;
pub extern fn fd_cnc_signal_cstr(signal: u64, buf: [*]u8) [*:0]u8;

// ---------------------------------------------------------------------------
// Direct volatile mirrors of the header's `static inline` accessors.
// ---------------------------------------------------------------------------

fn asPrivate(cnc: *Cnc) *volatile CncPrivate {
    return @ptrCast(@alignCast(cnc));
}

fn asPrivateConst(cnc: *const Cnc) *const volatile CncPrivate {
    return @ptrCast(@alignCast(cnc));
}

/// Mirrors static inline fd_cnc_app_laddr (fd_cnc.h).
pub fn appLaddr(cnc: *Cnc) [*]u8 {
    return @as([*]u8, @ptrCast(cnc)) + cnc_app_offset;
}

pub const app_counter_cap: usize = 8;

/// Reads one u64 counter slot from the cnc's app-defined region
/// (fd_cnc_app_laddr). Tickoni process-mode tiles publish their own local
/// produced/normalized/etc. counters here so a diagnostics reader can see
/// them across the process boundary without a separate shared object per
/// counter. Callers must ensure the cnc was created with app_sz >=
/// (idx+1)*8.
pub fn appCounterRead(cnc: *Cnc, idx: usize) u64 {
    std.debug.assert(idx < app_counter_cap);
    const base = appLaddr(cnc);
    const ptr: *const volatile u64 = @ptrCast(@alignCast(base + idx * 8));
    return ptr.*;
}

/// Writes one u64 counter slot in the cnc's app-defined region.
pub fn appCounterWrite(cnc: *Cnc, idx: usize, value: u64) void {
    std.debug.assert(idx < app_counter_cap);
    const base = appLaddr(cnc);
    const ptr: *volatile u64 = @ptrCast(@alignCast(base + idx * 8));
    ptr.* = value;
}

/// Mirrors static inline fd_cnc_heartbeat_query (fd_cnc.h).
pub fn heartbeatQuery(cnc: *const Cnc) i64 {
    return asPrivateConst(cnc).heartbeat;
}

/// Mirrors static inline fd_cnc_heartbeat (fd_cnc.h).
pub fn heartbeat(cnc: *Cnc, now: i64) void {
    asPrivate(cnc).heartbeat = now;
}

/// Mirrors static inline fd_cnc_signal_query (fd_cnc.h).
pub fn signalQuery(cnc: *const Cnc) u64 {
    return asPrivateConst(cnc).signal;
}

/// Mirrors static inline fd_cnc_signal (fd_cnc.h).
pub fn signal(cnc: *Cnc, s: u64) void {
    asPrivate(cnc).signal = s;
}

/// Mirrors static inline fd_cnc_close (fd_cnc.h).
pub fn close(cnc: *Cnc) void {
    asPrivate(cnc).lock = 0;
}

// ---------------------------------------------------------------------------
// Tests — layout only; no C linkage required
// ---------------------------------------------------------------------------

test "CncPrivate field offsets match fd_cnc_private layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(CncPrivate, "magic"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(CncPrivate, "app_sz"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(CncPrivate, "type"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(CncPrivate, "heartbeat0"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(CncPrivate, "heartbeat"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(CncPrivate, "lock"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(CncPrivate, "signal"));
}

test "cnc alignment and app-region offset constants match header" {
    try std.testing.expectEqual(@as(usize, 128), cnc_align);
    try std.testing.expectEqual(@as(usize, 64), cnc_app_align);
    try std.testing.expectEqual(@as(usize, 64), cnc_app_offset);
}

test "appCounterRead/Write round-trip within a fake cnc-shaped buffer" {
    var buf: [256]u8 align(128) = [_]u8{0} ** 256;
    const cnc: *Cnc = @ptrCast(&buf);
    appCounterWrite(cnc, 0, 42);
    appCounterWrite(cnc, 7, 100);
    try std.testing.expectEqual(@as(u64, 42), appCounterRead(cnc, 0));
    try std.testing.expectEqual(@as(u64, 100), appCounterRead(cnc, 7));
    try std.testing.expectEqual(@as(u64, 0), appCounterRead(cnc, 1));
}

test "cnc signal constants match header" {
    try std.testing.expectEqual(@as(u64, 0), signal_run);
    try std.testing.expectEqual(@as(u64, 1), signal_boot);
    try std.testing.expectEqual(@as(u64, 2), signal_fail);
    try std.testing.expectEqual(@as(u64, 3), signal_halt);
}
