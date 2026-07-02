/// V1.14.S1 M6 acceptance proof: process isolation (T13) and crash
/// isolation (T12) through the real supervisor — real child processes,
/// real /proc introspection, a real SIGKILL. Also covers the process-mode
/// fail-closed configuration checks that don't need real shared memory to
/// exercise (heap_dev-backed channel, missing workspace name).
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");

const Supervisor = supervisor_mod.Supervisor;
const TileId = rt.topology.TileId;

/// readFileAlloc-style helpers size their buffer from fstat, which
/// reports 0 for /proc pseudo-files and hangs waiting for a size that
/// never arrives. Read positionally into a fixed buffer instead — pread
/// against /proc/<pid>/status returns 0 (real EOF) once its actual
/// (non-zero) content is exhausted, same as any other file.
fn parentPidOf(io: std.Io, pid: std.process.Child.Id) !c_int {
    var path_buf: [64]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/proc/{d}/status", .{pid});
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    const n = try file.readPositionalAll(io, &buf, 0);
    const contents = buf[0..n];

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "PPid:")) {
            const value = std.mem.trim(u8, line["PPid:".len..], " \t");
            return std.fmt.parseInt(c_int, value, 10);
        }
    }
    return error.PPidNotFound;
}

test "process_topology_integration: every tile is a distinct OS process parented by the supervisor" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = rt.topology.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 8;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const supervisor_pid = c_abi.sandbox.getpid();

    // Every tile has a distinct pid, and every pid's own /proc/<pid>/status
    // reports this test process (the "supervisor") as its parent.
    var seen_pids: [8]std.process.Child.Id = undefined;
    for (sup.monitor(), 0..) |h, i| {
        const pid = h.pid orelse return error.MissingPid;
        for (seen_pids[0..i]) |other| try std.testing.expect(other != pid);
        seen_pids[i] = pid;

        const ppid = try parentPidOf(std.testing.io, pid);
        try std.testing.expectEqual(supervisor_pid, ppid);
    }

    // Wait for the pipeline to actually reach real completion before
    // requesting a stop. stopProcess()'s halt signal races a still-booting
    // tile's own boot->run cnc transition (tile_main.zig signals RUN
    // unconditionally on boot, clobbering an earlier HALT write) — a tile
    // caught mid-boot would silently ignore the halt and then block forever
    // waiting on an upstream tile that already exited. Same poll-until-real
    // completion pattern as test_process_pipeline.zig/test_process_cpu_placement.zig.
    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        rt.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    try std.testing.expectEqual(event_count, sup.snapshotProcessMetrics().audited);

    sup.stopProcess(std.testing.io);
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "process_topology_integration: SIGKILL on one tile is reported by identity without corrupting siblings" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = rt.topology.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    // tkrepl (index 5) has no pipeline role (see process_stage.zig's scope
    // doc comment) — it is purely an observer heartbeating in its idle
    // loop, so killing it cannot itself corrupt the tkings..tkaudt
    // pipeline that is running concurrently in sibling processes.
    const tkrepl_idx = 5;
    try std.testing.expectEqualStrings("tkrepl", topo.tiles[tkrepl_idx].id.slice());
    const tkrepl_pid = sup.monitor()[tkrepl_idx].pid orelse return error.MissingPid;

    const linux = std.os.linux;
    _ = linux.kill(tkrepl_pid, linux.SIG.KILL);

    // Poll for the pipeline's real completion signal on the surviving
    // tiles while tkrepl's death is reaped in the background by
    // waitProcess below.
    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        rt.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    const metrics = sup.snapshotProcessMetrics();

    sup.stopProcess(std.testing.io);

    // The killed tile is reported crashed, by identity, via signal —
    // not folded into an unrelated tile's state.
    try std.testing.expectEqual(rt.tile.TileState.crashed, sup.monitor()[tkrepl_idx].state);
    try std.testing.expectEqual(rt.tile.CrashReason.signal, sup.monitor()[tkrepl_idx].crashed_because);

    // Every other tile — including tkmetr/tkdiag, tkrepl's siblings, and
    // the whole tkings..tkaudt pipeline — still shut down cleanly, and
    // the pipeline's own state was not corrupted by tkrepl's death.
    for (sup.monitor(), 0..) |h, i| {
        if (i == tkrepl_idx) continue;
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);
}

test "process_topology_integration: process mode refuses to start a heap_dev-backed channel" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Same shape as paymentPipelineProcess() but the first channel is left
    // at its heap_dev default instead of being declared tango_shm.
    const base = rt.topology.paymentPipelineProcess();
    var channels: [4]rt.topology.Channel = undefined;
    @memcpy(&channels, base.channels[0..4]);
    channels[0].backing = .heap_dev;
    const topo = rt.topology.Topology{ .tiles = base.tiles, .channels = &channels };

    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try std.testing.expectError(error.ProcessModeRequiresTangoShm, sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    }));
    for (sup.monitor()) |h| try std.testing.expect(h.pid == null);
}

test "process_topology_integration: process mode refuses to start with a missing workspace name" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const base = rt.topology.paymentPipelineProcess();
    var channels: [4]rt.topology.Channel = undefined;
    @memcpy(&channels, base.channels[0..4]);
    channels[0].workspace_name = .{};
    const topo = rt.topology.Topology{ .tiles = base.tiles, .channels = &channels };

    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try std.testing.expectError(error.ChannelWorkspaceNameMissing, sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    }));
    for (sup.monitor()) |h| try std.testing.expect(h.pid == null);
}
