/// Narrow Zig bindings over the subset of src/util/wksp/fd_wksp.h needed to
/// create/join a named, process-shared workspace that backs Tango
/// mcache/dcache/fseq/cnc objects for V1.14 process mode.
///
/// Uses FD_SHMEM_NORMAL_PAGE_SZ (4 KiB) workspaces, which fd_wksp_new_named
/// backs with a plain file under the FD_SHMEM_PATH directory (see
/// src/util/shmem/fd_shmem_admin.c) rather than hugetlbfs — no gigantic/huge
/// pages or root privileges are required, matching the roadmap requirement
/// that Tickoni not inherit Firedancer validator's hugepage assumption.
///
/// Link requirements: -lfd_util at link time (fd_wksp lives under src/util).
const std = @import("std");

// ---------------------------------------------------------------------------
// Constants (from fd_shmem.h)
// ---------------------------------------------------------------------------

pub const shmem_normal_page_sz: usize = 4096;

/// Opaque workspace handle returned by fd_wksp_new_named / fd_wksp_attach.
pub const Wksp = opaque {};

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_util at link time
// ---------------------------------------------------------------------------

pub const wksp_success: c_int = 0;

/// Returns FD_WKSP_SUCCESS (0) or a negative FD_WKSP_ERR_* code — NOT a
/// workspace handle. Call fd_wksp_attach(name) afterward to join it.
pub extern fn fd_wksp_new_named(
    name: [*:0]const u8,
    page_sz: usize,
    sub_cnt: usize,
    sub_page_cnt: [*]const usize,
    sub_cpu_idx: [*]const usize,
    mode: usize,
    seed: u32,
    opt_part_max: usize,
) c_int;
pub extern fn fd_wksp_delete_named(name: [*:0]const u8) c_int;
pub extern fn fd_wksp_attach(name: [*:0]const u8) ?*Wksp;
pub extern fn fd_wksp_detach(wksp: *Wksp) c_int;
pub extern fn fd_wksp_alloc_at_least(
    wksp: *Wksp,
    alignment: usize,
    sz: usize,
    tag: usize,
    lo: *usize,
    hi: *usize,
) usize;
pub extern fn fd_wksp_free(wksp: *Wksp, gaddr: usize) void;
pub extern fn fd_wksp_laddr(wksp: *const Wksp, gaddr: usize) ?*anyopaque;
pub extern fn fd_wksp_gaddr(wksp: *const Wksp, laddr: *const anyopaque) usize;

/// Mirrors static inline fd_wksp_alloc (fd_wksp.h): a fixed-alignment
/// wrapper around fd_wksp_alloc_at_least with dummy [lo,hi) outputs.
pub fn alloc(wksp: *Wksp, alignment: usize, sz: usize, tag: usize) usize {
    var dummy: [2]usize = .{ 0, 0 };
    return fd_wksp_alloc_at_least(wksp, alignment, sz, tag, &dummy[0], &dummy[1]);
}

// ---------------------------------------------------------------------------
// Tests — constants only; no C linkage required
// ---------------------------------------------------------------------------

test "shmem normal page size matches header" {
    try std.testing.expectEqual(@as(usize, 4096), shmem_normal_page_sz);
}
