# Tickoni Audit & Replay

## Audit Event

```json
{
  "event_id": "evt_01JX9Z7F6J4A9",
  "previous_hash": "hash_8c1e...",
  "timestamp_ns": 1780423319123000000,
  "case_id": "PAY-84721",
  "actor_type": "agent",
  "actor_id": "payment_exception_agent",
  "model_id": "model_provider/model_name",
  "action": "tool_call",
  "tool": "read_processor_log",
  "input_hash": "hash_12ab...",
  "output_hash": "hash_88fc...",
  "policy_version": "policy_2026_06_01",
  "policy_decision": "allow",
  "capability": "read_processor_log",
  "result": "success",
  "signature": "sig_..."
}
```

## Replay Capsule

```yaml
capsule_id: capsule_PAY_84721
case_id: PAY-84721

events:
  - hash://event_payment_failed
  - hash://event_processor_timeout
  - hash://event_retry_failed

policy:
  version: policy_2026_06_01
  hash: hash://policy

agent:
  role: payment_exception_agent
  transcript: hash://agent_transcript
  tool_calls: hash://tool_calls

evidence:
  processor_logs: hash://processor_logs
  ledger_entries: hash://ledger_entries
  case_history: hash://case_history

expected:
  final_state: action_proposed
  proposed_action: draft_merchant_response
  policy_result: allow
```
