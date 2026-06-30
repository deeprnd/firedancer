/// V1.3.S2 Thesis and Money Proposal Cards
///
/// ThesisCard (T1): persisted after paper execution. Carries thesis id, user text,
/// basket id, linked positions (each with ticker, rationale, and allocation_cents),
/// target and current exposure in basis points, health status, and timestamps.
///
/// MoneyProposalCard (T2): persisted after proposal generation. Carries proposal id,
/// source event, beneficiary, rail, currency, amount, approval state, expiry,
/// content-addressed evidence hash, and status.
///
/// buildThesisCard() (T3): constructs a ThesisCard from basket and computed impact
/// after a paper execution. Linked positions carry the basket rationale strings (T5).
///
/// buildMoneyProposalCard() (T4): constructs a MoneyProposalCard from a pending
/// obligation plus source and evidence metadata. The evidence_hash field links the
/// card back to the content-addressed evidence record (T5).
const std = @import("std");
const basket_mod = @import("basket");
const impact_mod = @import("impact");

// Re-export impact types so card consumers do not import impact separately.
pub const PaymentRail = impact_mod.PaymentRail;
pub const ApprovalState = impact_mod.ApprovalState;

pub const cards_schema_version: u16 = 1;

// ---------------------------------------------------------------------------
// Capacity constants
// ---------------------------------------------------------------------------

/// Maximum linked positions in one ThesisCard (bounded by basket max).
pub const max_linked_positions: usize = basket_mod.max_basket_instruments;
/// Maximum bytes in user_text stored in a ThesisCard.
pub const max_user_text_len: usize = 512;
/// Maximum bytes in the source_event field of a MoneyProposalCard.
pub const max_source_event_len: usize = 64;
/// Maximum bytes in the beneficiary field of a MoneyProposalCard.
pub const max_beneficiary_len: usize = 128;
/// Currency code slot: three-letter ISO code zero-padded to 4 bytes.
pub const currency_len: usize = 4;

// ---------------------------------------------------------------------------
// ThesisCard (T1)
// ---------------------------------------------------------------------------

/// Health status of a thesis card.
pub const ThesisCardStatus = enum(u8) {
    /// Thesis is active and within bounds at last check.
    active,
    /// At least one drift condition was detected at last check.
    drifted,
    /// Thesis was manually closed or superseded.
    closed,
};

/// One position linked to a thesis card, carrying the basket rationale (T5).
pub const LinkedPosition = struct {
    ticker: [basket_mod.catalog.max_ticker_len]u8,
    ticker_len: u8,
    /// Rationale text copied from the basket instrument at card creation (T5).
    rationale: [basket_mod.max_rationale_len]u8,
    rationale_len: u8,
    allocation_cents: i64,

    pub fn tickerSlice(self: *const LinkedPosition) []const u8 {
        return self.ticker[0..self.ticker_len];
    }

    pub fn rationaleSlice(self: *const LinkedPosition) []const u8 {
        return self.rationale[0..self.rationale_len];
    }
};

/// Persisted record for an investment thesis after paper execution (T1).
pub const ThesisCard = struct {
    /// Content hash of the source ThesisInput (computeThesisInputHash()).
    thesis_id: u64,
    user_text: [max_user_text_len]u8,
    user_text_len: u16,
    /// Content hash of the basket produced from the thesis.
    basket_id: u64,
    /// Positions included in the basket, with rationale and allocation (T5).
    linked_positions: [max_linked_positions]LinkedPosition,
    linked_position_count: u8,
    /// Intended exposure: basket fraction of total invested portfolio after
    /// paper execution, in basis points (10000 = 100%).
    target_exposure_bp: u32,
    /// Exposure at last check (equals target_exposure_bp at card creation).
    current_exposure_bp: u32,
    status: ThesisCardStatus,
    /// Nanosecond epoch timestamp of card creation.
    created_at_ns: u64,
    /// Nanosecond epoch timestamp of last drift check.
    last_checked_at_ns: u64,

    pub fn userTextSlice(self: *const ThesisCard) []const u8 {
        return self.user_text[0..self.user_text_len];
    }
};

// ---------------------------------------------------------------------------
// MoneyProposalCard (T2)
// ---------------------------------------------------------------------------

/// Lifecycle status of a money proposal card.
pub const MoneyProposalStatus = enum(u8) {
    /// Proposal is open and awaiting action or approval.
    pending,
    /// Proposal was approved and is ready for execution.
    approved,
    /// Proposal was rejected.
    rejected,
    /// Proposal approval window has expired.
    expired,
    /// Proposal was executed (future tkexec path).
    executed,
};

/// Persisted record for a payment or transfer proposal (T2).
pub const MoneyProposalCard = struct {
    /// Stable proposal identifier matching the source PendingObligation.
    proposal_id: u64,
    /// Financial event that triggered this proposal (e.g. "payment.failed").
    source_event: [max_source_event_len]u8,
    source_event_len: u8,
    /// Human-readable beneficiary label or opaque identifier.
    beneficiary: [max_beneficiary_len]u8,
    beneficiary_len: u8,
    rail: PaymentRail,
    /// ISO 4217 currency code, zero-padded to currency_len bytes.
    currency: [currency_len]u8,
    amount_cents: i64,
    approval_state: ApprovalState,
    /// Nanosecond epoch expiry; 0 means no expiry.
    expires_at_ns: u64,
    /// Content-addressed hash of the evidence record that justified this
    /// proposal. Links the card back to auditable rationale (T5).
    evidence_hash: u64,
    status: MoneyProposalStatus,
    created_at_ns: u64,

    pub fn sourceEventSlice(self: *const MoneyProposalCard) []const u8 {
        return self.source_event[0..self.source_event_len];
    }

    pub fn beneficiarySlice(self: *const MoneyProposalCard) []const u8 {
        return self.beneficiary[0..self.beneficiary_len];
    }

    pub fn currencySlice(self: *const MoneyProposalCard) []const u8 {
        var end: usize = currency_len;
        while (end > 0 and self.currency[end - 1] == 0) end -= 1;
        return self.currency[0..end];
    }
};

// ---------------------------------------------------------------------------
// Build functions (T3, T4)
// ---------------------------------------------------------------------------

/// Construct a ThesisCard after paper execution (T3).
///
/// `thesis_id`  — computeThesisInputHash() result for the source ThesisInput.
/// `user_text`  — the raw investor text from ThesisInput; truncated to
///                max_user_text_len if necessary.
/// `basket`     — the deterministic basket produced from the thesis.
/// `impact`     — the PortfolioImpact computed after paper execution.
///                impact.thesis_after_bp is used as both target and current
///                exposure at card creation (they diverge only in S3 drift).
/// `now_ns`     — nanosecond epoch timestamp for created_at_ns and
///                last_checked_at_ns.
///
/// Linked positions are populated from basket.instruments, carrying the per-
/// instrument rationale strings so the card can be rendered without the basket
/// being present (T5).
pub fn buildThesisCard(
    thesis_id: u64,
    user_text: []const u8,
    basket: *const basket_mod.Basket,
    impact: *const impact_mod.PortfolioImpact,
    now_ns: u64,
) ThesisCard {
    var card = std.mem.zeroes(ThesisCard);
    card.thesis_id = thesis_id;
    card.basket_id = basket.basket_id;
    card.target_exposure_bp = impact.thesis_after_bp;
    card.current_exposure_bp = impact.thesis_after_bp;
    card.status = .active;
    card.created_at_ns = now_ns;
    card.last_checked_at_ns = now_ns;

    // Copy user text, clamped to capacity.
    const text_len = @min(user_text.len, max_user_text_len);
    @memcpy(card.user_text[0..text_len], user_text[0..text_len]);
    card.user_text_len = @intCast(text_len);

    // Link positions: copy ticker, rationale, and allocation from each basket
    // instrument so the card carries its own evidence references (T5).
    const pos_count = @min(basket.instrument_count, max_linked_positions);
    for (basket.instruments[0..pos_count], 0..) |*instr, i| {
        var pos = std.mem.zeroes(LinkedPosition);

        const tk_len = @min(@as(usize, instr.ticker_len), basket_mod.catalog.max_ticker_len);
        @memcpy(pos.ticker[0..tk_len], instr.ticker[0..tk_len]);
        pos.ticker_len = @intCast(tk_len);

        const rat_len = @min(@as(usize, instr.rationale_len), basket_mod.max_rationale_len);
        @memcpy(pos.rationale[0..rat_len], instr.rationale[0..rat_len]);
        pos.rationale_len = @intCast(rat_len);

        pos.allocation_cents = instr.allocation_cents;
        card.linked_positions[i] = pos;
    }
    card.linked_position_count = @intCast(pos_count);

    return card;
}

/// Construct a MoneyProposalCard after proposal generation (T4).
///
/// `obligation`     — the PendingObligation created by the proposal path.
/// `source_event`   — the financial event type that triggered the proposal
///                    (e.g. "payment.failed", "transfer.requested").
/// `beneficiary`    — display label or destination identifier for the
///                    beneficiary; truncated to max_beneficiary_len.
/// `currency`       — ISO 4217 code (e.g. "USD"); must be 1–3 bytes.
/// `evidence_hash`  — content-addressed hash of the evidence record that
///                    justified this proposal. Links the card back to auditable
///                    rationale (T5). Pass 0 when evidence is not yet hashed.
/// `now_ns`         — nanosecond epoch timestamp for created_at_ns.
pub fn buildMoneyProposalCard(
    obligation: *const impact_mod.PendingObligation,
    source_event: []const u8,
    beneficiary: []const u8,
    currency: []const u8,
    evidence_hash: u64,
    now_ns: u64,
) MoneyProposalCard {
    var card = std.mem.zeroes(MoneyProposalCard);
    card.proposal_id = obligation.proposal_id;
    card.rail = obligation.rail;
    card.amount_cents = obligation.amount_cents;
    card.approval_state = obligation.approval_state;
    card.expires_at_ns = obligation.expires_at_ns;
    card.evidence_hash = evidence_hash;
    card.created_at_ns = now_ns;

    // Derive card status from approval state.
    card.status = switch (obligation.approval_state) {
        .pending => .pending,
        .approved => .approved,
        .rejected => .rejected,
        .expired => .expired,
    };

    const ev_len = @min(source_event.len, max_source_event_len);
    @memcpy(card.source_event[0..ev_len], source_event[0..ev_len]);
    card.source_event_len = @intCast(ev_len);

    const ben_len = @min(beneficiary.len, max_beneficiary_len);
    @memcpy(card.beneficiary[0..ben_len], beneficiary[0..ben_len]);
    card.beneficiary_len = @intCast(ben_len);

    // Copy ISO currency code into the fixed-width slot.
    const cur_len = @min(currency.len, currency_len);
    @memcpy(card.currency[0..cur_len], currency[0..cur_len]);

    return card;
}

// ---------------------------------------------------------------------------
// Tests (T3, T4, T5)
// ---------------------------------------------------------------------------

const testing = std.testing;
const cat = basket_mod.catalog;

fn makeMinimalBasket(basket_id: u64, thesis_id: u64) basket_mod.Basket {
    var b = std.mem.zeroes(basket_mod.Basket);
    b.basket_id = basket_id;
    b.thesis_id = thesis_id;
    b.account_id = 1001;
    b.target_notional_cents = 200_000;
    b.total_allocated_cents = 200_000;
    return b;
}

fn addInstrument(
    b: *basket_mod.Basket,
    comptime ticker: []const u8,
    comptime rationale: []const u8,
    allocation_cents: i64,
) void {
    const i = b.instrument_count;
    @memcpy(b.instruments[i].ticker[0..ticker.len], ticker);
    b.instruments[i].ticker_len = ticker.len;
    @memcpy(b.instruments[i].rationale[0..rationale.len], rationale);
    b.instruments[i].rationale_len = rationale.len;
    b.instruments[i].allocation_cents = allocation_cents;
    b.instruments[i].asset_class = .equity;
    b.instruments[i].instrument_type = .etf;
    b.instruments[i].weight_bp = 5000;
    b.instrument_count += 1;
}

fn makeMinimalImpact(thesis_after_bp: u32) impact_mod.PortfolioImpact {
    var imp = std.mem.zeroes(impact_mod.PortfolioImpact);
    imp.thesis_after_bp = thesis_after_bp;
    imp.thesis_before_bp = 0;
    imp.thesis_position_count = 2;
    return imp;
}

fn makeObligation(
    proposal_id: u64,
    rail: PaymentRail,
    amount_cents: i64,
    approval_state: ApprovalState,
    expires_at_ns: u64,
) impact_mod.PendingObligation {
    return .{
        .proposal_id = proposal_id,
        .rail = rail,
        .destination_id = 42,
        .amount_cents = amount_cents,
        .approval_state = approval_state,
        .expires_at_ns = expires_at_ns,
    };
}

// ---- ThesisCard (T3) -------------------------------------------------------

test "buildThesisCard: thesis_id and basket_id are preserved" {
    var basket = makeMinimalBasket(0xABC, 0xDEF);
    addInstrument(&basket, "SOXX", "AI semiconductor ETF", 100_000);
    addInstrument(&basket, "NVDA", "GPU leader for AI workloads", 100_000);

    const impact = makeMinimalImpact(2_200);
    const card = buildThesisCard(0xDEF, "Buy AI infra", &basket, &impact, 1_000_000);

    try testing.expectEqual(@as(u64, 0xDEF), card.thesis_id);
    try testing.expectEqual(@as(u64, 0xABC), card.basket_id);
}

test "buildThesisCard: target and current exposure equal thesis_after_bp at creation" {
    var basket = makeMinimalBasket(1, 2);
    addInstrument(&basket, "SOXX", "semiconductor etf", 200_000);

    const impact = makeMinimalImpact(3_100);
    const card = buildThesisCard(2, "test", &basket, &impact, 0);

    try testing.expectEqual(@as(u32, 3_100), card.target_exposure_bp);
    try testing.expectEqual(@as(u32, 3_100), card.current_exposure_bp);
}

test "buildThesisCard: status is active at creation" {
    var basket = makeMinimalBasket(1, 2);
    addInstrument(&basket, "SOXX", "reason", 100_000);

    const impact = makeMinimalImpact(1_000);
    const card = buildThesisCard(2, "test", &basket, &impact, 0);

    try testing.expectEqual(ThesisCardStatus.active, card.status);
}

test "buildThesisCard: timestamps set to now_ns" {
    var basket = makeMinimalBasket(1, 2);
    addInstrument(&basket, "SOXX", "reason", 100_000);

    const now: u64 = 9_999_888_777;
    const impact = makeMinimalImpact(1_000);
    const card = buildThesisCard(2, "test", &basket, &impact, now);

    try testing.expectEqual(now, card.created_at_ns);
    try testing.expectEqual(now, card.last_checked_at_ns);
}

test "buildThesisCard: user text stored and retrievable" {
    var basket = makeMinimalBasket(1, 2);
    addInstrument(&basket, "SOXX", "reason", 100_000);

    const user_text = "I want to invest USD 2,000 in AI infrastructure.";
    const impact = makeMinimalImpact(2_200);
    const card = buildThesisCard(2, user_text, &basket, &impact, 0);

    try testing.expectEqualStrings(user_text, card.userTextSlice());
}

// T5: linked positions carry ticker and rationale from the basket.
test "buildThesisCard: linked positions carry ticker and rationale from basket (T5)" {
    var basket = makeMinimalBasket(10, 20);
    addInstrument(&basket, "SOXX", "AI semiconductor ETF for broad exposure", 100_000);
    addInstrument(&basket, "NVDA", "GPU leader enabling AI model training", 100_000);

    const impact = makeMinimalImpact(2_200);
    const card = buildThesisCard(20, "AI infra thesis", &basket, &impact, 0);

    try testing.expectEqual(@as(u8, 2), card.linked_position_count);

    try testing.expectEqualStrings("SOXX", card.linked_positions[0].tickerSlice());
    try testing.expectEqualStrings("AI semiconductor ETF for broad exposure", card.linked_positions[0].rationaleSlice());
    try testing.expectEqual(@as(i64, 100_000), card.linked_positions[0].allocation_cents);

    try testing.expectEqualStrings("NVDA", card.linked_positions[1].tickerSlice());
    try testing.expectEqualStrings("GPU leader enabling AI model training", card.linked_positions[1].rationaleSlice());
    try testing.expectEqual(@as(i64, 100_000), card.linked_positions[1].allocation_cents);
}

test "buildThesisCard: empty basket produces zero linked_position_count" {
    const basket = makeMinimalBasket(5, 6);
    const impact = makeMinimalImpact(0);
    const card = buildThesisCard(6, "test", &basket, &impact, 0);

    try testing.expectEqual(@as(u8, 0), card.linked_position_count);
}

test "buildThesisCard: user text truncated at max_user_text_len" {
    var basket = makeMinimalBasket(1, 2);
    addInstrument(&basket, "SOXX", "r", 100_000);

    // Build a text longer than max_user_text_len.
    var long_text: [max_user_text_len + 10]u8 = undefined;
    @memset(&long_text, 'x');

    const impact = makeMinimalImpact(0);
    const card = buildThesisCard(2, &long_text, &basket, &impact, 0);

    try testing.expectEqual(@as(u16, max_user_text_len), card.user_text_len);
}

// ---- MoneyProposalCard (T4) ------------------------------------------------

test "buildMoneyProposalCard: proposal_id, rail, amount, approval_state preserved" {
    const ob = makeObligation(101, .ach, 124_000, .pending, 0);
    const card = buildMoneyProposalCard(&ob, "payment.failed", "Supplier A", "USD", 0xCAFE, 5_000);

    try testing.expectEqual(@as(u64, 101), card.proposal_id);
    try testing.expectEqual(PaymentRail.ach, card.rail);
    try testing.expectEqual(@as(i64, 124_000), card.amount_cents);
    try testing.expectEqual(ApprovalState.pending, card.approval_state);
}

test "buildMoneyProposalCard: source_event and beneficiary stored correctly" {
    const ob = makeObligation(202, .wire, 50_000, .approved, 0);
    const card = buildMoneyProposalCard(&ob, "transfer.requested", "Payroll account", "USD", 0, 0);

    try testing.expectEqualStrings("transfer.requested", card.sourceEventSlice());
    try testing.expectEqualStrings("Payroll account", card.beneficiarySlice());
}

test "buildMoneyProposalCard: currency stored and trimmed" {
    const ob = makeObligation(303, .ach, 10_000, .pending, 0);
    const card = buildMoneyProposalCard(&ob, "payment.retry", "Partner B", "USD", 0, 0);

    try testing.expectEqualStrings("USD", card.currencySlice());
}

// T5: evidence_hash links the card back to auditable evidence.
test "buildMoneyProposalCard: evidence_hash links card to evidence record (T5)" {
    const ob = makeObligation(404, .ach, 124_000, .pending, 0);
    const evidence_hash: u64 = 0xDEAD_BEEF_CAFE_1234;
    const card = buildMoneyProposalCard(&ob, "payment.failed", "Supplier payout", "USD", evidence_hash, 0);

    try testing.expectEqual(evidence_hash, card.evidence_hash);
}

test "buildMoneyProposalCard: status derived from approval_state at creation" {
    const pending_ob = makeObligation(1, .ach, 1_000, .pending, 0);
    const pending_card = buildMoneyProposalCard(&pending_ob, "ev", "b", "USD", 0, 0);
    try testing.expectEqual(MoneyProposalStatus.pending, pending_card.status);

    const approved_ob = makeObligation(2, .ach, 1_000, .approved, 0);
    const approved_card = buildMoneyProposalCard(&approved_ob, "ev", "b", "USD", 0, 0);
    try testing.expectEqual(MoneyProposalStatus.approved, approved_card.status);

    const rejected_ob = makeObligation(3, .ach, 1_000, .rejected, 0);
    const rejected_card = buildMoneyProposalCard(&rejected_ob, "ev", "b", "USD", 0, 0);
    try testing.expectEqual(MoneyProposalStatus.rejected, rejected_card.status);

    const expired_ob = makeObligation(4, .ach, 1_000, .expired, 0);
    const expired_card = buildMoneyProposalCard(&expired_ob, "ev", "b", "USD", 0, 0);
    try testing.expectEqual(MoneyProposalStatus.expired, expired_card.status);
}

test "buildMoneyProposalCard: expires_at_ns and created_at_ns preserved" {
    const expiry: u64 = 9_999_000_000;
    const now: u64 = 5_000_000_000;
    const ob = makeObligation(505, .wire, 75_000, .pending, expiry);
    const card = buildMoneyProposalCard(&ob, "payment.failed", "Vendor C", "USD", 0, now);

    try testing.expectEqual(expiry, card.expires_at_ns);
    try testing.expectEqual(now, card.created_at_ns);
}

test "buildMoneyProposalCard: zero evidence_hash is valid" {
    const ob = makeObligation(606, .internal, 10_000, .pending, 0);
    const card = buildMoneyProposalCard(&ob, "ledger.transfer", "Internal ops", "USD", 0, 0);

    try testing.expectEqual(@as(u64, 0), card.evidence_hash);
}

test "buildMoneyProposalCard: beneficiary truncated at max_beneficiary_len" {
    const ob = makeObligation(707, .ach, 1_000, .pending, 0);
    var long_ben: [max_beneficiary_len + 5]u8 = undefined;
    @memset(&long_ben, 'B');

    const card = buildMoneyProposalCard(&ob, "ev", &long_ben, "USD", 0, 0);
    try testing.expectEqual(@as(u8, max_beneficiary_len), card.beneficiary_len);
}

test "cards_schema_version is 1" {
    try testing.expectEqual(@as(u16, 1), cards_schema_version);
}
