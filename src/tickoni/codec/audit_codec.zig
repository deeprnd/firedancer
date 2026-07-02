/// Narrow Zig extern bindings for the Tickoni audit codec C surface.
///
/// The implementation lives under src/tickoni/codec/ and reaches Firedancer
/// protobuf/hash/JSON primitives only through src/tickoni/c_abi/shim/**.
pub const status_ok: c_int = 0;
pub const status_no_space: c_int = 1;
pub const status_invalid_protobuf: c_int = 2;
pub const status_invalid_json: c_int = 3;
pub const status_invalid_field: c_int = 4;

pub const Header = extern struct {
    schema_version: u16,
    run_id: u64,
    seq: u64,
    source_offset: u64,
    tile_id: [6]u8,
    logical_actor_id: u64,
    policy_version: [32]u8,
    capability_envelope_id_le: [16]u8,
    timestamp_ns: u64,
    prev_hash: u64,
    record_hash: u64,
};

pub const SourceEventPayload = extern struct {
    source_system: [16]u8,
    event_type: [32]u8,
    raw_hash: u64,
};

pub const NormalizationPayload = extern struct {
    source_event_hash: u64,
    normalized_hash: u64,
    canonical_event_type: [32]u8,
};

pub const PolicyDecisionPayload = extern struct {
    outcome: u8,
    rule_id: u32,
    failed_scope_dim: [32]u8,
    source_event_hash: u64,
    catalog_schema_version: u32,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
};

pub const ModelCallPayload = extern struct {
    model_id: [32]u8,
    prompt_hash: u64,
    response_hash: u64,
    token_estimate: u32,
    retry_count: u8,
    actor_role: [16]u8,
    workflow: [16]u8,
    policy_decision_id: u64,
    replay_substitution_id: u64,
};

pub const FinancialAdapterCallPayload = extern struct {
    adapter_id: [16]u8,
    request_hash: u64,
    response_hash: u64,
    fixture_id: u32,
};

pub const ProposalPayload = extern struct {
    proposal_type: [32]u8,
    proposal_hash: u64,
    approval_state: u8,
};

pub const DestinationCheckPayload = extern struct {
    destination_type: [16]u8,
    allowlist_version: u32,
    outcome: u8,
};

pub const LimitCheckPayload = extern struct {
    limit_type: u8,
    value: i64,
    limit: i64,
    outcome: u8,
};

pub const ApprovalRequiredPayload = extern struct {
    action_class: [32]u8,
    approval_path: [32]u8,
    proposal_hash: u64,
};

pub const DenialPayload = extern struct {
    action_class: [32]u8,
    reason_code: u32,
    failed_scope_dim: [32]u8,
    catalog_schema_version: u32,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
};

pub const TelemetryCheckpointPayload = extern struct {
    metric_set_hash: u64,
    source_offset_watermark: u64,
};

pub const ReplayResultPayload = extern struct {
    capsule_id: u64,
    divergences: u64,
    first_divergent_seq: u64,
};

pub const DeduplicationPayload = extern struct {
    idempotency_key: u64,
    is_duplicate: u8,
};

pub const CaseCreationPayload = extern struct {
    basket_id: u64,
    instrument_count: u8,
    rejected_count: u8,
    total_allocated_cents: i64,
};

pub const Payload = extern union {
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
    deduplication: DeduplicationPayload,
    case_creation: CaseCreationPayload,
};

pub const Event = extern struct {
    header: Header,
    record_type: u8,
    payload: Payload,
};

const std = @import("std");
const c_abi = @import("c_abi");

/// k0/k1 are fixed constants baked into the audit schema. Changing them
/// invalidates all existing audit logs.
const hash_k0: u64 = 0x0000544455414B54; // "TKAUDT\0\0" LE
const hash_k1: u64 = 2; // schema version

pub fn tk_audit_record_hash(event: *const Event) u64 {
    var sip: c_abi.ballet.Siphash13 = .{};
    c_abi.ballet.siphashInit(&sip, hash_k0, hash_k1);
    const h = &event.header;

    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.schema_version));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.run_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.seq));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.source_offset));
    c_abi.ballet.siphashAppend(&sip, &h.tile_id);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.logical_actor_id));
    c_abi.ballet.siphashAppend(&sip, &h.policy_version);
    c_abi.ballet.siphashAppend(&sip, &h.capability_envelope_id_le);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.prev_hash));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&event.record_type));

    switch (event.record_type) {
        0 => {
            const p = &event.payload.source_event;
            c_abi.ballet.siphashAppend(&sip, &p.source_system);
            c_abi.ballet.siphashAppend(&sip, &p.event_type);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.raw_hash));
        },
        1 => {
            const p = &event.payload.normalization;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.source_event_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.normalized_hash));
            c_abi.ballet.siphashAppend(&sip, &p.canonical_event_type);
        },
        2 => {
            const p = &event.payload.policy_decision;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.outcome));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.rule_id));
            c_abi.ballet.siphashAppend(&sip, &p.failed_scope_dim);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.source_event_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.catalog_schema_version));
            c_abi.ballet.siphashAppend(&sip, &p.taxonomy_id);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.taxonomy_version));
            c_abi.ballet.siphashAppend(&sip, &p.classification_code);
        },
        3 => {
            const p = &event.payload.model_call;
            c_abi.ballet.siphashAppend(&sip, &p.model_id);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.prompt_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.response_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.token_estimate));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.retry_count));
            c_abi.ballet.siphashAppend(&sip, &p.actor_role);
            c_abi.ballet.siphashAppend(&sip, &p.workflow);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.policy_decision_id));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.replay_substitution_id));
        },
        4 => {
            const p = &event.payload.financial_adapter_call;
            c_abi.ballet.siphashAppend(&sip, &p.adapter_id);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.request_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.response_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.fixture_id));
        },
        5 => {
            const p = &event.payload.proposal;
            c_abi.ballet.siphashAppend(&sip, &p.proposal_type);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.proposal_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.approval_state));
        },
        6 => {
            const p = &event.payload.destination_check;
            c_abi.ballet.siphashAppend(&sip, &p.destination_type);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.allowlist_version));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.outcome));
        },
        7 => {
            const p = &event.payload.limit_check;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.limit_type));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.value));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.limit));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.outcome));
        },
        8 => {
            const p = &event.payload.approval_required;
            c_abi.ballet.siphashAppend(&sip, &p.action_class);
            c_abi.ballet.siphashAppend(&sip, &p.approval_path);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.proposal_hash));
        },
        9 => {
            const p = &event.payload.denial;
            c_abi.ballet.siphashAppend(&sip, &p.action_class);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.reason_code));
            c_abi.ballet.siphashAppend(&sip, &p.failed_scope_dim);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.catalog_schema_version));
            c_abi.ballet.siphashAppend(&sip, &p.taxonomy_id);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.taxonomy_version));
            c_abi.ballet.siphashAppend(&sip, &p.classification_code);
        },
        10 => {
            const p = &event.payload.telemetry_checkpoint;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.metric_set_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.source_offset_watermark));
        },
        11 => {
            const p = &event.payload.replay_result;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.capsule_id));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.divergences));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.first_divergent_seq));
        },
        12 => {
            const p = &event.payload.deduplication;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.idempotency_key));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.is_duplicate));
        },
        13 => {
            const p = &event.payload.case_creation;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.basket_id));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.instrument_count));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.rejected_count));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.total_allocated_cents));
        },
        else => {},
    }

    return c_abi.ballet.siphashFini(&sip);
}

pub fn tk_audit_peek_binary_len(
    in: [*]const u8,
    in_sz: usize,
    out_total_len: *usize,
) c_int {
    if (in_sz < @sizeOf(u32)) return status_invalid_protobuf;
    const body_len = std.mem.readInt(u32, in[0..@sizeOf(u32)], .little);
    out_total_len.* = @sizeOf(u32) + @as(usize, body_len);
    return status_ok;
}

// ---------------------------------------------------------------------------
// Protobuf field numbers (audit header). Oneof payload field = payload_base
// + record_type (0..13).
// ---------------------------------------------------------------------------
const field_schema_version: u32 = 1;
const field_run_id: u32 = 2;
const field_seq: u32 = 3;
const field_source_offset: u32 = 4;
const field_tile_id: u32 = 5;
const field_logical_actor_id: u32 = 6;
const field_policy_version: u32 = 7;
const field_capability_envelope_id: u32 = 8;
const field_timestamp_ns: u32 = 9;
const field_prev_hash: u32 = 10;
const field_record_hash: u32 = 11;
const field_payload_base: u32 = 12;

fn trimmedLen(buf: []const u8) usize {
    var len: usize = 0;
    while (len < buf.len and buf[len] != 0) : (len += 1) {}
    return len;
}

fn zeroTail(buf: []u8, used: usize) void {
    if (used < buf.len) @memset(buf[used..], 0);
}

fn skipBytes(buf: *c_abi.ballet.PbInbuf, len: u64) void {
    if (c_abi.ballet.pbInbufSz(buf) >= len) c_abi.ballet.pbInbufAdvance(buf, len);
}

fn copyLenBytes(dst: []u8, buf: *c_abi.ballet.PbInbuf, len: u64) !void {
    if (len > dst.len) return error.InvalidProtobuf;
    if (c_abi.ballet.pbInbufSz(buf) < len) return error.InvalidProtobuf;
    const src = c_abi.ballet.pbInbufCur(buf)[0..@intCast(len)];
    @memcpy(dst[0..@intCast(len)], src);
    zeroTail(dst, @intCast(len));
    c_abi.ballet.pbInbufAdvance(buf, len);
}

pub fn tk_audit_format_protobuf(
    out: [*]u8,
    out_sz: usize,
    event: *const Event,
    written: *usize,
) c_int {
    var scratch: [512]u8 align(32) = undefined;
    const capped_out_sz = @min(out_sz, scratch.len);
    var enc: c_abi.ballet.PbEncoder = .{};
    if (!c_abi.ballet.pbEncoderInit(&enc, scratch[0..capped_out_sz])) return status_no_space;

    const h = &event.header;
    const tile_len = trimmedLen(&h.tile_id);
    const policy_len = trimmedLen(&h.policy_version);

    if (!c_abi.ballet.pbPushUint32(&enc, field_schema_version, h.schema_version)) return status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_run_id, h.run_id)) return status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_seq, h.seq)) return status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_source_offset, h.source_offset)) return status_no_space;
    if (!c_abi.ballet.pbPushBytes(&enc, field_tile_id, h.tile_id[0..tile_len])) return status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_logical_actor_id, h.logical_actor_id)) return status_no_space;
    if (!c_abi.ballet.pbPushBytes(&enc, field_policy_version, h.policy_version[0..policy_len])) return status_no_space;
    if (!c_abi.ballet.pbPushBytes(&enc, field_capability_envelope_id, &h.capability_envelope_id_le)) return status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_timestamp_ns, h.timestamp_ns)) return status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_prev_hash, h.prev_hash)) return status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_record_hash, h.record_hash)) return status_no_space;

    if (!c_abi.ballet.pbSubmsgOpen(&enc, field_payload_base + event.record_type)) return status_no_space;
    switch (event.record_type) {
        0 => {
            const p = &event.payload.source_event;
            const source_len = trimmedLen(&p.source_system);
            const event_type_len = trimmedLen(&p.event_type);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.source_system[0..source_len])) return status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 2, p.event_type[0..event_type_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.raw_hash)) return status_no_space;
        },
        1 => {
            const p = &event.payload.normalization;
            const event_type_len = trimmedLen(&p.canonical_event_type);
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.source_event_hash)) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.normalized_hash)) return status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 3, p.canonical_event_type[0..event_type_len])) return status_no_space;
        },
        2 => {
            const p = &event.payload.policy_decision;
            const failed_dim_len = trimmedLen(&p.failed_scope_dim);
            const taxonomy_id_len = trimmedLen(&p.taxonomy_id);
            const classification_code_len = trimmedLen(&p.classification_code);
            if (!c_abi.ballet.pbPushUint32(&enc, 1, p.outcome)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.rule_id)) return status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 3, p.failed_scope_dim[0..failed_dim_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 4, p.source_event_hash)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 5, p.catalog_schema_version)) return status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 6, p.taxonomy_id[0..taxonomy_id_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 7, p.taxonomy_version)) return status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 8, p.classification_code[0..classification_code_len])) return status_no_space;
        },
        3 => {
            const p = &event.payload.model_call;
            const model_len = trimmedLen(&p.model_id);
            const actor_role_len = trimmedLen(&p.actor_role);
            const workflow_len = trimmedLen(&p.workflow);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.model_id[0..model_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.prompt_hash)) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.response_hash)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 4, p.token_estimate)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 5, p.retry_count)) return status_no_space;
            if (actor_role_len != 0 and !c_abi.ballet.pbPushBytes(&enc, 6, p.actor_role[0..actor_role_len])) return status_no_space;
            if (workflow_len != 0 and !c_abi.ballet.pbPushBytes(&enc, 7, p.workflow[0..workflow_len])) return status_no_space;
            if (p.policy_decision_id != 0 and !c_abi.ballet.pbPushUint64(&enc, 8, p.policy_decision_id)) return status_no_space;
            if (p.replay_substitution_id != 0 and !c_abi.ballet.pbPushUint64(&enc, 9, p.replay_substitution_id)) return status_no_space;
        },
        4 => {
            const p = &event.payload.financial_adapter_call;
            const adapter_len = trimmedLen(&p.adapter_id);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.adapter_id[0..adapter_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.request_hash)) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.response_hash)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 4, p.fixture_id)) return status_no_space;
        },
        5 => {
            const p = &event.payload.proposal;
            const proposal_len = trimmedLen(&p.proposal_type);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.proposal_type[0..proposal_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.proposal_hash)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 3, p.approval_state)) return status_no_space;
        },
        6 => {
            const p = &event.payload.destination_check;
            const dest_len = trimmedLen(&p.destination_type);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.destination_type[0..dest_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.allowlist_version)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 3, p.outcome)) return status_no_space;
        },
        7 => {
            const p = &event.payload.limit_check;
            if (!c_abi.ballet.pbPushUint32(&enc, 1, p.limit_type)) return status_no_space;
            if (!c_abi.ballet.pbPushInt64(&enc, 2, p.value)) return status_no_space;
            if (!c_abi.ballet.pbPushInt64(&enc, 3, p.limit)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 4, p.outcome)) return status_no_space;
        },
        8 => {
            const p = &event.payload.approval_required;
            const action_len = trimmedLen(&p.action_class);
            const path_len = trimmedLen(&p.approval_path);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.action_class[0..action_len])) return status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 2, p.approval_path[0..path_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.proposal_hash)) return status_no_space;
        },
        9 => {
            const p = &event.payload.denial;
            const action_len = trimmedLen(&p.action_class);
            const failed_len = trimmedLen(&p.failed_scope_dim);
            const taxonomy_id_len = trimmedLen(&p.taxonomy_id);
            const classification_code_len = trimmedLen(&p.classification_code);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.action_class[0..action_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.reason_code)) return status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 3, p.failed_scope_dim[0..failed_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 4, p.catalog_schema_version)) return status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 5, p.taxonomy_id[0..taxonomy_id_len])) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 6, p.taxonomy_version)) return status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 7, p.classification_code[0..classification_code_len])) return status_no_space;
        },
        10 => {
            const p = &event.payload.telemetry_checkpoint;
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.metric_set_hash)) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.source_offset_watermark)) return status_no_space;
        },
        11 => {
            const p = &event.payload.replay_result;
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.capsule_id)) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.divergences)) return status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.first_divergent_seq)) return status_no_space;
        },
        12 => {
            const p = &event.payload.deduplication;
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.idempotency_key)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.is_duplicate)) return status_no_space;
        },
        13 => {
            const p = &event.payload.case_creation;
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.basket_id)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.instrument_count)) return status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 3, p.rejected_count)) return status_no_space;
            if (!c_abi.ballet.pbPushInt64(&enc, 4, p.total_allocated_cents)) return status_no_space;
        },
        else => return status_invalid_field,
    }
    if (!c_abi.ballet.pbSubmsgClose(&enc)) return status_no_space;
    written.* = @intCast(c_abi.ballet.pbEncoderOutSz(&enc));
    if (!c_abi.ballet.pbEncoderFini(&enc)) return status_no_space;
    @memcpy(out[0..written.*], scratch[0..written.*]);
    return status_ok;
}

fn parsePayload(record_type: u32, inbuf: *c_abi.ballet.PbInbuf, payload: *Payload) c_int {
    var tlv: c_abi.ballet.PbTlv = .{};
    while (c_abi.ballet.pbInbufSz(inbuf) != 0) {
        if (!c_abi.ballet.pbReadTlv(inbuf, &tlv)) return status_invalid_protobuf;
        switch (record_type) {
            0 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.source_event.source_system, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.source_event.event_type, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.source_event.raw_hash = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            1 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.normalization.source_event_hash = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.normalization.normalized_hash = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.normalization.canonical_event_type, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            2 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.policy_decision.outcome = @truncate(tlv.varint);
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.policy_decision.rule_id = @truncate(tlv.varint);
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.policy_decision.failed_scope_dim, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.policy_decision.source_event_hash = tlv.varint;
                },
                5 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.policy_decision.catalog_schema_version = @truncate(tlv.varint);
                },
                6 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.policy_decision.taxonomy_id, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                7 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.policy_decision.taxonomy_version = @truncate(tlv.varint);
                },
                8 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.policy_decision.classification_code, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            3 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.model_call.model_id, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.model_call.prompt_hash = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.model_call.response_hash = tlv.varint;
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.model_call.token_estimate = @truncate(tlv.varint);
                },
                5 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.model_call.retry_count = @truncate(tlv.varint);
                },
                6 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.model_call.actor_role, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                7 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.model_call.workflow, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                8 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.model_call.policy_decision_id = tlv.varint;
                },
                9 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.model_call.replay_substitution_id = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            4 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.financial_adapter_call.adapter_id, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.financial_adapter_call.request_hash = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.financial_adapter_call.response_hash = tlv.varint;
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.financial_adapter_call.fixture_id = @truncate(tlv.varint);
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            5 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.proposal.proposal_type, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.proposal.proposal_hash = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.proposal.approval_state = @truncate(tlv.varint);
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            6 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.destination_check.destination_type, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.destination_check.allowlist_version = @truncate(tlv.varint);
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.destination_check.outcome = @truncate(tlv.varint);
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            7 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.limit_check.limit_type = @truncate(tlv.varint);
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.limit_check.value = @bitCast(tlv.varint);
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.limit_check.limit = @bitCast(tlv.varint);
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.limit_check.outcome = @truncate(tlv.varint);
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            8 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.approval_required.action_class, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.approval_required.approval_path, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.approval_required.proposal_hash = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            9 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.denial.action_class, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.denial.reason_code = @truncate(tlv.varint);
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.denial.failed_scope_dim, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.denial.catalog_schema_version = @truncate(tlv.varint);
                },
                5 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.denial.taxonomy_id, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                6 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.denial.taxonomy_version = @truncate(tlv.varint);
                },
                7 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                    copyLenBytes(&payload.denial.classification_code, inbuf, tlv.len()) catch return status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            10 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.telemetry_checkpoint.metric_set_hash = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.telemetry_checkpoint.source_offset_watermark = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            11 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.replay_result.capsule_id = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.replay_result.divergences = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.replay_result.first_divergent_seq = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            12 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.deduplication.idempotency_key = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.deduplication.is_duplicate = @truncate(tlv.varint);
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            13 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.case_creation.basket_id = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.case_creation.instrument_count = @truncate(tlv.varint);
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.case_creation.rejected_count = @truncate(tlv.varint);
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                    payload.case_creation.total_allocated_cents = @bitCast(tlv.varint);
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            else => return status_invalid_protobuf,
        }
    }
    return status_ok;
}

pub fn tk_audit_parse_protobuf(
    in: [*]const u8,
    in_sz: usize,
    event: *Event,
) c_int {
    event.* = std.mem.zeroes(Event);

    var inbuf: c_abi.ballet.PbInbuf = .{};
    c_abi.ballet.pbInbufInit(&inbuf, in[0..in_sz]);
    var tlv: c_abi.ballet.PbTlv = .{};

    while (c_abi.ballet.pbInbufSz(&inbuf) != 0) {
        if (!c_abi.ballet.pbReadTlv(&inbuf, &tlv)) return status_invalid_protobuf;
        switch (tlv.field_id) {
            field_schema_version => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                event.header.schema_version = @truncate(tlv.varint);
            },
            field_run_id => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                event.header.run_id = tlv.varint;
            },
            field_seq => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                event.header.seq = tlv.varint;
            },
            field_source_offset => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                event.header.source_offset = tlv.varint;
            },
            field_tile_id => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                copyLenBytes(&event.header.tile_id, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_logical_actor_id => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                event.header.logical_actor_id = tlv.varint;
            },
            field_policy_version => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                copyLenBytes(&event.header.policy_version, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_capability_envelope_id => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                copyLenBytes(&event.header.capability_envelope_id_le, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_timestamp_ns => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                event.header.timestamp_ns = tlv.varint;
            },
            field_prev_hash => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                event.header.prev_hash = tlv.varint;
            },
            field_record_hash => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return status_invalid_protobuf;
                event.header.record_hash = tlv.varint;
            },
            12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return status_invalid_protobuf;
                if (c_abi.ballet.pbInbufSz(&inbuf) < tlv.len()) return status_invalid_protobuf;
                const rt = tlv.field_id - field_payload_base;
                event.record_type = @truncate(rt);
                var payload_buf: c_abi.ballet.PbInbuf = .{};
                c_abi.ballet.pbInbufInit(&payload_buf, c_abi.ballet.pbInbufCur(&inbuf)[0..@intCast(tlv.len())]);
                const err = parsePayload(rt, &payload_buf, &event.payload);
                if (err != status_ok) return err;
                c_abi.ballet.pbInbufAdvance(&inbuf, tlv.len());
            },
            else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(&inbuf, tlv.len()),
        }
    }

    return status_ok;
}

fn statusFromErr(err: anyerror) c_int {
    return switch (err) {
        error.InvalidProtobuf => status_invalid_protobuf,
        else => status_invalid_protobuf,
    };
}
