/// Phase 0 Tickoni payment pipeline.
///
/// This is still a spike: tiles run as in-process threads so tests do not
/// require hugetlbfs, tango workspaces, or sandbox privileges.  The behavior is
/// intentionally product-shaped: bounded links, stable event hashes,
/// append-only audit ordering, deterministic replay, metrics, diagnostics, and
/// crash-only failure propagation.
const std = @import("std");
const audit = @import("audit.zig");

pub const PolicyDecision = enum(u8) {
    allow,
    deny,
    malformed_drop,
    duplicate_drop,
};

pub const PaymentPipelineConfig = struct {
    event_count: u64 = 10_000,
    queue_depth: usize = 64,
    policy_limit_cents: i64 = 100_000,
    inject_duplicate: bool = true,
    inject_malformed: bool = false,
    /// When set, tkings records a sandbox failure at this source offset and
    /// stops the topology.  This simulates the process-supervisor edge while
    /// the spike still runs in threads.
    sandbox_fail_at: ?u64 = null,
};

pub const RawPayment = struct {
    source_offset: u64,
    idempotency_key: u64,
    account_id: u32,
    amount_cents: i64,
    currency: [3]u8,
    malformed: bool = false,
};

pub const PaymentMessage = struct {
    raw: RawPayment,
    event_hash: u64 = 0,
    pipeline_hops: u8 = 0,
    duplicate: bool = false,
    decision: PolicyDecision = .allow,
};

pub const MetricSnapshot = struct {
    produced: u64,
    normalized: u64,
    invalid: u64,
    duplicates: u64,
    allowed: u64,
    denied: u64,
    audited: u64,
    backpressure_waits: u64,
    max_queue_depth: usize,
    max_latency_hops: u64,
};

pub const DiagSnapshot = struct {
    crashed_tile: i32,
    sandbox_failures: u64,
    audit_records: u64,
    replay_checked: bool,
    replay_match: bool,
};

const MessageQueue = BoundedQueue(PaymentMessage);
const crash_none: i32 = -1;
const tile_tkings: i32 = 0;
const audit_seed: u64 = 0xcbf29ce484222325;

pub const PaymentPipelineState = struct {
    allocator: std.mem.Allocator,
    config: PaymentPipelineConfig,
    q_ing_norm: MessageQueue,
    q_norm_dedu: MessageQueue,
    q_dedu_poly: MessageQueue,
    q_poly_audit: MessageQueue,
    seen_keys: []u64,
    seen_hashes: []u64,
    seen_count: usize,
    audit: AuditLog,

    stop: std.atomic.Value(bool),
    audit_done: std.atomic.Value(bool),
    replay_checked: std.atomic.Value(bool),
    replay_match: std.atomic.Value(bool),
    external_effects_disabled: std.atomic.Value(bool),
    crashed_tile: std.atomic.Value(i32),

    produced: std.atomic.Value(u64),
    normalized: std.atomic.Value(u64),
    invalid: std.atomic.Value(u64),
    duplicates: std.atomic.Value(u64),
    allowed: std.atomic.Value(u64),
    denied: std.atomic.Value(u64),
    audited: std.atomic.Value(u64),
    sandbox_failures: std.atomic.Value(u64),
    metric_snapshots: std.atomic.Value(u64),
    diag_snapshots: std.atomic.Value(u64),
    replay_divergences: std.atomic.Value(u64),
    max_latency_hops: std.atomic.Value(u64),

    pub fn init(allocator: std.mem.Allocator, config: PaymentPipelineConfig) !PaymentPipelineState {
        if (config.queue_depth == 0 or !std.math.isPowerOfTwo(config.queue_depth)) {
            return error.QueueDepthNotPowerOfTwo;
        }

        const audit_cap: usize = @intCast(config.event_count);
        const seen_keys = try allocator.alloc(u64, audit_cap);
        errdefer allocator.free(seen_keys);
        const seen_hashes = try allocator.alloc(u64, audit_cap);
        errdefer allocator.free(seen_hashes);

        var q_ing_norm = try MessageQueue.init(allocator, config.queue_depth);
        errdefer q_ing_norm.deinit(allocator);
        var q_norm_dedu = try MessageQueue.init(allocator, config.queue_depth);
        errdefer q_norm_dedu.deinit(allocator);
        var q_dedu_poly = try MessageQueue.init(allocator, config.queue_depth);
        errdefer q_dedu_poly.deinit(allocator);
        var q_poly_audit = try MessageQueue.init(allocator, config.queue_depth);
        errdefer q_poly_audit.deinit(allocator);

        return .{
            .allocator = allocator,
            .config = config,
            .q_ing_norm = q_ing_norm,
            .q_norm_dedu = q_norm_dedu,
            .q_dedu_poly = q_dedu_poly,
            .q_poly_audit = q_poly_audit,
            .seen_keys = seen_keys,
            .seen_hashes = seen_hashes,
            .seen_count = 0,
            .audit = try AuditLog.init(allocator, audit_cap),
            .stop = std.atomic.Value(bool).init(false),
            .audit_done = std.atomic.Value(bool).init(false),
            .replay_checked = std.atomic.Value(bool).init(false),
            .replay_match = std.atomic.Value(bool).init(false),
            .external_effects_disabled = std.atomic.Value(bool).init(false),
            .crashed_tile = std.atomic.Value(i32).init(crash_none),
            .produced = std.atomic.Value(u64).init(0),
            .normalized = std.atomic.Value(u64).init(0),
            .invalid = std.atomic.Value(u64).init(0),
            .duplicates = std.atomic.Value(u64).init(0),
            .allowed = std.atomic.Value(u64).init(0),
            .denied = std.atomic.Value(u64).init(0),
            .audited = std.atomic.Value(u64).init(0),
            .sandbox_failures = std.atomic.Value(u64).init(0),
            .metric_snapshots = std.atomic.Value(u64).init(0),
            .diag_snapshots = std.atomic.Value(u64).init(0),
            .replay_divergences = std.atomic.Value(u64).init(0),
            .max_latency_hops = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *PaymentPipelineState) void {
        self.closeQueues();
        self.q_ing_norm.deinit(self.allocator);
        self.q_norm_dedu.deinit(self.allocator);
        self.q_dedu_poly.deinit(self.allocator);
        self.q_poly_audit.deinit(self.allocator);
        self.allocator.free(self.seen_keys);
        self.allocator.free(self.seen_hashes);
        self.audit.deinit(self.allocator);
    }

    pub fn closeQueues(self: *PaymentPipelineState) void {
        self.q_ing_norm.close();
        self.q_norm_dedu.close();
        self.q_dedu_poly.close();
        self.q_poly_audit.close();
    }

    pub fn requestStop(self: *PaymentPipelineState) void {
        self.stop.store(true, .release);
        self.closeQueues();
    }

    pub fn snapshotMetrics(self: *PaymentPipelineState) MetricSnapshot {
        return .{
            .produced = self.produced.load(.acquire),
            .normalized = self.normalized.load(.acquire),
            .invalid = self.invalid.load(.acquire),
            .duplicates = self.duplicates.load(.acquire),
            .allowed = self.allowed.load(.acquire),
            .denied = self.denied.load(.acquire),
            .audited = self.audited.load(.acquire),
            .backpressure_waits = self.q_ing_norm.pushWaits() +
                self.q_norm_dedu.pushWaits() +
                self.q_dedu_poly.pushWaits() +
                self.q_poly_audit.pushWaits(),
            .max_queue_depth = @max(
                @max(self.q_ing_norm.maxDepth(), self.q_norm_dedu.maxDepth()),
                @max(self.q_dedu_poly.maxDepth(), self.q_poly_audit.maxDepth()),
            ),
            .max_latency_hops = self.max_latency_hops.load(.acquire),
        };
    }

    pub fn snapshotDiag(self: *PaymentPipelineState) DiagSnapshot {
        return .{
            .crashed_tile = self.crashed_tile.load(.acquire),
            .sandbox_failures = self.sandbox_failures.load(.acquire),
            .audit_records = self.audited.load(.acquire),
            .replay_checked = self.replay_checked.load(.acquire),
            .replay_match = self.replay_match.load(.acquire),
        };
    }

    fn seenOrRemember(self: *PaymentPipelineState, msg: PaymentMessage) bool {
        for (self.seen_keys[0..self.seen_count], self.seen_hashes[0..self.seen_count]) |key, hash| {
            if (key == msg.raw.idempotency_key and hash == msg.event_hash) return true;
        }
        self.seen_keys[self.seen_count] = msg.raw.idempotency_key;
        self.seen_hashes[self.seen_count] = msg.event_hash;
        self.seen_count += 1;
        return false;
    }
};

pub fn runIngest(state: *PaymentPipelineState) void {
    defer state.q_ing_norm.close();

    var offset: u64 = 0;
    while (offset < state.config.event_count) : (offset += 1) {
        if (state.stop.load(.acquire)) break;
        if (state.config.sandbox_fail_at) |fail_at| {
            if (offset == fail_at) {
                _ = state.sandbox_failures.fetchAdd(1, .release);
                state.crashed_tile.store(tile_tkings, .release);
                state.requestStop();
                break;
            }
        }

        const raw = syntheticPayment(state.config, offset);
        if (state.q_ing_norm.push(.{ .raw = raw, .pipeline_hops = 1 }, &state.stop)) |_| {
            _ = state.produced.fetchAdd(1, .release);
        } else |_| {
            break;
        }
    }
}

pub fn runNormalize(state: *PaymentPipelineState) void {
    defer state.q_norm_dedu.close();

    while (state.q_ing_norm.pop(&state.stop)) |msg_in| {
        var msg = msg_in;
        if (!validFraming(msg.raw)) {
            _ = state.invalid.fetchAdd(1, .release);
            msg.pipeline_hops += 1;
            msg.event_hash = stableEventHash(msg.raw);
            msg.decision = .malformed_drop;
            state.q_norm_dedu.push(msg, &state.stop) catch break;
            continue;
        }
        msg.pipeline_hops += 1;
        msg.event_hash = stableEventHash(msg.raw);
        _ = state.normalized.fetchAdd(1, .release);
        state.q_norm_dedu.push(msg, &state.stop) catch break;
    }
}

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

pub fn runPolicy(state: *PaymentPipelineState) void {
    defer state.q_poly_audit.close();

    while (state.q_dedu_poly.pop(&state.stop)) |msg_in| {
        var msg = msg_in;
        msg.pipeline_hops += 1;
        if (msg.decision == .malformed_drop) {
            // tknorm already made this rejection decision; preserve it for
            // audit instead of silently dropping malformed source facts.
        } else if (msg.duplicate) {
            msg.decision = .duplicate_drop;
        } else if (msg.raw.amount_cents > state.config.policy_limit_cents) {
            msg.decision = .deny;
            _ = state.denied.fetchAdd(1, .release);
        } else {
            msg.decision = .allow;
            _ = state.allowed.fetchAdd(1, .release);
        }
        state.q_poly_audit.push(msg, &state.stop) catch break;
    }
}

pub fn runAudit(state: *PaymentPipelineState) void {
    while (state.q_poly_audit.pop(&state.stop)) |msg| {
        updateMaxU64(&state.max_latency_hops, @as(u64, msg.pipeline_hops) + 1);
        state.audit.append(msg) catch {
            state.crashed_tile.store(4, .release);
            state.requestStop();
            break;
        };
        _ = state.audited.fetchAdd(1, .release);
    }
    state.audit_done.store(true, .release);
}

pub fn runReplay(state: *PaymentPipelineState) void {
    while (!state.audit_done.load(.acquire)) {
        if (state.stop.load(.acquire) and state.crashed_tile.load(.acquire) != crash_none) {
            state.replay_checked.store(true, .release);
            state.replay_match.store(false, .release);
            return;
        }
        std.Thread.yield() catch {};
    }

    state.external_effects_disabled.store(true, .release);
    const divergences = deterministicReplayDivergences(state);
    state.replay_divergences.store(divergences, .release);
    state.replay_match.store(divergences == 0, .release);
    state.replay_checked.store(true, .release);
}

pub fn runMetric(state: *PaymentPipelineState) void {
    while (!state.replay_checked.load(.acquire) and !state.stop.load(.acquire)) {
        _ = state.snapshotMetrics();
        _ = state.metric_snapshots.fetchAdd(1, .release);
        std.Thread.yield() catch {};
    }
    _ = state.snapshotMetrics();
    _ = state.metric_snapshots.fetchAdd(1, .release);
}

pub fn runDiag(state: *PaymentPipelineState) void {
    while (!state.replay_checked.load(.acquire) and !state.stop.load(.acquire)) {
        _ = state.snapshotDiag();
        _ = state.diag_snapshots.fetchAdd(1, .release);
        std.Thread.yield() catch {};
    }
    _ = state.snapshotDiag();
    _ = state.diag_snapshots.fetchAdd(1, .release);
}

pub fn syntheticPayment(config: PaymentPipelineConfig, offset: u64) RawPayment {
    const canonical_offset: u64 = if (config.inject_duplicate and offset == 3) 1 else offset;
    const amount: i64 = if (offset == 7) config.policy_limit_cents + 1 else @as(i64, @intCast(1_000 + canonical_offset));
    const malformed_offset: u64 = if (config.event_count == 0)
        0
    else if (config.event_count <= 5)
        config.event_count - 1
    else
        5;
    return .{
        .source_offset = offset,
        .idempotency_key = 10_000 + canonical_offset,
        .account_id = @intCast(42 + canonical_offset % 17),
        .amount_cents = amount,
        .currency = .{ 'U', 'S', 'D' },
        .malformed = config.inject_malformed and offset == malformed_offset,
    };
}

pub fn stableEventHash(raw: RawPayment) u64 {
    var h = audit_seed;
    hashU64(&h, raw.idempotency_key);
    hashU32(&h, raw.account_id);
    hashI64(&h, raw.amount_cents);
    hashBytes(&h, &raw.currency);
    return h;
}

fn validFraming(raw: RawPayment) bool {
    if (raw.malformed) return false;
    if (!std.mem.eql(u8, &raw.currency, "USD")) return false;
    return raw.amount_cents > 0;
}

fn deterministicReplayDivergences(state: *PaymentPipelineState) u64 {
    var prev_hash = audit_seed;
    var expected_seq: u64 = 0;
    var divergences: u64 = 0;

    var offset: u64 = 0;
    while (offset < state.config.event_count) : (offset += 1) {
        const raw = syntheticPayment(state.config, offset);
        const event_hash = stableEventHash(raw);
        const decision: PolicyDecision = if (!validFraming(raw)) .malformed_drop else blk: {
            const duplicate = replayDuplicate(state.config, offset, raw.idempotency_key, event_hash);
            break :blk if (duplicate)
                .duplicate_drop
            else if (raw.amount_cents > state.config.policy_limit_cents)
                .deny
            else
                .allow;
        };

        const expected = buildPolicyDecisionEvent(expected_seq, raw, event_hash, decision, prev_hash);
        if (expected_seq >= state.audit.count) {
            divergences += 1;
        } else if (!audit.auditEventsEql(expected, state.audit.records[@intCast(expected_seq)])) {
            divergences += 1;
        }
        prev_hash = expected.header.record_hash;
        expected_seq += 1;
    }

    if (expected_seq != state.audit.count) {
        divergences += if (expected_seq > state.audit.count)
            expected_seq - state.audit.count
        else
            state.audit.count - expected_seq;
    }
    return divergences;
}

fn replayDuplicate(config: PaymentPipelineConfig, offset: u64, key: u64, hash: u64) bool {
    var prior: u64 = 0;
    while (prior < offset) : (prior += 1) {
        const raw = syntheticPayment(config, prior);
        if (!validFraming(raw)) continue;
        if (raw.idempotency_key == key and stableEventHash(raw) == hash) return true;
    }
    return false;
}

fn hashU64(h: *u64, value: u64) void {
    var x = value;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        hashByte(h, @intCast(x & 0xff));
        x >>= 8;
    }
}

fn hashU32(h: *u64, value: u32) void {
    var x = value;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        hashByte(h, @intCast(x & 0xff));
        x >>= 8;
    }
}

fn hashI64(h: *u64, value: i64) void {
    hashU64(h, @bitCast(value));
}

fn hashBytes(h: *u64, bytes: []const u8) void {
    for (bytes) |byte| hashByte(h, byte);
}

fn hashByte(h: *u64, byte: u8) void {
    h.* = (h.* ^ byte) *% 0x100000001b3;
}

fn BoundedQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        buf: []T,
        /// Written by the consumer, observed by the producer.
        head: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        /// Written by the producer, observed by the consumer.
        tail: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        /// Written by the producer or supervisor during shutdown.
        closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        max_len: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        push_waits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            return .{ .buf = try allocator.alloc(T, capacity) };
        }

        fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.buf);
        }

        fn push(self: *Self, value: T, stop: *std.atomic.Value(bool)) error{ Closed, Stopped }!void {
            while (true) {
                if (self.closed.load(.acquire)) return error.Closed;

                const tail = self.tail.load(.monotonic);
                const head = self.head.load(.acquire);
                const len = tail - head;
                if (len < self.buf.len) {
                    const idx = tail & (self.buf.len - 1);
                    self.buf[idx] = value;
                    updateMaxUsize(&self.max_len, len + 1);
                    self.tail.store(tail + 1, .release);
                    return;
                }

                _ = self.push_waits.fetchAdd(1, .release);
                if (stop.load(.acquire)) return error.Stopped;
                std.Thread.yield() catch {};
            }
        }

        fn pop(self: *Self, stop: *std.atomic.Value(bool)) ?T {
            while (true) {
                const head = self.head.load(.monotonic);
                const tail = self.tail.load(.acquire);
                if (head != tail) {
                    const value = self.buf[head & (self.buf.len - 1)];
                    self.head.store(head + 1, .release);
                    return value;
                }

                if (self.closed.load(.acquire)) return null;
                if (stop.load(.acquire)) return null;
                std.Thread.yield() catch {};
            }
        }

        fn close(self: *Self) void {
            self.closed.store(true, .release);
        }

        fn maxDepth(self: *Self) usize {
            return self.max_len.load(.acquire);
        }

        fn pushWaits(self: *Self) u64 {
            return self.push_waits.load(.acquire);
        }
    };
}

const tkpoly_tile_id: [6]u8 = "tkpoly".*;

fn buildPolicyDecisionEvent(
    seq: u64,
    raw: RawPayment,
    event_hash: u64,
    decision: PolicyDecision,
    prev_hash: u64,
) audit.AuditEvent {
    const outcome: audit.PolicyOutcome = switch (decision) {
        .allow => .allow,
        .deny => .deny,
        .malformed_drop => .malformed_drop,
        .duplicate_drop => .duplicate_drop,
    };
    return audit.buildEvent(.{
        .schema_version = audit.audit_schema_version,
        .seq = seq,
        .source_offset = raw.source_offset,
        .tile_id = tkpoly_tile_id,
        .logical_actor_id = 0,
        .policy_version = [_]u8{0} ** 32,
        .capability_envelope_id = 0,
        .timestamp_ns = 0,
        .prev_hash = prev_hash,
        .record_hash = 0,
    }, .{
        .policy_decision = .{
            .outcome = outcome,
            .rule_id = 0,
            .failed_scope_dim = [_]u8{0} ** 32,
            .source_event_hash = event_hash,
        },
    });
}

const AuditLog = struct {
    records: []audit.AuditEvent,
    count: usize = 0,
    prev_hash: u64 = audit_seed,

    fn init(allocator: std.mem.Allocator, capacity: usize) !AuditLog {
        return .{ .records = try allocator.alloc(audit.AuditEvent, capacity) };
    }

    fn deinit(self: *AuditLog, allocator: std.mem.Allocator) void {
        allocator.free(self.records);
    }

    fn append(self: *AuditLog, msg: PaymentMessage) error{AuditFull}!void {
        if (self.count >= self.records.len) return error.AuditFull;
        const event = buildPolicyDecisionEvent(
            @intCast(self.count),
            msg.raw,
            msg.event_hash,
            msg.decision,
            self.prev_hash,
        );
        self.records[self.count] = event;
        self.count += 1;
        self.prev_hash = event.header.record_hash;
    }
};

fn updateMaxU64(value: *std.atomic.Value(u64), candidate: u64) void {
    var current = value.load(.acquire);
    while (candidate > current) {
        if (value.cmpxchgWeak(current, candidate, .release, .acquire)) |observed| {
            current = observed;
        } else {
            return;
        }
    }
}

fn updateMaxUsize(value: *std.atomic.Value(usize), candidate: usize) void {
    var current = value.load(.acquire);
    while (candidate > current) {
        if (value.cmpxchgWeak(current, candidate, .release, .acquire)) |observed| {
            current = observed;
        } else {
            return;
        }
    }
}

test "stableEventHash is deterministic and ignores source offset" {
    const cfg = PaymentPipelineConfig{};
    const a = syntheticPayment(cfg, 1);
    const b = syntheticPayment(cfg, 3);
    try std.testing.expectEqual(a.idempotency_key, b.idempotency_key);
    try std.testing.expectEqual(stableEventHash(a), stableEventHash(b));
}

test "payment tile stages audit and replay one valid payment sequentially" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 1, .queue_depth = 1 });
    defer state.deinit();

    try runOneSequentialForTest(&state, syntheticPayment(state.config, 0));

    const metrics = state.snapshotMetrics();
    try std.testing.expectEqual(@as(u64, 1), metrics.normalized);
    try std.testing.expectEqual(@as(u64, 1), metrics.audited);
    try std.testing.expectEqual(@as(u64, 1), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 5), metrics.max_latency_hops);
    try std.testing.expect(state.replay_checked.load(.seq_cst));
    try std.testing.expect(state.replay_match.load(.seq_cst));
    try std.testing.expect(state.external_effects_disabled.load(.seq_cst));
}

test "Phase 0 rejects malformed payment framing" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 1, .queue_depth = 1, .inject_malformed = true });
    defer state.deinit();
    try runOneSequentialForTest(&state, syntheticPayment(state.config, 0));
    try std.testing.expectEqual(@as(u64, 1), state.invalid.load(.seq_cst));
    try std.testing.expectEqual(@as(u64, 0), state.normalized.load(.seq_cst));
    try std.testing.expectEqual(@as(u64, 1), state.audited.load(.seq_cst));
    try std.testing.expectEqual(audit.PolicyOutcome.malformed_drop, state.audit.records[0].payload.policy_decision.outcome);
    try std.testing.expect(state.replay_match.load(.seq_cst));
}

test "sandbox failure records crash diagnostics and stops ingest" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 10, .queue_depth = 2, .sandbox_fail_at = 2 });
    defer state.deinit();
    runIngest(&state);
    const diag = state.snapshotDiag();
    try std.testing.expectEqual(tile_tkings, diag.crashed_tile);
    try std.testing.expectEqual(@as(u64, 1), diag.sandbox_failures);
    try std.testing.expect(state.stop.load(.seq_cst));
}

fn runOneSequentialForTest(state: *PaymentPipelineState, raw: RawPayment) !void {
    try state.q_ing_norm.push(.{ .raw = raw, .pipeline_hops = 1 }, &state.stop);
    state.q_ing_norm.close();
    runNormalize(state);
    runDedupe(state);
    runPolicy(state);
    runAudit(state);
    runReplay(state);
}
