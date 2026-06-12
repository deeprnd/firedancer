/// Canonical audit record schema for Tickoni tiles.
///
/// Every material boundary event is a typed AuditEvent so replay and
/// investigation do not depend on logs or UI state.
const std = @import("std");
const audit_codec = @import("audit_cabi");

pub const audit_schema_version: u16 = 1;

pub const max_binary_len: usize = 256;

pub const PolicyOutcome = enum(u8) {
    allow,
    deny,
    require_approval,
    malformed_drop,
    duplicate_drop,
    escalate,
    require_more_evidence,
};

pub const LimitType = enum(u8) {
    amount,
    frequency,
    holding_period,
    per_day,
    per_month,
};

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

pub const PolicyDecisionPayload = struct {
    outcome: PolicyOutcome,
    rule_id: u32,
    failed_scope_dim: [32]u8,
    source_event_hash: u64,
};

pub const ModelCallPayload = struct {
    model_id: [32]u8,
    prompt_hash: u64,
    response_hash: u64,
    token_estimate: u32,
    retry_count: u8,
};

pub const FinancialAdapterCallPayload = struct {
    adapter_id: [16]u8,
    request_hash: u64,
    response_hash: u64,
    fixture_id: u32,
};

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

pub const ParsedBinary = struct {
    event: AuditEvent,
    consumed_len: usize,
};

pub fn buildEvent(header_without_hash: Header, payload: AuditEvent.Payload) AuditEvent {
    var event = AuditEvent{ .header = header_without_hash, .payload = payload };
    event.header.record_hash = computeRecordHash(event);
    return event;
}

pub fn computeRecordHash(event: AuditEvent) u64 {
    const codec_event = toCodecEvent(event);
    return audit_codec.tk_audit_record_hash(&codec_event);
}

pub fn auditEventsEql(a: AuditEvent, b: AuditEvent) bool {
    var ah = a.header;
    var bh = b.header;
    ah.timestamp_ns = 0;
    bh.timestamp_ns = 0;
    return std.meta.eql(ah, bh) and std.meta.eql(a.payload, b.payload);
}

pub fn checkSchemaVersion(version: u16) error{UnknownSchemaVersion}!void {
    if (version > audit_schema_version) return error.UnknownSchemaVersion;
}

pub fn parseRecordType(tag: u8) error{UnknownRecordType}!RecordType {
    inline for (@typeInfo(RecordType).@"enum".fields) |field| {
        if (field.value == tag) return @field(RecordType, field.name);
    }
    return error.UnknownRecordType;
}

pub fn peekBinaryLen(input: []const u8) error{UnexpectedEof}!usize {
    var total_len: usize = 0;
    if (audit_codec.tk_audit_peek_binary_len(input.ptr, input.len, &total_len) != audit_codec.status_ok)
        return error.UnexpectedEof;
    return total_len;
}

pub fn formatBinary(buf: []u8, event: AuditEvent) ![]u8 {
    if (buf.len < @sizeOf(u32)) return error.NoSpaceLeft;
    var codec_event = toCodecEvent(event);
    var body_len: usize = 0;
    switch (audit_codec.tk_audit_format_protobuf(
        buf[@sizeOf(u32)..].ptr,
        buf.len - @sizeOf(u32),
        &codec_event,
        &body_len,
    )) {
        audit_codec.status_ok => {},
        audit_codec.status_no_space => return error.NoSpaceLeft,
        else => return error.InvalidBinaryRecord,
    }
    if (body_len > std.math.maxInt(u32)) return error.RecordTooLarge;
    std.mem.writeInt(u32, buf[0..@sizeOf(u32)], @intCast(body_len), .little);
    return buf[0 .. @sizeOf(u32) + body_len];
}

pub fn parseBinary(input: []const u8) !ParsedBinary {
    const consumed_len = try peekBinaryLen(input);
    if (input.len < consumed_len) return error.UnexpectedEof;
    var codec_event: audit_codec.Event = undefined;
    switch (audit_codec.tk_audit_parse_protobuf(
        input[@sizeOf(u32)..consumed_len].ptr,
        consumed_len - @sizeOf(u32),
        &codec_event,
    )) {
        audit_codec.status_ok => {},
        audit_codec.status_invalid_protobuf => return error.InvalidBinaryRecord,
        else => return error.InvalidBinaryRecord,
    }
    const event = try fromCodecEvent(codec_event);
    return .{ .event = event, .consumed_len = consumed_len };
}

fn toCodecEvent(event: AuditEvent) audit_codec.Event {
    return .{
        .header = .{
            .schema_version = event.header.schema_version,
            .seq = event.header.seq,
            .source_offset = event.header.source_offset,
            .tile_id = event.header.tile_id,
            .logical_actor_id = event.header.logical_actor_id,
            .policy_version = event.header.policy_version,
            .capability_envelope_id_le = @bitCast(event.header.capability_envelope_id),
            .timestamp_ns = event.header.timestamp_ns,
            .prev_hash = event.header.prev_hash,
            .record_hash = event.header.record_hash,
        },
        .record_type = @intFromEnum(std.meta.activeTag(event.payload)),
        .payload = payloadToCodec(event.payload),
    };
}

fn fromCodecEvent(codec_event: audit_codec.Event) !AuditEvent {
    try checkSchemaVersion(codec_event.header.schema_version);
    const record_type = try parseRecordType(codec_event.record_type);
    const payload = try payloadFromCodec(record_type, codec_event.payload);
    return validateParsedEvent(.{
        .header = .{
            .schema_version = codec_event.header.schema_version,
            .seq = codec_event.header.seq,
            .source_offset = codec_event.header.source_offset,
            .tile_id = codec_event.header.tile_id,
            .logical_actor_id = codec_event.header.logical_actor_id,
            .policy_version = codec_event.header.policy_version,
            .capability_envelope_id = @bitCast(codec_event.header.capability_envelope_id_le),
            .timestamp_ns = codec_event.header.timestamp_ns,
            .prev_hash = codec_event.header.prev_hash,
            .record_hash = codec_event.header.record_hash,
        },
        .payload = payload,
    });
}

fn payloadToCodec(payload: AuditEvent.Payload) audit_codec.Payload {
    return switch (payload) {
        .source_event => |p| .{ .source_event = .{
            .source_system = p.source_system,
            .event_type = p.event_type,
            .raw_hash = p.raw_hash,
        } },
        .normalization => |p| .{ .normalization = .{
            .source_event_hash = p.source_event_hash,
            .normalized_hash = p.normalized_hash,
            .canonical_event_type = p.canonical_event_type,
        } },
        .policy_decision => |p| .{ .policy_decision = .{
            .outcome = @intFromEnum(p.outcome),
            .rule_id = p.rule_id,
            .failed_scope_dim = p.failed_scope_dim,
            .source_event_hash = p.source_event_hash,
        } },
        .model_call => |p| .{ .model_call = .{
            .model_id = p.model_id,
            .prompt_hash = p.prompt_hash,
            .response_hash = p.response_hash,
            .token_estimate = p.token_estimate,
            .retry_count = p.retry_count,
        } },
        .financial_adapter_call => |p| .{ .financial_adapter_call = .{
            .adapter_id = p.adapter_id,
            .request_hash = p.request_hash,
            .response_hash = p.response_hash,
            .fixture_id = p.fixture_id,
        } },
        .proposal => |p| .{ .proposal = .{
            .proposal_type = p.proposal_type,
            .proposal_hash = p.proposal_hash,
            .approval_state = p.approval_state,
        } },
        .destination_check => |p| .{ .destination_check = .{
            .destination_type = p.destination_type,
            .allowlist_version = p.allowlist_version,
            .outcome = @intFromEnum(p.outcome),
        } },
        .limit_check => |p| .{ .limit_check = .{
            .limit_type = @intFromEnum(p.limit_type),
            .value = p.value,
            .limit = p.limit,
            .outcome = @intFromEnum(p.outcome),
        } },
        .approval_required => |p| .{ .approval_required = .{
            .action_class = p.action_class,
            .approval_path = p.approval_path,
            .proposal_hash = p.proposal_hash,
        } },
        .denial => |p| .{ .denial = .{
            .action_class = p.action_class,
            .reason_code = p.reason_code,
            .failed_scope_dim = p.failed_scope_dim,
        } },
        .telemetry_checkpoint => |p| .{ .telemetry_checkpoint = .{
            .metric_set_hash = p.metric_set_hash,
            .source_offset_watermark = p.source_offset_watermark,
        } },
        .replay_result => |p| .{ .replay_result = .{
            .capsule_id = p.capsule_id,
            .divergences = p.divergences,
            .first_divergent_seq = p.first_divergent_seq,
        } },
    };
}

fn payloadFromCodec(record_type: RecordType, payload: audit_codec.Payload) !AuditEvent.Payload {
    return switch (record_type) {
        .source_event => .{ .source_event = .{
            .source_system = payload.source_event.source_system,
            .event_type = payload.source_event.event_type,
            .raw_hash = payload.source_event.raw_hash,
        } },
        .normalization => .{ .normalization = .{
            .source_event_hash = payload.normalization.source_event_hash,
            .normalized_hash = payload.normalization.normalized_hash,
            .canonical_event_type = payload.normalization.canonical_event_type,
        } },
        .policy_decision => .{ .policy_decision = .{
            .outcome = try parseEnumByValue(PolicyOutcome, payload.policy_decision.outcome),
            .rule_id = payload.policy_decision.rule_id,
            .failed_scope_dim = payload.policy_decision.failed_scope_dim,
            .source_event_hash = payload.policy_decision.source_event_hash,
        } },
        .model_call => .{ .model_call = .{
            .model_id = payload.model_call.model_id,
            .prompt_hash = payload.model_call.prompt_hash,
            .response_hash = payload.model_call.response_hash,
            .token_estimate = payload.model_call.token_estimate,
            .retry_count = payload.model_call.retry_count,
        } },
        .financial_adapter_call => .{ .financial_adapter_call = .{
            .adapter_id = payload.financial_adapter_call.adapter_id,
            .request_hash = payload.financial_adapter_call.request_hash,
            .response_hash = payload.financial_adapter_call.response_hash,
            .fixture_id = payload.financial_adapter_call.fixture_id,
        } },
        .proposal => .{ .proposal = .{
            .proposal_type = payload.proposal.proposal_type,
            .proposal_hash = payload.proposal.proposal_hash,
            .approval_state = payload.proposal.approval_state,
        } },
        .destination_check => .{ .destination_check = .{
            .destination_type = payload.destination_check.destination_type,
            .allowlist_version = payload.destination_check.allowlist_version,
            .outcome = try parseEnumByValue(PolicyOutcome, payload.destination_check.outcome),
        } },
        .limit_check => .{ .limit_check = .{
            .limit_type = try parseEnumByValue(LimitType, payload.limit_check.limit_type),
            .value = payload.limit_check.value,
            .limit = payload.limit_check.limit,
            .outcome = try parseEnumByValue(PolicyOutcome, payload.limit_check.outcome),
        } },
        .approval_required => .{ .approval_required = .{
            .action_class = payload.approval_required.action_class,
            .approval_path = payload.approval_required.approval_path,
            .proposal_hash = payload.approval_required.proposal_hash,
        } },
        .denial => .{ .denial = .{
            .action_class = payload.denial.action_class,
            .reason_code = payload.denial.reason_code,
            .failed_scope_dim = payload.denial.failed_scope_dim,
        } },
        .telemetry_checkpoint => .{ .telemetry_checkpoint = .{
            .metric_set_hash = payload.telemetry_checkpoint.metric_set_hash,
            .source_offset_watermark = payload.telemetry_checkpoint.source_offset_watermark,
        } },
        .replay_result => .{ .replay_result = .{
            .capsule_id = payload.replay_result.capsule_id,
            .divergences = payload.replay_result.divergences,
            .first_divergent_seq = payload.replay_result.first_divergent_seq,
        } },
    };
}

fn parseFixedAsciiBytes(comptime N: usize, value: []const u8) ![N]u8 {
    if (value.len > N) return error.StringTooLong;
    var out = [_]u8{0} ** N;
    for (value, 0..) |byte, idx| {
        if (byte < 0x20 or byte > 0x7e) return error.InvalidStringByte;
        out[idx] = byte;
    }
    return out;
}

fn validateParsedEvent(event: AuditEvent) !AuditEvent {
    const expected_hash = computeRecordHash(event);
    if (expected_hash != event.header.record_hash) return error.InvalidRecordHash;
    return event;
}

fn parseEnumByValue(comptime T: type, value: anytype) error{ UnknownRecordType, UnknownEnumValue }!T {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        if (field.value == value) return @field(T, field.name);
    }
    if (T == RecordType) return error.UnknownRecordType;
    return error.UnknownEnumValue;
}

fn fixtureHeader(
    seq: u64,
    source_offset: u64,
    tile_id: []const u8,
    logical_actor_id: u64,
    policy_version: []const u8,
    capability_envelope_id: u128,
    timestamp_ns: u64,
    prev_hash: u64,
) Header {
    return .{
        .schema_version = audit_schema_version,
        .seq = seq,
        .source_offset = source_offset,
        .tile_id = parseFixedAsciiBytes(6, tile_id) catch unreachable,
        .logical_actor_id = logical_actor_id,
        .policy_version = parseFixedAsciiBytes(32, policy_version) catch unreachable,
        .capability_envelope_id = capability_envelope_id,
        .timestamp_ns = timestamp_ns,
        .prev_hash = prev_hash,
        .record_hash = 0,
    };
}

fn makeFixtures() [12]AuditEvent {
    const headers = [_]Header{
        fixtureHeader(1, 10, "tkings", 1001, "policy_ingress_v1", 1, 111, 500),
        fixtureHeader(2, 11, "tknorm", 1002, "policy_norm_v1", 2, 222, 501),
        fixtureHeader(3, 12, "tkpoly", 1003, "policy_poly_v1", 3, 333, 502),
        fixtureHeader(4, 13, "tkmodl", 1004, "policy_model_v1", 4, 444, 503),
        fixtureHeader(5, 14, "tkadpt", 1005, "policy_adpt_v1", 5, 555, 504),
        fixtureHeader(6, 15, "tkagnt", 1006, "policy_prop_v1", 6, 666, 505),
        fixtureHeader(7, 16, "tkpoly", 1007, "policy_dest_v1", 7, 777, 506),
        fixtureHeader(8, 17, "tkpoly", 1008, "policy_limt_v1", 8, 888, 507),
        fixtureHeader(9, 18, "tkpoly", 1009, "policy_aprv_v1", 9, 999, 508),
        fixtureHeader(10, 19, "tkpoly", 1010, "policy_deny_v1", 10, 1110, 509),
        fixtureHeader(11, 20, "tkmetr", 1011, "policy_metr_v1", 11, 1221, 510),
        fixtureHeader(12, 21, "tkrepl", 1012, "policy_repl_v1", 12, 1332, 511),
    };

    const events = [_]AuditEvent{
        buildEvent(headers[0], .{ .source_event = .{
            .source_system = parseFixedAsciiBytes(16, "feed_alpha") catch unreachable,
            .event_type = parseFixedAsciiBytes(32, "payment_exception") catch unreachable,
            .raw_hash = 9001,
        } }),
        buildEvent(headers[1], .{ .normalization = .{
            .source_event_hash = 9001,
            .normalized_hash = 9002,
            .canonical_event_type = parseFixedAsciiBytes(32, "payment.normalized") catch unreachable,
        } }),
        buildEvent(headers[2], .{ .policy_decision = .{
            .outcome = .require_approval,
            .rule_id = 42,
            .failed_scope_dim = parseFixedAsciiBytes(32, "amount_limit") catch unreachable,
            .source_event_hash = 9002,
        } }),
        buildEvent(headers[3], .{ .model_call = .{
            .model_id = parseFixedAsciiBytes(32, "gpt_local_stub") catch unreachable,
            .prompt_hash = 9100,
            .response_hash = 9101,
            .token_estimate = 512,
            .retry_count = 2,
        } }),
        buildEvent(headers[4], .{ .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "broker_demo") catch unreachable,
            .request_hash = 9200,
            .response_hash = 9201,
            .fixture_id = 7,
        } }),
        buildEvent(headers[5], .{ .proposal = .{
            .proposal_type = parseFixedAsciiBytes(32, "trading_order.propose") catch unreachable,
            .proposal_hash = 9300,
            .approval_state = 1,
        } }),
        buildEvent(headers[6], .{ .destination_check = .{
            .destination_type = parseFixedAsciiBytes(16, "broker_account") catch unreachable,
            .allowlist_version = 8,
            .outcome = .allow,
        } }),
        buildEvent(headers[7], .{ .limit_check = .{
            .limit_type = .per_day,
            .value = 1200,
            .limit = 1000,
            .outcome = .deny,
        } }),
        buildEvent(headers[8], .{ .approval_required = .{
            .action_class = parseFixedAsciiBytes(32, "payment_retry.propose") catch unreachable,
            .approval_path = parseFixedAsciiBytes(32, "maker_checker") catch unreachable,
            .proposal_hash = 9300,
        } }),
        buildEvent(headers[9], .{ .denial = .{
            .action_class = parseFixedAsciiBytes(32, "trading_order.place") catch unreachable,
            .reason_code = 17,
            .failed_scope_dim = parseFixedAsciiBytes(32, "environment") catch unreachable,
        } }),
        buildEvent(headers[10], .{ .telemetry_checkpoint = .{
            .metric_set_hash = 9400,
            .source_offset_watermark = 41,
        } }),
        buildEvent(headers[11], .{ .replay_result = .{
            .capsule_id = 9500,
            .divergences = 3,
            .first_divergent_seq = 9,
        } }),
    };

    return events;
}

test "computeRecordHash excludes timestamp_ns" {
    const header = fixtureHeader(0, 0, "tkpoly", 0, "policy", 0, 0, 0);
    const payload = AuditEvent.Payload{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 2,
    } };
    var header_with_timestamp = header;
    header_with_timestamp.timestamp_ns = 999_999;
    const e0 = buildEvent(header, payload);
    const e1 = buildEvent(header_with_timestamp, payload);
    try std.testing.expectEqual(e0.header.record_hash, e1.header.record_hash);
}

test "hash chain mutation changes downstream records" {
    const first = buildEvent(fixtureHeader(0, 0, "tkpoly", 0, "policy", 0, 0, 0), .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 3,
    } });
    var second_header = fixtureHeader(1, 1, "tkpoly", 0, "policy", 0, 0, first.header.record_hash);
    const second = buildEvent(second_header, .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 3,
    } });

    const mutated_first = buildEvent(fixtureHeader(0, 9, "tkpoly", 0, "policy", 0, 0, 0), .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 3,
    } });
    second_header.prev_hash = mutated_first.header.record_hash;
    const mutated_second = buildEvent(second_header, second.payload);

    try std.testing.expect(first.header.record_hash != mutated_first.header.record_hash);
    try std.testing.expect(second.header.record_hash != mutated_second.header.record_hash);
}

test "binary and wire format pinned" {
    // Golden values generated by `just gen-audit-fixtures` and committed.
    // Any change to formatBinary, toCodecEvent, computeRecordHash, or the C
    // codec that affects output will break this test — including symmetric
    // bugs that cancel out in a round-trip. Update by running the generator.
    const golden = @import("audit_fixtures_gen").values;
    for (makeFixtures(), &golden) |event, g| {
        try std.testing.expectEqual(g.expected_hash, event.header.record_hash);
        var buf: [max_binary_len]u8 = undefined;
        const binary = try formatBinary(&buf, event);
        try std.testing.expectEqual(g.expected_binary_len, binary.len);
        try std.testing.expectEqualSlices(u8, g.expected_binary_bytes, binary);
    }
}

test "binary round-trip and hash consistency" {
    for (makeFixtures()) |event| {
        try std.testing.expectEqual(computeRecordHash(event), event.header.record_hash);

        var binary_buf: [max_binary_len]u8 = undefined;
        const binary = try formatBinary(&binary_buf, event);
        try std.testing.expectEqual(binary.len, try peekBinaryLen(binary));

        const parsed_binary = try parseBinary(binary);
        try std.testing.expectEqual(binary.len, parsed_binary.consumed_len);
        try std.testing.expect(auditEventsEql(event, parsed_binary.event));
    }
}

test "parseBinary rejects future schema version" {
    const event = makeFixtures()[0];
    var binary_buf: [max_binary_len]u8 = undefined;
    const binary = try formatBinary(&binary_buf, event);
    binary[@sizeOf(u32) + 1] = audit_schema_version + 1;
    try std.testing.expectError(error.UnknownSchemaVersion, parseBinary(binary));
}

test "fromCodecEvent rejects unknown record type" {
    // With the oneof encoding, record_type is derived from the field number
    // (fields 12–23 → types 0–11). The C decoder always produces 0–11 on
    // success, so UnknownRecordType cannot be triggered through binary
    // parsing. Test the Zig guard directly instead.
    const event = makeFixtures()[0];
    var codec_event = toCodecEvent(event);
    codec_event.record_type = 15;
    try std.testing.expectError(error.UnknownRecordType, fromCodecEvent(codec_event));
}

test "parseBinary rejects truncated record" {
    const event = makeFixtures()[0];
    var binary_buf: [max_binary_len]u8 = undefined;
    const binary = try formatBinary(&binary_buf, event);
    try std.testing.expectError(error.UnexpectedEof, parseBinary(binary[0 .. binary.len - 1]));
}

/// Prints computed hash and wire bytes for every fixture event to stderr.
/// Run with: just gen-audit-fixtures
/// Use the output to understand or snapshot the current encoding after intentional changes.
fn cwrite(f: *std.c.FILE, s: []const u8) void {
    _ = std.c.fwrite(s.ptr, 1, s.len, f);
}

fn writeFixtureFile() !void {
    const path = "src/tickoni/test/audit_fixtures_gen.zig";
    const f = std.c.fopen(path, "w") orelse return error.FileOpenFailed;
    defer _ = std.c.fclose(f);

    cwrite(f,
        \\// Auto-generated by `just gen-audit-fixtures`. Do not edit manually.
        \\pub const Fixture = struct {
        \\    expected_hash: u64,
        \\    expected_binary_len: usize,
        \\    expected_binary_bytes: []const u8,
        \\};
        \\
        \\pub const values = [12]Fixture{
        \\
    );

    var buf: [512]u8 = undefined;
    for (makeFixtures()) |event| {
        var binary_buf: [max_binary_len]u8 = undefined;
        const binary = try formatBinary(&binary_buf, event);
        cwrite(f, try std.fmt.bufPrint(
            &buf,
            "    .{{ .expected_hash = {d}, .expected_binary_len = {d}, .expected_binary_bytes = &.{{",
            .{ event.header.record_hash, binary.len },
        ));
        for (binary, 0..) |b, j| {
            const sep: []const u8 = if (j > 0) ", " else "";
            cwrite(f, try std.fmt.bufPrint(&buf, "{s}0x{X:0>2}", .{ sep, b }));
        }
        cwrite(f, "} },\n");
    }

    cwrite(f, "};\n");
    std.debug.print("wrote {s}\n", .{path});
}

test "gen audit fixture values" {
    // Skipped in normal runs; set TK_GEN_FIXTURES=1 to regenerate the golden file.
    // Run: just gen-audit-fixtures
    if (std.c.getenv("TK_GEN_FIXTURES") == null) return error.SkipZigTest;
    try writeFixtureFile();
}
