/// tknorm: canonicalizes payment events (stable event hash) and rejects
/// malformed framing, stamping itself as the audit record's decided_by tile
/// when it makes that rejection decision.
const runtime = @import("runtime.zig");
const audit_sink = @import("audit_sink.zig");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runNormalize(state: *PaymentPipelineState) void {
    defer state.q_norm_dedu.close();

    while (state.q_ing_norm.pop(&state.stop)) |msg_in| {
        var msg = msg_in;
        if (!runtime.validFraming(msg.raw)) {
            _ = state.invalid.fetchAdd(1, .release);
            msg.pipeline_hops += 1;
            msg.event_hash = runtime.stableEventHash(msg.raw);
            msg.decision = .malformed_drop;
            msg.decided_by = audit_sink.tile_id_tknorm;
            state.q_norm_dedu.push(msg, &state.stop) catch break;
            continue;
        }
        msg.pipeline_hops += 1;
        msg.event_hash = runtime.stableEventHash(msg.raw);
        _ = state.normalized.fetchAdd(1, .release);
        state.q_norm_dedu.push(msg, &state.stop) catch break;
    }
}
