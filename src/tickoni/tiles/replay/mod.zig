const std = @import("std");
const adapter = @import("adapter");
const basket = @import("basket");
const drift = @import("drift");
const model = @import("model");
const portfolio = @import("portfolio");
const trade_ticket = @import("trade_ticket");
const tkpoly = @import("tkpoly");
const capsule_mod = @import("capsule.zig");
const hash_mod = @import("hash.zig");

// Capsule wire format, version checking, and fixture-file loading live in
// capsule.zig; aliased here so the verify orchestration below and its tests
// keep using bare names — see finding 22 in
// doc/strategy/roadmap/backlog/audits/tech_debt.md.
const replay_capsule_schema_version = capsule_mod.replay_capsule_schema_version;
const ReplayCapsuleWire = capsule_mod.ReplayCapsuleWire;
const DivergenceTracker = capsule_mod.DivergenceTracker;
const loadReplayCapsule = capsule_mod.loadReplayCapsule;
const checkCapsuleVersions = capsule_mod.checkCapsuleVersions;
const hasAdapterOperation = capsule_mod.hasAdapterOperation;
const findAdapterSubstitution = capsule_mod.findAdapterSubstitution;
const fixtureDir = capsule_mod.fixtureDir;
const loadModelFixtureContent = capsule_mod.loadModelFixtureContent;
const loadPaperFixture = capsule_mod.loadPaperFixture;

// Replay-critical hash helpers live in hash.zig; re-exported (not just
// aliased) because external callers use replay.hashBytes/hashTicket/etc.
pub const hashBytes = hash_mod.hashBytes;
pub const hashQuoteSnapshot = hash_mod.hashQuoteSnapshot;
pub const hashAffordability = hash_mod.hashAffordability;
pub const hashTicket = hash_mod.hashTicket;
pub const hashPaperResult = hash_mod.hashPaperResult;

pub const ReplayVerification = struct {
    external_effects_disabled: bool,
    replay_match: bool,
    divergence_count: u64,
    first_divergent_field: []const u8,
    first_divergent_seq: u64,
};

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
    drift_contract: *const drift.DriftContract,
) !ReplayVerification {
    var loaded = try loadReplayCapsule(allocator, io, capsule_path);
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    const fixture_dir = fixtureDir(capsule_path);
    var divergences = DivergenceTracker{};
    try checkCapsuleVersions(capsule, &divergences);

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
        !std.mem.eql(u8, capsule.model_substitutions[0].fixture_file, "fixture_model_response_gemma4.json"))
        divergences.note("model_fixture_file", 3);
    if (proposed_basket.thesis_id != 0 and
        capsule.model_substitutions.len > 0 and
        proposed_basket.thesis_id != capsule.model_substitutions[0].request_hash)
        divergences.note("model_request_hash", 3);

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
    if (capsule.expected_rebalance_hash) |expected| {
        if (drift.hashRebalanceSuggestion(&drift_contract.rebalance_suggestion) != expected)
            divergences.note("rebalance_hash", 11);
    } else {
        divergences.note("rebalance_hash_missing", 11);
    }
    if (capsule.expected_payment_update_hash) |expected| {
        if (drift.hashPaymentProposalUpdate(&drift_contract.payment_proposal_update) != expected)
            divergences.note("payment_update_hash", 13);
    } else {
        divergences.note("payment_update_hash_missing", 13);
    }
    if (capsule.replay_assertions.rebalance_requires_user_action) |expected| {
        if (drift_contract.rebalance_suggestion.requires_user_action != expected)
            divergences.note("rebalance_requires_user_action", 11);
    }
    if (capsule.replay_assertions.payment_update_requires_user_action) |expected| {
        if (drift_contract.payment_proposal_update.requires_user_action != expected)
            divergences.note("payment_update_requires_user_action", 13);
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
        if (model_content.hash != capsule.model_substitutions[0].response_hash)
            divergences.note("model_response_hash", 3);
    }

    var fixture_backend = try adapter.FixtureBackend.initFromDir(allocator, io, fixture_dir);
    const account = switch (try fixture_backend.call(.{
        .operation = .portfolio_snapshot,
        .account_id = ticket.account_id,
    })) {
        .portfolio_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, proposed_basket);
    if (findAdapterSubstitution(capsule, "portfolio_snapshot")) |substitution| {
        if (substitution.request_hash != hashBytes("portfolio.read"))
            divergences.note("portfolio_request_hash", 4);
        if (substitution.response_hash != hashAffordability(affordability))
            divergences.note("portfolio_response_hash", 4);
    } else {
        divergences.note("portfolio_substitution_missing", 4);
    }

    const quote_snapshot = switch (try fixture_backend.call(.{
        .operation = .quote_snapshot,
        .account_id = proposed_basket.account_id,
        .ticker_count = proposed_basket.instrument_count,
        .tickers = blk: {
            var tickers = std.mem.zeroes([basket.max_basket_instruments][portfolio.max_ticker_len]u8);
            for (proposed_basket.instruments[0..proposed_basket.instrument_count], 0..) |instrument, i| {
                @memcpy(tickers[i][0..instrument.ticker_len], instrument.tickerSlice());
            }
            break :blk tickers;
        },
    })) {
        .quote_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };
    if (findAdapterSubstitution(capsule, "quote_snapshot")) |substitution| {
        if (substitution.request_hash != proposed_basket.basket_id)
            divergences.note("quote_request_hash", 5);
        if (substitution.response_hash != hashQuoteSnapshot(&quote_snapshot))
            divergences.note("quote_response_hash", 5);
    } else {
        divergences.note("quote_substitution_missing", 5);
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
        if (substitution.request_hash != hashTicket(ticket)) divergences.note("paper_request_hash", 7);
        if (paper_result.total_filled_cents != ticket.target_notional_cents) divergences.note("paper_fill_total", 7);
        if (hashPaperResult(&paper_result) != substitution.response_hash)
            divergences.note("adapter_response_hash", 7);
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
    drift_contract: *const drift.DriftContract,
) !ReplayVerification {
    return verifyAllowedTradeWithCapsulePath(
        allocator,
        io,
        "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule.json",
        model_backend,
        adapter_backend,
        proposed_basket,
        ticket,
        drift_contract,
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
    const capsule_path = "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_oversized_25000.json";
    var loaded = try loadReplayCapsule(allocator, io, capsule_path);
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    const fixture_dir = fixtureDir(capsule_path);
    var divergences = DivergenceTracker{};
    try checkCapsuleVersions(capsule, &divergences);

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
    if (proposed_basket.thesis_id != 0 and
        capsule.model_substitutions.len > 0 and
        proposed_basket.thesis_id != capsule.model_substitutions[0].request_hash)
        divergences.note("model_request_hash", 3);

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
        if (model_content.hash != capsule.model_substitutions[0].response_hash)
            divergences.note("model_response_hash", 3);
    }

    var fixture_backend = try adapter.FixtureBackend.initFromDir(allocator, io, fixture_dir);
    const account = switch (try fixture_backend.call(.{
        .operation = .portfolio_snapshot,
        .account_id = ticket.account_id,
    })) {
        .portfolio_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, proposed_basket);
    if (findAdapterSubstitution(capsule, "portfolio_snapshot")) |substitution| {
        if (substitution.request_hash != hashBytes("portfolio.read"))
            divergences.note("portfolio_request_hash", 4);
        if (substitution.response_hash != hashAffordability(affordability))
            divergences.note("portfolio_response_hash", 4);
    } else {
        divergences.note("portfolio_substitution_missing", 4);
    }

    const quote_snapshot = switch (try fixture_backend.call(.{
        .operation = .quote_snapshot,
        .account_id = proposed_basket.account_id,
        .ticker_count = proposed_basket.instrument_count,
        .tickers = blk: {
            var tickers = std.mem.zeroes([basket.max_basket_instruments][portfolio.max_ticker_len]u8);
            for (proposed_basket.instruments[0..proposed_basket.instrument_count], 0..) |instrument, i| {
                @memcpy(tickers[i][0..instrument.ticker_len], instrument.tickerSlice());
            }
            break :blk tickers;
        },
    })) {
        .quote_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };
    if (findAdapterSubstitution(capsule, "quote_snapshot")) |substitution| {
        if (substitution.request_hash != proposed_basket.basket_id)
            divergences.note("quote_request_hash", 5);
        if (substitution.response_hash != hashQuoteSnapshot(&quote_snapshot))
            divergences.note("quote_response_hash", 5);
    } else {
        divergences.note("quote_substitution_missing", 5);
    }

    const external_effects_disabled = model_backend.isEffectFree() and adapter_backend.isEffectFree();
    return buildReplayVerification(divergences, external_effects_disabled);
}

pub fn verifyRestrictedInstrumentBlock(
    allocator: std.mem.Allocator,
    io: std.Io,
    proposed_basket: *const basket.Basket,
    requested_ticker: []const u8,
) !ReplayVerification {
    const capsule_path = "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_restricted_soxl.json";
    var loaded = try loadReplayCapsule(allocator, io, capsule_path);
    defer loaded.deinit(allocator);

    const capsule = loaded.parsed.value;
    var divergences = DivergenceTracker{};
    try checkCapsuleVersions(capsule, &divergences);

    if (!capsule.replay_assertions.no_live_model_call) divergences.note("no_live_model_call", 5);
    if (!capsule.replay_assertions.no_live_adapter_call) divergences.note("no_live_adapter_call", 5);
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences.note("no_paper_fill_emitted", 5);
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "deny")) divergences.note("policy_outcome", 2);
    if (capsule.replay_assertions.affordability_outcome_matches.len != 0) divergences.note("affordability_outcome", 5);
    if (capsule.ticket_id.len != 0) divergences.note("ticket_id", 5);
    if (capsule.model_substitutions.len != 0) divergences.note("model_substitution_count", 3);
    if (capsule.adapter_substitutions.len != 0) divergences.note("adapter_substitution_count", 5);
    if (capsule.expected_basket_id) |expected| {
        if (proposed_basket.basket_id != expected) divergences.note("basket_id", 1);
    } else {
        divergences.note("basket_id_missing", 1);
    }
    if (proposed_basket.rejected_count == 0) divergences.note("rejected_count", 2);
    if (!std.mem.eql(u8, requested_ticker, "SOXL")) divergences.note("requested_ticker", 2);

    if (capsule.replay_assertions.failed_scope_dim_matches) |expected| {
        if (!std.mem.eql(u8, expected, "restricted_instrument")) divergences.note("failed_scope_dim", 4);
    } else {
        divergences.note("failed_scope_dim", 4);
    }
    // Restricted-instrument path performs no model or adapter work.
    const external_effects_disabled = true;
    return buildReplayVerification(divergences, external_effects_disabled);
}

const AllowedReplayFixture = struct {
    proposed_basket: basket.Basket,
    ticket: trade_ticket.TradeTicket,
};

fn loadExpectedBasketId(
    allocator: std.mem.Allocator,
    io: std.Io,
    capsule_path: []const u8,
) !u64 {
    var loaded = try loadReplayCapsule(
        allocator,
        io,
        capsule_path,
    );
    defer loaded.deinit(allocator);

    return loaded.parsed.value.expected_basket_id orelse return error.MissingExpectedBasketId;
}

fn buildAllowedReplayFixture(allocator: std.mem.Allocator, io: std.Io) !AllowedReplayFixture {
    const expected_basket_id = try loadExpectedBasketId(
        allocator,
        io,
        "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule.json",
    );
    var loaded = try loadReplayCapsule(
        allocator,
        io,
        "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule.json",
    );
    defer loaded.deinit(allocator);

    var proposed_basket: basket.Basket = std.mem.zeroes(basket.Basket);
    proposed_basket.basket_id = expected_basket_id;
    proposed_basket.thesis_id = loaded.parsed.value.model_substitutions[0].request_hash;
    proposed_basket.account_id = 2001;
    proposed_basket.target_notional_cents = 200_000;
    proposed_basket.catalog_schema_version = 2;
    proposed_basket.instrument_count = 7;
    proposed_basket.total_allocated_cents = 200_000;

    const line_specs = [_]struct {
        ticker: []const u8,
        asset_class: @FieldType(basket.BasketInstrument, "asset_class"),
        instrument_type: @FieldType(basket.BasketInstrument, "instrument_type"),
        allocation_cents: i64,
        weight_bp: u32,
    }{
        .{ .ticker = "NVDA", .asset_class = .equity, .instrument_type = .stock, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "AMD", .asset_class = .equity, .instrument_type = .stock, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "AVGO", .asset_class = .equity, .instrument_type = .stock, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "MSFT", .asset_class = .equity, .instrument_type = .stock, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "AMZN", .asset_class = .equity, .instrument_type = .stock, .allocation_cents = 25_000, .weight_bp = 1_250 },
        .{ .ticker = "BOTZ", .asset_class = .equity, .instrument_type = .etf, .allocation_cents = 37_500, .weight_bp = 1_875 },
        .{ .ticker = "SOXX", .asset_class = .equity, .instrument_type = .etf, .allocation_cents = 37_500, .weight_bp = 1_875 },
    };
    for (line_specs, 0..) |spec, i| {
        proposed_basket.instruments[i].ticker_len = @intCast(spec.ticker.len);
        @memcpy(proposed_basket.instruments[i].ticker[0..spec.ticker.len], spec.ticker);
        proposed_basket.instruments[i].asset_class = spec.asset_class;
        proposed_basket.instruments[i].instrument_type = spec.instrument_type;
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
        "ticket_ai_infra_2000_market",
    );
    tkpoly.applyTradeGuardrails(&ticket, affordability, 250_000);

    return .{
        .proposed_basket = proposed_basket,
        .ticket = ticket,
    };
}

fn testCapsule() ReplayCapsuleWire {
    return .{
        .ticket_id = "ticket_test",
        .schema_version = replay_capsule_schema_version,
        .catalog_schema_version = basket.catalog.catalog_schema_version,
        .taxonomy_version = basket.catalog.sector_taxonomy_version,
        .policy_version = tkpoly.trade_policy_version,
        .model_substitutions = &.{},
        .adapter_substitutions = &.{},
        .replay_assertions = .{
            .no_live_model_call = true,
            .no_live_adapter_call = true,
            .no_paper_fill_emitted = true,
            .affordability_outcome_matches = "",
            .policy_outcome_matches = "",
        },
    };
}

test "checkCapsuleVersions: matching versions produce no divergence" {
    var divergences = DivergenceTracker{};
    try checkCapsuleVersions(testCapsule(), &divergences);
    try std.testing.expectEqual(@as(u64, 0), divergences.count);
}

test "checkCapsuleVersions: catalog_schema_version mismatch is a soft divergence" {
    var capsule = testCapsule();
    capsule.catalog_schema_version += 1;
    var divergences = DivergenceTracker{};
    try checkCapsuleVersions(capsule, &divergences);
    try std.testing.expectEqual(@as(u64, 1), divergences.count);
    try std.testing.expectEqualStrings("catalog_schema_version", divergences.first_field);
}

test "checkCapsuleVersions: taxonomy_version mismatch is a soft divergence" {
    var capsule = testCapsule();
    capsule.taxonomy_version += 1;
    var divergences = DivergenceTracker{};
    try checkCapsuleVersions(capsule, &divergences);
    try std.testing.expectEqual(@as(u64, 1), divergences.count);
    try std.testing.expectEqualStrings("taxonomy_version", divergences.first_field);
}

test "checkCapsuleVersions: policy_version mismatch is a soft divergence" {
    var capsule = testCapsule();
    capsule.policy_version = "v0";
    var divergences = DivergenceTracker{};
    try checkCapsuleVersions(capsule, &divergences);
    try std.testing.expectEqual(@as(u64, 1), divergences.count);
    try std.testing.expectEqualStrings("policy_version", divergences.first_field);
}

test "checkCapsuleVersions: unsupported schema_version is a hard reject" {
    var capsule = testCapsule();
    capsule.schema_version += 1;
    var divergences = DivergenceTracker{};
    try std.testing.expectError(
        error.UnsupportedCapsuleSchemaVersion,
        checkCapsuleVersions(capsule, &divergences),
    );
}

test "verifyAllowedTradeWithCapsulePath marks live model backends as external effects" {
    const fixture = try buildAllowedReplayFixture(std.testing.allocator, std.testing.io);
    var model_backend_impl = model.HttpBackend{
        .endpoint = "http://127.0.0.1:65535/v1",
        .io = std.testing.io,
    };
    var model_backend = model_backend_impl.asBackend();
    var adapter_backend_impl = adapter.FixtureBackend{};
    var adapter_backend = adapter_backend_impl.asBackend();
    var drift_contract = std.mem.zeroes(drift.DriftContract);

    const replay_result = try verifyAllowedTrade(
        std.testing.allocator,
        std.testing.io,
        &model_backend,
        &adapter_backend,
        &fixture.proposed_basket,
        &fixture.ticket,
        &drift_contract,
    );
    try std.testing.expect(!replay_result.external_effects_disabled);
}

test "verifyAllowedTradeWithCapsulePath detects tampered paper fill hashes" {
    const fixture = try buildAllowedReplayFixture(std.testing.allocator, std.testing.io);
    var model_backend_impl = model.FixtureBackend{};
    var model_backend = model_backend_impl.asBackend();
    var adapter_backend_impl = adapter.FixtureBackend{};
    var adapter_backend = adapter_backend_impl.asBackend();
    var drift_contract = std.mem.zeroes(drift.DriftContract);

    const replay_result = try verifyAllowedTradeWithCapsulePath(
        std.testing.allocator,
        std.testing.io,
        "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_tampered_paper_fill.json",
        &model_backend,
        &adapter_backend,
        &fixture.proposed_basket,
        &fixture.ticket,
        &drift_contract,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(!replay_result.replay_match);
    try std.testing.expect(replay_result.divergence_count >= 1);
    try std.testing.expect(replay_result.first_divergent_field.len > 0);
}

test "verifyRestrictedInstrumentBlock stays offline with fixture model backend" {
    var proposed_basket: basket.Basket = std.mem.zeroes(basket.Basket);
    proposed_basket.basket_id = try loadExpectedBasketId(
        std.testing.allocator,
        std.testing.io,
        "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_restricted_soxl.json",
    );
    proposed_basket.rejected_count = 1;
    proposed_basket.rejected[0].ticker_len = 4;
    @memcpy(proposed_basket.rejected[0].ticker[0..4], "SOXL");
    proposed_basket.rejected[0].reason_code = .restricted_instrument;
    const replay_result = try verifyRestrictedInstrumentBlock(
        std.testing.allocator,
        std.testing.io,
        &proposed_basket,
        "SOXL",
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
}
