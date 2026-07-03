/// V1.14.S1 process-mode payment pipeline stage orchestration: runs inside
/// each tile's own process (dispatched from tile_main.zig), reading/writing
/// Tango shared-memory links (src/tickoni/runtime/link.zig) instead of
/// the thread-mode heap ring
/// (src/tickoni/tiles/payment_pipeline/queue.zig's BoundedQueue). The pure
/// decision logic — hashing, framing validation, dedup comparison, policy
/// decision, audit record building — is reused unchanged from
/// src/tickoni/tiles/payment_pipeline/{runtime,audit_sink}.zig; only the
/// transport and state ownership differ from thread mode. Dedup state
/// (tkdedu) and the audit log (tkaudt) are local to that tile's own
/// process now, not a struct shared across tiles.
///
/// The pipeline is deterministic and bounded (spec.event_count messages
/// flow through every stage — normalization/dedupe/policy mark and
/// forward rather than drop), so consumers loop exactly event_count times
/// instead of needing an explicit end-of-stream signal on the link.
///
/// Known gap: the halt check only happens between iterations, so a stage
/// blocked inside a single consume()/publish() wait will not observe a
/// halt signalled mid-wait. This does not affect the natural-completion
/// path (every stage always eventually receives its expected
/// event_count messages), only an early-abort request mid-run; broader
/// halt responsiveness is left to a follow-on story if needed.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const payment_runtime = @import("runtime.zig");
const audit_sink = @import("audit_sink.zig");

const PaymentMessage = payment_runtime.PaymentMessage;
const msg_size = @sizeOf(PaymentMessage);

fn halted(cnc: *c_abi.cnc.Cnc) bool {
    return c_abi.cnc.signalQuery(cnc) == c_abi.cnc.signal_halt;
}

fn pipelineConfig(spec: *const rt.launch_spec.LaunchSpec) payment_runtime.PaymentPipelineConfig {
    return .{
        .event_count = spec.event_count,
        .policy_limit_cents = spec.policy_limit_cents,
        .inject_duplicate = spec.inject_duplicate,
        .inject_malformed = spec.inject_malformed,
    };
}

pub fn runIngestProcess(spec: *const rt.launch_spec.LaunchSpec, output: *rt.link.Producer, cnc: *c_abi.cnc.Cnc) void {
    var stop_flag = std.atomic.Value(bool).init(false);
    var backpressure_waits = std.atomic.Value(u64).init(0);
    const cfg = pipelineConfig(spec);

    var produced: u64 = 0;
    var offset: u64 = 0;
    while (offset < spec.event_count) : (offset += 1) {
        if (halted(cnc)) break;
        const raw = payment_runtime.syntheticPayment(cfg, offset);
        const msg = PaymentMessage{ .raw = raw, .pipeline_hops = 1 };
        output.publish(std.mem.asBytes(&msg), &backpressure_waits, &stop_flag) catch break;
        produced += 1;
    }
    rt.cnc_counters.appCounterWrite(cnc, 0, produced);
}

pub fn runNormalizeProcess(spec: *const rt.launch_spec.LaunchSpec, input: *rt.link.Consumer, output: *rt.link.Producer, cnc: *c_abi.cnc.Cnc) void {
    var stop_flag = std.atomic.Value(bool).init(false);
    var backpressure_waits = std.atomic.Value(u64).init(0);
    var idle_polls = std.atomic.Value(u64).init(0);
    var buf: [msg_size]u8 = undefined;

    var normalized: u64 = 0;
    var invalid: u64 = 0;
    var i: u64 = 0;
    while (i < spec.event_count) : (i += 1) {
        if (halted(cnc)) break;
        _ = input.consume(&buf, &idle_polls, &stop_flag) orelse break;
        var msg = std.mem.bytesToValue(PaymentMessage, buf[0..msg_size]);
        msg.pipeline_hops += 1;
        msg.event_hash = payment_runtime.stableEventHash(msg.raw);
        if (!payment_runtime.validFraming(msg.raw)) {
            msg.decision = .malformed_drop;
            msg.decided_by = audit_sink.tile_id_tknorm;
            invalid += 1;
        } else {
            normalized += 1;
        }
        output.publish(std.mem.asBytes(&msg), &backpressure_waits, &stop_flag) catch break;
    }
    rt.cnc_counters.appCounterWrite(cnc, 0, normalized);
    rt.cnc_counters.appCounterWrite(cnc, 1, invalid);
}

pub fn runDedupeProcess(
    spec: *const rt.launch_spec.LaunchSpec,
    input: *rt.link.Consumer,
    output: *rt.link.Producer,
    cnc: *c_abi.cnc.Cnc,
    seen_keys: []u64,
    seen_hashes: []u64,
) void {
    var stop_flag = std.atomic.Value(bool).init(false);
    var backpressure_waits = std.atomic.Value(u64).init(0);
    var idle_polls = std.atomic.Value(u64).init(0);
    var buf: [msg_size]u8 = undefined;
    var seen_count: usize = 0;

    var duplicates: u64 = 0;
    var i: u64 = 0;
    while (i < spec.event_count) : (i += 1) {
        if (halted(cnc)) break;
        _ = input.consume(&buf, &idle_polls, &stop_flag) orelse break;
        var msg = std.mem.bytesToValue(PaymentMessage, buf[0..msg_size]);
        msg.pipeline_hops += 1;
        if (msg.decision != .malformed_drop and seenOrRemember(seen_keys, seen_hashes, &seen_count, msg)) {
            msg.duplicate = true;
            duplicates += 1;
        }
        output.publish(std.mem.asBytes(&msg), &backpressure_waits, &stop_flag) catch break;
    }
    rt.cnc_counters.appCounterWrite(cnc, 0, duplicates);
}

fn seenOrRemember(seen_keys: []u64, seen_hashes: []u64, seen_count: *usize, msg: PaymentMessage) bool {
    for (seen_keys[0..seen_count.*], seen_hashes[0..seen_count.*]) |key, hash| {
        if (key == msg.raw.idempotency_key and hash == msg.event_hash) return true;
    }
    seen_keys[seen_count.*] = msg.raw.idempotency_key;
    seen_hashes[seen_count.*] = msg.event_hash;
    seen_count.* += 1;
    return false;
}

pub fn runPolicyProcess(spec: *const rt.launch_spec.LaunchSpec, input: *rt.link.Consumer, output: *rt.link.Producer, cnc: *c_abi.cnc.Cnc) void {
    var stop_flag = std.atomic.Value(bool).init(false);
    var backpressure_waits = std.atomic.Value(u64).init(0);
    var idle_polls = std.atomic.Value(u64).init(0);
    var buf: [msg_size]u8 = undefined;

    var allowed: u64 = 0;
    var denied: u64 = 0;
    var i: u64 = 0;
    while (i < spec.event_count) : (i += 1) {
        if (halted(cnc)) break;
        _ = input.consume(&buf, &idle_polls, &stop_flag) orelse break;
        var msg = std.mem.bytesToValue(PaymentMessage, buf[0..msg_size]);
        msg.pipeline_hops += 1;
        if (msg.decision == .malformed_drop) {
            // tknorm already made this rejection decision; preserve it (and
            // its decided_by) for audit instead of silently dropping
            // malformed source facts.
        } else if (msg.duplicate) {
            msg.decision = .duplicate_drop;
            msg.decided_by = audit_sink.tile_id_tkpoly;
        } else if (msg.raw.amount_cents > spec.policy_limit_cents) {
            msg.decision = .deny;
            msg.decided_by = audit_sink.tile_id_tkpoly;
            denied += 1;
        } else {
            msg.decision = .allow;
            msg.decided_by = audit_sink.tile_id_tkpoly;
            allowed += 1;
        }
        output.publish(std.mem.asBytes(&msg), &backpressure_waits, &stop_flag) catch break;
    }
    rt.cnc_counters.appCounterWrite(cnc, 0, allowed);
    rt.cnc_counters.appCounterWrite(cnc, 1, denied);
}

pub fn runAuditProcess(
    spec: *const rt.launch_spec.LaunchSpec,
    input: *rt.link.Consumer,
    cnc: *c_abi.cnc.Cnc,
    audit_log: *audit_sink.AuditLog,
) void {
    var stop_flag = std.atomic.Value(bool).init(false);
    var idle_polls = std.atomic.Value(u64).init(0);
    var buf: [msg_size]u8 = undefined;

    var audited: u64 = 0;
    var i: u64 = 0;
    while (i < spec.event_count) : (i += 1) {
        if (halted(cnc)) break;
        _ = input.consume(&buf, &idle_polls, &stop_flag) orelse break;
        const msg = std.mem.bytesToValue(PaymentMessage, buf[0..msg_size]);
        audit_log.append(.{
            .source_offset = msg.raw.source_offset,
            .event_hash = msg.event_hash,
            .decision = @enumFromInt(@intFromEnum(msg.decision)),
            .tile_id = msg.decided_by,
        }) catch break;
        audited += 1;
    }
    rt.cnc_counters.appCounterWrite(cnc, 0, audited);
}
