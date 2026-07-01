const std = @import("std");
const audit = @import("audit_tile");

pub const AuditAppendInput = struct {
    source_offset: u64,
    event_hash: u64,
    decision: Decision,
};

pub const Decision = enum(u8) {
    allow,
    deny,
    malformed_drop,
    duplicate_drop,
};

pub const audit_seed: u64 = 0xcbf29ce484222325;

const tkpoly_tile_id: [6]u8 = "tkpoly".*;

pub const AuditLog = struct {
    records: []audit.AuditEvent,
    count: usize = 0,
    prev_hash: u64 = audit_seed,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !AuditLog {
        return .{ .records = try allocator.alloc(audit.AuditEvent, capacity) };
    }

    pub fn deinit(self: *AuditLog, allocator: std.mem.Allocator) void {
        allocator.free(self.records);
    }

    pub fn append(self: *AuditLog, msg: AuditAppendInput) error{AuditFull}!void {
        if (self.count >= self.records.len) return error.AuditFull;
        const event = buildPolicyDecisionEvent(
            @intCast(self.count),
            msg.source_offset,
            msg.event_hash,
            msg.decision,
            self.prev_hash,
        );
        self.records[self.count] = event;
        self.count += 1;
        self.prev_hash = event.header.record_hash;
    }
};

pub fn buildPolicyDecisionEvent(
    seq: u64,
    source_offset: u64,
    event_hash: u64,
    decision: Decision,
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
        .run_id = 0,
        .seq = seq,
        .source_offset = source_offset,
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
            .catalog_schema_version = 0,
            .taxonomy_id = [_]u8{0} ** 32,
            .taxonomy_version = 0,
            .classification_code = [_]u8{0} ** 32,
        },
    });
}
