/// Narrow Zig bindings over src/tango mcache/dcache primitives.
///
/// Mirrors the public API in src/tango/mcache/fd_mcache.h. The
/// mcacheLineIdx/mcachePublish/fragMetaSeqQuery wrappers bind to
/// shim/tango.c. See doc/knowledge/architecture.md.
///
/// Link requirements: -lfd_tango -lfd_util plus shim/tango.c, via
/// linkTickoniTango in build.zig.
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

extern fn tk_mcache_align() usize;
extern fn tk_mcache_footprint(depth: usize, app_sz: usize) usize;
extern fn tk_mcache_new(shmem: *anyopaque, depth: usize, app_sz: usize, seq0: u64) ?*anyopaque;
extern fn tk_mcache_join(shcache: *anyopaque) ?[*]FragMeta;
extern fn tk_mcache_leave(mcache: [*]const FragMeta) ?*anyopaque;
extern fn tk_mcache_delete(shcache: *anyopaque) ?*anyopaque;
extern fn tk_mcache_depth(mcache: [*]const FragMeta) usize;
extern fn tk_mcache_seq0(mcache: [*]const FragMeta) u64;
extern fn tk_mcache_seq_laddr(mcache: [*]FragMeta) [*]volatile u64;
extern fn tk_mcache_seq_laddr_const(mcache: [*]const FragMeta) [*]const volatile u64;

pub fn mcacheAlign() usize {
    return tk_mcache_align();
}

pub fn mcacheFootprint(depth: usize, app_sz: usize) usize {
    return tk_mcache_footprint(depth, app_sz);
}

pub fn mcacheNew(shmem: *anyopaque, depth: usize, app_sz: usize, seq0: u64) ?*anyopaque {
    return tk_mcache_new(shmem, depth, app_sz, seq0);
}

pub fn mcacheJoin(shcache: *anyopaque) ?[*]FragMeta {
    return tk_mcache_join(shcache);
}

pub fn mcacheLeave(mcache: [*]const FragMeta) ?*anyopaque {
    return tk_mcache_leave(mcache);
}

pub fn mcacheDelete(shcache: *anyopaque) ?*anyopaque {
    return tk_mcache_delete(shcache);
}

pub fn mcacheDepth(mcache: [*]const FragMeta) usize {
    return tk_mcache_depth(mcache);
}

pub fn mcacheSeq0(mcache: [*]const FragMeta) u64 {
    return tk_mcache_seq0(mcache);
}

pub fn mcacheSeqLaddr(mcache: [*]FragMeta) [*]volatile u64 {
    return tk_mcache_seq_laddr(mcache);
}

pub fn mcacheSeqLaddrConst(mcache: [*]const FragMeta) [*]const volatile u64 {
    return tk_mcache_seq_laddr_const(mcache);
}

/// Wraps fd_mcache_line_idx (fd_mcache.h) for the FD_MCACHE_LG_INTERLEAVE==0
/// build (the header's compiled-in default). Binds to shim/tango.c.
extern fn tk_mcache_line_idx(seq: u64, depth: u64) u64;
pub fn mcacheLineIdx(seq: u64, depth: usize) usize {
    return @intCast(tk_mcache_line_idx(seq, depth));
}

/// Wraps fd_mcache_publish (fd_mcache.h): writes frag metadata for `seq`
/// into the ring, marking the line in-progress (seq-1) before the
/// payload-adjacent fields are written and only publishing the real `seq`
/// once they are, so a consumer never observes a torn frag. Binds to
/// shim/tango.c.
extern fn tk_mcache_publish(
    mcache: [*]FragMeta,
    depth: u64,
    seq: u64,
    sig: u64,
    chunk: u64,
    sz: u64,
    ctl: u64,
    tsorig: u64,
    tspub: u64,
) void;
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
    tk_mcache_publish(mcache, depth, seq, sig, chunk, sz, ctl, tsorig, tspub);
}

/// Wraps fd_frag_meta_seq_query (fd_tango_base.h). Binds to shim/tango.c.
extern fn tk_frag_meta_seq_query(meta: *const volatile FragMeta) u64;
pub fn fragMetaSeqQuery(meta: *const volatile FragMeta) u64 {
    return tk_frag_meta_seq_query(meta);
}

// ---------------------------------------------------------------------------
// Tests — FragMeta layout and the mcache_align constant need no C linkage;
// mcacheLineIdx/mcachePublish/fragMetaSeqQuery tests link shim/tango.c.
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
