/// tkdedu: marks duplicate payment events using the pipeline's idempotency
/// key + event hash table. Preserves tknorm's malformed_drop decision
/// unchanged rather than checking already-rejected messages for duplicates.
const runtime = @import("runtime.zig");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runDedupe(state: *PaymentPipelineState) void {
    defer state.q_dedu_poly.close();

    while (state.q_norm_dedu.pop(&state.stop)) |msg_in| {
        var msg = msg_in;
        msg.pipeline_hops += 1;
        if (msg.decision != .malformed_drop and state.seenOrRemember(msg)) {
            msg.duplicate = true;
            _ = state.duplicates.fetchAdd(1, .release);
        }
        state.q_dedu_poly.push(msg, &state.stop) catch break;
    }
}
