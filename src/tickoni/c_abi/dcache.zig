/// Narrow Zig bindings over src/tango/dcache/fd_dcache.h.
///
/// Zig callers bind only through Tickoni-owned `tk_*` shim symbols; the shim
/// calls the real Firedancer functions/macros.
///
/// Link requirements: -lfd_tango -lfd_util at link time.
const std = @import("std");

// ---------------------------------------------------------------------------
// Constants (from fd_tango_base.h / fd_dcache.h)
// ---------------------------------------------------------------------------

pub const chunk_align: usize = 64;
pub const dcache_align: usize = 4096;
pub const dcache_slot_align: usize = 128;
pub const dcache_guard_footprint: usize = 3968;

extern fn tk_dcache_slot_footprint(mtu: usize) usize;
extern fn tk_dcache_req_data_sz(mtu: usize, depth: usize, burst: usize, compact: c_int) usize;
extern fn tk_dcache_align() usize;
extern fn tk_dcache_footprint(data_sz: usize, app_sz: usize) usize;
extern fn tk_dcache_new(shmem: *anyopaque, data_sz: usize, app_sz: usize) ?*anyopaque;
extern fn tk_dcache_join(shdcache: *anyopaque) ?[*]u8;
extern fn tk_dcache_leave(dcache: [*]const u8) ?*anyopaque;
extern fn tk_dcache_delete(shdcache: *anyopaque) ?*anyopaque;
extern fn tk_dcache_data_sz(dcache: [*]const u8) usize;
extern fn tk_dcache_app_sz(dcache: [*]const u8) usize;
extern fn tk_dcache_app_laddr(dcache: [*]u8) ?[*]u8;
extern fn tk_dcache_app_laddr_const(dcache: [*]const u8) ?[*]const u8;
extern fn tk_dcache_compact_is_safe(base: *const anyopaque, dcache: *const anyopaque, mtu: usize, depth: usize) c_int;

pub fn dcacheSlotFootprint(mtu: usize) usize {
    return tk_dcache_slot_footprint(mtu);
}

pub fn dcacheReqDataSz(mtu: usize, depth: usize, burst: usize, compact: bool) usize {
    return tk_dcache_req_data_sz(mtu, depth, burst, @intFromBool(compact));
}

pub fn dcacheAlign() usize {
    return tk_dcache_align();
}

pub fn dcacheFootprint(data_sz: usize, app_sz: usize) usize {
    return tk_dcache_footprint(data_sz, app_sz);
}

pub fn dcacheNew(shmem: *anyopaque, data_sz: usize, app_sz: usize) ?*anyopaque {
    return tk_dcache_new(shmem, data_sz, app_sz);
}

pub fn dcacheJoin(shdcache: *anyopaque) ?[*]u8 {
    return tk_dcache_join(shdcache);
}

pub fn dcacheLeave(dcache: [*]const u8) ?*anyopaque {
    return tk_dcache_leave(dcache);
}

pub fn dcacheDelete(shdcache: *anyopaque) ?*anyopaque {
    return tk_dcache_delete(shdcache);
}

pub fn dcacheDataSz(dcache: [*]const u8) usize {
    return tk_dcache_data_sz(dcache);
}

pub fn dcacheAppSz(dcache: [*]const u8) usize {
    return tk_dcache_app_sz(dcache);
}

pub fn dcacheAppLaddr(dcache: [*]u8) ?[*]u8 {
    return tk_dcache_app_laddr(dcache);
}

pub fn dcacheAppLaddrConst(dcache: [*]const u8) ?[*]const u8 {
    return tk_dcache_app_laddr_const(dcache);
}

pub fn dcacheCompactIsSafe(base: *const anyopaque, dcache: *const anyopaque, mtu: usize, depth: usize) bool {
    return tk_dcache_compact_is_safe(base, dcache, mtu, depth) != 0;
}

// ---------------------------------------------------------------------------
// Tests — layout and macro-mirror checks only; no C linkage required
// ---------------------------------------------------------------------------

test "dcache alignment constants match header" {
    try std.testing.expectEqual(@as(usize, 4096), dcache_align);
    try std.testing.expectEqual(@as(usize, 128), dcache_slot_align);
    try std.testing.expectEqual(@as(usize, 3968), dcache_guard_footprint);
    try std.testing.expectEqual(@as(usize, 64), chunk_align);
}

test "dcacheSlotFootprint rounds up to slot_align multiple" {
    try std.testing.expectEqual(@as(usize, 128), dcacheSlotFootprint(1));
    try std.testing.expectEqual(@as(usize, 128), dcacheSlotFootprint(128));
    try std.testing.expectEqual(@as(usize, 256), dcacheSlotFootprint(129));
}

test "dcacheReqDataSz matches FD_DCACHE_REQ_DATA_SZ for a known example" {
    // mtu=256 (slot=256), depth=64, burst=1, non-compact: 256 * (64+1+0) = 16640
    try std.testing.expectEqual(@as(usize, 16640), dcacheReqDataSz(256, 64, 1, false));
    // Same with compact=true adds one more slot: 256 * (64+1+1) = 16896
    try std.testing.expectEqual(@as(usize, 16896), dcacheReqDataSz(256, 64, 1, true));
}
