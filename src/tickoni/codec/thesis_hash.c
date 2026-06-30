#include "thesis_codec.h"

#include "../../ballet/siphash13/fd_siphash13.h"

/* Hash keys for the thesis input schema.
   TK_THESIS_HASH_K0 encodes "TKTHSS\0\0" in little-endian.
   Changing either constant invalidates all existing thesis content hashes. */
#define TK_THESIS_HASH_K0 (0x0000535348544B54UL) /* "TKTHSS\0\0" LE */
#define TK_THESIS_HASH_K1 ((ulong)TK_THESIS_SCHEMA_VERSION)

#define TK_HASH(ptr,sz) fd_siphash13_append( sip, (uchar const *)(ptr), (sz) )

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
                      unsigned char const * requested_tickers ) {
  fd_siphash13_t _sip[1];
  fd_siphash13_t * sip = fd_siphash13_init( _sip, TK_THESIS_HASH_K0, TK_THESIS_HASH_K1 );

  /* Structured identity fields first, then user text. */
  uint16_t ver = TK_THESIS_SCHEMA_VERSION;
  TK_HASH( &ver,                   sizeof(uint16_t) );
  TK_HASH( &account_id,            sizeof(uint32_t) );
  TK_HASH( &target_notional_cents, sizeof(int64_t)  );
  TK_HASH( &market_scope,          sizeof(uint8_t)  );
  TK_HASH( &asset_class_pref_count,sizeof(uint8_t)  );
  for( uint8_t i = 0; i < asset_class_pref_count; i++ ) {
    TK_HASH( asset_class_prefs + i, sizeof(uint8_t) );
  }
  TK_HASH( &instrument_type_pref_count, sizeof(uint8_t) );
  for( uint8_t i = 0; i < instrument_type_pref_count; i++ ) {
    TK_HASH( instrument_type_prefs + i, sizeof(uint8_t) );
  }
  /* Multi-theme filter: count followed by each theme zero-padded to
     TK_THESIS_MAX_CANONICAL_ID_LEN bytes.  Caller must sort themes into
     canonical order before calling so equivalent sets hash identically. */
  TK_HASH( &theme_count, sizeof(uint8_t) );
  ulong theme_stride = TK_THESIS_MAX_CANONICAL_ID_LEN;
  for( uint8_t i = 0; i < theme_count; i++ ) {
    TK_HASH( themes_flat + (ulong)i * theme_stride, theme_stride );
  }
  TK_HASH( &risk_preference,       sizeof(uint8_t)  );
  TK_HASH( &max_single_name_pct,   sizeof(uint8_t)  );
  TK_HASH( &asset_class_exclusion_count, sizeof(uint8_t) );
  for( uint8_t i = 0; i < asset_class_exclusion_count; i++ ) {
    TK_HASH( asset_class_exclusions + i, sizeof(uint8_t) );
  }
  TK_HASH( &instrument_type_exclusion_count, sizeof(uint8_t) );
  for( uint8_t i = 0; i < instrument_type_exclusion_count; i++ ) {
    TK_HASH( instrument_type_exclusions + i, sizeof(uint8_t) );
  }
  /* Sector and industry classification filters: count followed by packed
     ClassificationRef entries (TK_THESIS_CLASSIFICATION_REF_STRIDE bytes each).
     Caller must sort into canonical order so equivalent sets hash identically. */
  TK_HASH( &sector_filter_count, sizeof(uint8_t) );
  ulong ref_stride = TK_THESIS_CLASSIFICATION_REF_STRIDE;
  for( uint8_t i = 0; i < sector_filter_count; i++ ) {
    TK_HASH( sector_filter_flat + (ulong)i * ref_stride, ref_stride );
  }
  TK_HASH( &industry_filter_count, sizeof(uint8_t) );
  for( uint8_t i = 0; i < industry_filter_count; i++ ) {
    TK_HASH( industry_filter_flat + (ulong)i * ref_stride, ref_stride );
  }
  /* Explicitly requested tickers: count followed by each ticker zero-padded to
     TK_THESIS_MAX_TICKER_LEN bytes.  Two inputs that differ only in which tickers
     were explicitly named produce different hashes. */
  TK_HASH( &requested_ticker_count, sizeof(uint8_t) );
  ulong ticker_stride = TK_THESIS_MAX_TICKER_LEN;
  for( uint8_t i = 0; i < requested_ticker_count; i++ ) {
    TK_HASH( requested_tickers + (ulong)i * ticker_stride, ticker_stride );
  }
  /* user_text follows so two different phrasings of the same thesis are
     distinguishable at the source-event level even when intent normalizes
     identically. */
  TK_HASH( &user_text_len,         sizeof(uint16_t)     );
  TK_HASH( user_text,              (ulong)user_text_len );

  return fd_siphash13_fini( sip );
}

/* Hash keys for the basket schema.
   TK_BASKET_HASH_K0 encodes "TKBSKT\0\0" in little-endian.
   Changing either constant invalidates all existing basket content hashes. */
#define TK_BASKET_HASH_K0 (0x00005454534B424BUL) /* "TKBSKT\0\0" LE */
#define TK_BASKET_HASH_K1 ((ulong)TK_BASKET_SCHEMA_VERSION)

uint64_t
tk_basket_hash( uint64_t         thesis_id,
                uint16_t         catalog_schema_version,
                uint8_t          instrument_count,
                uint8_t  const * tickers,
                uint32_t const * weight_bps,
                int64_t  const * alloc_cents ) {
  fd_siphash13_t _sip[1];
  fd_siphash13_t * sip = fd_siphash13_init( _sip, TK_BASKET_HASH_K0, TK_BASKET_HASH_K1 );

  uint16_t ver = TK_BASKET_SCHEMA_VERSION;
  TK_HASH( &ver,                   sizeof(uint16_t) );
  TK_HASH( &thesis_id,             sizeof(uint64_t) );
  TK_HASH( &catalog_schema_version, sizeof(uint16_t) );
  TK_HASH( &instrument_count,      sizeof(uint8_t)  );
  /* Per-instrument composition: ticker (zero-padded stride), weight_bp, alloc_cents. */
  ulong stride = TK_BASKET_MAX_TICKER_LEN;
  for( uint8_t i = 0; i < instrument_count; i++ ) {
    TK_HASH( tickers + (ulong)i * stride, stride           );
    TK_HASH( weight_bps + i,              sizeof(uint32_t) );
    TK_HASH( alloc_cents + i,             sizeof(int64_t)  );
  }

  return fd_siphash13_fini( sip );
}

/* Hash keys for the trade ticket schema.
   TK_TICKET_HASH_K0 encodes "TKTCKT\0\0" approximately in little-endian.
   Changing either constant invalidates all existing ticket content hashes. */
#define TK_TICKET_HASH_K0 (0x000054434B544B54UL)
#define TK_TICKET_HASH_K1 ((ulong)TK_TRADE_TICKET_SCHEMA_VERSION)

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
                      uint8_t  const * sectors ) {
  fd_siphash13_t _sip[1];
  fd_siphash13_t * sip = fd_siphash13_init( _sip, TK_TICKET_HASH_K0, TK_TICKET_HASH_K1 );

  uint16_t ver = TK_TRADE_TICKET_SCHEMA_VERSION;
  TK_HASH( &ver,                   sizeof(uint16_t) );
  TK_HASH( &basket_id,             sizeof(uint64_t) );
  TK_HASH( &account_id,            sizeof(uint32_t) );
  TK_HASH( &side,                  sizeof(uint8_t)  );
  TK_HASH( &order_type,            sizeof(uint8_t)  );
  TK_HASH( &time_in_force,         sizeof(uint8_t)  );
  TK_HASH( &target_notional_cents, sizeof(int64_t)  );
  TK_HASH( &line_item_count,       sizeof(uint8_t)  );
  ulong stride = TK_TICKET_MAX_TICKER_LEN;
  for( uint8_t i = 0; i < line_item_count; i++ ) {
    TK_HASH( tickers + (ulong)i * stride, stride            );
    TK_HASH( notional_cents + i,          sizeof(int64_t)   );
    TK_HASH( limit_price_cents + i,       sizeof(int64_t)   );
    TK_HASH( markets + i,                 sizeof(uint8_t)   );
    TK_HASH( venues + i,                  sizeof(uint8_t)   );
    TK_HASH( sectors + i,                 sizeof(uint8_t)   );
  }

  return fd_siphash13_fini( sip );
}

/* Hash keys for the paper execution result.
   TK_PAPER_ORDER_HASH_K0 encodes "TKPODR\0\0" approximately in little-endian.
   Changing either constant invalidates all existing paper-order content hashes. */
#define TK_PAPER_ORDER_HASH_K0 (0x000052444F504B54UL)
#define TK_PAPER_ORDER_HASH_K1 ((ulong)TK_TRADE_TICKET_SCHEMA_VERSION)

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
                     int64_t  const * holding_market_values ) {
  fd_siphash13_t _sip[1];
  fd_siphash13_t * sip = fd_siphash13_init( _sip, TK_PAPER_ORDER_HASH_K0, TK_PAPER_ORDER_HASH_K1 );

  uint16_t ver = TK_TRADE_TICKET_SCHEMA_VERSION;
  TK_HASH( &ver,                         sizeof(uint16_t) );
  TK_HASH( &ticket_id,                   sizeof(uint64_t) );
  TK_HASH( &account_id,                  sizeof(uint32_t) );
  TK_HASH( &executed_at_ns,              sizeof(uint64_t) );
  TK_HASH( &filled_line_item_count,      sizeof(uint8_t)  );
  TK_HASH( &paper_seq,                   sizeof(uint64_t) );
  TK_HASH( &total_fill_notional_cents,   sizeof(int64_t)  );
  TK_HASH( &resulting_cash_cents,        sizeof(int64_t)  );
  TK_HASH( &resulting_buying_power_cents,sizeof(int64_t)  );

  ulong filled_stride = TK_TICKET_MAX_TICKER_LEN;
  for( uint8_t i = 0; i < filled_line_item_count; i++ ) {
    TK_HASH( filled_tickers + (ulong)i * filled_stride, filled_stride     );
    TK_HASH( filled_shares + i,                         sizeof(uint32_t)  );
    TK_HASH( fill_price_cents + i,                      sizeof(int64_t)   );
    TK_HASH( fill_notional_cents + i,                   sizeof(int64_t)   );
  }

  TK_HASH( &holding_count, sizeof(uint8_t) );
  for( uint8_t i = 0; i < holding_count; i++ ) {
    TK_HASH( holding_tickers + (ulong)i * filled_stride, filled_stride     );
    TK_HASH( holding_share_counts + i,                   sizeof(uint32_t)  );
    TK_HASH( holding_market_values + i,                  sizeof(int64_t)   );
  }

  return fd_siphash13_fini( sip );
}
