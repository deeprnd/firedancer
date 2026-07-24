/// v2.14.S1 M6 acceptance proof: process isolation (T13) and crash
/// isolation (T12) through the real supervisor — real child processes,
/// real /proc introspection, a real SIGKILL. Also covers the process-mode
/// fail-closed configuration checks that don't need real shared memory to
/// exercise (heap_dev-backed channel, missing workspace name).
const std = @import("std");
const c_abi = @import("c_abi");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;
const TileId = rt.topology.TileId;

/// Get parent PID of a process — cross-platform via os.c shim.
/// Linux: /proc/<pid>/status
/// macOS: sysctl(KERN_PROC, KERN_PROC_PID, pid) → kinfo_proc
fn parentPidOf(pid: std.process.Child.Id) !c_int {
    return util.os_api.parentPid(pid);
}

test "process_topology_integration: every tile is a distinct OS process parented by the supervisor" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
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

        const ppid = try parentPidOf(pid);
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
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    try std.testing.expectEqual(event_count, sup.snapshotProcessMetrics().audited);

    sup.stopProcess(std.testing.io);
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "process_topology_integration: supervisor marks a truly stuck tile stale while blocked consumers keep heartbeating" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = 16,
        .heartbeat_interval_ns = 10 * std.time.ns_per_ms,
        .heartbeat_stale_after_ns = 60 * std.time.ns_per_ms,
        .stuck_tile_idx = 0,
        .stuck_after_messages = 0,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 200;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[0].state == rt.tile.TileState.stale) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    try std.testing.expectEqual(rt.tile.TileState.stale, sup.monitor()[0].state);
    try std.testing.expectEqual(rt.tile.CrashReason.stale, sup.monitor()[0].crashed_because);
    try std.testing.expect(sup.monitor()[0].isAlive());

    // tknorm..tkaudt are all blocked in consume() waiting on tkings, so this
    // proves the T6 work-loop heartbeat move: blocked consumers stay healthy
    // enough to avoid stale classification while their upstream tile is
    // intentionally frozen.
    for (sup.monitor(), 0..) |h, i| {
        if (i == 0) continue;
        try std.testing.expect(h.state != rt.tile.TileState.stale);
    }

    sup.stopProcess(std.testing.io);
    try std.testing.expectEqual(rt.tile.TileState.stale, sup.monitor()[0].state);
    try std.testing.expectEqual(rt.tile.CrashReason.stale, sup.monitor()[0].crashed_because);
    for (sup.monitor(), 0..) |h, i| {
        if (i == 0) continue;
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "process_topology_integration: SIGKILL on one tile is reported by identity without corrupting siblings" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    // tkrepl (index 5) has no pipeline role (see
    // tiles/payment_pipeline/process.zig's scope doc comment) — it is
    // purely an observer heartbeating in its idle
    // loop, so killing it cannot itself corrupt the tkings..tkaudt
    // pipeline that is running concurrently in sibling processes.
    const tkrepl_idx = 5;
    try std.testing.expectEqualStrings("tkrepl", topo.tiles[tkrepl_idx].id.slice());
    const tkrepl_pid = sup.monitor()[tkrepl_idx].pid orelse return error.MissingPid;

    _ = std.posix.kill(tkrepl_pid, std.posix.SIG.KILL) catch {};

    // Poll for the pipeline's real completion signal on the surviving
    // tiles while tkrepl's death is reaped in the background by
    // waitProcess below.
    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
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

test "process_topology_integration: a self-exiting tile is reported crashed via exit_code, not signal" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    // tkrepl (index 5) only heartbeats in its idle loop (see the SIGKILL
    // test above), so crashing it via the crash_after_heartbeats test hook
    // (runtime/tile_process.zig: exit(1) without a clean cnc transition)
    // cannot itself corrupt the tkings..tkaudt pipeline running in sibling
    // processes. Crash on the first heartbeat so the self-exit happens
    // immediately after RUN, well before this test's own poll loop below
    // could observe pipeline completion and call stopProcess() — avoiding a
    // race against a HALT arriving before tkrepl reaches its crash check.
    const tkrepl_idx = 5;
    var crash_after_heartbeats = [_]u32{0} ** 8;
    crash_after_heartbeats[tkrepl_idx] = 1;

    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .crash_after_heartbeats = crash_after_heartbeats,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });
    try std.testing.expectEqualStrings("tkrepl", topo.tiles[tkrepl_idx].id.slice());

    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    const metrics = sup.snapshotProcessMetrics();

    sup.stopProcess(std.testing.io);

    try std.testing.expectEqual(rt.tile.TileState.crashed, sup.monitor()[tkrepl_idx].state);
    try std.testing.expectEqual(rt.tile.CrashReason.exit_code, sup.monitor()[tkrepl_idx].crashed_because);
    try std.testing.expectEqual(@as(u8, 1), sup.monitor()[tkrepl_idx].exit_code);

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
    const base = topologies.paymentPipelineProcess();
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
    const base = topologies.paymentPipelineProcess();
    var channels: [4]rt.topology.Channel = undefined;
    @memcpy(&channels, base.channels[0..4]);
    channels[0].workspace_name = .{};
    const topo = rt.topology.Topology{ .tiles = base.tiles, .channels = &channels };

    // Supervisor.init() now runs topo.validate()'s structural checks (see
    // Supervisor.init()'s doc comment), so a missing workspace name on a
    // tango_shm channel fails closed here rather than needing a tile to
    // reach startPaymentPipelineProcess first.
    try std.testing.expectError(error.ChannelWorkspaceNameMissing, Supervisor.init(std.testing.allocator, topo));
}
