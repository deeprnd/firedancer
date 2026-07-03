const std = @import("std");
const schema = @import("audit_schema");

pub fn formatJsonLine(event: schema.AuditEvent, writer: anytype) !void {
    const h = event.header;
    try writer.writeAll("{");
    try writer.print("\"schema_version\":{d},", .{h.schema_version});
    try writer.print("\"run_id\":{d},", .{h.run_id});
    try writer.print("\"seq\":{d},", .{h.seq});
    try writer.print("\"source_offset\":{d},", .{h.source_offset});
    try writer.print("\"tile_id\":\"{s}\",", .{std.mem.sliceTo(&h.tile_id, 0)});
    try writer.print("\"logical_actor_id\":{d},", .{h.logical_actor_id});
    try writer.print("\"policy_version\":\"{s}\",", .{std.mem.sliceTo(&h.policy_version, 0)});
    try writer.print("\"capability_envelope_id\":{d},", .{h.capability_envelope_id});
    try writer.print("\"timestamp_ns\":{d},", .{h.timestamp_ns});
    try writer.print("\"prev_hash\":{d},", .{h.prev_hash});
    try writer.print("\"record_hash\":{d},", .{h.record_hash});
    try writer.print("\"record_type\":\"{s}\",", .{@tagName(std.meta.activeTag(event.payload))});
    try writer.writeAll("\"payload\":");
    try writePayloadJson(event.payload, writer);
    try writer.writeAll("}\n");
}

fn writePayloadJson(payload: schema.AuditEvent.Payload, writer: anytype) !void {
    switch (payload) {
        .source_event => |p| {
            try writer.writeAll("{");
            try writer.print("\"source_system\":\"{s}\",", .{std.mem.sliceTo(&p.source_system, 0)});
            try writer.print("\"event_type\":\"{s}\",", .{std.mem.sliceTo(&p.event_type, 0)});
            try writer.print("\"raw_hash\":{d}", .{p.raw_hash});
            try writer.writeAll("}");
        },
        .normalization => |p| {
            try writer.writeAll("{");
            try writer.print("\"source_event_hash\":{d},", .{p.source_event_hash});
            try writer.print("\"normalized_hash\":{d},", .{p.normalized_hash});
            try writer.print("\"canonical_event_type\":\"{s}\"", .{std.mem.sliceTo(&p.canonical_event_type, 0)});
            try writer.writeAll("}");
        },
        .policy_decision => |p| {
            try writer.writeAll("{");
            try writer.print("\"outcome\":\"{s}\",", .{@tagName(p.outcome)});
            try writer.print("\"rule_id\":{d},", .{p.rule_id});
            try writer.print("\"failed_scope_dim\":\"{s}\",", .{std.mem.sliceTo(&p.failed_scope_dim, 0)});
            try writer.print("\"source_event_hash\":{d},", .{p.source_event_hash});
            try writer.print("\"catalog_schema_version\":{d},", .{p.catalog_schema_version});
            try writer.print("\"taxonomy_id\":\"{s}\",", .{std.mem.sliceTo(&p.taxonomy_id, 0)});
            try writer.print("\"taxonomy_version\":{d},", .{p.taxonomy_version});
            try writer.print("\"classification_code\":\"{s}\"", .{std.mem.sliceTo(&p.classification_code, 0)});
            try writer.writeAll("}");
        },
        .model_call => |p| {
            try writer.writeAll("{");
            try writer.print("\"model_id\":\"{s}\",", .{std.mem.sliceTo(&p.model_id, 0)});
            try writer.print("\"prompt_hash\":{d},", .{p.prompt_hash});
            try writer.print("\"response_hash\":{d},", .{p.response_hash});
            try writer.print("\"token_estimate\":{d},", .{p.token_estimate});
            try writer.print("\"retry_count\":{d},", .{p.retry_count});
            try writer.print("\"actor_role\":\"{s}\",", .{std.mem.sliceTo(&p.actor_role, 0)});
            try writer.print("\"workflow\":\"{s}\",", .{std.mem.sliceTo(&p.workflow, 0)});
            try writer.print("\"policy_decision_id\":{d},", .{p.policy_decision_id});
            try writer.print("\"replay_substitution_id\":{d}", .{p.replay_substitution_id});
            try writer.writeAll("}");
        },
        .financial_adapter_call => |p| {
            try writer.writeAll("{");
            try writer.print("\"adapter_id\":\"{s}\",", .{std.mem.sliceTo(&p.adapter_id, 0)});
            try writer.print("\"request_hash\":{d},", .{p.request_hash});
            try writer.print("\"response_hash\":{d},", .{p.response_hash});
            try writer.print("\"replay_substitution_id\":{d}", .{p.replay_substitution_id});
            try writer.writeAll("}");
        },
        .proposal => |p| {
            try writer.writeAll("{");
            try writer.print("\"proposal_type\":\"{s}\",", .{std.mem.sliceTo(&p.proposal_type, 0)});
            try writer.print("\"proposal_hash\":{d},", .{p.proposal_hash});
            try writer.print("\"approval_state\":{d}", .{p.approval_state});
            try writer.writeAll("}");
        },
        .destination_check => |p| {
            try writer.writeAll("{");
            try writer.print("\"destination_type\":\"{s}\",", .{std.mem.sliceTo(&p.destination_type, 0)});
            try writer.print("\"allowlist_version\":{d},", .{p.allowlist_version});
            try writer.print("\"outcome\":\"{s}\"", .{@tagName(p.outcome)});
            try writer.writeAll("}");
        },
        .limit_check => |p| {
            try writer.writeAll("{");
            try writer.print("\"limit_type\":\"{s}\",", .{@tagName(p.limit_type)});
            try writer.print("\"value\":{d},", .{p.value});
            try writer.print("\"limit\":{d},", .{p.limit});
            try writer.print("\"outcome\":\"{s}\"", .{@tagName(p.outcome)});
            try writer.writeAll("}");
        },
        .approval_required => |p| {
            try writer.writeAll("{");
            try writer.print("\"action_class\":\"{s}\",", .{std.mem.sliceTo(&p.action_class, 0)});
            try writer.print("\"approval_path\":\"{s}\",", .{std.mem.sliceTo(&p.approval_path, 0)});
            try writer.print("\"proposal_hash\":{d}", .{p.proposal_hash});
            try writer.writeAll("}");
        },
        .denial => |p| {
            try writer.writeAll("{");
            try writer.print("\"action_class\":\"{s}\",", .{std.mem.sliceTo(&p.action_class, 0)});
            try writer.print("\"reason_code\":{d},", .{p.reason_code});
            try writer.print("\"failed_scope_dim\":\"{s}\",", .{std.mem.sliceTo(&p.failed_scope_dim, 0)});
            try writer.print("\"catalog_schema_version\":{d},", .{p.catalog_schema_version});
            try writer.print("\"taxonomy_id\":\"{s}\",", .{std.mem.sliceTo(&p.taxonomy_id, 0)});
            try writer.print("\"taxonomy_version\":{d},", .{p.taxonomy_version});
            try writer.print("\"classification_code\":\"{s}\"", .{std.mem.sliceTo(&p.classification_code, 0)});
            try writer.writeAll("}");
        },
        .telemetry_checkpoint => |p| {
            try writer.writeAll("{");
            try writer.print("\"metric_set_hash\":{d},", .{p.metric_set_hash});
            try writer.print("\"source_offset_watermark\":{d}", .{p.source_offset_watermark});
            try writer.writeAll("}");
        },
        .replay_result => |p| {
            try writer.writeAll("{");
            try writer.print("\"capsule_id\":{d},", .{p.capsule_id});
            try writer.print("\"divergences\":{d},", .{p.divergences});
            try writer.print("\"first_divergent_seq\":{d}", .{p.first_divergent_seq});
            try writer.writeAll("}");
        },
        .deduplication => |p| {
            try writer.writeAll("{");
            try writer.print("\"idempotency_key\":{d},", .{p.idempotency_key});
            try writer.print("\"is_duplicate\":{s}", .{if (p.is_duplicate) "true" else "false"});
            try writer.writeAll("}");
        },
        .case_creation => |p| {
            try writer.writeAll("{");
            try writer.print("\"basket_id\":{d},", .{p.basket_id});
            try writer.print("\"instrument_count\":{d},", .{p.instrument_count});
            try writer.print("\"rejected_count\":{d},", .{p.rejected_count});
            try writer.print("\"total_allocated_cents\":{d}", .{p.total_allocated_cents});
            try writer.writeAll("}");
        },
    }
}
