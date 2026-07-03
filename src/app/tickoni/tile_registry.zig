/// V1.14.S8.T1: single source of truth for tile id -> behavior. Before this
/// file, tile identity was independently mapped in four places: supervisor's
/// thread-mode spawn (position-indexed), supervisor's snapshotProcessMetrics
/// (string-matched), tile_main's process dispatch (string-matched if/else),
/// and process.zig's counter indices (positionally assumed, unowned).
///
/// This registry follows Firedancer's TILES[] + one-dispatcher pattern: one
/// array of TileEntry, looked up by TileId, that owns a tile's thread-mode
/// run callback, process-mode run callback, and counter schema. Every
/// consumer of tile identity reads from here instead of recreating the
/// mapping.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tiles = @import("tiles");

/// Thread-mode (dev/test) run callback: every Phase 0 tile has one.
pub const RunFn = *const fn (state: *tiles.PaymentPipelineState) void;

/// Process-mode run callback: joins this tile's links from the launch spec
/// and runs its pipeline stage. Not every tile has a process-mode role yet
/// (see TileEntry.process_fn). Takes `io` so a wrapper can read the shared
/// payment-pipeline config file written once by the supervisor (see
/// loadProcessConfig below).
pub const ProcessFn = *const fn (
    io: std.Io,
    wksp: *c_abi.wksp.Wksp,
    spec: *const rt.launch_spec.LaunchSpec,
    cnc: *c_abi.cnc.Cnc,
    allocator: std.mem.Allocator,
) anyerror!void;

/// Named meaning of a cnc app-region counter index, so supervisor.zig's
/// snapshotProcessMetrics can read counters without knowing per-tile which
/// index means what. See tiles/payment_pipeline/process.zig's
/// rt.cnc_counters.appCounterWrite call sites for where each index is
/// written.
pub const CounterField = enum { produced, normalized, invalid, duplicates, allowed, denied, audited };

pub const CounterSchemaEntry = struct { idx: u8, field: CounterField };

pub const TileEntry = struct {
    id: rt.tile.TileId,
    run_fn: RunFn,
    /// Null for tiles with no process-mode pipeline role yet (tkrepl,
    /// tkmetr, tkdiag) — see tiles/payment_pipeline/process.zig's module
    /// doc comment for that scope boundary.
    process_fn: ?ProcessFn = null,
    counters: []const CounterSchemaEntry = &.{},
    /// Expected link cardinality (V1.14.S8 registry responsibility).
    /// V1.14.S8.T2 wires these into real validation: validate(topo) below
    /// fails closed if a topology's actual per-tile channel count for this
    /// id doesn't match.
    in_cnt: u8 = 0,
    out_cnt: u8 = 0,
};

fn id(comptime s: []const u8) rt.tile.TileId {
    return rt.tile.TileId.parse(s) catch unreachable;
}

/// Reads the payment-pipeline test config the supervisor wrote once for
/// the whole run (see supervisor.zig's startPaymentPipelineProcess), from
/// the path convention "<shmem_path>/payment_pipeline.config" — sibling to
/// this tile's own LaunchSpec file, derived from spec.shmemPath() rather
/// than carried as a LaunchSpec field (V1.14.S8.T2 keeps that record
/// payment-pipeline-agnostic).
fn loadProcessConfig(io: std.Io, spec: *const rt.launch_spec.LaunchSpec) !tiles.PaymentPipelineConfig {
    var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/payment_pipeline.config", .{spec.shmemPath()});
    return tiles.process.readProcessConfig(io, std.Io.Dir.cwd(), path);
}

// ---------------------------------------------------------------------------
// Process-mode dispatch wrappers.
//
// Each wrapper owns the link-joining shape for its tile (which of
// input/output it expects) and calls into the pure pipeline-stage logic in
// tiles.process. Moved here from tile_main.zig's if/else dispatch so this
// file is the actual single source of truth, not just a lookup table
// pointing back at scattered per-tile logic.
// ---------------------------------------------------------------------------

fn tkingsProcess(io: std.Io, wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    _ = allocator;
    if (spec.out_cnt != 1) return error.MissingOutputLink;
    var output = try rt.link.Producer.join(wksp, spec.outLinks()[0]);
    defer output.leave();
    const cfg = try loadProcessConfig(io, spec);
    tiles.process.runIngestProcess(cfg, &output, cnc);
}

fn tknormProcess(io: std.Io, wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    _ = allocator;
    if (spec.in_cnt != 1 or spec.out_cnt != 1) return error.MissingLink;
    var input = try rt.link.Consumer.join(wksp, spec.inLinks()[0]);
    defer input.leave();
    var output = try rt.link.Producer.join(wksp, spec.outLinks()[0]);
    defer output.leave();
    const cfg = try loadProcessConfig(io, spec);
    tiles.process.runNormalizeProcess(cfg, &input, &output, cnc);
}

fn tkdeduProcess(io: std.Io, wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    if (spec.in_cnt != 1 or spec.out_cnt != 1) return error.MissingLink;
    var input = try rt.link.Consumer.join(wksp, spec.inLinks()[0]);
    defer input.leave();
    var output = try rt.link.Producer.join(wksp, spec.outLinks()[0]);
    defer output.leave();
    const cfg = try loadProcessConfig(io, spec);
    const cap: usize = @intCast(cfg.event_count);
    const seen_keys = try allocator.alloc(u64, cap);
    defer allocator.free(seen_keys);
    const seen_hashes = try allocator.alloc(u64, cap);
    defer allocator.free(seen_hashes);
    tiles.process.runDedupeProcess(cfg, &input, &output, cnc, seen_keys, seen_hashes);
}

fn tkpolyProcess(io: std.Io, wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    _ = allocator;
    if (spec.in_cnt != 1 or spec.out_cnt != 1) return error.MissingLink;
    var input = try rt.link.Consumer.join(wksp, spec.inLinks()[0]);
    defer input.leave();
    var output = try rt.link.Producer.join(wksp, spec.outLinks()[0]);
    defer output.leave();
    const cfg = try loadProcessConfig(io, spec);
    tiles.process.runPolicyProcess(cfg, &input, &output, cnc);
}

fn tkaudtProcess(io: std.Io, wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    if (spec.in_cnt != 1) return error.MissingInputLink;
    var input = try rt.link.Consumer.join(wksp, spec.inLinks()[0]);
    defer input.leave();
    const cfg = try loadProcessConfig(io, spec);
    const cap: usize = @intCast(cfg.event_count);
    var audit_log = try tiles.audit_sink.AuditLog.init(allocator, cap);
    defer audit_log.deinit(allocator);
    tiles.process.runAuditProcess(cfg, &input, cnc, &audit_log);
}

// ---------------------------------------------------------------------------
// Registry.
// ---------------------------------------------------------------------------

/// Phase 0 tiles, in the order topologies.paymentPipeline() and
/// ProcessPipelineConfig's [8]... arrays assume. Order matters only insofar
/// as callers that spawn by topology index still get the right tile — the
/// spawn/dispatch call sites below look up by id, not by this array's
/// position, so a reordering here is harmless.
pub const entries = [_]TileEntry{
    .{
        .id = id("tkings"),
        .run_fn = tiles.runIngest,
        .process_fn = tkingsProcess,
        .counters = &.{.{ .idx = 0, .field = .produced }},
        .out_cnt = 1,
    },
    .{
        .id = id("tknorm"),
        .run_fn = tiles.runNormalize,
        .process_fn = tknormProcess,
        .counters = &.{ .{ .idx = 0, .field = .normalized }, .{ .idx = 1, .field = .invalid } },
        .in_cnt = 1,
        .out_cnt = 1,
    },
    .{
        .id = id("tkdedu"),
        .run_fn = tiles.runDedupe,
        .process_fn = tkdeduProcess,
        .counters = &.{.{ .idx = 0, .field = .duplicates }},
        .in_cnt = 1,
        .out_cnt = 1,
    },
    .{
        .id = id("tkpoly"),
        .run_fn = tiles.runPolicy,
        .process_fn = tkpolyProcess,
        .counters = &.{ .{ .idx = 0, .field = .allowed }, .{ .idx = 1, .field = .denied } },
        .in_cnt = 1,
        .out_cnt = 1,
    },
    .{
        .id = id("tkaudt"),
        .run_fn = tiles.runAudit,
        .process_fn = tkaudtProcess,
        .counters = &.{.{ .idx = 0, .field = .audited }},
        .in_cnt = 1,
    },
    .{
        .id = id("tkrepl"),
        .run_fn = tiles.runReplay,
    },
    .{
        .id = id("tkmetr"),
        .run_fn = tiles.runMetric,
    },
    .{
        .id = id("tkdiag"),
        .run_fn = tiles.runDiag,
    },
};

pub fn findById(tile_id: rt.tile.TileId) ?*const TileEntry {
    for (&entries) |*e| {
        if (e.id.eql(tile_id)) return e;
    }
    return null;
}

/// Kept for completeness/self-checks; the actual spawn/dispatch call sites
/// use findById so behavior stays correct if a topology ever reorders
/// tiles (see V1.14.S8.T1's acceptance criterion: lookups must be by id,
/// not by position).
pub fn findByIdx(idx: usize) *const TileEntry {
    return &entries[idx];
}

/// Asserts a bijection between topo.tiles and this registry (every
/// topology tile is registered, and every registered tile is present in
/// the topology), and that each topology tile's actual channel cardinality
/// matches its registry entry's expected in_cnt/out_cnt. Called once from
/// Supervisor.init so both thread-mode and process-mode start paths share
/// the check.
pub fn validate(topo: rt.topology.Topology) !void {
    if (topo.tiles.len != entries.len) return error.TopologyTileCountMismatch;
    for (topo.tiles) |t| {
        if (findById(t.id) == null) return error.UnregisteredTopologyTile;
    }
    for (&entries) |*e| {
        var found = false;
        for (topo.tiles) |t| {
            if (t.id.eql(e.id)) {
                found = true;
                break;
            }
        }
        if (!found) return error.RegisteredTileMissingFromTopology;
    }

    for (topo.tiles, 0..) |t, i| {
        const entry = findById(t.id) orelse unreachable; // proven present above
        var in_cnt: u8 = 0;
        var out_cnt: u8 = 0;
        for (topo.channels) |ch| {
            if (ch.dst_idx == i) in_cnt += 1;
            if (ch.src_idx == i) out_cnt += 1;
        }
        if (in_cnt != entry.in_cnt or out_cnt != entry.out_cnt) return error.LinkCardinalityMismatch;
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "registry has exactly the 8 Phase 0 tiles" {
    try std.testing.expectEqual(@as(usize, 8), entries.len);
}

test "findById finds every registered tile" {
    inline for (.{ "tkings", "tknorm", "tkdedu", "tkpoly", "tkaudt", "tkrepl", "tkmetr", "tkdiag" }) |name| {
        const tile_id = try rt.tile.TileId.parse(name);
        try std.testing.expect(findById(tile_id) != null);
    }
}

test "findById returns null for an unregistered id" {
    const unknown = try rt.tile.TileId.parse("tkzzzz");
    try std.testing.expectEqual(@as(?*const TileEntry, null), findById(unknown));
}

test "process_fn is null for tiles with no process-mode role" {
    inline for (.{ "tkrepl", "tkmetr", "tkdiag" }) |name| {
        const tile_id = try rt.tile.TileId.parse(name);
        const entry = findById(tile_id).?;
        try std.testing.expectEqual(@as(?ProcessFn, null), entry.process_fn);
    }
}

test "process_fn is set for the 5 pipeline-stage tiles" {
    inline for (.{ "tkings", "tknorm", "tkdedu", "tkpoly", "tkaudt" }) |name| {
        const tile_id = try rt.tile.TileId.parse(name);
        const entry = findById(tile_id).?;
        try std.testing.expect(entry.process_fn != null);
    }
}

test "counter schema matches known field meanings" {
    const tkings = findById(try rt.tile.TileId.parse("tkings")).?;
    try std.testing.expectEqual(@as(usize, 1), tkings.counters.len);
    try std.testing.expectEqual(CounterField.produced, tkings.counters[0].field);

    const tknorm = findById(try rt.tile.TileId.parse("tknorm")).?;
    try std.testing.expectEqual(@as(usize, 2), tknorm.counters.len);
    try std.testing.expectEqual(CounterField.normalized, tknorm.counters[0].field);
    try std.testing.expectEqual(CounterField.invalid, tknorm.counters[1].field);
}

test "expected link cardinality matches the linear Phase 0 chain" {
    const tkings = findById(try rt.tile.TileId.parse("tkings")).?;
    try std.testing.expectEqual(@as(u8, 0), tkings.in_cnt);
    try std.testing.expectEqual(@as(u8, 1), tkings.out_cnt);

    const tkaudt = findById(try rt.tile.TileId.parse("tkaudt")).?;
    try std.testing.expectEqual(@as(u8, 1), tkaudt.in_cnt);
    try std.testing.expectEqual(@as(u8, 0), tkaudt.out_cnt);

    const tkrepl = findById(try rt.tile.TileId.parse("tkrepl")).?;
    try std.testing.expectEqual(@as(u8, 0), tkrepl.in_cnt);
    try std.testing.expectEqual(@as(u8, 0), tkrepl.out_cnt);
}

fn descriptorsFromRegistry() [8]rt.tile.TileDescriptor {
    var descriptors: [8]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |*e, i| descriptors[i] = .{ .id = e.id, .name = "t" };
    return descriptors;
}

/// Channels matching the real linear Phase 0 chain: tkings(0)->tknorm(1)
/// ->tkdedu(2)->tkpoly(3)->tkaudt(4); tkrepl/tkmetr/tkdiag(5,6,7) have none.
fn channelsFromRegistry() [4]rt.link.Channel {
    return .{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
        .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 128 },
        .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 128 },
    };
}

test "validate accepts a topology matching the registry" {
    var descriptors = descriptorsFromRegistry();
    const channels = channelsFromRegistry();
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channels };
    try validate(topo);
}

test "validate rejects a topology with an unregistered tile" {
    var descriptors = descriptorsFromRegistry();
    descriptors[0].id = try rt.tile.TileId.parse("tkzzzz");
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &.{} };
    try std.testing.expectError(error.UnregisteredTopologyTile, validate(topo));
}

test "validate rejects a topology with the wrong tile count" {
    var descriptors: [7]rt.tile.TileDescriptor = undefined;
    for (entries[0..7], 0..) |e, i| descriptors[i] = .{ .id = e.id, .name = "t" };
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &.{} };
    try std.testing.expectError(error.TopologyTileCountMismatch, validate(topo));
}

test "validate rejects a topology missing a registered tile even at the right count" {
    // Same count (8) as the registry, but tknorm's slot is overwritten
    // with a duplicate of tkings's id, so tknorm is absent from the
    // topology while every present id is still individually registered.
    var descriptors = descriptorsFromRegistry();
    descriptors[1].id = descriptors[0].id;
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &.{} };
    try std.testing.expectError(error.RegisteredTileMissingFromTopology, validate(topo));
}

test "validate rejects a topology whose channel cardinality doesn't match the registry" {
    var descriptors = descriptorsFromRegistry();
    // Drop the tkdedu->tkpoly channel: tkpoly's registry entry expects
    // in_cnt == 1 but the topology now gives it 0.
    const channels = [_]rt.link.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
        .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 128 },
    };
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channels };
    try std.testing.expectError(error.LinkCardinalityMismatch, validate(topo));
}

test "validate rejects unexpected fan-in against a registry entry expecting a single input" {
    var descriptors = descriptorsFromRegistry();
    // Give tkaudt (index 4, in_cnt == 1) a second inbound channel.
    const channels = [_]rt.link.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
        .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 128 },
        .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 128 },
        .{ .src_idx = 1, .dst_idx = 4, .depth = 64, .mtu = 128 },
    };
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channels };
    try std.testing.expectError(error.LinkCardinalityMismatch, validate(topo));
}
