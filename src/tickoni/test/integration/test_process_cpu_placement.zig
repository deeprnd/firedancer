/// V1.14.S1 M5 acceptance proof: an explicit shared-core CPU placement
/// (two tiles both declaring `.shared = 0`) starts as two distinct OS
/// processes pinned to the same CPU — proving shared-core placement means
/// shared CPU assignment, not a shared process or address space — and the
/// pipeline still completes correctly. Runs through real
/// startPaymentPipelineProcess/cpu.validate(), not a mock.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const util = @import("util");
const topologies = @import("topologies");

const Supervisor = supervisor_mod.Supervisor;
const TileId = rt.topology.TileId;

/// Same 8 tiles as topologies.paymentPipelineProcess(), except tkings and
/// tknorm both declare an explicit shared placement on CPU 0.
const shared_core_tiles = [_]rt.topology.TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile", .phase = .core, .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile", .phase = .core, .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile", .phase = .core },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile", .phase = .core },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .phase = .core },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile", .phase = .core },
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile", .phase = .core },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile", .phase = .core },
};

test "process_cpu_placement_integration: two tiles sharing one cpu get distinct pids and still complete" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Channels are independent of cpu_placement; reuse the standard
    // process-mode channel shape and only override the tile placements.
    const topo = rt.topology.Topology{
        .tiles = &shared_core_tiles,
        .channels = topologies.paymentPipelineProcess().channels,
    };

    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const report = sup.processPlacementReport().?;
    try std.testing.expectEqual(@as(usize, 2), report.shared_count);
    try std.testing.expectEqual(@as(usize, 6), report.floating_count);
    try std.testing.expect(report.shared_core);

    const tkings_pid = sup.monitor()[0].pid.?;
    const tknorm_pid = sup.monitor()[1].pid.?;
    try std.testing.expect(tkings_pid != tknorm_pid);
    try std.testing.expectEqual(rt.topology.CpuPlacement{ .shared = 0 }, sup.monitor()[0].cpu_placement);
    try std.testing.expectEqual(rt.topology.CpuPlacement{ .shared = 0 }, sup.monitor()[1].cpu_placement);

    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    sup.stopProcess(std.testing.io);

    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
}

test "process_cpu_placement_integration: a malformed (out-of-range) cpu id fails closed before spawning" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const bogus_tiles = [_]rt.topology.TileDescriptor{
        .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile", .phase = .core, .cpu_placement = .{ .exclusive = 65000 } },
        .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile", .phase = .core },
        .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile", .phase = .core },
        .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile", .phase = .core },
        .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .phase = .core },
        .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile", .phase = .core },
        .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile", .phase = .core },
        .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile", .phase = .core },
    };
    const topo = rt.topology.Topology{
        .tiles = &bogus_tiles,
        .channels = topologies.paymentPipelineProcess().channels,
    };

    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try std.testing.expectError(error.CpuIdMalformed, sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    }));

    // Fail-closed means no partial topology: no process was spawned and
    // there is nothing left to stop.
    try std.testing.expect(sup.processPlacementReport() == null);
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expect(h.pid == null);
    }
}
