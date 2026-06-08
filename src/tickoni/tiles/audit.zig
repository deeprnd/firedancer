/// Canonical audit record schema for Tickoni tiles.
///
/// Every material boundary event is a typed AuditEvent so replay and
/// investigation do not depend on logs or UI state.
const std = @import("std");
const audit_codec = @import("audit_cabi");

pub const audit_schema_version: u16 = 1;
const hash_seed: u64 = 0xcbf29ce484222325;

pub const max_jsonl_len: usize = 2048;
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
    hashPayload(&h, event.payload);
    return h;
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
    if (input.len < @sizeOf(u32)) return error.UnexpectedEof;
    return @sizeOf(u32) + readIntFromSlice(u32, input[0..@sizeOf(u32)]);
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

pub fn formatJsonl(buf: []u8, event: AuditEvent) ![]u8 {
    var codec_event = toCodecEvent(event);
    var written: usize = 0;
    switch (audit_codec.tk_audit_format_jsonl(buf.ptr, buf.len, &codec_event, &written)) {
        audit_codec.status_ok => return buf[0..written],
        audit_codec.status_no_space => return error.NoSpaceLeft,
        audit_codec.status_invalid_field => return error.InvalidStringByte,
        else => return error.InvalidJsonRecord,
    }
}

pub fn parseJson(allocator: std.mem.Allocator, input: []const u8) !AuditEvent {
    const trimmed = std.mem.trimEnd(u8, input, "\r\n");
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidJsonRecord;
    const obj = parsed.value.object;

    const schema_version = try getJsonUnsigned(u16, obj, "schema_version");
    try checkSchemaVersion(schema_version);
    const record_type_name = try getJsonString(obj, "record_type");
    const record_type = try parseEnumByName(RecordType, record_type_name);

    const header = Header{
        .schema_version = schema_version,
        .seq = try getJsonUnsigned(u64, obj, "seq"),
        .source_offset = try getJsonUnsigned(u64, obj, "source_offset"),
        .tile_id = try getJsonFixedBytes(6, obj, "tile_id"),
        .logical_actor_id = try getJsonUnsigned(u64, obj, "logical_actor_id"),
        .policy_version = try getJsonFixedBytes(32, obj, "policy_version"),
        .capability_envelope_id = try getJsonUnsigned(u128, obj, "capability_envelope_id"),
        .timestamp_ns = try getJsonUnsigned(u64, obj, "timestamp_ns"),
        .prev_hash = try getJsonUnsigned(u64, obj, "prev_hash"),
        .record_hash = try getJsonUnsigned(u64, obj, "record_hash"),
    };

    const payload = try readJsonPayload(obj, record_type);
    return validateParsedEvent(.{ .header = header, .payload = payload });
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
            .capability_envelope_id_le = u128ToLeBytes(event.header.capability_envelope_id),
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
            .capability_envelope_id = leBytesToU128(codec_event.header.capability_envelope_id_le),
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

fn u128ToLeBytes(value: u128) [16]u8 {
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u128, &bytes, value, .little);
    return bytes;
}

fn leBytesToU128(bytes: [16]u8) u128 {
    return std.mem.readInt(u128, &bytes, .little);
}

const BinaryWriter = struct {
    buf: []u8,
    pos: usize,

    fn writeByte(self: *BinaryWriter, byte: u8) error{NoSpaceLeft}!void {
        if (self.pos >= self.buf.len) return error.NoSpaceLeft;
        self.buf[self.pos] = byte;
        self.pos += 1;
    }

    fn writeAll(self: *BinaryWriter, bytes: []const u8) error{NoSpaceLeft}!void {
        if (self.pos + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
    }

    fn writeIntLe(self: *BinaryWriter, comptime T: type, value: T) error{NoSpaceLeft}!void {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        try self.writeAll(&bytes);
    }
};

const BinaryReader = struct {
    buf: []const u8,
    pos: usize,

    fn readBytes(self: *BinaryReader, len: usize) error{UnexpectedEof}![]const u8 {
        if (self.pos + len > self.buf.len) return error.UnexpectedEof;
        const out = self.buf[self.pos..][0..len];
        self.pos += len;
        return out;
    }

    fn readFixedBytes(self: *BinaryReader, comptime N: usize) error{UnexpectedEof}![N]u8 {
        var out = [_]u8{0} ** N;
        const bytes = try self.readBytes(N);
        @memcpy(&out, bytes);
        return out;
    }

    fn readIntLe(self: *BinaryReader, comptime T: type) error{UnexpectedEof}!T {
        const bytes = try self.readBytes(@sizeOf(T));
        return readIntFromSlice(T, bytes);
    }

    fn done(self: *BinaryReader) bool {
        return self.pos == self.buf.len;
    }
};

const JsonWriter = struct {
    buf: []u8,
    pos: usize,

    fn print(self: *JsonWriter, comptime fmt: []const u8, args: anytype) error{NoSpaceLeft}!void {
        const written = try std.fmt.bufPrint(self.buf[self.pos..], fmt, args);
        self.pos += written.len;
    }

    fn writeByte(self: *JsonWriter, byte: u8) error{NoSpaceLeft}!void {
        if (self.pos >= self.buf.len) return error.NoSpaceLeft;
        self.buf[self.pos] = byte;
        self.pos += 1;
    }

    fn writeAll(self: *JsonWriter, bytes: []const u8) error{NoSpaceLeft}!void {
        if (self.pos + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
    }

    fn writeJsonString(self: *JsonWriter, value: []const u8) !void {
        try self.writeByte('"');
        for (value) |byte| {
            switch (byte) {
                '"', '\\' => {
                    try self.writeByte('\\');
                    try self.writeByte(byte);
                },
                0x00...0x1f, 0x7f...0xff => return error.InvalidStringByte,
                else => try self.writeByte(byte),
            }
        }
        try self.writeByte('"');
    }
};

fn writeBinaryHeader(w: *BinaryWriter, header: Header) !void {
    try w.writeIntLe(u64, header.seq);
    try w.writeIntLe(u64, header.source_offset);
    try w.writeAll(&header.tile_id);
    try w.writeIntLe(u64, header.logical_actor_id);
    try w.writeAll(&header.policy_version);
    try w.writeIntLe(u128, header.capability_envelope_id);
    try w.writeIntLe(u64, header.timestamp_ns);
    try w.writeIntLe(u64, header.prev_hash);
    try w.writeIntLe(u64, header.record_hash);
}

fn writeBinaryPayload(w: *BinaryWriter, payload: AuditEvent.Payload) !void {
    switch (payload) {
        .source_event => |p| {
            try w.writeAll(&p.source_system);
            try w.writeAll(&p.event_type);
            try w.writeIntLe(u64, p.raw_hash);
        },
        .normalization => |p| {
            try w.writeIntLe(u64, p.source_event_hash);
            try w.writeIntLe(u64, p.normalized_hash);
            try w.writeAll(&p.canonical_event_type);
        },
        .policy_decision => |p| {
            try w.writeIntLe(u8, @intFromEnum(p.outcome));
            try w.writeIntLe(u32, p.rule_id);
            try w.writeAll(&p.failed_scope_dim);
            try w.writeIntLe(u64, p.source_event_hash);
        },
        .model_call => |p| {
            try w.writeAll(&p.model_id);
            try w.writeIntLe(u64, p.prompt_hash);
            try w.writeIntLe(u64, p.response_hash);
            try w.writeIntLe(u32, p.token_estimate);
            try w.writeIntLe(u8, p.retry_count);
        },
        .financial_adapter_call => |p| {
            try w.writeAll(&p.adapter_id);
            try w.writeIntLe(u64, p.request_hash);
            try w.writeIntLe(u64, p.response_hash);
            try w.writeIntLe(u32, p.fixture_id);
        },
        .proposal => |p| {
            try w.writeAll(&p.proposal_type);
            try w.writeIntLe(u64, p.proposal_hash);
            try w.writeIntLe(u8, p.approval_state);
        },
        .destination_check => |p| {
            try w.writeAll(&p.destination_type);
            try w.writeIntLe(u32, p.allowlist_version);
            try w.writeIntLe(u8, @intFromEnum(p.outcome));
        },
        .limit_check => |p| {
            try w.writeIntLe(u8, @intFromEnum(p.limit_type));
            try w.writeIntLe(i64, p.value);
            try w.writeIntLe(i64, p.limit);
            try w.writeIntLe(u8, @intFromEnum(p.outcome));
        },
        .approval_required => |p| {
            try w.writeAll(&p.action_class);
            try w.writeAll(&p.approval_path);
            try w.writeIntLe(u64, p.proposal_hash);
        },
        .denial => |p| {
            try w.writeAll(&p.action_class);
            try w.writeIntLe(u32, p.reason_code);
            try w.writeAll(&p.failed_scope_dim);
        },
        .telemetry_checkpoint => |p| {
            try w.writeIntLe(u64, p.metric_set_hash);
            try w.writeIntLe(u64, p.source_offset_watermark);
        },
        .replay_result => |p| {
            try w.writeIntLe(u64, p.capsule_id);
            try w.writeIntLe(u64, p.divergences);
            try w.writeIntLe(u64, p.first_divergent_seq);
        },
    }
}

fn readBinaryHeader(r: *BinaryReader) !Header {
    return .{
        .schema_version = audit_schema_version,
        .seq = try r.readIntLe(u64),
        .source_offset = try r.readIntLe(u64),
        .tile_id = try r.readFixedBytes(6),
        .logical_actor_id = try r.readIntLe(u64),
        .policy_version = try r.readFixedBytes(32),
        .capability_envelope_id = try r.readIntLe(u128),
        .timestamp_ns = try r.readIntLe(u64),
        .prev_hash = try r.readIntLe(u64),
        .record_hash = try r.readIntLe(u64),
    };
}

fn readBinaryPayload(r: *BinaryReader, record_type: RecordType) !AuditEvent.Payload {
    return switch (record_type) {
        .source_event => .{ .source_event = .{
            .source_system = try r.readFixedBytes(16),
            .event_type = try r.readFixedBytes(32),
            .raw_hash = try r.readIntLe(u64),
        } },
        .normalization => .{ .normalization = .{
            .source_event_hash = try r.readIntLe(u64),
            .normalized_hash = try r.readIntLe(u64),
            .canonical_event_type = try r.readFixedBytes(32),
        } },
        .policy_decision => .{ .policy_decision = .{
            .outcome = try parseEnumByValue(PolicyOutcome, try r.readIntLe(u8)),
            .rule_id = try r.readIntLe(u32),
            .failed_scope_dim = try r.readFixedBytes(32),
            .source_event_hash = try r.readIntLe(u64),
        } },
        .model_call => .{ .model_call = .{
            .model_id = try r.readFixedBytes(32),
            .prompt_hash = try r.readIntLe(u64),
            .response_hash = try r.readIntLe(u64),
            .token_estimate = try r.readIntLe(u32),
            .retry_count = try r.readIntLe(u8),
        } },
        .financial_adapter_call => .{ .financial_adapter_call = .{
            .adapter_id = try r.readFixedBytes(16),
            .request_hash = try r.readIntLe(u64),
            .response_hash = try r.readIntLe(u64),
            .fixture_id = try r.readIntLe(u32),
        } },
        .proposal => .{ .proposal = .{
            .proposal_type = try r.readFixedBytes(32),
            .proposal_hash = try r.readIntLe(u64),
            .approval_state = try r.readIntLe(u8),
        } },
        .destination_check => .{ .destination_check = .{
            .destination_type = try r.readFixedBytes(16),
            .allowlist_version = try r.readIntLe(u32),
            .outcome = try parseEnumByValue(PolicyOutcome, try r.readIntLe(u8)),
        } },
        .limit_check => .{ .limit_check = .{
            .limit_type = try parseEnumByValue(LimitType, try r.readIntLe(u8)),
            .value = try r.readIntLe(i64),
            .limit = try r.readIntLe(i64),
            .outcome = try parseEnumByValue(PolicyOutcome, try r.readIntLe(u8)),
        } },
        .approval_required => .{ .approval_required = .{
            .action_class = try r.readFixedBytes(32),
            .approval_path = try r.readFixedBytes(32),
            .proposal_hash = try r.readIntLe(u64),
        } },
        .denial => .{ .denial = .{
            .action_class = try r.readFixedBytes(32),
            .reason_code = try r.readIntLe(u32),
            .failed_scope_dim = try r.readFixedBytes(32),
        } },
        .telemetry_checkpoint => .{ .telemetry_checkpoint = .{
            .metric_set_hash = try r.readIntLe(u64),
            .source_offset_watermark = try r.readIntLe(u64),
        } },
        .replay_result => .{ .replay_result = .{
            .capsule_id = try r.readIntLe(u64),
            .divergences = try r.readIntLe(u64),
            .first_divergent_seq = try r.readIntLe(u64),
        } },
    };
}

fn writeJsonHeader(w: *JsonWriter, header: Header, record_type_name: []const u8) !void {
    try writeJsonKeyNumber(w, true, "schema_version", header.schema_version);
    try writeJsonKeyString(w, false, "record_type", record_type_name);
    try writeJsonKeyNumber(w, false, "seq", header.seq);
    try writeJsonKeyNumber(w, false, "source_offset", header.source_offset);
    try writeJsonKeyTrimmedBytes(w, false, "tile_id", &header.tile_id);
    try writeJsonKeyNumber(w, false, "logical_actor_id", header.logical_actor_id);
    try writeJsonKeyTrimmedBytes(w, false, "policy_version", &header.policy_version);
    try writeJsonKeyNumber(w, false, "capability_envelope_id", header.capability_envelope_id);
    try writeJsonKeyNumber(w, false, "timestamp_ns", header.timestamp_ns);
    try writeJsonKeyNumber(w, false, "prev_hash", header.prev_hash);
    try writeJsonKeyNumber(w, false, "record_hash", header.record_hash);
}

fn writeJsonPayload(w: *JsonWriter, payload: AuditEvent.Payload) !void {
    switch (payload) {
        .source_event => |p| {
            try writeJsonKeyTrimmedBytes(w, false, "source_system", &p.source_system);
            try writeJsonKeyTrimmedBytes(w, false, "event_type", &p.event_type);
            try writeJsonKeyNumber(w, false, "raw_hash", p.raw_hash);
        },
        .normalization => |p| {
            try writeJsonKeyNumber(w, false, "source_event_hash", p.source_event_hash);
            try writeJsonKeyNumber(w, false, "normalized_hash", p.normalized_hash);
            try writeJsonKeyTrimmedBytes(w, false, "canonical_event_type", &p.canonical_event_type);
        },
        .policy_decision => |p| {
            try writeJsonKeyString(w, false, "outcome", @tagName(p.outcome));
            try writeJsonKeyNumber(w, false, "rule_id", p.rule_id);
            try writeJsonKeyTrimmedBytes(w, false, "failed_scope_dim", &p.failed_scope_dim);
            try writeJsonKeyNumber(w, false, "source_event_hash", p.source_event_hash);
        },
        .model_call => |p| {
            try writeJsonKeyTrimmedBytes(w, false, "model_id", &p.model_id);
            try writeJsonKeyNumber(w, false, "prompt_hash", p.prompt_hash);
            try writeJsonKeyNumber(w, false, "response_hash", p.response_hash);
            try writeJsonKeyNumber(w, false, "token_estimate", p.token_estimate);
            try writeJsonKeyNumber(w, false, "retry_count", p.retry_count);
        },
        .financial_adapter_call => |p| {
            try writeJsonKeyTrimmedBytes(w, false, "adapter_id", &p.adapter_id);
            try writeJsonKeyNumber(w, false, "request_hash", p.request_hash);
            try writeJsonKeyNumber(w, false, "response_hash", p.response_hash);
            try writeJsonKeyNumber(w, false, "fixture_id", p.fixture_id);
        },
        .proposal => |p| {
            try writeJsonKeyTrimmedBytes(w, false, "proposal_type", &p.proposal_type);
            try writeJsonKeyNumber(w, false, "proposal_hash", p.proposal_hash);
            try writeJsonKeyNumber(w, false, "approval_state", p.approval_state);
        },
        .destination_check => |p| {
            try writeJsonKeyTrimmedBytes(w, false, "destination_type", &p.destination_type);
            try writeJsonKeyNumber(w, false, "allowlist_version", p.allowlist_version);
            try writeJsonKeyString(w, false, "outcome", @tagName(p.outcome));
        },
        .limit_check => |p| {
            try writeJsonKeyString(w, false, "limit_type", @tagName(p.limit_type));
            try writeJsonKeyNumber(w, false, "value", p.value);
            try writeJsonKeyNumber(w, false, "limit", p.limit);
            try writeJsonKeyString(w, false, "outcome", @tagName(p.outcome));
        },
        .approval_required => |p| {
            try writeJsonKeyTrimmedBytes(w, false, "action_class", &p.action_class);
            try writeJsonKeyTrimmedBytes(w, false, "approval_path", &p.approval_path);
            try writeJsonKeyNumber(w, false, "proposal_hash", p.proposal_hash);
        },
        .denial => |p| {
            try writeJsonKeyTrimmedBytes(w, false, "action_class", &p.action_class);
            try writeJsonKeyNumber(w, false, "reason_code", p.reason_code);
            try writeJsonKeyTrimmedBytes(w, false, "failed_scope_dim", &p.failed_scope_dim);
        },
        .telemetry_checkpoint => |p| {
            try writeJsonKeyNumber(w, false, "metric_set_hash", p.metric_set_hash);
            try writeJsonKeyNumber(w, false, "source_offset_watermark", p.source_offset_watermark);
        },
        .replay_result => |p| {
            try writeJsonKeyNumber(w, false, "capsule_id", p.capsule_id);
            try writeJsonKeyNumber(w, false, "divergences", p.divergences);
            try writeJsonKeyNumber(w, false, "first_divergent_seq", p.first_divergent_seq);
        },
    }
}

fn readJsonPayload(obj: std.json.ObjectMap, record_type: RecordType) !AuditEvent.Payload {
    return switch (record_type) {
        .source_event => .{ .source_event = .{
            .source_system = try getJsonFixedBytes(16, obj, "source_system"),
            .event_type = try getJsonFixedBytes(32, obj, "event_type"),
            .raw_hash = try getJsonUnsigned(u64, obj, "raw_hash"),
        } },
        .normalization => .{ .normalization = .{
            .source_event_hash = try getJsonUnsigned(u64, obj, "source_event_hash"),
            .normalized_hash = try getJsonUnsigned(u64, obj, "normalized_hash"),
            .canonical_event_type = try getJsonFixedBytes(32, obj, "canonical_event_type"),
        } },
        .policy_decision => .{ .policy_decision = .{
            .outcome = try getJsonEnum(PolicyOutcome, obj, "outcome"),
            .rule_id = try getJsonUnsigned(u32, obj, "rule_id"),
            .failed_scope_dim = try getJsonFixedBytes(32, obj, "failed_scope_dim"),
            .source_event_hash = try getJsonUnsigned(u64, obj, "source_event_hash"),
        } },
        .model_call => .{ .model_call = .{
            .model_id = try getJsonFixedBytes(32, obj, "model_id"),
            .prompt_hash = try getJsonUnsigned(u64, obj, "prompt_hash"),
            .response_hash = try getJsonUnsigned(u64, obj, "response_hash"),
            .token_estimate = try getJsonUnsigned(u32, obj, "token_estimate"),
            .retry_count = try getJsonUnsigned(u8, obj, "retry_count"),
        } },
        .financial_adapter_call => .{ .financial_adapter_call = .{
            .adapter_id = try getJsonFixedBytes(16, obj, "adapter_id"),
            .request_hash = try getJsonUnsigned(u64, obj, "request_hash"),
            .response_hash = try getJsonUnsigned(u64, obj, "response_hash"),
            .fixture_id = try getJsonUnsigned(u32, obj, "fixture_id"),
        } },
        .proposal => .{ .proposal = .{
            .proposal_type = try getJsonFixedBytes(32, obj, "proposal_type"),
            .proposal_hash = try getJsonUnsigned(u64, obj, "proposal_hash"),
            .approval_state = try getJsonUnsigned(u8, obj, "approval_state"),
        } },
        .destination_check => .{ .destination_check = .{
            .destination_type = try getJsonFixedBytes(16, obj, "destination_type"),
            .allowlist_version = try getJsonUnsigned(u32, obj, "allowlist_version"),
            .outcome = try getJsonEnum(PolicyOutcome, obj, "outcome"),
        } },
        .limit_check => .{ .limit_check = .{
            .limit_type = try getJsonEnum(LimitType, obj, "limit_type"),
            .value = try getJsonSigned(i64, obj, "value"),
            .limit = try getJsonSigned(i64, obj, "limit"),
            .outcome = try getJsonEnum(PolicyOutcome, obj, "outcome"),
        } },
        .approval_required => .{ .approval_required = .{
            .action_class = try getJsonFixedBytes(32, obj, "action_class"),
            .approval_path = try getJsonFixedBytes(32, obj, "approval_path"),
            .proposal_hash = try getJsonUnsigned(u64, obj, "proposal_hash"),
        } },
        .denial => .{ .denial = .{
            .action_class = try getJsonFixedBytes(32, obj, "action_class"),
            .reason_code = try getJsonUnsigned(u32, obj, "reason_code"),
            .failed_scope_dim = try getJsonFixedBytes(32, obj, "failed_scope_dim"),
        } },
        .telemetry_checkpoint => .{ .telemetry_checkpoint = .{
            .metric_set_hash = try getJsonUnsigned(u64, obj, "metric_set_hash"),
            .source_offset_watermark = try getJsonUnsigned(u64, obj, "source_offset_watermark"),
        } },
        .replay_result => .{ .replay_result = .{
            .capsule_id = try getJsonUnsigned(u64, obj, "capsule_id"),
            .divergences = try getJsonUnsigned(u64, obj, "divergences"),
            .first_divergent_seq = try getJsonUnsigned(u64, obj, "first_divergent_seq"),
        } },
    };
}

fn writeJsonKeyNumber(w: *JsonWriter, first: bool, key: []const u8, value: anytype) !void {
    if (!first) try w.writeByte(',');
    try w.writeJsonString(key);
    try w.writeByte(':');
    try w.print("{d}", .{value});
}

fn writeJsonKeyString(w: *JsonWriter, first: bool, key: []const u8, value: []const u8) !void {
    if (!first) try w.writeByte(',');
    try w.writeJsonString(key);
    try w.writeByte(':');
    try w.writeJsonString(value);
}

fn writeJsonKeyTrimmedBytes(w: *JsonWriter, first: bool, key: []const u8, value: []const u8) !void {
    try writeJsonKeyString(w, first, key, trimmedBytes(value));
}

fn getJsonValue(obj: std.json.ObjectMap, key: []const u8) error{MissingField}!std.json.Value {
    return obj.get(key) orelse error.MissingField;
}

fn getJsonString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    return switch (try getJsonValue(obj, key)) {
        .string => |s| s,
        else => error.InvalidJsonField,
    };
}

fn getJsonUnsigned(comptime T: type, obj: std.json.ObjectMap, key: []const u8) !T {
    return parseJsonUnsigned(T, try getJsonValue(obj, key));
}

fn getJsonSigned(comptime T: type, obj: std.json.ObjectMap, key: []const u8) !T {
    return parseJsonSigned(T, try getJsonValue(obj, key));
}

fn getJsonEnum(comptime T: type, obj: std.json.ObjectMap, key: []const u8) !T {
    return parseEnumByName(T, try getJsonString(obj, key));
}

fn getJsonFixedBytes(comptime N: usize, obj: std.json.ObjectMap, key: []const u8) ![N]u8 {
    return parseFixedAsciiBytes(N, try getJsonString(obj, key));
}

fn parseJsonUnsigned(comptime T: type, value: std.json.Value) !T {
    return switch (value) {
        .integer => |integer| blk: {
            if (integer < 0) return error.InvalidJsonField;
            break :blk std.math.cast(T, integer) orelse return error.InvalidJsonField;
        },
        .number_string => |s| std.fmt.parseInt(T, s, 10) catch return error.InvalidJsonField,
        else => error.InvalidJsonField,
    };
}

fn parseJsonSigned(comptime T: type, value: std.json.Value) !T {
    return switch (value) {
        .integer => |integer| std.math.cast(T, integer) orelse return error.InvalidJsonField,
        .number_string => |s| std.fmt.parseInt(T, s, 10) catch return error.InvalidJsonField,
        else => error.InvalidJsonField,
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

fn hashPayload(h: *u64, payload: AuditEvent.Payload) void {
    switch (payload) {
        .source_event => |p| {
            hashBytes(h, &p.source_system);
            hashBytes(h, &p.event_type);
            hashU64(h, p.raw_hash);
        },
        .normalization => |p| {
            hashU64(h, p.source_event_hash);
            hashU64(h, p.normalized_hash);
            hashBytes(h, &p.canonical_event_type);
        },
        .policy_decision => |p| {
            hashU8(h, @intFromEnum(p.outcome));
            hashU32(h, p.rule_id);
            hashBytes(h, &p.failed_scope_dim);
            hashU64(h, p.source_event_hash);
        },
        .model_call => |p| {
            hashBytes(h, &p.model_id);
            hashU64(h, p.prompt_hash);
            hashU64(h, p.response_hash);
            hashU32(h, p.token_estimate);
            hashU8(h, p.retry_count);
        },
        .financial_adapter_call => |p| {
            hashBytes(h, &p.adapter_id);
            hashU64(h, p.request_hash);
            hashU64(h, p.response_hash);
            hashU32(h, p.fixture_id);
        },
        .proposal => |p| {
            hashBytes(h, &p.proposal_type);
            hashU64(h, p.proposal_hash);
            hashU8(h, p.approval_state);
        },
        .destination_check => |p| {
            hashBytes(h, &p.destination_type);
            hashU32(h, p.allowlist_version);
            hashU8(h, @intFromEnum(p.outcome));
        },
        .limit_check => |p| {
            hashU8(h, @intFromEnum(p.limit_type));
            hashI64(h, p.value);
            hashI64(h, p.limit);
            hashU8(h, @intFromEnum(p.outcome));
        },
        .approval_required => |p| {
            hashBytes(h, &p.action_class);
            hashBytes(h, &p.approval_path);
            hashU64(h, p.proposal_hash);
        },
        .denial => |p| {
            hashBytes(h, &p.action_class);
            hashU32(h, p.reason_code);
            hashBytes(h, &p.failed_scope_dim);
        },
        .telemetry_checkpoint => |p| {
            hashU64(h, p.metric_set_hash);
            hashU64(h, p.source_offset_watermark);
        },
        .replay_result => |p| {
            hashU64(h, p.capsule_id);
            hashU64(h, p.divergences);
            hashU64(h, p.first_divergent_seq);
        },
    }
}

fn parseEnumByValue(comptime T: type, value: anytype) error{ UnknownRecordType, UnknownEnumValue }!T {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        if (field.value == value) return @field(T, field.name);
    }
    if (T == RecordType) return error.UnknownRecordType;
    return error.UnknownEnumValue;
}

fn parseEnumByName(comptime T: type, name: []const u8) error{ UnknownRecordType, UnknownEnumValue }!T {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return @field(T, field.name);
    }
    if (T == RecordType) return error.UnknownRecordType;
    return error.UnknownEnumValue;
}

fn trimmedBytes(bytes: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    return bytes[0..end];
}

fn readIntFromSlice(comptime T: type, bytes: []const u8) T {
    var array: [@sizeOf(T)]u8 = undefined;
    @memcpy(&array, bytes);
    return std.mem.readInt(T, &array, .little);
}

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

const FixtureSpec = struct {
    event: AuditEvent,
    expected_hash: u64,
    expected_json: []const u8,
    expected_binary_len: usize,
};

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

fn makeFixtures() [12]FixtureSpec {
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

    return .{
        .{
            .event = events[0],
            .expected_hash = 9067401012303657398,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"source_event\",\"seq\":1,\"source_offset\":10,\"tile_id\":\"tkings\",\"logical_actor_id\":1001,\"policy_version\":\"policy_ingress_v1\",\"capability_envelope_id\":1,\"timestamp_ns\":111,\"prev_hash\":500,\"record_hash\":9067401012303657398,\"source_system\":\"feed_alpha\",\"event_type\":\"payment_exception\",\"raw_hash\":9001}\n",
            .expected_binary_len = 115,
        },
        .{
            .event = events[1],
            .expected_hash = 6918337723137924779,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"normalization\",\"seq\":2,\"source_offset\":11,\"tile_id\":\"tknorm\",\"logical_actor_id\":1002,\"policy_version\":\"policy_norm_v1\",\"capability_envelope_id\":2,\"timestamp_ns\":222,\"prev_hash\":501,\"record_hash\":6918337723137924779,\"source_event_hash\":9001,\"normalized_hash\":9002,\"canonical_event_type\":\"payment.normalized\"}\n",
            .expected_binary_len = 105,
        },
        .{
            .event = events[2],
            .expected_hash = 7411971109969488810,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"policy_decision\",\"seq\":3,\"source_offset\":12,\"tile_id\":\"tkpoly\",\"logical_actor_id\":1003,\"policy_version\":\"policy_poly_v1\",\"capability_envelope_id\":3,\"timestamp_ns\":333,\"prev_hash\":502,\"record_hash\":7411971109969488810,\"outcome\":\"require_approval\",\"rule_id\":42,\"failed_scope_dim\":\"amount_limit\",\"source_event_hash\":9002}\n",
            .expected_binary_len = 100,
        },
        .{
            .event = events[3],
            .expected_hash = 3979198928737662599,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"model_call\",\"seq\":4,\"source_offset\":13,\"tile_id\":\"tkmodl\",\"logical_actor_id\":1004,\"policy_version\":\"policy_model_v1\",\"capability_envelope_id\":4,\"timestamp_ns\":444,\"prev_hash\":503,\"record_hash\":3979198928737662599,\"model_id\":\"gpt_local_stub\",\"prompt_hash\":9100,\"response_hash\":9101,\"token_estimate\":512,\"retry_count\":2}\n",
            .expected_binary_len = 107,
        },
        .{
            .event = events[4],
            .expected_hash = 6681056275576866608,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"financial_adapter_call\",\"seq\":5,\"source_offset\":14,\"tile_id\":\"tkadpt\",\"logical_actor_id\":1005,\"policy_version\":\"policy_adpt_v1\",\"capability_envelope_id\":5,\"timestamp_ns\":555,\"prev_hash\":504,\"record_hash\":6681056275576866608,\"adapter_id\":\"broker_demo\",\"request_hash\":9200,\"response_hash\":9201,\"fixture_id\":7}\n",
            .expected_binary_len = 100,
        },
        .{
            .event = events[5],
            .expected_hash = 5907408996459572371,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"proposal\",\"seq\":6,\"source_offset\":15,\"tile_id\":\"tkagnt\",\"logical_actor_id\":1006,\"policy_version\":\"policy_prop_v1\",\"capability_envelope_id\":6,\"timestamp_ns\":666,\"prev_hash\":505,\"record_hash\":5907408996459572371,\"proposal_type\":\"trading_order.propose\",\"proposal_hash\":9300,\"approval_state\":1}\n",
            .expected_binary_len = 107,
        },
        .{
            .event = events[6],
            .expected_hash = 4167997239744904552,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"destination_check\",\"seq\":7,\"source_offset\":16,\"tile_id\":\"tkpoly\",\"logical_actor_id\":1007,\"policy_version\":\"policy_dest_v1\",\"capability_envelope_id\":7,\"timestamp_ns\":777,\"prev_hash\":506,\"record_hash\":4167997239744904552,\"destination_type\":\"broker_account\",\"allowlist_version\":8,\"outcome\":\"allow\"}\n",
            .expected_binary_len = 99,
        },
        .{
            .event = events[7],
            .expected_hash = 768806302014049322,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"limit_check\",\"seq\":8,\"source_offset\":17,\"tile_id\":\"tkpoly\",\"logical_actor_id\":1008,\"policy_version\":\"policy_limt_v1\",\"capability_envelope_id\":8,\"timestamp_ns\":888,\"prev_hash\":507,\"record_hash\":768806302014049322,\"limit_type\":\"per_day\",\"value\":1200,\"limit\":1000,\"outcome\":\"deny\"}\n",
            .expected_binary_len = 89,
        },
        .{
            .event = events[8],
            .expected_hash = 6653273299180568845,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"approval_required\",\"seq\":9,\"source_offset\":18,\"tile_id\":\"tkpoly\",\"logical_actor_id\":1009,\"policy_version\":\"policy_aprv_v1\",\"capability_envelope_id\":9,\"timestamp_ns\":999,\"prev_hash\":508,\"record_hash\":6653273299180568845,\"action_class\":\"payment_retry.propose\",\"approval_path\":\"maker_checker\",\"proposal_hash\":9300}\n",
            .expected_binary_len = 120,
        },
        .{
            .event = events[9],
            .expected_hash = 9533858372233767222,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"denial\",\"seq\":10,\"source_offset\":19,\"tile_id\":\"tkpoly\",\"logical_actor_id\":1010,\"policy_version\":\"policy_deny_v1\",\"capability_envelope_id\":10,\"timestamp_ns\":1110,\"prev_hash\":509,\"record_hash\":9533858372233767222,\"action_class\":\"trading_order.place\",\"reason_code\":17,\"failed_scope_dim\":\"environment\"}\n",
            .expected_binary_len = 116,
        },
        .{
            .event = events[10],
            .expected_hash = 15048564978396858322,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"telemetry_checkpoint\",\"seq\":11,\"source_offset\":20,\"tile_id\":\"tkmetr\",\"logical_actor_id\":1011,\"policy_version\":\"policy_metr_v1\",\"capability_envelope_id\":11,\"timestamp_ns\":1221,\"prev_hash\":510,\"record_hash\":15048564978396858322,\"metric_set_hash\":9400,\"source_offset_watermark\":41}\n",
            .expected_binary_len = 85,
        },
        .{
            .event = events[11],
            .expected_hash = 10647979821608911434,
            .expected_json = "{\"schema_version\":1,\"record_type\":\"replay_result\",\"seq\":12,\"source_offset\":21,\"tile_id\":\"tkrepl\",\"logical_actor_id\":1012,\"policy_version\":\"policy_repl_v1\",\"capability_envelope_id\":12,\"timestamp_ns\":1332,\"prev_hash\":511,\"record_hash\":10647979821608911434,\"capsule_id\":9500,\"divergences\":3,\"first_divergent_seq\":9}\n",
            .expected_binary_len = 87,
        },
    };
}

test "computeRecordHash excludes timestamp_ns" {
    const header = fixtureHeader(0, 0, "tkpoly", 0, "policy", 0, 0, hash_seed);
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
    const first = buildEvent(fixtureHeader(0, 0, "tkpoly", 0, "policy", 0, 0, hash_seed), .{ .policy_decision = .{
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

    const mutated_first = buildEvent(fixtureHeader(0, 9, "tkpoly", 0, "policy", 0, 0, hash_seed), .{ .policy_decision = .{
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

test "binary and json fixtures are pinned and round-trip" {
    const fixtures = makeFixtures();
    for (fixtures) |fixture| {
        try std.testing.expectEqual(fixture.expected_hash, fixture.event.header.record_hash);

        var json_buf: [max_jsonl_len]u8 = undefined;
        const json_line = try formatJsonl(&json_buf, fixture.event);
        try std.testing.expectEqualStrings(fixture.expected_json, json_line);

        var binary_buf: [max_binary_len]u8 = undefined;
        const binary = try formatBinary(&binary_buf, fixture.event);
        try std.testing.expectEqual(fixture.expected_binary_len, binary.len);
        try std.testing.expectEqual(binary.len, try peekBinaryLen(binary));

        const parsed_binary = try parseBinary(binary);
        try std.testing.expectEqual(binary.len, parsed_binary.consumed_len);
        try std.testing.expect(auditEventsEql(fixture.event, parsed_binary.event));

        const parsed_json = try parseJson(std.testing.allocator, json_line);
        try std.testing.expect(auditEventsEql(fixture.event, parsed_json));
    }
}

test "parseBinary rejects future schema version" {
    const fixture = makeFixtures()[0];
    var binary_buf: [max_binary_len]u8 = undefined;
    const binary = try formatBinary(&binary_buf, fixture.event);
    binary[@sizeOf(u32) + 1] = audit_schema_version + 1;
    try std.testing.expectError(error.UnknownSchemaVersion, parseBinary(binary));
}

test "parseBinary rejects unknown record type" {
    const fixture = makeFixtures()[0];
    var binary_buf: [max_binary_len]u8 = undefined;
    const binary = try formatBinary(&binary_buf, fixture.event);
    binary[@sizeOf(u32) + 3] = 15;
    try std.testing.expectError(error.UnknownRecordType, parseBinary(binary));
}

test "parseBinary rejects truncated record" {
    const fixture = makeFixtures()[0];
    var binary_buf: [max_binary_len]u8 = undefined;
    const binary = try formatBinary(&binary_buf, fixture.event);
    try std.testing.expectError(error.UnexpectedEof, parseBinary(binary[0 .. binary.len - 1]));
}

test "parseJson rejects future schema version" {
    try std.testing.expectError(
        error.UnknownSchemaVersion,
        parseJson(std.testing.allocator, "{\"schema_version\":9999,\"record_type\":\"source_event\"}\n"),
    );
}

test "parseJson rejects unknown record type" {
    try std.testing.expectError(
        error.UnknownRecordType,
        parseJson(
            std.testing.allocator,
            "{\"schema_version\":1,\"record_type\":\"unknown\",\"seq\":0,\"source_offset\":0,\"tile_id\":\"tkings\",\"logical_actor_id\":0,\"policy_version\":\"p\",\"capability_envelope_id\":0,\"timestamp_ns\":0,\"prev_hash\":0,\"record_hash\":0}\n",
        ),
    );
}

test "parseJson ignores unknown keys" {
    const fixture = makeFixtures()[2];
    var json_buf: [max_jsonl_len]u8 = undefined;
    const json_line = try formatJsonl(&json_buf, fixture.event);
    var mutated: [max_jsonl_len]u8 = undefined;
    const suffix = ",\"ignored_key\":\"ignored\"}\n";
    const prefix = json_line[0 .. json_line.len - 2];
    @memcpy(mutated[0..prefix.len], prefix);
    @memcpy(mutated[prefix.len..][0..suffix.len], suffix);
    const parsed = try parseJson(std.testing.allocator, mutated[0 .. prefix.len + suffix.len]);
    try std.testing.expect(auditEventsEql(fixture.event, parsed));
}

test "formatJsonl escapes quotes and backslashes" {
    const event = buildEvent(fixtureHeader(100, 200, "tkings", 1, "policy", 0, 0, 1), .{ .source_event = .{
        .source_system = parseFixedAsciiBytes(16, "feed\\alpha") catch unreachable,
        .event_type = parseFixedAsciiBytes(32, "payment\"event") catch unreachable,
        .raw_hash = 7,
    } });
    var buf: [max_jsonl_len]u8 = undefined;
    const line = try formatJsonl(&buf, event);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"source_system\":\"feed\\\\alpha\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"event_type\":\"payment\\\"event\"") != null);
}
