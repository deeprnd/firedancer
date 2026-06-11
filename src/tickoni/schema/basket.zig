/// Basket construction schema for V1.1.S3.
///
/// Basket: result of deterministic construction from InvestorIntent and the
/// instrument catalog.  Instruments are scope-checked (US market, NYSE/NASDAQ
/// venues, equity/ETF asset classes, theme tags, restricted-instrument
/// denylist) and allocated using equal-weight with optional ETF preference and
/// max-single-name concentration cap.
///
/// build(): same InvestorIntent and thesis_id always produce the same Basket.
/// basket_id is a content hash of the constructed basket (computeBasketHash),
/// distinct from thesis_id so replay can detect basket-construction drift
/// independent of the source thesis.
///
/// Canonical encoding: binary protobuf via fd_pb_encoder, following the
/// audit codec pattern in src/tickoni/codec/audit_pb.c.  Encoding is not yet
/// implemented; this comment marks the planned format so the schema is not
/// extended incompatibly before it is defined.
const std = @import("std");
const thesis = @import("thesis.zig");
const cat = @import("catalog.zig");
const thesis_cabi = @import("thesis_cabi");

pub const basket_schema_version: u16 = 1;

// Capacity invariants: the catalog must fit within the rejection buffer so no
// rejected candidate is silently dropped.  Increment max_rejected_instruments
// if the catalog grows beyond 24 entries.
comptime {
    std.debug.assert(cat.catalog.len <= max_rejected_instruments);
}

/// Maximum instruments in one basket.
pub const max_basket_instruments: usize = 16;
/// Maximum rejected candidates listed (bounded by catalog size).
pub const max_rejected_instruments: usize = 24;
/// Maximum bytes in a per-instrument rationale string.
pub const max_rationale_len: usize = 80;
/// Maximum bytes in a per-rejected reason string.
pub const max_reason_len: usize = 80;

// ---------------------------------------------------------------------------
// Scale constants
// ---------------------------------------------------------------------------

/// 100.00% expressed in basis-point notation (1 bp = 0.01%).
pub const bp_denom: u32 = 10_000;
/// Multiplier to convert an integer percentage (0–100) to basis points.
pub const pct_to_bp: u32 = 100;
/// Number of cents in one dollar.
pub const cents_per_dollar: i64 = 100;

// ---------------------------------------------------------------------------
// Types (T1)
// ---------------------------------------------------------------------------

/// Why a theme-matching instrument was excluded from the basket.
pub const RejectionReason = enum(u8) {
    /// instrument.restricted == true; restriction_reason carries the detail.
    restricted_instrument = 0,
    /// Asset class not in intent.allowed_asset_classes.
    wrong_asset_class = 1,
    /// Market != intent.market.
    /// Forward-looking: currently unreachable because Market only has .us and
    /// the catalog contains only .us entries.  Will become reachable when
    /// non-US markets are added to either type.
    wrong_market = 2,
    /// Venue not in intent.venues.
    /// Forward-looking: currently unreachable because normalize() always sets
    /// venues = {nyse, nasdaq} and all catalog entries are NYSE or NASDAQ.
    /// Will become reachable when additional venues are introduced.
    wrong_venue = 3,
};

/// One instrument included in the basket with its allocation and rationale.
pub const BasketInstrument = struct {
    ticker: [cat.max_ticker_len]u8,
    ticker_len: u8,
    asset_class: cat.AssetClass,
    /// Allocation weight in basis points; 10000 = 100.0%.
    weight_bp: u32,
    /// Allocated dollars in cents for this instrument.
    allocation_cents: i64,
    rationale: [max_rationale_len]u8,
    rationale_len: u8,

    pub fn tickerSlice(self: *const BasketInstrument) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
    pub fn rationaleSlice(self: *const BasketInstrument) []const u8 {
        return self.rationale[0..self.rationale_len];
    }
};

/// One theme-matching instrument rejected from the basket with its reason.
pub const RejectedCandidate = struct {
    ticker: [cat.max_ticker_len]u8,
    ticker_len: u8,
    reason_code: RejectionReason,
    reason: [max_reason_len]u8,
    reason_len: u8,

    pub fn tickerSlice(self: *const RejectedCandidate) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
    pub fn reasonSlice(self: *const RejectedCandidate) []const u8 {
        return self.reason[0..self.reason_len];
    }
};

/// Deterministic basket produced from InvestorIntent and the instrument catalog.
pub const Basket = struct {
    /// Content hash of the basket composition (computeBasketHash).
    /// Distinct from thesis_id so replay can detect basket-construction drift.
    basket_id: u64,
    /// Content hash of the source ThesisInput (computeThesisInputHash).
    thesis_id: u64,
    account_id: u32,
    target_notional_cents: i64,
    /// Catalog schema version consulted; stamped for replay integrity.
    catalog_schema_version: u16,

    instruments: [max_basket_instruments]BasketInstrument,
    instrument_count: u8,

    rejected: [max_rejected_instruments]RejectedCandidate,
    rejected_count: u8,

    /// Set to target_notional_cents.  The rounding remainder is added to
    /// instrument[0] so the actual sum of allocation_cents equals this value.
    total_allocated_cents: i64,
};

pub const BasketError = error{
    /// All theme-matching instruments were rejected; basket cannot be built.
    NoEligibleInstruments,
};

/// Stable error codes for BasketDenialPayload, matching BasketError variants.
pub const BasketErrorCode = enum(u8) {
    no_eligible_instruments = 0,
};

/// Audit record payload for a successful basket construction.
/// Emitted by the basket-construction tile after build() succeeds.
/// basket_id is the content hash of the constructed basket (computeBasketHash).
/// thesis_id is the computeThesisInputHash() result for the source ThesisInput.
pub const BasketConstructionPayload = struct {
    thesis_id: u64,
    basket_id: u64,
    account_id: u32,
    target_notional_cents: i64,
    instrument_count: u8,
    rejected_count: u8,
    catalog_schema_version: u16,
};

/// Audit record payload for a basket construction denial.
/// Emitted by the basket-construction tile when build() fails.
pub const BasketDenialPayload = struct {
    thesis_id: u64,
    account_id: u32,
    target_notional_cents: i64,
    error_code: BasketErrorCode,
};

// ---------------------------------------------------------------------------
// Content hash
// ---------------------------------------------------------------------------

/// Compute a stable content hash over a basket's composition via fd_siphash13.
///
/// Uses tk_basket_hash() from src/tickoni/codec/thesis_hash.c.
/// Covers basket_schema_version, thesis_id, catalog_schema_version,
/// instrument_count, and per-instrument ticker, weight_bp, and allocation_cents.
/// The hash is stable across process restarts; it changes when any instrument,
/// weight, or allocation changes, making it suitable for replay integrity checks.
pub fn computeBasketHash(basket: *const Basket) u64 {
    var ticker_data: [max_basket_instruments * cat.max_ticker_len]u8 =
        std.mem.zeroes([max_basket_instruments * cat.max_ticker_len]u8);
    var weight_bps_arr: [max_basket_instruments]u32 = [_]u32{0} ** max_basket_instruments;
    var alloc_cents_arr: [max_basket_instruments]i64 = [_]i64{0} ** max_basket_instruments;
    for (0..basket.instrument_count) |i| {
        const off = i * cat.max_ticker_len;
        @memcpy(ticker_data[off..][0..cat.max_ticker_len], &basket.instruments[i].ticker);
        weight_bps_arr[i] = basket.instruments[i].weight_bp;
        alloc_cents_arr[i] = basket.instruments[i].allocation_cents;
    }
    return thesis_cabi.tk_basket_hash(
        basket.thesis_id,
        basket.catalog_schema_version,
        basket.instrument_count,
        &ticker_data,
        &weight_bps_arr,
        &alloc_cents_arr,
    );
}

// ---------------------------------------------------------------------------
// Build (T2, T3, T4, T5)
// ---------------------------------------------------------------------------

/// Construct a deterministic basket from InvestorIntent and the static catalog.
///
/// basket_id: content hash of the source ThesisInput; callers use
///   computeThesisInputHash() from thesis.zig.  Passed as a parameter so
///   basket.zig does not need to import thesis_cabi.
///
/// Design note — scope enforcement and tkpoly:
///   The checks below (market, venue, asset class, restricted-instrument
///   denylist) implement the V1.1.S3 finance-native scope filter in this schema
///   module as a provisional scaffold.  The contribution guide assigns
///   capability-envelope authority to tkpoly; when basket construction is
///   integrated into the runtime tile pipeline, these checks should be
///   expressed as capability-envelope decisions through tkpoly rather than
///   inline in the schema module.
///
/// Scope enforcement (T3):
///   - US market only
///   - NYSE and NASDAQ venues only
///   - asset classes from intent.allowed_asset_classes (equity/ETF; options,
///     futures, leveraged ETFs, inverse ETFs denied by thesis.normalize())
///   - restricted-instrument denylist (InstrumentEntry.restricted == true)
///   - sector/theme filter via filterByTheme(intent.theme)
///
/// Allocation (T4):
///   - Equal-weight baseline; ETF preference (1.5× equity base weight) when
///     both equity and ETF are in intent.allowed_asset_classes.
///   - Max-single-name cap at intent.max_single_name_pct (3 redistribution
///     iterations; if all instruments hit the cap each is capped to cap_bp and
///     the loop stops; weight_sum reflects the capped total).
///   - Total rounded to target_notional_cents; remainder added to instrument 0.
///
/// Explainability (T5):
///   - rationale string per included instrument (asset class, venue, weight,
///     dollars, ETF preference note).
///   - reason string per rejected instrument (restriction type or scope failure).
pub fn build(intent: thesis.InvestorIntent, thesis_id: u64) BasketError!Basket {
    var theme_buf: [cat.catalog.len]*const cat.InstrumentEntry = undefined;
    const theme_n = cat.filterByTheme(intent.theme, &theme_buf);

    var candidates: [max_basket_instruments]*const cat.InstrumentEntry = undefined;
    var n: usize = 0;

    var basket: Basket = std.mem.zeroes(Basket);
    basket.thesis_id = thesis_id;
    basket.account_id = intent.account_id;
    basket.target_notional_cents = intent.target_amount_cents;
    basket.catalog_schema_version = cat.catalog_schema_version;

    // Phase 1 – scope-check each theme match (T3).
    for (theme_buf[0..theme_n]) |e| {
        if (e.restricted) {
            addRejected(&basket, e, .restricted_instrument, restrictionMsg(e.restriction_reason));
            continue;
        }
        if (!intent.allowed_asset_classes.has(e.asset_class)) {
            addRejected(&basket, e, .wrong_asset_class, "Asset class not eligible (equity/ETF only)");
            continue;
        }
        if (e.market != intent.market) {
            addRejected(&basket, e, .wrong_market, "Market not in US scope");
            continue;
        }
        if (!venueAllowed(e.venue, intent.venues[0..@as(usize, intent.venue_count)])) {
            addRejected(&basket, e, .wrong_venue, "Venue not NYSE or NASDAQ");
            continue;
        }
        if (n < max_basket_instruments) {
            candidates[n] = e;
            n += 1;
        }
    }

    if (n == 0) return BasketError.NoEligibleInstruments;

    // Phase 2 – compute initial weights (T4).
    var weights: [max_basket_instruments]u32 = [_]u32{0} ** max_basket_instruments;
    const etf_preferred = intent.allowed_asset_classes.etf and intent.allowed_asset_classes.equity;
    initialWeights(candidates[0..n], etf_preferred, weights[0..n]);

    // Phase 3 – apply concentration cap (T4).
    const cap_bp: u32 = if (intent.max_single_name_pct == 0)
        bp_denom
    else
        @as(u32, intent.max_single_name_pct) * pct_to_bp;
    applyCap(weights[0..n], cap_bp);

    // Phase 4 – convert weights to allocation_cents.
    // Max sum: max_basket_instruments * bp_denom = 160000, fits in u32.
    var weight_sum: u32 = 0;
    for (weights[0..n]) |w| weight_sum += w;

    // When the cap is binding across all instruments, weight_sum is significantly
    // less than bp_denom (e.g. 5 instruments × 10% cap = 50%).  In this case,
    // use bp_denom as the denominator so weight_bp stays within the cap and the
    // total_allocated_cents reflects the cap-limited amount, not the full target.
    // A small deficit (≤ 4 × max_basket_instruments bp) is normal integer rounding
    // from initialWeights and applyCap redistribution; larger deficits are cap-induced.
    const cap_limited = (weight_sum < bp_denom) and
        (bp_denom - weight_sum > 4 * max_basket_instruments);
    const alloc_denom: i64 = if (cap_limited) bp_denom else weight_sum;

    basket.instrument_count = @intCast(n);
    var total_alloc: i64 = 0;
    for (0..n) |i| {
        // Zero-allocation invariant: with min_target_notional_cents=100, cap_bp≥100,
        // alloc = 100 * 100 / 10000 = 1 cent minimum.  Zero is unreachable given
        // the current validation bounds.
        const alloc: i64 = @divTrunc(
            intent.target_amount_cents * @as(i64, weights[i]),
            alloc_denom,
        );
        std.debug.assert(alloc > 0);
        basket.instruments[i].ticker = candidates[i].ticker;
        basket.instruments[i].ticker_len = candidates[i].ticker_len;
        basket.instruments[i].asset_class = candidates[i].asset_class;
        basket.instruments[i].allocation_cents = alloc;
        total_alloc += alloc;
    }
    if (!cap_limited) {
        // Rounding remainder to instrument 0 so total == target (T acceptance).
        basket.instruments[0].allocation_cents += intent.target_amount_cents - total_alloc;
        basket.total_allocated_cents = intent.target_amount_cents;
    } else {
        // Cap prevented full allocation; total_alloc < target is correct.
        basket.total_allocated_cents = total_alloc;
    }

    // Compute weight_bp from actual allocations so rationale matches cents.
    for (0..n) |i| {
        basket.instruments[i].weight_bp = @intCast(@divTrunc(
            basket.instruments[i].allocation_cents * @as(i64, bp_denom),
            intent.target_amount_cents,
        ));
    }

    // Phase 5 – rationale strings (T5).
    for (0..n) |i| {
        writeRationale(&basket.instruments[i], candidates[i], etf_preferred);
    }

    // basket_id: content hash of the constructed composition, distinct from
    // thesis_id so replay can detect catalog or allocation drift.
    basket.basket_id = computeBasketHash(&basket);

    return basket;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn venueAllowed(venue: cat.Venue, allowed: []const thesis.Venue) bool {
    for (allowed) |v| if (v == venue) return true;
    return false;
}

/// Assign initial weights using ETF preference (1.5× equity) when both classes
/// are allowed; otherwise equal weight.
fn initialWeights(
    candidates: []*const cat.InstrumentEntry,
    etf_preferred: bool,
    out: []u32,
) void {
    const n = candidates.len;
    if (n == 0) return;

    if (etf_preferred) {
        // Count each class; assign 3 units to ETFs, 2 units to equities.
        var n_etf: u32 = 0;
        var n_eq: u32 = 0;
        for (candidates) |e| {
            if (e.asset_class == .etf) n_etf += 1 else n_eq += 1;
        }
        const total_units: u32 = n_etf * 3 + n_eq * 2;
        if (total_units > 0) {
            for (candidates, 0..) |e, i| {
                const units: u32 = if (e.asset_class == .etf) 3 else 2;
                out[i] = units * bp_denom / total_units;
            }
            return;
        }
    }

    const base: u32 = bp_denom / @as(u32, @intCast(n));
    for (out[0..n]) |*w| w.* = base;
}

/// Iteratively cap any instrument exceeding cap_bp and redistribute excess to
/// uncapped instruments proportionally.  Runs at most 3 iterations.  If all
/// instruments exceed cap_bp (no room to redistribute), each is capped to cap_bp
/// and the loop stops; the weight_sum reflects the capped total so proportional
/// allocations remain correct.
fn applyCap(weights: []u32, cap_bp: u32) void {
    var iter: u32 = 0;
    while (iter < 3) : (iter += 1) {
        // Read pass: measure excess and uncapped total.
        var excess: u32 = 0;
        var uncapped_sum: u32 = 0;
        for (weights) |w| {
            if (w > cap_bp) {
                excess += w - cap_bp;
            } else {
                uncapped_sum += w;
            }
        }
        if (excess == 0) break;

        // Cap pass: apply cap to every over-weight instrument.
        for (weights) |*w| {
            if (w.* > cap_bp) w.* = cap_bp;
        }
        if (uncapped_sum == 0) break; // all were over cap; nothing to redistribute into

        // Redistribute excess proportionally among instruments that were under cap.
        for (weights) |*w| {
            if (w.* < cap_bp) {
                w.* += @intCast(@as(u64, excess) * @as(u64, w.*) / @as(u64, uncapped_sum));
            }
        }
    }
}

fn addRejected(
    basket: *Basket,
    e: *const cat.InstrumentEntry,
    code: RejectionReason,
    reason_str: []const u8,
) void {
    if (basket.rejected_count >= max_rejected_instruments) return;
    const rc = &basket.rejected[basket.rejected_count];
    rc.ticker = e.ticker;
    rc.ticker_len = e.ticker_len;
    rc.reason_code = code;
    rc.reason = std.mem.zeroes([max_reason_len]u8);
    const len = @min(reason_str.len, max_reason_len);
    @memcpy(rc.reason[0..len], reason_str[0..len]);
    rc.reason_len = @intCast(len);
    basket.rejected_count += 1;
}

fn restrictionMsg(reason: cat.RestrictionReason) []const u8 {
    return switch (reason) {
        .none => "Restricted (unexpected reason code)",
        .leveraged_etf => "Restricted: leveraged ETF",
        .inverse_etf => "Restricted: inverse ETF",
        .options_contract => "Restricted: options contract",
        .futures_contract => "Restricted: futures contract",
        .non_us_venue => "Restricted: non-US venue",
        .manual_denylist => "Restricted: manual denylist",
    };
}

/// Write a rationale string into out.rationale/rationale_len.
/// Format: "Eligible {equity|ETF} on {NYSE|NASDAQ}; {pct}% = ${dollars}[, ETF preferred]"
///
/// fd_cstr_printf (src/util/cstr) wraps snprintf and is available at runtime, but
/// Zig's typed std.fmt.bufPrint is used here: it keeps typed fixed-point formatting
/// (two-decimal cents display) in the owning Zig module without a C round-trip for
/// display-only strings.  src/util/cstr provides no fixed-point decimal formatting.
fn writeRationale(
    out: *BasketInstrument,
    e: *const cat.InstrumentEntry,
    etf_preferred: bool,
) void {
    const venue_str: []const u8 = if (e.venue == .nyse) "NYSE" else "NASDAQ";
    const class_str: []const u8 = if (e.asset_class == .etf) "ETF" else "equity";
    const pct_whole = out.weight_bp / pct_to_bp;
    const pct_frac = out.weight_bp % pct_to_bp;
    const dollars = @divFloor(out.allocation_cents, cents_per_dollar);
    const cents_part: i64 = @rem(out.allocation_cents, cents_per_dollar);

    // max_rationale_len (80) is always sufficient for the formatted string given
    // bounded venue/class names, weight_bp <= bp_denom, and allocation bounded
    // by max_target_notional_cents.  bufPrint errors are unreachable.
    var buf: [max_rationale_len]u8 = undefined;
    const written: []const u8 = if (etf_preferred and e.asset_class == .etf)
        std.fmt.bufPrint(
            &buf,
            "Eligible {s} on {s}; {d}.{d:0>2}% = ${d}.{d:0>2}, ETF preferred",
            .{ class_str, venue_str, pct_whole, pct_frac, dollars, cents_part },
        ) catch unreachable
    else
        std.fmt.bufPrint(
            &buf,
            "Eligible {s} on {s}; {d}.{d:0>2}% = ${d}.{d:0>2}",
            .{ class_str, venue_str, pct_whole, pct_frac, dollars, cents_part },
        ) catch unreachable;

    out.rationale = std.mem.zeroes([max_rationale_len]u8);
    @memcpy(out.rationale[0..written.len], written);
    out.rationale_len = @intCast(written.len);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "basket_schema_version is 1" {
    try std.testing.expectEqual(@as(u16, 1), basket_schema_version);
}

// --- Acceptance: >= 4 eligible, >= 2 rejected for AI infrastructure demo ---

test "build: ai_infrastructure produces >= 4 instruments and >= 2 rejected" {
    const input = thesis.fixtures.ai_infrastructure;
    const hash = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try build(intent, hash);

    try std.testing.expect(basket.instrument_count >= 4);
    try std.testing.expect(basket.rejected_count >= 2);
}

// --- Acceptance: allocation sums to target within rounding tolerance ---

test "build: total_allocated_cents equals target_notional_cents" {
    for ([_]thesis.ThesisInput{
        thesis.fixtures.ai_infrastructure,
        thesis.fixtures.us_dividends,
        thesis.fixtures.cyber_security,
        thesis.fixtures.broad_market,
        thesis.fixtures.cash_preservation,
    }) |input| {
        const hash = thesis.computeThesisInputHash(input);
        const intent = try thesis.normalize(input);
        const basket = try build(intent, hash);
        try std.testing.expectEqual(
            intent.target_amount_cents,
            basket.total_allocated_cents,
        );
        // Verify the stored sum matches the field.
        var manual_sum: i64 = 0;
        for (basket.instruments[0..basket.instrument_count]) |inst| {
            manual_sum += inst.allocation_cents;
        }
        try std.testing.expectEqual(intent.target_amount_cents, manual_sum);
    }
}

// --- Acceptance: restricted instruments rejected before appearing in basket ---

test "build: SOXL and BULZ appear in rejected, not in instruments" {
    const input = thesis.fixtures.ai_infrastructure;
    const hash = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try build(intent, hash);

    // Neither SOXL nor BULZ should appear in the included list.
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        try std.testing.expect(!std.mem.eql(u8, inst.tickerSlice(), "SOXL"));
        try std.testing.expect(!std.mem.eql(u8, inst.tickerSlice(), "BULZ"));
    }

    // Both must appear in the rejected list with restricted_instrument reason.
    var found_soxl = false;
    var found_bulz = false;
    for (basket.rejected[0..basket.rejected_count]) |rc| {
        if (std.mem.eql(u8, rc.tickerSlice(), "SOXL")) {
            try std.testing.expectEqual(RejectionReason.restricted_instrument, rc.reason_code);
            try std.testing.expect(rc.reason_len > 0);
            found_soxl = true;
        }
        if (std.mem.eql(u8, rc.tickerSlice(), "BULZ")) {
            try std.testing.expectEqual(RejectionReason.restricted_instrument, rc.reason_code);
            try std.testing.expect(rc.reason_len > 0);
            found_bulz = true;
        }
    }
    try std.testing.expect(found_soxl);
    try std.testing.expect(found_bulz);
}

test "build: no instrument exceeds max_single_name_pct (non-binding cap)" {
    // 4 broad-market ETFs at equal weight = 25% each; 40% cap is not binding.
    var input = thesis.fixtures.broad_market;
    input.max_single_name_pct = 40;
    const intent = try thesis.normalize(input);
    const basket = try build(intent, thesis.computeThesisInputHash(input));

    const cap_bp: u32 = @as(u32, input.max_single_name_pct) * pct_to_bp;
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        try std.testing.expect(inst.weight_bp <= cap_bp + 1);
    }
}

test "build: cap is enforced when all instruments exceed it (binding cap)" {
    // AI infrastructure has 5 eligible equity instruments (equity-only filter
    // removes the 2 ETFs).  Equal weight = 2000 bp each.  With a 10% cap (1000 bp)
    // every instrument exceeds the cap; applyCap caps all.  Because 5 × 10% = 50%,
    // total_allocated_cents will be half of target; no instrument should exceed 10%.
    var input = thesis.fixtures.ai_infrastructure;
    input.max_single_name_pct = 10;
    // Equity-only so equal weighting applies (no ETF preference skew).
    input.asset_class_prefs = .{ .equity = true };
    input.exclusions = .{ .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true };
    const intent = try thesis.normalize(input);
    const basket = try build(intent, thesis.computeThesisInputHash(input));

    const cap_bp: u32 = @as(u32, input.max_single_name_pct) * pct_to_bp;
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        // weight_bp is recomputed from actual cents (which include a per-instrument
        // rounding remainder of at most 1 cent); allow 1 bp of rounding drift.
        try std.testing.expect(inst.weight_bp <= cap_bp + 1);
    }
    // 5 × 10% = 50% of target; total_allocated_cents is cap-limited, not full target.
    try std.testing.expect(basket.total_allocated_cents <= intent.target_amount_cents);
    try std.testing.expect(basket.total_allocated_cents > 0);
}

test "build: ETF instruments receive higher allocation than equities when etf_preferred" {
    // AI infrastructure intent allows both equity and ETF → ETF preference.
    const input = thesis.fixtures.ai_infrastructure;
    const hash = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try build(intent, hash);

    // At least one ETF and one equity must be present.
    var etf_alloc: i64 = 0;
    var eq_alloc: i64 = 0;
    var etf_count: usize = 0;
    var eq_count: usize = 0;
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        if (inst.asset_class == .etf) {
            etf_alloc += inst.allocation_cents;
            etf_count += 1;
        } else {
            eq_alloc += inst.allocation_cents;
            eq_count += 1;
        }
    }
    if (etf_count > 0 and eq_count > 0) {
        // Average ETF allocation > average equity allocation.
        const avg_etf = @divFloor(etf_alloc, @as(i64, @intCast(etf_count)));
        const avg_eq = @divFloor(eq_alloc, @as(i64, @intCast(eq_count)));
        try std.testing.expect(avg_etf > avg_eq);
    }
}

test "build: thesis_id matches caller-provided value; basket_id is composition hash" {
    const input = thesis.fixtures.ai_infrastructure;
    const hash = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try build(intent, hash);
    // thesis_id must equal the caller-supplied thesis input hash.
    try std.testing.expectEqual(hash, basket.thesis_id);
    // basket_id is the composition hash; it must be non-zero and distinct from thesis_id.
    try std.testing.expect(basket.basket_id != 0);
    try std.testing.expect(basket.basket_id != basket.thesis_id);
}

test "build: basket_id is stable (same inputs produce same composition hash)" {
    const input = thesis.fixtures.ai_infrastructure;
    const hash = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b1 = try build(intent, hash);
    const b2 = try build(intent, hash);
    try std.testing.expectEqual(b1.basket_id, b2.basket_id);
}

test "build: basket_id changes when thesis_id changes" {
    const input = thesis.fixtures.ai_infrastructure;
    var other_input = input;
    other_input.account_id = 9999;
    const h1 = thesis.computeThesisInputHash(input);
    const h2 = thesis.computeThesisInputHash(other_input);
    const b1 = try build(try thesis.normalize(input), h1);
    const b2 = try build(try thesis.normalize(other_input), h2);
    // Different thesis_id → different basket_id even for identical allocation.
    try std.testing.expect(b1.basket_id != b2.basket_id);
}

test "build: account_id carried from intent" {
    var input = thesis.fixtures.ai_infrastructure;
    input.account_id = 7777;
    const hash = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try build(intent, hash);
    try std.testing.expectEqual(@as(u32, 7777), basket.account_id);
}

test "build: catalog_schema_version stamped correctly" {
    const input = thesis.fixtures.ai_infrastructure;
    const intent = try thesis.normalize(input);
    const basket = try build(intent, 0);
    try std.testing.expectEqual(cat.catalog_schema_version, basket.catalog_schema_version);
}

test "build: all allocation_cents are positive" {
    const input = thesis.fixtures.ai_infrastructure;
    const intent = try thesis.normalize(input);
    const basket = try build(intent, 0);
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        try std.testing.expect(inst.allocation_cents > 0);
    }
}

test "build: all weight_bp values are non-zero" {
    const input = thesis.fixtures.ai_infrastructure;
    const intent = try thesis.normalize(input);
    const basket = try build(intent, 0);
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        try std.testing.expect(inst.weight_bp > 0);
    }
}

test "build: weight_bp values sum to approximately bp_denom" {
    const input = thesis.fixtures.ai_infrastructure;
    const intent = try thesis.normalize(input);
    const basket = try build(intent, 0);
    var sum: u32 = 0;
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        sum += inst.weight_bp;
    }
    // Allow a few bp of rounding drift (one per instrument).
    const n: u32 = basket.instrument_count;
    try std.testing.expect(sum >= bp_denom -| n);
    try std.testing.expect(sum <= bp_denom + n);
}

test "build: all included instruments have non-empty rationale" {
    const input = thesis.fixtures.ai_infrastructure;
    const intent = try thesis.normalize(input);
    const basket = try build(intent, 0);
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        try std.testing.expect(inst.rationale_len > 0);
        try std.testing.expect(inst.rationaleSlice().len > 0);
    }
}

test "build: all rejected candidates have non-empty reason" {
    const input = thesis.fixtures.ai_infrastructure;
    const intent = try thesis.normalize(input);
    const basket = try build(intent, 0);
    for (basket.rejected[0..basket.rejected_count]) |rc| {
        try std.testing.expect(rc.reason_len > 0);
        try std.testing.expect(rc.reasonSlice().len > 0);
    }
}

test "build: broad_market ETF-only intent produces valid basket" {
    const input = thesis.fixtures.broad_market;
    const intent = try thesis.normalize(input);
    const basket = try build(intent, 0);
    try std.testing.expect(basket.instrument_count >= 1);
    try std.testing.expectEqual(intent.target_amount_cents, basket.total_allocated_cents);
    // Broad market has only ETFs; no ETF preference applies (no equity class).
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        try std.testing.expectEqual(cat.AssetClass.etf, inst.asset_class);
    }
}

test "build: cyber_security intent includes HACK and CIBR ETFs" {
    const input = thesis.fixtures.cyber_security;
    const intent = try thesis.normalize(input);
    const basket = try build(intent, 0);
    var found_hack = false;
    var found_cibr = false;
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        if (std.mem.eql(u8, inst.tickerSlice(), "HACK")) found_hack = true;
        if (std.mem.eql(u8, inst.tickerSlice(), "CIBR")) found_cibr = true;
    }
    try std.testing.expect(found_hack);
    try std.testing.expect(found_cibr);
}

test "build: equity-only intent excludes ETFs" {
    // Override to equity-only asset class preference; no ETF preference applied.
    var input = thesis.fixtures.ai_infrastructure;
    input.asset_class_prefs = .{ .equity = true };
    input.exclusions = .{ .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true };
    const intent = try thesis.normalize(input);
    const basket = try build(intent, 0);
    for (basket.instruments[0..basket.instrument_count]) |inst| {
        try std.testing.expectEqual(cat.AssetClass.equity, inst.asset_class);
    }
}

test "build: NoEligibleInstruments when all theme matches are restricted" {
    // Use a manually crafted intent whose theme has only restricted instruments.
    // We test this by using ai_infrastructure with equity-and-etf excluded,
    // which leaves no eligible class.
    var input = thesis.fixtures.ai_infrastructure;
    input.asset_class_prefs = .{ .equity = true, .etf = true };
    // Exclude all supported classes so normalize() returns NoEligibleAssetClass.
    input.exclusions = .{ .equity = true, .etf = true, .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true };
    try std.testing.expectError(thesis.ThesisError.NoEligibleAssetClass, thesis.normalize(input));
    // Basket build would return NoEligibleInstruments for an intent whose theme
    // has no matching eligible catalog entries.  We verify the error path by
    // building with cash_like intent restricted to equities only (no equity in
    // the cash_like catalog subset).
    var cash_input = thesis.fixtures.cash_preservation;
    cash_input.asset_class_prefs = .{ .equity = true };
    cash_input.exclusions = .{ .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true };
    const cash_intent = try thesis.normalize(cash_input);
    try std.testing.expectError(BasketError.NoEligibleInstruments, build(cash_intent, 0));
}

test "build: deterministic — same intent produces identical basket and basket_id" {
    const input = thesis.fixtures.ai_infrastructure;
    const hash = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const b1 = try build(intent, hash);
    const b2 = try build(intent, hash);
    try std.testing.expectEqual(b1.basket_id, b2.basket_id);
    try std.testing.expectEqual(b1.instrument_count, b2.instrument_count);
    try std.testing.expectEqual(b1.total_allocated_cents, b2.total_allocated_cents);
    for (0..b1.instrument_count) |i| {
        try std.testing.expectEqualStrings(b1.instruments[i].tickerSlice(), b2.instruments[i].tickerSlice());
        try std.testing.expectEqual(b1.instruments[i].allocation_cents, b2.instruments[i].allocation_cents);
        try std.testing.expectEqual(b1.instruments[i].weight_bp, b2.instruments[i].weight_bp);
    }
}
