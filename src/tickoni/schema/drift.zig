/// V1.3.S3 Drift, approval, and rebalance signals
///
/// T1: ThesisDriftCondition — allocation breach, sector breach, concentration
///     breach, instrument no longer eligible, buying-power change.
/// T2: PaymentDriftCondition — retry window expired, beneficiary limit changed,
///     evidence expired, approval expired, approval revoked, cash buffer breached.
/// T3: fixtures — deterministic market, cash, and approval-state values that
///     trigger each drift condition.
/// T4: RebalanceSuggestion + generateRebalanceSuggestion() — previewable
///     rebalance ticket, always in proposed state, no autonomous execution.
/// T5: PaymentProposalUpdate + generatePaymentProposalUpdate() — updated
///     proposal record, always requires explicit user action.
const std = @import("std");
const basket_mod = @import("basket");
const cards_mod = @import("cards");

pub const drift_schema_version: u16 = 1;

const cat = basket_mod.catalog;
const bp_denom = cards_mod.bp_denom;
const governance_field_len: usize = 32;

// ---------------------------------------------------------------------------
// Capacity constants
// ---------------------------------------------------------------------------

pub const max_thesis_drift_conditions: usize = 8;
pub const max_payment_drift_conditions: usize = 8;
pub const max_rebalance_adjustments: usize = basket_mod.max_basket_instruments;
pub const max_reason_len: usize = 128;
pub const max_ticker_len: usize = cat.max_ticker_len;
pub const max_source_event_len: usize = cards_mod.max_source_event_len;
pub const max_beneficiary_len: usize = cards_mod.max_beneficiary_len;
pub const currency_len: usize = cards_mod.currency_len;

pub const ThesisDriftError = error{
    EmptyLinkedPositions,
    InvalidTargetExposure,
    InvalidCurrentExposure,
    InvalidSectorExposure,
    InvalidSingleNameExposure,
    InvalidAllocationThreshold,
    InvalidSectorThreshold,
    InvalidSingleNameThreshold,
    NegativeMinBuyingPower,
    RestrictedTickerTooLong,
    NonPositiveLinkedAllocation,
};

pub const PaymentDriftError = error{
    NegativeCashBufferThreshold,
    NegativeDailyLimit,
    NegativeMonthlyLimit,
    NegativeCurrentDailyLimit,
    NegativeCurrentMonthlyLimit,
};

pub const PaymentProposalUpdateError = error{
    EmptyActionClass,
    ActionClassTooLong,
    EmptyApprovalPath,
    ApprovalPathTooLong,
    EmptyPolicyVersion,
    PolicyVersionTooLong,
};

// ---------------------------------------------------------------------------
// T1: Thesis drift conditions
// ---------------------------------------------------------------------------

/// Conditions that indicate a thesis has drifted from its original state (T1).
pub const ThesisDriftCondition = enum(u8) {
    /// Actual exposure diverges from target beyond the policy threshold.
    allocation_breach,
    /// A sector's share of the invested portfolio exceeds the policy cap.
    sector_exposure_breach,
    /// A single position's weight exceeds the single-name concentration cap.
    concentration_breach,
    /// A linked position's instrument is now restricted or no longer eligible.
    instrument_no_longer_eligible,
    /// Buying power dropped below the minimum needed to execute a rebalance.
    buying_power_change,

    pub fn label(self: ThesisDriftCondition) []const u8 {
        return switch (self) {
            .allocation_breach => "allocation_breach",
            .sector_exposure_breach => "sector_exposure_breach",
            .concentration_breach => "concentration_breach",
            .instrument_no_longer_eligible => "instrument_no_longer_eligible",
            .buying_power_change => "buying_power_change",
        };
    }
};

// ---------------------------------------------------------------------------
// T2: Payment drift conditions
// ---------------------------------------------------------------------------

/// Conditions that indicate a payment or transfer proposal has drifted (T2).
pub const PaymentDriftCondition = enum(u8) {
    /// The retry window for the payment has expired.
    retry_window_expired,
    /// The per-beneficiary daily or monthly limit changed since proposal creation.
    beneficiary_limit_changed,
    /// The evidence backing the proposal has expired.
    evidence_expired,
    /// The approval window for the proposal has expired.
    approval_expired,
    /// A previously granted approval was revoked.
    approval_revoked,
    /// Cash dropped below the required buffer, putting the payment at risk.
    cash_buffer_breached,

    pub fn label(self: PaymentDriftCondition) []const u8 {
        return switch (self) {
            .retry_window_expired => "retry_window_expired",
            .beneficiary_limit_changed => "beneficiary_limit_changed",
            .evidence_expired => "evidence_expired",
            .approval_expired => "approval_expired",
            .approval_revoked => "approval_revoked",
            .cash_buffer_breached => "cash_buffer_breached",
        };
    }
};

// ---------------------------------------------------------------------------
// Policy thresholds
// ---------------------------------------------------------------------------

/// Policy thresholds that govern thesis drift assessment.
pub const ThesisDriftPolicy = struct {
    /// Absolute delta in bp between actual and target that constitutes a breach.
    allocation_breach_threshold_bp: u32,
    /// Sector exposure above this fraction (bp of invested portfolio) is a breach.
    max_sector_exposure_bp: u32,
    /// Single-name concentration above this (bp of invested portfolio) is a breach.
    max_single_name_bp: u32,
    /// Buying power below this (cents) means a rebalance cannot be afforded.
    min_buying_power_to_rebalance_cents: i64,
};

/// Policy thresholds that govern payment drift assessment.
pub const PaymentDriftPolicy = struct {
    /// Required cash buffer (cents). Buffer breach is a drift condition.
    cash_buffer_threshold_cents: i64,
    /// Daily limit per beneficiary (cents) recorded at proposal creation.
    daily_limit_cents_at_proposal: i64,
    /// Monthly limit per beneficiary (cents) recorded at proposal creation.
    monthly_limit_cents_at_proposal: i64,
};

// ---------------------------------------------------------------------------
// Thesis drift result (T1)
// ---------------------------------------------------------------------------

pub const ThesisDriftResult = struct {
    active_conditions: [max_thesis_drift_conditions]ThesisDriftCondition,
    condition_count: u8,
    allocation_actual_bp: u32,
    allocation_target_bp: u32,
    /// Absolute delta |actual - target| in basis points.
    allocation_delta_abs_bp: u32,
    max_sector_exposure_bp: u32,
    max_single_name_bp: u32,
    /// First linked-position ticker that is now restricted. Empty if none.
    restricted_ticker: [max_ticker_len]u8,
    restricted_ticker_len: u8,
    buying_power_cents: i64,
    has_drift: bool,

    pub fn restrictedTickerSlice(self: *const ThesisDriftResult) []const u8 {
        return self.restricted_ticker[0..self.restricted_ticker_len];
    }
};

// ---------------------------------------------------------------------------
// Payment drift result (T2)
// ---------------------------------------------------------------------------

pub const PaymentDriftResult = struct {
    active_conditions: [max_payment_drift_conditions]PaymentDriftCondition,
    condition_count: u8,
    has_drift: bool,
};

// ---------------------------------------------------------------------------
// T4: Rebalance suggestion
// ---------------------------------------------------------------------------

pub const RebalanceSuggestionStatus = enum(u8) {
    /// Suggestion is previewable and awaits explicit user approval.
    proposed,

    pub fn label(self: RebalanceSuggestionStatus) []const u8 {
        return switch (self) {
            .proposed => "proposed",
        };
    }
};

pub const RebalanceDirection = enum(u8) {
    buy,
    sell,
    hold,

    pub fn label(self: RebalanceDirection) []const u8 {
        return switch (self) {
            .buy => "buy",
            .sell => "sell",
            .hold => "hold",
        };
    }
};

pub const RebalanceAdjustment = struct {
    ticker: [max_ticker_len]u8,
    ticker_len: u8,
    direction: RebalanceDirection,
    current_weight_bp: u32,
    target_weight_bp: u32,
    /// Suggested notional in cents. 0 for holds or when buying power is insufficient.
    suggested_notional_cents: i64,

    pub fn tickerSlice(self: *const RebalanceAdjustment) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

/// Previewable rebalance ticket produced from thesis drift assessment (T4).
/// Status is always .proposed. No trade executes without explicit user action.
pub const RebalanceSuggestion = struct {
    schema_version: u16,
    thesis_id: u64,
    basket_id: u64,
    status: RebalanceSuggestionStatus,
    reason: [max_reason_len]u8,
    reason_len: u8,
    target_exposure_bp: u32,
    current_exposure_bp: u32,
    adjustments: [max_rebalance_adjustments]RebalanceAdjustment,
    adjustment_count: u8,
    requires_user_action: bool,

    pub fn reasonSlice(self: *const RebalanceSuggestion) []const u8 {
        return self.reason[0..self.reason_len];
    }
};

// ---------------------------------------------------------------------------
// T5: Payment proposal update
// ---------------------------------------------------------------------------

pub const SuggestedProposalStatus = enum(u8) {
    no_change,
    needs_renewal,
    needs_replacement,
    cancel_suggested,

    pub fn label(self: SuggestedProposalStatus) []const u8 {
        return switch (self) {
            .no_change => "no_change",
            .needs_renewal => "needs_renewal",
            .needs_replacement => "needs_replacement",
            .cancel_suggested => "cancel_suggested",
        };
    }
};

pub const PaymentProposalGovernance = struct {
    action_class: []const u8,
    approval_path: []const u8,
    policy_version: []const u8,
};

/// Updated payment proposal record produced from drift assessment (T5).
/// No retry, transfer, or payment executes without explicit user action.
pub const PaymentProposalUpdate = struct {
    schema_version: u16,
    proposal_id: u64,
    source_event: [max_source_event_len]u8,
    source_event_len: u8,
    beneficiary: [max_beneficiary_len]u8,
    beneficiary_len: u8,
    rail: cards_mod.PaymentRail,
    currency: [currency_len]u8,
    amount_cents: i64,
    approval_state: cards_mod.ApprovalState,
    expires_at_ns: u64,
    evidence_hash: u64,
    action_class: [governance_field_len]u8,
    action_class_len: u8,
    approval_path: [governance_field_len]u8,
    approval_path_len: u8,
    policy_version: [governance_field_len]u8,
    policy_version_len: u8,
    suggested_status: SuggestedProposalStatus,
    drift_conditions: [max_payment_drift_conditions]PaymentDriftCondition,
    drift_condition_count: u8,
    requires_user_action: bool,

    pub fn sourceEventSlice(self: *const PaymentProposalUpdate) []const u8 {
        return self.source_event[0..self.source_event_len];
    }

    pub fn beneficiarySlice(self: *const PaymentProposalUpdate) []const u8 {
        return self.beneficiary[0..self.beneficiary_len];
    }

    pub fn currencySlice(self: *const PaymentProposalUpdate) []const u8 {
        var end: usize = currency_len;
        while (end > 0 and self.currency[end - 1] == 0) end -= 1;
        return self.currency[0..end];
    }

    pub fn actionClassSlice(self: *const PaymentProposalUpdate) []const u8 {
        return self.action_class[0..self.action_class_len];
    }

    pub fn approvalPathSlice(self: *const PaymentProposalUpdate) []const u8 {
        return self.approval_path[0..self.approval_path_len];
    }

    pub fn policyVersionSlice(self: *const PaymentProposalUpdate) []const u8 {
        return self.policy_version[0..self.policy_version_len];
    }
};

// ---------------------------------------------------------------------------
// Combined drift contract for UI consumption
// ---------------------------------------------------------------------------

pub const DriftContract = struct {
    schema_version: u16 = drift_schema_version,
    thesis_drift: ThesisDriftResult,
    rebalance_suggestion: RebalanceSuggestion,
    payment_drift: PaymentDriftResult,
    payment_proposal_update: PaymentProposalUpdate,
};

// ---------------------------------------------------------------------------
// T3: Deterministic drift fixtures
// ---------------------------------------------------------------------------

/// Deterministic test-only values that trigger specific drift conditions (T3).
const fixtures = struct {
    // ---- Thesis drift policy ----
    pub const thesis_policy = ThesisDriftPolicy{
        .allocation_breach_threshold_bp = 800,
        .max_sector_exposure_bp = 5_000,
        .max_single_name_bp = 3_000,
        .min_buying_power_to_rebalance_cents = 200_000,
    };

    // Thesis target: 31%. Breach when actual drops to 18% (delta 1300 bp > 800).
    pub const thesis_target_bp: u32 = 3_100;
    pub const allocation_breach_actual_bp: u32 = 1_800;
    pub const allocation_ok_actual_bp: u32 = 2_800;

    // Sector breach: 60% > 50% cap.
    pub const sector_breach_max_sector_bp: u32 = 6_000;
    pub const sector_ok_max_sector_bp: u32 = 4_000;

    // Concentration breach: 35% > 30% cap.
    pub const concentration_breach_max_single_name_bp: u32 = 3_500;
    pub const concentration_ok_max_single_name_bp: u32 = 2_500;

    // Buying power: USD 1,000 < USD 2,000 minimum.
    pub const low_buying_power_cents: i64 = 100_000;
    pub const adequate_buying_power_cents: i64 = 500_000;

    // ---- Payment drift policy ----
    pub const payment_policy = PaymentDriftPolicy{
        .cash_buffer_threshold_cents = 500_000,
        .daily_limit_cents_at_proposal = 200_000,
        .monthly_limit_cents_at_proposal = 1_000_000,
    };

    // Reference timestamp: 2025-12-15T10:00:00Z in nanoseconds.
    pub const now_ns: u64 = 1_765_792_800_000_000_000;

    // Approval expiry: ns epoch far in the past → triggers approval_expired.
    pub const expired_at_ns: u64 = 1_000;

    // Retry window: 1000 seconds before now → triggers retry_window_expired.
    pub const past_retry_window_ns: u64 = now_ns - 1_000_000_000_000;

    // Evidence expiry: 1 day before now → triggers evidence_expired.
    pub const past_evidence_expiry_ns: u64 = now_ns - 86_400_000_000_000;

    // Cash fixtures for payment drift.
    pub const low_available_cash_cents: i64 = 300_000;
    pub const adequate_available_cash_cents: i64 = 800_000;

    // Changed limits trigger beneficiary_limit_changed.
    pub const changed_daily_limit_cents: i64 = 100_000;
    pub const changed_monthly_limit_cents: i64 = 500_000;

    pub const payment_governance = PaymentProposalGovernance{
        .action_class = "payment_retry.propose",
        .approval_path = "maker_checker",
        .policy_version = "tickoni.v1",
    };
};

// ---------------------------------------------------------------------------
// T1: Thesis drift assessment
// ---------------------------------------------------------------------------

/// Assess thesis drift from scalar current-state inputs (T1).
///
/// current_exposure_bp         — actual current thesis exposure (caller computes)
/// current_max_sector_bp       — highest sector concentration in current portfolio (bp)
/// current_max_single_name_bp  — highest single-name concentration (bp)
/// current_buying_power_cents  — current account buying power in cents
/// restricted_linked_ticker    — first linked-position ticker now restricted; null if none
pub fn assessThesisDrift(
    thesis_card: *const cards_mod.ThesisCard,
    current_exposure_bp: u32,
    current_max_sector_bp: u32,
    current_max_single_name_bp: u32,
    current_buying_power_cents: i64,
    restricted_linked_ticker: ?[]const u8,
    policy: ThesisDriftPolicy,
) ThesisDriftError!ThesisDriftResult {
    try validateThesisDriftInputs(
        thesis_card,
        current_exposure_bp,
        current_max_sector_bp,
        current_max_single_name_bp,
        current_buying_power_cents,
        restricted_linked_ticker,
        policy,
    );

    var result = std.mem.zeroes(ThesisDriftResult);
    result.allocation_actual_bp = current_exposure_bp;
    result.allocation_target_bp = thesis_card.target_exposure_bp;
    result.max_sector_exposure_bp = current_max_sector_bp;
    result.max_single_name_bp = current_max_single_name_bp;
    result.buying_power_cents = current_buying_power_cents;

    const delta_abs: u32 = if (current_exposure_bp >= thesis_card.target_exposure_bp)
        current_exposure_bp - thesis_card.target_exposure_bp
    else
        thesis_card.target_exposure_bp - current_exposure_bp;
    result.allocation_delta_abs_bp = delta_abs;

    if (delta_abs >= policy.allocation_breach_threshold_bp)
        addThesisCond(&result, .allocation_breach);

    if (current_max_sector_bp >= policy.max_sector_exposure_bp)
        addThesisCond(&result, .sector_exposure_breach);

    if (current_max_single_name_bp >= policy.max_single_name_bp)
        addThesisCond(&result, .concentration_breach);

    if (restricted_linked_ticker) |ticker| {
        addThesisCond(&result, .instrument_no_longer_eligible);
        @memcpy(result.restricted_ticker[0..ticker.len], ticker[0..ticker.len]);
        result.restricted_ticker_len = @intCast(ticker.len);
    }

    if (current_buying_power_cents < policy.min_buying_power_to_rebalance_cents)
        addThesisCond(&result, .buying_power_change);

    result.has_drift = result.condition_count > 0;
    return result;
}

fn validateThesisDriftInputs(
    thesis_card: *const cards_mod.ThesisCard,
    current_exposure_bp: u32,
    current_max_sector_bp: u32,
    current_max_single_name_bp: u32,
    current_buying_power_cents: i64,
    restricted_linked_ticker: ?[]const u8,
    policy: ThesisDriftPolicy,
) ThesisDriftError!void {
    if (thesis_card.linked_position_count == 0) return error.EmptyLinkedPositions;
    if (thesis_card.target_exposure_bp > bp_denom) return error.InvalidTargetExposure;
    if (current_exposure_bp > bp_denom) return error.InvalidCurrentExposure;
    if (current_max_sector_bp > bp_denom) return error.InvalidSectorExposure;
    if (current_max_single_name_bp > bp_denom) return error.InvalidSingleNameExposure;
    if (policy.allocation_breach_threshold_bp > bp_denom) return error.InvalidAllocationThreshold;
    if (policy.max_sector_exposure_bp > bp_denom) return error.InvalidSectorThreshold;
    if (policy.max_single_name_bp > bp_denom) return error.InvalidSingleNameThreshold;
    if (policy.min_buying_power_to_rebalance_cents < 0 or current_buying_power_cents < 0) {
        return error.NegativeMinBuyingPower;
    }
    if (restricted_linked_ticker) |ticker| {
        if (ticker.len == 0 or ticker.len > max_ticker_len) return error.RestrictedTickerTooLong;
    }
    for (thesis_card.linked_positions[0..thesis_card.linked_position_count]) |position| {
        if (position.allocation_cents <= 0) return error.NonPositiveLinkedAllocation;
    }
}

fn addThesisCond(result: *ThesisDriftResult, condition: ThesisDriftCondition) void {
    if (result.condition_count >= max_thesis_drift_conditions) return;
    result.active_conditions[result.condition_count] = condition;
    result.condition_count += 1;
}

// ---------------------------------------------------------------------------
// T2: Payment drift assessment
// ---------------------------------------------------------------------------

/// Assess payment proposal drift (T2).
///
/// retry_window_expiry_ns      — 0 means no retry window limit
/// evidence_expiry_ns          — 0 means evidence has no expiry
/// previous_approval_state     — null means unknown; .approved with current .pending/.rejected
///                               indicates revocation
/// cash_buffer_breached        — true if current cash is below the required buffer
/// current_daily_limit_cents   — current per-beneficiary daily limit (cents)
/// current_monthly_limit_cents — current per-beneficiary monthly limit (cents)
pub fn assessPaymentDrift(
    card: *const cards_mod.MoneyProposalCard,
    now_ns: u64,
    retry_window_expiry_ns: u64,
    evidence_expiry_ns: u64,
    previous_approval_state: ?cards_mod.ApprovalState,
    available_cash_cents: i64,
    current_daily_limit_cents: i64,
    current_monthly_limit_cents: i64,
    policy: PaymentDriftPolicy,
) PaymentDriftError!PaymentDriftResult {
    try validatePaymentDriftInputs(
        current_daily_limit_cents,
        current_monthly_limit_cents,
        policy,
    );

    var result = std.mem.zeroes(PaymentDriftResult);

    if (retry_window_expiry_ns != 0 and now_ns > retry_window_expiry_ns)
        addPaymentCond(&result, .retry_window_expired);

    if (current_daily_limit_cents != policy.daily_limit_cents_at_proposal or
        current_monthly_limit_cents != policy.monthly_limit_cents_at_proposal)
        addPaymentCond(&result, .beneficiary_limit_changed);

    if (evidence_expiry_ns != 0 and now_ns > evidence_expiry_ns)
        addPaymentCond(&result, .evidence_expired);

    if ((card.expires_at_ns != 0 and now_ns > card.expires_at_ns) or
        card.approval_state == .expired)
        addPaymentCond(&result, .approval_expired);

    if (previous_approval_state) |prev| {
        if (prev == .approved and
            (card.approval_state == .pending or card.approval_state == .rejected))
            addPaymentCond(&result, .approval_revoked);
    }

    if (available_cash_cents < policy.cash_buffer_threshold_cents)
        addPaymentCond(&result, .cash_buffer_breached);

    result.has_drift = result.condition_count > 0;
    return result;
}

fn validatePaymentDriftInputs(
    current_daily_limit_cents: i64,
    current_monthly_limit_cents: i64,
    policy: PaymentDriftPolicy,
) PaymentDriftError!void {
    if (policy.cash_buffer_threshold_cents < 0) return error.NegativeCashBufferThreshold;
    if (policy.daily_limit_cents_at_proposal < 0) return error.NegativeDailyLimit;
    if (policy.monthly_limit_cents_at_proposal < 0) return error.NegativeMonthlyLimit;
    if (current_daily_limit_cents < 0) return error.NegativeCurrentDailyLimit;
    if (current_monthly_limit_cents < 0) return error.NegativeCurrentMonthlyLimit;
}

fn addPaymentCond(result: *PaymentDriftResult, condition: PaymentDriftCondition) void {
    if (result.condition_count >= max_payment_drift_conditions) return;
    result.active_conditions[result.condition_count] = condition;
    result.condition_count += 1;
}

// ---------------------------------------------------------------------------
// T4: Generate rebalance suggestion
// ---------------------------------------------------------------------------

/// Produce a previewable rebalance ticket from thesis drift (T4).
/// Status is always .proposed. No trade executes without explicit user action.
pub fn generateRebalanceSuggestion(
    thesis_card: *const cards_mod.ThesisCard,
    drift_result: ThesisDriftResult,
    buying_power_cents: i64,
) ThesisDriftError!RebalanceSuggestion {
    if (thesis_card.linked_position_count == 0) return error.EmptyLinkedPositions;

    var s = std.mem.zeroes(RebalanceSuggestion);
    s.schema_version = drift_schema_version;
    s.thesis_id = thesis_card.thesis_id;
    s.basket_id = thesis_card.basket_id;
    s.status = .proposed;
    s.target_exposure_bp = thesis_card.target_exposure_bp;
    s.current_exposure_bp = drift_result.allocation_actual_bp;
    s.requires_user_action = true;

    var reason_buf: [max_reason_len]u8 = undefined;
    const reason = buildRebalanceReason(&reason_buf, drift_result.active_conditions[0..drift_result.condition_count]);
    const rlen = @min(reason.len, max_reason_len);
    @memcpy(s.reason[0..rlen], reason[0..rlen]);
    s.reason_len = @intCast(rlen);

    if (!drift_result.has_drift) return s;

    const allocation_short = allocationShort(
        drift_result.active_conditions[0..drift_result.condition_count],
        drift_result.allocation_actual_bp,
        thesis_card.target_exposure_bp,
    );
    const allocation_long = hasAllocationLong(
        drift_result.active_conditions[0..drift_result.condition_count],
        drift_result.allocation_actual_bp,
        thesis_card.target_exposure_bp,
    );
    const sell_pressure = hasSellPressure(drift_result.active_conditions[0..drift_result.condition_count]);

    const pos_count: usize = thesis_card.linked_position_count;
    const per_position_cents: i64 = if (pos_count > 0 and allocation_short)
        @divTrunc(buying_power_cents, @as(i64, @intCast(pos_count)))
    else
        0;
    const total_linked_cents = linkedPositionTotalCents(thesis_card);
    if (total_linked_cents <= 0) return error.NonPositiveLinkedAllocation;

    for (thesis_card.linked_positions[0..pos_count]) |*pos| {
        if (s.adjustment_count >= max_rebalance_adjustments) break;
        var adj = std.mem.zeroes(RebalanceAdjustment);
        const tlen: usize = pos.ticker_len;
        @memcpy(adj.ticker[0..tlen], pos.ticker[0..tlen]);
        adj.ticker_len = pos.ticker_len;
        adj.current_weight_bp = allocationToBp(pos.allocation_cents, total_linked_cents);
        adj.target_weight_bp = targetWeightForPosition(pos, drift_result, pos_count);
        adj.direction = rebalanceDirectionForPosition(
            pos,
            drift_result,
            allocation_short,
            allocation_long,
            sell_pressure,
            adj.current_weight_bp,
            adj.target_weight_bp,
        );
        adj.suggested_notional_cents = switch (adj.direction) {
            .buy => per_position_cents,
            .sell => suggestedSellNotional(pos.allocation_cents, total_linked_cents, adj.current_weight_bp, adj.target_weight_bp),
            .hold => 0,
        };
        if (adj.direction == .hold and !isOnlyBuyingPowerDrift(drift_result.active_conditions[0..drift_result.condition_count])) continue;
        s.adjustments[s.adjustment_count] = adj;
        s.adjustment_count += 1;
    }

    return s;
}

fn allocationShort(
    conditions: []const ThesisDriftCondition,
    actual_bp: u32,
    target_bp: u32,
) bool {
    for (conditions) |c| {
        if (c == .allocation_breach and actual_bp < target_bp) return true;
    }
    return false;
}

fn hasAllocationLong(
    conditions: []const ThesisDriftCondition,
    actual_bp: u32,
    target_bp: u32,
) bool {
    for (conditions) |c| {
        if (c == .allocation_breach and actual_bp > target_bp) return true;
    }
    return false;
}

fn hasSellPressure(conditions: []const ThesisDriftCondition) bool {
    for (conditions) |c| {
        switch (c) {
            .sector_exposure_breach, .concentration_breach, .instrument_no_longer_eligible => return true,
            else => {},
        }
    }
    return false;
}

fn isOnlyBuyingPowerDrift(conditions: []const ThesisDriftCondition) bool {
    return conditions.len == 1 and conditions[0] == .buying_power_change;
}

fn linkedPositionTotalCents(thesis_card: *const cards_mod.ThesisCard) i64 {
    var total: i64 = 0;
    for (thesis_card.linked_positions[0..thesis_card.linked_position_count]) |position| {
        total += position.allocation_cents;
    }
    return total;
}

fn allocationToBp(allocation_cents: i64, total_cents: i64) u32 {
    if (allocation_cents <= 0 or total_cents <= 0) return 0;
    return @intCast(@divTrunc(@as(i128, allocation_cents) * bp_denom, total_cents));
}

fn targetWeightForPosition(
    position: *const cards_mod.LinkedPosition,
    drift_result: ThesisDriftResult,
    pos_count: usize,
) u32 {
    if (drift_result.condition_count > 0 and drift_result.restricted_ticker_len > 0 and
        std.mem.eql(u8, position.tickerSlice(), drift_result.restrictedTickerSlice()))
        return 0;
    if (pos_count == 0) return 0;
    return @intCast(@divTrunc(@as(u64, bp_denom), pos_count));
}

fn rebalanceDirectionForPosition(
    position: *const cards_mod.LinkedPosition,
    drift_result: ThesisDriftResult,
    allocation_short: bool,
    allocation_long: bool,
    sell_pressure: bool,
    current_weight_bp: u32,
    target_weight_bp: u32,
) RebalanceDirection {
    if (drift_result.restricted_ticker_len > 0 and
        std.mem.eql(u8, position.tickerSlice(), drift_result.restrictedTickerSlice()))
        return .sell;
    if (allocation_short) return .buy;
    if (allocation_long or sell_pressure) {
        if (current_weight_bp > target_weight_bp or target_weight_bp == 0) return .sell;
    }
    return .hold;
}

fn suggestedSellNotional(
    allocation_cents: i64,
    total_linked_cents: i64,
    current_weight_bp: u32,
    target_weight_bp: u32,
) i64 {
    if (target_weight_bp == 0) return allocation_cents;
    if (current_weight_bp <= target_weight_bp) return 0;
    const target_allocation_cents = @divTrunc(@as(i128, total_linked_cents) * target_weight_bp, bp_denom);
    const delta = allocation_cents - @as(i64, @intCast(target_allocation_cents));
    return if (delta > 0) delta else 0;
}

fn buildRebalanceReason(buf: []u8, conditions: []const ThesisDriftCondition) []const u8 {
    if (conditions.len == 0) return "No drift detected.";
    return switch (conditions[0]) {
        .allocation_breach => std.fmt.bufPrint(buf, "Allocation drifted from target; rebalance suggested.", .{}) catch "Allocation drift.",
        .sector_exposure_breach => std.fmt.bufPrint(buf, "Sector exposure exceeds cap; diversification suggested.", .{}) catch "Sector drift.",
        .concentration_breach => std.fmt.bufPrint(buf, "Single-name concentration exceeds cap; trim suggested.", .{}) catch "Concentration drift.",
        .instrument_no_longer_eligible => std.fmt.bufPrint(buf, "Linked instrument is no longer eligible; replacement suggested.", .{}) catch "Eligibility drift.",
        .buying_power_change => std.fmt.bufPrint(buf, "Buying power below minimum to rebalance; defer until funded.", .{}) catch "Buying power drift.",
    };
}

// ---------------------------------------------------------------------------
// T5: Generate payment proposal update
// ---------------------------------------------------------------------------

/// Produce an updated payment proposal record from drift assessment (T5).
/// No retry, transfer, or payment executes without explicit user action.
pub fn generatePaymentProposalUpdate(
    card: *const cards_mod.MoneyProposalCard,
    drift_result: PaymentDriftResult,
) PaymentProposalUpdateError!PaymentProposalUpdate {
    var u = std.mem.zeroes(PaymentProposalUpdate);
    u.schema_version = drift_schema_version;
    u.proposal_id = card.proposal_id;
    @memcpy(u.source_event[0..card.source_event_len], card.source_event[0..card.source_event_len]);
    u.source_event_len = card.source_event_len;
    @memcpy(u.beneficiary[0..card.beneficiary_len], card.beneficiary[0..card.beneficiary_len]);
    u.beneficiary_len = card.beneficiary_len;
    u.rail = card.rail;
    u.currency = card.currency;
    u.amount_cents = card.amount_cents;
    u.approval_state = card.approval_state;
    u.expires_at_ns = card.expires_at_ns;
    u.evidence_hash = card.evidence_hash;
    u.requires_user_action = drift_result.has_drift;
    u.drift_condition_count = drift_result.condition_count;
    for (drift_result.active_conditions[0..drift_result.condition_count], 0..) |c, i| {
        u.drift_conditions[i] = c;
    }
    u.suggested_status = suggestProposalStatus(drift_result.active_conditions[0..drift_result.condition_count]);
    return u;
}

pub fn generateGovernedPaymentProposalUpdate(
    card: *const cards_mod.MoneyProposalCard,
    drift_result: PaymentDriftResult,
    governance: PaymentProposalGovernance,
) PaymentProposalUpdateError!PaymentProposalUpdate {
    try validateGovernanceFields(governance);

    var update = try generatePaymentProposalUpdate(card, drift_result);
    @memcpy(update.action_class[0..governance.action_class.len], governance.action_class);
    update.action_class_len = @intCast(governance.action_class.len);
    @memcpy(update.approval_path[0..governance.approval_path.len], governance.approval_path);
    update.approval_path_len = @intCast(governance.approval_path.len);
    @memcpy(update.policy_version[0..governance.policy_version.len], governance.policy_version);
    update.policy_version_len = @intCast(governance.policy_version.len);
    return update;
}

fn validateGovernanceFields(governance: PaymentProposalGovernance) PaymentProposalUpdateError!void {
    if (governance.action_class.len == 0) return error.EmptyActionClass;
    if (governance.action_class.len > governance_field_len) return error.ActionClassTooLong;
    if (governance.approval_path.len == 0) return error.EmptyApprovalPath;
    if (governance.approval_path.len > governance_field_len) return error.ApprovalPathTooLong;
    if (governance.policy_version.len == 0) return error.EmptyPolicyVersion;
    if (governance.policy_version.len > governance_field_len) return error.PolicyVersionTooLong;
}

fn suggestProposalStatus(conditions: []const PaymentDriftCondition) SuggestedProposalStatus {
    var has_expiry = false;
    var has_revocation = false;
    var has_buffer = false;
    for (conditions) |c| {
        switch (c) {
            .approval_expired, .retry_window_expired, .evidence_expired => has_expiry = true,
            .approval_revoked => has_revocation = true,
            .cash_buffer_breached => has_buffer = true,
            .beneficiary_limit_changed => {},
        }
    }
    if (has_revocation) return .cancel_suggested;
    if (has_expiry) return .needs_renewal;
    if (has_buffer) return .needs_replacement;
    if (conditions.len > 0) return .needs_renewal;
    return .no_change;
}

fn updateValue(hasher: *std.hash.Wyhash, value: anytype) void {
    var copy = value;
    hasher.update(std.mem.asBytes(&copy));
}

pub fn hashRebalanceSuggestion(suggestion: *const RebalanceSuggestion) u64 {
    var hasher = std.hash.Wyhash.init(0);
    updateValue(&hasher, suggestion.schema_version);
    updateValue(&hasher, suggestion.thesis_id);
    updateValue(&hasher, suggestion.basket_id);
    updateValue(&hasher, suggestion.status);
    hasher.update(suggestion.reasonSlice());
    updateValue(&hasher, suggestion.target_exposure_bp);
    updateValue(&hasher, suggestion.current_exposure_bp);
    updateValue(&hasher, suggestion.adjustment_count);
    for (suggestion.adjustments[0..suggestion.adjustment_count]) |adjustment| {
        hasher.update(adjustment.tickerSlice());
        updateValue(&hasher, adjustment.direction);
        updateValue(&hasher, adjustment.current_weight_bp);
        updateValue(&hasher, adjustment.target_weight_bp);
        updateValue(&hasher, adjustment.suggested_notional_cents);
    }
    updateValue(&hasher, suggestion.requires_user_action);
    return hasher.final();
}

pub fn hashPaymentProposalUpdate(update: *const PaymentProposalUpdate) u64 {
    var hasher = std.hash.Wyhash.init(0);
    updateValue(&hasher, update.schema_version);
    updateValue(&hasher, update.proposal_id);
    hasher.update(update.sourceEventSlice());
    hasher.update(update.beneficiarySlice());
    updateValue(&hasher, update.rail);
    hasher.update(update.currencySlice());
    updateValue(&hasher, update.amount_cents);
    updateValue(&hasher, update.approval_state);
    updateValue(&hasher, update.expires_at_ns);
    updateValue(&hasher, update.evidence_hash);
    hasher.update(update.actionClassSlice());
    hasher.update(update.approvalPathSlice());
    hasher.update(update.policyVersionSlice());
    updateValue(&hasher, update.suggested_status);
    updateValue(&hasher, update.drift_condition_count);
    for (update.drift_conditions[0..update.drift_condition_count]) |condition| {
        updateValue(&hasher, condition);
    }
    updateValue(&hasher, update.requires_user_action);
    return hasher.final();
}

pub fn hashDriftContract(contract: *const DriftContract) u64 {
    var hasher = std.hash.Wyhash.init(0);
    updateValue(&hasher, contract.schema_version);
    updateValue(&hasher, contract.thesis_drift.condition_count);
    for (contract.thesis_drift.active_conditions[0..contract.thesis_drift.condition_count]) |condition| {
        updateValue(&hasher, condition);
    }
    updateValue(&hasher, contract.thesis_drift.allocation_actual_bp);
    updateValue(&hasher, contract.thesis_drift.allocation_target_bp);
    updateValue(&hasher, contract.thesis_drift.allocation_delta_abs_bp);
    updateValue(&hasher, contract.thesis_drift.max_sector_exposure_bp);
    updateValue(&hasher, contract.thesis_drift.max_single_name_bp);
    hasher.update(contract.thesis_drift.restrictedTickerSlice());
    updateValue(&hasher, contract.thesis_drift.buying_power_cents);
    updateValue(&hasher, contract.thesis_drift.has_drift);
    updateValue(&hasher, hashRebalanceSuggestion(&contract.rebalance_suggestion));
    updateValue(&hasher, contract.payment_drift.condition_count);
    for (contract.payment_drift.active_conditions[0..contract.payment_drift.condition_count]) |condition| {
        updateValue(&hasher, condition);
    }
    updateValue(&hasher, contract.payment_drift.has_drift);
    updateValue(&hasher, hashPaymentProposalUpdate(&contract.payment_proposal_update));
    return hasher.final();
}

// ---------------------------------------------------------------------------
// JSON export
// ---------------------------------------------------------------------------

pub fn allocDriftContractJson(
    allocator: std.mem.Allocator,
    contract: *const DriftContract,
) ![]u8 {
    const AdjView = struct {
        ticker: []const u8,
        direction: []const u8,
        current_weight_bp: u32,
        target_weight_bp: u32,
        suggested_notional_cents: i64,
    };

    var thesis_cond_labels: [max_thesis_drift_conditions][]const u8 = undefined;
    for (contract.thesis_drift.active_conditions[0..contract.thesis_drift.condition_count], 0..) |c, i| {
        thesis_cond_labels[i] = c.label();
    }

    var adj_views: [max_rebalance_adjustments]AdjView = undefined;
    for (contract.rebalance_suggestion.adjustments[0..contract.rebalance_suggestion.adjustment_count], 0..) |*adj, i| {
        adj_views[i] = .{
            .ticker = adj.tickerSlice(),
            .direction = adj.direction.label(),
            .current_weight_bp = adj.current_weight_bp,
            .target_weight_bp = adj.target_weight_bp,
            .suggested_notional_cents = adj.suggested_notional_cents,
        };
    }

    var payment_cond_labels: [max_payment_drift_conditions][]const u8 = undefined;
    for (contract.payment_drift.active_conditions[0..contract.payment_drift.condition_count], 0..) |c, i| {
        payment_cond_labels[i] = c.label();
    }

    var update_cond_labels: [max_payment_drift_conditions][]const u8 = undefined;
    for (contract.payment_proposal_update.drift_conditions[0..contract.payment_proposal_update.drift_condition_count], 0..) |c, i| {
        update_cond_labels[i] = c.label();
    }

    return std.json.Stringify.valueAlloc(allocator, .{
        .schema_version = contract.schema_version,
        .thesis_drift = .{
            .active_conditions = thesis_cond_labels[0..contract.thesis_drift.condition_count],
            .allocation_actual_bp = contract.thesis_drift.allocation_actual_bp,
            .allocation_target_bp = contract.thesis_drift.allocation_target_bp,
            .allocation_delta_abs_bp = contract.thesis_drift.allocation_delta_abs_bp,
            .max_sector_exposure_bp = contract.thesis_drift.max_sector_exposure_bp,
            .max_single_name_bp = contract.thesis_drift.max_single_name_bp,
            .restricted_ticker = contract.thesis_drift.restrictedTickerSlice(),
            .buying_power_cents = contract.thesis_drift.buying_power_cents,
            .has_drift = contract.thesis_drift.has_drift,
        },
        .rebalance_suggestion = .{
            .thesis_id = contract.rebalance_suggestion.thesis_id,
            .basket_id = contract.rebalance_suggestion.basket_id,
            .status = contract.rebalance_suggestion.status.label(),
            .reason = contract.rebalance_suggestion.reasonSlice(),
            .target_exposure_bp = contract.rebalance_suggestion.target_exposure_bp,
            .current_exposure_bp = contract.rebalance_suggestion.current_exposure_bp,
            .adjustments = adj_views[0..contract.rebalance_suggestion.adjustment_count],
            .requires_user_action = contract.rebalance_suggestion.requires_user_action,
        },
        .payment_drift = .{
            .active_conditions = payment_cond_labels[0..contract.payment_drift.condition_count],
            .has_drift = contract.payment_drift.has_drift,
        },
        .payment_proposal_update = .{
            .proposal_id = contract.payment_proposal_update.proposal_id,
            .source_event = contract.payment_proposal_update.sourceEventSlice(),
            .beneficiary = contract.payment_proposal_update.beneficiarySlice(),
            .rail = railLabel(contract.payment_proposal_update.rail),
            .currency = contract.payment_proposal_update.currencySlice(),
            .amount_cents = contract.payment_proposal_update.amount_cents,
            .approval_state = approvalStateLabel(contract.payment_proposal_update.approval_state),
            .expires_at_ns = contract.payment_proposal_update.expires_at_ns,
            .evidence_hash = contract.payment_proposal_update.evidence_hash,
            .action_class = contract.payment_proposal_update.actionClassSlice(),
            .approval_path = contract.payment_proposal_update.approvalPathSlice(),
            .policy_version = contract.payment_proposal_update.policyVersionSlice(),
            .suggested_status = contract.payment_proposal_update.suggested_status.label(),
            .drift_conditions = update_cond_labels[0..contract.payment_proposal_update.drift_condition_count],
            .requires_user_action = contract.payment_proposal_update.requires_user_action,
        },
    }, .{});
}

fn railLabel(rail: cards_mod.PaymentRail) []const u8 {
    return switch (rail) {
        .ach => "ach",
        .wire => "wire",
        .card => "card",
        .internal => "internal",
    };
}

fn approvalStateLabel(state: cards_mod.ApprovalState) []const u8 {
    return switch (state) {
        .pending => "pending",
        .approved => "approved",
        .rejected => "rejected",
        .expired => "expired",
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn makeThesisCard(thesis_id: u64, basket_id: u64, target_bp: u32) cards_mod.ThesisCard {
    var card = std.mem.zeroes(cards_mod.ThesisCard);
    card.thesis_id = thesis_id;
    card.basket_id = basket_id;
    card.target_exposure_bp = target_bp;
    card.current_exposure_bp = target_bp;
    card.status = .active;
    card.created_at_ns = 1_000_000;
    card.last_checked_at_ns = 1_000_000;
    const text = "AI infrastructure thesis";
    @memcpy(card.user_text[0..text.len], text);
    card.user_text_len = @intCast(text.len);
    return card;
}

fn addPosition(card: *cards_mod.ThesisCard, comptime ticker: []const u8) void {
    const i = card.linked_position_count;
    @memcpy(card.linked_positions[i].ticker[0..ticker.len], ticker);
    card.linked_positions[i].ticker_len = @intCast(ticker.len);
    card.linked_positions[i].evidence_hash = 0xDEAD_BEEF;
    card.linked_positions[i].allocation_cents = 100_000;
    card.linked_position_count += 1;
}

fn makeProposalCard(
    proposal_id: u64,
    approval_state: cards_mod.ApprovalState,
    expires_at_ns: u64,
) cards_mod.MoneyProposalCard {
    var card = std.mem.zeroes(cards_mod.MoneyProposalCard);
    card.proposal_id = proposal_id;
    card.approval_state = approval_state;
    card.expires_at_ns = expires_at_ns;
    card.amount_cents = 124_000;
    card.rail = .ach;
    card.status = .pending;
    const se = "payment_failed";
    @memcpy(card.source_event[0..se.len], se);
    card.source_event_len = @intCast(se.len);
    const ben = "supplier_acme_us";
    @memcpy(card.beneficiary[0..ben.len], ben);
    card.beneficiary_len = @intCast(ben.len);
    @memcpy(card.currency[0..3], "USD");
    card.evidence_hash = 0xCAFE;
    card.created_at_ns = 1_000;
    return card;
}

test "drift_schema_version is 1" {
    try testing.expectEqual(@as(u16, 1), drift_schema_version);
}

// T1: allocation_breach

test "assessThesisDrift: allocation_breach when delta exceeds threshold" {
    var card = makeThesisCard(1, 2, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const result = try assessThesisDrift(
        &card,
        fixtures.allocation_breach_actual_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .allocation_breach) found = true;
    }
    try testing.expect(found);
    try testing.expectEqual(fixtures.thesis_target_bp, result.allocation_target_bp);
    try testing.expectEqual(fixtures.allocation_breach_actual_bp, result.allocation_actual_bp);
    try testing.expectEqual(@as(u32, 1_300), result.allocation_delta_abs_bp);
}

test "assessThesisDrift: no allocation_breach when delta is within threshold" {
    var card = makeThesisCard(1, 2, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const result = try assessThesisDrift(
        &card,
        fixtures.allocation_ok_actual_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );

    for (result.active_conditions[0..result.condition_count]) |c| {
        try testing.expect(c != .allocation_breach);
    }
}

// T1: sector_exposure_breach

test "assessThesisDrift: sector_exposure_breach when sector exceeds cap" {
    var card = makeThesisCard(3, 4, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const result = try assessThesisDrift(
        &card,
        fixtures.thesis_target_bp,
        fixtures.sector_breach_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .sector_exposure_breach) found = true;
    }
    try testing.expect(found);
}

test "assessThesisDrift: no sector_exposure_breach when sector is under cap" {
    var card = makeThesisCard(3, 4, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const result = try assessThesisDrift(
        &card,
        fixtures.thesis_target_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );

    for (result.active_conditions[0..result.condition_count]) |c| {
        try testing.expect(c != .sector_exposure_breach);
    }
}

// T1: concentration_breach

test "assessThesisDrift: concentration_breach when single-name exceeds cap" {
    var card = makeThesisCard(5, 6, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const result = try assessThesisDrift(
        &card,
        fixtures.thesis_target_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_breach_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .concentration_breach) found = true;
    }
    try testing.expect(found);
}

// T1: instrument_no_longer_eligible

test "assessThesisDrift: instrument_no_longer_eligible when restricted ticker supplied" {
    var card = makeThesisCard(7, 8, fixtures.thesis_target_bp);
    addPosition(&card, "SOXL");

    const result = try assessThesisDrift(
        &card,
        fixtures.thesis_target_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        "SOXL",
        fixtures.thesis_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .instrument_no_longer_eligible) found = true;
    }
    try testing.expect(found);
    try testing.expectEqualStrings("SOXL", result.restrictedTickerSlice());
}

test "assessThesisDrift: no instrument_no_longer_eligible when restricted_linked_ticker is null" {
    var card = makeThesisCard(7, 8, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const result = try assessThesisDrift(
        &card,
        fixtures.thesis_target_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );

    for (result.active_conditions[0..result.condition_count]) |c| {
        try testing.expect(c != .instrument_no_longer_eligible);
    }
    try testing.expectEqual(@as(u8, 0), result.restricted_ticker_len);
}

// T1: buying_power_change

test "assessThesisDrift: buying_power_change when buying power below minimum" {
    var card = makeThesisCard(9, 10, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const result = try assessThesisDrift(
        &card,
        fixtures.thesis_target_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.low_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .buying_power_change) found = true;
    }
    try testing.expect(found);
}

test "assessThesisDrift: no drift when all values are within policy bounds" {
    var card = makeThesisCard(11, 12, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const result = try assessThesisDrift(
        &card,
        fixtures.allocation_ok_actual_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );

    try testing.expect(!result.has_drift);
    try testing.expectEqual(@as(u8, 0), result.condition_count);
}

// T2: approval_expired

test "assessPaymentDrift: approval_expired when card expiry is in the past" {
    const card = makeProposalCard(101, .pending, fixtures.expired_at_ns);

    const result = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .approval_expired) found = true;
    }
    try testing.expect(found);
}

// T2: retry_window_expired

test "assessPaymentDrift: retry_window_expired when retry window is in the past" {
    const card = makeProposalCard(102, .pending, fixtures.now_ns + 1_000_000);

    const result = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        fixtures.past_retry_window_ns,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .retry_window_expired) found = true;
    }
    try testing.expect(found);
}

// T2: evidence_expired

test "assessPaymentDrift: evidence_expired when evidence expiry is in the past" {
    const card = makeProposalCard(103, .pending, fixtures.now_ns + 1_000_000);

    const result = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        fixtures.past_evidence_expiry_ns,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .evidence_expired) found = true;
    }
    try testing.expect(found);
}

// T2: approval_revoked

test "assessPaymentDrift: approval_revoked when previous state was approved but now pending" {
    const card = makeProposalCard(104, .pending, fixtures.now_ns + 1_000_000);

    const result = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        cards_mod.ApprovalState.approved,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .approval_revoked) found = true;
    }
    try testing.expect(found);
}

test "assessPaymentDrift: no approval_revoked when still pending with no prior approval" {
    const card = makeProposalCard(104, .pending, fixtures.now_ns + 1_000_000);

    const result = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );

    for (result.active_conditions[0..result.condition_count]) |c| {
        try testing.expect(c != .approval_revoked);
    }
}

// T2: cash_buffer_breached

test "assessPaymentDrift: cash_buffer_breached condition set" {
    const card = makeProposalCard(105, .pending, fixtures.now_ns + 1_000_000);

    const result = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.low_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .cash_buffer_breached) found = true;
    }
    try testing.expect(found);
}

// T2: beneficiary_limit_changed

test "assessPaymentDrift: beneficiary_limit_changed when daily limit differs" {
    const card = makeProposalCard(106, .pending, fixtures.now_ns + 1_000_000);

    const result = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.changed_daily_limit_cents,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .beneficiary_limit_changed) found = true;
    }
    try testing.expect(found);
}

test "assessPaymentDrift: beneficiary_limit_changed when monthly limit differs" {
    const card = makeProposalCard(106, .pending, fixtures.now_ns + 1_000_000);

    const result = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.changed_monthly_limit_cents,
        fixtures.payment_policy,
    );

    try testing.expect(result.has_drift);
    var found = false;
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == .beneficiary_limit_changed) found = true;
    }
    try testing.expect(found);
}

test "assessPaymentDrift: no drift when card is valid and limits unchanged" {
    const card = makeProposalCard(107, .pending, fixtures.now_ns + 1_000_000);

    const result = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );

    try testing.expect(!result.has_drift);
    try testing.expectEqual(@as(u8, 0), result.condition_count);
}

// T4: generateRebalanceSuggestion

test "generateRebalanceSuggestion: proposed rebalance for allocation_breach with two positions" {
    var card = makeThesisCard(0xAA, 0xBB, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");
    addPosition(&card, "SOXX");

    const drift = try assessThesisDrift(
        &card,
        fixtures.allocation_breach_actual_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );
    try testing.expect(drift.has_drift);

    const s = try generateRebalanceSuggestion(&card, drift, fixtures.adequate_buying_power_cents);
    try testing.expectEqual(RebalanceSuggestionStatus.proposed, s.status);
    try testing.expect(s.requires_user_action);
    try testing.expectEqual(@as(u8, 2), s.adjustment_count);
    try testing.expectEqual(@as(u64, 0xAA), s.thesis_id);
    try testing.expectEqual(@as(u64, 0xBB), s.basket_id);
    try testing.expectEqual(fixtures.thesis_target_bp, s.target_exposure_bp);
    try testing.expectEqual(fixtures.allocation_breach_actual_bp, s.current_exposure_bp);
    for (s.adjustments[0..s.adjustment_count]) |adj| {
        try testing.expectEqual(RebalanceDirection.buy, adj.direction);
        try testing.expect(adj.current_weight_bp > 0);
        // Each position gets half of buying power.
        try testing.expectEqual(@as(i64, fixtures.adequate_buying_power_cents / 2), adj.suggested_notional_cents);
    }
}

test "generateRebalanceSuggestion: hold direction when no allocation breach" {
    var card = makeThesisCard(0xCC, 0xDD, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const drift = try assessThesisDrift(
        &card,
        fixtures.allocation_ok_actual_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );
    const s = try generateRebalanceSuggestion(&card, drift, fixtures.adequate_buying_power_cents);
    try testing.expectEqual(RebalanceSuggestionStatus.proposed, s.status);
    try testing.expect(s.requires_user_action);
    try testing.expectEqual(@as(u8, 0), s.adjustment_count);
}

test "generateRebalanceSuggestion: reason text is non-empty for any drift" {
    var card = makeThesisCard(0xEE, 0xFF, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");

    const drift = try assessThesisDrift(
        &card,
        fixtures.allocation_breach_actual_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );
    const s = try generateRebalanceSuggestion(&card, drift, fixtures.adequate_buying_power_cents);
    try testing.expect(s.reason_len > 0);
    try testing.expect(std.mem.indexOf(u8, s.reasonSlice(), "Allocation") != null);
}

test "generateRebalanceSuggestion: concentration drift emits sell adjustment" {
    var card = makeThesisCard(0xAB, 0xCD, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");
    addPosition(&card, "MSFT");
    card.linked_positions[0].allocation_cents = 700_000;
    card.linked_positions[1].allocation_cents = 300_000;

    const drift = try assessThesisDrift(
        &card,
        fixtures.thesis_target_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_breach_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );
    const suggestion = try generateRebalanceSuggestion(&card, drift, fixtures.adequate_buying_power_cents);
    try testing.expectEqual(@as(u8, 1), suggestion.adjustment_count);
    try testing.expectEqual(RebalanceDirection.sell, suggestion.adjustments[0].direction);
    try testing.expect(suggestion.adjustments[0].suggested_notional_cents > 0);
}

// T5: generatePaymentProposalUpdate

test "generatePaymentProposalUpdate: needs_renewal for expired approval" {
    const card = makeProposalCard(201, .pending, fixtures.expired_at_ns);
    const drift = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );
    try testing.expect(drift.has_drift);

    const u = try generateGovernedPaymentProposalUpdate(&card, drift, fixtures.payment_governance);
    try testing.expectEqual(@as(u64, 201), u.proposal_id);
    try testing.expectEqual(SuggestedProposalStatus.needs_renewal, u.suggested_status);
    try testing.expect(u.requires_user_action);
    try testing.expect(u.drift_condition_count > 0);
    try testing.expectEqualStrings("payment_retry.propose", u.actionClassSlice());
    try testing.expectEqualStrings("maker_checker", u.approvalPathSlice());
    try testing.expectEqualStrings("tickoni.v1", u.policyVersionSlice());
}

test "generatePaymentProposalUpdate: cancel_suggested for revoked approval" {
    const card = makeProposalCard(202, .pending, fixtures.now_ns + 1_000_000);
    const drift = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        cards_mod.ApprovalState.approved,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );
    try testing.expect(drift.has_drift);

    const u = try generateGovernedPaymentProposalUpdate(&card, drift, fixtures.payment_governance);
    try testing.expectEqual(SuggestedProposalStatus.cancel_suggested, u.suggested_status);
    try testing.expect(u.requires_user_action);
}

test "generatePaymentProposalUpdate: needs_replacement for cash buffer breach" {
    const card = makeProposalCard(203, .pending, fixtures.now_ns + 1_000_000);
    const drift = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.low_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );
    const u = try generateGovernedPaymentProposalUpdate(&card, drift, fixtures.payment_governance);
    try testing.expectEqual(SuggestedProposalStatus.needs_replacement, u.suggested_status);
    try testing.expect(u.requires_user_action);
}

test "generatePaymentProposalUpdate: no_change and no user action when no drift" {
    const card = makeProposalCard(204, .pending, fixtures.now_ns + 1_000_000);
    const drift = try assessPaymentDrift(
        &card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );
    const u = try generateGovernedPaymentProposalUpdate(&card, drift, fixtures.payment_governance);
    try testing.expectEqual(SuggestedProposalStatus.no_change, u.suggested_status);
    try testing.expect(!u.requires_user_action);
    try testing.expectEqual(@as(u8, 0), u.drift_condition_count);
}

// DriftContract and JSON export

test "allocDriftContractJson produces renderable UI contract" {
    var thesis_card = makeThesisCard(0xA1, 0xB2, fixtures.thesis_target_bp);
    addPosition(&thesis_card, "NVDA");

    const thesis_drift = try assessThesisDrift(
        &thesis_card,
        fixtures.allocation_breach_actual_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );
    const rebalance = try generateRebalanceSuggestion(&thesis_card, thesis_drift, fixtures.adequate_buying_power_cents);

    const payment_card = makeProposalCard(301, .pending, fixtures.expired_at_ns);
    const payment_drift = try assessPaymentDrift(
        &payment_card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );
    const payment_update = try generateGovernedPaymentProposalUpdate(&payment_card, payment_drift, fixtures.payment_governance);

    const contract = DriftContract{
        .thesis_drift = thesis_drift,
        .rebalance_suggestion = rebalance,
        .payment_drift = payment_drift,
        .payment_proposal_update = payment_update,
    };

    const json = try allocDriftContractJson(testing.allocator, &contract);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"thesis_drift\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"rebalance_suggestion\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"payment_drift\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"payment_proposal_update\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"proposed\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "allocation_breach") != null);
    try testing.expect(std.mem.indexOf(u8, json, "approval_expired") != null);
    try testing.expect(std.mem.indexOf(u8, json, "needs_renewal") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"approval_path\":\"maker_checker\"") != null);
}

test "allocDriftContractJson: no execution paths in output for no-drift state" {
    var thesis_card = makeThesisCard(0xC3, 0xD4, fixtures.thesis_target_bp);
    addPosition(&thesis_card, "NVDA");

    const thesis_drift = try assessThesisDrift(
        &thesis_card,
        fixtures.allocation_ok_actual_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );
    const rebalance = try generateRebalanceSuggestion(&thesis_card, thesis_drift, fixtures.adequate_buying_power_cents);

    const payment_card = makeProposalCard(401, .pending, fixtures.now_ns + 1_000_000);
    const payment_drift = try assessPaymentDrift(
        &payment_card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );
    const payment_update = try generateGovernedPaymentProposalUpdate(&payment_card, payment_drift, fixtures.payment_governance);

    const contract = DriftContract{
        .thesis_drift = thesis_drift,
        .rebalance_suggestion = rebalance,
        .payment_drift = payment_drift,
        .payment_proposal_update = payment_update,
    };

    const json = try allocDriftContractJson(testing.allocator, &contract);
    defer testing.allocator.free(json);

    // No drift means no active conditions in either drift block.
    try testing.expect(std.mem.indexOf(u8, json, "\"has_drift\":false") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"no_change\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"adjustments\":[]") != null);
}

test "assessThesisDrift: overlong restricted ticker fails closed" {
    var card = makeThesisCard(0x01, 0x02, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");
    const ticker = "TOO_LONGER";
    try testing.expectError(
        error.RestrictedTickerTooLong,
        assessThesisDrift(
            &card,
            fixtures.thesis_target_bp,
            fixtures.sector_ok_max_sector_bp,
            fixtures.concentration_ok_max_single_name_bp,
            fixtures.adequate_buying_power_cents,
            ticker,
            fixtures.thesis_policy,
        ),
    );
}

test "assessThesisDrift: invalid exposure over 10000 bp fails closed" {
    var card = makeThesisCard(0x03, 0x04, fixtures.thesis_target_bp);
    addPosition(&card, "NVDA");
    try testing.expectError(
        error.InvalidCurrentExposure,
        assessThesisDrift(
            &card,
            10_001,
            fixtures.sector_ok_max_sector_bp,
            fixtures.concentration_ok_max_single_name_bp,
            fixtures.adequate_buying_power_cents,
            null,
            fixtures.thesis_policy,
        ),
    );
}

test "assessPaymentDrift: negative cash buffer threshold fails closed" {
    const card = makeProposalCard(500, .pending, fixtures.now_ns + 1_000_000);
    var policy = fixtures.payment_policy;
    policy.cash_buffer_threshold_cents = -1;
    try testing.expectError(
        error.NegativeCashBufferThreshold,
        assessPaymentDrift(
            &card,
            fixtures.now_ns,
            0,
            0,
            null,
            fixtures.adequate_available_cash_cents,
            fixtures.payment_policy.daily_limit_cents_at_proposal,
            fixtures.payment_policy.monthly_limit_cents_at_proposal,
            policy,
        ),
    );
}

test "hashDriftContract is deterministic" {
    var thesis_card = makeThesisCard(0x05, 0x06, fixtures.thesis_target_bp);
    addPosition(&thesis_card, "NVDA");
    const thesis_drift = try assessThesisDrift(
        &thesis_card,
        fixtures.allocation_breach_actual_bp,
        fixtures.sector_ok_max_sector_bp,
        fixtures.concentration_ok_max_single_name_bp,
        fixtures.adequate_buying_power_cents,
        null,
        fixtures.thesis_policy,
    );
    const rebalance = try generateRebalanceSuggestion(&thesis_card, thesis_drift, fixtures.adequate_buying_power_cents);
    const payment_card = makeProposalCard(600, .pending, fixtures.expired_at_ns);
    const payment_drift = try assessPaymentDrift(
        &payment_card,
        fixtures.now_ns,
        0,
        0,
        null,
        fixtures.adequate_available_cash_cents,
        fixtures.payment_policy.daily_limit_cents_at_proposal,
        fixtures.payment_policy.monthly_limit_cents_at_proposal,
        fixtures.payment_policy,
    );
    const payment_update = try generateGovernedPaymentProposalUpdate(&payment_card, payment_drift, fixtures.payment_governance);
    const contract = DriftContract{
        .thesis_drift = thesis_drift,
        .rebalance_suggestion = rebalance,
        .payment_drift = payment_drift,
        .payment_proposal_update = payment_update,
    };
    try testing.expectEqual(hashDriftContract(&contract), hashDriftContract(&contract));
}
