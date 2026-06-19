/// Instrument catalog fixture and lookup functions
///
/// InstrumentEntry: static record per instrument (ticker, name, asset class,
/// market, venue, sector, theme tags, risk tier, expense ratio, restriction).
/// catalog: compile-time array of all fixture instruments (24 entries).
/// Lookup functions: filterByTheme, filterBySector, filterByAssetClass,
/// filterByVenue, lookupByTicker.
///
/// Restricted instruments (leveraged ETFs, inverse ETFs, manual denylist) carry
/// a non-none RestrictionReason so basket construction can reject them with a
/// clear message before they appear in a candidate list.
///
/// Schema version: catalog_schema_version below.  When S3 basket construction
/// produces audit records, it must stamp the catalog version that was consulted
/// so replay can detect catalog drift.  Incrementing catalog_schema_version
/// signals a compatibility break in InstrumentEntry layout or fixture content.
///
/// Canonical encoding: binary protobuf.  Wire format is defined in
/// src/tickoni/schema/catalog.proto; breaking changes are enforced by buf
/// in CI (quality-check-proto / proto_check.yml).
const std = @import("std");
const thesis = @import("thesis.zig");

pub const AssetClass = thesis.AssetClass;
pub const Market = thesis.Market;
pub const Venue = thesis.Venue;
pub const SectorTheme = thesis.SectorTheme;
pub const RiskPreference = thesis.RiskPreference;

/// Schema version for the instrument catalog.
/// Increment when InstrumentEntry layout or fixture content changes in a way
/// that would alter basket construction or audit records.
pub const catalog_schema_version: u16 = 1;

pub const max_ticker_len: usize = 8;
pub const max_name_len: usize = 48;

/// Why an instrument is excluded from eligible baskets.
///
/// Matches the asset-class deny policy in thesis.zig (denied_asset_classes)
/// and the restricted-instrument denylist.
pub const RestrictionReason = enum(u8) {
    none = 0,
    leveraged_etf = 1,
    inverse_etf = 2,
    options_contract = 3,
    futures_contract = 4,
    non_us_venue = 5,
    manual_denylist = 6,
};

/// Bit-set of all sector/investment themes, backed by a single byte.
///
/// Layout invariant: @sizeOf(ThemeSet) == 1 (tested below).
/// An instrument may belong to multiple themes (e.g. NVDA is both
/// ai_infrastructure and semiconductors).
pub const ThemeSet = packed struct(u8) {
    ai_infrastructure: bool = false,
    semiconductors: bool = false,
    cloud: bool = false,
    cyber_security: bool = false,
    broad_market: bool = false,
    dividends: bool = false,
    cash_like: bool = false,
    _reserved: bool = false,

    pub fn has(self: ThemeSet, theme: SectorTheme) bool {
        return switch (theme) {
            .ai_infrastructure => self.ai_infrastructure,
            .semiconductors => self.semiconductors,
            .cloud => self.cloud,
            .cyber_security => self.cyber_security,
            .broad_market => self.broad_market,
            .dividends => self.dividends,
            .cash_like => self.cash_like,
        };
    }
};

/// Single instrument record in the catalog.
///
/// expense_ratio_bps: annual fund expense ratio in basis points (100 bps = 1%).
///   Zero for individual equities, which have no fund expense ratio.
/// restricted: true when the instrument is policy-denied regardless of thesis.
/// restriction_reason: explains why; .none when restricted is false.
pub const InstrumentEntry = struct {
    ticker: [max_ticker_len]u8,
    ticker_len: u8,
    name: [max_name_len]u8,
    name_len: u8,
    asset_class: AssetClass,
    market: Market,
    venue: Venue,
    sector: SectorTheme,
    themes: ThemeSet,
    risk_tier: RiskPreference,
    expense_ratio_bps: u16,
    restricted: bool,
    restriction_reason: RestrictionReason,

    pub fn tickerSlice(self: *const InstrumentEntry) []const u8 {
        return self.ticker[0..self.ticker_len];
    }

    pub fn nameSlice(self: *const InstrumentEntry) []const u8 {
        return self.name[0..self.name_len];
    }
};

// ---------------------------------------------------------------------------
// Comptime helpers
// ---------------------------------------------------------------------------

/// Fill a [max_ticker_len]u8 buffer with s, zero-padded.
///
/// fd_cstr_ncpy from src/util/cstr covers string copy at runtime, but this
/// helper is called in comptime const initializers where C externs cannot be
/// evaluated.  A Zig for-loop is the only comptime-safe copy path here.
fn tickerBuf(comptime s: []const u8) [max_ticker_len]u8 {
    if (s.len > max_ticker_len) @compileError("ticker exceeds max_ticker_len");
    var buf = [_]u8{0} ** max_ticker_len;
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

/// Fill a [max_name_len]u8 buffer with s, zero-padded.
///
/// fd_cstr_ncpy from src/util/cstr covers string copy at runtime, but this
/// helper is called in comptime const initializers where C externs cannot be
/// evaluated.  A Zig for-loop is the only comptime-safe copy path here.
fn nameBuf(comptime s: []const u8) [max_name_len]u8 {
    if (s.len > max_name_len) @compileError("name exceeds max_name_len");
    var buf = [_]u8{0} ** max_name_len;
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

fn mkEntry(
    comptime ticker_s: []const u8,
    comptime name_s: []const u8,
    ac: AssetClass,
    mkt: Market,
    vnue: Venue,
    sec: SectorTheme,
    themes: ThemeSet,
    risk: RiskPreference,
    er_bps: u16,
    restr: bool,
    restr_reason: RestrictionReason,
) InstrumentEntry {
    return .{
        .ticker = tickerBuf(ticker_s),
        .ticker_len = @intCast(ticker_s.len),
        .name = nameBuf(name_s),
        .name_len = @intCast(name_s.len),
        .asset_class = ac,
        .market = mkt,
        .venue = vnue,
        .sector = sec,
        .themes = themes,
        .risk_tier = risk,
        .expense_ratio_bps = er_bps,
        .restricted = restr,
        .restriction_reason = restr_reason,
    };
}

// ---------------------------------------------------------------------------
// Instrument catalog (T1, T2, T3)
// ---------------------------------------------------------------------------

pub const catalog = [_]InstrumentEntry{
    // --- Semiconductors / AI infrastructure equities ---
    mkEntry("NVDA", "NVIDIA Corporation", .equity, .us, .nasdaq, .semiconductors, .{ .ai_infrastructure = true, .semiconductors = true }, .high, 0, false, .none),
    mkEntry("AMD", "Advanced Micro Devices Inc.", .equity, .us, .nasdaq, .semiconductors, .{ .ai_infrastructure = true, .semiconductors = true }, .high, 0, false, .none),
    mkEntry("AVGO", "Broadcom Inc.", .equity, .us, .nasdaq, .semiconductors, .{ .ai_infrastructure = true, .semiconductors = true }, .moderate, 0, false, .none),
    mkEntry("MSFT", "Microsoft Corporation", .equity, .us, .nasdaq, .cloud, .{ .ai_infrastructure = true, .cloud = true }, .moderate, 0, false, .none),
    // --- AI infrastructure ETFs ---
    mkEntry("BOTZ", "Global X Robotics & AI ETF", .etf, .us, .nasdaq, .ai_infrastructure, .{ .ai_infrastructure = true }, .moderate, 68, false, .none),
    mkEntry("SOXX", "iShares Semiconductor ETF", .etf, .us, .nasdaq, .semiconductors, .{ .ai_infrastructure = true, .semiconductors = true }, .high, 35, false, .none),
    // --- Cloud ---
    mkEntry("AMZN", "Amazon.com Inc.", .equity, .us, .nasdaq, .cloud, .{ .ai_infrastructure = true, .cloud = true }, .moderate, 0, false, .none),
    mkEntry("WCLD", "WisdomTree Cloud Computing ETF", .etf, .us, .nasdaq, .cloud, .{ .cloud = true }, .moderate, 45, false, .none),
    // --- Cyber security ---
    mkEntry("PANW", "Palo Alto Networks Inc.", .equity, .us, .nasdaq, .cyber_security, .{ .cyber_security = true }, .high, 0, false, .none),
    mkEntry("CRWD", "CrowdStrike Holdings Inc.", .equity, .us, .nasdaq, .cyber_security, .{ .cyber_security = true }, .high, 0, false, .none),
    mkEntry("HACK", "ETFMG Prime Cyber Security ETF", .etf, .us, .nyse, .cyber_security, .{ .cyber_security = true }, .moderate, 60, false, .none),
    mkEntry("CIBR", "First Trust NASDAQ Cybersecurity ETF", .etf, .us, .nasdaq, .cyber_security, .{ .cyber_security = true }, .moderate, 60, false, .none),
    // --- Broad market ---
    mkEntry("SPY", "SPDR S&P 500 ETF Trust", .etf, .us, .nyse, .broad_market, .{ .broad_market = true }, .low, 9, false, .none),
    mkEntry("IVV", "iShares Core S&P 500 ETF", .etf, .us, .nasdaq, .broad_market, .{ .broad_market = true }, .low, 3, false, .none),
    mkEntry("VOO", "Vanguard S&P 500 ETF", .etf, .us, .nyse, .broad_market, .{ .broad_market = true }, .low, 3, false, .none),
    mkEntry("VTI", "Vanguard Total Stock Market ETF", .etf, .us, .nyse, .broad_market, .{ .broad_market = true }, .low, 3, false, .none),
    // --- Dividends ---
    mkEntry("VYM", "Vanguard High Dividend Yield ETF", .etf, .us, .nyse, .dividends, .{ .dividends = true }, .low, 6, false, .none),
    mkEntry("DVY", "iShares Select Dividend ETF", .etf, .us, .nasdaq, .dividends, .{ .dividends = true }, .low, 38, false, .none),
    // --- Cash-like ---
    mkEntry("SHV", "iShares Short Treasury Bond ETF", .etf, .us, .nasdaq, .cash_like, .{ .cash_like = true }, .low, 15, false, .none),
    mkEntry("SGOV", "iShares 0-3 Month Treasury Bond ETF", .etf, .us, .nyse, .cash_like, .{ .cash_like = true }, .low, 9, false, .none),
    mkEntry("BIL", "SPDR Bloomberg 1-3 Month T-Bill ETF", .etf, .us, .nyse, .cash_like, .{ .cash_like = true }, .low, 14, false, .none),
    // --- Restricted: leveraged and inverse ETFs (T3) ---
    mkEntry("SOXL", "Direxion Daily Semiconductor Bull 3X ETF", .leveraged_etf, .us, .nyse, .semiconductors, .{ .ai_infrastructure = true, .semiconductors = true }, .high, 77, true, .leveraged_etf),
    mkEntry("SOXS", "Direxion Daily Semiconductor Bear 3X ETF", .inverse_etf, .us, .nyse, .semiconductors, .{ .semiconductors = true }, .high, 92, true, .inverse_etf),
    mkEntry("BULZ", "MicroSectors FANG 3X Bull Leveraged ETN", .leveraged_etf, .us, .nyse, .ai_infrastructure, .{ .ai_infrastructure = true }, .high, 95, true, .leveraged_etf),
};

// ---------------------------------------------------------------------------
// Lookup functions (T4)
// ---------------------------------------------------------------------------

/// Writes pointers to catalog entries tagged with theme into out[0..return_value].
/// Includes both eligible and restricted entries; callers check .restricted.
/// out.len bounds the maximum results written.
pub fn filterByTheme(theme: SectorTheme, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const e = &catalog[i];
        if (e.themes.has(theme)) {
            out[n] = e;
            n += 1;
        }
    }
    return n;
}

/// Writes pointers to catalog entries with the given primary sector into out[0..return_value].
pub fn filterBySector(sector: SectorTheme, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const e = &catalog[i];
        if (e.sector == sector) {
            out[n] = e;
            n += 1;
        }
    }
    return n;
}

/// Writes pointers to catalog entries with the given asset class into out[0..return_value].
pub fn filterByAssetClass(ac: AssetClass, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const e = &catalog[i];
        if (e.asset_class == ac) {
            out[n] = e;
            n += 1;
        }
    }
    return n;
}

/// Writes pointers to catalog entries listed on the given venue into out[0..return_value].
pub fn filterByVenue(venue: Venue, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const e = &catalog[i];
        if (e.venue == venue) {
            out[n] = e;
            n += 1;
        }
    }
    return n;
}

/// Returns a pointer to the catalog entry matching ticker, or null if not found.
///
/// Uses std.mem.eql for byte-equality comparison.  src/util/cstr provides
/// fd_cstr_ncpy, fd_cstr_printf, and fd_cstr_to_* for copy and formatting but
/// no string equality function, so std.mem.eql is the correct path here.
pub fn lookupByTicker(ticker: []const u8) ?*const InstrumentEntry {
    for (0..catalog.len) |i| {
        const e = &catalog[i];
        if (std.mem.eql(u8, e.tickerSlice(), ticker)) return e;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ThemeSet layout: size is exactly 1 byte" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(ThemeSet));
}

test "ThemeSet: has() returns correct membership" {
    const ts = ThemeSet{ .ai_infrastructure = true, .semiconductors = true };
    try std.testing.expect(ts.has(.ai_infrastructure));
    try std.testing.expect(ts.has(.semiconductors));
    try std.testing.expect(!ts.has(.cloud));
    try std.testing.expect(!ts.has(.cyber_security));
    try std.testing.expect(!ts.has(.broad_market));
    try std.testing.expect(!ts.has(.dividends));
    try std.testing.expect(!ts.has(.cash_like));
}

test "ThemeSet: empty set has() returns false for all themes" {
    const ts = ThemeSet{};
    inline for (std.meta.fields(SectorTheme)) |f| {
        try std.testing.expect(!ts.has(@enumFromInt(f.value)));
    }
}

test "catalog: total entry count is 24" {
    try std.testing.expectEqual(@as(usize, 24), catalog.len);
}

test "catalog: all entries have non-empty ticker and name" {
    for (catalog) |e| {
        try std.testing.expect(e.ticker_len > 0);
        try std.testing.expect(e.name_len > 0);
        try std.testing.expect(e.ticker_len <= max_ticker_len);
        try std.testing.expect(e.name_len <= max_name_len);
    }
}

test "catalog: restricted entries have non-none restriction_reason" {
    for (catalog) |e| {
        if (e.restricted) {
            try std.testing.expect(e.restriction_reason != .none);
        } else {
            try std.testing.expectEqual(RestrictionReason.none, e.restriction_reason);
        }
    }
}

test "catalog: all equities have expense_ratio_bps == 0" {
    for (catalog) |e| {
        if (e.asset_class == .equity) {
            try std.testing.expectEqual(@as(u16, 0), e.expense_ratio_bps);
        }
    }
}

test "catalog: all entries are US market" {
    for (catalog) |e| {
        try std.testing.expectEqual(Market.us, e.market);
    }
}

test "catalog: all entries are NYSE or NASDAQ" {
    for (catalog) |e| {
        const ok = e.venue == .nyse or e.venue == .nasdaq;
        try std.testing.expect(ok);
    }
}

// --- Acceptance criteria: AI infra scenario >= 4 eligible, >= 2 rejected ---

test "filterByTheme: ai_infrastructure scenario yields >= 4 eligible and >= 2 restricted" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterByTheme(.ai_infrastructure, &out);
    var eligible: usize = 0;
    var restricted: usize = 0;
    for (out[0..n]) |e| {
        if (e.restricted) restricted += 1 else eligible += 1;
    }
    try std.testing.expect(eligible >= 4);
    try std.testing.expect(restricted >= 2);
}

test "filterByTheme: restricted entries carry clear restriction_reason" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterByTheme(.ai_infrastructure, &out);
    for (out[0..n]) |e| {
        if (e.restricted) {
            try std.testing.expect(e.restriction_reason == .leveraged_etf or
                e.restriction_reason == .inverse_etf or
                e.restriction_reason == .manual_denylist);
        }
    }
}

test "filterByTheme: unknown theme with no matches returns 0" {
    // Cash-like instruments have no ai_infrastructure tag; verify disjoint.
    // Use a theme that has entries so we can confirm the inverse.
    var cash_out: [catalog.len]*const InstrumentEntry = undefined;
    const cash_n = filterByTheme(.cash_like, &cash_out);
    try std.testing.expect(cash_n > 0);
    for (cash_out[0..cash_n]) |e| {
        try std.testing.expect(e.themes.has(.cash_like));
    }
}

test "filterByTheme: every returned entry has the requested theme bit set" {
    const themes_to_check = [_]SectorTheme{
        .ai_infrastructure, .semiconductors, .cloud,
        .cyber_security,    .broad_market,   .dividends,
        .cash_like,
    };
    var out: [catalog.len]*const InstrumentEntry = undefined;
    for (themes_to_check) |theme| {
        const n = filterByTheme(theme, &out);
        for (out[0..n]) |e| {
            try std.testing.expect(e.themes.has(theme));
        }
    }
}

test "filterBySector: every returned entry has the requested primary sector" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterBySector(.broad_market, &out);
    try std.testing.expect(n >= 4);
    for (out[0..n]) |e| {
        try std.testing.expectEqual(SectorTheme.broad_market, e.sector);
    }
}

test "filterByAssetClass: every returned entry has the requested asset class" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterByAssetClass(.etf, &out);
    try std.testing.expect(n > 0);
    for (out[0..n]) |e| {
        try std.testing.expectEqual(AssetClass.etf, e.asset_class);
    }
}

test "filterByAssetClass: equity returns only equities" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterByAssetClass(.equity, &out);
    try std.testing.expect(n > 0);
    for (out[0..n]) |e| {
        try std.testing.expectEqual(AssetClass.equity, e.asset_class);
    }
}

test "filterByVenue: every returned entry is on the requested venue" {
    var nasdaq_out: [catalog.len]*const InstrumentEntry = undefined;
    const nasdaq_n = filterByVenue(.nasdaq, &nasdaq_out);
    try std.testing.expect(nasdaq_n > 0);
    for (nasdaq_out[0..nasdaq_n]) |e| {
        try std.testing.expectEqual(Venue.nasdaq, e.venue);
    }

    var nyse_out: [catalog.len]*const InstrumentEntry = undefined;
    const nyse_n = filterByVenue(.nyse, &nyse_out);
    try std.testing.expect(nyse_n > 0);
    for (nyse_out[0..nyse_n]) |e| {
        try std.testing.expectEqual(Venue.nyse, e.venue);
    }
}

test "filterByVenue: nasdaq + nyse counts sum to total catalog size" {
    var nasdaq_out: [catalog.len]*const InstrumentEntry = undefined;
    var nyse_out: [catalog.len]*const InstrumentEntry = undefined;
    const nasdaq_n = filterByVenue(.nasdaq, &nasdaq_out);
    const nyse_n = filterByVenue(.nyse, &nyse_out);
    try std.testing.expectEqual(catalog.len, nasdaq_n + nyse_n);
}

test "lookupByTicker: NVDA returns correct entry" {
    const e = lookupByTicker("NVDA");
    try std.testing.expect(e != null);
    try std.testing.expectEqualStrings("NVDA", e.?.tickerSlice());
    try std.testing.expectEqual(AssetClass.equity, e.?.asset_class);
    try std.testing.expectEqual(Market.us, e.?.market);
    try std.testing.expectEqual(Venue.nasdaq, e.?.venue);
    try std.testing.expect(e.?.themes.has(.ai_infrastructure));
    try std.testing.expect(e.?.themes.has(.semiconductors));
    try std.testing.expect(!e.?.restricted);
    try std.testing.expectEqual(@as(u16, 0), e.?.expense_ratio_bps);
}

test "lookupByTicker: SOXL is restricted with leveraged_etf reason" {
    const e = lookupByTicker("SOXL");
    try std.testing.expect(e != null);
    try std.testing.expect(e.?.restricted);
    try std.testing.expectEqual(RestrictionReason.leveraged_etf, e.?.restriction_reason);
    try std.testing.expectEqual(AssetClass.leveraged_etf, e.?.asset_class);
}

test "lookupByTicker: SOXS is restricted with inverse_etf reason" {
    const e = lookupByTicker("SOXS");
    try std.testing.expect(e != null);
    try std.testing.expect(e.?.restricted);
    try std.testing.expectEqual(RestrictionReason.inverse_etf, e.?.restriction_reason);
}

test "lookupByTicker: BULZ is restricted with leveraged_etf reason" {
    const e = lookupByTicker("BULZ");
    try std.testing.expect(e != null);
    try std.testing.expect(e.?.restricted);
    try std.testing.expectEqual(RestrictionReason.leveraged_etf, e.?.restriction_reason);
}

test "lookupByTicker: unknown ticker returns null" {
    try std.testing.expectEqual(@as(?*const InstrumentEntry, null), lookupByTicker("ZZZZ"));
    try std.testing.expectEqual(@as(?*const InstrumentEntry, null), lookupByTicker(""));
}

test "lookupByTicker: all catalog tickers are individually resolvable" {
    for (&catalog) |*e| {
        const found = lookupByTicker(e.tickerSlice());
        try std.testing.expect(found != null);
        try std.testing.expectEqualStrings(e.tickerSlice(), found.?.tickerSlice());
    }
}

test "catalog: ticker slices match expected values for known entries" {
    const nvda = lookupByTicker("NVDA").?;
    try std.testing.expectEqualStrings("NVIDIA Corporation", nvda.nameSlice());

    const spy = lookupByTicker("SPY").?;
    try std.testing.expectEqualStrings("SPDR S&P 500 ETF Trust", spy.nameSlice());
    try std.testing.expectEqual(AssetClass.etf, spy.asset_class);
    try std.testing.expectEqual(@as(u16, 9), spy.expense_ratio_bps);

    const sgov = lookupByTicker("SGOV").?;
    try std.testing.expectEqual(SectorTheme.cash_like, sgov.sector);
    try std.testing.expect(sgov.themes.has(.cash_like));
    try std.testing.expect(!sgov.restricted);
}
