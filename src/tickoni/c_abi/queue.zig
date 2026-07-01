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

// ---------------------------------------------------------------------------
// Constants (from fd_tango_base.h / fd_mcache.h)
// ---------------------------------------------------------------------------

pub const frag_meta_sz: usize = 32;
pub const frag_meta_align: usize = 32;
pub const mcache_align: usize = 128;
pub const mcache_seq_cnt: usize = 16;
pub const mcache_lg_interleave: usize = 0;
pub const mcache_block: usize = 1;

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_tango at link time
//
// fd_mcache_join returns fd_frag_meta_t* (a directly indexable [0,depth)
// array), not an opaque handle — confirmed against fd_mcache.h; the
// earlier opaque Mcache type here did not match the real ABI and was
// never exercised until src/tickoni/runtime/shm_link.zig needed it.
// ---------------------------------------------------------------------------

pub extern fn fd_mcache_align() usize;
pub extern fn fd_mcache_footprint(depth: usize, app_sz: usize) usize;
pub extern fn fd_mcache_new(shmem: *anyopaque, depth: usize, app_sz: usize, seq0: u64) ?*anyopaque;
pub extern fn fd_mcache_join(shcache: *anyopaque) ?[*]FragMeta;
pub extern fn fd_mcache_leave(mcache: [*]const FragMeta) ?*anyopaque;
pub extern fn fd_mcache_delete(shcache: *anyopaque) ?*anyopaque;
pub extern fn fd_mcache_depth(mcache: [*]const FragMeta) usize;
pub extern fn fd_mcache_seq0(mcache: [*]const FragMeta) u64;
pub extern fn fd_mcache_seq_laddr(mcache: [*]FragMeta) [*]volatile u64;
pub extern fn fd_mcache_seq_laddr_const(mcache: [*]const FragMeta) [*]const volatile u64;

/// Mirrors FD_COMPILER_MFENCE (fd_tango_base.h): a compiler-only ordering
/// barrier (no CPU fence instruction), matching Firedancer's reliance on
/// x86-64 TSO for cross-thread/process visibility.
fn compilerFence() void {
    asm volatile ("" ::: .{ .memory = true });
}

/// Mirrors static inline fd_mcache_line_idx (fd_mcache.h) for the
/// FD_MCACHE_LG_INTERLEAVE==0 build (the header's compiled-in default) —
/// not callable via extern; it is a static inline with no linkable symbol.
pub fn mcacheLineIdx(seq: u64, depth: usize) usize {
    return @intCast(seq & (depth - 1));
}

/// Mirrors static inline fd_mcache_publish (fd_mcache.h): writes frag
/// metadata for `seq` into the ring, marking the line in-progress (seq-1)
/// before the payload-adjacent fields are written and only publishing the
/// real `seq` once they are, so a consumer never observes a torn frag.
pub fn mcachePublish(
    mcache: [*]FragMeta,
    depth: usize,
    seq: u64,
    sig: u64,
    chunk: u32,
    sz: u16,
    ctl: u16,
    tsorig: u32,
    tspub: u32,
) void {
    const meta: *volatile FragMeta = @ptrCast(&mcache[mcacheLineIdx(seq, depth)]);
    meta.seq = seq -% 1;
    compilerFence();
    meta.sig = sig;
    meta.chunk = chunk;
    meta.sz = sz;
    meta.ctl = ctl;
    meta.tsorig = tsorig;
    meta.tspub = tspub;
    compilerFence();
    meta.seq = seq;
}

/// Mirrors static inline fd_frag_meta_seq_query (fd_tango_base.h).
pub fn fragMetaSeqQuery(meta: *const volatile FragMeta) u64 {
    return meta.seq;
}

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

test "mcacheLineIdx wraps modulo depth" {
    try std.testing.expectEqual(@as(usize, 5), mcacheLineIdx(5, 8));
    try std.testing.expectEqual(@as(usize, 5), mcacheLineIdx(13, 8));
    try std.testing.expectEqual(@as(usize, 0), mcacheLineIdx(8, 8));
}

test "mcachePublish writes a frag readable via fragMetaSeqQuery" {
    var ring: [8]FragMeta = undefined;
    mcachePublish(&ring, 8, 5, 42, 3, 10, 0, 0, 0);

    const line = mcacheLineIdx(5, 8);
    const meta: *const volatile FragMeta = @ptrCast(&ring[line]);
    try std.testing.expectEqual(@as(u64, 5), fragMetaSeqQuery(meta));
    try std.testing.expectEqual(@as(u64, 42), ring[line].sig);
    try std.testing.expectEqual(@as(u32, 3), ring[line].chunk);
    try std.testing.expectEqual(@as(u16, 10), ring[line].sz);
}
