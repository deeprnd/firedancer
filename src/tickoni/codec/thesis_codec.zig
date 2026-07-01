/// Narrow Zig extern bindings for the Tickoni thesis/basket codec C surface.
///
/// The implementation lives in src/tickoni/codec/thesis_hash.c and uses
/// fd_siphash13 from src/ballet/siphash13.  This file stays ABI-only.
/// Compute a stable content hash over a ThesisInput.
/// See src/tickoni/codec/thesis_codec.h for field coverage and key constants.
/// Callers must ensure user_text_len <= max_user_text_len before calling.
pub extern fn tk_thesis_input_hash(
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
) u64;

/// Compute a stable content hash over a constructed basket's composition.
/// See src/tickoni/codec/thesis_codec.h for field coverage and key constants.
/// tickers must point to instrument_count * TK_BASKET_MAX_TICKER_LEN (8) bytes.
/// weight_bps and alloc_cents must each point to instrument_count elements.
pub extern fn tk_basket_hash(
    thesis_id: u64,
    catalog_schema_version: u16,
    instrument_count: u8,
    tickers: [*]const u8,
    weight_bps: [*]const u32,
    alloc_cents: [*]const i64,
) u64;

/// Compute a stable content hash for a trade ticket.
/// See src/tickoni/codec/thesis_codec.h for field coverage and key constants.
/// tickers must point to line_item_count * TK_TICKET_MAX_TICKER_LEN (8) bytes.
/// line-item arrays must each point to line_item_count elements.
pub extern fn tk_trade_ticket_hash(
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
) u64;

/// Compute a stable content hash for a paper execution result.
/// See src/tickoni/codec/thesis_codec.h for field coverage and key constants.
pub extern fn tk_paper_order_hash(
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
) u64;
