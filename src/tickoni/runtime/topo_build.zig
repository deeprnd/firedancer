/// V1.14.S8.T12: builds a real Firedancer fd_topo_t from Tickoni's own
/// Topology (tiles + channels), driving it through c_abi.topob's fd_topob
/// wrappers. Called identically by the supervisor (parent, to pre-format
/// the shared workspace) and by each self-exec'd tile process (child, to
/// re-derive an identical topology and find its own tile) — see the
/// V1.14.S8.T12 "topology handoff" finding: Tickoni rebuilds the topology
/// in every process rather than serializing fd_topo_t through a handoff
/// file, matching Firedancer's own self-exec convention.
///
/// Does not create the workspace or instantiate any object content —
/// that's the caller's job via c_abi.topob.topoCreateWorkspace/
/// topoWkspNew (parent-only, once). This function only builds the
/// in-memory topology description and calls topobFinish, which computes
/// every object's offset deterministically from the construction order
/// below — the parent and every child must call this with identical
/// inputs to get byte-identical offsets.
const std = @import("std");
const c_abi = @import("c_abi");
const topology = @import("topology.zig");
const cpu_placement = @import("cpu_placement.zig");

const Topo = c_abi.topob.Topo;

/// fd_topo_t's real alignment isn't knowable from Zig (opaque type) but is
/// small in practice (char-array/ulong/union-of-ulongs fields only) — 128
/// is a safe, generous bound matching this codebase's existing Tango
/// alignment convention (e.g. cnc_align). Checked against the real
/// runtime value in build() below; fails closed if Firedancer's actual
/// alignment ever exceeds this.
const topo_alloc_align: std.mem.Alignment = .fromByteUnits(128);

/// ULONG_MAX sentinel Firedancer uses for "no CPU pinned" (see
/// src/disco/topo/fd_topo_run.c's `tile->cpu_idx<65535UL` floating check).
const cpu_idx_floating: usize = std.math.maxInt(usize);

pub const BuiltTopo = struct {
    buf: []align(128) u8,
    topo: *Topo,
    wksp_idx: usize,
    /// Per-tile cnc object id, indexed the same as Topology.tiles.
    cnc_obj_id: []usize,

    pub fn deinit(self: *BuiltTopo, allocator: std.mem.Allocator) void {
        allocator.free(self.cnc_obj_id);
        allocator.free(self.buf);
    }
};

fn toZ(buf: []u8, s: []const u8) [*:0]const u8 {
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return @ptrCast(buf.ptr);
}

fn linkNameZ(buf: []u8, idx: usize) [*:0]const u8 {
    const s = std.fmt.bufPrint(buf[0 .. buf.len - 1], "ch{d}", .{idx}) catch unreachable;
    buf[s.len] = 0;
    return @ptrCast(buf.ptr);
}

fn tileCpuIdx(placement: cpu_placement.CpuPlacement) usize {
    return switch (placement) {
        .exclusive => |cpu| cpu,
        .shared => |cpu| cpu,
        .floating => cpu_idx_floating,
    };
}

pub fn build(
    allocator: std.mem.Allocator,
    topo_desc: topology.Topology,
    app_name: []const u8,
    workspace_name: []const u8,
) !BuiltTopo {
    std.debug.assert(c_abi.topob.topoAlignof() <= topo_alloc_align.toByteUnits());

    const size = c_abi.topob.topoSizeof();
    const buf = try allocator.alignedAlloc(u8, topo_alloc_align, size);
    errdefer allocator.free(buf);

    var app_name_buf: [64]u8 = undefined;
    const topo = c_abi.topob.topobNew(buf.ptr, toZ(&app_name_buf, app_name)) orelse return error.TopobNewFailed;

    var wksp_name_buf: [64]u8 = undefined;
    const wksp_idx = c_abi.topob.topobWksp(topo, toZ(&wksp_name_buf, workspace_name));
    var wksp_name_z_buf: [64]u8 = undefined;
    const wksp_name_z = toZ(&wksp_name_z_buf, workspace_name);

    // Links first, then tiles, then per-tile cnc objects, then wiring —
    // a fixed construction order so object ids stay deterministic across
    // parent/child rebuilds.
    for (topo_desc.channels, 0..) |ch, i| {
        var link_name_buf: [8]u8 = undefined;
        _ = c_abi.topob.topobLink(topo, linkNameZ(&link_name_buf, i), wksp_name_z, ch.depth, ch.mtu, 1);
    }

    for (topo_desc.tiles) |t| {
        var tile_name_buf: [8]u8 = undefined;
        _ = c_abi.topob.topobTile(topo, toZ(&tile_name_buf, t.id.slice()), wksp_name_z, wksp_name_z, tileCpuIdx(t.cpu_placement));
    }

    const cnc_obj_id = try allocator.alloc(usize, topo_desc.tiles.len);
    errdefer allocator.free(cnc_obj_id);
    for (0..topo_desc.tiles.len) |i| {
        const obj_id = c_abi.topob.topobObj(topo, "cnc", wksp_name_z);
        c_abi.topob.topobTileUses(topo, i, obj_id, true);
        cnc_obj_id[i] = obj_id;
    }

    for (topo_desc.channels, 0..) |ch, i| {
        var src_name_buf: [8]u8 = undefined;
        var dst_name_buf: [8]u8 = undefined;
        var link_name_buf: [8]u8 = undefined;
        const src_name_z = toZ(&src_name_buf, topo_desc.tiles[ch.src_idx].id.slice());
        const dst_name_z = toZ(&dst_name_buf, topo_desc.tiles[ch.dst_idx].id.slice());
        const link_name_z = linkNameZ(&link_name_buf, i);
        c_abi.topob.topobTileIn(topo, dst_name_z, 0, wksp_name_z, link_name_z, 0, true, true);
        c_abi.topob.topobTileOut(topo, src_name_z, 0, link_name_z, 0);
    }

    c_abi.topob.topobFinish(topo);

    return .{
        .buf = buf,
        .topo = topo,
        .wksp_idx = wksp_idx,
        .cnc_obj_id = cnc_obj_id,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const tile_mod = @import("tile.zig");
const link_mod = @import("link.zig");

fn testTile(id: []const u8) tile_mod.TileDescriptor {
    return .{ .id = tile_mod.TileId.parse(id) catch unreachable, .name = id };
}

test "build produces a topology for the linear Phase 0 chain" {
    const tiles = [_]tile_mod.TileDescriptor{
        testTile("tkings"),
        testTile("tknorm"),
        testTile("tkdedu"),
        testTile("tkpoly"),
        testTile("tkaudt"),
    };
    const channels = [_]link_mod.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
        .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 128 },
        .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 128 },
    };
    const topo_desc = topology.Topology{ .tiles = &tiles, .channels = &channels };

    var built = try build(std.testing.allocator, topo_desc, "tickoni", "tkpay0");
    defer built.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), built.cnc_obj_id.len);

    var name_buf: [8]u8 = undefined;
    const tkaudt_id = c_abi.topob.topoFindTile(built.topo, toZ(&name_buf, "tkaudt"), 0);
    try std.testing.expect(tkaudt_id != c_abi.topob.not_found);
}
