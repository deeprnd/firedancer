/// Entrypoint for the internal `__tile-run <spec-file>` subcommand that
/// src/app/tickoni/supervisor.zig's startPaymentPipelineProcess self-execs
/// into for every V1.14.S1 process-mode tile. Not part of the advertised
/// CLI surface (see main.zig's usage text) — this is a supervisor-to-child
/// handoff, matching the Firedancer convention of one binary re-exec'd per
/// tile rather than a family of small per-tile binaries.
///
/// The generic single-tile boot/heartbeat/halt lifecycle lives in
/// src/tickoni/runtime/tile_process.zig; this file only looks up this
/// tile's process-mode callback in tile_registry.zig (V1.14.S8.T1's single
/// source of truth for tile id -> behavior) and runs it.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tile_registry = @import("tile_registry.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, spec_path: []const u8) u8 {
    return rt.tile_process.run(io, allocator, spec_path, runPipelineStage);
}

/// Dispatches the deterministic payment pipeline stage for this tile's
/// role and runs it to completion (bounded by spec.event_count). Runs
/// before the heartbeat/halt-wait loop above so the supervisor's stop
/// sequence (signal every cnc to halt, wait for exit) stays uniform
/// whether or not a tile has pipeline work.
///
/// tkrepl/tkmetr/tkdiag have no process-mode pipeline role yet — see the
/// module doc comment in tiles/payment_pipeline/process.zig for the scope
/// boundary; their tile_registry entry has process_fn == null and is a
/// no-op here.
fn runPipelineStage(wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) !void {
    const entry = tile_registry.findById(spec.tile_id) orelse return error.UnregisteredTile;
    const process_fn = entry.process_fn orelse return;
    try process_fn(wksp, spec, cnc, allocator);
}
