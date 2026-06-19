#ifndef HEADER_fd_src_tickoni_codec_audit_codec_h
#define HEADER_fd_src_tickoni_codec_audit_codec_h

#include <stddef.h>
#include <stdint.h>

enum {
  TK_AUDIT_CODEC_OK = 0,
  TK_AUDIT_CODEC_NO_SPACE = 1,
  TK_AUDIT_CODEC_INVALID_PROTOBUF = 2,
  TK_AUDIT_CODEC_INVALID_JSON = 3,
  TK_AUDIT_CODEC_INVALID_FIELD = 4,
};

typedef struct {
  uint16_t schema_version;
  uint64_t run_id;
  uint64_t seq;
  uint64_t source_offset;
  unsigned char tile_id[ 6 ];
  uint64_t logical_actor_id;
  unsigned char policy_version[ 32 ];
  unsigned char capability_envelope_id_le[ 16 ];
  uint64_t timestamp_ns;
  uint64_t prev_hash;
  uint64_t record_hash;
} tk_audit_header_t;

typedef struct {
  unsigned char source_system[ 16 ];
  unsigned char event_type[ 32 ];
  uint64_t raw_hash;
} tk_audit_source_event_t;

typedef struct {
  uint64_t source_event_hash;
  uint64_t normalized_hash;
  unsigned char canonical_event_type[ 32 ];
} tk_audit_normalization_t;

typedef struct {
  uint8_t outcome;
  uint32_t rule_id;
  unsigned char failed_scope_dim[ 32 ];
  uint64_t source_event_hash;
} tk_audit_policy_decision_t;

typedef struct {
  unsigned char model_id[ 32 ];
  uint64_t prompt_hash;
  uint64_t response_hash;
  uint32_t token_estimate;
  uint8_t retry_count;
} tk_audit_model_call_t;

typedef struct {
  unsigned char adapter_id[ 16 ];
  uint64_t request_hash;
  uint64_t response_hash;
  uint32_t fixture_id;
} tk_audit_financial_adapter_call_t;

typedef struct {
  unsigned char proposal_type[ 32 ];
  uint64_t proposal_hash;
  uint8_t approval_state;
} tk_audit_proposal_t;

typedef struct {
  unsigned char destination_type[ 16 ];
  uint32_t allowlist_version;
  uint8_t outcome;
} tk_audit_destination_check_t;

typedef struct {
  uint8_t limit_type;
  int64_t value;
  int64_t limit;
  uint8_t outcome;
} tk_audit_limit_check_t;

typedef struct {
  unsigned char action_class[ 32 ];
  unsigned char approval_path[ 32 ];
  uint64_t proposal_hash;
} tk_audit_approval_required_t;

typedef struct {
  unsigned char action_class[ 32 ];
  uint32_t reason_code;
  unsigned char failed_scope_dim[ 32 ];
} tk_audit_denial_t;

typedef struct {
  uint64_t metric_set_hash;
  uint64_t source_offset_watermark;
} tk_audit_telemetry_checkpoint_t;

typedef struct {
  uint64_t capsule_id;
  uint64_t divergences;
  uint64_t first_divergent_seq;
} tk_audit_replay_result_t;

typedef struct {
  uint64_t idempotency_key;
  uint8_t  is_duplicate;
} tk_audit_deduplication_t;

typedef struct {
  uint64_t basket_id;
  uint8_t  instrument_count;
  uint8_t  rejected_count;
  int64_t  total_allocated_cents;
} tk_audit_case_creation_t;

typedef union {
  tk_audit_source_event_t source_event;
  tk_audit_normalization_t normalization;
  tk_audit_policy_decision_t policy_decision;
  tk_audit_model_call_t model_call;
  tk_audit_financial_adapter_call_t financial_adapter_call;
  tk_audit_proposal_t proposal;
  tk_audit_destination_check_t destination_check;
  tk_audit_limit_check_t limit_check;
  tk_audit_approval_required_t approval_required;
  tk_audit_denial_t denial;
  tk_audit_telemetry_checkpoint_t telemetry_checkpoint;
  tk_audit_replay_result_t replay_result;
  tk_audit_deduplication_t deduplication;
  tk_audit_case_creation_t case_creation;
} tk_audit_payload_t;

typedef struct {
  tk_audit_header_t header;
  uint8_t record_type;
  tk_audit_payload_t payload;
} tk_audit_event_t;

uint64_t
tk_audit_record_hash( tk_audit_event_t const * event );

int
tk_audit_peek_binary_len( void const * in,
                          size_t       in_sz,
                          size_t *     out_total_len );

int
tk_audit_format_protobuf( void *                    out,
                          size_t                    out_sz,
                          tk_audit_event_t const *  event,
                          size_t *                  written );

int
tk_audit_parse_protobuf( void const *        in,
                         size_t              in_sz,
                         tk_audit_event_t *  event );

int
tk_audit_format_jsonl( char *                     out,
                       size_t                     out_sz,
                       tk_audit_event_t const *   event,
                       size_t *                   written );

#endif /* HEADER_fd_src_tickoni_codec_audit_codec_h */
