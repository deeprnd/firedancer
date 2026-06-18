/// Narrow Zig extern bindings for the Tickoni audit codec C surface.
///
/// The implementation lives under src/tickoni/codec/ and reuses
/// Firedancer protobuf/tokenizer and cJSON primitives. This file stays
/// ABI-only so src/tickoni/c_abi remains a thin binding layer.
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
};

pub const ModelCallPayload = extern struct {
    model_id: [32]u8,
    prompt_hash: u64,
    response_hash: u64,
    token_estimate: u32,
    retry_count: u8,
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

pub extern fn tk_audit_record_hash(event: *const Event) u64;

pub extern fn tk_audit_peek_binary_len(
    in: [*]const u8,
    in_sz: usize,
    out_total_len: *usize,
) c_int;

pub extern fn tk_audit_format_protobuf(
    out: [*]u8,
    out_sz: usize,
    event: *const Event,
    written: *usize,
) c_int;

pub extern fn tk_audit_parse_protobuf(
    in: [*]const u8,
    in_sz: usize,
    event: *Event,
) c_int;
