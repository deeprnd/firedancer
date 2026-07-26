/// Linux-strict CPU placement proof: shared-core declarations must create
/// observable contention relative to a non-shared baseline on a host with real
/// sched_*affinity semantics.
const std = @import("std");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const util = @import("util");
const topologies = @import("topologies");

const Supervisor = supervisor_mod.Supervisor;
const TileId = rt.topology.TileId;

const shared_core_tiles = [_]rt.topology.TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile" },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile" },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile" },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile" },
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile" },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile" },
};

const event_count: u64 = 32;
const samples: usize = 3;

fn runDurationNs(io: std.Io, topo: rt.topology.Topology, run_dir: []const u8) !u64 {
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const start_ns = util.process.monotonicNanos();
    try sup.startPaymentPipelineProcess(io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 1200;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    const elapsed_ns = std.math.cast(u64, util.process.monotonicNanos() - start_ns) orelse return error.DurationOverflow;
    sup.stopProcess(io);

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);

    return elapsed_ns;
}

fn median3(values: [samples]u64) u64 {
    var copy = values;
    std.sort.pdq(u64, &copy, {}, std.sort.asc(u64));
    return copy[1];
}

test "process_cpu_placement_linux: shared-core contention is slower than a floating baseline" {
    var floating_runs: [samples]u64 = undefined;
    inline for (0..samples) |i| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const len = try tmp.dir.realPath(std.testing.io, &path_buf);
        floating_runs[i] = try runDurationNs(std.testing.io, topologies.paymentPipelineProcess(), path_buf[0..len]);
    }

    const shared_topo = rt.topology.Topology{
        .tiles = &shared_core_tiles,
        .channels = topologies.paymentPipelineProcess().channels,
    };
    var shared_runs: [samples]u64 = undefined;
    inline for (0..samples) |i| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const len = try tmp.dir.realPath(std.testing.io, &path_buf);
        shared_runs[i] = try runDurationNs(std.testing.io, shared_topo, path_buf[0..len]);
    }

    const floating_median = median3(floating_runs);
    const shared_median = median3(shared_runs);

    try std.testing.expect(shared_median >= floating_median);
}
