/// Entrypoint for the internal `__tile-run <spec-file>` subcommand that
/// src/app/tickoni/supervisor.zig's startPaymentPipelineProcess self-execs
/// into for every V1.14.S1 process-mode tile. Not part of the advertised
/// CLI surface (see main.zig's usage text) — this is a supervisor-to-child
/// handoff, matching the Firedancer convention of one binary re-exec'd per
/// tile rather than a family of small per-tile binaries.
///
/// The generic single-tile boot/heartbeat/halt lifecycle lives in
/// src/tickoni/runtime/tile_process.zig; this file owns only the
/// payment-pipeline-specific dispatch (which decision-logic function to run
/// for which tile id).
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tiles = @import("tiles");
const process_stage = tiles.process;

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
/// boundary.
fn runPipelineStage(wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) !void {
    const id = spec.tile_id.slice();

    if (std.mem.eql(u8, id, "tkings")) {
        if (!spec.has_output_link) return error.MissingOutputLink;
        var output = try rt.link.Producer.join(wksp, spec.output_link);
        defer output.leave();
        process_stage.runIngestProcess(spec, &output, cnc);
    } else if (std.mem.eql(u8, id, "tknorm")) {
        if (!spec.has_input_link or !spec.has_output_link) return error.MissingLink;
        var input = try rt.link.Consumer.join(wksp, spec.input_link);
        defer input.leave();
        var output = try rt.link.Producer.join(wksp, spec.output_link);
        defer output.leave();
        process_stage.runNormalizeProcess(spec, &input, &output, cnc);
    } else if (std.mem.eql(u8, id, "tkdedu")) {
        if (!spec.has_input_link or !spec.has_output_link) return error.MissingLink;
        var input = try rt.link.Consumer.join(wksp, spec.input_link);
        defer input.leave();
        var output = try rt.link.Producer.join(wksp, spec.output_link);
        defer output.leave();
        const cap: usize = @intCast(spec.event_count);
        const seen_keys = try allocator.alloc(u64, cap);
        defer allocator.free(seen_keys);
        const seen_hashes = try allocator.alloc(u64, cap);
        defer allocator.free(seen_hashes);
        process_stage.runDedupeProcess(spec, &input, &output, cnc, seen_keys, seen_hashes);
    } else if (std.mem.eql(u8, id, "tkpoly")) {
        if (!spec.has_input_link or !spec.has_output_link) return error.MissingLink;
        var input = try rt.link.Consumer.join(wksp, spec.input_link);
        defer input.leave();
        var output = try rt.link.Producer.join(wksp, spec.output_link);
        defer output.leave();
        process_stage.runPolicyProcess(spec, &input, &output, cnc);
    } else if (std.mem.eql(u8, id, "tkaudt")) {
        if (!spec.has_input_link) return error.MissingInputLink;
        var input = try rt.link.Consumer.join(wksp, spec.input_link);
        defer input.leave();
        const cap: usize = @intCast(spec.event_count);
        var audit_log = try tiles.audit_sink.AuditLog.init(allocator, cap);
        defer audit_log.deinit(allocator);
        process_stage.runAuditProcess(spec, &input, cnc, &audit_log);
    }
}
