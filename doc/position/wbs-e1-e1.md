E1.S1: Audit Record Schema — Implementation Plan
What to read before touching code
File	Lines	Why
payment_pipeline.zig:46-54	AuditRecord struct	This is the Phase 0 spike record; E1.S1 evolves it
payment_pipeline.zig:483-492	auditHash()	The current hash function; understand its field ordering
payment_pipeline.zig:597-618	AuditLog.append()	How records are built and chained today
payment_pipeline.zig:411-447	deterministicReplayDivergences()	Replay comparison depends on record shape
doc/architecture.md:306-328	Audit journal spec	Authoritative list of required header fields
doc/position/wbs.md:88-103	E1.S1 tasks	The work item being planned
doc/position/wbs.md:199-216	E3.S1 capability envelope	capability_envelope_id comes from here — reserve the field now
src/tickoni/runtime/topology.zig:68	TileId for tkaudt	The tile_id header field type is defined here
New file to create
src/tickoni/tiles/audit.zig — canonical schema, hashing, encoding, and tests.

The existing AuditRecord, AuditLog, auditHash(), buildAuditRecord(), and formatAuditJsonl() in payment_pipeline.zig become the starting point. They migrate to audit.zig and are extended per T1–T3. payment_pipeline.zig becomes an importer.

T1: Define all audit record types
Gap: The current AuditRecord (7 fields, payment-specific) conflates source ingestion, normalization, deduplication, and policy decision into one struct using PolicyDecision. Phase 1 adds model calls, adapter calls, proposals, approvals, denials, destination checks, limit checks, telemetry checkpoints, and replay results — none of which fit a payment-shaped struct without becoming a bag of optional fields.

Design: A Zig tagged union AuditEvent with a common Header embedded in each variant and a per-type payload. Tagged unions give exhaustive switch coverage, so adding a new type forces every consumer to handle it explicitly.

Record types to define (per WBS T1):

Tag	Owning tile	Payload fields
source_event	tkings	source_system, event_type, raw_hash
normalization	tknorm	source_event_hash, normalized_hash, canonical_event_type
policy_decision	tkpoly	outcome (allow/deny/require_approval/malformed_drop/duplicate_drop/escalate), rule_id, failed_scope_dim
model_call	tkmodl (stub)	model_id, prompt_hash, response_hash, token_estimate, retry_count
financial_adapter_call	tkadpt (stub)	adapter_id, request_hash, response_hash, fixture_id
proposal	tkagnt (stub)	proposal_type, proposal_hash, approval_state
destination_check	tkpoly	destination_type, allowlist_version, outcome
limit_check	tkpoly	limit_type (amount/frequency/holding_period), value, limit, outcome
approval_required	tkpoly	action_class, approval_path, proposal_hash
denial	tkpoly	action_class, reason_code, failed_scope_dim
telemetry_checkpoint	tkmetr	metric_set_hash, source_offset_watermark
replay_result	tkrepl	capsule_id, divergences, first_divergent_seq
Phase 1 stubs (model_call, financial_adapter_call, proposal, approval_required) carry the correct header but minimal payloads. They will be filled out by E4.S1, E5.S2, and E5.S3–S4 respectively.

Key decision: The existing PolicyDecision enum in payment_pipeline.zig covers only payment-pipeline outcomes. The policy_decision record needs a broader PolicyOutcome enum: allow, deny, require_approval, malformed_drop, duplicate_drop, escalate, require_more_evidence. Define PolicyOutcome in audit.zig, then alias it back into the pipeline.

T2: Include the required header fields
Gap: The current AuditRecord is missing five of the eight header fields the architecture requires.

Field	Status	Notes
seq	present	monotonic append sequence
source_offset	present	from tkings
tile_id	missing	which tile emitted this record; use [6]u8 matching TileId
logical_actor_id	missing	service identity or agent role; u64 or [32]u8; zero for system events
policy_version	missing	versioned policy in effect; [32]u8 or u32 — pick one stable form
capability_envelope_id	missing	reserved as u128 = 0 until E3.S1 populates it
prev_hash	present	links to previous record
record_hash	present (as audit_hash)	rename to record_hash for clarity
Hash stability rule: timestamp_ns must be in the record for human inspection (E1.S2 JSONL export), but must be excluded from the hash computation — wall-clock timestamps differ between original and replay runs. The auditHash() function must document which fields are hashed and which are metadata-only.

tile_id convention: [6]u8 padded with zeros, matching the 6-char constraint in the topology C ABI. Import or mirror the TileId type from topology.zig.

capability_envelope_id placeholder: A u128 zero-value field. When E3.S1 ships, the envelope id is computed and stored here. Replay divergence detection must compare this field, so a replay run without an envelope will produce zeros and match correctly.

T3: Schema versioning and unknown-field handling
Gap: No version field exists anywhere in AuditRecord. The Phase 0 replay comparison (auditRecordEql) does a field-by-field equality check; a schema version bump without this guard would silently corrupt replay results.

What to add:

const audit_schema_version: u16 = 1; — a package-level constant in audit.zig.
A schema_version: u16 field in the common Header, always serialized first in both binary and JSON output so a streaming reader can branch early.
A parseAuditRecord(bytes) or parseAuditRecordJson(json) function that returns error.UnknownSchemaVersion when schema_version > audit_schema_version. This is the "fail closed" behavior.
For the tagged union record type: a parseRecordType(tag) helper that returns error.UnknownRecordType for tags not in the current enum, instead of unreachable. This matters for forward-compatibility reading.
For binary records: a length prefix per record so an unknown-version record can be skipped without corrupting subsequent records (skip-forward semantics).
For JSONL (E1.S2): unknown JSON keys must be silently ignored during read-back (structural forward-compatibility), but the schema_version field is authoritative for whether the record is interpretable.
Replay implication: tkrepl must check schema_version of captured records before comparing. A version mismatch should be reported as a divergence, not compared field-by-field.

T4: Stable binary and JSON encoding tests
Gap: Current tests verify that formatAuditJsonl output starts with {"seq":0, and ends with }\n, and that stableEventHash produces the same value for duplicate-key events. There are no pinned hash values, no cross-optimization-mode assertions, and no coverage of the new record types.

Tests to write:

Pinned hash test — for each record type, create a canonical fixture with known field values and assert recordHash(fixture) == KNOWN_CONSTANT. The constant must be computed once and hardcoded. This test fails if the hash function changes (field reordering, algorithm change, enum value change). Add a comment: // This value must not change without bumping audit_schema_version.

Pinned JSON test — for each record type, assert the exact JSON string produced by the serializer, including field order. Field order in JSONL must be fixed (not map-iteration order). This proves the format is stable for log consumers.

Hash chain integrity test — build a chain of N records, mutate one field in record K, verify that records K through N all have different hashes. This validates the append-only invariant.

Schema version round-trip — serialize a record with schema_version = 1, deserialize it, assert all fields survive intact. This proves the codec is self-consistent.

Unknown version rejection — pass a record buffer with schema_version = 9999 to parseAuditRecord and assert it returns error.UnknownSchemaVersion.

Unknown record type rejection — pass a buffer with an unrecognized tag byte and assert it returns error.UnknownRecordType.

Timestamp excluded from hash — create two records with identical fields except timestamp_ns, verify their hashes are equal.

Coverage of all 12 record types — at minimum one round-trip test per type from T1.

Cross-optimization-mode note: The pinned hash tests implicitly cover this: if Debug and ReleaseSafe produce different hash values for the same input, the pinned test fails in one mode. Run zig build test -Doptimize=ReleaseSafe in CI to catch optimization-mode divergence.

Sequencing

T1 (record type definitions)
  → T2 (header fields, added to each type)
    → T3 (schema version + unknown-field handling)
      → T4 (pinned tests, one per type)
T4 stubs (expected values as @compileError("fill in")) can be written alongside T1 to lock the intended interface before the hash values are known.

Dependencies on other stories
E1.S2 (durable audit export) cannot be implemented until T1-T3 ship, since the JSONL writer must iterate over all record type variants.
E3.S1 (capability envelope) will back-fill capability_envelope_id once its type is defined; E1.S1 reserves the field as a zero u128.
E4.S1 (tkmodl), E5.S2 (tool broker), E5.S3/S4 (stub adapters) will produce records of types model_call, financial_adapter_call, and proposal — these types are defined as stubs in T1 so those stories don't need to touch audit.zig.