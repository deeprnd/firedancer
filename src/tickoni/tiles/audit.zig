/// Canonical audit record schema for Tickoni tiles.
///
/// Every material boundary event is a typed AuditEvent so replay and
/// investigation do not depend on logs or UI state.
const std = @import("std");

pub const audit_schema_version: u16 = 1;
const hash_seed: u64 = 0xcbf29ce484222325;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Policy evaluation outcomes — superset covering all tile decision paths.
pub const PolicyOutcome = enum(u8) {
    allow,
    deny,
    require_approval,
    malformed_drop,
    duplicate_drop,
    escalate,
    require_more_evidence,
};

/// Financial limit categories used in limit check records.
pub const LimitType = enum(u8) {
    amount,
    frequency,
    holding_period,
    per_day,
    per_month,
};

/// Every material event kind that can appear in the audit chain.
pub const RecordType = enum(u8) {
    source_event = 0,
    normalization = 1,
    policy_decision = 2,
    model_call = 3,
    financial_adapter_call = 4,
    proposal = 5,
    destination_check = 6,
    limit_check = 7,
    approval_required = 8,
    denial = 9,
    telemetry_checkpoint = 10,
    replay_result = 11,
};

// ---------------------------------------------------------------------------
// Per-type payloads
// ---------------------------------------------------------------------------

pub const SourceEventPayload = struct {
    source_system: [16]u8,
    event_type: [32]u8,
    raw_hash: u64,
};

pub const NormalizationPayload = struct {
    source_event_hash: u64,
    normalized_hash: u64,
    canonical_event_type: [32]u8,
};

/// source_event_hash links this decision back to the source event.
pub const PolicyDecisionPayload = struct {
    outcome: PolicyOutcome,
    rule_id: u32,
    failed_scope_dim: [32]u8,
    source_event_hash: u64,
};

/// Stub — fields populated by tkmodl in Phase 1.
pub const ModelCallPayload = struct {
    model_id: [32]u8,
    prompt_hash: u64,
    response_hash: u64,
    token_estimate: u32,
    retry_count: u8,
};

/// Stub — fields populated by tkadpt in Phase 1.
pub const FinancialAdapterCallPayload = struct {
    adapter_id: [16]u8,
    request_hash: u64,
    response_hash: u64,
    fixture_id: u32,
};

/// Stub — fields populated by tkagnt in Phase 1.
pub const ProposalPayload = struct {
    proposal_type: [32]u8,
    proposal_hash: u64,
    approval_state: u8,
};

pub const DestinationCheckPayload = struct {
    destination_type: [16]u8,
    allowlist_version: u32,
    outcome: PolicyOutcome,
};

pub const LimitCheckPayload = struct {
    limit_type: LimitType,
    value: i64,
    limit: i64,
    outcome: PolicyOutcome,
};

pub const ApprovalRequiredPayload = struct {
    action_class: [32]u8,
    approval_path: [32]u8,
    proposal_hash: u64,
};

pub const DenialPayload = struct {
    action_class: [32]u8,
    reason_code: u32,
    failed_scope_dim: [32]u8,
};

pub const TelemetryCheckpointPayload = struct {
    metric_set_hash: u64,
    source_offset_watermark: u64,
};

pub const ReplayResultPayload = struct {
    capsule_id: u64,
    divergences: u64,
    first_divergent_seq: u64,
};

// ---------------------------------------------------------------------------
// Header and AuditEvent
// ---------------------------------------------------------------------------

/// Common header on every audit record.
///
/// timestamp_ns is stored for human inspection but excluded from record_hash
/// so replay runs (which use timestamp_ns=0) produce matching hashes against
/// original runs.
///
/// capability_envelope_id is reserved as 0 until E3.S1 defines the envelope
/// schema.
pub const Header = struct {
    schema_version: u16,
    seq: u64,
    source_offset: u64,
    tile_id: [6]u8,
    logical_actor_id: u64,
    policy_version: [32]u8,
    capability_envelope_id: u128,
    timestamp_ns: u64,
    prev_hash: u64,
    record_hash: u64,
};

/// One entry in the append-only audit chain.
pub const AuditEvent = struct {
    header: Header,
    payload: Payload,

    pub const Payload = union(RecordType) {
        source_event: SourceEventPayload,
        normalization: NormalizationPayload,
        policy_decision: PolicyDecisionPayload,
        model_call: ModelCallPayload,
        financial_adapter_call: FinancialAdapterCallPayload,
        proposal: ProposalPayload,
        destination_check: DestinationCheckPayload,
        limit_check: LimitCheckPayload,
        approval_required: ApprovalRequiredPayload,
        denial: DenialPayload,
        telemetry_checkpoint: TelemetryCheckpointPayload,
        replay_result: ReplayResultPayload,
    };
};

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Build an AuditEvent with record_hash computed from all fields except
/// timestamp_ns.  Set timestamp_ns in header_without_hash before calling;
/// it is stored in the returned event but does not affect the hash.
pub fn buildEvent(header_without_hash: Header, payload: AuditEvent.Payload) AuditEvent {
    var event = AuditEvent{ .header = header_without_hash, .payload = payload };
    event.header.record_hash = computeRecordHash(event);
    return event;
}

/// Hash all header fields except timestamp_ns and record_hash, plus all
/// payload fields, in a fixed canonical field order using FNV-1a byte mixing.
///
/// Deterministic across process runs and compiler optimization modes because
/// each field is hashed byte-by-byte in explicit order — no struct memory
/// layout or padding is assumed.
pub fn computeRecordHash(event: AuditEvent) u64 {
    var h = hash_seed;
    hashU16(&h, event.header.schema_version);
    hashU64(&h, event.header.seq);
    hashU64(&h, event.header.source_offset);
    hashBytes(&h, &event.header.tile_id);
    hashU64(&h, event.header.logical_actor_id);
    hashBytes(&h, &event.header.policy_version);
    hashU128(&h, event.header.capability_envelope_id);
    hashU64(&h, event.header.prev_hash);
    hashU8(&h, @intFromEnum(std.meta.activeTag(event.payload)));
    switch (event.payload) {
        .source_event => |p| {
            hashBytes(&h, &p.source_system);
            hashBytes(&h, &p.event_type);
            hashU64(&h, p.raw_hash);
        },
        .normalization => |p| {
            hashU64(&h, p.source_event_hash);
            hashU64(&h, p.normalized_hash);
            hashBytes(&h, &p.canonical_event_type);
        },
        .policy_decision => |p| {
            hashU8(&h, @intFromEnum(p.outcome));
            hashU32(&h, p.rule_id);
            hashBytes(&h, &p.failed_scope_dim);
            hashU64(&h, p.source_event_hash);
        },
        .model_call => |p| {
            hashBytes(&h, &p.model_id);
            hashU64(&h, p.prompt_hash);
            hashU64(&h, p.response_hash);
            hashU32(&h, p.token_estimate);
            hashU8(&h, p.retry_count);
        },
        .financial_adapter_call => |p| {
            hashBytes(&h, &p.adapter_id);
            hashU64(&h, p.request_hash);
            hashU64(&h, p.response_hash);
            hashU32(&h, p.fixture_id);
        },
        .proposal => |p| {
            hashBytes(&h, &p.proposal_type);
            hashU64(&h, p.proposal_hash);
            hashU8(&h, p.approval_state);
        },
        .destination_check => |p| {
            hashBytes(&h, &p.destination_type);
            hashU32(&h, p.allowlist_version);
            hashU8(&h, @intFromEnum(p.outcome));
        },
        .limit_check => |p| {
            hashU8(&h, @intFromEnum(p.limit_type));
            hashI64(&h, p.value);
            hashI64(&h, p.limit);
            hashU8(&h, @intFromEnum(p.outcome));
        },
        .approval_required => |p| {
            hashBytes(&h, &p.action_class);
            hashBytes(&h, &p.approval_path);
            hashU64(&h, p.proposal_hash);
        },
        .denial => |p| {
            hashBytes(&h, &p.action_class);
            hashU32(&h, p.reason_code);
            hashBytes(&h, &p.failed_scope_dim);
        },
        .telemetry_checkpoint => |p| {
            hashU64(&h, p.metric_set_hash);
            hashU64(&h, p.source_offset_watermark);
        },
        .replay_result => |p| {
            hashU64(&h, p.capsule_id);
            hashU64(&h, p.divergences);
            hashU64(&h, p.first_divergent_seq);
        },
    }
    return h;
}

// ---------------------------------------------------------------------------
// Comparison and validation
// ---------------------------------------------------------------------------

/// Returns true when both events have the same record_hash.
///
/// timestamp_ns is not compared — it differs between original and replay runs
/// but is excluded from record_hash by design.
pub fn auditEventsEql(a: AuditEvent, b: AuditEvent) bool {
    return a.header.record_hash == b.header.record_hash;
}

/// Returns error.UnknownSchemaVersion for versions this code cannot interpret.
pub fn checkSchemaVersion(version: u16) error{UnknownSchemaVersion}!void {
    if (version > audit_schema_version) return error.UnknownSchemaVersion;
}

/// Returns error.UnknownRecordType for tags not in the current RecordType enum.
pub fn parseRecordType(tag: u8) error{UnknownRecordType}!RecordType {
    inline for (@typeInfo(RecordType).@"enum".fields) |field| {
        if (field.value == tag) return @field(RecordType, field.name);
    }
    return error.UnknownRecordType;
}

// ---------------------------------------------------------------------------
// JSON serialization
// ---------------------------------------------------------------------------

/// Maximum byte length of one JSONL line including the trailing newline.
pub const max_jsonl_len: usize = 1024;

/// Write one JSONL line for event into buf and return the written slice.
///
/// Field order is fixed and canonical; schema_version is always first.
/// timestamp_ns is included in output even though it is not in the hash.
/// String fields are null-truncated; full JSON escaping is not implemented —
/// field values must be printable ASCII in Phase 0.
pub fn formatJsonl(buf: []u8, event: AuditEvent) ![]u8 {
    var w = BufWriter{ .buf = buf, .pos = 0 };
    try w.writeByte('{');
    try writeJsonHeader(&w, event.header, @tagName(std.meta.activeTag(event.payload)));
    try w.writeByte(',');
    switch (event.payload) {
        .source_event => |p| try writeJsonSourceEvent(&w, p),
        .normalization => |p| try writeJsonNormalization(&w, p),
        .policy_decision => |p| try writeJsonPolicyDecision(&w, p),
        .model_call => |p| try writeJsonModelCall(&w, p),
        .financial_adapter_call => |p| try writeJsonFinancialAdapterCall(&w, p),
        .proposal => |p| try writeJsonProposal(&w, p),
        .destination_check => |p| try writeJsonDestinationCheck(&w, p),
        .limit_check => |p| try writeJsonLimitCheck(&w, p),
        .approval_required => |p| try writeJsonApprovalRequired(&w, p),
        .denial => |p| try writeJsonDenial(&w, p),
        .telemetry_checkpoint => |p| try writeJsonTelemetryCheckpoint(&w, p),
        .replay_result => |p| try writeJsonReplayResult(&w, p),
    }
    try w.writeAll("}\n");
    return buf[0..w.pos];
}

// ---------------------------------------------------------------------------
// Private: buffer writer
// ---------------------------------------------------------------------------

const BufWriter = struct {
    buf: []u8,
    pos: usize,

    fn print(self: *BufWriter, comptime fmt: []const u8, args: anytype) error{NoSpaceLeft}!void {
        const written = try std.fmt.bufPrint(self.buf[self.pos..], fmt, args);
        self.pos += written.len;
    }

    fn writeByte(self: *BufWriter, byte: u8) error{NoSpaceLeft}!void {
        if (self.pos >= self.buf.len) return error.NoSpaceLeft;
        self.buf[self.pos] = byte;
        self.pos += 1;
    }

    fn writeAll(self: *BufWriter, s: []const u8) error{NoSpaceLeft}!void {
        if (self.pos + s.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..s.len], s);
        self.pos += s.len;
    }
};

// ---------------------------------------------------------------------------
// Private: per-type JSON writers
// ---------------------------------------------------------------------------

fn writeJsonHeader(w: *BufWriter, h: Header, record_type: []const u8) !void {
    try w.print(
        "\"schema_version\":{d},\"record_type\":\"{s}\"," ++
            "\"seq\":{d},\"source_offset\":{d},\"tile_id\":\"{s}\"," ++
            "\"logical_actor_id\":{d},\"policy_version\":\"{s}\"," ++
            "\"capability_envelope_id\":{d},\"timestamp_ns\":{d}," ++
            "\"prev_hash\":{d},\"record_hash\":{d}",
        .{
            h.schema_version,
            record_type,
            h.seq,
            h.source_offset,
            trimmedBytes(&h.tile_id),
            h.logical_actor_id,
            trimmedBytes(&h.policy_version),
            h.capability_envelope_id,
            h.timestamp_ns,
            h.prev_hash,
            h.record_hash,
        },
    );
}

fn writeJsonSourceEvent(w: *BufWriter, p: SourceEventPayload) !void {
    try w.print(
        "\"source_system\":\"{s}\",\"event_type\":\"{s}\",\"raw_hash\":{d}",
        .{ trimmedBytes(&p.source_system), trimmedBytes(&p.event_type), p.raw_hash },
    );
}

fn writeJsonNormalization(w: *BufWriter, p: NormalizationPayload) !void {
    try w.print(
        "\"source_event_hash\":{d},\"normalized_hash\":{d},\"canonical_event_type\":\"{s}\"",
        .{ p.source_event_hash, p.normalized_hash, trimmedBytes(&p.canonical_event_type) },
    );
}

fn writeJsonPolicyDecision(w: *BufWriter, p: PolicyDecisionPayload) !void {
    try w.print(
        "\"outcome\":\"{s}\",\"rule_id\":{d},\"failed_scope_dim\":\"{s}\",\"source_event_hash\":{d}",
        .{ @tagName(p.outcome), p.rule_id, trimmedBytes(&p.failed_scope_dim), p.source_event_hash },
    );
}

fn writeJsonModelCall(w: *BufWriter, p: ModelCallPayload) !void {
    try w.print(
        "\"model_id\":\"{s}\",\"prompt_hash\":{d},\"response_hash\":{d}," ++
            "\"token_estimate\":{d},\"retry_count\":{d}",
        .{ trimmedBytes(&p.model_id), p.prompt_hash, p.response_hash, p.token_estimate, p.retry_count },
    );
}

fn writeJsonFinancialAdapterCall(w: *BufWriter, p: FinancialAdapterCallPayload) !void {
    try w.print(
        "\"adapter_id\":\"{s}\",\"request_hash\":{d},\"response_hash\":{d},\"fixture_id\":{d}",
        .{ trimmedBytes(&p.adapter_id), p.request_hash, p.response_hash, p.fixture_id },
    );
}

fn writeJsonProposal(w: *BufWriter, p: ProposalPayload) !void {
    try w.print(
        "\"proposal_type\":\"{s}\",\"proposal_hash\":{d},\"approval_state\":{d}",
        .{ trimmedBytes(&p.proposal_type), p.proposal_hash, p.approval_state },
    );
}

fn writeJsonDestinationCheck(w: *BufWriter, p: DestinationCheckPayload) !void {
    try w.print(
        "\"destination_type\":\"{s}\",\"allowlist_version\":{d},\"outcome\":\"{s}\"",
        .{ trimmedBytes(&p.destination_type), p.allowlist_version, @tagName(p.outcome) },
    );
}

fn writeJsonLimitCheck(w: *BufWriter, p: LimitCheckPayload) !void {
    try w.print(
        "\"limit_type\":\"{s}\",\"value\":{d},\"limit\":{d},\"outcome\":\"{s}\"",
        .{ @tagName(p.limit_type), p.value, p.limit, @tagName(p.outcome) },
    );
}

fn writeJsonApprovalRequired(w: *BufWriter, p: ApprovalRequiredPayload) !void {
    try w.print(
        "\"action_class\":\"{s}\",\"approval_path\":\"{s}\",\"proposal_hash\":{d}",
        .{ trimmedBytes(&p.action_class), trimmedBytes(&p.approval_path), p.proposal_hash },
    );
}

fn writeJsonDenial(w: *BufWriter, p: DenialPayload) !void {
    try w.print(
        "\"action_class\":\"{s}\",\"reason_code\":{d},\"failed_scope_dim\":\"{s}\"",
        .{ trimmedBytes(&p.action_class), p.reason_code, trimmedBytes(&p.failed_scope_dim) },
    );
}

fn writeJsonTelemetryCheckpoint(w: *BufWriter, p: TelemetryCheckpointPayload) !void {
    try w.print(
        "\"metric_set_hash\":{d},\"source_offset_watermark\":{d}",
        .{ p.metric_set_hash, p.source_offset_watermark },
    );
}

fn writeJsonReplayResult(w: *BufWriter, p: ReplayResultPayload) !void {
    try w.print(
        "\"capsule_id\":{d},\"divergences\":{d},\"first_divergent_seq\":{d}",
        .{ p.capsule_id, p.divergences, p.first_divergent_seq },
    );
}

/// Slice a zero-padded fixed-size byte array to its first null byte.
fn trimmedBytes(arr: anytype) []const u8 {
    const s: []const u8 = arr;
    const end = std.mem.indexOfScalar(u8, s, 0) orelse s.len;
    return s[0..end];
}

// ---------------------------------------------------------------------------
// Private FNV-1a hash helpers
// ---------------------------------------------------------------------------

fn hashU8(h: *u64, value: u8) void {
    h.* = (h.* ^ value) *% 0x100000001b3;
}

fn hashU16(h: *u64, value: u16) void {
    hashU8(h, @intCast(value & 0xff));
    hashU8(h, @intCast((value >> 8) & 0xff));
}

fn hashU32(h: *u64, value: u32) void {
    var x = value;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        hashU8(h, @intCast(x & 0xff));
        x >>= 8;
    }
}

fn hashU64(h: *u64, value: u64) void {
    var x = value;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        hashU8(h, @intCast(x & 0xff));
        x >>= 8;
    }
}

fn hashU128(h: *u64, value: u128) void {
    var x = value;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        hashU8(h, @intCast(x & 0xff));
        x >>= 8;
    }
}

fn hashI64(h: *u64, value: i64) void {
    hashU64(h, @bitCast(value));
}

fn hashBytes(h: *u64, bytes: []const u8) void {
    for (bytes) |byte| hashU8(h, byte);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn zeroHeader(seq: u64, source_offset: u64, tile_id_str: []const u8) Header {
    var tile_id = [_]u8{0} ** 6;
    @memcpy(tile_id[0..tile_id_str.len], tile_id_str);
    return .{
        .schema_version = audit_schema_version,
        .seq = seq,
        .source_offset = source_offset,
        .tile_id = tile_id,
        .logical_actor_id = 0,
        .policy_version = [_]u8{0} ** 32,
        .capability_envelope_id = 0,
        .timestamp_ns = 0,
        .prev_hash = hash_seed,
        .record_hash = 0,
    };
}

fn zeroPolicyDecision() AuditEvent.Payload {
    return .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 0,
        .failed_scope_dim = [_]u8{0} ** 32,
        .source_event_hash = 0,
    } };
}

test "computeRecordHash excludes timestamp_ns" {
    const payload = zeroPolicyDecision();
    const h0 = zeroHeader(0, 0, "tkaudt");
    var h1 = h0;
    h1.timestamp_ns = 999_999_999;
    const e0 = buildEvent(h0, payload);
    const e1 = buildEvent(h1, payload);
    try std.testing.expectEqual(e0.header.record_hash, e1.header.record_hash);
}

test "computeRecordHash is stable across two calls with identical inputs" {
    // Verifies no non-deterministic input (pointer, padding, etc.) leaks in.
    const e0 = buildEvent(zeroHeader(42, 7, "tkpoly"), zeroPolicyDecision());
    const e1 = buildEvent(zeroHeader(42, 7, "tkpoly"), zeroPolicyDecision());
    try std.testing.expectEqual(e0.header.record_hash, e1.header.record_hash);
}

test "computeRecordHash differs by seq" {
    const e0 = buildEvent(zeroHeader(0, 0, "tkaudt"), zeroPolicyDecision());
    const e1 = buildEvent(zeroHeader(1, 0, "tkaudt"), zeroPolicyDecision());
    try std.testing.expect(e0.header.record_hash != e1.header.record_hash);
}

test "computeRecordHash differs by source_offset" {
    const e0 = buildEvent(zeroHeader(0, 0, "tkaudt"), zeroPolicyDecision());
    const e1 = buildEvent(zeroHeader(0, 1, "tkaudt"), zeroPolicyDecision());
    try std.testing.expect(e0.header.record_hash != e1.header.record_hash);
}

test "computeRecordHash differs by tile_id" {
    const e0 = buildEvent(zeroHeader(0, 0, "tkaudt"), zeroPolicyDecision());
    const e1 = buildEvent(zeroHeader(0, 0, "tkpoly"), zeroPolicyDecision());
    try std.testing.expect(e0.header.record_hash != e1.header.record_hash);
}

test "computeRecordHash differs by prev_hash" {
    var h0 = zeroHeader(0, 0, "tkaudt");
    var h1 = zeroHeader(0, 0, "tkaudt");
    h0.prev_hash = hash_seed;
    h1.prev_hash = 0;
    const e0 = buildEvent(h0, zeroPolicyDecision());
    const e1 = buildEvent(h1, zeroPolicyDecision());
    try std.testing.expect(e0.header.record_hash != e1.header.record_hash);
}

test "computeRecordHash differs by policy outcome" {
    const h = zeroHeader(0, 0, "tkaudt");
    const e0 = buildEvent(h, .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 0,
        .failed_scope_dim = [_]u8{0} ** 32,
        .source_event_hash = 0,
    } });
    const e1 = buildEvent(h, .{ .policy_decision = .{
        .outcome = .deny,
        .rule_id = 0,
        .failed_scope_dim = [_]u8{0} ** 32,
        .source_event_hash = 0,
    } });
    try std.testing.expect(e0.header.record_hash != e1.header.record_hash);
}

test "computeRecordHash differs by record type" {
    const h = zeroHeader(0, 0, "tkaudt");
    const pd = buildEvent(h, zeroPolicyDecision());
    const rr = buildEvent(h, .{ .replay_result = .{
        .capsule_id = 0,
        .divergences = 0,
        .first_divergent_seq = 0,
    } });
    try std.testing.expect(pd.header.record_hash != rr.header.record_hash);
}

test "hash chain: mutating one record changes all subsequent hashes" {
    const payload = zeroPolicyDecision();
    const e0 = buildEvent(zeroHeader(0, 0, "tkaudt"), payload);

    var h1a = zeroHeader(1, 1, "tkaudt");
    h1a.prev_hash = e0.header.record_hash;
    const e1a = buildEvent(h1a, payload);

    var h0m = zeroHeader(0, 99, "tkaudt");
    h0m.prev_hash = hash_seed;
    const e0m = buildEvent(h0m, payload);

    var h1b = zeroHeader(1, 1, "tkaudt");
    h1b.prev_hash = e0m.header.record_hash;
    const e1b = buildEvent(h1b, payload);

    try std.testing.expect(e0.header.record_hash != e0m.header.record_hash);
    try std.testing.expect(e1a.header.record_hash != e1b.header.record_hash);
}

test "auditEventsEql: same record equals itself" {
    const e = buildEvent(zeroHeader(0, 0, "tkaudt"), zeroPolicyDecision());
    try std.testing.expect(auditEventsEql(e, e));
}

test "auditEventsEql: events with different timestamps are equal" {
    const payload = zeroPolicyDecision();
    const h0 = zeroHeader(0, 0, "tkaudt");
    var h1 = h0;
    h1.timestamp_ns = 42;
    const e0 = buildEvent(h0, payload);
    const e1 = buildEvent(h1, payload);
    try std.testing.expect(auditEventsEql(e0, e1));
}

test "auditEventsEql: different seq are not equal" {
    const e0 = buildEvent(zeroHeader(0, 0, "tkaudt"), zeroPolicyDecision());
    const e1 = buildEvent(zeroHeader(1, 0, "tkaudt"), zeroPolicyDecision());
    try std.testing.expect(!auditEventsEql(e0, e1));
}

test "checkSchemaVersion accepts current version" {
    try checkSchemaVersion(audit_schema_version);
}

test "checkSchemaVersion rejects future version" {
    try std.testing.expectError(
        error.UnknownSchemaVersion,
        checkSchemaVersion(audit_schema_version + 1),
    );
}

test "parseRecordType accepts all known types" {
    try std.testing.expectEqual(RecordType.source_event, try parseRecordType(0));
    try std.testing.expectEqual(RecordType.normalization, try parseRecordType(1));
    try std.testing.expectEqual(RecordType.policy_decision, try parseRecordType(2));
    try std.testing.expectEqual(RecordType.model_call, try parseRecordType(3));
    try std.testing.expectEqual(RecordType.financial_adapter_call, try parseRecordType(4));
    try std.testing.expectEqual(RecordType.proposal, try parseRecordType(5));
    try std.testing.expectEqual(RecordType.destination_check, try parseRecordType(6));
    try std.testing.expectEqual(RecordType.limit_check, try parseRecordType(7));
    try std.testing.expectEqual(RecordType.approval_required, try parseRecordType(8));
    try std.testing.expectEqual(RecordType.denial, try parseRecordType(9));
    try std.testing.expectEqual(RecordType.telemetry_checkpoint, try parseRecordType(10));
    try std.testing.expectEqual(RecordType.replay_result, try parseRecordType(11));
}

test "parseRecordType rejects unknown tag" {
    try std.testing.expectError(error.UnknownRecordType, parseRecordType(255));
}

test "formatJsonl policy_decision has correct structure" {
    const e = buildEvent(zeroHeader(0, 0, "tkaudt"), zeroPolicyDecision());
    var buf: [max_jsonl_len]u8 = undefined;
    const line = try formatJsonl(&buf, e);
    try std.testing.expect(std.mem.startsWith(
        u8,
        line,
        "{\"schema_version\":1,\"record_type\":\"policy_decision\",",
    ));
    try std.testing.expect(std.mem.endsWith(u8, line, "}\n"));
    try std.testing.expect(std.mem.indexOf(u8, line, "\"outcome\":\"allow\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"tile_id\":\"tkaudt\"") != null);
}

test "formatJsonl all record types produce valid structure" {
    var buf: [max_jsonl_len]u8 = undefined;
    const h = zeroHeader(0, 0, "tkaudt");

    const payloads = [_]AuditEvent.Payload{
        .{ .source_event = .{
            .source_system = [_]u8{0} ** 16,
            .event_type = [_]u8{0} ** 32,
            .raw_hash = 1,
        } },
        .{ .normalization = .{
            .source_event_hash = 0,
            .normalized_hash = 0,
            .canonical_event_type = [_]u8{0} ** 32,
        } },
        .{ .policy_decision = .{
            .outcome = .deny,
            .rule_id = 1,
            .failed_scope_dim = [_]u8{0} ** 32,
            .source_event_hash = 0,
        } },
        .{ .model_call = .{
            .model_id = [_]u8{0} ** 32,
            .prompt_hash = 0,
            .response_hash = 0,
            .token_estimate = 0,
            .retry_count = 0,
        } },
        .{ .financial_adapter_call = .{
            .adapter_id = [_]u8{0} ** 16,
            .request_hash = 0,
            .response_hash = 0,
            .fixture_id = 0,
        } },
        .{ .proposal = .{
            .proposal_type = [_]u8{0} ** 32,
            .proposal_hash = 0,
            .approval_state = 0,
        } },
        .{ .destination_check = .{
            .destination_type = [_]u8{0} ** 16,
            .allowlist_version = 0,
            .outcome = .allow,
        } },
        .{ .limit_check = .{
            .limit_type = .amount,
            .value = 100,
            .limit = 1000,
            .outcome = .allow,
        } },
        .{ .approval_required = .{
            .action_class = [_]u8{0} ** 32,
            .approval_path = [_]u8{0} ** 32,
            .proposal_hash = 0,
        } },
        .{ .denial = .{
            .action_class = [_]u8{0} ** 32,
            .reason_code = 0,
            .failed_scope_dim = [_]u8{0} ** 32,
        } },
        .{ .telemetry_checkpoint = .{
            .metric_set_hash = 0,
            .source_offset_watermark = 0,
        } },
        .{ .replay_result = .{
            .capsule_id = 0,
            .divergences = 0,
            .first_divergent_seq = 0,
        } },
    };

    for (payloads) |payload| {
        const event = buildEvent(h, payload);
        const line = try formatJsonl(&buf, event);
        try std.testing.expect(std.mem.startsWith(u8, line, "{\"schema_version\":1,"));
        try std.testing.expect(std.mem.endsWith(u8, line, "}\n"));
    }
}
