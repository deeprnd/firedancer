/* Thin wrappers around Firedancer Ballet protobuf/hash primitives and the
   vendored JSON implementation. Tickoni callers see only tk_* symbols. */

#include "firedancer.h"

#include "third_party/cjson/cJSON.h"
#include "../../../ballet/pb/fd_pb_encode.h"
#include "../../../ballet/pb/fd_pb_tokenize.h"
#include "../../../ballet/siphash13/fd_siphash13.h"

#include <stddef.h>

_Static_assert( sizeof(tk_siphash13_t)==sizeof(fd_siphash13_t), "siphash size mismatch" );
_Static_assert( _Alignof(tk_siphash13_t)==_Alignof(fd_siphash13_t), "siphash align mismatch" );
_Static_assert( sizeof(tk_pb_encoder_t)==sizeof(fd_pb_encoder_t), "pb encoder size mismatch" );
_Static_assert( offsetof(tk_pb_encoder_t, cur)==offsetof(fd_pb_encoder_t, cur), "pb encoder layout mismatch" );
_Static_assert( sizeof(tk_pb_inbuf_t)==sizeof(fd_pb_inbuf_t), "pb inbuf size mismatch" );
_Static_assert( offsetof(tk_pb_inbuf_t, cur)==offsetof(fd_pb_inbuf_t, cur), "pb inbuf layout mismatch" );
_Static_assert( sizeof(tk_pb_tlv_t)==sizeof(fd_pb_tlv_t), "pb tlv size mismatch" );
_Static_assert( offsetof(tk_pb_tlv_t, field_id)==offsetof(fd_pb_tlv_t, field_id), "pb tlv layout mismatch" );

struct tk_json {
  cJSON inner;
};

tk_siphash13_t *
tk_siphash13_init( tk_siphash13_t * sip,
                   uint64_t         k0,
                   uint64_t         k1 ) {
  return (tk_siphash13_t *)fd_siphash13_init( (fd_siphash13_t *)sip, (ulong)k0, (ulong)k1 );
}

tk_siphash13_t *
tk_siphash13_append( tk_siphash13_t * sip,
                     void const *     data,
                     uint64_t         sz ) {
  return (tk_siphash13_t *)fd_siphash13_append( (fd_siphash13_t *)sip, (uchar const *)data, (ulong)sz );
}

uint64_t
tk_siphash13_fini( tk_siphash13_t * sip ) {
  return (uint64_t)fd_siphash13_fini( (fd_siphash13_t *)sip );
}

tk_pb_encoder_t *
tk_pb_encoder_init( tk_pb_encoder_t * encoder,
                    void *            out,
                    uint64_t          out_sz ) {
  return (tk_pb_encoder_t *)fd_pb_encoder_init( (fd_pb_encoder_t *)encoder, (uchar *)out, (ulong)out_sz );
}

int
tk_pb_encoder_fini( tk_pb_encoder_t * encoder ) {
  return !!fd_pb_encoder_fini( (fd_pb_encoder_t *)encoder );
}

uint64_t
tk_pb_encoder_out_sz( tk_pb_encoder_t * encoder ) {
  return (uint64_t)fd_pb_encoder_out_sz( (fd_pb_encoder_t *)encoder );
}

int
tk_pb_submsg_open( tk_pb_encoder_t * encoder,
                   uint32_t          field_id ) {
  return !!fd_pb_submsg_open( (fd_pb_encoder_t *)encoder, (uint)field_id );
}

int
tk_pb_submsg_close( tk_pb_encoder_t * encoder ) {
  return !!fd_pb_submsg_close( (fd_pb_encoder_t *)encoder );
}

int
tk_pb_push_uint32( tk_pb_encoder_t * encoder,
                   uint32_t          field_id,
                   uint32_t          value ) {
  return !!fd_pb_push_uint32( (fd_pb_encoder_t *)encoder, (uint)field_id, (uint)value );
}

int
tk_pb_push_uint64( tk_pb_encoder_t * encoder,
                   uint32_t          field_id,
                   uint64_t          value ) {
  return !!fd_pb_push_uint64( (fd_pb_encoder_t *)encoder, (uint)field_id, (ulong)value );
}

int
tk_pb_push_int64( tk_pb_encoder_t * encoder,
                  uint32_t          field_id,
                  int64_t           value ) {
  return !!fd_pb_push_int64( (fd_pb_encoder_t *)encoder, (uint)field_id, (long)value );
}

int
tk_pb_push_bytes( tk_pb_encoder_t * encoder,
                  uint32_t          field_id,
                  void const *      bytes,
                  uint64_t          bytes_sz ) {
  return !!fd_pb_push_bytes( (fd_pb_encoder_t *)encoder, (uint)field_id, bytes, (ulong)bytes_sz );
}

tk_pb_inbuf_t *
tk_pb_inbuf_init( tk_pb_inbuf_t * buf,
                  void const *     data,
                  uint64_t         data_sz ) {
  return (tk_pb_inbuf_t *)fd_pb_inbuf_init( (fd_pb_inbuf_t *)buf, data, (ulong)data_sz );
}

uint64_t
tk_pb_inbuf_sz( tk_pb_inbuf_t * buf ) {
  return (uint64_t)fd_pb_inbuf_sz( (fd_pb_inbuf_t *)buf );
}

uint8_t const *
tk_pb_inbuf_cur( tk_pb_inbuf_t * buf ) {
  return buf->cur;
}

void
tk_pb_inbuf_advance( tk_pb_inbuf_t * buf,
                     uint64_t        bytes_sz ) {
  buf->cur += bytes_sz;
}

int
tk_pb_read_tlv( tk_pb_inbuf_t * buf,
                tk_pb_tlv_t *   tlv ) {
  return !!fd_pb_read_tlv( (fd_pb_inbuf_t *)buf, (fd_pb_tlv_t *)tlv );
}

tk_json_t *
tk_json_create_object( void ) {
  return (tk_json_t *)cJSON_CreateObject();
}

tk_json_t *
tk_json_create_raw( char const * value ) {
  return (tk_json_t *)cJSON_CreateRaw( value );
}

void
tk_json_delete( tk_json_t * item ) {
  cJSON_Delete( (cJSON *)item );
}

void
tk_json_add_item_to_object( tk_json_t *  obj,
                            char const * key,
                            tk_json_t *  item ) {
  cJSON_AddItemToObject( (cJSON *)obj, key, (cJSON *)item );
}

int
tk_json_add_string_to_object( tk_json_t *  obj,
                              char const * key,
                              char const * value ) {
  return !!cJSON_AddStringToObject( (cJSON *)obj, key, value );
}

int
tk_json_print_preallocated( tk_json_t * item,
                            char *      out,
                            int         out_sz,
                            int         format ) {
  return cJSON_PrintPreallocated( (cJSON *)item, out, out_sz, format );
}
