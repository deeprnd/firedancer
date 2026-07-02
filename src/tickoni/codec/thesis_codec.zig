/// Content-hash composition for the thesis/basket/trade-ticket/paper-order
/// schemas. Hashing runs through c_abi.ballet (real Firedancer siphash13 via
/// src/tickoni/c_abi/shim/ballet.c); field order and hash keys are Tickoni
/// schema logic and live here. Field coverage per function is documented on
/// each function.
const std = @import("std");
const c_abi = @import("c_abi");

pub const thesis_schema_version: u16 = 3;
pub const thesis_max_ticker_len: u64 = 8;
pub const thesis_max_requested_tickers: u8 = 8;
pub const thesis_max_canonical_id_len: u64 = 32;
pub const thesis_classification_ref_stride: u64 = 66;

pub const basket_schema_version: u16 = 1;
pub const basket_max_ticker_len: u64 = 8;

pub const trade_ticket_schema_version: u16 = 1;
pub const ticket_max_ticker_len: u64 = 8;

const thesis_hash_k0: u64 = 0x0000535348544B54; // "TKTHSS\0\0" LE
const basket_hash_k0: u64 = 0x00005454534B424B; // "TKBSKT\0\0" LE
const ticket_hash_k0: u64 = 0x000054434B544B54; // "TKTCKT\0\0" LE
const paper_order_hash_k0: u64 = 0x000052444F504B54; // "TKPODR\0\0" LE

/// Compute a stable content hash over a ThesisInput.
///
/// Covers schema_version, account_id, target_notional_cents, market_scope,
/// asset_class_prefs, instrument_type_prefs, theme_count + themes_flat,
/// risk_preference, max_single_name_pct, asset_class_exclusions,
/// instrument_type_exclusions, sector_filter_count + sector_filter_flat,
/// industry_filter_count + industry_filter_flat, requested_ticker_count +
/// requested_tickers[0..requested_ticker_count] (each zero-padded to
/// thesis_max_ticker_len bytes), user_text_len, and user_text[0..user_text_len].
/// Themes and sector/industry filter entries must be passed in sorted
/// canonical order so equivalent inputs produce identical hashes regardless
/// of source ordering.
/// Hash key: "TKTHSS\0\0" LE (k0, k1=thesis_schema_version).
/// themes_flat must point to theme_count * thesis_max_canonical_id_len bytes.
/// sector_filter_flat/industry_filter_flat must point to
/// count * thesis_classification_ref_stride bytes.
/// requested_tickers must point to requested_ticker_count * thesis_max_ticker_len bytes.
pub fn tk_thesis_input_hash(
    user_text_len: u16,
    user_text: [*]const u8,
    target_notional_cents: i64,
    account_id: u32,
    market_scope: u8,
    asset_class_pref_count: u8,
    asset_class_prefs: [*]const u8,
    instrument_type_pref_count: u8,
    instrument_type_prefs: [*]const u8,
    theme_count: u8,
    themes_flat: [*]const u8,
    risk_preference: u8,
    max_single_name_pct: u8,
    asset_class_exclusion_count: u8,
    asset_class_exclusions: [*]const u8,
    instrument_type_exclusion_count: u8,
    instrument_type_exclusions: [*]const u8,
    sector_filter_count: u8,
    sector_filter_flat: [*]const u8,
    industry_filter_count: u8,
    industry_filter_flat: [*]const u8,
    requested_ticker_count: u8,
    requested_tickers: [*]const u8,
) u64 {
    var sip: c_abi.ballet.Siphash13 = .{};
    c_abi.ballet.siphashInit(&sip, thesis_hash_k0, thesis_schema_version);

    const ver: u16 = thesis_schema_version;
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&ver));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&account_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&target_notional_cents));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&market_scope));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&asset_class_pref_count));
    for (0..asset_class_pref_count) |i| c_abi.ballet.siphashAppend(&sip, asset_class_prefs[i .. i + 1]);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&instrument_type_pref_count));
    for (0..instrument_type_pref_count) |i| c_abi.ballet.siphashAppend(&sip, instrument_type_prefs[i .. i + 1]);

    // Multi-theme filter: count followed by each theme zero-padded to
    // thesis_max_canonical_id_len bytes. Caller must sort themes into
    // canonical order before calling so equivalent sets hash identically.
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&theme_count));
    for (0..theme_count) |i| {
        const off = i * thesis_max_canonical_id_len;
        c_abi.ballet.siphashAppend(&sip, themes_flat[off .. off + thesis_max_canonical_id_len]);
    }
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&risk_preference));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&max_single_name_pct));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&asset_class_exclusion_count));
    for (0..asset_class_exclusion_count) |i| c_abi.ballet.siphashAppend(&sip, asset_class_exclusions[i .. i + 1]);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&instrument_type_exclusion_count));
    for (0..instrument_type_exclusion_count) |i| c_abi.ballet.siphashAppend(&sip, instrument_type_exclusions[i .. i + 1]);

    // Sector and industry classification filters: count followed by packed
    // ClassificationRef entries (thesis_classification_ref_stride bytes
    // each). Caller must sort into canonical order.
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&sector_filter_count));
    for (0..sector_filter_count) |i| {
        const off = i * thesis_classification_ref_stride;
        c_abi.ballet.siphashAppend(&sip, sector_filter_flat[off .. off + thesis_classification_ref_stride]);
    }
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&industry_filter_count));
    for (0..industry_filter_count) |i| {
        const off = i * thesis_classification_ref_stride;
        c_abi.ballet.siphashAppend(&sip, industry_filter_flat[off .. off + thesis_classification_ref_stride]);
    }

    // Explicitly requested tickers: count followed by each ticker
    // zero-padded to thesis_max_ticker_len bytes.
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&requested_ticker_count));
    for (0..requested_ticker_count) |i| {
        const off = i * thesis_max_ticker_len;
        c_abi.ballet.siphashAppend(&sip, requested_tickers[off .. off + thesis_max_ticker_len]);
    }

    // user_text follows so two different phrasings of the same thesis are
    // distinguishable at the source-event level.
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&user_text_len));
    c_abi.ballet.siphashAppend(&sip, user_text[0..user_text_len]);

    return c_abi.ballet.siphashFini(&sip);
}

/// Compute a stable content hash over a constructed basket's composition.
/// Covers basket_schema_version, thesis_id, catalog_schema_version,
/// instrument_count, and for each instrument: ticker (zero-padded to
/// basket_max_ticker_len bytes), weight_bp, and allocation_cents.
/// Hash key: "TKBSKT\0\0" LE (k0, k1=basket_schema_version).
/// tickers must point to instrument_count * basket_max_ticker_len bytes.
pub fn tk_basket_hash(
    thesis_id: u64,
    catalog_schema_version: u16,
    instrument_count: u8,
    tickers: [*]const u8,
    weight_bps: [*]const u32,
    alloc_cents: [*]const i64,
) u64 {
    var sip: c_abi.ballet.Siphash13 = .{};
    c_abi.ballet.siphashInit(&sip, basket_hash_k0, basket_schema_version);

    const ver: u16 = basket_schema_version;
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&ver));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&thesis_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&catalog_schema_version));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&instrument_count));
    for (0..instrument_count) |i| {
        const off = i * basket_max_ticker_len;
        c_abi.ballet.siphashAppend(&sip, tickers[off .. off + basket_max_ticker_len]);
        c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&weight_bps[i]));
        c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&alloc_cents[i]));
    }

    return c_abi.ballet.siphashFini(&sip);
}

/// Compute a stable content hash for a trade ticket.
/// Covers schema_version, basket_id, account_id, side, order_type,
/// time_in_force, target_notional_cents, line_item_count, and for each
/// line item: ticker (zero-padded to ticket_max_ticker_len bytes),
/// notional_cents, limit_price_cents, market, venue, and sector.
/// Hash key: "TKTCKT\0\0" LE (k0, k1=trade_ticket_schema_version).
pub fn tk_trade_ticket_hash(
    basket_id: u64,
    account_id: u32,
    side: u8,
    order_type: u8,
    time_in_force: u8,
    target_notional_cents: i64,
    line_item_count: u8,
    tickers: [*]const u8,
    notional_cents: [*]const i64,
    limit_price_cents: [*]const i64,
    markets: [*]const u8,
    venues: [*]const u8,
    sectors: [*]const u8,
) u64 {
    var sip: c_abi.ballet.Siphash13 = .{};
    c_abi.ballet.siphashInit(&sip, ticket_hash_k0, trade_ticket_schema_version);

    const ver: u16 = trade_ticket_schema_version;
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&ver));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&basket_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&account_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&side));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&order_type));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&time_in_force));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&target_notional_cents));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&line_item_count));
    for (0..line_item_count) |i| {
        const off = i * ticket_max_ticker_len;
        c_abi.ballet.siphashAppend(&sip, tickers[off .. off + ticket_max_ticker_len]);
        c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&notional_cents[i]));
        c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&limit_price_cents[i]));
        c_abi.ballet.siphashAppend(&sip, markets[i .. i + 1]);
        c_abi.ballet.siphashAppend(&sip, venues[i .. i + 1]);
        c_abi.ballet.siphashAppend(&sip, sectors[i .. i + 1]);
    }

    return c_abi.ballet.siphashFini(&sip);
}

/// Compute a stable content hash for a paper execution result.
/// Covers schema_version, ticket_id, account_id, executed_at_ns,
/// filled_line_item_count, paper_seq, total_fill_notional_cents,
/// resulting_cash_cents, resulting_buying_power_cents, each filled line
/// item, and the resulting holdings snapshot.
/// Hash key: "TKPODR\0\0" LE (k0, k1=trade_ticket_schema_version).
pub fn tk_paper_order_hash(
    ticket_id: u64,
    account_id: u32,
    executed_at_ns: u64,
    filled_line_item_count: u8,
    paper_seq: u64,
    total_fill_notional_cents: i64,
    resulting_cash_cents: i64,
    resulting_buying_power_cents: i64,
    filled_tickers: [*]const u8,
    filled_shares: [*]const u32,
    fill_price_cents: [*]const i64,
    fill_notional_cents: [*]const i64,
    holding_count: u8,
    holding_tickers: [*]const u8,
    holding_share_counts: [*]const u32,
    holding_market_values: [*]const i64,
) u64 {
    var sip: c_abi.ballet.Siphash13 = .{};
    c_abi.ballet.siphashInit(&sip, paper_order_hash_k0, trade_ticket_schema_version);

    const ver: u16 = trade_ticket_schema_version;
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&ver));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&ticket_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&account_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&executed_at_ns));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&filled_line_item_count));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&paper_seq));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&total_fill_notional_cents));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&resulting_cash_cents));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&resulting_buying_power_cents));

    const filled_stride = ticket_max_ticker_len;
    for (0..filled_line_item_count) |i| {
        const off = i * filled_stride;
        c_abi.ballet.siphashAppend(&sip, filled_tickers[off .. off + filled_stride]);
        c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&filled_shares[i]));
        c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&fill_price_cents[i]));
        c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&fill_notional_cents[i]));
    }

    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&holding_count));
    for (0..holding_count) |i| {
        const off = i * filled_stride;
        c_abi.ballet.siphashAppend(&sip, holding_tickers[off .. off + filled_stride]);
        c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&holding_share_counts[i]));
        c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&holding_market_values[i]));
    }

    return c_abi.ballet.siphashFini(&sip);
}
