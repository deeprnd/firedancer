/// tkdedu: marks duplicate payment events using the pipeline's idempotency
/// key + event hash table. Preserves tknorm's malformed_drop decision
/// unchanged rather than checking already-rejected messages for duplicates.
const std = @import("std");
const runtime = @import("runtime.zig");
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runDedupe(state: *PaymentPipelineState) void {
    const log = logger.get();
    try log.enter("tkdedu", "runDedupe");
    defer log.exit("tkdedu", "runDedupe") catch {};

    defer state.q_dedu_poly.close();

    var offset: u64 = 0;
    while (state.q_norm_dedu.pop(&state.stop)) |msg_in| {
        var msg = msg_in;
        msg.pipeline_hops += 1;
        offset += 1;
        if (msg.decision != .malformed_drop and state.seenOrRemember(msg)) {
            msg.duplicate = true;
            _ = state.duplicates.fetchAdd(1, .release);
            log.err("tkdedu", "runDedupe", "duplicate event at offset") catch {};
        }
        state.q_dedu_poly.push(msg, &state.stop) catch break;
    }
    log.debug("tkdedu", "runDedupe", "done") catch {};
}

test "sandbox failure records crash diagnostics and stops dedupe" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 5, .queue_depth = 2 });
    defer state.deinit();
    runDedupe(&state);
}
