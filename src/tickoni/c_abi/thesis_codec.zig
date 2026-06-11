/// Narrow Zig extern bindings for the Tickoni thesis codec C surface.
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
