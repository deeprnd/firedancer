/// tkpoly: makes the final policy decision for each payment event (allow,
/// deny on amount limit, or duplicate_drop), preserving tknorm's
/// malformed_drop decision unchanged. Stamps itself as decided_by for every
/// decision it makes.
const runtime = @import("runtime.zig");
const audit_sink = @import("audit_sink.zig");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runPolicy(state: *PaymentPipelineState) void {
    defer state.q_poly_audit.close();

    while (state.q_dedu_poly.pop(&state.stop)) |msg_in| {
        var msg = msg_in;
        msg.pipeline_hops += 1;
        if (msg.decision == .malformed_drop) {
            // tknorm already made this rejection decision; preserve it (and
            // its decided_by) for audit instead of silently dropping
            // malformed source facts.
        } else if (msg.duplicate) {
            msg.decision = .duplicate_drop;
            msg.decided_by = audit_sink.tile_id_tkpoly;
        } else if (msg.raw.amount_cents > state.config.policy_limit_cents) {
            msg.decision = .deny;
            msg.decided_by = audit_sink.tile_id_tkpoly;
            _ = state.denied.fetchAdd(1, .release);
        } else {
            msg.decision = .allow;
            msg.decided_by = audit_sink.tile_id_tkpoly;
            _ = state.allowed.fetchAdd(1, .release);
        }
        state.q_poly_audit.push(msg, &state.stop) catch break;
    }
}
