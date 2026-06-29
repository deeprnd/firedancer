/// V1.3.S1 Portfolio and Cash Impact Model
///
/// Defines before/after impact fields for cash, buying power, pending obligations,
/// asset class exposure, sector exposure, ticker concentration, thesis exposure,
/// rail exposure, destination exposure, and estimated order or transfer cost (T1).
///
/// Three computation paths:
///   computePreTradeImpact    — before paper execution or payment proposal (T2)
///   computeRealizedTradeImpact — after paper fills execute (T3)
///   computePendingPaymentImpact — when a payment proposal is added as pending (T3)
///
/// generateExplanations — populates display-ready explanation strings for
/// material changes into the PortfolioImpact.explanations array (T4).
const std = @import("std");
const basket_mod = @import("basket");
const portfolio = @import("portfolio");

const cat = basket_mod.catalog;

pub const impact_schema_version: u16 = 1;

// ---------------------------------------------------------------------------
// Capacity constants
// ---------------------------------------------------------------------------

/// One entry per AssetClass enum value (6 values currently).
pub const max_asset_class_exposure_entries: usize = 8;
/// One entry per InstrumentType enum value (7 values currently).
pub const max_instrument_type_exposure_entries: usize = 8;
/// One entry per distinct GICS sector code seen across holdings + basket.
pub const max_sector_exposure_entries: usize = 16;
/// Bounded by max_holdings + max_basket_instruments.
pub const max_ticker_concentration_entries: usize = 32;
/// Maximum tracked pending payment/transfer obligations.
pub const max_pending_obligations: usize = 16;
/// One entry per PaymentRail enum value.
pub const max_rail_exposure_entries: usize = 8;
/// One entry per distinct destination_id in pending obligations.
pub const max_destination_exposure_entries: usize = 16;
/// Maximum display-ready explanations per impact result.
pub const max_explanations: usize = 16;
pub const max_explanation_len: usize = 128;
pub const max_sector_code_len: usize = 32;

/// A sector exposure change >= 500 bp (5 percentage points) is material.
pub const material_exposure_change_bp: u32 = 500;

// ---------------------------------------------------------------------------
// Types (T1)
// ---------------------------------------------------------------------------

/// Payment rail for pending obligations.
pub const PaymentRail = enum(u8) { ach, wire, card, internal };

/// Approval state of a pending payment or transfer proposal.
pub const ApprovalState = enum(u8) {
    pending,
    approved,
    rejected,
    expired,
};

/// One pending payment or transfer obligation.
pub const PendingObligation = struct {
    proposal_id: u64,
    rail: PaymentRail,
    /// Opaque destination identifier; 0 is unused.
    destination_id: u64,
    amount_cents: i64,
    approval_state: ApprovalState,
    /// Nanosecond epoch timestamp; 0 means no expiry set.
    expires_at_ns: u64,

    pub fn isExpired(self: *const PendingObligation, now_ns: u64) bool {
        return self.expires_at_ns != 0 and now_ns > self.expires_at_ns;
    }
};

/// Asset class exposure before and after an action.
pub const AssetClassExposure = struct {
    asset_class: cat.AssetClass,
    /// Fraction of invested portfolio in basis points (10000 = 100%).
    before_bp: u32,
    after_bp: u32,
};

/// Instrument type exposure before and after an action.
pub const InstrumentTypeExposure = struct {
    instrument_type: cat.InstrumentType,
    before_bp: u32,
    after_bp: u32,
};

/// GICS sector exposure before and after an action.
pub const SectorExposure = struct {
    code: [max_sector_code_len]u8,
    code_len: u8,
    before_bp: u32,
    after_bp: u32,

    pub fn codeSlice(self: *const SectorExposure) []const u8 {
        return self.code[0..self.code_len];
    }
};

/// Per-ticker concentration before and after an action.
/// Tracks only tickers that appear in the proposed action.
pub const TickerConcentration = struct {
    ticker: [cat.max_ticker_len]u8,
    ticker_len: u8,
    before_bp: u32,
    after_bp: u32,

    pub fn tickerSlice(self: *const TickerConcentration) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

/// Aggregate pending cents on one payment rail.
pub const RailExposure = struct {
    rail: PaymentRail,
    /// Total cents committed to pending obligations on this rail.
    pending_cents: i64,
};

/// Aggregate pending cents to one destination.
pub const DestinationExposure = struct {
    destination_id: u64,
    pending_cents: i64,
};

/// Display-ready explanation string for one material change (T4).
pub const ImpactExplanation = struct {
    text: [max_explanation_len]u8,
    text_len: u8,

    pub fn textSlice(self: *const ImpactExplanation) []const u8 {
        return self.text[0..self.text_len];
    }
};

/// Full portfolio and cash impact before and after one or more proposed actions (T1).
pub const PortfolioImpact = struct {
    // Cash and buying power (raw account balance, not invested portfolio).
    cash_before_cents: i64,
    cash_after_cents: i64,
    buying_power_before_cents: i64,
    buying_power_after_cents: i64,

    // Aggregate cents committed to pending payment/transfer obligations.
    pending_obligations_before_cents: i64,
    pending_obligations_after_cents: i64,

    // Estimated costs.
    estimated_trade_cost_cents: i64,
    estimated_payment_cost_cents: i64,

    // Asset class exposures (fraction of invested portfolio).
    asset_class_exposures: [max_asset_class_exposure_entries]AssetClassExposure,
    asset_class_exposure_count: u8,

    // Instrument type exposures (fraction of invested portfolio).
    instrument_type_exposures: [max_instrument_type_exposure_entries]InstrumentTypeExposure,
    instrument_type_exposure_count: u8,

    // Sector exposures (fraction of invested portfolio, by GICS sector code).
    sector_exposures: [max_sector_exposure_entries]SectorExposure,
    sector_exposure_count: u8,

    // Per-ticker concentrations for tickers in the proposed action.
    ticker_concentrations: [max_ticker_concentration_entries]TickerConcentration,
    ticker_concentration_count: u8,

    // Thesis exposure: basket as fraction of invested portfolio before/after.
    thesis_before_bp: u32,
    thesis_after_bp: u32,

    // Number of distinct positions the thesis basket contributes.
    thesis_position_count: u8,

    // Rail and destination exposures from all pending obligations (before + new).
    rail_exposures: [max_rail_exposure_entries]RailExposure,
    rail_exposure_count: u8,
    destination_exposures: [max_destination_exposure_entries]DestinationExposure,
    destination_exposure_count: u8,

    // Display-ready explanations for material changes.
    explanations: [max_explanations]ImpactExplanation,
    explanation_count: u8,

    // Cash buffer breach: true when cash_after < cash_buffer_threshold_cents.
    cash_buffer_threshold_cents: i64,
    cash_buffer_breached_after: bool,

    // Pending obligation approval and expiry state.
    any_approval_required: bool,
    any_obligation_expired: bool,
};

// ---------------------------------------------------------------------------
// Computation (T2, T3)
// ---------------------------------------------------------------------------

/// Compute portfolio and cash impact before paper execution or payment proposal.
/// Shows what changes in cash, portfolio exposure, and pending obligations
/// when the proposed basket and the pending obligations are considered together (T2).
pub fn computePreTradeImpact(
    account: *const portfolio.BrokerageAccount,
    proposed_basket: *const basket_mod.Basket,
    pending_obligations: []const PendingObligation,
    cash_buffer_threshold_cents: i64,
    now_ns: u64,
) PortfolioImpact {
    var impact = std.mem.zeroes(PortfolioImpact);
    impact.cash_buffer_threshold_cents = cash_buffer_threshold_cents;

    // Cash and buying power.
    impact.cash_before_cents = account.cash_cents;
    impact.buying_power_before_cents = account.buying_power_cents;
    impact.estimated_trade_cost_cents = proposed_basket.total_allocated_cents;

    const cash_after = account.cash_cents - proposed_basket.total_allocated_cents;
    impact.cash_after_cents = cash_after;
    impact.buying_power_after_cents = account.buying_power_cents - proposed_basket.total_allocated_cents;

    // Pending obligations (all existing are "before"; no new ones added here).
    fillObligationState(&impact, pending_obligations, pending_obligations, now_ns);

    // Invested portfolio totals: holdings only (not raw cash).
    const total_before = holdingsTotalCents(account);
    const total_after = total_before + proposed_basket.total_allocated_cents;

    // Asset class exposures.
    fillAssetClassExposures(&impact, account, total_before, proposed_basket, total_after);

    // Instrument type exposures.
    fillInstrumentTypeExposures(&impact, account, total_before, proposed_basket, total_after);

    // Sector exposures.
    fillSectorExposures(&impact, account, total_before, proposed_basket, total_after);

    // Ticker concentrations for basket instruments.
    fillTickerConcentrations(&impact, account, total_before, proposed_basket, total_after);

    // Thesis exposure: basket fraction of total invested portfolio.
    impact.thesis_before_bp = toBp(proposed_basket.total_allocated_cents, total_before);
    impact.thesis_after_bp = toBp(proposed_basket.total_allocated_cents, total_after);
    impact.thesis_position_count = proposed_basket.instrument_count;

    // Cash buffer.
    impact.cash_buffer_breached_after = cash_buffer_threshold_cents > 0 and
        cash_after < cash_buffer_threshold_cents;

    return impact;
}

/// Compute realized paper-trade impact after paper fills execute (T3).
/// Uses filled_notional_cents (actual fills) rather than basket target
/// so partial fills produce accurate cash and exposure changes.
pub fn computeRealizedTradeImpact(
    account_before: *const portfolio.BrokerageAccount,
    proposed_basket: *const basket_mod.Basket,
    filled_notional_cents: i64,
    pending_obligations: []const PendingObligation,
    cash_buffer_threshold_cents: i64,
    now_ns: u64,
) PortfolioImpact {
    var impact = std.mem.zeroes(PortfolioImpact);
    impact.cash_buffer_threshold_cents = cash_buffer_threshold_cents;

    // Cash reflects actual fills.
    impact.cash_before_cents = account_before.cash_cents;
    impact.buying_power_before_cents = account_before.buying_power_cents;
    impact.estimated_trade_cost_cents = filled_notional_cents;

    const cash_after = account_before.cash_cents - filled_notional_cents;
    impact.cash_after_cents = cash_after;
    impact.buying_power_after_cents = account_before.buying_power_cents - filled_notional_cents;

    fillObligationState(&impact, pending_obligations, pending_obligations, now_ns);

    const total_before = holdingsTotalCents(account_before);
    const total_after = total_before + filled_notional_cents;

    // Use basket instruments as the realized additions (proportionally scaled
    // if filled_notional differs from basket.total_allocated_cents).
    fillAssetClassExposures(&impact, account_before, total_before, proposed_basket, total_after);
    fillInstrumentTypeExposures(&impact, account_before, total_before, proposed_basket, total_after);
    fillSectorExposures(&impact, account_before, total_before, proposed_basket, total_after);
    fillTickerConcentrations(&impact, account_before, total_before, proposed_basket, total_after);

    impact.thesis_before_bp = toBp(filled_notional_cents, total_before);
    impact.thesis_after_bp = toBp(filled_notional_cents, total_after);
    impact.thesis_position_count = proposed_basket.instrument_count;

    impact.cash_buffer_breached_after = cash_buffer_threshold_cents > 0 and
        cash_after < cash_buffer_threshold_cents;

    return impact;
}

/// Compute pending payment impact when a new obligation is added (T3).
/// Shows cash and obligation state before and after adding new_obligation,
/// separate from any trade impact.
pub fn computePendingPaymentImpact(
    account: *const portfolio.BrokerageAccount,
    new_obligation: PendingObligation,
    existing_obligations: []const PendingObligation,
    cash_buffer_threshold_cents: i64,
    now_ns: u64,
) PortfolioImpact {
    var impact = std.mem.zeroes(PortfolioImpact);
    impact.cash_buffer_threshold_cents = cash_buffer_threshold_cents;

    impact.cash_before_cents = account.cash_cents;
    impact.buying_power_before_cents = account.buying_power_cents;
    impact.estimated_payment_cost_cents = new_obligation.amount_cents;

    // Cash and buying power do not decrease until the approval-required
    // payment actually executes.  Only reserved/pending obligations increase.
    impact.cash_after_cents = account.cash_cents;
    impact.buying_power_after_cents = account.buying_power_cents;

    // Pending obligations: existing are "before"; existing + new are "after".
    const new_slice = [1]PendingObligation{new_obligation};
    fillObligationStateSplit(&impact, existing_obligations, existing_obligations, &new_slice, now_ns);

    // No portfolio composition change from a pending payment proposal.
    // Exposures remain zero (no basket, no holdings change).

    impact.cash_buffer_breached_after = cash_buffer_threshold_cents > 0 and
        (impact.pending_obligations_after_cents > account.cash_cents -| cash_buffer_threshold_cents);

    return impact;
}

// ---------------------------------------------------------------------------
// Display-ready explanations (T4)
// ---------------------------------------------------------------------------

/// Populate display-ready explanation strings for material changes (T4).
/// Writes into impact.explanations[].  Callers invoke this after computing
/// the impact to obtain the narrative layer.
///
/// Produces explanations for:
///   - sector exposure changes >= material_exposure_change_bp
///   - instrument type exposure changes >= material_exposure_change_bp
///   - cash change (when nonzero trade or payment cost)
///   - ticker concentration vs policy_max_single_name_bp
///   - thesis position count
///   - approval-required or expired pending obligations
///   - cash buffer breach
pub fn generateExplanations(
    impact: *PortfolioImpact,
    policy_max_single_name_bp: u32,
) void {
    impact.explanation_count = 0;
    var buf: [max_explanation_len]u8 = undefined;

    // Sector exposure changes.
    for (impact.sector_exposures[0..impact.sector_exposure_count]) |*se| {
        const change = absDiff(se.after_bp, se.before_bp);
        if (change < material_exposure_change_bp) continue;
        const dir: []const u8 = if (se.after_bp > se.before_bp) "increases" else "decreases";
        const text = std.fmt.bufPrint(
            &buf,
            "{s} exposure {s} from {d}.{d:0>2}% to {d}.{d:0>2}%.",
            .{
                se.codeSlice(),
                dir,
                se.before_bp / 100,
                se.before_bp % 100,
                se.after_bp / 100,
                se.after_bp % 100,
            },
        ) catch continue;
        addExplanation(impact, text);
    }

    // Instrument type exposure changes.
    for (impact.instrument_type_exposures[0..impact.instrument_type_exposure_count]) |*ite| {
        const change = absDiff(ite.after_bp, ite.before_bp);
        if (change < material_exposure_change_bp) continue;
        const dir: []const u8 = if (ite.after_bp > ite.before_bp) "increases" else "decreases";
        const text = std.fmt.bufPrint(
            &buf,
            "{s} exposure {s} from {d}.{d:0>2}% to {d}.{d:0>2}%.",
            .{
                ite.instrument_type.label(),
                dir,
                ite.before_bp / 100,
                ite.before_bp % 100,
                ite.after_bp / 100,
                ite.after_bp % 100,
            },
        ) catch continue;
        addExplanation(impact, text);
    }

    // Max single-name concentration vs policy cap.
    if (policy_max_single_name_bp > 0 and impact.ticker_concentration_count > 0) {
        var max_after_bp: u32 = 0;
        for (impact.ticker_concentrations[0..impact.ticker_concentration_count]) |*tc| {
            if (tc.after_bp > max_after_bp) max_after_bp = tc.after_bp;
        }
        if (max_after_bp <= policy_max_single_name_bp) {
            const text = std.fmt.bufPrint(
                &buf,
                "Single-name concentration remains below {d}.{d:0>2}%.",
                .{ policy_max_single_name_bp / 100, policy_max_single_name_bp % 100 },
            ) catch "Single-name concentration within policy.";
            addExplanation(impact, text);
        } else {
            const text = std.fmt.bufPrint(
                &buf,
                "Single-name concentration {d}.{d:0>2}% exceeds policy cap {d}.{d:0>2}%.",
                .{
                    max_after_bp / 100,
                    max_after_bp % 100,
                    policy_max_single_name_bp / 100,
                    policy_max_single_name_bp % 100,
                },
            ) catch "Single-name concentration exceeds policy cap.";
            addExplanation(impact, text);
        }
    }

    // Cash change.
    if (impact.estimated_trade_cost_cents != 0 or impact.estimated_payment_cost_cents != 0) {
        const before_d = @divTrunc(impact.cash_before_cents, 100);
        const before_c: u64 = @intCast(@abs(@rem(impact.cash_before_cents, 100)));
        const after_d = @divTrunc(impact.cash_after_cents, 100);
        const after_c: u64 = @intCast(@abs(@rem(impact.cash_after_cents, 100)));
        const text = std.fmt.bufPrint(
            &buf,
            "Cash drops from USD {d}.{d:0>2} to USD {d}.{d:0>2}.",
            .{ before_d, before_c, after_d, after_c },
        ) catch "Cash decreases after action.";
        addExplanation(impact, text);
    }

    // Thesis position count.
    if (impact.thesis_position_count > 0) {
        const text = std.fmt.bufPrint(
            &buf,
            "Thesis is represented by {d} position(s) in the basket.",
            .{impact.thesis_position_count},
        ) catch "Thesis positions in basket.";
        addExplanation(impact, text);
    }

    // Approval-required pending obligation.
    if (impact.any_approval_required) {
        addExplanation(impact, "One or more pending obligations remain approval-required and unexecuted.");
    }

    // Expired pending obligation.
    if (impact.any_obligation_expired) {
        addExplanation(impact, "One or more pending obligations have expired and require review.");
    }

    // Cash buffer breach.
    if (impact.cash_buffer_breached_after) {
        addExplanation(impact, "Post-action cash falls below the required cash buffer.");
    }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn holdingsTotalCents(account: *const portfolio.BrokerageAccount) i64 {
    var total: i64 = 0;
    for (account.holdings[0..account.holding_count]) |*h| {
        total += @max(@as(i64, 0), h.market_value_cents);
    }
    return total;
}

/// Safe basis-point conversion: (value * 10000) / total; returns 0 when total <= 0.
fn toBp(value: i64, total: i64) u32 {
    if (total <= 0 or value <= 0) return 0;
    const numerator = value *% @as(i64, 10_000);
    return @intCast(@min(@as(i64, 10_000), @divTrunc(numerator, total)));
}

fn absDiff(a: u32, b: u32) u32 {
    return if (a >= b) a - b else b - a;
}

fn addExplanation(impact: *PortfolioImpact, text: []const u8) void {
    if (impact.explanation_count >= max_explanations) return;
    const e = &impact.explanations[impact.explanation_count];
    e.* = std.mem.zeroes(ImpactExplanation);
    const len = @min(text.len, max_explanation_len);
    @memcpy(e.text[0..len], text[0..len]);
    e.text_len = @intCast(len);
    impact.explanation_count += 1;
}

fn assetClassValueInHoldings(
    account: *const portfolio.BrokerageAccount,
    asset_class: cat.AssetClass,
) i64 {
    var total: i64 = 0;
    for (account.holdings[0..account.holding_count]) |*h| {
        const entry = cat.lookupByTicker(h.tickerSlice()) orelse continue;
        if (entry.asset_class == asset_class) {
            total += @max(@as(i64, 0), h.market_value_cents);
        }
    }
    return total;
}

fn assetClassValueInBasket(
    proposed_basket: *const basket_mod.Basket,
    asset_class: cat.AssetClass,
) i64 {
    var total: i64 = 0;
    for (proposed_basket.instruments[0..proposed_basket.instrument_count]) |*instr| {
        if (instr.asset_class == asset_class) {
            total += @max(@as(i64, 0), instr.allocation_cents);
        }
    }
    return total;
}

fn instrumentTypeValueInHoldings(
    account: *const portfolio.BrokerageAccount,
    instrument_type: cat.InstrumentType,
) i64 {
    var total: i64 = 0;
    for (account.holdings[0..account.holding_count]) |*h| {
        const entry = cat.lookupByTicker(h.tickerSlice()) orelse continue;
        if (entry.instrument_type == instrument_type) {
            total += @max(@as(i64, 0), h.market_value_cents);
        }
    }
    return total;
}

fn instrumentTypeValueInBasket(
    proposed_basket: *const basket_mod.Basket,
    instrument_type: cat.InstrumentType,
) i64 {
    var total: i64 = 0;
    for (proposed_basket.instruments[0..proposed_basket.instrument_count]) |*instr| {
        if (instr.instrument_type == instrument_type) {
            total += @max(@as(i64, 0), instr.allocation_cents);
        }
    }
    return total;
}

fn fillAssetClassExposures(
    impact: *PortfolioImpact,
    account: *const portfolio.BrokerageAccount,
    total_before: i64,
    proposed_basket: *const basket_mod.Basket,
    total_after: i64,
) void {
    const classes = [_]cat.AssetClass{ .equity, .fixed_income, .commodity, .fx, .crypto, .cash };
    for (classes) |ac| {
        const before_val = assetClassValueInHoldings(account, ac);
        const basket_val = assetClassValueInBasket(proposed_basket, ac);
        const after_val = before_val + basket_val;
        // Skip if neither before nor after has any exposure.
        if (before_val == 0 and after_val == 0) continue;
        if (impact.asset_class_exposure_count >= max_asset_class_exposure_entries) break;
        impact.asset_class_exposures[impact.asset_class_exposure_count] = .{
            .asset_class = ac,
            .before_bp = toBp(before_val, total_before),
            .after_bp = toBp(after_val, total_after),
        };
        impact.asset_class_exposure_count += 1;
    }
}

fn fillInstrumentTypeExposures(
    impact: *PortfolioImpact,
    account: *const portfolio.BrokerageAccount,
    total_before: i64,
    proposed_basket: *const basket_mod.Basket,
    total_after: i64,
) void {
    const types = [_]cat.InstrumentType{ .stock, .etf, .bond, .option, .future, .fund, .token };
    for (types) |it| {
        const before_val = instrumentTypeValueInHoldings(account, it);
        const basket_val = instrumentTypeValueInBasket(proposed_basket, it);
        const after_val = before_val + basket_val;
        if (before_val == 0 and after_val == 0) continue;
        if (impact.instrument_type_exposure_count >= max_instrument_type_exposure_entries) break;
        impact.instrument_type_exposures[impact.instrument_type_exposure_count] = .{
            .instrument_type = it,
            .before_bp = toBp(before_val, total_before),
            .after_bp = toBp(after_val, total_after),
        };
        impact.instrument_type_exposure_count += 1;
    }
}

fn findOrAddSector(impact: *PortfolioImpact, code: []const u8) ?*SectorExposure {
    for (impact.sector_exposures[0..impact.sector_exposure_count]) |*se| {
        if (std.mem.eql(u8, se.codeSlice(), code)) return se;
    }
    if (impact.sector_exposure_count >= max_sector_exposure_entries) return null;
    const se = &impact.sector_exposures[impact.sector_exposure_count];
    se.* = std.mem.zeroes(SectorExposure);
    const len = @min(code.len, max_sector_code_len);
    @memcpy(se.code[0..len], code[0..len]);
    se.code_len = @intCast(len);
    impact.sector_exposure_count += 1;
    return se;
}

fn fillSectorExposures(
    impact: *PortfolioImpact,
    account: *const portfolio.BrokerageAccount,
    total_before: i64,
    proposed_basket: *const basket_mod.Basket,
    total_after: i64,
) void {
    // Collect per-sector values from existing holdings.
    for (account.holdings[0..account.holding_count]) |*h| {
        const entry = cat.lookupByTicker(h.tickerSlice()) orelse continue;
        const mv = @max(@as(i64, 0), h.market_value_cents);
        if (mv == 0) continue;
        for (entry.sectors.values[0..entry.sectors.count]) |*ref| {
            const code = ref.code.slice();
            const se = findOrAddSector(impact, code) orelse break;
            se.before_bp = @intCast(@min(10_000, @as(i64, se.before_bp) + toBp(mv, total_before)));
        }
    }

    // Collect per-sector values from basket instruments.
    for (proposed_basket.instruments[0..proposed_basket.instrument_count]) |*instr| {
        const entry = cat.lookupByTicker(instr.tickerSlice()) orelse continue;
        const alloc = @max(@as(i64, 0), instr.allocation_cents);
        if (alloc == 0) continue;
        for (entry.sectors.values[0..entry.sectors.count]) |*ref| {
            const code = ref.code.slice();
            const se = findOrAddSector(impact, code) orelse break;
            se.after_bp = @intCast(@min(10_000, @as(i64, se.after_bp) + toBp(alloc, total_after)));
        }
    }

    // Finalize: after_bp = before contributions + basket contributions.
    // Holdings' "before" contribution to "after" is their proportionally scaled value.
    for (impact.sector_exposures[0..impact.sector_exposure_count]) |*se| {
        // Holdings contribute to after at scaled-down weight since total_after > total_before.
        var holding_after_cents: i64 = 0;
        for (account.holdings[0..account.holding_count]) |*h| {
            const entry = cat.lookupByTicker(h.tickerSlice()) orelse continue;
            const mv = @max(@as(i64, 0), h.market_value_cents);
            for (entry.sectors.values[0..entry.sectors.count]) |*ref| {
                if (std.mem.eql(u8, ref.code.slice(), se.codeSlice())) {
                    holding_after_cents += mv;
                    break;
                }
            }
        }
        var basket_after_cents: i64 = 0;
        for (proposed_basket.instruments[0..proposed_basket.instrument_count]) |*instr| {
            const entry = cat.lookupByTicker(instr.tickerSlice()) orelse continue;
            const alloc = @max(@as(i64, 0), instr.allocation_cents);
            for (entry.sectors.values[0..entry.sectors.count]) |*ref| {
                if (std.mem.eql(u8, ref.code.slice(), se.codeSlice())) {
                    basket_after_cents += alloc;
                    break;
                }
            }
        }
        se.after_bp = toBp(holding_after_cents + basket_after_cents, total_after);
    }
}

fn findOrAddTicker(impact: *PortfolioImpact, ticker: []const u8) ?*TickerConcentration {
    for (impact.ticker_concentrations[0..impact.ticker_concentration_count]) |*tc| {
        if (std.mem.eql(u8, tc.tickerSlice(), ticker)) return tc;
    }
    if (impact.ticker_concentration_count >= max_ticker_concentration_entries) return null;
    const tc = &impact.ticker_concentrations[impact.ticker_concentration_count];
    tc.* = std.mem.zeroes(TickerConcentration);
    const len = @min(ticker.len, cat.max_ticker_len);
    @memcpy(tc.ticker[0..len], ticker[0..len]);
    tc.ticker_len = @intCast(len);
    impact.ticker_concentration_count += 1;
    return tc;
}

fn fillTickerConcentrations(
    impact: *PortfolioImpact,
    account: *const portfolio.BrokerageAccount,
    total_before: i64,
    proposed_basket: *const basket_mod.Basket,
    total_after: i64,
) void {
    for (proposed_basket.instruments[0..proposed_basket.instrument_count]) |*instr| {
        const ticker = instr.tickerSlice();
        const tc = findOrAddTicker(impact, ticker) orelse continue;

        // Before: value from existing holdings (0 if new position).
        var existing_mv: i64 = 0;
        if (portfolio.findHolding(account, ticker)) |h| {
            existing_mv = @max(@as(i64, 0), h.market_value_cents);
        }
        tc.before_bp = toBp(existing_mv, total_before);

        // After: existing holding + basket allocation.
        tc.after_bp = toBp(existing_mv + instr.allocation_cents, total_after);
    }
}

fn obligationsTotalCents(obligations: []const PendingObligation) i64 {
    var total: i64 = 0;
    for (obligations) |*ob| {
        if (ob.amount_cents > 0) total += ob.amount_cents;
    }
    return total;
}

fn fillRailAndDestination(
    impact: *PortfolioImpact,
    obligations: []const PendingObligation,
) void {
    for (obligations) |*ob| {
        // Rail exposure.
        var found_rail = false;
        for (impact.rail_exposures[0..impact.rail_exposure_count]) |*re| {
            if (re.rail == ob.rail) {
                re.pending_cents += ob.amount_cents;
                found_rail = true;
                break;
            }
        }
        if (!found_rail and impact.rail_exposure_count < max_rail_exposure_entries) {
            impact.rail_exposures[impact.rail_exposure_count] = .{
                .rail = ob.rail,
                .pending_cents = ob.amount_cents,
            };
            impact.rail_exposure_count += 1;
        }

        // Destination exposure.
        if (ob.destination_id == 0) continue;
        var found_dest = false;
        for (impact.destination_exposures[0..impact.destination_exposure_count]) |*de| {
            if (de.destination_id == ob.destination_id) {
                de.pending_cents += ob.amount_cents;
                found_dest = true;
                break;
            }
        }
        if (!found_dest and impact.destination_exposure_count < max_destination_exposure_entries) {
            impact.destination_exposures[impact.destination_exposure_count] = .{
                .destination_id = ob.destination_id,
                .pending_cents = ob.amount_cents,
            };
            impact.destination_exposure_count += 1;
        }
    }
}

fn fillObligationState(
    impact: *PortfolioImpact,
    before_obligations: []const PendingObligation,
    after_obligations: []const PendingObligation,
    now_ns: u64,
) void {
    impact.pending_obligations_before_cents = obligationsTotalCents(before_obligations);
    impact.pending_obligations_after_cents = obligationsTotalCents(after_obligations);

    for (after_obligations) |*ob| {
        if (ob.approval_state == .pending) impact.any_approval_required = true;
        if (ob.isExpired(now_ns)) impact.any_obligation_expired = true;
    }

    fillRailAndDestination(impact, after_obligations);
}

fn fillObligationStateSplit(
    impact: *PortfolioImpact,
    before_obligations: []const PendingObligation,
    existing_after: []const PendingObligation,
    new_obligations: []const PendingObligation,
    now_ns: u64,
) void {
    impact.pending_obligations_before_cents = obligationsTotalCents(before_obligations);
    impact.pending_obligations_after_cents =
        obligationsTotalCents(existing_after) + obligationsTotalCents(new_obligations);

    for (existing_after) |*ob| {
        if (ob.approval_state == .pending) impact.any_approval_required = true;
        if (ob.isExpired(now_ns)) impact.any_obligation_expired = true;
    }
    for (new_obligations) |*ob| {
        if (ob.approval_state == .pending) impact.any_approval_required = true;
        if (ob.isExpired(now_ns)) impact.any_obligation_expired = true;
    }

    fillRailAndDestination(impact, existing_after);
    fillRailAndDestination(impact, new_obligations);
}

// ---------------------------------------------------------------------------
// Tests (T5)
// ---------------------------------------------------------------------------

test "impact_schema_version is 1" {
    try std.testing.expectEqual(@as(u16, 1), impact_schema_version);
}

const testing = std.testing;

fn makeMinimalAccount(cash_cents: i64) portfolio.BrokerageAccount {
    var a = std.mem.zeroes(portfolio.BrokerageAccount);
    a.account_id = 9001;
    a.currency = .usd;
    a.cash_cents = cash_cents;
    a.buying_power_cents = cash_cents;
    return a;
}

fn makeBasketWith(
    account_id: u32,
    alloc_cents: i64,
    comptime ticker1: []const u8,
    asset_class1: cat.AssetClass,
    instrument_type1: cat.InstrumentType,
    comptime ticker2: []const u8,
    asset_class2: cat.AssetClass,
    instrument_type2: cat.InstrumentType,
) basket_mod.Basket {
    var b = std.mem.zeroes(basket_mod.Basket);
    b.account_id = account_id;
    b.total_allocated_cents = alloc_cents;
    b.instrument_count = 2;
    // Instrument 0
    const len1 = ticker1.len;
    @memcpy(b.instruments[0].ticker[0..len1], ticker1);
    b.instruments[0].ticker_len = len1;
    b.instruments[0].allocation_cents = @divTrunc(alloc_cents, 2);
    b.instruments[0].asset_class = asset_class1;
    b.instruments[0].instrument_type = instrument_type1;
    b.instruments[0].weight_bp = 5000;
    // Instrument 1
    const len2 = ticker2.len;
    @memcpy(b.instruments[1].ticker[0..len2], ticker2);
    b.instruments[1].ticker_len = len2;
    b.instruments[1].allocation_cents = alloc_cents - @divTrunc(alloc_cents, 2);
    b.instruments[1].asset_class = asset_class2;
    b.instruments[1].instrument_type = instrument_type2;
    b.instruments[1].weight_bp = 5000;
    return b;
}

// T5: Increased technology exposure — buying IT-sector instruments raises sector exposure.
test "computePreTradeImpact: technology exposure increases when basket is all information_technology" {
    const account = makeMinimalAccount(5_000_000); // USD 50,000 cash, 0 holdings
    // NVDA and SOXX are both information_technology in the catalog.
    const basket = makeBasketWith(
        account.account_id,
        200_000, // USD 2,000
        "NVDA",
        .equity,
        .stock,
        "SOXX",
        .equity,
        .etf,
    );
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);

    // Before: no holdings, technology exposure = 0.
    var tech_before: u32 = 0;
    var tech_after: u32 = 0;
    for (impact.sector_exposures[0..impact.sector_exposure_count]) |*se| {
        if (std.mem.eql(u8, se.codeSlice(), "information_technology")) {
            tech_before = se.before_bp;
            tech_after = se.after_bp;
        }
    }
    try testing.expectEqual(@as(u32, 0), tech_before);
    try testing.expect(tech_after > 0); // exposure increases after buying IT instruments
}

// T5: Cash decrease — cash after trade is lower by the basket cost.
test "computePreTradeImpact: cash decreases by basket.total_allocated_cents" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(
        account.account_id,
        200_000,
        "NVDA",
        .equity,
        .stock,
        "SOXX",
        .equity,
        .etf,
    );
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);

    try testing.expectEqual(@as(i64, 5_000_000), impact.cash_before_cents);
    try testing.expectEqual(@as(i64, 4_800_000), impact.cash_after_cents);
    try testing.expect(impact.cash_after_cents < impact.cash_before_cents);
}

// T5: Pending obligation increase — adding a payment obligation increases pending cents.
test "computePendingPaymentImpact: pending obligations increase when new obligation is added" {
    const account = makeMinimalAccount(3_000_000); // USD 30,000
    const new_ob = PendingObligation{
        .proposal_id = 101,
        .rail = .ach,
        .destination_id = 42,
        .amount_cents = 124_000, // USD 1,240
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const impact = computePendingPaymentImpact(
        &account,
        new_ob,
        &[_]PendingObligation{},
        0,
        0,
    );

    try testing.expectEqual(@as(i64, 0), impact.pending_obligations_before_cents);
    try testing.expectEqual(@as(i64, 124_000), impact.pending_obligations_after_cents);
    try testing.expect(impact.pending_obligations_after_cents > impact.pending_obligations_before_cents);
    try testing.expect(impact.any_approval_required);
}

// T5: Approval expiry — an obligation with past expiry is flagged.
test "computePreTradeImpact: any_obligation_expired true when obligation has past expiry" {
    const account = makeMinimalAccount(1_000_000);
    const basket = makeBasketWith(
        account.account_id,
        50_000,
        "NVDA",
        .equity,
        .stock,
        "SOXX",
        .equity,
        .etf,
    );
    const expired_ob = PendingObligation{
        .proposal_id = 202,
        .rail = .wire,
        .destination_id = 55,
        .amount_cents = 50_000,
        .approval_state = .pending,
        .expires_at_ns = 1_000, // nanosecond epoch far in the past
    };
    const now_ns: u64 = 1_000_000_000_000; // long after expiry

    const impact = computePreTradeImpact(
        &account,
        &basket,
        &[_]PendingObligation{expired_ob},
        0,
        now_ns,
    );

    try testing.expect(impact.any_obligation_expired);
}

// T5: Cash-buffer threshold — post-action cash below threshold is flagged.
test "computePreTradeImpact: cash_buffer_breached_after when trade leaves too little cash" {
    const account = makeMinimalAccount(2_000_000); // USD 20,000
    const basket = makeBasketWith(
        account.account_id,
        1_600_000, // USD 16,000 trade cost
        "NVDA",
        .equity,
        .stock,
        "SOXX",
        .equity,
        .etf,
    );
    // Require at least USD 10,000 cash buffer (1,000,000 cents).
    const cash_buffer: i64 = 1_000_000;
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, cash_buffer, 0);

    // cash_after = 2,000,000 - 1,600,000 = 400,000 < 1,000,000 threshold.
    try testing.expectEqual(@as(i64, 400_000), impact.cash_after_cents);
    try testing.expect(impact.cash_buffer_breached_after);
}

// T5: No buffer breach when cash remains above threshold.
test "computePreTradeImpact: cash_buffer_breached_after false when cash stays above threshold" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(
        account.account_id,
        200_000, // USD 2,000
        "NVDA",
        .equity,
        .stock,
        "SOXX",
        .equity,
        .etf,
    );
    const cash_buffer: i64 = 1_000_000; // USD 10,000 buffer
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, cash_buffer, 0);

    // cash_after = 5,000,000 - 200,000 = 4,800,000 > 1,000,000 threshold.
    try testing.expectEqual(@as(i64, 4_800_000), impact.cash_after_cents);
    try testing.expect(!impact.cash_buffer_breached_after);
}

// T5 supplement: instrument type exposure — ETF exposure increases when buying ETFs.
test "computePreTradeImpact: ETF exposure increases when basket includes ETFs" {
    const account = makeMinimalAccount(5_000_000); // no holdings
    const basket = makeBasketWith(
        account.account_id,
        200_000,
        "NVDA", // stock
        .equity,
        .stock,
        "SOXX", // ETF
        .equity,
        .etf,
    );
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);

    var etf_before: u32 = 0;
    var etf_after: u32 = 0;
    for (impact.instrument_type_exposures[0..impact.instrument_type_exposure_count]) |*ite| {
        if (ite.instrument_type == .etf) {
            etf_before = ite.before_bp;
            etf_after = ite.after_bp;
        }
    }
    try testing.expectEqual(@as(u32, 0), etf_before); // no ETFs before
    try testing.expect(etf_after > 0); // ETF exposure after buying SOXX
}

// Realized trade impact uses filled_notional_cents for cash reduction.
test "computeRealizedTradeImpact: cash decreases by filled_notional_cents" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(
        account.account_id,
        200_000,
        "NVDA",
        .equity,
        .stock,
        "SOXX",
        .equity,
        .etf,
    );
    const filled: i64 = 199_800; // slight rounding from actual fills
    const impact = computeRealizedTradeImpact(
        &account,
        &basket,
        filled,
        &[_]PendingObligation{},
        0,
        0,
    );
    try testing.expectEqual(account.cash_cents - filled, impact.cash_after_cents);
}

// generateExplanations produces material sector explanation.
test "generateExplanations: sector explanation produced for technology exposure change" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(
        account.account_id,
        200_000,
        "NVDA",
        .equity,
        .stock,
        "SOXX",
        .equity,
        .etf,
    );
    var impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);
    generateExplanations(&impact, 0);

    // At least one explanation should mention technology since exposure goes from 0 to >0.
    try testing.expect(impact.explanation_count > 0);
    var found = false;
    for (impact.explanations[0..impact.explanation_count]) |*e| {
        if (std.mem.indexOf(u8, e.textSlice(), "information_technology") != null) {
            found = true;
        }
    }
    try testing.expect(found);
}

// generateExplanations: cash buffer breach explanation.
test "generateExplanations: cash buffer breach explanation produced" {
    const account = makeMinimalAccount(1_000_000);
    const basket = makeBasketWith(
        account.account_id,
        900_000,
        "NVDA",
        .equity,
        .stock,
        "SOXX",
        .equity,
        .etf,
    );
    var impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 500_000, 0);
    generateExplanations(&impact, 0);

    var found = false;
    for (impact.explanations[0..impact.explanation_count]) |*e| {
        if (std.mem.indexOf(u8, e.textSlice(), "cash buffer") != null) found = true;
    }
    try testing.expect(found);
}

// Rail exposure is tracked from pending obligations.
test "computePendingPaymentImpact: rail exposure tracked for ACH obligation" {
    const account = makeMinimalAccount(5_000_000);
    const new_ob = PendingObligation{
        .proposal_id = 303,
        .rail = .ach,
        .destination_id = 77,
        .amount_cents = 124_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const impact = computePendingPaymentImpact(&account, new_ob, &[_]PendingObligation{}, 0, 0);

    try testing.expectEqual(@as(u8, 1), impact.rail_exposure_count);
    try testing.expectEqual(PaymentRail.ach, impact.rail_exposures[0].rail);
    try testing.expectEqual(@as(i64, 124_000), impact.rail_exposures[0].pending_cents);
}

// Destination exposure is tracked from pending obligations.
test "computePendingPaymentImpact: destination exposure tracked" {
    const account = makeMinimalAccount(5_000_000);
    const new_ob = PendingObligation{
        .proposal_id = 404,
        .rail = .wire,
        .destination_id = 99,
        .amount_cents = 50_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const impact = computePendingPaymentImpact(&account, new_ob, &[_]PendingObligation{}, 0, 0);

    try testing.expectEqual(@as(u8, 1), impact.destination_exposure_count);
    try testing.expectEqual(@as(u64, 99), impact.destination_exposures[0].destination_id);
}

// Thesis position count matches basket instrument count.
test "computePreTradeImpact: thesis_position_count matches basket instrument count" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(
        account.account_id,
        200_000,
        "NVDA",
        .equity,
        .stock,
        "SOXX",
        .equity,
        .etf,
    );
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);
    try testing.expectEqual(@as(u8, 2), impact.thesis_position_count);
}

// ---------------------------------------------------------------------------
// PendingObligation.isExpired edge cases
// ---------------------------------------------------------------------------

test "PendingObligation.isExpired: never expires when expires_at_ns is 0" {
    const ob = PendingObligation{
        .proposal_id = 1,
        .rail = .ach,
        .destination_id = 1,
        .amount_cents = 1_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    try testing.expect(!ob.isExpired(std.math.maxInt(u64)));
}

test "PendingObligation.isExpired: not expired when now equals or is below expires_at_ns" {
    const ob = PendingObligation{
        .proposal_id = 2,
        .rail = .wire,
        .destination_id = 1,
        .amount_cents = 1_000,
        .approval_state = .pending,
        .expires_at_ns = 1_000_000_000,
    };
    try testing.expect(!ob.isExpired(1_000_000_000)); // exactly at expiry: not expired
    try testing.expect(!ob.isExpired(999_999_999)); // before expiry: not expired
    try testing.expect(ob.isExpired(1_000_000_001)); // one ns past: expired
}

// ---------------------------------------------------------------------------
// computePreTradeImpact: buying power, obligation totals, and approval state
// ---------------------------------------------------------------------------

test "computePreTradeImpact: buying_power_after decremented by basket cost" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);
    try testing.expectEqual(@as(i64, 5_000_000), impact.buying_power_before_cents);
    try testing.expectEqual(@as(i64, 4_800_000), impact.buying_power_after_cents);
}

test "computePreTradeImpact: pending_obligations_before_cents sums existing obligations" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const obligations = [_]PendingObligation{
        .{ .proposal_id = 10, .rail = .ach, .destination_id = 1, .amount_cents = 100_000, .approval_state = .pending, .expires_at_ns = 0 },
        .{ .proposal_id = 11, .rail = .wire, .destination_id = 2, .amount_cents = 50_000, .approval_state = .approved, .expires_at_ns = 0 },
    };
    const impact = computePreTradeImpact(&account, &basket, &obligations, 0, 0);
    try testing.expectEqual(@as(i64, 150_000), impact.pending_obligations_before_cents);
    try testing.expectEqual(@as(i64, 150_000), impact.pending_obligations_after_cents);
}

test "computePreTradeImpact: any_approval_required false when obligations are approved or rejected" {
    const account = makeMinimalAccount(3_000_000);
    const basket = makeBasketWith(account.account_id, 100_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const obligations = [_]PendingObligation{
        .{ .proposal_id = 20, .rail = .ach, .destination_id = 1, .amount_cents = 50_000, .approval_state = .approved, .expires_at_ns = 0 },
        .{ .proposal_id = 21, .rail = .wire, .destination_id = 2, .amount_cents = 50_000, .approval_state = .rejected, .expires_at_ns = 0 },
    };
    const impact = computePreTradeImpact(&account, &basket, &obligations, 0, 0);
    try testing.expect(!impact.any_approval_required);
}

test "computePreTradeImpact: any_obligation_expired and any_approval_required false when no obligations" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);
    try testing.expect(!impact.any_obligation_expired);
    try testing.expect(!impact.any_approval_required);
}

test "computePreTradeImpact: estimated_trade_cost_cents equals basket allocated; payment cost is zero" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);
    try testing.expectEqual(@as(i64, 200_000), impact.estimated_trade_cost_cents);
    try testing.expectEqual(@as(i64, 0), impact.estimated_payment_cost_cents);
}

test "computePreTradeImpact: empty basket produces no ticker concentrations and zero thesis_position_count" {
    const account = makeMinimalAccount(5_000_000);
    var empty_basket = std.mem.zeroes(basket_mod.Basket);
    empty_basket.account_id = account.account_id;
    const impact = computePreTradeImpact(&account, &empty_basket, &[_]PendingObligation{}, 0, 0);
    try testing.expectEqual(@as(u8, 0), impact.ticker_concentration_count);
    try testing.expectEqual(@as(u8, 0), impact.thesis_position_count);
}

// ---------------------------------------------------------------------------
// computePreTradeImpact: account with existing holdings (technology_heavy fixture)
// ---------------------------------------------------------------------------

test "computePreTradeImpact: ticker concentration before_bp nonzero for existing holding" {
    // technology_heavy holds NVDA at 1,495,000 cents; buying more raises concentration.
    const account = portfolio.fixtures.technology_heavy;
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);

    var nvda_before_bp: u32 = 0;
    var nvda_after_bp: u32 = 0;
    for (impact.ticker_concentrations[0..impact.ticker_concentration_count]) |*tc| {
        if (std.mem.eql(u8, tc.tickerSlice(), "NVDA")) {
            nvda_before_bp = tc.before_bp;
            nvda_after_bp = tc.after_bp;
        }
    }
    try testing.expect(nvda_before_bp > 0); // NVDA already held
    try testing.expect(nvda_after_bp > nvda_before_bp); // concentration grows after basket adds more
}

test "computePreTradeImpact: technology_heavy has nonzero equity exposure before trade" {
    const account = portfolio.fixtures.technology_heavy;
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);

    var equity_before: u32 = 0;
    for (impact.asset_class_exposures[0..impact.asset_class_exposure_count]) |*ace| {
        if (ace.asset_class == .equity) equity_before = ace.before_bp;
    }
    try testing.expect(equity_before > 0); // existing equity holdings
}

// ---------------------------------------------------------------------------
// computePendingPaymentImpact: cash not drained, buffer breach, obligation sums
// ---------------------------------------------------------------------------

test "computePendingPaymentImpact: cash and buying power are not drained by pending obligation" {
    const account = makeMinimalAccount(3_000_000);
    const new_ob = PendingObligation{
        .proposal_id = 501,
        .rail = .ach,
        .destination_id = 10,
        .amount_cents = 500_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const impact = computePendingPaymentImpact(&account, new_ob, &[_]PendingObligation{}, 0, 0);
    try testing.expectEqual(impact.cash_before_cents, impact.cash_after_cents);
    try testing.expectEqual(impact.buying_power_before_cents, impact.buying_power_after_cents);
}

test "computePendingPaymentImpact: cash_buffer_breached_after when pending obligations exceed buffer headroom" {
    // cash = USD 10,000; buffer = USD 5,000; headroom = USD 5,000.
    // pending = USD 9,500 > headroom → breach.
    const account = makeMinimalAccount(1_000_000);
    const new_ob = PendingObligation{
        .proposal_id = 600,
        .rail = .ach,
        .destination_id = 10,
        .amount_cents = 950_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const cash_buffer: i64 = 500_000;
    const impact = computePendingPaymentImpact(&account, new_ob, &[_]PendingObligation{}, cash_buffer, 0);
    try testing.expect(impact.cash_buffer_breached_after);
}

test "computePendingPaymentImpact: pending_obligations_before_cents sums existing; after adds new" {
    const account = makeMinimalAccount(5_000_000);
    const existing = [_]PendingObligation{
        .{ .proposal_id = 700, .rail = .ach, .destination_id = 1, .amount_cents = 50_000, .approval_state = .approved, .expires_at_ns = 0 },
        .{ .proposal_id = 701, .rail = .wire, .destination_id = 2, .amount_cents = 75_000, .approval_state = .pending, .expires_at_ns = 0 },
    };
    const new_ob = PendingObligation{
        .proposal_id = 702,
        .rail = .card,
        .destination_id = 3,
        .amount_cents = 25_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const impact = computePendingPaymentImpact(&account, new_ob, &existing, 0, 0);
    try testing.expectEqual(@as(i64, 125_000), impact.pending_obligations_before_cents);
    try testing.expectEqual(@as(i64, 150_000), impact.pending_obligations_after_cents);
}

test "computePendingPaymentImpact: estimated_payment_cost_cents equals new obligation amount" {
    const account = makeMinimalAccount(5_000_000);
    const new_ob = PendingObligation{
        .proposal_id = 800,
        .rail = .ach,
        .destination_id = 5,
        .amount_cents = 124_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const impact = computePendingPaymentImpact(&account, new_ob, &[_]PendingObligation{}, 0, 0);
    try testing.expectEqual(@as(i64, 124_000), impact.estimated_payment_cost_cents);
    try testing.expectEqual(@as(i64, 0), impact.estimated_trade_cost_cents);
}

// ---------------------------------------------------------------------------
// Rail and destination exposure accumulation
// ---------------------------------------------------------------------------

test "rail exposure: two obligations on the same rail accumulate" {
    const account = makeMinimalAccount(5_000_000);
    const existing_ob = PendingObligation{
        .proposal_id = 900,
        .rail = .ach,
        .destination_id = 10,
        .amount_cents = 100_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const new_ob = PendingObligation{
        .proposal_id = 901,
        .rail = .ach,
        .destination_id = 20,
        .amount_cents = 200_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const impact = computePendingPaymentImpact(&account, new_ob, &[_]PendingObligation{existing_ob}, 0, 0);

    var ach_cents: i64 = 0;
    for (impact.rail_exposures[0..impact.rail_exposure_count]) |*re| {
        if (re.rail == .ach) ach_cents = re.pending_cents;
    }
    try testing.expectEqual(@as(i64, 300_000), ach_cents);
}

test "destination exposure: two obligations to same destination accumulate" {
    const account = makeMinimalAccount(5_000_000);
    const existing_ob = PendingObligation{
        .proposal_id = 1_000,
        .rail = .ach,
        .destination_id = 42,
        .amount_cents = 100_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const new_ob = PendingObligation{
        .proposal_id = 1_001,
        .rail = .wire,
        .destination_id = 42,
        .amount_cents = 75_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const impact = computePendingPaymentImpact(&account, new_ob, &[_]PendingObligation{existing_ob}, 0, 0);

    var dest_cents: i64 = 0;
    for (impact.destination_exposures[0..impact.destination_exposure_count]) |*de| {
        if (de.destination_id == 42) dest_cents = de.pending_cents;
    }
    try testing.expectEqual(@as(i64, 175_000), dest_cents);
}

test "destination exposure: destination_id zero is not tracked" {
    const account = makeMinimalAccount(5_000_000);
    const new_ob = PendingObligation{
        .proposal_id = 1_100,
        .rail = .ach,
        .destination_id = 0,
        .amount_cents = 100_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    const impact = computePendingPaymentImpact(&account, new_ob, &[_]PendingObligation{}, 0, 0);
    try testing.expectEqual(@as(u8, 0), impact.destination_exposure_count);
    try testing.expectEqual(@as(u8, 1), impact.rail_exposure_count); // rail is still tracked
}

// ---------------------------------------------------------------------------
// computeRealizedTradeImpact: thesis bp and partial fills
// ---------------------------------------------------------------------------

test "computeRealizedTradeImpact: thesis_after_bp is 10000 when filled notional equals all holdings" {
    // No existing holdings; filled notional becomes 100% of the portfolio.
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const filled: i64 = 200_000;
    const impact = computeRealizedTradeImpact(&account, &basket, filled, &[_]PendingObligation{}, 0, 0);
    try testing.expectEqual(@as(u32, 0), impact.thesis_before_bp); // no holdings before
    try testing.expectEqual(@as(u32, 10_000), impact.thesis_after_bp); // 100% of portfolio
}

test "computeRealizedTradeImpact: partial fill reduces cash by filled notional not basket target" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const filled: i64 = 150_000; // partial fill
    const impact = computeRealizedTradeImpact(&account, &basket, filled, &[_]PendingObligation{}, 0, 0);
    try testing.expectEqual(@as(i64, 5_000_000 - 150_000), impact.cash_after_cents);
    try testing.expectEqual(@as(i64, 150_000), impact.estimated_trade_cost_cents);
}

// ---------------------------------------------------------------------------
// generateExplanations: all narrative paths
// ---------------------------------------------------------------------------

test "generateExplanations: approval-required explanation produced" {
    const account = makeMinimalAccount(3_000_000);
    const basket = makeBasketWith(account.account_id, 50_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const ob = PendingObligation{
        .proposal_id = 2_000,
        .rail = .ach,
        .destination_id = 1,
        .amount_cents = 50_000,
        .approval_state = .pending,
        .expires_at_ns = 0,
    };
    var impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{ob}, 0, 0);
    generateExplanations(&impact, 0);

    var found = false;
    for (impact.explanations[0..impact.explanation_count]) |*e| {
        if (std.mem.indexOf(u8, e.textSlice(), "approval-required") != null) found = true;
    }
    try testing.expect(found);
}

test "generateExplanations: expired obligation explanation produced" {
    const account = makeMinimalAccount(3_000_000);
    const basket = makeBasketWith(account.account_id, 50_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    const ob = PendingObligation{
        .proposal_id = 2_001,
        .rail = .wire,
        .destination_id = 5,
        .amount_cents = 50_000,
        .approval_state = .pending,
        .expires_at_ns = 1,
    };
    var impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{ob}, 0, 1_000_000);
    generateExplanations(&impact, 0);

    var found = false;
    for (impact.explanations[0..impact.explanation_count]) |*e| {
        if (std.mem.indexOf(u8, e.textSlice(), "expired") != null) found = true;
    }
    try testing.expect(found);
}

test "generateExplanations: thesis position count explanation produced" {
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    var impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);
    generateExplanations(&impact, 0);

    var found = false;
    for (impact.explanations[0..impact.explanation_count]) |*e| {
        if (std.mem.indexOf(u8, e.textSlice(), "position(s)") != null) found = true;
    }
    try testing.expect(found);
}

test "generateExplanations: single-name concentration exceeds cap produces warning" {
    // Basket: 100_000 NVDA + 100_000 SOXX, total_after = 200_000.
    // NVDA concentration = 50% = 5000 bp; policy cap = 3000 bp → exceeded.
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    var impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);
    generateExplanations(&impact, 3_000);

    var found = false;
    for (impact.explanations[0..impact.explanation_count]) |*e| {
        if (std.mem.indexOf(u8, e.textSlice(), "exceeds policy cap") != null) found = true;
    }
    try testing.expect(found);
}

test "generateExplanations: single-name within cap produces reassurance" {
    // NVDA concentration = 50% = 5000 bp; policy cap = 9000 bp (90%) → within.
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "NVDA", .equity, .stock, "SOXX", .equity, .etf);
    var impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);
    generateExplanations(&impact, 9_000);

    var found = false;
    for (impact.explanations[0..impact.explanation_count]) |*e| {
        if (std.mem.indexOf(u8, e.textSlice(), "remains below") != null) found = true;
    }
    try testing.expect(found);
}

test "generateExplanations: zero impact produces no explanations" {
    var impact = std.mem.zeroes(PortfolioImpact);
    generateExplanations(&impact, 0);
    try testing.expectEqual(@as(u8, 0), impact.explanation_count);
}

test "generateExplanations: ETF instrument type explanation produced for material change" {
    // Basket is all ETFs from zero ETF holdings → ETF exposure change is material (>500 bp).
    const account = makeMinimalAccount(5_000_000);
    const basket = makeBasketWith(account.account_id, 200_000, "SOXX", .equity, .etf, "BOTZ", .equity, .etf);
    var impact = computePreTradeImpact(&account, &basket, &[_]PendingObligation{}, 0, 0);
    generateExplanations(&impact, 0);

    var found = false;
    for (impact.explanations[0..impact.explanation_count]) |*e| {
        if (std.mem.indexOf(u8, e.textSlice(), "ETF") != null) found = true;
    }
    try testing.expect(found);
}
