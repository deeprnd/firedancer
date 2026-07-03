/// tkaudt: appends every payment event's policy decision to the append-only
/// audit log, attributing each record to whichever earlier stage
/// (decided_by) actually finalized it. Named audit_stage.zig (not audit.zig)
/// to stay distinct from the sibling audit_sink.zig record-builder and the
/// audit_tile module this pipeline audits into.
const runtime = @import("runtime.zig");
const queue = @import("queue.zig");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runAudit(state: *PaymentPipelineState) void {
    while (state.q_poly_audit.pop(&state.stop)) |msg| {
        queue.updateMaxU64(&state.max_latency_hops, @as(u64, msg.pipeline_hops) + 1);
        state.audit.append(.{
            .source_offset = msg.raw.source_offset,
            .event_hash = msg.event_hash,
            .decision = @enumFromInt(@intFromEnum(msg.decision)),
            .tile_id = msg.decided_by,
        }) catch {
            state.crashed_tile.store(4, .release);
            state.requestStop();
            break;
        };
        _ = state.audited.fetchAdd(1, .release);
    }
    state.audit_done.store(true, .release);
}
