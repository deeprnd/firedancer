/// Thesis input schema and investor intent normalization for V1.1.S1.
///
/// ThesisInput: raw investor request captured from the user or a demo fixture.
/// InvestorIntent: validated, structured form produced by normalize().
/// fixtures: deterministic demo inputs for the five canonical V1.1 themes.
///
/// All validation in normalize() is fail-closed: missing or out-of-range
/// fields return an explicit ThesisError instead of silently substituting
/// defaults.
const std = @import("std");

/// Maximum bytes stored in the user_text field.
pub const max_user_text_len: usize = 512;

/// Minimum allowed target notional: USD 1.00 = 100 cents.
pub const min_target_notional_cents: i64 = 100;

// ---------------------------------------------------------------------------
// Bounded domain types
// ---------------------------------------------------------------------------

/// Markets supported in V1.1.
pub const Market = enum(u8) { us };

/// Venues within the US market.
pub const Venue = enum(u8) { nyse, nasdaq };

/// Asset classes recognized by the thesis schema.
pub const AssetClass = enum(u8) {
    equity,
    etf,
    option,
    future,
    leveraged_etf,
    inverse_etf,
    crypto,
    bond,
};

/// Bit-set of up to 8 asset classes, backed by a single byte.
pub const AssetClassSet = packed struct(u8) {
    equity: bool = false,
    etf: bool = false,
    option: bool = false,
    future: bool = false,
    leveraged_etf: bool = false,
    inverse_etf: bool = false,
    crypto: bool = false,
    bond: bool = false,

    /// Returns true if the given class is a member of this set.
    pub fn has(self: AssetClassSet, class: AssetClass) bool {
        return switch (class) {
            .equity => self.equity,
            .etf => self.etf,
            .option => self.option,
            .future => self.future,
            .leveraged_etf => self.leveraged_etf,
            .inverse_etf => self.inverse_etf,
            .crypto => self.crypto,
            .bond => self.bond,
        };
    }

    /// Returns true when at least one V1.1-supported class (equity or etf) is set.
    pub fn hasSupportedClass(self: AssetClassSet) bool {
        return self.equity or self.etf;
    }
};

/// Sector and theme taxonomy for V1.1 investment theses.
pub const SectorTheme = enum(u8) {
    ai_infrastructure,
    semiconductors,
    cloud,
    cyber_security,
    broad_market,
    dividends,
    cash_like,
};

pub const RiskPreference = enum(u8) { low, moderate, high };

// ---------------------------------------------------------------------------
// Input schema (T1)
// ---------------------------------------------------------------------------

/// Raw investor thesis as received from the user or provided by a demo fixture.
///
/// user_text is the plain-English investment intent; user_text_len is its byte
/// count.  Call normalize() to validate and convert to InvestorIntent.
pub const ThesisInput = struct {
    user_text: [max_user_text_len]u8,
    user_text_len: u16,
    target_notional_cents: i64,
    account_id: u32,
    market_scope: Market,
    /// Asset classes the user wants to include.
    asset_class_prefs: AssetClassSet,
    sector_theme: SectorTheme,
    risk_preference: RiskPreference,
    /// Maximum single-name allocation as a percentage of total basket notional (1–100).
    max_single_name_pct: u8,
    /// Explicit user exclusions; always merged with denied_asset_classes in normalize().
    exclusions: AssetClassSet,

    pub fn text(self: *const ThesisInput) []const u8 {
        return self.user_text[0..self.user_text_len];
    }
};

// ---------------------------------------------------------------------------
// Normalized output (T3)
// ---------------------------------------------------------------------------

/// Structured investor intent produced by normalize().
///
/// allowed_asset_classes is the user's preference minus always-denied classes
/// and the user's explicit exclusions.
/// excluded_asset_classes is the union of always-denied classes and the user's
/// explicit exclusions, so downstream catalog and basket code can trust it.
pub const InvestorIntent = struct {
    theme: SectorTheme,
    target_amount_cents: i64,
    allowed_asset_classes: AssetClassSet,
    excluded_asset_classes: AssetClassSet,
    market: Market,
    venues: [2]Venue,
    venue_count: u8,
    risk_preference: RiskPreference,
    /// Maximum single-name allocation as a percentage of the basket notional.
    max_single_name_pct: u8,
};

// ---------------------------------------------------------------------------
// Policy constants
// ---------------------------------------------------------------------------

/// Asset classes always denied in V1.1 regardless of user preference.
/// options, futures, leveraged ETFs, inverse ETFs, and crypto are outside the
/// V1.1 mandate and denied by policy even if the user requests them.
pub const denied_asset_classes: AssetClassSet = .{
    .option = true,
    .future = true,
    .leveraged_etf = true,
    .inverse_etf = true,
    .crypto = true,
};

// ---------------------------------------------------------------------------
// Validation errors (T4)
// ---------------------------------------------------------------------------

pub const ThesisError = error{
    EmptyUserText,
    UserTextTooLong,
    MissingTargetAmount,
    TargetAmountTooSmall,
    NoEligibleAssetClass,
};

// ---------------------------------------------------------------------------
// Normalization (T3 + T4)
// ---------------------------------------------------------------------------

/// Validate a ThesisInput and return a structured InvestorIntent.
///
/// Returns ThesisError when:
/// - user_text_len is 0 (EmptyUserText)
/// - user_text_len exceeds max_user_text_len (UserTextTooLong)
/// - target_notional_cents is zero or negative (MissingTargetAmount)
/// - target_notional_cents is below min_target_notional_cents (TargetAmountTooSmall)
/// - no supported asset class (equity or etf) remains after removing
///   always-denied classes and user exclusions (NoEligibleAssetClass)
pub fn normalize(input: ThesisInput) ThesisError!InvestorIntent {
    if (input.user_text_len == 0) return ThesisError.EmptyUserText;
    if (@as(usize, input.user_text_len) > max_user_text_len) return ThesisError.UserTextTooLong;
    if (input.target_notional_cents <= 0) return ThesisError.MissingTargetAmount;
    if (input.target_notional_cents < min_target_notional_cents) return ThesisError.TargetAmountTooSmall;

    // Allowed = user prefs, minus always-denied, minus explicit user exclusions.
    var allowed = input.asset_class_prefs;
    allowed.option = false;
    allowed.future = false;
    allowed.leveraged_etf = false;
    allowed.inverse_etf = false;
    allowed.crypto = false;
    if (input.exclusions.equity) allowed.equity = false;
    if (input.exclusions.etf) allowed.etf = false;
    if (input.exclusions.bond) allowed.bond = false;

    if (!allowed.hasSupportedClass()) return ThesisError.NoEligibleAssetClass;

    // Excluded = always-denied union explicit user exclusions.
    var excluded = denied_asset_classes;
    if (input.exclusions.equity) excluded.equity = true;
    if (input.exclusions.etf) excluded.etf = true;
    if (input.exclusions.bond) excluded.bond = true;

    return InvestorIntent{
        .theme = input.sector_theme,
        .target_amount_cents = input.target_notional_cents,
        .allowed_asset_classes = allowed,
        .excluded_asset_classes = excluded,
        .market = input.market_scope,
        .venues = .{ .nyse, .nasdaq },
        .venue_count = 2,
        .risk_preference = input.risk_preference,
        .max_single_name_pct = input.max_single_name_pct,
    };
}

// ---------------------------------------------------------------------------
// Demo fixtures (T2)
// ---------------------------------------------------------------------------

/// Fills a [max_user_text_len]u8 buffer with s, zero-padded.
fn textBuf(comptime s: []const u8) [max_user_text_len]u8 {
    if (s.len > max_user_text_len) @compileError("user text exceeds max_user_text_len");
    var buf = [_]u8{0} ** max_user_text_len;
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

/// Deterministic demo fixtures for the five canonical V1.1.S1 investment themes.
pub const fixtures = struct {
    const ai_text =
        "I want to invest USD 2,000 in AI infrastructure, " ++
        "but avoid single-name concentration and keep it to US-listed ETFs or large-cap equities.";
    pub const ai_infrastructure = ThesisInput{
        .user_text = textBuf(ai_text),
        .user_text_len = @intCast(ai_text.len),
        .target_notional_cents = 200_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = .{ .equity = true, .etf = true },
        .sector_theme = .ai_infrastructure,
        .risk_preference = .moderate,
        .max_single_name_pct = 30,
        .exclusions = .{ .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true },
    };

    const div_text =
        "I want USD 1,500 in US dividend-paying equities or dividend ETFs for steady income.";
    pub const us_dividends = ThesisInput{
        .user_text = textBuf(div_text),
        .user_text_len = @intCast(div_text.len),
        .target_notional_cents = 150_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = .{ .equity = true, .etf = true },
        .sector_theme = .dividends,
        .risk_preference = .low,
        .max_single_name_pct = 25,
        .exclusions = .{ .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true },
    };

    const cyber_text =
        "I want USD 3,000 in US-listed cybersecurity equities or ETFs.";
    pub const cyber_security = ThesisInput{
        .user_text = textBuf(cyber_text),
        .user_text_len = @intCast(cyber_text.len),
        .target_notional_cents = 300_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = .{ .equity = true, .etf = true },
        .sector_theme = .cyber_security,
        .risk_preference = .moderate,
        .max_single_name_pct = 35,
        .exclusions = .{ .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true },
    };

    const broad_text =
        "I want USD 5,000 in broad US market ETFs with low cost and wide diversification.";
    pub const broad_market = ThesisInput{
        .user_text = textBuf(broad_text),
        .user_text_len = @intCast(broad_text.len),
        .target_notional_cents = 500_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = .{ .etf = true },
        .sector_theme = .broad_market,
        .risk_preference = .moderate,
        .max_single_name_pct = 50,
        .exclusions = .{ .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true },
    };

    const cash_text =
        "I want USD 10,000 in cash-like US ETFs such as Treasury money market or short-duration bond ETFs.";
    pub const cash_preservation = ThesisInput{
        .user_text = textBuf(cash_text),
        .user_text_len = @intCast(cash_text.len),
        .target_notional_cents = 1_000_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = .{ .etf = true, .bond = true },
        .sector_theme = .cash_like,
        .risk_preference = .low,
        .max_single_name_pct = 50,
        .exclusions = .{ .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true },
    };
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "normalize: ai_infrastructure fixture produces valid intent" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expectEqual(SectorTheme.ai_infrastructure, intent.theme);
    try std.testing.expectEqual(@as(i64, 200_000), intent.target_amount_cents);
    try std.testing.expect(intent.allowed_asset_classes.equity);
    try std.testing.expect(intent.allowed_asset_classes.etf);
    try std.testing.expect(!intent.allowed_asset_classes.option);
    try std.testing.expect(!intent.allowed_asset_classes.crypto);
    try std.testing.expectEqual(@as(u8, 2), intent.venue_count);
    try std.testing.expectEqual(Venue.nyse, intent.venues[0]);
    try std.testing.expectEqual(Venue.nasdaq, intent.venues[1]);
    try std.testing.expectEqual(Market.us, intent.market);
    try std.testing.expectEqual(RiskPreference.moderate, intent.risk_preference);
    try std.testing.expectEqual(@as(u8, 30), intent.max_single_name_pct);
}

test "normalize: all five fixtures produce valid intent" {
    for ([_]ThesisInput{
        fixtures.ai_infrastructure,
        fixtures.us_dividends,
        fixtures.cyber_security,
        fixtures.broad_market,
        fixtures.cash_preservation,
    }) |f| {
        _ = try normalize(f);
    }
}

test "normalize: always-denied classes excluded from allowed_asset_classes" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expect(!intent.allowed_asset_classes.option);
    try std.testing.expect(!intent.allowed_asset_classes.future);
    try std.testing.expect(!intent.allowed_asset_classes.leveraged_etf);
    try std.testing.expect(!intent.allowed_asset_classes.inverse_etf);
    try std.testing.expect(!intent.allowed_asset_classes.crypto);
}

test "normalize: always-denied classes present in excluded_asset_classes" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expect(intent.excluded_asset_classes.option);
    try std.testing.expect(intent.excluded_asset_classes.future);
    try std.testing.expect(intent.excluded_asset_classes.leveraged_etf);
    try std.testing.expect(intent.excluded_asset_classes.inverse_etf);
    try std.testing.expect(intent.excluded_asset_classes.crypto);
}

test "normalize: denied classes removed from allowed even when user requests them" {
    var input = fixtures.ai_infrastructure;
    input.asset_class_prefs = .{ .equity = true, .etf = true, .option = true, .future = true, .crypto = true };
    const intent = try normalize(input);
    try std.testing.expect(intent.allowed_asset_classes.equity);
    try std.testing.expect(intent.allowed_asset_classes.etf);
    try std.testing.expect(!intent.allowed_asset_classes.option);
    try std.testing.expect(!intent.allowed_asset_classes.future);
    try std.testing.expect(!intent.allowed_asset_classes.crypto);
}

test "normalize: empty user text returns EmptyUserText" {
    var input = fixtures.ai_infrastructure;
    input.user_text_len = 0;
    try std.testing.expectError(ThesisError.EmptyUserText, normalize(input));
}

test "normalize: user_text_len exceeding max returns UserTextTooLong" {
    var input = fixtures.ai_infrastructure;
    input.user_text_len = @intCast(max_user_text_len + 1);
    try std.testing.expectError(ThesisError.UserTextTooLong, normalize(input));
}

test "normalize: zero target notional returns MissingTargetAmount" {
    var input = fixtures.ai_infrastructure;
    input.target_notional_cents = 0;
    try std.testing.expectError(ThesisError.MissingTargetAmount, normalize(input));
}

test "normalize: negative target notional returns MissingTargetAmount" {
    var input = fixtures.ai_infrastructure;
    input.target_notional_cents = -1;
    try std.testing.expectError(ThesisError.MissingTargetAmount, normalize(input));
}

test "normalize: notional below minimum returns TargetAmountTooSmall" {
    var input = fixtures.ai_infrastructure;
    input.target_notional_cents = 50; // USD 0.50 < USD 1.00 minimum
    try std.testing.expectError(ThesisError.TargetAmountTooSmall, normalize(input));
}

test "normalize: options-only preference returns NoEligibleAssetClass" {
    var input = fixtures.ai_infrastructure;
    input.asset_class_prefs = .{ .option = true };
    try std.testing.expectError(ThesisError.NoEligibleAssetClass, normalize(input));
}

test "normalize: user excludes both equity and etf returns NoEligibleAssetClass" {
    var input = fixtures.ai_infrastructure;
    input.exclusions = .{ .equity = true, .etf = true, .option = true, .future = true, .leveraged_etf = true, .inverse_etf = true, .crypto = true };
    try std.testing.expectError(ThesisError.NoEligibleAssetClass, normalize(input));
}

test "normalize: cash_preservation ETF+bond fixture normalizes with etf allowed" {
    const intent = try normalize(fixtures.cash_preservation);
    try std.testing.expect(intent.allowed_asset_classes.etf);
    try std.testing.expectEqual(SectorTheme.cash_like, intent.theme);
    try std.testing.expectEqual(RiskPreference.low, intent.risk_preference);
}

test "AssetClassSet: has() returns correct membership" {
    const s = AssetClassSet{ .equity = true, .etf = true };
    try std.testing.expect(s.has(.equity));
    try std.testing.expect(s.has(.etf));
    try std.testing.expect(!s.has(.option));
    try std.testing.expect(!s.has(.crypto));
}

test "AssetClassSet: hasSupportedClass returns false for denied-only set" {
    try std.testing.expect(!denied_asset_classes.hasSupportedClass());
}

test "fixtures: text() length matches user_text_len" {
    for ([_]ThesisInput{
        fixtures.ai_infrastructure,
        fixtures.us_dividends,
        fixtures.cyber_security,
        fixtures.broad_market,
        fixtures.cash_preservation,
    }) |f| {
        try std.testing.expectEqual(@as(usize, f.user_text_len), f.text().len);
    }
}
