#ifndef HEADER_fd_src_tickoni_codec_thesis_codec_h
#define HEADER_fd_src_tickoni_codec_thesis_codec_h

#include <stdint.h>

/* Schema version for the thesis input schema.
   Must match thesis_schema_version in src/tickoni/schema/consumer_money/thesis.zig.
   Incrementing this value changes the hash key and invalidates existing hashes. */
#define TK_THESIS_SCHEMA_VERSION ((uint16_t)3)

/* Ticker stride for requested_tickers: same as catalog and basket stride. */
#define TK_THESIS_MAX_TICKER_LEN ((ulong)8)

/* Maximum explicitly requested tickers in one ThesisInput. */
#define TK_THESIS_MAX_REQUESTED_TICKERS ((uint8_t)8)

/* Byte stride for each canonical id in the themes_flat buffer.
   Must match max_canonical_id_len in src/tickoni/schema/classification/classification.zig. */
#define TK_THESIS_MAX_CANONICAL_ID_LEN ((ulong)32)

/* Packed byte stride for one ClassificationRef in sector/industry filter buffers.
   Layout per entry: taxonomy_id (32 bytes, zero-padded) +
                     taxonomy_version (2 bytes, little-endian uint16) +
                     code (32 bytes, zero-padded) = 66 bytes. */
#define TK_THESIS_CLASSIFICATION_REF_STRIDE ((ulong)66)

/* Compute a stable content hash over a ThesisInput.
   Covers schema_version, account_id, target_notional_cents, market_scope,
   asset_class_prefs, instrument_type_prefs, theme_count + themes_flat,
   risk_preference, max_single_name_pct, asset_class_exclusions,
   instrument_type_exclusions, sector_filter_count + sector_filter_flat,
   industry_filter_count + industry_filter_flat, requested_ticker_count +
   requested_tickers[0..requested_ticker_count] (each zero-padded to
   TK_THESIS_MAX_TICKER_LEN bytes), user_text_len, and user_text[0..user_text_len].
   Themes and sector/industry filter entries must be passed in sorted canonical
   order so equivalent inputs produce identical hashes regardless of source ordering.
   Hash key: "TKTHSS\0\0" LE (k0=0x0000535348544B54, k1=TK_THESIS_SCHEMA_VERSION).
   user_text must point to at least user_text_len bytes.
   themes_flat must point to theme_count * TK_THESIS_MAX_CANONICAL_ID_LEN bytes.
   sector_filter_flat must point to sector_filter_count * TK_THESIS_CLASSIFICATION_REF_STRIDE bytes.
   industry_filter_flat must point to industry_filter_count * TK_THESIS_CLASSIFICATION_REF_STRIDE bytes.
   requested_tickers must point to requested_ticker_count * TK_THESIS_MAX_TICKER_LEN bytes. */
uint64_t
tk_thesis_input_hash( uint16_t              user_text_len,
                      unsigned char const * user_text,
                      int64_t               target_notional_cents,
                      uint32_t              account_id,
                      uint8_t               market_scope,
                      uint8_t               asset_class_pref_count,
                      uint8_t const *       asset_class_prefs,
                      uint8_t               instrument_type_pref_count,
                      uint8_t const *       instrument_type_prefs,
                      uint8_t               theme_count,
                      unsigned char const * themes_flat,
                      uint8_t               risk_preference,
                      uint8_t               max_single_name_pct,
                      uint8_t               asset_class_exclusion_count,
                      uint8_t const *       asset_class_exclusions,
                      uint8_t               instrument_type_exclusion_count,
                      uint8_t const *       instrument_type_exclusions,
                      uint8_t               sector_filter_count,
                      unsigned char const * sector_filter_flat,
                      uint8_t               industry_filter_count,
                      unsigned char const * industry_filter_flat,
                      uint8_t               requested_ticker_count,
                      unsigned char const * requested_tickers );

/* Schema version for the basket schema.
   Must match basket_schema_version in src/tickoni/schema/consumer_money/basket.zig.
   Incrementing this value changes the hash key and invalidates existing hashes. */
#define TK_BASKET_SCHEMA_VERSION ((uint16_t)1)

/* Basket ticker stride: each ticker entry is zero-padded to this many bytes.
   Must match max_ticker_len in src/tickoni/schema/consumer_money/catalog.zig. */
#define TK_BASKET_MAX_TICKER_LEN ((ulong)8)

/* Compute a stable content hash over a constructed basket's composition.
   Covers basket_schema_version, thesis_id, catalog_schema_version,
   instrument_count, and for each instrument: ticker (zero-padded to
   TK_BASKET_MAX_TICKER_LEN bytes), weight_bp, and allocation_cents.
   Hash key: "TKBSKT\0\0" LE (k0=0x00005454534B424B, k1=TK_BASKET_SCHEMA_VERSION).
   tickers must point to instrument_count * TK_BASKET_MAX_TICKER_LEN bytes.
   weight_bps and alloc_cents must each point to instrument_count elements. */
uint64_t
tk_basket_hash( uint64_t         thesis_id,
                uint16_t         catalog_schema_version,
                uint8_t          instrument_count,
                uint8_t  const * tickers,
                uint32_t const * weight_bps,
                int64_t  const * alloc_cents );

/* Schema version for the trade ticket schema.
   Must match trade_ticket_schema_version in src/tickoni/schema/consumer_money/trade_ticket.zig.
   Incrementing this value changes the hash key and invalidates existing hashes. */
#define TK_TRADE_TICKET_SCHEMA_VERSION ((uint16_t)1)

/* Ticker stride for trade tickets: same as the basket and catalog stride. */
#define TK_TICKET_MAX_TICKER_LEN ((ulong)8)

/* Compute a stable content hash for a trade ticket.
   Covers schema_version, basket_id, account_id, side, order_type,
   time_in_force, target_notional_cents, line_item_count, and for each
   line item: ticker (zero-padded to TK_TICKET_MAX_TICKER_LEN bytes),
   target_notional_cents, limit_price_cents, market, venue, and sector.
   Hash key: "TKTCKT\0\0" LE (k0=0x000054434B544B54, k1=TK_TRADE_TICKET_SCHEMA_VERSION).
   tickers must point to line_item_count * TK_TICKET_MAX_TICKER_LEN bytes.
   line-item arrays must each point to line_item_count elements. */
uint64_t
tk_trade_ticket_hash( uint64_t         basket_id,
                      uint32_t         account_id,
                      uint8_t          side,
                      uint8_t          order_type,
                      uint8_t          time_in_force,
                      int64_t          target_notional_cents,
                      uint8_t          line_item_count,
                      uint8_t  const * tickers,
                      int64_t  const * notional_cents,
                      int64_t  const * limit_price_cents,
                      uint8_t  const * markets,
                      uint8_t  const * venues,
                      uint8_t  const * sectors );

/* Compute a stable content hash for a paper execution result.
   Covers schema_version, ticket_id, account_id, executed_at_ns,
   filled_line_item_count, paper_seq, total_fill_notional_cents,
   resulting_cash_cents, resulting_buying_power_cents, each filled line item,
   and the resulting holdings snapshot.
   Hash key: "TKPODR\0\0" LE (k0=0x000052444F504B54, k1=TK_TRADE_TICKET_SCHEMA_VERSION). */
uint64_t
tk_paper_order_hash( uint64_t ticket_id,
                     uint32_t account_id,
                     uint64_t executed_at_ns,
                     uint8_t  filled_line_item_count,
                     uint64_t paper_seq,
                     int64_t  total_fill_notional_cents,
                     int64_t  resulting_cash_cents,
                     int64_t  resulting_buying_power_cents,
                     uint8_t  const * filled_tickers,
                     uint32_t const * filled_shares,
                     int64_t  const * fill_price_cents,
                     int64_t  const * fill_notional_cents,
                     uint8_t  holding_count,
                     uint8_t  const * holding_tickers,
                     uint32_t const * holding_share_counts,
                     int64_t  const * holding_market_values );

#endif /* HEADER_fd_src_tickoni_codec_thesis_codec_h */
