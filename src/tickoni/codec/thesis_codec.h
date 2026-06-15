#ifndef HEADER_fd_src_tickoni_codec_thesis_codec_h
#define HEADER_fd_src_tickoni_codec_thesis_codec_h

#include <stdint.h>

/* Schema version for the thesis input schema.
   Must match thesis_schema_version in src/tickoni/schema/thesis.zig.
   Incrementing this value changes the hash key and invalidates existing hashes. */
#define TK_THESIS_SCHEMA_VERSION ((uint16_t)1)

/* Compute a stable content hash over a ThesisInput.
   Covers schema_version, account_id, target_notional_cents, market_scope,
   asset_class_prefs, sector_theme, risk_preference, max_single_name_pct,
   exclusions, user_text_len, and user_text[0..user_text_len].
   Hash key: "TKTHSS\0\0" LE (k0=0x0000535348544B54, k1=TK_THESIS_SCHEMA_VERSION).
   user_text must point to at least user_text_len bytes. */
uint64_t
tk_thesis_input_hash( uint16_t              user_text_len,
                      unsigned char const * user_text,
                      int64_t               target_notional_cents,
                      uint32_t              account_id,
                      uint8_t               market_scope,
                      uint8_t               asset_class_prefs,
                      uint8_t               sector_theme,
                      uint8_t               risk_preference,
                      uint8_t               max_single_name_pct,
                      uint8_t               exclusions );

/* Schema version for the basket schema.
   Must match basket_schema_version in src/tickoni/schema/basket.zig.
   Incrementing this value changes the hash key and invalidates existing hashes. */
#define TK_BASKET_SCHEMA_VERSION ((uint16_t)1)

/* Basket ticker stride: each ticker entry is zero-padded to this many bytes.
   Must match max_ticker_len in src/tickoni/schema/catalog.zig. */
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
   Must match trade_ticket_schema_version in src/tickoni/schema/trade_ticket.zig.
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
