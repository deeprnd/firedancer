/// Shared instrument classification schema
///
/// This module is the single Zig source of truth for bounded financial
/// classification primitives that are shared across thesis intent, catalog
/// facts, basket construction, and policy screening.
const std = @import("std");

comptime {
    @setEvalBranchQuota(50_000);
}

pub const classification_contract_version: u16 = 1;

pub const max_canonical_id_len: usize = 32;
pub const max_asset_class_values: usize = 8;
pub const max_instrument_type_values: usize = 8;
pub const max_classification_refs: usize = 8;
pub const max_theme_ids: usize = 8;

pub const Market = enum(u8) { us };

pub const Venue = enum(u8) { nyse, nasdaq };

pub const AssetClass = enum(u8) {
    equity,
    fixed_income,
    commodity,
    fx,
    crypto,
    cash,

    pub fn label(self: AssetClass) []const u8 {
        return switch (self) {
            .equity => "equity",
            .fixed_income => "fixed_income",
            .commodity => "commodity",
            .fx => "fx",
            .crypto => "crypto",
            .cash => "cash",
        };
    }
};

pub const InstrumentType = enum(u8) {
    stock,
    etf,
    bond,
    option,
    future,
    fund,
    token,

    pub fn label(self: InstrumentType) []const u8 {
        return switch (self) {
            .stock => "stock",
            .etf => "ETF",
            .bond => "bond",
            .option => "option",
            .future => "future",
            .fund => "fund",
            .token => "token",
        };
    }
};

pub const RiskPreference = enum(u8) { low, moderate, high };

pub const CanonicalIdError = error{
    Empty,
    TooLong,
    InvalidEncoding,
};

pub const AssetClassListError = error{
    TooManyValues,
    DuplicateValue,
};

pub const InstrumentTypeListError = error{
    TooManyValues,
    DuplicateValue,
};

pub const ClassificationRefError = error{
    MissingTaxonomyVersion,
    TooManyValues,
    DuplicateValue,
    InvalidEncoding,
};

pub const ThemeIdListError = error{
    TooManyValues,
    DuplicateValue,
    InvalidEncoding,
};

pub const CanonicalId = struct {
    bytes: [max_canonical_id_len]u8 = std.mem.zeroes([max_canonical_id_len]u8),
    len: u8 = 0,

    pub fn slice(self: *const CanonicalId) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(self: CanonicalId, other: CanonicalId) bool {
        return std.mem.eql(u8, self.slice(), other.slice());
    }

    pub fn init(value: []const u8) CanonicalIdError!CanonicalId {
        try validateCanonicalId(value);
        var out = CanonicalId{};
        @memcpy(out.bytes[0..value.len], value);
        out.len = @intCast(value.len);
        return out;
    }
};

pub fn canonicalId(comptime raw_value: anytype) CanonicalId {
    const value = canonicalInputSlice(raw_value);
    validateCanonicalId(value) catch |err| switch (err) {
        error.Empty => @compileError("canonical id must be non-empty"),
        error.TooLong => @compileError("canonical id exceeds max_canonical_id_len"),
        error.InvalidEncoding => @compileError("canonical id must use lowercase ascii, digits, or underscore, and start with a letter"),
    };
    var out = CanonicalId{};
    inline for (value, 0..) |byte, i| out.bytes[i] = byte;
    out.len = value.len;
    return out;
}

pub const ClassificationRef = struct {
    taxonomy_id: CanonicalId = .{},
    taxonomy_version: u16 = 0,
    code: CanonicalId = .{},

    pub fn eql(self: ClassificationRef, other: ClassificationRef) bool {
        return self.taxonomy_version == other.taxonomy_version and
            self.taxonomy_id.eql(other.taxonomy_id) and
            self.code.eql(other.code);
    }

    pub fn init(
        taxonomy_id_value: []const u8,
        taxonomy_version_value: u16,
        code_value: []const u8,
    ) ClassificationRefError!ClassificationRef {
        if (taxonomy_version_value == 0) return ClassificationRefError.MissingTaxonomyVersion;
        return .{
            .taxonomy_id = CanonicalId.init(taxonomy_id_value) catch return ClassificationRefError.InvalidEncoding,
            .taxonomy_version = taxonomy_version_value,
            .code = CanonicalId.init(code_value) catch return ClassificationRefError.InvalidEncoding,
        };
    }
};

pub fn classificationRef(
    comptime taxonomy_id_value: anytype,
    comptime taxonomy_version_value: u16,
    comptime code_value: anytype,
) ClassificationRef {
    if (taxonomy_version_value == 0) {
        @compileError("classification taxonomy_version must be non-zero");
    }
    return .{
        .taxonomy_id = canonicalId(taxonomy_id_value),
        .taxonomy_version = taxonomy_version_value,
        .code = canonicalId(code_value),
    };
}

pub const AssetClassList = struct {
    values: [max_asset_class_values]AssetClass = std.mem.zeroes([max_asset_class_values]AssetClass),
    count: u8 = 0,

    pub fn has(self: AssetClassList, value: AssetClass) bool {
        for (self.values[0..self.count]) |member| {
            if (member == value) return true;
        }
        return false;
    }

    pub fn append(self: *AssetClassList, value: AssetClass) AssetClassListError!void {
        if (self.has(value)) return AssetClassListError.DuplicateValue;
        if (self.count >= max_asset_class_values) return AssetClassListError.TooManyValues;
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn validate(self: AssetClassList) AssetClassListError!void {
        if (self.count > max_asset_class_values) return AssetClassListError.TooManyValues;
        for (self.values[0..self.count], 0..) |value, i| {
            for (self.values[0..i]) |prior| {
                if (prior == value) return AssetClassListError.DuplicateValue;
            }
        }
    }
};

pub fn assetClassList(comptime values: anytype) AssetClassList {
    var out = AssetClassList{};
    inline for (values, 0..) |value, i| {
        if (i >= max_asset_class_values) @compileError("too many asset classes in literal");
        inline for (values, 0..) |prior, j| {
            if (j >= i) break;
            if (prior == value) @compileError("duplicate asset class in literal");
        }
        out.values[i] = value;
        out.count = i + 1;
    }
    return out;
}

pub const InstrumentTypeList = struct {
    values: [max_instrument_type_values]InstrumentType = std.mem.zeroes([max_instrument_type_values]InstrumentType),
    count: u8 = 0,

    pub fn has(self: InstrumentTypeList, value: InstrumentType) bool {
        for (self.values[0..self.count]) |member| {
            if (member == value) return true;
        }
        return false;
    }

    pub fn append(self: *InstrumentTypeList, value: InstrumentType) InstrumentTypeListError!void {
        if (self.has(value)) return InstrumentTypeListError.DuplicateValue;
        if (self.count >= max_instrument_type_values) return InstrumentTypeListError.TooManyValues;
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn validate(self: InstrumentTypeList) InstrumentTypeListError!void {
        if (self.count > max_instrument_type_values) return InstrumentTypeListError.TooManyValues;
        for (self.values[0..self.count], 0..) |value, i| {
            for (self.values[0..i]) |prior| {
                if (prior == value) return InstrumentTypeListError.DuplicateValue;
            }
        }
    }
};

pub fn instrumentTypeList(comptime values: anytype) InstrumentTypeList {
    var out = InstrumentTypeList{};
    inline for (values, 0..) |value, i| {
        if (i >= max_instrument_type_values) @compileError("too many instrument types in literal");
        inline for (values, 0..) |prior, j| {
            if (j >= i) break;
            if (prior == value) @compileError("duplicate instrument type in literal");
        }
        out.values[i] = value;
        out.count = i + 1;
    }
    return out;
}

pub const ThemeIdList = struct {
    values: [max_theme_ids]CanonicalId = std.mem.zeroes([max_theme_ids]CanonicalId),
    count: u8 = 0,

    pub fn has(self: ThemeIdList, value: CanonicalId) bool {
        for (self.values[0..self.count]) |member| {
            if (member.eql(value)) return true;
        }
        return false;
    }

    pub fn append(self: *ThemeIdList, value: CanonicalId) ThemeIdListError!void {
        if (self.has(value)) return ThemeIdListError.DuplicateValue;
        if (self.count >= max_theme_ids) return ThemeIdListError.TooManyValues;
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn validate(self: ThemeIdList) ThemeIdListError!void {
        if (self.count > max_theme_ids) return ThemeIdListError.TooManyValues;
        for (self.values[0..self.count], 0..) |value, i| {
            if (value.len == 0) return ThemeIdListError.InvalidEncoding;
            validateCanonicalId(value.slice()) catch return ThemeIdListError.InvalidEncoding;
            for (self.values[0..i]) |prior| {
                if (prior.eql(value)) return ThemeIdListError.DuplicateValue;
            }
        }
    }
};

pub fn themeIdList(comptime values: anytype) ThemeIdList {
    var out = ThemeIdList{};
    inline for (values, 0..) |value, i| {
        if (i >= max_theme_ids) @compileError("too many theme ids in literal");
        inline for (values, 0..) |prior, j| {
            if (j >= i) break;
            if (std.mem.eql(u8, canonicalInputSlice(prior), canonicalInputSlice(value))) {
                @compileError("duplicate theme id in literal");
            }
        }
        out.values[i] = canonicalId(value);
        out.count = i + 1;
    }
    return out;
}

pub const ClassificationRefList = struct {
    values: [max_classification_refs]ClassificationRef = std.mem.zeroes([max_classification_refs]ClassificationRef),
    count: u8 = 0,

    pub fn has(self: ClassificationRefList, value: ClassificationRef) bool {
        for (self.values[0..self.count]) |member| {
            if (member.eql(value)) return true;
        }
        return false;
    }

    pub fn append(self: *ClassificationRefList, value: ClassificationRef) ClassificationRefError!void {
        if (value.taxonomy_version == 0) return ClassificationRefError.MissingTaxonomyVersion;
        validateCanonicalId(value.taxonomy_id.slice()) catch return ClassificationRefError.InvalidEncoding;
        validateCanonicalId(value.code.slice()) catch return ClassificationRefError.InvalidEncoding;
        if (self.has(value)) return ClassificationRefError.DuplicateValue;
        if (self.count >= max_classification_refs) return ClassificationRefError.TooManyValues;
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn validate(self: ClassificationRefList) ClassificationRefError!void {
        if (self.count > max_classification_refs) return ClassificationRefError.TooManyValues;
        for (self.values[0..self.count], 0..) |value, i| {
            if (value.taxonomy_version == 0) return ClassificationRefError.MissingTaxonomyVersion;
            validateCanonicalId(value.taxonomy_id.slice()) catch return ClassificationRefError.InvalidEncoding;
            validateCanonicalId(value.code.slice()) catch return ClassificationRefError.InvalidEncoding;
            for (self.values[0..i]) |prior| {
                if (prior.eql(value)) return ClassificationRefError.DuplicateValue;
            }
        }
    }
};

pub fn classificationRefList(comptime values: anytype) ClassificationRefList {
    var out = ClassificationRefList{};
    inline for (values, 0..) |value, i| {
        if (i >= max_classification_refs) @compileError("too many classification refs in literal");
        if (value.taxonomy_version == 0) @compileError("classification taxonomy_version must be non-zero");
        validateCanonicalId(value.taxonomy_id.slice()) catch |err| switch (err) {
            error.Empty => @compileError("classification taxonomy_id must be non-empty"),
            error.TooLong => @compileError("classification taxonomy_id exceeds max_canonical_id_len"),
            error.InvalidEncoding => @compileError("classification taxonomy_id must be a canonical id"),
        };
        validateCanonicalId(value.code.slice()) catch |err| switch (err) {
            error.Empty => @compileError("classification code must be non-empty"),
            error.TooLong => @compileError("classification code exceeds max_canonical_id_len"),
            error.InvalidEncoding => @compileError("classification code must be a canonical id"),
        };
        inline for (values, 0..) |prior, j| {
            if (j >= i) break;
            if (prior.eql(value)) @compileError("duplicate classification ref in literal");
        }
        out.values[i] = value;
        out.count = i + 1;
    }
    return out;
}

pub fn validateCanonicalId(value: []const u8) CanonicalIdError!void {
    @setEvalBranchQuota(50_000);
    if (value.len == 0) return CanonicalIdError.Empty;
    if (value.len > max_canonical_id_len) return CanonicalIdError.TooLong;
    if (!isLowerAlpha(value[0])) return CanonicalIdError.InvalidEncoding;
    for (value) |byte| {
        if (!(isLowerAlpha(byte) or isDigit(byte) or byte == '_')) {
            return CanonicalIdError.InvalidEncoding;
        }
    }
}

fn isLowerAlpha(byte: u8) bool {
    return byte >= 'a' and byte <= 'z';
}

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

fn canonicalInputSlice(comptime value: anytype) []const u8 {
    return switch (@typeInfo(@TypeOf(value))) {
        .pointer => |pointer| switch (pointer.size) {
            .slice => value,
            .one => switch (@typeInfo(pointer.child)) {
                .array => |array| value.*[0..array.len],
                else => @compileError("unsupported canonical id pointer input"),
            },
            else => @compileError("unsupported canonical id pointer input"),
        },
        .array => value[0..],
        else => value,
    };
}

test "canonicalId validates lowercase underscore encoding" {
    const ok = try CanonicalId.init("ai_infrastructure");
    try std.testing.expectEqualStrings("ai_infrastructure", ok.slice());
    try std.testing.expectError(CanonicalIdError.InvalidEncoding, CanonicalId.init("AI"));
    try std.testing.expectError(CanonicalIdError.InvalidEncoding, CanonicalId.init("cash-like"));
}

test "assetClassList rejects duplicates" {
    var list = AssetClassList{};
    try list.append(.equity);
    try std.testing.expectError(AssetClassListError.DuplicateValue, list.append(.equity));
}

test "classificationRefList validates taxonomy version and uniqueness" {
    var list = ClassificationRefList{};
    const sector = try ClassificationRef.init("gics_sector", 2025, "information_technology");
    try list.append(sector);
    try std.testing.expectError(ClassificationRefError.DuplicateValue, list.append(sector));
    try std.testing.expectError(
        ClassificationRefError.MissingTaxonomyVersion,
        ClassificationRef.init("gics_sector", 0, "information_technology"),
    );
}

test "themeIdList rejects duplicate canonical ids" {
    var list = ThemeIdList{};
    try list.append(CanonicalId.init("ai_infrastructure") catch unreachable);
    try std.testing.expectError(
        ThemeIdListError.DuplicateValue,
        list.append(CanonicalId.init("ai_infrastructure") catch unreachable),
    );
}
