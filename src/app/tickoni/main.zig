const std = @import("std");
const File = std.Io.File;
const rt = @import("runtime");
const c_abi = @import("c_abi");
const Supervisor = @import("supervisor.zig").Supervisor;
const tile_main = @import("tile_main.zig");

const usage =
    \\Usage: tickoni-supervisor <command>
    \\
    \\Commands:
    \\  start           Run the Phase 0 Tickoni pipeline spike (dev/test mode)
    \\  start-process   Run the Phase 0 pipeline as isolated OS processes over
    \\                  Tango shared memory (V1.14.S1); requires <run-dir>
    \\  status          Print topology tile names
    \\
;

pub fn main(init: std.process.Init) !void {
    var it = init.minimal.args.iterate();
    _ = it.skip(); // skip program name

    const cmd = it.next() orelse {
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    };

    // Internal supervisor-to-child handoff for V1.14.S1 process mode, not
    // part of the advertised command surface: `__tile-run <spec-file>`.
    if (std.mem.eql(u8, cmd, "__tile-run")) {
        const spec_path = it.next() orelse std.process.exit(1);
        std.process.exit(tile_main.run(init.io, spec_path));
    }

    if (std.mem.eql(u8, cmd, "start")) {
        try cmdStart(init, rt.topology.paymentPipeline());
    } else if (std.mem.eql(u8, cmd, "start-process")) {
        const run_dir = it.next() orelse {
            try File.writeStreamingAll(File.stderr(), init.io, "start-process requires <run-dir>\n");
            std.process.exit(1);
        };
        try cmdStartProcess(init, rt.topology.paymentPipelineProcess(), run_dir);
    } else if (std.mem.eql(u8, cmd, "status")) {
        try cmdStatus(init.io, rt.topology.paymentPipeline());
    } else {
        var buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "unknown command: {s}\n", .{cmd});
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    }
}

fn cmdStart(init: std.process.Init, topo: rt.topology.Topology) !void {
    const stdout = File.stdout();
    var sup = try Supervisor.init(init.gpa, topo);
    defer sup.deinit();

    try sup.startPaymentPipeline(.{ .event_count = 10_000, .queue_depth = 64 });
    sup.wait();

    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: Phase 0 pipeline completed\ntiles:\n");

    var buf: [256]u8 = undefined;
    for (sup.monitor()) |h| {
        const line = try std.fmt.bufPrint(&buf, "  [{d}] {s}  state={s}\n", .{
            h.tile_idx,
            topo.tiles[h.tile_idx].name,
            @tagName(h.state),
        });
        try File.writeStreamingAll(stdout, init.io, line);
    }

    if (sup.pipeline) |state| {
        const metrics = state.snapshotMetrics();
        const diag = state.snapshotDiag();
        const metrics_line = try std.fmt.bufPrint(
            &buf,
            "metrics: produced={d} audited={d} duplicates={d} denied={d} backpressure_waits={d} max_queue_depth={d} max_latency_hops={d}\n",
            .{
                metrics.produced,
                metrics.audited,
                metrics.duplicates,
                metrics.denied,
                metrics.backpressure_waits,
                metrics.max_queue_depth,
                metrics.max_latency_hops,
            },
        );
        try File.writeStreamingAll(stdout, init.io, metrics_line);

        const diag_line = try std.fmt.bufPrint(
            &buf,
            "diag: sandbox_failures={d} replay_checked={s} replay_match={s}\n",
            .{
                diag.sandbox_failures,
                if (diag.replay_checked) "true" else "false",
                if (diag.replay_match) "true" else "false",
            },
        );
        try File.writeStreamingAll(stdout, init.io, diag_line);
    }

    sup.stop();
    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: stopped\n");
}

/// V1.14.S1: run the payment pipeline as one OS process per tile connected
/// by Tango shared memory instead of in-process threads. run_dir holds the
/// per-tile launch specs and the FD_SHMEM_PATH workspace backing.
fn cmdStartProcess(init: std.process.Init, topo: rt.topology.Topology, run_dir: []const u8) !void {
    const stdout = File.stdout();
    var sup = try Supervisor.init(init.gpa, topo);
    defer sup.deinit();

    try sup.startPaymentPipelineProcess(init.io, .{ .run_dir = run_dir });

    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: process-mode pipeline started\ntiles:\n");
    var buf: [256]u8 = undefined;
    for (sup.monitor()) |h| {
        const line = try std.fmt.bufPrint(&buf, "  [{d}] {s}  pid={?d}  state={s}\n", .{
            h.tile_idx,
            topo.tiles[h.tile_idx].name,
            h.pid,
            @tagName(h.state),
        });
        try File.writeStreamingAll(stdout, init.io, line);
    }

    // Brief window for manual process-isolation verification (e.g. `ps
    // --ppid <supervisor-pid>`) before requesting a clean shutdown.
    c_abi.process.sleepNanos(2 * std.time.ns_per_s);

    sup.stopProcess(init.io);
    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: process-mode pipeline stopped\n");
}

fn cmdStatus(io: std.Io, topo: rt.topology.Topology) !void {
    const stdout = File.stdout();
    var buf: [256]u8 = undefined;

    const header = try std.fmt.bufPrint(&buf, "topology: {d} tiles, {d} channels\n", .{
        topo.tiles.len, topo.channels.len,
    });
    try File.writeStreamingAll(stdout, io, header);

    for (topo.tiles, 0..) |t, i| {
        const line = try std.fmt.bufPrint(&buf, "  [{d}] id={s}  name={s}  phase={d}\n", .{
            i, t.id.slice(), t.name, t.phase,
        });
        try File.writeStreamingAll(stdout, io, line);
    }
}
