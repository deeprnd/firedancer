/// Narrow Zig bindings over src/disco/topo/fd_topob.h's topology builder
/// (fd_topob_new/wksp/obj/link/tile/tile_in/tile_out/finish) plus the two
/// parent-side workspace-materialization steps
/// (fd_topo_create_workspace/fd_topo_wksp_new) and the read-only topology
/// finders (fd_topo_find_wksp/find_tile/find_link, fd_topo_obj_laddr).
///
/// Depends on topo_run.zig for the shared opaque Topo/TopoTile types —
/// this file builds a Topo, topo_run.zig launches it; they must be the
/// same Zig type since they're the same underlying C type.
///
/// This file and shim/topob.c never expose fd_topo_obj_callbacks_t or any
/// Firedancer object-callback type to Zig: Tickoni's own 6-entry callback
/// array (mcache/dcache/fseq/metrics/tile/cnc — see shim/topob.c's module
/// doc for why "tile" and "cnc" are Tickoni-owned rather than reused from
/// src/app/shared/fd_obj_callbacks.c) lives entirely inside the C shim.
///
/// Link requirements: -lfd_disco -lfd_ballet -lfd_waltz -lfd_tango
/// -lfd_util and shim/topob.c at link time.
const topo_run = @import("topo_run.zig");

pub const Topo = topo_run.Topo;
pub const TopoTile = topo_run.TopoTile;

pub const shmem_join_mode_read_only: c_int = 0;
pub const shmem_join_mode_read_write: c_int = 1;

// ---------------------------------------------------------------------------
// Extern declarations.
// ---------------------------------------------------------------------------

extern fn tk_topo_sizeof() usize;
extern fn tk_topo_alignof() usize;
extern fn tk_topob_new(mem: *anyopaque, app_name: [*:0]const u8) ?*Topo;
extern fn tk_topob_wksp(topo: *Topo, name: [*:0]const u8) usize;
extern fn tk_topob_obj(topo: *Topo, obj_type: [*:0]const u8, wksp_name: [*:0]const u8) usize;
extern fn tk_topob_tile_uses(topo: *Topo, tile_id: usize, obj_id: usize, mode: c_int) void;
extern fn tk_topob_link(topo: *Topo, link_name: [*:0]const u8, wksp_name: [*:0]const u8, depth: usize, mtu: usize, burst: usize) usize;
extern fn tk_topob_tile(topo: *Topo, tile_name: [*:0]const u8, tile_wksp: [*:0]const u8, metrics_wksp: [*:0]const u8, cpu_idx: usize) usize;
extern fn tk_topob_tile_in(topo: *Topo, tile_name: [*:0]const u8, tile_kind_id: usize, fseq_wksp: [*:0]const u8, link_name: [*:0]const u8, link_kind_id: usize, reliable: c_int, polled: c_int) void;
extern fn tk_topob_tile_out(topo: *Topo, tile_name: [*:0]const u8, tile_kind_id: usize, link_name: [*:0]const u8, link_kind_id: usize) void;
extern fn tk_topob_finish(topo: *Topo) void;
extern fn tk_topo_create_workspace(topo: *Topo, wksp_idx: usize, update_existing: c_int) c_int;
extern fn tk_topo_wksp_new(topo: *Topo, wksp_idx: usize) void;
extern fn tk_topo_find_wksp(topo: *Topo, name: [*:0]const u8) usize;
extern fn tk_topo_find_tile(topo: *Topo, name: [*:0]const u8, kind_id: usize) usize;
extern fn tk_topo_find_link(topo: *Topo, name: [*:0]const u8, kind_id: usize) usize;
extern fn tk_topo_obj_laddr(topo: *Topo, obj_id: usize) *anyopaque;
extern fn tk_topo_tile_ptr(topo: *Topo, tile_id: usize) *TopoTile;

// ---------------------------------------------------------------------------
// Public Zig wrappers.
// ---------------------------------------------------------------------------

/// Not found sentinel, matching Firedancer's ULONG_MAX convention for
/// fd_topo_find_wksp/find_tile/find_link.
pub const not_found: usize = ~@as(usize, 0);

pub fn topoSizeof() usize {
    return tk_topo_sizeof();
}

pub fn topoAlignof() usize {
    return tk_topo_alignof();
}

pub fn topobNew(mem: *anyopaque, app_name: [*:0]const u8) ?*Topo {
    return tk_topob_new(mem, app_name);
}

pub fn topobWksp(topo: *Topo, name: [*:0]const u8) usize {
    return tk_topob_wksp(topo, name);
}

pub fn topobObj(topo: *Topo, obj_type: [*:0]const u8, wksp_name: [*:0]const u8) usize {
    return tk_topob_obj(topo, obj_type, wksp_name);
}

pub fn topobTileUses(topo: *Topo, tile_id: usize, obj_id: usize, read_write: bool) void {
    tk_topob_tile_uses(topo, tile_id, obj_id, if (read_write) shmem_join_mode_read_write else shmem_join_mode_read_only);
}

pub fn topobLink(topo: *Topo, link_name: [*:0]const u8, wksp_name: [*:0]const u8, depth: usize, mtu: usize, burst: usize) usize {
    return tk_topob_link(topo, link_name, wksp_name, depth, mtu, burst);
}

pub fn topobTile(topo: *Topo, tile_name: [*:0]const u8, tile_wksp: [*:0]const u8, metrics_wksp: [*:0]const u8, cpu_idx: usize) usize {
    return tk_topob_tile(topo, tile_name, tile_wksp, metrics_wksp, cpu_idx);
}

pub fn topobTileIn(topo: *Topo, tile_name: [*:0]const u8, tile_kind_id: usize, fseq_wksp: [*:0]const u8, link_name: [*:0]const u8, link_kind_id: usize, reliable: bool, polled: bool) void {
    tk_topob_tile_in(topo, tile_name, tile_kind_id, fseq_wksp, link_name, link_kind_id, @intFromBool(reliable), @intFromBool(polled));
}

pub fn topobTileOut(topo: *Topo, tile_name: [*:0]const u8, tile_kind_id: usize, link_name: [*:0]const u8, link_kind_id: usize) void {
    tk_topob_tile_out(topo, tile_name, tile_kind_id, link_name, link_kind_id);
}

pub fn topobFinish(topo: *Topo) void {
    tk_topob_finish(topo);
}

pub fn topoCreateWorkspace(topo: *Topo, wksp_idx: usize, update_existing: bool) c_int {
    return tk_topo_create_workspace(topo, wksp_idx, @intFromBool(update_existing));
}

pub fn topoWkspNew(topo: *Topo, wksp_idx: usize) void {
    tk_topo_wksp_new(topo, wksp_idx);
}

pub fn topoFindWksp(topo: *Topo, name: [*:0]const u8) usize {
    return tk_topo_find_wksp(topo, name);
}

pub fn topoFindTile(topo: *Topo, name: [*:0]const u8, kind_id: usize) usize {
    return tk_topo_find_tile(topo, name, kind_id);
}

pub fn topoFindLink(topo: *Topo, name: [*:0]const u8, kind_id: usize) usize {
    return tk_topo_find_link(topo, name, kind_id);
}

pub fn topoObjLaddr(topo: *Topo, obj_id: usize) *anyopaque {
    return tk_topo_obj_laddr(topo, obj_id);
}

pub fn topoTilePtr(topo: *Topo, tile_id: usize) *TopoTile {
    return tk_topo_tile_ptr(topo, tile_id);
}
