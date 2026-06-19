const std = @import("std");
const audit_codec = @import("audit_cabi");
const schema = @import("schema.zig");

pub const max_binary_len: usize = 256;

pub const ParsedBinary = struct {
    event: schema.AuditEvent,
    consumed_len: usize,
};

pub fn buildEvent(header_without_hash: schema.Header, payload: schema.AuditEvent.Payload) schema.AuditEvent {
    var event = schema.AuditEvent{ .header = header_without_hash, .payload = payload };
    event.header.record_hash = computeRecordHash(event);
    return event;
}

pub fn computeRecordHash(event: schema.AuditEvent) u64 {
    const codec_event = toCodecEvent(event);
    return audit_codec.tk_audit_record_hash(&codec_event);
}

pub fn auditEventsEql(a: schema.AuditEvent, b: schema.AuditEvent) bool {
    var ah = a.header;
    var bh = b.header;
    ah.timestamp_ns = 0;
    bh.timestamp_ns = 0;
    return std.meta.eql(ah, bh) and std.meta.eql(a.payload, b.payload);
}

pub fn checkSchemaVersion(version: u16) error{UnknownSchemaVersion}!void {
    if (version > schema.audit_schema_version) return error.UnknownSchemaVersion;
}

pub fn parseRecordType(tag: u8) error{UnknownRecordType}!schema.RecordType {
    inline for (@typeInfo(schema.RecordType).@"enum".fields) |field| {
        if (field.value == tag) return @field(schema.RecordType, field.name);
    }
    return error.UnknownRecordType;
}

pub fn peekBinaryLen(input: []const u8) error{UnexpectedEof}!usize {
    var total_len: usize = 0;
    if (audit_codec.tk_audit_peek_binary_len(input.ptr, input.len, &total_len) != audit_codec.status_ok)
        return error.UnexpectedEof;
    return total_len;
}

pub fn formatBinary(buf: []u8, event: schema.AuditEvent) ![]u8 {
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

fn toCodecEvent(event: schema.AuditEvent) audit_codec.Event {
    return .{
        .header = .{
            .schema_version = event.header.schema_version,
            .run_id = event.header.run_id,
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

fn fromCodecEvent(codec_event: audit_codec.Event) !schema.AuditEvent {
    try checkSchemaVersion(codec_event.header.schema_version);
    const record_type = try parseRecordType(codec_event.record_type);
    const payload = try payloadFromCodec(record_type, codec_event.payload);
    return validateParsedEvent(.{
        .header = .{
            .schema_version = codec_event.header.schema_version,
            .run_id = codec_event.header.run_id,
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

fn payloadToCodec(payload: schema.AuditEvent.Payload) audit_codec.Payload {
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
            .actor_role = p.actor_role,
            .workflow = p.workflow,
            .policy_decision_id = p.policy_decision_id,
            .replay_substitution_id = p.replay_substitution_id,
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
        .deduplication => |p| .{ .deduplication = .{
            .idempotency_key = p.idempotency_key,
            .is_duplicate = @intFromBool(p.is_duplicate),
        } },
        .case_creation => |p| .{ .case_creation = .{
            .basket_id = p.basket_id,
            .instrument_count = p.instrument_count,
            .rejected_count = p.rejected_count,
            .total_allocated_cents = p.total_allocated_cents,
        } },
    };
}

fn payloadFromCodec(record_type: schema.RecordType, payload: audit_codec.Payload) !schema.AuditEvent.Payload {
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
            .outcome = try parseEnumByValue(schema.PolicyOutcome, payload.policy_decision.outcome),
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
            .actor_role = payload.model_call.actor_role,
            .workflow = payload.model_call.workflow,
            .policy_decision_id = payload.model_call.policy_decision_id,
            .replay_substitution_id = payload.model_call.replay_substitution_id,
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
            .outcome = try parseEnumByValue(schema.PolicyOutcome, payload.destination_check.outcome),
        } },
        .limit_check => .{ .limit_check = .{
            .limit_type = try parseEnumByValue(schema.LimitType, payload.limit_check.limit_type),
            .value = payload.limit_check.value,
            .limit = payload.limit_check.limit,
            .outcome = try parseEnumByValue(schema.PolicyOutcome, payload.limit_check.outcome),
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
        .deduplication => .{ .deduplication = .{
            .idempotency_key = payload.deduplication.idempotency_key,
            .is_duplicate = payload.deduplication.is_duplicate != 0,
        } },
        .case_creation => .{ .case_creation = .{
            .basket_id = payload.case_creation.basket_id,
            .instrument_count = payload.case_creation.instrument_count,
            .rejected_count = payload.case_creation.rejected_count,
            .total_allocated_cents = payload.case_creation.total_allocated_cents,
        } },
    };
}

fn validateParsedEvent(event: schema.AuditEvent) !schema.AuditEvent {
    const expected_hash = computeRecordHash(event);
    if (expected_hash != event.header.record_hash) return error.InvalidRecordHash;
    return event;
}

fn parseEnumByValue(comptime T: type, value: anytype) error{ UnknownRecordType, UnknownEnumValue }!T {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        if (field.value == value) return @field(T, field.name);
    }
    if (T == schema.RecordType) return error.UnknownRecordType;
    return error.UnknownEnumValue;
}

test "fromCodecEvent rejects unknown record type" {
    const fixtures = @import("fixtures.zig");

    const event = fixtures.makeFixtures()[0];
    var codec_event = toCodecEvent(event);
    codec_event.record_type = 15;
    try std.testing.expectError(error.UnknownRecordType, fromCodecEvent(codec_event));
}
