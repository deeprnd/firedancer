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
    asset_class_prefs: u8,
    sector_theme: u8,
    risk_preference: u8,
    max_single_name_pct: u8,
    exclusions: u8,
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
/// notional_cents must point to line_item_count elements.
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
) u64;

/// Compute a stable content hash for a paper execution result.
/// See src/tickoni/codec/thesis_codec.h for field coverage and key constants.
pub extern fn tk_paper_order_hash(
    ticket_id: u64,
    account_id: u32,
    filled_line_item_count: u8,
    paper_seq: u64,
) u64;
