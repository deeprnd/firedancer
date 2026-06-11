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

#endif /* HEADER_fd_src_tickoni_codec_thesis_codec_h */
