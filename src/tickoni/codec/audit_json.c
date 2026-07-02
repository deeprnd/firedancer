#include "audit_codec.h"
#include "../c_abi/shim/firedancer.h"

#include <stdio.h>
#include <string.h>

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

static char const *
tk_record_type_name( uint8_t record_type ) {
  switch( record_type ) {
    case 0U: return "source_event";
    case 1U: return "normalization";
    case 2U: return "policy_decision";
    case 3U: return "model_call";
    case 4U: return "financial_adapter_call";
    case 5U: return "proposal";
    case 6U: return "destination_check";
    case 7U: return "limit_check";
    case 8U: return "approval_required";
    case 9U: return "denial";
    case 10U: return "telemetry_checkpoint";
    case 11U: return "replay_result";
    default: return NULL;
  }
}

static char const *
tk_policy_outcome_name( uint8_t outcome ) {
  switch( outcome ) {
    case 0U: return "allow";
    case 1U: return "deny";
    case 2U: return "require_approval";
    case 3U: return "malformed_drop";
    case 4U: return "duplicate_drop";
    case 5U: return "escalate";
    case 6U: return "require_more_evidence";
    default: return NULL;
  }
}

static char const *
tk_limit_type_name( uint8_t limit_type ) {
  switch( limit_type ) {
    case 0U: return "amount";
    case 1U: return "frequency";
    case 2U: return "holding_period";
    case 3U: return "per_day";
    case 4U: return "per_month";
    default: return NULL;
  }
}

static int
tk_add_raw_number( tk_json_t *   obj,
                   char const *  key,
                   char const *  value ) {
  tk_json_t * raw = tk_json_create_raw( value );
  if( !raw ) return TK_AUDIT_CODEC_INVALID_JSON;
  tk_json_add_item_to_object( obj, key, raw );
  return TK_AUDIT_CODEC_OK;
}

static int
tk_add_u64( tk_json_t *   obj,
            char const *  key,
            uint64_t      value ) {
  char buf[ 32 ];
  int len = snprintf( buf, sizeof(buf), "%llu", (unsigned long long)value );
  if( len<0 || (size_t)len>=sizeof(buf) ) return TK_AUDIT_CODEC_INVALID_JSON;
  return tk_add_raw_number( obj, key, buf );
}

static int
tk_add_u32( tk_json_t *   obj,
            char const *  key,
            uint32_t      value ) {
  return tk_add_u64( obj, key, (uint64_t)value );
}

static int
tk_add_i64( tk_json_t *   obj,
            char const *  key,
            int64_t       value ) {
  char buf[ 32 ];
  int len = snprintf( buf, sizeof(buf), "%lld", (long long)value );
  if( len<0 || (size_t)len>=sizeof(buf) ) return TK_AUDIT_CODEC_INVALID_JSON;
  return tk_add_raw_number( obj, key, buf );
}

static int
tk_add_u128_le( tk_json_t *           obj,
                char const *          key,
                unsigned char const * value_le ) {
  unsigned __int128 value = 0;
  for( int i=15; i>=0; i-- ) value = ( value<<8 ) | value_le[i];

  char digits[ 40 ];
  size_t pos = sizeof(digits);
  digits[ --pos ] = '\0';
  if( !value ) {
    digits[ --pos ] = '0';
  } else {
    while( value ) {
      digits[ --pos ] = (char)('0' + ( value % 10 ));
      value /= 10;
    }
  }
  return tk_add_raw_number( obj, key, digits+pos );
}

static int
tk_add_string( tk_json_t *           obj,
               char const *          key,
               unsigned char const * value,
               size_t                value_sz ) {
  char buf[ 33 ];
  size_t len = 0UL;
  int err = tk_trimmed_ascii( value, value_sz, buf, &len );
  if( err ) return err;
  (void)len;
  if( !tk_json_add_string_to_object( obj, key, buf ) ) return TK_AUDIT_CODEC_INVALID_JSON;
  return TK_AUDIT_CODEC_OK;
}

int
tk_audit_format_jsonl( char *                    out,
                       size_t                    out_sz,
                       tk_audit_event_t const *  event,
                       size_t *                  written ) {
  int err = TK_AUDIT_CODEC_OK;
  tk_json_t * root = tk_json_create_object();
  if( !root ) return TK_AUDIT_CODEC_INVALID_JSON;

  char const * record_type_name = tk_record_type_name( event->record_type );
  if( !record_type_name ) {
    tk_json_delete( root );
    return TK_AUDIT_CODEC_INVALID_FIELD;
  }

  if( !( err = tk_add_u32( root, "schema_version", event->header.schema_version ) ) &&
      !( err = ( tk_json_add_string_to_object( root, "record_type", record_type_name ) ? TK_AUDIT_CODEC_OK : TK_AUDIT_CODEC_INVALID_JSON ) ) &&
      !( err = tk_add_u64( root, "seq", event->header.seq ) ) &&
      !( err = tk_add_u64( root, "source_offset", event->header.source_offset ) ) &&
      !( err = tk_add_string( root, "tile_id", event->header.tile_id, 6UL ) ) &&
      !( err = tk_add_u64( root, "logical_actor_id", event->header.logical_actor_id ) ) &&
      !( err = tk_add_string( root, "policy_version", event->header.policy_version, 32UL ) ) &&
      !( err = tk_add_u128_le( root, "capability_envelope_id", event->header.capability_envelope_id_le ) ) &&
      !( err = tk_add_u64( root, "timestamp_ns", event->header.timestamp_ns ) ) &&
      !( err = tk_add_u64( root, "prev_hash", event->header.prev_hash ) ) &&
      !( err = tk_add_u64( root, "record_hash", event->header.record_hash ) ) ) {
    switch( event->record_type ) {
      case 0U:
        err = tk_add_string( root, "source_system", event->payload.source_event.source_system, 16UL );
        if( !err ) err = tk_add_string( root, "event_type", event->payload.source_event.event_type, 32UL );
        if( !err ) err = tk_add_u64( root, "raw_hash", event->payload.source_event.raw_hash );
        break;
      case 1U:
        err = tk_add_u64( root, "source_event_hash", event->payload.normalization.source_event_hash );
        if( !err ) err = tk_add_u64( root, "normalized_hash", event->payload.normalization.normalized_hash );
        if( !err ) err = tk_add_string( root, "canonical_event_type", event->payload.normalization.canonical_event_type, 32UL );
        break;
      case 2U: {
        char const * outcome = tk_policy_outcome_name( event->payload.policy_decision.outcome );
        if( !outcome ) err = TK_AUDIT_CODEC_INVALID_FIELD;
        if( !err && !tk_json_add_string_to_object( root, "outcome", outcome ) ) err = TK_AUDIT_CODEC_INVALID_JSON;
        if( !err ) err = tk_add_u32( root, "rule_id", event->payload.policy_decision.rule_id );
        if( !err ) err = tk_add_string( root, "failed_scope_dim", event->payload.policy_decision.failed_scope_dim, 32UL );
        if( !err ) err = tk_add_u64( root, "source_event_hash", event->payload.policy_decision.source_event_hash );
        break;
      }
      case 3U:
        err = tk_add_string( root, "model_id", event->payload.model_call.model_id, 32UL );
        if( !err ) err = tk_add_u64( root, "prompt_hash", event->payload.model_call.prompt_hash );
        if( !err ) err = tk_add_u64( root, "response_hash", event->payload.model_call.response_hash );
        if( !err ) err = tk_add_u32( root, "token_estimate", event->payload.model_call.token_estimate );
        if( !err ) err = tk_add_u32( root, "retry_count", event->payload.model_call.retry_count );
        if( !err ) err = tk_add_string( root, "actor_role", event->payload.model_call.actor_role, 16UL );
        if( !err ) err = tk_add_string( root, "workflow", event->payload.model_call.workflow, 16UL );
        if( !err ) err = tk_add_u64( root, "policy_decision_id", event->payload.model_call.policy_decision_id );
        if( !err ) err = tk_add_u64( root, "replay_substitution_id", event->payload.model_call.replay_substitution_id );
        break;
      case 4U:
        err = tk_add_string( root, "adapter_id", event->payload.financial_adapter_call.adapter_id, 16UL );
        if( !err ) err = tk_add_u64( root, "request_hash", event->payload.financial_adapter_call.request_hash );
        if( !err ) err = tk_add_u64( root, "response_hash", event->payload.financial_adapter_call.response_hash );
        if( !err ) err = tk_add_u32( root, "fixture_id", event->payload.financial_adapter_call.fixture_id );
        break;
      case 5U:
        err = tk_add_string( root, "proposal_type", event->payload.proposal.proposal_type, 32UL );
        if( !err ) err = tk_add_u64( root, "proposal_hash", event->payload.proposal.proposal_hash );
        if( !err ) err = tk_add_u32( root, "approval_state", event->payload.proposal.approval_state );
        break;
      case 6U: {
        char const * outcome = tk_policy_outcome_name( event->payload.destination_check.outcome );
        if( !outcome ) err = TK_AUDIT_CODEC_INVALID_FIELD;
        if( !err ) err = tk_add_string( root, "destination_type", event->payload.destination_check.destination_type, 16UL );
        if( !err ) err = tk_add_u32( root, "allowlist_version", event->payload.destination_check.allowlist_version );
        if( !err && !tk_json_add_string_to_object( root, "outcome", outcome ) ) err = TK_AUDIT_CODEC_INVALID_JSON;
        break;
      }
      case 7U: {
        char const * limit_type = tk_limit_type_name( event->payload.limit_check.limit_type );
        char const * outcome = tk_policy_outcome_name( event->payload.limit_check.outcome );
        if( !limit_type || !outcome ) err = TK_AUDIT_CODEC_INVALID_FIELD;
        if( !err && !tk_json_add_string_to_object( root, "limit_type", limit_type ) ) err = TK_AUDIT_CODEC_INVALID_JSON;
        if( !err ) err = tk_add_i64( root, "value", event->payload.limit_check.value );
        if( !err ) err = tk_add_i64( root, "limit", event->payload.limit_check.limit );
        if( !err && !tk_json_add_string_to_object( root, "outcome", outcome ) ) err = TK_AUDIT_CODEC_INVALID_JSON;
        break;
      }
      case 8U:
        err = tk_add_string( root, "action_class", event->payload.approval_required.action_class, 32UL );
        if( !err ) err = tk_add_string( root, "approval_path", event->payload.approval_required.approval_path, 32UL );
        if( !err ) err = tk_add_u64( root, "proposal_hash", event->payload.approval_required.proposal_hash );
        break;
      case 9U:
        err = tk_add_string( root, "action_class", event->payload.denial.action_class, 32UL );
        if( !err ) err = tk_add_u32( root, "reason_code", event->payload.denial.reason_code );
        if( !err ) err = tk_add_string( root, "failed_scope_dim", event->payload.denial.failed_scope_dim, 32UL );
        break;
      case 10U:
        err = tk_add_u64( root, "metric_set_hash", event->payload.telemetry_checkpoint.metric_set_hash );
        if( !err ) err = tk_add_u64( root, "source_offset_watermark", event->payload.telemetry_checkpoint.source_offset_watermark );
        break;
      case 11U:
        err = tk_add_u64( root, "capsule_id", event->payload.replay_result.capsule_id );
        if( !err ) err = tk_add_u64( root, "divergences", event->payload.replay_result.divergences );
        if( !err ) err = tk_add_u64( root, "first_divergent_seq", event->payload.replay_result.first_divergent_seq );
        break;
      default:
        err = TK_AUDIT_CODEC_INVALID_FIELD;
        break;
    }
  }

  if( !err ) {
    if( out_sz<2UL ) {
      err = TK_AUDIT_CODEC_NO_SPACE;
    } else if( !tk_json_print_preallocated( root, out, (int)( out_sz-1UL ), 0 ) ) {
      err = TK_AUDIT_CODEC_NO_SPACE;
    } else {
      size_t len = strlen( out );
      if( len+1UL>=out_sz ) {
        err = TK_AUDIT_CODEC_NO_SPACE;
      } else {
        out[len] = '\n';
        out[len+1UL] = '\0';
        *written = len+1UL;
      }
    }
  }

  tk_json_delete( root );
  return err;
}
