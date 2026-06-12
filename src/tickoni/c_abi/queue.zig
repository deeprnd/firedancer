/// Narrow Zig bindings over src/tango mcache/dcache primitives.
///
/// Mirrors the public API in src/tango/mcache/fd_mcache.h.
/// These declarations are not called during Step 1 tests; the C substrate
/// is linked only when building the supervisor binary against Firedancer.
///
/// Link requirements: -lfd_tango -lfd_util (built by GNUmakefile).
const std = @import("std");

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Fragment metadata. Matches the named-struct view of fd_frag_meta_t
/// (src/tango/fd_tango_base.h). Size and alignment: 32 bytes / 32 bytes.
pub const FragMeta = extern struct {
    seq: u64,
    sig: u64,
    chunk: u32,
    sz: u16,
    ctl: u16,
    tsorig: u32,
    tspub: u32,
};

/// Message cache (mcache) opaque handle.
pub const Mcache = opaque {};

/// Data cache (dcache) opaque handle.
pub const Dcache = opaque {};

// ---------------------------------------------------------------------------
// Constants (from fd_tango_base.h / fd_mcache.h)
// ---------------------------------------------------------------------------

pub const frag_meta_sz: usize = 32;
pub const frag_meta_align: usize = 32;
pub const mcache_align: usize = 128;
pub const mcache_seq_cnt: usize = 16;

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_tango at link time
// ---------------------------------------------------------------------------

pub extern fn fd_mcache_align() usize;
pub extern fn fd_mcache_footprint(depth: usize, app_sz: usize) usize;
pub extern fn fd_mcache_new(shmem: *anyopaque, depth: usize, app_sz: usize, seq0: u64) ?*anyopaque;
pub extern fn fd_mcache_join(shcache: *anyopaque) ?*Mcache;
pub extern fn fd_mcache_leave(mcache: *Mcache) ?*anyopaque;
pub extern fn fd_mcache_delete(shcache: *anyopaque) ?*anyopaque;
pub extern fn fd_mcache_depth(mcache: *const Mcache) usize;
pub extern fn fd_mcache_seq0(mcache: *const Mcache) u64;
pub extern fn fd_mcache_seq_laddr(mcache: *Mcache) [*]volatile u64;
pub extern fn fd_mcache_seq_laddr_const(mcache: *const Mcache) [*]const volatile u64;

// ---------------------------------------------------------------------------
// Tests — layout only; no C linkage required
// ---------------------------------------------------------------------------

test "FragMeta is 32 bytes" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(FragMeta));
}

test "FragMeta field offsets match C layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(FragMeta, "seq"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(FragMeta, "sig"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(FragMeta, "chunk"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(FragMeta, "sz"));
    try std.testing.expectEqual(@as(usize, 22), @offsetOf(FragMeta, "ctl"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(FragMeta, "tsorig"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(FragMeta, "tspub"));
}

test "mcache alignment constant matches header" {
    try std.testing.expectEqual(@as(usize, 128), mcache_align);
}
