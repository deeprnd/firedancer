const std = @import("std");
const basket = @import("basket");
const model = @import("model");
const trade_ticket = @import("trade_ticket");

const ReplayCapsuleWire = struct {
    ticket_id: []const u8,
    model_substitutions: []const struct {
        fixture_file: []const u8,
    },
    adapter_substitutions: []const struct {
        operation: []const u8,
        fixture_file: []const u8,
    },
    replay_assertions: struct {
        no_live_model_call: bool,
        no_live_adapter_call: bool,
        no_paper_fill_emitted: bool,
        affordability_outcome_matches: []const u8,
        policy_outcome_matches: []const u8,
        max_affordable_cents: ?i64 = null,
        effective_max_paper_trade_cents: ?i64 = null,
        blocked_reason_code_matches: ?[]const u8 = null,
        failed_scope_dim_matches: ?[]const u8 = null,
    },
};

pub const ReplayVerification = struct {
    external_effects_disabled: bool,
    replay_match: bool,
    divergence_count: u64,
};

const LoadedReplayCapsule = struct {
    raw: []u8,
    parsed: std.json.Parsed(ReplayCapsuleWire),

    fn deinit(self: *LoadedReplayCapsule, allocator: std.mem.Allocator) void {
        self.parsed.deinit();
        allocator.free(self.raw);
    }
};

fn loadReplayCapsule(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !LoadedReplayCapsule {
    const raw = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(16 * 1024),
    );
    errdefer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(ReplayCapsuleWire, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    return .{
        .raw = raw,
        .parsed = parsed,
    };
}

fn hasAdapterOperation(capsule: ReplayCapsuleWire, operation: []const u8) bool {
    for (capsule.adapter_substitutions) |substitution| {
        if (std.mem.eql(u8, substitution.operation, operation)) return true;
    }
    return false;
}

pub fn verifyAllowedTrade(
    allocator: std.mem.Allocator,
    io: std.Io,
    proposed_basket: *const basket.Basket,
    ticket: *const trade_ticket.TradeTicket,
    paper_result: *const trade_ticket.PaperExecutionResult,
    model_response: *const model.ModelResponse,
) !ReplayVerification {
    var loaded = try loadReplayCapsule(
        allocator,
        io,
        "src/tickoni/test/fixtures/investment/replay_capsule.json",
    );
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    var divergences: u64 = 0;

    if (!capsule.replay_assertions.no_live_model_call) divergences += 1;
    if (!capsule.replay_assertions.no_live_adapter_call) divergences += 1;
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences += 1;
    if (!std.mem.eql(u8, capsule.replay_assertions.affordability_outcome_matches, "allow")) divergences += 1;
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "allow")) divergences += 1;
    if (!std.mem.eql(u8, ticket.ticketIdSlice(), capsule.ticket_id)) divergences += 1;
    if (ticket.target_notional_cents != proposed_basket.total_allocated_cents) divergences += 1;
    if (paper_result.total_filled_cents != ticket.target_notional_cents) divergences += 1;
    if (model_response.content.len == 0) divergences += 1;
    if (capsule.model_substitutions.len != 1) divergences += 1;
    if (capsule.adapter_substitutions.len != 3) divergences += 1;
    if (!std.mem.eql(u8, capsule.model_substitutions[0].fixture_file, "model_response_gemma4.json")) divergences += 1;

    return .{
        .external_effects_disabled = true,
        .replay_match = divergences == 0,
        .divergence_count = divergences,
    };
}

pub fn verifyOversizedTradeBlock(
    allocator: std.mem.Allocator,
    io: std.Io,
    proposed_basket: *const basket.Basket,
    ticket: *const trade_ticket.TradeTicket,
    model_response: *const model.ModelResponse,
) !ReplayVerification {
    var loaded = try loadReplayCapsule(
        allocator,
        io,
        "src/tickoni/test/fixtures/investment/replay_capsule_oversized_25000.json",
    );
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    var divergences: u64 = 0;

    if (!capsule.replay_assertions.no_live_model_call) divergences += 1;
    if (!capsule.replay_assertions.no_live_adapter_call) divergences += 1;
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences += 1;
    if (!std.mem.eql(u8, capsule.replay_assertions.affordability_outcome_matches, "allow")) divergences += 1;
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "deny")) divergences += 1;
    if (!std.mem.eql(u8, ticket.ticketIdSlice(), capsule.ticket_id)) divergences += 1;
    if (ticket.target_notional_cents != proposed_basket.total_allocated_cents) divergences += 1;
    if (ticket.policy_outcome != .deny) divergences += 1;
    if (ticket.blocked_reason_count != 1) divergences += 1;
    if (model_response.content.len == 0) divergences += 1;
    if (capsule.model_substitutions.len != 1) divergences += 1;
    if (capsule.adapter_substitutions.len != 2) divergences += 1;
    if (hasAdapterOperation(capsule, "paper_order")) divergences += 1;

    if (capsule.replay_assertions.max_affordable_cents) |expected| {
        if (ticket.affordability_result.max_affordable_cents != expected) divergences += 1;
    }
    if (capsule.replay_assertions.effective_max_paper_trade_cents) |expected| {
        if (ticket.affordability_result.effective_max_paper_trade_cents != expected) divergences += 1;
    }
    if (capsule.replay_assertions.blocked_reason_code_matches) |expected| {
        if (ticket.blocked_reason_count == 0 or
            !std.mem.eql(u8, ticket.blocked_reasons[0].code.label(), expected))
            divergences += 1;
    }
    if (capsule.replay_assertions.failed_scope_dim_matches) |expected| {
        if (ticket.blocked_reason_count == 0 or
            !std.mem.eql(u8, ticket.blocked_reasons[0].failed_scope_dim.label(), expected))
            divergences += 1;
    }

    return .{
        .external_effects_disabled = true,
        .replay_match = divergences == 0,
        .divergence_count = divergences,
    };
}

pub fn verifyRestrictedInstrumentBlock(
    allocator: std.mem.Allocator,
    io: std.Io,
    proposed_basket: *const basket.Basket,
    requested_ticker: []const u8,
    model_response: *const model.ModelResponse,
) !ReplayVerification {
    var loaded = try loadReplayCapsule(
        allocator,
        io,
        "src/tickoni/test/fixtures/investment/replay_capsule_restricted_soxl.json",
    );
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    var divergences: u64 = 0;

    if (!capsule.replay_assertions.no_live_model_call) divergences += 1;
    if (!capsule.replay_assertions.no_live_adapter_call) divergences += 1;
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences += 1;
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "deny")) divergences += 1;
    if (capsule.replay_assertions.affordability_outcome_matches.len != 0) divergences += 1;
    if (capsule.ticket_id.len != 0) divergences += 1;
    if (model_response.content.len == 0) divergences += 1;
    if (capsule.model_substitutions.len != 1) divergences += 1;
    if (capsule.adapter_substitutions.len != 0) divergences += 1;
    if (!std.mem.eql(u8, capsule.model_substitutions[0].fixture_file, "model_response_gemma4.json")) divergences += 1;
    if (proposed_basket.rejected_count == 0) divergences += 1;
    if (!std.mem.eql(u8, requested_ticker, "SOXL")) divergences += 1;

    if (capsule.replay_assertions.failed_scope_dim_matches) |expected| {
        if (!std.mem.eql(u8, expected, "restricted_instrument")) divergences += 1;
    } else {
        divergences += 1;
    }

    return .{
        .external_effects_disabled = true,
        .replay_match = divergences == 0,
        .divergence_count = divergences,
    };
}
