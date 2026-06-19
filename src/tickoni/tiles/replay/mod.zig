const std = @import("std");
const adapter = @import("adapter");
const basket = @import("basket");
const model = @import("model");
const trade_ticket = @import("trade_ticket");
const tkpoly = @import("tkpoly");

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

// ---------------------------------------------------------------------------
// Fixture loading for substitution replay
// ---------------------------------------------------------------------------

fn fixtureDir(capsule_path: []const u8) []const u8 {
    const last_slash = std.mem.lastIndexOfScalar(u8, capsule_path, '/') orelse return ".";
    return capsule_path[0..last_slash];
}

const ModelFixtureContentWire = struct {
    content: std.json.Value,
};

const ModelFixtureContent = struct {
    len: usize,
    hash: u64,
};

fn loadModelFixtureContent(
    allocator: std.mem.Allocator,
    io: std.Io,
    fixture_dir: []const u8,
    filename: []const u8,
) !ModelFixtureContent {
    var path_buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ fixture_dir, filename });
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(32 * 1024));
    defer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(ModelFixtureContentWire, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const content_json = try std.json.Stringify.valueAlloc(allocator, parsed.value.content, .{});
    defer allocator.free(content_json);
    return .{ .len = content_json.len, .hash = hashBytes(content_json) };
}

fn parseQuantityMicros(s: []const u8) !u64 {
    const dot_pos = std.mem.indexOfScalar(u8, s, '.') orelse {
        const whole = try std.fmt.parseInt(u64, s, 10);
        return whole * 1_000_000;
    };
    const whole = try std.fmt.parseInt(u64, s[0..dot_pos], 10);
    const frac_str = s[dot_pos + 1 ..];
    var frac: u64 = 0;
    var multiplier: u64 = 100_000;
    for (frac_str) |c| {
        if (c < '0' or c > '9') return error.InvalidQuantity;
        frac += (c - '0') * multiplier;
        multiplier /= 10;
        if (multiplier == 0) break;
    }
    return whole * 1_000_000 + frac;
}

const PaperFillFixtureWire = struct {
    ticker: []const u8,
    quantity: []const u8,
    fill_price_cents: i64,
    filled_notional_cents: i64,
};

const PaperFixtureWire = struct {
    paper_order_id: []const u8,
    ticket_id: []const u8,
    total_filled_cents: i64,
    fills: []const PaperFillFixtureWire,
    resulting_account_snapshot: struct {
        cash_cents: i64,
        buying_power_cents: i64,
        day_notional_used_cents: i64,
        month_notional_used_cents: i64,
    },
};

fn loadPaperFixture(
    allocator: std.mem.Allocator,
    io: std.Io,
    fixture_dir: []const u8,
    filename: []const u8,
    account_id: u32,
) !trade_ticket.PaperExecutionResult {
    var path_buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ fixture_dir, filename });
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(32 * 1024));
    defer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(PaperFixtureWire, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const w = parsed.value;
    if (w.fills.len > basket.max_basket_instruments) return error.TooManyFills;
    var result: trade_ticket.PaperExecutionResult = std.mem.zeroes(trade_ticket.PaperExecutionResult);
    if (w.paper_order_id.len > trade_ticket.max_paper_order_id_len) return error.PaperOrderIdTooLong;
    result.paper_order_id_len = @intCast(w.paper_order_id.len);
    @memcpy(result.paper_order_id[0..result.paper_order_id_len], w.paper_order_id);
    if (w.ticket_id.len > trade_ticket.max_ticket_id_len) return error.TicketIdTooLong;
    result.ticket_id_len = @intCast(w.ticket_id.len);
    @memcpy(result.ticket_id[0..result.ticket_id_len], w.ticket_id);
    result.account_id = account_id;
    result.status = .filled;
    result.total_filled_cents = w.total_filled_cents;
    result.fill_count = @intCast(w.fills.len);
    for (w.fills, 0..) |wf, i| {
        if (wf.ticker.len > trade_ticket.max_ticker_len) return error.TickerTooLong;
        result.fills[i].ticker = std.mem.zeroes([trade_ticket.max_ticker_len]u8);
        @memcpy(result.fills[i].ticker[0..wf.ticker.len], wf.ticker);
        result.fills[i].ticker_len = @intCast(wf.ticker.len);
        result.fills[i].quantity_micros = try parseQuantityMicros(wf.quantity);
        result.fills[i].fill_price_cents = wf.fill_price_cents;
        result.fills[i].filled_notional_cents = wf.filled_notional_cents;
    }
    result.resulting_account_snapshot = .{
        .cash_cents = w.resulting_account_snapshot.cash_cents,
        .buying_power_cents = w.resulting_account_snapshot.buying_power_cents,
        .day_notional_used_cents = w.resulting_account_snapshot.day_notional_used_cents,
        .month_notional_used_cents = w.resulting_account_snapshot.month_notional_used_cents,
    };
    return result;
}

// ---------------------------------------------------------------------------
// Public verify functions
// ---------------------------------------------------------------------------

pub fn verifyAllowedTradeWithCapsulePath(
    allocator: std.mem.Allocator,
    io: std.Io,
    capsule_path: []const u8,
    model_backend: *const model.Backend,
    adapter_backend: *const adapter.Backend,
    proposed_basket: *const basket.Basket,
    ticket: *const trade_ticket.TradeTicket,
) !ReplayVerification {
    var loaded = try loadReplayCapsule(allocator, io, capsule_path);
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    const fixture_dir = fixtureDir(capsule_path);
    var divergences = DivergenceTracker{};

    if (!capsule.replay_assertions.no_live_model_call) divergences.note("no_live_model_call", 8);
    if (!capsule.replay_assertions.no_live_adapter_call) divergences.note("no_live_adapter_call", 8);
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences.note("no_paper_fill_emitted", 8);
    if (!std.mem.eql(u8, capsule.replay_assertions.affordability_outcome_matches, "allow")) divergences.note("affordability_outcome", 4);
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "allow")) divergences.note("policy_outcome", 2);
    if (!std.mem.eql(u8, ticket.ticketIdSlice(), capsule.ticket_id)) divergences.note("ticket_id", 6);
    if (ticket.target_notional_cents != proposed_basket.total_allocated_cents) divergences.note("target_notional_cents", 6);
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

    // Load model fixture and verify substituted content hash.
    if (capsule.model_substitutions.len > 0) {
        const model_content = try loadModelFixtureContent(
            allocator,
            io,
            fixture_dir,
            capsule.model_substitutions[0].fixture_file,
        );
        if (model_content.len == 0) divergences.note("model_response_content", 3);
        if (capsule.model_substitutions[0].expected_response_hash) |expected| {
            if (model_content.hash != expected) divergences.note("model_response_hash", 3);
        } else {
            divergences.note("model_response_hash_missing", 3);
        }
    }

    // Load paper order fixture and verify substituted result hash.
    if (findAdapterSubstitution(capsule, "paper_order")) |substitution| {
        const paper_result = try loadPaperFixture(
            allocator,
            io,
            fixture_dir,
            substitution.fixture_file,
            ticket.account_id,
        );
        if (paper_result.total_filled_cents != ticket.target_notional_cents) divergences.note("paper_fill_total", 7);
        if (substitution.expected_response_hash) |expected| {
            if (hashPaperResult(&paper_result) != expected) divergences.note("adapter_response_hash", 7);
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
) !ReplayVerification {
    return verifyAllowedTradeWithCapsulePath(
        allocator,
        io,
        "src/tickoni/test/fixtures/investment/replay_capsule.json",
        model_backend,
        adapter_backend,
        proposed_basket,
        ticket,
    );
}

pub fn verifyOversizedTradeBlock(
    allocator: std.mem.Allocator,
    io: std.Io,
    model_backend: *const model.Backend,
    adapter_backend: *const adapter.Backend,
    proposed_basket: *const basket.Basket,
    ticket: *const trade_ticket.TradeTicket,
) !ReplayVerification {
    const capsule_path = "src/tickoni/test/fixtures/investment/replay_capsule_oversized_25000.json";
    var loaded = try loadReplayCapsule(allocator, io, capsule_path);
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    const fixture_dir = fixtureDir(capsule_path);
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

    // Load model fixture and verify substituted content hash.
    if (capsule.model_substitutions.len > 0) {
        const model_content = try loadModelFixtureContent(
            allocator,
            io,
            fixture_dir,
            capsule.model_substitutions[0].fixture_file,
        );
        if (model_content.len == 0) divergences.note("model_response_content", 3);
        if (capsule.model_substitutions[0].expected_response_hash) |expected| {
            if (model_content.hash != expected) divergences.note("model_response_hash", 3);
        } else {
            divergences.note("model_response_hash_missing", 3);
        }
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
) !ReplayVerification {
    const capsule_path = "src/tickoni/test/fixtures/investment/replay_capsule_restricted_soxl.json";
    var loaded = try loadReplayCapsule(allocator, io, capsule_path);
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    const fixture_dir = fixtureDir(capsule_path);
    var divergences = DivergenceTracker{};

    if (!capsule.replay_assertions.no_live_model_call) divergences.note("no_live_model_call", 5);
    if (!capsule.replay_assertions.no_live_adapter_call) divergences.note("no_live_adapter_call", 5);
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences.note("no_paper_fill_emitted", 5);
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "deny")) divergences.note("policy_outcome", 2);
    if (capsule.replay_assertions.affordability_outcome_matches.len != 0) divergences.note("affordability_outcome", 5);
    if (capsule.ticket_id.len != 0) divergences.note("ticket_id", 5);
    if (capsule.model_substitutions.len != 1) divergences.note("model_substitution_count", 3);
    if (capsule.adapter_substitutions.len != 0) divergences.note("adapter_substitution_count", 5);
    if (capsule.model_substitutions.len > 0 and
        !std.mem.eql(u8, capsule.model_substitutions[0].fixture_file, "model_response_gemma4.json"))
        divergences.note("model_fixture_file", 3);
    if (proposed_basket.rejected_count == 0) divergences.note("rejected_count", 2);
    if (!std.mem.eql(u8, requested_ticker, "SOXL")) divergences.note("requested_ticker", 2);

    if (capsule.replay_assertions.failed_scope_dim_matches) |expected| {
        if (!std.mem.eql(u8, expected, "restricted_instrument")) divergences.note("failed_scope_dim", 4);
    } else {
        divergences.note("failed_scope_dim", 4);
    }

    // Load model fixture and verify substituted content hash.
    if (capsule.model_substitutions.len > 0) {
        const model_content = try loadModelFixtureContent(
            allocator,
            io,
            fixture_dir,
            capsule.model_substitutions[0].fixture_file,
        );
        if (model_content.len == 0) divergences.note("model_response_content", 3);
        if (capsule.model_substitutions[0].expected_response_hash) |expected| {
            if (model_content.hash != expected) divergences.note("model_response_hash", 3);
        } else {
            divergences.note("model_response_hash_missing", 3);
        }
    }

    // Restricted-instrument path uses only the model backend; no adapter calls occur.
    const external_effects_disabled = model_backend.isEffectFree();
    return buildReplayVerification(divergences, external_effects_disabled);
}

const AllowedReplayFixture = struct {
    proposed_basket: basket.Basket,
    ticket: trade_ticket.TradeTicket,
};

fn loadExpectedAllowedBasketId(allocator: std.mem.Allocator, io: std.Io) !u64 {
    var loaded = try loadReplayCapsule(
        allocator,
        io,
        "src/tickoni/test/fixtures/investment/replay_capsule.json",
    );
    defer loaded.deinit(allocator);

    return loaded.parsed.value.expected_basket_id orelse return error.MissingExpectedBasketId;
}

fn buildAllowedReplayFixture(allocator: std.mem.Allocator, io: std.Io) !AllowedReplayFixture {
    const portfolio = @import("portfolio");
    const expected_basket_id = try loadExpectedAllowedBasketId(allocator, io);

    var proposed_basket: basket.Basket = std.mem.zeroes(basket.Basket);
    proposed_basket.basket_id = expected_basket_id;
    proposed_basket.account_id = 2001;
    proposed_basket.target_notional_cents = 200_000;
    proposed_basket.catalog_schema_version = 1;
    proposed_basket.instrument_count = 7;
    proposed_basket.total_allocated_cents = 200_000;

    const line_specs = [_]struct {
        ticker: []const u8,
        asset_class: @FieldType(basket.BasketInstrument, "asset_class"),
        allocation_cents: i64,
        weight_bp: u32,
    }{
        .{ .ticker = "NVDA", .asset_class = .equity, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "AMD", .asset_class = .equity, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "AVGO", .asset_class = .equity, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "MSFT", .asset_class = .equity, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "AMZN", .asset_class = .equity, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "BOTZ", .asset_class = .etf, .allocation_cents = 37_500, .weight_bp = 1_875 },
        .{ .ticker = "SOXX", .asset_class = .etf, .allocation_cents = 37_500, .weight_bp = 1_875 },
    };
    for (line_specs, 0..) |spec, i| {
        proposed_basket.instruments[i].ticker_len = @intCast(spec.ticker.len);
        @memcpy(proposed_basket.instruments[i].ticker[0..spec.ticker.len], spec.ticker);
        proposed_basket.instruments[i].asset_class = spec.asset_class;
        proposed_basket.instruments[i].allocation_cents = spec.allocation_cents;
        proposed_basket.instruments[i].weight_bp = spec.weight_bp;
    }

    var quote_request = adapter.AdapterRequest{
        .operation = .quote_snapshot,
        .account_id = proposed_basket.account_id,
        .ticker_count = proposed_basket.instrument_count,
    };
    for (proposed_basket.instruments[0..proposed_basket.instrument_count], 0..) |instrument, i| {
        @memcpy(quote_request.tickers[i][0..instrument.ticker_len], instrument.tickerSlice());
    }

    const fixture_backend = adapter.FixtureBackend{};
    const quote_result = try fixture_backend.call(quote_request);
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |snapshot| snapshot,
        else => unreachable,
    };
    const affordability = try portfolio.checkBasketAffordability(
        &fixture_backend.account_snapshot,
        &proposed_basket,
    );
    var ticket = try trade_ticket.buildMarketBuyTicket(
        &proposed_basket,
        &quote_snapshot,
        affordability,
        "ticket_v1_1_ai_infra_2000_market",
    );
    tkpoly.applyTradeGuardrails(&ticket, affordability, 250_000);

    return .{
        .proposed_basket = proposed_basket,
        .ticket = ticket,
    };
}

test "verifyAllowedTradeWithCapsulePath marks live model backends as external effects" {
    const fixture = try buildAllowedReplayFixture(std.testing.allocator, std.testing.io);
    var model_backend = model.Backend{ .http = .{
        .endpoint = "http://127.0.0.1:65535/v1",
        .io = std.testing.io,
    } };
    var adapter_backend = adapter.Backend{ .fixture = .{} };

    const replay_result = try verifyAllowedTrade(
        std.testing.allocator,
        std.testing.io,
        &model_backend,
        &adapter_backend,
        &fixture.proposed_basket,
        &fixture.ticket,
    );
    try std.testing.expect(!replay_result.external_effects_disabled);
}

test "verifyAllowedTradeWithCapsulePath detects tampered paper fill hashes" {
    const fixture = try buildAllowedReplayFixture(std.testing.allocator, std.testing.io);
    var model_backend = model.Backend{ .fixture = .{} };
    var adapter_backend = adapter.Backend{ .fixture = .{} };

    const replay_result = try verifyAllowedTradeWithCapsulePath(
        std.testing.allocator,
        std.testing.io,
        "src/tickoni/test/fixtures/investment/replay_capsule_tampered_paper_fill.json",
        &model_backend,
        &adapter_backend,
        &fixture.proposed_basket,
        &fixture.ticket,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(!replay_result.replay_match);
    try std.testing.expect(replay_result.divergence_count >= 1);
    try std.testing.expect(replay_result.first_divergent_field.len > 0);
}

test "verifyRestrictedInstrumentBlock stays offline with fixture model backend" {
    var proposed_basket: basket.Basket = std.mem.zeroes(basket.Basket);
    proposed_basket.rejected_count = 1;
    proposed_basket.rejected[0].ticker_len = 4;
    @memcpy(proposed_basket.rejected[0].ticker[0..4], "SOXL");
    proposed_basket.rejected[0].reason_code = .restricted_instrument;
    var model_backend = model.Backend{ .fixture = .{} };

    const replay_result = try verifyRestrictedInstrumentBlock(
        std.testing.allocator,
        std.testing.io,
        &model_backend,
        &proposed_basket,
        "SOXL",
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
}
