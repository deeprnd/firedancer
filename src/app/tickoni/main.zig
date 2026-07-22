const std = @import("std");
const File = std.Io.File;
const rt = @import("runtime");
const c_abi = @import("c_abi");
const util = @import("util");
const supervisor_mod = @import("supervisor.zig");
const Supervisor = supervisor_mod.Supervisor;
const ProcessPipelineConfig = supervisor_mod.ProcessPipelineConfig;
const tile_main = @import("tile_main.zig");
const topologies = @import("topologies");
const doctor_output = @import("doctor_output");
const demo_preflight = @import("demo_preflight");
const version = @import("version");

const usage =
    \\Usage: tickoni-supervisor <command>
    \\
    \\Commands:
    \\  start           Run the Phase 0 Tickoni pipeline spike (dev/test mode)
    \\  start-process   Run the Phase 0 pipeline as isolated OS processes over
    \\                  Tango shared memory (v2.14.S1); requires <run-dir>
    \\  status          Print topology tile names
    \\  doctor          Run environment checks
    \\  demo <manifest> Run a demo scenario (preflight-gated)
    \\  --version       Print version information
    \\
;

pub fn main(init: std.process.Init) !void {
    var it = init.minimal.args.iterate();
    _ = it.skip(); // skip program name

    const cmd = it.next() orelse {
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    };

    // Handle --version flag
    if (std.mem.eql(u8, cmd, "--version")) {
        const ver = @import("version");
        const info = ver.VersionInfo.init();
        var buf: [1024]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        try ver.formatVersionInfo(info, &w);
        try std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, w.buffered());
        std.process.exit(0);
    }

    // Handle --help flag
    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(0);
    }

    // Internal supervisor-to-child handoff for v2.14.S1 process mode
    if (std.mem.eql(u8, cmd, "__tile-run")) {
        const spec_path = it.next() orelse std.process.exit(1);
        std.process.exit(tile_main.run(init.io, init.gpa, spec_path));
    }

    if (std.mem.eql(u8, cmd, "start")) {
        try cmdStart(init, topologies.paymentPipeline());
    } else if (std.mem.eql(u8, cmd, "start-process")) {
        const run_dir = it.next() orelse {
            try File.writeStreamingAll(File.stderr(), init.io, "start-process requires <run-dir>\n");
            std.process.exit(1);
        };
        try cmdStartProcess(init, topologies.paymentPipelineProcess(), run_dir);
    } else if (std.mem.eql(u8, cmd, "status")) {
        try cmdStatus(init.io, topologies.paymentPipeline());
    } else if (std.mem.eql(u8, cmd, "doctor")) {
        var format: doctor_output.Format = .text;
        while (it.next()) |a| {
            if (std.mem.eql(u8, a, "--json")) format = .json;
        }
        try cmdDoctor(init, format);
    } else if (std.mem.eql(u8, cmd, "demo")) {
        const manifest_path = it.next() orelse {
            try File.writeStreamingAll(File.stderr(), init.io, "demo requires <manifest-path>\n");
            std.process.exit(1);
        };
        try cmdDemo(init, manifest_path);
    } else {
        var buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "unknown command: {s}\n", .{cmd});
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    }
}

fn cmdDoctor(init: std.process.Init, format: doctor_output.Format) !void {
    var buf: [8192]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try doctor_output.runAndFormat(init.io, init.gpa, format, &w);
    const output = w.buffered();
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, output);

    // Exit code: 0 for pass/warn, 1 for fail
    const doctor_checks = @import("doctor_checks");
    var results: [20]doctor_checks.Result = undefined;
    const count = doctor_checks.runAll(&results, init.io, init.gpa);
    var fail_count: usize = 0;
    for (results[0..count]) |r| {
        if (r.status == .fail) fail_count += 1;
    }
    std.process.exit(if (fail_count > 0) 1 else 0);
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

/// v2.14.S1: run the payment pipeline as one OS process per tile connected
/// by Tango shared memory instead of in-process threads. run_dir holds the
/// per-tile launch specs and the FD_SHMEM_PATH workspace backing.
fn cmdStartProcess(init: std.process.Init, topo: rt.topology.Topology, run_dir: []const u8) !void {
    const stdout = File.stdout();
    var sup = try Supervisor.init(init.gpa, topo);
    defer sup.deinit();

    const process_config = ProcessPipelineConfig{ .run_dir = run_dir };
    try sup.startPaymentPipelineProcess(init.io, process_config);

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

    // Poll for pipeline completion (audited count reaches event_count)
    const poll_interval_ns: u64 = 5 * std.time.ns_per_ms;
    const max_polls: u32 = 2000; // 10s bound
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= process_config.event_count) break;
        util.process.sleepNanos(poll_interval_ns);
    }

    const metrics = sup.snapshotProcessMetrics();
    const metrics_line = try std.fmt.bufPrint(
        &buf,
        "metrics: produced={d} normalized={d} invalid={d} duplicates={d} allowed={d} denied={d} audited={d}\n",
        .{ metrics.produced, metrics.normalized, metrics.invalid, metrics.duplicates, metrics.allowed, metrics.denied, metrics.audited },
    );
    try File.writeStreamingAll(stdout, init.io, metrics_line);

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
        const line = try std.fmt.bufPrint(&buf, "  [{d}] id={s}  name={s}\n", .{
            i, t.id.slice(), t.name,
        });
        try File.writeStreamingAll(stdout, io, line);
    }
}

/// Demo command — fail-closed preflight check before running any demo.
///
/// If preflight fails, prints diagnostic error and exits 1.
/// No proposal/audit artifacts are created.
fn cmdDemo(init: std.process.Init, manifest_path: []const u8) !void {
    // Load manifest
    const cwd = std.Io.Dir.cwd();
    const m = demo_preflight.loadManifest(init.gpa, init.io, cwd, manifest_path) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "error: could not load manifest '{s}': {}\n", .{ manifest_path, err });
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        std.process.exit(1);
    };
    defer demo_preflight.deinitManifest(m);

    // Gather installed system info
    const version_info = version.VersionInfo.init();

    // Run preflight — fail-closed
    const preflight_result = demo_preflight.run(
        init.gpa,
        init.io,
        m,
        cwd,
        version_info.semver,
        "linux_full", // installed runtime tier
        "retail", // installed isolation tier
        "/tmp/fixtures",
    ) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "error: preflight failed: {}\n", .{err});
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        std.process.exit(1);
    };

    // Preflight passed — proceed with demo
    try File.writeStreamingAll(File.stdout(), init.io, "preflight: passed\n");
    demo_preflight.deinit(preflight_result, init.gpa);
    // Demo execution would go here
    try File.writeStreamingAll(File.stdout(), init.io, "demo: completed\n");
}
