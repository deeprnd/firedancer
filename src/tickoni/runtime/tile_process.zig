/// Generic single-tile process-mode lifecycle, reusable across any Tickoni
/// process-mode tile regardless of which pipeline it belongs to. Mirrors
/// Firedancer's fd_topo_run_tile (src/disco/topo/fd_topo_run.c): a single
/// spawned process's own boot/attach/run/halt mechanics, with the
/// tile-specific work as a caller-supplied step — not the parent-side
/// orchestration loop that spawns and tracks every tile (that stays in
/// src/app/tickoni/supervisor.zig, matching Firedancer's own
/// src/app/shared/commands/run/run.c).
///
/// Lifecycle: read the launch spec -> attach the shared workspace -> join
/// the pre-formatted cnc -> signal RUN -> run `work` -> heartbeat until the
/// supervisor signals HALT via the cnc (fd_cnc's own command/control model,
/// not a POSIX signal) -> signal BOOT and return 0. The
/// crash_after_heartbeats test hook returns 1 without any clean
/// transition, simulating an unexpected crash for V1.14.S1.T12
/// sibling-isolation tests.
const std = @import("std");
const c_abi = @import("c_abi");
const util = @import("util");
const launch_spec = @import("launch_spec.zig");
const boot = @import("boot.zig");

pub const WorkFn = *const fn (
    io: std.Io,
    wksp: *c_abi.wksp.Wksp,
    spec: *const launch_spec.LaunchSpec,
    cnc: *c_abi.cnc.Cnc,
    allocator: std.mem.Allocator,
) anyerror!void;

/// Runs one process-mode tile to completion. `work` performs the caller's
/// tile-specific behavior (which links to join, which decision logic to
/// run) after this tile has joined its cnc and signalled RUN, and before
/// the heartbeat/halt-wait loop. Returns 1 (with a diagnostic on stderr)
/// on any failure; 0 on a clean RUN -> HALT -> BOOT transition.
pub fn run(io: std.Io, allocator: std.mem.Allocator, spec_path: []const u8, work: WorkFn) u8 {
    const spec = launch_spec.LaunchSpec.readFromFile(io, std.Io.Dir.cwd(), spec_path) catch |err| {
        std.debug.print("tile_process: failed to read launch spec {s}: {t}\n", .{ spec_path, err });
        return 1;
    };

    boot.bootWithSyntheticArgv(spec.shmemPath()) catch |err| {
        std.debug.print("tile_process: bootWithSyntheticArgv failed for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    defer c_abi.boot.halt();

    var workspace_name_buf: [64]u8 = undefined;
    const workspace_name_z = std.fmt.bufPrintZ(&workspace_name_buf, "{s}", .{spec.workspace_name.slice()}) catch {
        std.debug.print("tile_process: workspace name too long for tile {d}\n", .{spec.tile_idx});
        return 1;
    };

    const wksp = c_abi.wksp.wkspAttach(workspace_name_z) orelse {
        std.debug.print("tile_process: fd_wksp_attach failed for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    defer _ = c_abi.wksp.wkspDetach(wksp);

    const laddr = c_abi.wksp.wkspLaddr(wksp, spec.cnc_gaddr) orelse {
        std.debug.print("tile_process: fd_wksp_laddr failed for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    const cnc = c_abi.cnc.cncJoin(laddr) orelse {
        std.debug.print("tile_process: fd_cnc_join failed for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    defer _ = c_abi.cnc.cncLeave(cnc);

    c_abi.cnc.heartbeat(cnc, util.process.monotonicNanos());
    // Unconditional BOOT->RUN transition: if the supervisor's stopProcess
    // writes HALT to this cnc before this line runs (a tile caught mid-boot),
    // this write silently clobbers it back to RUN and the halt request is
    // lost — this tile then blocks forever waiting on an upstream tile that
    // already honored the same halt and stopped producing. Callers must not
    // request a stop before every tile has demonstrably reached RUN (see
    // startPaymentPipelineProcess's callers, which poll for real pipeline
    // progress before calling stopProcess).
    c_abi.cnc.signal(cnc, c_abi.cnc.signal_run);

    work(io, wksp, &spec, cnc, allocator) catch |err| {
        std.debug.print("tile_process: work failed for tile {d} ({s}): {t}\n", .{ spec.tile_idx, spec.tile_id.slice(), err });
        return 1;
    };

    var heartbeats: u32 = 0;
    while (true) {
        const sig = c_abi.cnc.signalQuery(cnc);
        if (sig == c_abi.cnc.signal_halt) break;

        heartbeats += 1;
        if (spec.crash_after_heartbeats > 0 and heartbeats >= spec.crash_after_heartbeats) {
            // Test-only crash-isolation hook (V1.14.S1.T12): exit without a
            // clean cnc transition, simulating an unexpected tile failure.
            return 1;
        }

        util.process.sleepNanos(spec.heartbeat_interval_ns);
        c_abi.cnc.heartbeat(cnc, util.process.monotonicNanos());
    }

    c_abi.cnc.signal(cnc, c_abi.cnc.signal_boot);
    return 0;
}
