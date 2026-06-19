const std = @import("std");
const schema = @import("schema.zig");
const codec = @import("codec.zig");

fn parseFixedAsciiBytes(comptime N: usize, value: []const u8) ![N]u8 {
    if (value.len > N) return error.StringTooLong;
    var out = [_]u8{0} ** N;
    for (value, 0..) |byte, idx| {
        if (byte < 0x20 or byte > 0x7e) return error.InvalidStringByte;
        out[idx] = byte;
    }
    return out;
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
    run_id: u64,
) schema.Header {
    return .{
        .schema_version = schema.audit_schema_version,
        .run_id = run_id,
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

pub fn makeFixtures() [12]schema.AuditEvent {
    const headers = [_]schema.Header{
        fixtureHeader(1, 10, "tkings", 1001, "policy_ingress_v1", 1, 111, 500, 0),
        fixtureHeader(2, 11, "tknorm", 1002, "policy_norm_v1", 2, 222, 501, 0),
        fixtureHeader(3, 12, "tkpoly", 1003, "policy_poly_v1", 3, 333, 502, 0),
        fixtureHeader(4, 13, "tkmodl", 1004, "policy_model_v1", 4, 444, 503, 0),
        fixtureHeader(5, 14, "tkadpt", 1005, "policy_adpt_v1", 5, 555, 504, 0),
        fixtureHeader(6, 15, "tkagnt", 1006, "policy_prop_v1", 6, 666, 505, 0),
        fixtureHeader(7, 16, "tkpoly", 1007, "policy_dest_v1", 7, 777, 506, 0),
        fixtureHeader(8, 17, "tkpoly", 1008, "policy_limt_v1", 8, 888, 507, 0),
        fixtureHeader(9, 18, "tkpoly", 1009, "policy_aprv_v1", 9, 999, 508, 0),
        fixtureHeader(10, 19, "tkpoly", 1010, "policy_deny_v1", 10, 1110, 509, 0),
        fixtureHeader(11, 20, "tkmetr", 1011, "policy_metr_v1", 11, 1221, 510, 0),
        fixtureHeader(12, 21, "tkrepl", 1012, "policy_repl_v1", 12, 1332, 511, 0),
    };

    const events = [_]schema.AuditEvent{
        codec.buildEvent(headers[0], .{ .source_event = .{
            .source_system = parseFixedAsciiBytes(16, "feed_alpha") catch unreachable,
            .event_type = parseFixedAsciiBytes(32, "payment_exception") catch unreachable,
            .raw_hash = 9001,
        } }),
        codec.buildEvent(headers[1], .{ .normalization = .{
            .source_event_hash = 9001,
            .normalized_hash = 9002,
            .canonical_event_type = parseFixedAsciiBytes(32, "payment.normalized") catch unreachable,
        } }),
        codec.buildEvent(headers[2], .{ .policy_decision = .{
            .outcome = .require_approval,
            .rule_id = 42,
            .failed_scope_dim = parseFixedAsciiBytes(32, "amount_limit") catch unreachable,
            .source_event_hash = 9002,
        } }),
        codec.buildEvent(headers[3], .{ .model_call = .{
            .model_id = parseFixedAsciiBytes(32, "gpt_local_stub") catch unreachable,
            .prompt_hash = 9100,
            .response_hash = 9101,
            .token_estimate = 512,
            .retry_count = 2,
            .actor_role = [_]u8{0} ** 16,
            .workflow = [_]u8{0} ** 16,
            .policy_decision_id = 0,
            .replay_substitution_id = 0,
        } }),
        codec.buildEvent(headers[4], .{ .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "broker") catch unreachable,
            .request_hash = 9200,
            .response_hash = 9201,
            .fixture_id = 7,
        } }),
        codec.buildEvent(headers[5], .{ .proposal = .{
            .proposal_type = parseFixedAsciiBytes(32, "trading_order.propose") catch unreachable,
            .proposal_hash = 9300,
            .approval_state = 1,
        } }),
        codec.buildEvent(headers[6], .{ .destination_check = .{
            .destination_type = parseFixedAsciiBytes(16, "broker_account") catch unreachable,
            .allowlist_version = 8,
            .outcome = .allow,
        } }),
        codec.buildEvent(headers[7], .{ .limit_check = .{
            .limit_type = .per_day,
            .value = 1200,
            .limit = 1000,
            .outcome = .deny,
        } }),
        codec.buildEvent(headers[8], .{ .approval_required = .{
            .action_class = parseFixedAsciiBytes(32, "payment_retry.propose") catch unreachable,
            .approval_path = parseFixedAsciiBytes(32, "maker_checker") catch unreachable,
            .proposal_hash = 9300,
        } }),
        codec.buildEvent(headers[9], .{ .denial = .{
            .action_class = parseFixedAsciiBytes(32, "trading_order.place") catch unreachable,
            .reason_code = 17,
            .failed_scope_dim = parseFixedAsciiBytes(32, "environment") catch unreachable,
        } }),
        codec.buildEvent(headers[10], .{ .telemetry_checkpoint = .{
            .metric_set_hash = 9400,
            .source_offset_watermark = 41,
        } }),
        codec.buildEvent(headers[11], .{ .replay_result = .{
            .capsule_id = 9500,
            .divergences = 3,
            .first_divergent_seq = 9,
        } }),
    };

    return events;
}

test "computeRecordHash excludes timestamp_ns" {
    const header = fixtureHeader(0, 0, "tkpoly", 0, "policy", 0, 0, 0, 0);
    const payload = schema.AuditEvent.Payload{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 2,
    } };
    var header_with_timestamp = header;
    header_with_timestamp.timestamp_ns = 999_999;
    const e0 = codec.buildEvent(header, payload);
    const e1 = codec.buildEvent(header_with_timestamp, payload);
    try std.testing.expectEqual(e0.header.record_hash, e1.header.record_hash);
}

test "hash chain mutation changes downstream records" {
    const first = codec.buildEvent(fixtureHeader(0, 0, "tkpoly", 0, "policy", 0, 0, 0, 0), .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 3,
    } });
    var second_header = fixtureHeader(1, 1, "tkpoly", 0, "policy", 0, 0, first.header.record_hash, 0);
    const second = codec.buildEvent(second_header, .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 3,
    } });

    const mutated_first = codec.buildEvent(fixtureHeader(0, 9, "tkpoly", 0, "policy", 0, 0, 0, 0), .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 3,
    } });
    second_header.prev_hash = mutated_first.header.record_hash;
    const mutated_second = codec.buildEvent(second_header, second.payload);

    try std.testing.expect(first.header.record_hash != mutated_first.header.record_hash);
    try std.testing.expect(second.header.record_hash != mutated_second.header.record_hash);
}

test "binary and wire format pinned" {
    const golden = @import("audit_fixtures_gen").values;
    for (makeFixtures(), &golden) |event, g| {
        try std.testing.expectEqual(g.expected_hash, event.header.record_hash);
        var buf: [codec.max_binary_len]u8 = undefined;
        const binary = try codec.formatBinary(&buf, event);
        try std.testing.expectEqual(g.expected_binary_len, binary.len);
        try std.testing.expectEqualSlices(u8, g.expected_binary_bytes, binary);
    }
}

test "binary round-trip and hash consistency" {
    for (makeFixtures()) |event| {
        try std.testing.expectEqual(codec.computeRecordHash(event), event.header.record_hash);

        var binary_buf: [codec.max_binary_len]u8 = undefined;
        const binary = try codec.formatBinary(&binary_buf, event);
        try std.testing.expectEqual(binary.len, try codec.peekBinaryLen(binary));

        const parsed_binary = try codec.parseBinary(binary);
        try std.testing.expectEqual(binary.len, parsed_binary.consumed_len);
        try std.testing.expect(codec.auditEventsEql(event, parsed_binary.event));
    }
}

test "parseBinary rejects future schema version" {
    const event = makeFixtures()[0];
    var binary_buf: [codec.max_binary_len]u8 = undefined;
    const binary = try codec.formatBinary(&binary_buf, event);
    binary[@sizeOf(u32) + 1] = schema.audit_schema_version + 1;
    try std.testing.expectError(error.UnknownSchemaVersion, codec.parseBinary(binary));
}

test "parseBinary rejects truncated record" {
    const event = makeFixtures()[0];
    var binary_buf: [codec.max_binary_len]u8 = undefined;
    const binary = try codec.formatBinary(&binary_buf, event);
    try std.testing.expectError(error.UnexpectedEof, codec.parseBinary(binary[0 .. binary.len - 1]));
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
        var binary_buf: [codec.max_binary_len]u8 = undefined;
        const binary = try codec.formatBinary(&binary_buf, event);
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
    if (std.c.getenv("TK_GEN_FIXTURES") == null) return error.SkipZigTest;
    try writeFixtureFile();
}
