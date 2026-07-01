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

pub fn run(io: std.Io, spec_path: []const u8) u8 {
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
