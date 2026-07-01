/// Narrow Zig bindings over src/tango/dcache/fd_dcache.h.
///
/// Only mirrors real (non-`static inline`) C symbols. `fd_dcache_new`
/// formats a raw payload region; producers/consumers index into it with
/// chunk arithmetic owned by src/tickoni/runtime/shm_link.zig, not here.
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

/// Mirrors the FD_DCACHE_SLOT_FOOTPRINT macro (fd_dcache.h): round mtu up to
/// a dcache_slot_align multiple. Not callable via extern; macros have no
/// linkable symbol.
pub fn dcacheSlotFootprint(mtu: usize) usize {
    return std.mem.alignForward(usize, mtu, dcache_slot_align);
}

/// Mirrors the FD_DCACHE_REQ_DATA_SZ macro (fd_dcache.h).
pub fn dcacheReqDataSz(mtu: usize, depth: usize, burst: usize, compact: bool) usize {
    const extra: usize = if (compact) 1 else 0;
    return dcacheSlotFootprint(mtu) * (depth + burst + extra);
}

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_tango at link time
// ---------------------------------------------------------------------------

pub extern fn fd_dcache_req_data_sz(mtu: usize, depth: usize, burst: usize, compact: c_int) usize;
pub extern fn fd_dcache_align() usize;
pub extern fn fd_dcache_footprint(data_sz: usize, app_sz: usize) usize;
pub extern fn fd_dcache_new(shmem: *anyopaque, data_sz: usize, app_sz: usize) ?*anyopaque;
pub extern fn fd_dcache_join(shdcache: *anyopaque) ?[*]u8;
pub extern fn fd_dcache_leave(dcache: [*]const u8) ?*anyopaque;
pub extern fn fd_dcache_delete(shdcache: *anyopaque) ?*anyopaque;
pub extern fn fd_dcache_data_sz(dcache: [*]const u8) usize;
pub extern fn fd_dcache_app_sz(dcache: [*]const u8) usize;
pub extern fn fd_dcache_app_laddr(dcache: [*]u8) ?[*]u8;
pub extern fn fd_dcache_app_laddr_const(dcache: [*]const u8) ?[*]const u8;
pub extern fn fd_dcache_compact_is_safe(base: *const anyopaque, dcache: *const anyopaque, mtu: usize, depth: usize) c_int;

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
