/// Instrument catalog contract: the versioned record shape and bounds that
/// any catalog data source (the fixture array in catalog.zig, or a future
/// non-fixture provider) must produce. Carries no concrete instrument data —
/// see catalog.zig for the fixture array, lookup functions, and fixture
/// validation.
const thesis = @import("thesis");

pub const AssetClass = thesis.AssetClass;
pub const InstrumentType = thesis.InstrumentType;
pub const Market = thesis.Market;
pub const Venue = thesis.Venue;
pub const RiskPreference = thesis.RiskPreference;
pub const CanonicalId = thesis.CanonicalId;
pub const ClassificationRef = thesis.ClassificationRef;
pub const ClassificationRefList = thesis.ClassificationRefList;
pub const ThemeIdList = thesis.ThemeIdList;

pub const catalog_schema_version: u16 = 2;

pub const max_ticker_len: usize = 8;
pub const max_name_len: usize = 48;

pub const RestrictionReason = enum(u8) {
    none = 0,
    leveraged_etf = 1,
    inverse_etf = 2,
    options_contract = 3,
    futures_contract = 4,
    non_us_venue = 5,
    manual_denylist = 6,
};

pub const InstrumentEntry = struct {
    ticker: [max_ticker_len]u8,
    ticker_len: u8,
    name: [max_name_len]u8,
    name_len: u8,
    asset_class: AssetClass,
    instrument_type: InstrumentType,
    market: Market,
    venue: Venue,
    sectors: ClassificationRefList,
    industries: ClassificationRefList,
    themes: ThemeIdList,
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

pub const CatalogValidationError = error{
    InvalidTicker,
    InvalidName,
    InvalidClassification,
    DuplicateTicker,
};

const std = @import("std");

test "InstrumentEntry.tickerSlice and nameSlice trim to their stored length" {
    var entry = std.mem.zeroes(InstrumentEntry);
    entry.ticker[0..4].* = "NVDA".*;
    entry.ticker_len = 4;
    entry.name[0..6].* = "NVIDIA".*;
    entry.name_len = 6;
    try std.testing.expectEqualStrings("NVDA", entry.tickerSlice());
    try std.testing.expectEqualStrings("NVIDIA", entry.nameSlice());
}
