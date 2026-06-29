/// Thesis input schema and investor intent normalization
///
/// ThesisInput: raw investor request captured from the user or a test fixture.
/// InvestorIntent: validated, structured form produced by normalize().
/// fixtures: deterministic test inputs for the five canonical themes.
///
/// All validation in normalize() is fail-closed: missing or out-of-range
/// fields return an explicit ThesisError instead of silently substituting
/// defaults.
///
/// Canonical encoding: binary protobuf. Wire format is defined in
/// src/tickoni/schema/thesis.proto; breaking changes are enforced by buf
/// in CI (quality-check-proto / proto_check.yml).
const std = @import("std");
const cls = @import("classification.zig");
const thesis_cabi = @import("thesis_cabi");

pub const classification = cls;
pub const Market = cls.Market;
pub const Venue = cls.Venue;
pub const AssetClass = cls.AssetClass;
pub const AssetClassList = cls.AssetClassList;
pub const InstrumentType = cls.InstrumentType;
pub const InstrumentTypeList = cls.InstrumentTypeList;
pub const RiskPreference = cls.RiskPreference;
pub const CanonicalId = cls.CanonicalId;
pub const ClassificationRef = cls.ClassificationRef;
pub const ClassificationRefList = cls.ClassificationRefList;
pub const ThemeIdList = cls.ThemeIdList;
pub const canonicalId = cls.canonicalId;
pub const classificationRef = cls.classificationRef;
pub const assetClassList = cls.assetClassList;
pub const instrumentTypeList = cls.instrumentTypeList;
pub const themeIdList = cls.themeIdList;
pub const classificationRefList = cls.classificationRefList;
pub const validateCanonicalId = cls.validateCanonicalId;

/// Schema version. Must match TK_THESIS_SCHEMA_VERSION in thesis_codec.h.
/// Incrementing this value changes the hash key and invalidates existing hashes.
pub const thesis_schema_version: u16 = 2;

/// Maximum bytes stored in the user_text field.
pub const max_user_text_len: usize = 512;

/// Byte width of each ticker slot in requested_tickers.
/// Must match TK_THESIS_MAX_TICKER_LEN in thesis_codec.h and max_ticker_len in catalog.zig.
pub const max_ticker_len: usize = 8;

/// Maximum number of explicitly requested tickers in one ThesisInput.
/// Must match TK_THESIS_MAX_REQUESTED_TICKERS in thesis_codec.h.
pub const max_requested_tickers: usize = 8;

/// Minimum allowed target notional: USD 1.00 = 100 cents.
pub const min_target_notional_cents: i64 = 100;
/// Maximum allowed target notional: USD 10 billion = 1_000_000_000_000 cents.
/// Prevents i64 overflow in downstream multiplication: notional * 10_000 (bp_denom) must fit i64.
pub const max_target_notional_cents: i64 = 1_000_000_000_000;

/// Raw investor thesis as received from the user or provided by a test fixture.
///
/// user_text is the plain-English investment intent; user_text_len is its byte
/// count. Call normalize() to validate and convert to InvestorIntent.
/// Call computeThesisInputHash() to obtain a stable content hash for dedup
/// and audit reference.
pub const ThesisInput = struct {
    user_text: [max_user_text_len]u8,
    user_text_len: u16,
    target_notional_cents: i64,
    account_id: u32,
    market_scope: Market,
    /// Economic exposures the user wants to include.
    asset_class_prefs: AssetClassList,
    /// Traded product types the user wants to include.
    instrument_type_prefs: InstrumentTypeList,
    /// Canonical investment theme identifier used by the current V1.1 fixtures.
    theme: CanonicalId,
    risk_preference: RiskPreference,
    /// Maximum single-name allocation as a percentage of total basket notional (1-100).
    max_single_name_pct: u8,
    /// Explicit user exclusions; always merged with denied_* policy lists in normalize().
    asset_class_exclusions: AssetClassList,
    instrument_type_exclusions: InstrumentTypeList,
    /// Tickers the user explicitly named in their request (e.g. "Buy SOXL").
    /// Each slot is zero-padded to max_ticker_len bytes.
    /// normalize() passes these through to InvestorIntent unchanged; basket.build()
    /// checks them against the catalog restricted list before theme-based scope checks.
    requested_tickers: [max_requested_tickers][max_ticker_len]u8 = std.mem.zeroes([max_requested_tickers][max_ticker_len]u8),
    requested_ticker_count: u8 = 0,

    pub fn text(self: *const ThesisInput) []const u8 {
        return self.user_text[0..self.user_text_len];
    }
};

/// Structured investor intent produced by normalize().
///
/// allowed_* lists are the user's preferences minus always-denied values and
/// explicit exclusions. excluded_* lists are the union of always-denied values
/// and the user's explicit exclusions, so downstream catalog and basket code
/// can trust them.
pub const InvestorIntent = struct {
    account_id: u32,
    theme: CanonicalId,
    target_amount_cents: i64,
    allowed_asset_classes: AssetClassList,
    excluded_asset_classes: AssetClassList,
    allowed_instrument_types: InstrumentTypeList,
    excluded_instrument_types: InstrumentTypeList,
    market: Market,
    venues: [2]Venue,
    venue_count: u8,
    risk_preference: RiskPreference,
    /// Maximum single-name allocation as a percentage of the basket notional.
    max_single_name_pct: u8,
    /// Explicitly requested tickers forwarded from ThesisInput unchanged.
    requested_tickers: [max_requested_tickers][max_ticker_len]u8,
    requested_ticker_count: u8,
};

/// Asset classes always denied in V1.1 regardless of user preference.
/// Commodity, FX, and crypto are outside the initial mandate.
pub const denied_asset_classes = cls.assetClassList(.{
    .commodity,
    .fx,
    .crypto,
});

/// Instrument types always denied in V1.1 regardless of user preference.
/// Bonds, options, futures, funds, and tokens are represented in the shared
/// contract but remain outside the initial thesis mandate.
pub const denied_instrument_types = cls.instrumentTypeList(.{
    .bond,
    .option,
    .future,
    .fund,
    .token,
});

pub const ThesisError = error{
    EmptyUserText,
    UserTextTooLong,
    MissingTargetAmount,
    TargetAmountTooSmall,
    TargetAmountTooLarge,
    NoEligibleAssetClass,
    NoEligibleInstrumentType,
    MalformedClassification,
};

/// Stable error codes for ThesisDenialPayload, matching ThesisError variants.
pub const ThesisErrorCode = enum(u8) {
    empty_user_text = 0,
    user_text_too_long = 1,
    missing_target_amount = 2,
    target_amount_too_small = 3,
    target_amount_too_large = 4,
    no_eligible_asset_class = 5,
    no_eligible_instrument_type = 6,
    malformed_classification = 7,
};

/// Audit record payload for a successful thesis input normalization.
/// Emitted by the thesis normalization tile when normalize() succeeds.
/// thesis_input_hash is the computeThesisInputHash() result for this input.
pub const ThesisNormalizationPayload = struct {
    thesis_input_hash: u64,
    account_id: u32,
    theme: CanonicalId,
    target_amount_cents: i64,
};

/// Audit record payload for a thesis input denial.
/// Emitted by the thesis normalization tile when normalize() fails.
/// thesis_input_hash is 0 when user_text_len is unsafe to hash (UserTextTooLong).
pub const ThesisDenialPayload = struct {
    thesis_input_hash: u64,
    account_id: u32,
    error_code: ThesisErrorCode,
};

/// Validate a ThesisInput and return a structured InvestorIntent.
pub fn normalize(input: ThesisInput) ThesisError!InvestorIntent {
    if (input.user_text_len == 0) return ThesisError.EmptyUserText;
    if (@as(usize, input.user_text_len) > max_user_text_len) return ThesisError.UserTextTooLong;
    if (input.target_notional_cents <= 0) return ThesisError.MissingTargetAmount;
    if (input.target_notional_cents < min_target_notional_cents) return ThesisError.TargetAmountTooSmall;
    if (input.target_notional_cents > max_target_notional_cents) return ThesisError.TargetAmountTooLarge;

    validateInputClassifications(input) catch return ThesisError.MalformedClassification;

    const allowed_asset_classes = buildAllowedAssetClasses(input) catch return ThesisError.MalformedClassification;
    if (allowed_asset_classes.count == 0) return ThesisError.NoEligibleAssetClass;

    const allowed_instrument_types = buildAllowedInstrumentTypes(input) catch return ThesisError.MalformedClassification;
    if (allowed_instrument_types.count == 0) return ThesisError.NoEligibleInstrumentType;

    const excluded_asset_classes = buildExcludedAssetClasses(input) catch return ThesisError.MalformedClassification;
    const excluded_instrument_types = buildExcludedInstrumentTypes(input) catch return ThesisError.MalformedClassification;

    return InvestorIntent{
        .account_id = input.account_id,
        .theme = input.theme,
        .target_amount_cents = input.target_notional_cents,
        .allowed_asset_classes = allowed_asset_classes,
        .excluded_asset_classes = excluded_asset_classes,
        .allowed_instrument_types = allowed_instrument_types,
        .excluded_instrument_types = excluded_instrument_types,
        .market = input.market_scope,
        .venues = .{ .nyse, .nasdaq },
        .venue_count = 2,
        .risk_preference = input.risk_preference,
        .max_single_name_pct = input.max_single_name_pct,
        .requested_tickers = input.requested_tickers,
        .requested_ticker_count = input.requested_ticker_count,
    };
}

/// Compute a stable content hash over a ThesisInput via fd_siphash13.
///
/// Uses tk_thesis_input_hash() from src/tickoni/codec/thesis_hash.c.
///
/// Returns 0 when user_text_len > max_user_text_len to fail closed without
/// reading out of bounds. Callers building ThesisDenialPayload should record
/// 0 in that case and set error_code to user_text_too_long.
pub fn computeThesisInputHash(input: ThesisInput) u64 {
    if (@as(usize, input.user_text_len) > max_user_text_len) return 0;
    const tickers_flat: [*]const u8 = @ptrCast(&input.requested_tickers);
    const asset_class_prefs: [*]const u8 = @ptrCast(&input.asset_class_prefs.values);
    const instrument_type_prefs: [*]const u8 = @ptrCast(&input.instrument_type_prefs.values);
    const asset_class_exclusions: [*]const u8 = @ptrCast(&input.asset_class_exclusions.values);
    const instrument_type_exclusions: [*]const u8 = @ptrCast(&input.instrument_type_exclusions.values);
    return thesis_cabi.tk_thesis_input_hash(
        input.user_text_len,
        &input.user_text,
        input.target_notional_cents,
        input.account_id,
        @intFromEnum(input.market_scope),
        input.asset_class_prefs.count,
        asset_class_prefs,
        input.instrument_type_prefs.count,
        instrument_type_prefs,
        input.theme.len,
        &input.theme.bytes,
        @intFromEnum(input.risk_preference),
        input.max_single_name_pct,
        input.asset_class_exclusions.count,
        asset_class_exclusions,
        input.instrument_type_exclusions.count,
        instrument_type_exclusions,
        input.requested_ticker_count,
        tickers_flat,
    );
}

fn validateInputClassifications(input: ThesisInput) !void {
    try input.asset_class_prefs.validate();
    try input.instrument_type_prefs.validate();
    try input.asset_class_exclusions.validate();
    try input.instrument_type_exclusions.validate();
    try cls.validateCanonicalId(input.theme.slice());
}

fn buildAllowedAssetClasses(input: ThesisInput) !AssetClassList {
    var allowed = AssetClassList{};
    for (input.asset_class_prefs.values[0..input.asset_class_prefs.count]) |asset_class| {
        if (denied_asset_classes.has(asset_class)) continue;
        if (input.asset_class_exclusions.has(asset_class)) continue;
        try allowed.append(asset_class);
    }
    return allowed;
}

fn buildExcludedAssetClasses(input: ThesisInput) !AssetClassList {
    var excluded = AssetClassList{};
    for (denied_asset_classes.values[0..denied_asset_classes.count]) |asset_class| {
        try excluded.append(asset_class);
    }
    for (input.asset_class_exclusions.values[0..input.asset_class_exclusions.count]) |asset_class| {
        if (!excluded.has(asset_class)) try excluded.append(asset_class);
    }
    return excluded;
}

fn buildAllowedInstrumentTypes(input: ThesisInput) !InstrumentTypeList {
    var allowed = InstrumentTypeList{};
    for (input.instrument_type_prefs.values[0..input.instrument_type_prefs.count]) |instrument_type| {
        if (denied_instrument_types.has(instrument_type)) continue;
        if (input.instrument_type_exclusions.has(instrument_type)) continue;
        try allowed.append(instrument_type);
    }
    return allowed;
}

fn buildExcludedInstrumentTypes(input: ThesisInput) !InstrumentTypeList {
    var excluded = InstrumentTypeList{};
    for (denied_instrument_types.values[0..denied_instrument_types.count]) |instrument_type| {
        try excluded.append(instrument_type);
    }
    for (input.instrument_type_exclusions.values[0..input.instrument_type_exclusions.count]) |instrument_type| {
        if (!excluded.has(instrument_type)) try excluded.append(instrument_type);
    }
    return excluded;
}

fn textBuf(comptime s: []const u8) [max_user_text_len]u8 {
    if (s.len > max_user_text_len) @compileError("user text exceeds max_user_text_len");
    var buf = [_]u8{0} ** max_user_text_len;
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

/// Deterministic test fixtures for the five canonical investment themes.
pub const fixtures = struct {
    const default_asset_classes = cls.assetClassList(.{.equity});
    const default_instrument_types = cls.instrumentTypeList(.{ .stock, .etf });
    const default_asset_exclusions = cls.assetClassList(.{ .commodity, .fx, .crypto });
    const default_instrument_exclusions = cls.instrumentTypeList(.{ .bond, .option, .future, .fund, .token });

    const ai_text =
        "I want to invest USD 2,000 in AI infrastructure, " ++
        "but avoid single-name concentration and keep it to US-listed ETFs or large-cap equities.";
    pub const ai_infrastructure = ThesisInput{
        .user_text = textBuf(ai_text),
        .user_text_len = @intCast(ai_text.len),
        .target_notional_cents = 200_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = default_instrument_types,
        .theme = CanonicalId.init("ai_infrastructure") catch unreachable,
        .risk_preference = .moderate,
        .max_single_name_pct = 30,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    const div_text =
        "I want USD 1,500 in US dividend-paying equities or dividend ETFs for steady income.";
    pub const us_dividends = ThesisInput{
        .user_text = textBuf(div_text),
        .user_text_len = @intCast(div_text.len),
        .target_notional_cents = 150_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = default_instrument_types,
        .theme = CanonicalId.init("dividends") catch unreachable,
        .risk_preference = .low,
        .max_single_name_pct = 60,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    const cyber_text =
        "I want USD 3,000 in US-listed cybersecurity equities or ETFs.";
    pub const cyber_security = ThesisInput{
        .user_text = textBuf(cyber_text),
        .user_text_len = @intCast(cyber_text.len),
        .target_notional_cents = 300_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = default_instrument_types,
        .theme = CanonicalId.init("cyber_security") catch unreachable,
        .risk_preference = .moderate,
        .max_single_name_pct = 35,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    const broad_text =
        "I want USD 5,000 in broad US market ETFs with low cost and wide diversification.";
    pub const broad_market = ThesisInput{
        .user_text = textBuf(broad_text),
        .user_text_len = @intCast(broad_text.len),
        .target_notional_cents = 500_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = cls.instrumentTypeList(.{.etf}),
        .theme = CanonicalId.init("broad_market") catch unreachable,
        .risk_preference = .moderate,
        .max_single_name_pct = 50,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    const cash_text =
        "I want USD 10,000 in cash-like US ETFs such as Treasury money market or short-duration bond ETFs.";
    pub const cash_preservation = ThesisInput{
        .user_text = textBuf(cash_text),
        .user_text_len = @intCast(cash_text.len),
        .target_notional_cents = 1_000_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = cls.assetClassList(.{ .cash, .fixed_income }),
        .instrument_type_prefs = cls.instrumentTypeList(.{.etf}),
        .theme = CanonicalId.init("cash_like") catch unreachable,
        .risk_preference = .low,
        .max_single_name_pct = 50,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };
};

test "schema version matches codec constant" {
    try std.testing.expectEqual(@as(u16, 2), thesis_schema_version);
}

test "normalize: ai_infrastructure fixture produces valid intent" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expectEqual(@as(u32, 1001), intent.account_id);
    try std.testing.expectEqualStrings("ai_infrastructure", intent.theme.slice());
    try std.testing.expectEqual(@as(i64, 200_000), intent.target_amount_cents);
    try std.testing.expect(intent.allowed_asset_classes.has(.equity));
    try std.testing.expect(intent.allowed_instrument_types.has(.stock));
    try std.testing.expect(intent.allowed_instrument_types.has(.etf));
    try std.testing.expect(!intent.allowed_instrument_types.has(.option));
    try std.testing.expectEqual(@as(u8, 2), intent.venue_count);
    try std.testing.expectEqual(Venue.nyse, intent.venues[0]);
    try std.testing.expectEqual(Venue.nasdaq, intent.venues[1]);
    try std.testing.expectEqual(Market.us, intent.market);
    try std.testing.expectEqual(RiskPreference.moderate, intent.risk_preference);
    try std.testing.expectEqual(@as(u8, 30), intent.max_single_name_pct);
}

test "normalize: account_id is preserved in InvestorIntent" {
    var input = fixtures.ai_infrastructure;
    input.account_id = 42;
    const intent = try normalize(input);
    try std.testing.expectEqual(@as(u32, 42), intent.account_id);
}

test "normalize: all five fixtures produce valid intent" {
    for ([_]ThesisInput{
        fixtures.ai_infrastructure,
        fixtures.us_dividends,
        fixtures.cyber_security,
        fixtures.broad_market,
        fixtures.cash_preservation,
    }) |fixture| {
        _ = try normalize(fixture);
    }
}

test "normalize: always-denied classes excluded from allowed_asset_classes" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expect(!intent.allowed_asset_classes.has(.commodity));
    try std.testing.expect(!intent.allowed_asset_classes.has(.fx));
    try std.testing.expect(!intent.allowed_asset_classes.has(.crypto));
}

test "normalize: always-denied instrument types excluded from allowed_instrument_types" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expect(!intent.allowed_instrument_types.has(.bond));
    try std.testing.expect(!intent.allowed_instrument_types.has(.option));
    try std.testing.expect(!intent.allowed_instrument_types.has(.future));
    try std.testing.expect(!intent.allowed_instrument_types.has(.fund));
    try std.testing.expect(!intent.allowed_instrument_types.has(.token));
}

test "normalize: always-denied lists present in excluded lists" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expect(intent.excluded_asset_classes.has(.commodity));
    try std.testing.expect(intent.excluded_asset_classes.has(.fx));
    try std.testing.expect(intent.excluded_asset_classes.has(.crypto));
    try std.testing.expect(intent.excluded_instrument_types.has(.bond));
    try std.testing.expect(intent.excluded_instrument_types.has(.option));
    try std.testing.expect(intent.excluded_instrument_types.has(.future));
    try std.testing.expect(intent.excluded_instrument_types.has(.fund));
    try std.testing.expect(intent.excluded_instrument_types.has(.token));
}

test "normalize: denied values removed from allowed lists even when user requests them" {
    var input = fixtures.ai_infrastructure;
    input.asset_class_prefs = cls.assetClassList(.{ .equity, .commodity, .crypto });
    input.instrument_type_prefs = cls.instrumentTypeList(.{ .stock, .etf, .option, .future });
    const intent = try normalize(input);
    try std.testing.expect(intent.allowed_asset_classes.has(.equity));
    try std.testing.expect(!intent.allowed_asset_classes.has(.commodity));
    try std.testing.expect(!intent.allowed_asset_classes.has(.crypto));
    try std.testing.expect(intent.allowed_instrument_types.has(.stock));
    try std.testing.expect(intent.allowed_instrument_types.has(.etf));
    try std.testing.expect(!intent.allowed_instrument_types.has(.option));
    try std.testing.expect(!intent.allowed_instrument_types.has(.future));
}

test "normalize: explicit exclusions remove otherwise-allowed values and remain in excluded lists" {
    var input = fixtures.cash_preservation;
    input.asset_class_exclusions = cls.assetClassList(.{ .commodity, .fx, .crypto, .fixed_income });
    const intent = try normalize(input);
    try std.testing.expect(intent.allowed_asset_classes.has(.cash));
    try std.testing.expect(!intent.allowed_asset_classes.has(.fixed_income));
    try std.testing.expect(intent.excluded_asset_classes.has(.fixed_income));

    var ai_input = fixtures.ai_infrastructure;
    ai_input.instrument_type_exclusions = cls.instrumentTypeList(.{ .bond, .option, .future, .fund, .token, .stock });
    const ai_intent = try normalize(ai_input);
    try std.testing.expect(ai_intent.allowed_instrument_types.has(.etf));
    try std.testing.expect(!ai_intent.allowed_instrument_types.has(.stock));
    try std.testing.expect(ai_intent.excluded_instrument_types.has(.stock));
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
    input.target_notional_cents = 50;
    try std.testing.expectError(ThesisError.TargetAmountTooSmall, normalize(input));
}

test "normalize: notional above maximum returns TargetAmountTooLarge" {
    var input = fixtures.ai_infrastructure;
    input.target_notional_cents = max_target_notional_cents + 1;
    try std.testing.expectError(ThesisError.TargetAmountTooLarge, normalize(input));
}

test "normalize: denied-only asset classes return NoEligibleAssetClass" {
    var input = fixtures.ai_infrastructure;
    input.asset_class_prefs = cls.assetClassList(.{ .commodity, .crypto });
    try std.testing.expectError(ThesisError.NoEligibleAssetClass, normalize(input));
}

test "normalize: denied-only instrument types return NoEligibleInstrumentType" {
    var input = fixtures.ai_infrastructure;
    input.instrument_type_prefs = cls.instrumentTypeList(.{ .option, .future });
    try std.testing.expectError(ThesisError.NoEligibleInstrumentType, normalize(input));
}

test "normalize: duplicate classifications fail closed" {
    var input = fixtures.ai_infrastructure;
    input.asset_class_prefs.count = 2;
    input.asset_class_prefs.values[0] = .equity;
    input.asset_class_prefs.values[1] = .equity;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: malformed theme id fails closed" {
    var input = fixtures.ai_infrastructure;
    input.theme.bytes[0] = 'A';
    input.theme.bytes[1] = 'I';
    input.theme.len = 2;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: cash_preservation fixture keeps fixed income and cash exposure" {
    const intent = try normalize(fixtures.cash_preservation);
    try std.testing.expect(intent.allowed_asset_classes.has(.cash));
    try std.testing.expect(intent.allowed_asset_classes.has(.fixed_income));
    try std.testing.expect(intent.allowed_instrument_types.has(.etf));
    try std.testing.expectEqualStrings("cash_like", intent.theme.slice());
    try std.testing.expectEqual(RiskPreference.low, intent.risk_preference);
}

test "fixtures: text() length matches user_text_len" {
    for ([_]ThesisInput{
        fixtures.ai_infrastructure,
        fixtures.us_dividends,
        fixtures.cyber_security,
        fixtures.broad_market,
        fixtures.cash_preservation,
    }) |fixture| {
        try std.testing.expectEqual(@as(usize, fixture.user_text_len), fixture.text().len);
    }
}

test "computeThesisInputHash: same input produces same hash" {
    const h1 = computeThesisInputHash(fixtures.ai_infrastructure);
    const h2 = computeThesisInputHash(fixtures.ai_infrastructure);
    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != 0);
}

test "computeThesisInputHash: different account_id produces different hash" {
    var other = fixtures.ai_infrastructure;
    other.account_id = 9999;
    try std.testing.expect(
        computeThesisInputHash(fixtures.ai_infrastructure) != computeThesisInputHash(other),
    );
}

test "computeThesisInputHash: classification changes produce different hashes" {
    var other_theme = fixtures.ai_infrastructure;
    other_theme.theme = CanonicalId.init("cloud") catch unreachable;
    try std.testing.expect(
        computeThesisInputHash(fixtures.ai_infrastructure) != computeThesisInputHash(other_theme),
    );

    var other_type = fixtures.ai_infrastructure;
    other_type.instrument_type_prefs = cls.instrumentTypeList(.{.stock});
    try std.testing.expect(
        computeThesisInputHash(fixtures.ai_infrastructure) != computeThesisInputHash(other_type),
    );
}

test "computeThesisInputHash: all five fixtures produce distinct hashes" {
    const all = [_]ThesisInput{
        fixtures.ai_infrastructure,
        fixtures.us_dividends,
        fixtures.cyber_security,
        fixtures.broad_market,
        fixtures.cash_preservation,
    };
    for (all, 0..) |a, i| {
        for (all, 0..) |b, j| {
            if (i != j) {
                try std.testing.expect(computeThesisInputHash(a) != computeThesisInputHash(b));
            }
        }
    }
}

test "computeThesisInputHash: unsafe user_text_len returns 0" {
    var input = fixtures.ai_infrastructure;
    input.user_text_len = @intCast(max_user_text_len + 1);
    try std.testing.expectEqual(@as(u64, 0), computeThesisInputHash(input));
}
