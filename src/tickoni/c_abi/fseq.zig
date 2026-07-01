/// Narrow Zig bindings over src/tango/fseq/fd_fseq.h.
///
/// Only mirrors real (non-`static inline`) C symbols: align/footprint/
/// new/join/leave/delete. `fd_fseq_query`/`fd_fseq_update`/`fd_fseq_seq0`/
/// `fd_fseq_app_laddr` are `static inline` in the header (no linkable
/// symbol); src/tickoni/runtime/shm_link.zig operates on the joined
/// `[*]volatile u64` directly at the documented offsets instead of wrapping
/// them here, matching src/tickoni/c_abi/queue.zig's existing
/// `fd_mcache_seq_laddr` precedent.
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

pub extern fn fd_fseq_align() usize;
pub extern fn fd_fseq_footprint() usize;
pub extern fn fd_fseq_new(shmem: *anyopaque, seq0: u64) ?*anyopaque;
pub extern fn fd_fseq_join(shfseq: *anyopaque) ?[*]volatile u64;
pub extern fn fd_fseq_leave(fseq: [*]const u64) ?*anyopaque;
pub extern fn fd_fseq_delete(shfseq: *anyopaque) ?*anyopaque;

// ---------------------------------------------------------------------------
// Tests — layout only; no C linkage required
// ---------------------------------------------------------------------------

test "fseq alignment constants match header" {
    try std.testing.expectEqual(@as(usize, 128), fseq_align);
    try std.testing.expectEqual(@as(usize, 128), fseq_footprint);
    try std.testing.expectEqual(@as(usize, 32), fseq_app_align);
    try std.testing.expectEqual(@as(usize, 96), fseq_app_footprint);
}
