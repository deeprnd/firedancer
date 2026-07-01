/// Entrypoint for the internal `__tile-run <spec-file>` subcommand that
/// src/app/tickoni/supervisor.zig's startPaymentPipelineProcess self-execs
/// into for every V1.14.S1 process-mode tile. Not part of the advertised
/// CLI surface (see main.zig's usage text) — this is a supervisor-to-child
/// handoff, matching the Firedancer convention of one binary re-exec'd per
/// tile rather than a family of small per-tile binaries.
///
/// Lifecycle: read the launch spec -> attach the shared workspace -> join
/// the pre-formatted cnc -> signal RUN -> heartbeat until the supervisor
/// signals HALT via the cnc (fd_cnc's own command/control model, not a
/// POSIX signal) -> signal BOOT and exit 0. The crash_after_heartbeats
/// test hook exits(1) without any clean transition, simulating an
/// unexpected crash for V1.14.S1.T12 sibling-isolation tests.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tiles = @import("tiles");
const process_stage = @import("process_stage.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, spec_path: []const u8) u8 {
    const spec = rt.launch_spec.LaunchSpec.readFromFile(io, std.Io.Dir.cwd(), spec_path) catch |err| {
        std.debug.print("tile_main: failed to read launch spec {s}: {t}\n", .{ spec_path, err });
        return 1;
    };

    c_abi.boot.bootWithSyntheticArgv(spec.shmemPath()) catch |err| {
        std.debug.print("tile_main: bootWithSyntheticArgv failed for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    defer c_abi.boot.fd_halt();

    var workspace_name_buf: [64]u8 = undefined;
    const workspace_name_z = std.fmt.bufPrintZ(&workspace_name_buf, "{s}", .{spec.workspace_name.slice()}) catch {
        std.debug.print("tile_main: workspace name too long for tile {d}\n", .{spec.tile_idx});
        return 1;
    };

    const wksp = c_abi.wksp.fd_wksp_attach(workspace_name_z) orelse {
        std.debug.print("tile_main: fd_wksp_attach failed for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    defer _ = c_abi.wksp.fd_wksp_detach(wksp);

    const laddr = c_abi.wksp.fd_wksp_laddr(wksp, spec.cnc_gaddr) orelse {
        std.debug.print("tile_main: fd_wksp_laddr failed for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    const cnc = c_abi.cnc.fd_cnc_join(laddr) orelse {
        std.debug.print("tile_main: fd_cnc_join failed for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    defer _ = c_abi.cnc.fd_cnc_leave(cnc);

    c_abi.cnc.heartbeat(cnc, c_abi.process.monotonicNanos());
    c_abi.cnc.signal(cnc, c_abi.cnc.signal_run);

    runPipelineStage(wksp, &spec, cnc, allocator) catch |err| {
        std.debug.print("tile_main: pipeline stage failed for tile {d} ({s}): {t}\n", .{ spec.tile_idx, spec.tile_id.slice(), err });
        return 1;
    };

    var heartbeats: u32 = 0;
    while (true) {
        if (c_abi.cnc.signalQuery(cnc) == c_abi.cnc.signal_halt) break;

        heartbeats += 1;
        if (spec.crash_after_heartbeats > 0 and heartbeats >= spec.crash_after_heartbeats) {
            // Test-only crash-isolation hook (V1.14.S1.T12): exit without a
            // clean cnc transition, simulating an unexpected tile failure.
            return 1;
        }

        c_abi.process.sleepNanos(spec.heartbeat_interval_ns);
        c_abi.cnc.heartbeat(cnc, c_abi.process.monotonicNanos());
    }

    c_abi.cnc.signal(cnc, c_abi.cnc.signal_boot);
    return 0;
}

/// Dispatches the deterministic payment pipeline stage for this tile's
/// role and runs it to completion (bounded by spec.event_count). Runs
/// before the heartbeat/halt-wait loop above so the supervisor's stop
/// sequence (signal every cnc to halt, wait for exit) stays uniform
/// whether or not a tile has pipeline work.
///
/// tkrepl/tkmetr/tkdiag have no process-mode pipeline role yet — see the
/// module doc comment in process_stage.zig for the scope boundary.
fn runPipelineStage(wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) !void {
    const id = spec.tile_id.slice();

    if (std.mem.eql(u8, id, "tkings")) {
        if (!spec.has_output_link) return error.MissingOutputLink;
        var output = try rt.shm_link.Producer.join(wksp, spec.output_link);
        defer output.leave();
        process_stage.runIngestProcess(spec, &output, cnc);
    } else if (std.mem.eql(u8, id, "tknorm")) {
        if (!spec.has_input_link or !spec.has_output_link) return error.MissingLink;
        var input = try rt.shm_link.Consumer.join(wksp, spec.input_link);
        defer input.leave();
        var output = try rt.shm_link.Producer.join(wksp, spec.output_link);
        defer output.leave();
        process_stage.runNormalizeProcess(spec, &input, &output, cnc);
    } else if (std.mem.eql(u8, id, "tkdedu")) {
        if (!spec.has_input_link or !spec.has_output_link) return error.MissingLink;
        var input = try rt.shm_link.Consumer.join(wksp, spec.input_link);
        defer input.leave();
        var output = try rt.shm_link.Producer.join(wksp, spec.output_link);
        defer output.leave();
        const cap: usize = @intCast(spec.event_count);
        const seen_keys = try allocator.alloc(u64, cap);
        defer allocator.free(seen_keys);
        const seen_hashes = try allocator.alloc(u64, cap);
        defer allocator.free(seen_hashes);
        process_stage.runDedupeProcess(spec, &input, &output, cnc, seen_keys, seen_hashes);
    } else if (std.mem.eql(u8, id, "tkpoly")) {
        if (!spec.has_input_link or !spec.has_output_link) return error.MissingLink;
        var input = try rt.shm_link.Consumer.join(wksp, spec.input_link);
        defer input.leave();
        var output = try rt.shm_link.Producer.join(wksp, spec.output_link);
        defer output.leave();
        process_stage.runPolicyProcess(spec, &input, &output, cnc);
    } else if (std.mem.eql(u8, id, "tkaudt")) {
        if (!spec.has_input_link) return error.MissingInputLink;
        var input = try rt.shm_link.Consumer.join(wksp, spec.input_link);
        defer input.leave();
        const cap: usize = @intCast(spec.event_count);
        var audit_log = try tiles.audit_sink.AuditLog.init(allocator, cap);
        defer audit_log.deinit(allocator);
        process_stage.runAuditProcess(spec, &input, cnc, &audit_log);
    }
}
