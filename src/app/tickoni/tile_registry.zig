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
/// (see TileEntry.process_fn).
pub const ProcessFn = *const fn (
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
    /// Link-cardinality metadata (V1.14.S8 registry responsibility).
    /// Not consumed yet — V1.14.S8.T2 replaces LaunchSpec's single
    /// input_link/output_link fields with per-tile link arrays and wires
    /// this into real cardinality validation.
    expects_input: bool = false,
    expects_output: bool = false,
};

fn id(comptime s: []const u8) rt.tile.TileId {
    return rt.tile.TileId.parse(s) catch unreachable;
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

fn tkingsProcess(wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    _ = allocator;
    if (!spec.has_output_link) return error.MissingOutputLink;
    var output = try rt.link.Producer.join(wksp, spec.output_link);
    defer output.leave();
    tiles.process.runIngestProcess(spec, &output, cnc);
}

fn tknormProcess(wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    _ = allocator;
    if (!spec.has_input_link or !spec.has_output_link) return error.MissingLink;
    var input = try rt.link.Consumer.join(wksp, spec.input_link);
    defer input.leave();
    var output = try rt.link.Producer.join(wksp, spec.output_link);
    defer output.leave();
    tiles.process.runNormalizeProcess(spec, &input, &output, cnc);
}

fn tkdeduProcess(wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    if (!spec.has_input_link or !spec.has_output_link) return error.MissingLink;
    var input = try rt.link.Consumer.join(wksp, spec.input_link);
    defer input.leave();
    var output = try rt.link.Producer.join(wksp, spec.output_link);
    defer output.leave();
    const cap: usize = @intCast(spec.event_count);
    const seen_keys = try allocator.alloc(u64, cap);
    defer allocator.free(seen_keys);
    const seen_hashes = try allocator.alloc(u64, cap);
    defer allocator.free(seen_hashes);
    tiles.process.runDedupeProcess(spec, &input, &output, cnc, seen_keys, seen_hashes);
}

fn tkpolyProcess(wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    _ = allocator;
    if (!spec.has_input_link or !spec.has_output_link) return error.MissingLink;
    var input = try rt.link.Consumer.join(wksp, spec.input_link);
    defer input.leave();
    var output = try rt.link.Producer.join(wksp, spec.output_link);
    defer output.leave();
    tiles.process.runPolicyProcess(spec, &input, &output, cnc);
}

fn tkaudtProcess(wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    if (!spec.has_input_link) return error.MissingInputLink;
    var input = try rt.link.Consumer.join(wksp, spec.input_link);
    defer input.leave();
    const cap: usize = @intCast(spec.event_count);
    var audit_log = try tiles.audit_sink.AuditLog.init(allocator, cap);
    defer audit_log.deinit(allocator);
    tiles.process.runAuditProcess(spec, &input, cnc, &audit_log);
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
        .expects_output = true,
    },
    .{
        .id = id("tknorm"),
        .run_fn = tiles.runNormalize,
        .process_fn = tknormProcess,
        .counters = &.{ .{ .idx = 0, .field = .normalized }, .{ .idx = 1, .field = .invalid } },
        .expects_input = true,
        .expects_output = true,
    },
    .{
        .id = id("tkdedu"),
        .run_fn = tiles.runDedupe,
        .process_fn = tkdeduProcess,
        .counters = &.{.{ .idx = 0, .field = .duplicates }},
        .expects_input = true,
        .expects_output = true,
    },
    .{
        .id = id("tkpoly"),
        .run_fn = tiles.runPolicy,
        .process_fn = tkpolyProcess,
        .counters = &.{ .{ .idx = 0, .field = .allowed }, .{ .idx = 1, .field = .denied } },
        .expects_input = true,
        .expects_output = true,
    },
    .{
        .id = id("tkaudt"),
        .run_fn = tiles.runAudit,
        .process_fn = tkaudtProcess,
        .counters = &.{.{ .idx = 0, .field = .audited }},
        .expects_input = true,
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

/// Asserts a bijection between topo.tiles and this registry: every
/// topology tile is registered, and every registered tile is present in
/// the topology. Called once from Supervisor.init so both thread-mode and
/// process-mode start paths share the check.
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

test "validate accepts a topology matching the registry" {
    var descriptors: [8]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |*e, i| descriptors[i] = .{ .id = e.id, .name = "t" };
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &.{} };
    try validate(topo);
}

test "validate rejects a topology with an unregistered tile" {
    var descriptors: [8]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |*e, i| descriptors[i] = .{ .id = e.id, .name = "t" };
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
    var descriptors: [8]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |*e, i| descriptors[i] = .{ .id = e.id, .name = "t" };
    descriptors[1].id = descriptors[0].id;
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &.{} };
    try std.testing.expectError(error.RegisteredTileMissingFromTopology, validate(topo));
}
