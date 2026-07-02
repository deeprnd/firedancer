/// Narrow Zig bindings over src/tango/fseq/fd_fseq.h.
///
/// Zig callers bind only through Tickoni-owned `tk_*` shim symbols; the shim
/// calls the real Firedancer functions/static inline helpers.
const std = @import("std");

// ---------------------------------------------------------------------------
// Constants (from fd_fseq.h)
// ---------------------------------------------------------------------------

pub const fseq_align: usize = 128;
pub const fseq_footprint: usize = 128;
pub const fseq_app_align: usize = 32;
pub const fseq_app_footprint: usize = 96;

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_tango at link time
// ---------------------------------------------------------------------------

extern fn tk_fseq_align() usize;
extern fn tk_fseq_footprint() usize;
extern fn tk_fseq_new(shmem: *anyopaque, seq0: u64) ?*anyopaque;
extern fn tk_fseq_join(shfseq: *anyopaque) ?[*]volatile u64;
extern fn tk_fseq_leave(fseq: [*]const u64) ?*anyopaque;
extern fn tk_fseq_delete(shfseq: *anyopaque) ?*anyopaque;

pub fn fseqAlign() usize {
    return tk_fseq_align();
}

pub fn fseqFootprint() usize {
    return tk_fseq_footprint();
}

pub fn fseqNew(shmem: *anyopaque, seq0: u64) ?*anyopaque {
    return tk_fseq_new(shmem, seq0);
}

pub fn fseqJoin(shfseq: *anyopaque) ?[*]volatile u64 {
    return tk_fseq_join(shfseq);
}

pub fn fseqLeave(fseq: [*]const u64) ?*anyopaque {
    return tk_fseq_leave(fseq);
}

pub fn fseqDelete(shfseq: *anyopaque) ?*anyopaque {
    return tk_fseq_delete(shfseq);
}

/// Wraps the upstream fseq query helper. Binds to shim/tango.c.
extern fn tk_fseq_query(fseq: [*]const u64) u64;
pub fn fseqQuery(fseq: [*]volatile u64) u64 {
    return tk_fseq_query(@volatileCast(fseq));
}

/// Wraps the upstream fseq update helper. Binds to shim/tango.c.
extern fn tk_fseq_update(fseq: [*]u64, seq: u64) void;
pub fn fseqUpdate(fseq: [*]volatile u64, seq: u64) void {
    tk_fseq_update(@volatileCast(fseq), seq);
}

// ---------------------------------------------------------------------------
// Tests — alignment constants need no C linkage; fseqQuery/fseqUpdate tests
// link shim/tango.c.
// ---------------------------------------------------------------------------

test "fseq alignment constants match header" {
    try std.testing.expectEqual(@as(usize, 128), fseq_align);
    try std.testing.expectEqual(@as(usize, 128), fseq_footprint);
    try std.testing.expectEqual(@as(usize, 32), fseq_app_align);
    try std.testing.expectEqual(@as(usize, 96), fseq_app_footprint);
}

test "fseqUpdate then fseqQuery round-trips the published sequence number" {
    var slot: [1]u64 = .{0};
    const fseq: [*]volatile u64 = @ptrCast(&slot);
    fseqUpdate(fseq, 42);
    try std.testing.expectEqual(@as(u64, 42), fseqQuery(fseq));
}
