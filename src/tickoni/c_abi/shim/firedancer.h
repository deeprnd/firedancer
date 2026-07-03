#ifndef HEADER_fd_src_tickoni_c_abi_shim_firedancer_h
#define HEADER_fd_src_tickoni_c_abi_shim_firedancer_h

#include <stddef.h>
#include <stdint.h>

#define TK_PB_WIRE_TYPE_VARINT (0U)
#define TK_PB_WIRE_TYPE_I64    (1U)
#define TK_PB_WIRE_TYPE_LEN    (2U)
#define TK_PB_WIRE_TYPE_I32    (5U)

#define TK_PB_ENCODER_DEPTH_MAX (63UL)

typedef struct {
  uint8_t bytes[ 128 ];
} __attribute__((aligned(128))) tk_siphash13_t;

typedef struct {
  uint8_t * buf0;
  uint8_t * buf1;
  uint8_t * cur;
  uint32_t  depth;
  uint32_t  lp_off[ TK_PB_ENCODER_DEPTH_MAX ];
} tk_pb_encoder_t;

typedef struct {
  uint8_t const * cur;
  uint8_t const * end;
} tk_pb_inbuf_t;

typedef struct {
  uint32_t wire_type;
  uint32_t field_id;
  union {
    uint64_t varint;
    uint64_t i64;
    uint64_t len;
    uint32_t i32;
  };
} tk_pb_tlv_t;

typedef struct tk_json tk_json_t;

tk_siphash13_t *
tk_siphash13_init( tk_siphash13_t * sip,
                   uint64_t         k0,
                   uint64_t         k1 );

tk_siphash13_t *
tk_siphash13_append( tk_siphash13_t * sip,
                     void const *     data,
                     uint64_t         sz );

uint64_t
tk_siphash13_fini( tk_siphash13_t * sip );

tk_pb_encoder_t *
tk_pb_encoder_init( tk_pb_encoder_t * encoder,
                    void *            out,
                    uint64_t          out_sz );

int
tk_pb_encoder_fini( tk_pb_encoder_t * encoder );

uint64_t
tk_pb_encoder_out_sz( tk_pb_encoder_t * encoder );

int
tk_pb_submsg_open( tk_pb_encoder_t * encoder,
                   uint32_t          field_id );

int
tk_pb_submsg_close( tk_pb_encoder_t * encoder );

int
tk_pb_push_uint32( tk_pb_encoder_t * encoder,
                   uint32_t          field_id,
                   uint32_t          value );

int
tk_pb_push_uint64( tk_pb_encoder_t * encoder,
                   uint32_t          field_id,
                   uint64_t          value );

int
tk_pb_push_int64( tk_pb_encoder_t * encoder,
                  uint32_t          field_id,
                  int64_t           value );

int
tk_pb_push_bytes( tk_pb_encoder_t * encoder,
                  uint32_t          field_id,
                  void const *      bytes,
                  uint64_t          bytes_sz );

tk_pb_inbuf_t *
tk_pb_inbuf_init( tk_pb_inbuf_t * buf,
                  void const *     data,
                  uint64_t         data_sz );

uint64_t
tk_pb_inbuf_sz( tk_pb_inbuf_t * buf );

uint8_t const *
tk_pb_inbuf_cur( tk_pb_inbuf_t * buf );

void
tk_pb_inbuf_advance( tk_pb_inbuf_t * buf,
                     uint64_t        bytes_sz );

int
tk_pb_read_tlv( tk_pb_inbuf_t * buf,
                tk_pb_tlv_t *   tlv );

tk_json_t *
tk_json_create_object( void );

tk_json_t *
tk_json_create_raw( char const * value );

void
tk_json_delete( tk_json_t * item );

void
tk_json_add_item_to_object( tk_json_t *  obj,
                            char const * key,
                            tk_json_t *  item );

int
tk_json_add_string_to_object( tk_json_t *  obj,
                              char const * key,
                              char const * value );

int
tk_json_print_preallocated( tk_json_t * item,
                            char *      out,
                            int         out_sz,
                            int         format );

#endif /* HEADER_fd_src_tickoni_c_abi_shim_firedancer_h */
