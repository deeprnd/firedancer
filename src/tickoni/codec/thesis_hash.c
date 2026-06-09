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
                      uint8_t               asset_class_prefs,
                      uint8_t               sector_theme,
                      uint8_t               risk_preference,
                      uint8_t               max_single_name_pct,
                      uint8_t               exclusions ) {
  fd_siphash13_t _sip[1];
  fd_siphash13_t * sip = fd_siphash13_init( _sip, TK_THESIS_HASH_K0, TK_THESIS_HASH_K1 );

  /* Structured identity fields first, then user text. */
  uint16_t ver = TK_THESIS_SCHEMA_VERSION;
  TK_HASH( &ver,                   sizeof(uint16_t) );
  TK_HASH( &account_id,            sizeof(uint32_t) );
  TK_HASH( &target_notional_cents, sizeof(int64_t)  );
  TK_HASH( &market_scope,          sizeof(uint8_t)  );
  TK_HASH( &asset_class_prefs,     sizeof(uint8_t)  );
  TK_HASH( &sector_theme,          sizeof(uint8_t)  );
  TK_HASH( &risk_preference,       sizeof(uint8_t)  );
  TK_HASH( &max_single_name_pct,   sizeof(uint8_t)  );
  TK_HASH( &exclusions,            sizeof(uint8_t)  );
  /* user_text follows so two different phrasings of the same thesis are
     distinguishable at the source-event level even when intent normalizes
     identically. */
  TK_HASH( &user_text_len,         sizeof(uint16_t)     );
  TK_HASH( user_text,              (ulong)user_text_len );

  return fd_siphash13_fini( sip );
}
