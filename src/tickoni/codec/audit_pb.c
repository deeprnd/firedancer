#include "audit_codec.h"

#include "../../util/log/fd_log.h"
#undef FD_CRIT
#undef FD_LOG_WARNING
#define FD_CRIT(c,...) do { if( FD_UNLIKELY( !(c) ) ) __builtin_trap(); } while(0)
#define FD_LOG_WARNING(a) ((void)0)

#include "../../ballet/pb/fd_pb_encode.h"
#include "../../ballet/pb/fd_pb_tokenize.h"

#include <string.h>

#define TK_AUDIT_FIELD_SCHEMA_VERSION           (1U)
#define TK_AUDIT_FIELD_RECORD_TYPE              (2U)
#define TK_AUDIT_FIELD_SEQ                      (3U)
#define TK_AUDIT_FIELD_SOURCE_OFFSET            (4U)
#define TK_AUDIT_FIELD_TILE_ID                  (5U)
#define TK_AUDIT_FIELD_LOGICAL_ACTOR_ID         (6U)
#define TK_AUDIT_FIELD_POLICY_VERSION           (7U)
#define TK_AUDIT_FIELD_CAPABILITY_ENVELOPE_ID   (8U)
#define TK_AUDIT_FIELD_TIMESTAMP_NS             (9U)
#define TK_AUDIT_FIELD_PREV_HASH                (10U)
#define TK_AUDIT_FIELD_RECORD_HASH              (11U)
#define TK_AUDIT_FIELD_PAYLOAD                  (12U)

static size_t
tk_trimmed_len( unsigned char const * buf,
                size_t                buf_sz ) {
  size_t len = 0UL;
  while( len<buf_sz && buf[len] ) len++;
  return len;
}

static int
tk_trimmed_ascii( unsigned char const * buf,
                  size_t                buf_sz,
                  char *                out,
                  size_t *              out_len ) {
  size_t len = tk_trimmed_len( buf, buf_sz );
  for( size_t i=0UL; i<len; i++ ) {
    unsigned char c = buf[i];
    if( c<0x20U || c>0x7eU ) return TK_AUDIT_CODEC_INVALID_FIELD;
    out[i] = (char)c;
  }
  out[len] = '\0';
  *out_len = len;
  return TK_AUDIT_CODEC_OK;
}

static void
tk_zero_tail( unsigned char * buf,
              size_t          buf_sz,
              size_t          used ) {
  if( used<buf_sz ) memset( buf+used, 0, buf_sz-used );
}

static int
tk_skip_bytes( fd_pb_inbuf_t * buf,
               ulong           len ) {
  if( fd_pb_inbuf_sz( buf )<len ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
  buf->cur += len;
  return TK_AUDIT_CODEC_OK;
}

static int
tk_copy_len_bytes( unsigned char *  dst,
                   size_t           dst_sz,
                   fd_pb_inbuf_t *  buf,
                   ulong            len ) {
  if( len>dst_sz ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
  if( fd_pb_inbuf_sz( buf )<len ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
  memcpy( dst, buf->cur, len );
  tk_zero_tail( dst, dst_sz, (size_t)len );
  buf->cur += len;
  return TK_AUDIT_CODEC_OK;
}

static int
tk_parse_payload( uint                record_type,
                  fd_pb_inbuf_t *     inbuf,
                  tk_audit_payload_t *payload ) {
  fd_pb_tlv_t tlv[1];
  while( fd_pb_inbuf_sz( inbuf ) ) {
    if( FD_UNLIKELY( !fd_pb_read_tlv( inbuf, tlv ) ) ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
    switch( record_type ) {
      case 0U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->source_event.source_system, 16UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->source_event.event_type, 32UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->source_event.raw_hash = (uint64_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 1U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->normalization.source_event_hash = (uint64_t)tlv->varint;
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->normalization.normalized_hash = (uint64_t)tlv->varint;
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->normalization.canonical_event_type, 32UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 2U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->policy_decision.outcome = (uint8_t)tlv->varint;
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->policy_decision.rule_id = (uint32_t)tlv->varint;
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->policy_decision.failed_scope_dim, 32UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 4U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->policy_decision.source_event_hash = (uint64_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 3U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->model_call.model_id, 32UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->model_call.prompt_hash = (uint64_t)tlv->varint;
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->model_call.response_hash = (uint64_t)tlv->varint;
            break;
          case 4U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->model_call.token_estimate = (uint32_t)tlv->varint;
            break;
          case 5U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->model_call.retry_count = (uint8_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 4U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->financial_adapter_call.adapter_id, 16UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->financial_adapter_call.request_hash = (uint64_t)tlv->varint;
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->financial_adapter_call.response_hash = (uint64_t)tlv->varint;
            break;
          case 4U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->financial_adapter_call.fixture_id = (uint32_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 5U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->proposal.proposal_type, 32UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->proposal.proposal_hash = (uint64_t)tlv->varint;
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->proposal.approval_state = (uint8_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 6U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->destination_check.destination_type, 16UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->destination_check.allowlist_version = (uint32_t)tlv->varint;
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->destination_check.outcome = (uint8_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 7U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->limit_check.limit_type = (uint8_t)tlv->varint;
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->limit_check.value = (int64_t)(long)tlv->varint;
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->limit_check.limit = (int64_t)(long)tlv->varint;
            break;
          case 4U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->limit_check.outcome = (uint8_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 8U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->approval_required.action_class, 32UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->approval_required.approval_path, 32UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->approval_required.proposal_hash = (uint64_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 9U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->denial.action_class, 32UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->denial.reason_code = (uint32_t)tlv->varint;
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            {
              int err = tk_copy_len_bytes( payload->denial.failed_scope_dim, 32UL, inbuf, tlv->len );
              if( err ) return err;
            }
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 10U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->telemetry_checkpoint.metric_set_hash = (uint64_t)tlv->varint;
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->telemetry_checkpoint.source_offset_watermark = (uint64_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      case 11U:
        switch( tlv->field_id ) {
          case 1U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->replay_result.capsule_id = (uint64_t)tlv->varint;
            break;
          case 2U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->replay_result.divergences = (uint64_t)tlv->varint;
            break;
          case 3U:
            if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
            payload->replay_result.first_divergent_seq = (uint64_t)tlv->varint;
            break;
          default:
            if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
            break;
        }
        break;
      default:
        return TK_AUDIT_CODEC_INVALID_PROTOBUF;
    }
  }
  return TK_AUDIT_CODEC_OK;
}

int
tk_audit_format_protobuf( void *                   out,
                          size_t                   out_sz,
                          tk_audit_event_t const * event,
                          size_t *                 written ) {
  unsigned char scratch[ 512 ] __attribute__((aligned(32)));
  if( out_sz>sizeof(scratch) ) out_sz = sizeof(scratch);
  fd_pb_encoder_t enc_[1];
  fd_pb_encoder_t * enc = fd_pb_encoder_init( enc_, scratch, out_sz );
  if( FD_UNLIKELY( !enc ) ) return TK_AUDIT_CODEC_NO_SPACE;

  size_t tile_len = tk_trimmed_len( event->header.tile_id, 6UL );
  size_t policy_len = tk_trimmed_len( event->header.policy_version, 32UL );

  if( !fd_pb_push_uint32( enc, TK_AUDIT_FIELD_SCHEMA_VERSION, (uint)event->header.schema_version ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_uint32( enc, TK_AUDIT_FIELD_RECORD_TYPE,    (uint)event->record_type ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_uint64( enc, TK_AUDIT_FIELD_SEQ,            (ulong)event->header.seq ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_uint64( enc, TK_AUDIT_FIELD_SOURCE_OFFSET,  (ulong)event->header.source_offset ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_bytes(  enc, TK_AUDIT_FIELD_TILE_ID,        event->header.tile_id, tile_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_uint64( enc, TK_AUDIT_FIELD_LOGICAL_ACTOR_ID, (ulong)event->header.logical_actor_id ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_bytes(  enc, TK_AUDIT_FIELD_POLICY_VERSION, event->header.policy_version, policy_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_bytes(  enc, TK_AUDIT_FIELD_CAPABILITY_ENVELOPE_ID, event->header.capability_envelope_id_le, 16UL ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_uint64( enc, TK_AUDIT_FIELD_TIMESTAMP_NS,   (ulong)event->header.timestamp_ns ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_uint64( enc, TK_AUDIT_FIELD_PREV_HASH,      (ulong)event->header.prev_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
  if( !fd_pb_push_uint64( enc, TK_AUDIT_FIELD_RECORD_HASH,    (ulong)event->header.record_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;

  if( !fd_pb_submsg_open( enc, TK_AUDIT_FIELD_PAYLOAD ) ) return TK_AUDIT_CODEC_NO_SPACE;
  switch( event->record_type ) {
    case 0U: {
      size_t source_len = tk_trimmed_len( event->payload.source_event.source_system, 16UL );
      size_t event_type_len = tk_trimmed_len( event->payload.source_event.event_type, 32UL );
      if( !fd_pb_push_bytes( enc, 1U, event->payload.source_event.source_system, source_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_bytes( enc, 2U, event->payload.source_event.event_type, event_type_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 3U, (ulong)event->payload.source_event.raw_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    }
    case 1U: {
      size_t event_type_len = tk_trimmed_len( event->payload.normalization.canonical_event_type, 32UL );
      if( !fd_pb_push_uint64( enc, 1U, (ulong)event->payload.normalization.source_event_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 2U, (ulong)event->payload.normalization.normalized_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_bytes( enc, 3U, event->payload.normalization.canonical_event_type, event_type_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    }
    case 2U: {
      size_t failed_dim_len = tk_trimmed_len( event->payload.policy_decision.failed_scope_dim, 32UL );
      if( !fd_pb_push_uint32( enc, 1U, (uint)event->payload.policy_decision.outcome ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint32( enc, 2U, (uint)event->payload.policy_decision.rule_id ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_bytes( enc, 3U, event->payload.policy_decision.failed_scope_dim, failed_dim_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 4U, (ulong)event->payload.policy_decision.source_event_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    }
    case 3U: {
      size_t model_len = tk_trimmed_len( event->payload.model_call.model_id, 32UL );
      if( !fd_pb_push_bytes( enc, 1U, event->payload.model_call.model_id, model_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 2U, (ulong)event->payload.model_call.prompt_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 3U, (ulong)event->payload.model_call.response_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint32( enc, 4U, (uint)event->payload.model_call.token_estimate ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint32( enc, 5U, (uint)event->payload.model_call.retry_count ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    }
    case 4U: {
      size_t adapter_len = tk_trimmed_len( event->payload.financial_adapter_call.adapter_id, 16UL );
      if( !fd_pb_push_bytes( enc, 1U, event->payload.financial_adapter_call.adapter_id, adapter_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 2U, (ulong)event->payload.financial_adapter_call.request_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 3U, (ulong)event->payload.financial_adapter_call.response_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint32( enc, 4U, (uint)event->payload.financial_adapter_call.fixture_id ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    }
    case 5U: {
      size_t proposal_len = tk_trimmed_len( event->payload.proposal.proposal_type, 32UL );
      if( !fd_pb_push_bytes( enc, 1U, event->payload.proposal.proposal_type, proposal_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 2U, (ulong)event->payload.proposal.proposal_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint32( enc, 3U, (uint)event->payload.proposal.approval_state ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    }
    case 6U: {
      size_t dest_len = tk_trimmed_len( event->payload.destination_check.destination_type, 16UL );
      if( !fd_pb_push_bytes( enc, 1U, event->payload.destination_check.destination_type, dest_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint32( enc, 2U, (uint)event->payload.destination_check.allowlist_version ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint32( enc, 3U, (uint)event->payload.destination_check.outcome ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    }
    case 7U:
      if( !fd_pb_push_uint32( enc, 1U, (uint)event->payload.limit_check.limit_type ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_int64( enc, 2U, (long)event->payload.limit_check.value ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_int64( enc, 3U, (long)event->payload.limit_check.limit ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint32( enc, 4U, (uint)event->payload.limit_check.outcome ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    case 8U: {
      size_t action_len = tk_trimmed_len( event->payload.approval_required.action_class, 32UL );
      size_t path_len = tk_trimmed_len( event->payload.approval_required.approval_path, 32UL );
      if( !fd_pb_push_bytes( enc, 1U, event->payload.approval_required.action_class, action_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_bytes( enc, 2U, event->payload.approval_required.approval_path, path_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 3U, (ulong)event->payload.approval_required.proposal_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    }
    case 9U: {
      size_t action_len = tk_trimmed_len( event->payload.denial.action_class, 32UL );
      size_t failed_len = tk_trimmed_len( event->payload.denial.failed_scope_dim, 32UL );
      if( !fd_pb_push_bytes( enc, 1U, event->payload.denial.action_class, action_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint32( enc, 2U, (uint)event->payload.denial.reason_code ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_bytes( enc, 3U, event->payload.denial.failed_scope_dim, failed_len ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    }
    case 10U:
      if( !fd_pb_push_uint64( enc, 1U, (ulong)event->payload.telemetry_checkpoint.metric_set_hash ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 2U, (ulong)event->payload.telemetry_checkpoint.source_offset_watermark ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    case 11U:
      if( !fd_pb_push_uint64( enc, 1U, (ulong)event->payload.replay_result.capsule_id ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 2U, (ulong)event->payload.replay_result.divergences ) ) return TK_AUDIT_CODEC_NO_SPACE;
      if( !fd_pb_push_uint64( enc, 3U, (ulong)event->payload.replay_result.first_divergent_seq ) ) return TK_AUDIT_CODEC_NO_SPACE;
      break;
    default:
      return TK_AUDIT_CODEC_INVALID_FIELD;
  }
  if( !fd_pb_submsg_close( enc ) ) return TK_AUDIT_CODEC_NO_SPACE;
  *written = (size_t)( enc->cur - enc->buf0 );
  if( !fd_pb_encoder_fini( enc ) ) return TK_AUDIT_CODEC_NO_SPACE;
  memcpy( out, scratch, *written );
  return TK_AUDIT_CODEC_OK;
}

int
tk_audit_parse_protobuf( void const *       in,
                         size_t             in_sz,
                         tk_audit_event_t * event ) {
  memset( event, 0, sizeof(*event) );

  fd_pb_inbuf_t inbuf_[1];
  fd_pb_inbuf_t * inbuf = fd_pb_inbuf_init( inbuf_, in, in_sz );
  fd_pb_tlv_t tlv[1];

  while( fd_pb_inbuf_sz( inbuf ) ) {
    if( FD_UNLIKELY( !fd_pb_read_tlv( inbuf, tlv ) ) ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
    switch( tlv->field_id ) {
      case TK_AUDIT_FIELD_SCHEMA_VERSION:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        event->header.schema_version = (uint16_t)tlv->varint;
        break;
      case TK_AUDIT_FIELD_RECORD_TYPE:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        event->record_type = (uint8_t)tlv->varint;
        break;
      case TK_AUDIT_FIELD_SEQ:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        event->header.seq = (uint64_t)tlv->varint;
        break;
      case TK_AUDIT_FIELD_SOURCE_OFFSET:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        event->header.source_offset = (uint64_t)tlv->varint;
        break;
      case TK_AUDIT_FIELD_TILE_ID:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        {
          int err = tk_copy_len_bytes( event->header.tile_id, 6UL, inbuf, tlv->len );
          if( err ) return err;
        }
        break;
      case TK_AUDIT_FIELD_LOGICAL_ACTOR_ID:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        event->header.logical_actor_id = (uint64_t)tlv->varint;
        break;
      case TK_AUDIT_FIELD_POLICY_VERSION:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        {
          int err = tk_copy_len_bytes( event->header.policy_version, 32UL, inbuf, tlv->len );
          if( err ) return err;
        }
        break;
      case TK_AUDIT_FIELD_CAPABILITY_ENVELOPE_ID:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        {
          int err = tk_copy_len_bytes( event->header.capability_envelope_id_le, 16UL, inbuf, tlv->len );
          if( err ) return err;
        }
        break;
      case TK_AUDIT_FIELD_TIMESTAMP_NS:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        event->header.timestamp_ns = (uint64_t)tlv->varint;
        break;
      case TK_AUDIT_FIELD_PREV_HASH:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        event->header.prev_hash = (uint64_t)tlv->varint;
        break;
      case TK_AUDIT_FIELD_RECORD_HASH:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_VARINT ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        event->header.record_hash = (uint64_t)tlv->varint;
        break;
      case TK_AUDIT_FIELD_PAYLOAD:
        if( tlv->wire_type!=FD_PB_WIRE_TYPE_LEN ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        if( fd_pb_inbuf_sz( inbuf )<tlv->len ) return TK_AUDIT_CODEC_INVALID_PROTOBUF;
        if( event->record_type>11U ) {
          inbuf->cur += tlv->len;
        } else {
          fd_pb_inbuf_t payload_buf_[1];
          fd_pb_inbuf_t * payload_buf = fd_pb_inbuf_init( payload_buf_, inbuf->cur, tlv->len );
          int err = tk_parse_payload( event->record_type, payload_buf, &event->payload );
          if( err ) return err;
          inbuf->cur += tlv->len;
        }
        break;
      default:
        if( tlv->wire_type==FD_PB_WIRE_TYPE_LEN ) tk_skip_bytes( inbuf, tlv->len );
        break;
    }
  }

  return TK_AUDIT_CODEC_OK;
}
