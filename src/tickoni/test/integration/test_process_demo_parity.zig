/// V1.14.S1 M6 demo/replay parity (T14): CPU placement is a scheduling
/// policy, not a correctness dimension — an all-floating run and an
/// explicit shared-core run of the same deterministic input must reach
/// identical final pipeline metrics through the real supervisor.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");

const Supervisor = supervisor_mod.Supervisor;
const TileId = rt.topology.TileId;

/// Same 8 tiles as rt.topology.paymentPipelineProcess(), except tkpoly and
/// tkaudt both declare an explicit shared placement on CPU 0 — a different
/// pair than test_process_cpu_placement.zig pins, so this test's coverage
/// is not just a duplicate of M5's.
const shared_core_tiles = [_]rt.topology.TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile", .phase = 0 },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile", .phase = 0 },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile", .phase = 0 },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile", .phase = 0, .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .phase = 0, .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile", .phase = 0 },
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile", .phase = 0 },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile", .phase = 0 },
};

const event_count: u64 = 24;

fn runToCompletion(io: std.Io, topo: rt.topology.Topology, run_dir: []const u8) !Supervisor.ProcessMetricSnapshot {
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipelineProcess(io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        c_abi.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    sup.stopProcess(io);

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
    return metrics;
}

test "process_demo_parity: floating and shared-core CPU placement reach identical pipeline metrics" {
    var tmp_floating = std.testing.tmpDir(.{});
    defer tmp_floating.cleanup();
    var floating_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const floating_len = try tmp_floating.dir.realPath(std.testing.io, &floating_path_buf);
    const floating_run_dir = floating_path_buf[0..floating_len];

    const floating_metrics = try runToCompletion(std.testing.io, rt.topology.paymentPipelineProcess(), floating_run_dir);

    var tmp_shared = std.testing.tmpDir(.{});
    defer tmp_shared.cleanup();
    var shared_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const shared_len = try tmp_shared.dir.realPath(std.testing.io, &shared_path_buf);
    const shared_run_dir = shared_path_buf[0..shared_len];

    const shared_topo = rt.topology.Topology{
        .tiles = &shared_core_tiles,
        .channels = rt.topology.paymentPipelineProcess().channels,
    };
    const shared_metrics = try runToCompletion(std.testing.io, shared_topo, shared_run_dir);

    try std.testing.expectEqual(floating_metrics, shared_metrics);
    try std.testing.expectEqual(event_count, floating_metrics.produced);
    try std.testing.expectEqual(event_count, floating_metrics.audited);
}
