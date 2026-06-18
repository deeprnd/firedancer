const std = @import("std");
const adapter = @import("adapter");
const basket = @import("basket");
const model = @import("model");
const trade_ticket = @import("trade_ticket");

const ReplayCapsuleWire = struct {
    ticket_id: []const u8,
    expected_basket_id: ?u64 = null,
    expected_proposal_hash: ?u64 = null,
    model_substitutions: []const struct {
        fixture_file: []const u8,
        expected_response_hash: ?u64 = null,
    },
    adapter_substitutions: []const struct {
        operation: []const u8,
        fixture_file: []const u8,
        expected_response_hash: ?u64 = null,
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
    first_divergent_field: []const u8,
    first_divergent_seq: u64,
};

const DivergenceTracker = struct {
    count: u64 = 0,
    first_field: []const u8 = "",
    first_seq: u64 = 0,

    fn note(self: *DivergenceTracker, field: []const u8, seq: u64) void {
        self.count += 1;
        if (self.first_seq == 0) {
            self.first_field = field;
            self.first_seq = seq;
        }
    }
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

fn findAdapterSubstitution(
    capsule: ReplayCapsuleWire,
    operation: []const u8,
) ?@TypeOf(capsule.adapter_substitutions[0]) {
    for (capsule.adapter_substitutions) |substitution| {
        if (std.mem.eql(u8, substitution.operation, operation)) return substitution;
    }
    return null;
}

fn updateValue(hasher: *std.hash.Wyhash, value: anytype) void {
    var copy = value;
    hasher.update(std.mem.asBytes(&copy));
}

pub fn hashBytes(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

pub fn hashTicket(ticket: *const trade_ticket.TradeTicket) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(ticket.ticketIdSlice());
    updateValue(&hasher, ticket.account_id);
    updateValue(&hasher, ticket.side);
    updateValue(&hasher, ticket.order_type);
    updateValue(&hasher, ticket.target_notional_cents);
    updateValue(&hasher, ticket.estimated_cost_cents);
    updateValue(&hasher, ticket.policy_outcome);
    updateValue(&hasher, ticket.affordability_result.max_affordable_cents);
    updateValue(&hasher, ticket.affordability_result.effective_max_paper_trade_cents);
    updateValue(&hasher, ticket.line_item_count);
    for (ticket.line_items[0..ticket.line_item_count]) |line| {
        hasher.update(line.tickerSlice());
        updateValue(&hasher, line.quantity_micros);
        updateValue(&hasher, line.price_cents);
        updateValue(&hasher, line.line_notional_cents);
    }
    updateValue(&hasher, ticket.blocked_reason_count);
    for (ticket.blocked_reasons[0..ticket.blocked_reason_count]) |reason| {
        updateValue(&hasher, reason.code);
        updateValue(&hasher, reason.failed_scope_dim);
        updateValue(&hasher, reason.requested_cents);
        updateValue(&hasher, reason.limit_cents);
    }
    return hasher.final();
}

pub fn hashPaperResult(result: *const trade_ticket.PaperExecutionResult) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(result.paperOrderIdSlice());
    hasher.update(result.ticketIdSlice());
    updateValue(&hasher, result.account_id);
    updateValue(&hasher, result.status);
    updateValue(&hasher, result.total_filled_cents);
    updateValue(&hasher, result.fill_count);
    for (result.fills[0..result.fill_count]) |fill| {
        hasher.update(fill.tickerSlice());
        updateValue(&hasher, fill.quantity_micros);
        updateValue(&hasher, fill.fill_price_cents);
        updateValue(&hasher, fill.filled_notional_cents);
    }
    updateValue(&hasher, result.resulting_account_snapshot.cash_cents);
    updateValue(&hasher, result.resulting_account_snapshot.buying_power_cents);
    updateValue(&hasher, result.resulting_account_snapshot.day_notional_used_cents);
    updateValue(&hasher, result.resulting_account_snapshot.month_notional_used_cents);
    return hasher.final();
}

fn buildReplayVerification(divergences: DivergenceTracker, external_effects_disabled: bool) ReplayVerification {
    return .{
        .external_effects_disabled = external_effects_disabled,
        .replay_match = divergences.count == 0,
        .divergence_count = divergences.count,
        .first_divergent_field = divergences.first_field,
        .first_divergent_seq = divergences.first_seq,
    };
}

pub fn verifyAllowedTradeWithCapsulePath(
    allocator: std.mem.Allocator,
    io: std.Io,
    capsule_path: []const u8,
    model_backend: *const model.Backend,
    adapter_backend: *const adapter.Backend,
    proposed_basket: *const basket.Basket,
    ticket: *const trade_ticket.TradeTicket,
    paper_result: *const trade_ticket.PaperExecutionResult,
    model_response: *const model.ModelResponse,
) !ReplayVerification {
    var loaded = try loadReplayCapsule(allocator, io, capsule_path);
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    var divergences = DivergenceTracker{};

    if (!capsule.replay_assertions.no_live_model_call) divergences.note("no_live_model_call", 8);
    if (!capsule.replay_assertions.no_live_adapter_call) divergences.note("no_live_adapter_call", 8);
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences.note("no_paper_fill_emitted", 8);
    if (!std.mem.eql(u8, capsule.replay_assertions.affordability_outcome_matches, "allow")) divergences.note("affordability_outcome", 4);
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "allow")) divergences.note("policy_outcome", 2);
    if (!std.mem.eql(u8, ticket.ticketIdSlice(), capsule.ticket_id)) divergences.note("ticket_id", 6);
    if (ticket.target_notional_cents != proposed_basket.total_allocated_cents) divergences.note("target_notional_cents", 6);
    if (paper_result.total_filled_cents != ticket.target_notional_cents) divergences.note("paper_fill_total", 7);
    if (model_response.content.len == 0) divergences.note("model_response_content", 3);
    if (capsule.model_substitutions.len != 1) divergences.note("model_substitution_count", 3);
    if (capsule.adapter_substitutions.len != 3) divergences.note("adapter_substitution_count", 4);
    if (capsule.model_substitutions.len > 0 and
        !std.mem.eql(u8, capsule.model_substitutions[0].fixture_file, "model_response_gemma4.json"))
        divergences.note("model_fixture_file", 3);

    if (capsule.expected_basket_id) |expected| {
        if (proposed_basket.basket_id != expected) divergences.note("basket_id", 1);
    } else {
        divergences.note("basket_id_missing", 1);
    }
    if (capsule.expected_proposal_hash) |expected| {
        if (hashTicket(ticket) != expected) divergences.note("proposal_hash", 6);
    } else {
        divergences.note("proposal_hash_missing", 6);
    }
    if (capsule.model_substitutions.len > 0) {
        if (capsule.model_substitutions[0].expected_response_hash) |expected| {
            if (hashBytes(model_response.content) != expected) divergences.note("model_response_hash", 3);
        } else {
            divergences.note("model_response_hash_missing", 3);
        }
    }
    if (findAdapterSubstitution(capsule, "paper_order")) |substitution| {
        if (substitution.expected_response_hash) |expected| {
            if (hashPaperResult(paper_result) != expected) divergences.note("adapter_response_hash", 7);
        } else {
            divergences.note("paper_order_hash_missing", 7);
        }
    }

    const external_effects_disabled = model_backend.isEffectFree() and adapter_backend.isEffectFree();
    return buildReplayVerification(divergences, external_effects_disabled);
}

pub fn verifyAllowedTrade(
    allocator: std.mem.Allocator,
    io: std.Io,
    model_backend: *const model.Backend,
    adapter_backend: *const adapter.Backend,
    proposed_basket: *const basket.Basket,
    ticket: *const trade_ticket.TradeTicket,
    paper_result: *const trade_ticket.PaperExecutionResult,
    model_response: *const model.ModelResponse,
) !ReplayVerification {
    return verifyAllowedTradeWithCapsulePath(
        allocator,
        io,
        "src/tickoni/test/fixtures/investment/replay_capsule.json",
        model_backend,
        adapter_backend,
        proposed_basket,
        ticket,
        paper_result,
        model_response,
    );
}

pub fn verifyOversizedTradeBlock(
    allocator: std.mem.Allocator,
    io: std.Io,
    model_backend: *const model.Backend,
    adapter_backend: *const adapter.Backend,
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
    var divergences = DivergenceTracker{};

    if (!capsule.replay_assertions.no_live_model_call) divergences.note("no_live_model_call", 9);
    if (!capsule.replay_assertions.no_live_adapter_call) divergences.note("no_live_adapter_call", 9);
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences.note("no_paper_fill_emitted", 9);
    if (!std.mem.eql(u8, capsule.replay_assertions.affordability_outcome_matches, "allow")) divergences.note("affordability_outcome", 4);
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "deny")) divergences.note("policy_outcome", 2);
    if (!std.mem.eql(u8, ticket.ticketIdSlice(), capsule.ticket_id)) divergences.note("ticket_id", 6);
    if (ticket.target_notional_cents != proposed_basket.total_allocated_cents) divergences.note("target_notional_cents", 6);
    if (ticket.policy_outcome != .deny) divergences.note("ticket_policy_outcome", 6);
    if (ticket.blocked_reason_count != 1) divergences.note("blocked_reason_count", 8);
    if (model_response.content.len == 0) divergences.note("model_response_content", 3);
    if (capsule.model_substitutions.len != 1) divergences.note("model_substitution_count", 3);
    if (capsule.adapter_substitutions.len != 2) divergences.note("adapter_substitution_count", 4);
    if (hasAdapterOperation(capsule, "paper_order")) divergences.note("paper_order_substitution_present", 9);

    if (capsule.replay_assertions.max_affordable_cents) |expected| {
        if (ticket.affordability_result.max_affordable_cents != expected) divergences.note("max_affordable_cents", 4);
    }
    if (capsule.replay_assertions.effective_max_paper_trade_cents) |expected| {
        if (ticket.affordability_result.effective_max_paper_trade_cents != expected) divergences.note("effective_max_paper_trade_cents", 7);
    }
    if (capsule.replay_assertions.blocked_reason_code_matches) |expected| {
        if (ticket.blocked_reason_count == 0 or
            !std.mem.eql(u8, ticket.blocked_reasons[0].code.label(), expected))
            divergences.note("blocked_reason_code", 8);
    }
    if (capsule.replay_assertions.failed_scope_dim_matches) |expected| {
        if (ticket.blocked_reason_count == 0 or
            !std.mem.eql(u8, ticket.blocked_reasons[0].failed_scope_dim.label(), expected))
            divergences.note("failed_scope_dim", 8);
    }

    const external_effects_disabled = model_backend.isEffectFree() and adapter_backend.isEffectFree();
    return buildReplayVerification(divergences, external_effects_disabled);
}

pub fn verifyRestrictedInstrumentBlock(
    allocator: std.mem.Allocator,
    io: std.Io,
    model_backend: *const model.Backend,
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
    var divergences = DivergenceTracker{};

    if (!capsule.replay_assertions.no_live_model_call) divergences.note("no_live_model_call", 5);
    if (!capsule.replay_assertions.no_live_adapter_call) divergences.note("no_live_adapter_call", 5);
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences.note("no_paper_fill_emitted", 5);
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "deny")) divergences.note("policy_outcome", 2);
    if (capsule.replay_assertions.affordability_outcome_matches.len != 0) divergences.note("affordability_outcome", 5);
    if (capsule.ticket_id.len != 0) divergences.note("ticket_id", 5);
    if (model_response.content.len == 0) divergences.note("model_response_content", 3);
    if (capsule.model_substitutions.len != 1) divergences.note("model_substitution_count", 3);
    if (capsule.adapter_substitutions.len != 0) divergences.note("adapter_substitution_count", 5);
    if (!std.mem.eql(u8, capsule.model_substitutions[0].fixture_file, "model_response_gemma4.json")) divergences.note("model_fixture_file", 3);
    if (proposed_basket.rejected_count == 0) divergences.note("rejected_count", 2);
    if (!std.mem.eql(u8, requested_ticker, "SOXL")) divergences.note("requested_ticker", 2);

    if (capsule.replay_assertions.failed_scope_dim_matches) |expected| {
        if (!std.mem.eql(u8, expected, "restricted_instrument")) divergences.note("failed_scope_dim", 4);
    } else {
        divergences.note("failed_scope_dim", 4);
    }

    // Restricted-instrument path uses only the model backend; no adapter calls occur.
    const external_effects_disabled = model_backend.isEffectFree();
    return buildReplayVerification(divergences, external_effects_disabled);
}
