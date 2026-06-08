# Tickoni Workflows

## Core Use Cases

### 1. Payment Exception Handling

Events:

```text
payment_failed
settlement_delayed
payout_blocked
authorization_declined
processor_timeout
refund_failed
capture_failed
```

Agent tasks:

- classify failure reason
- retrieve processor logs
- summarize cause
- suggest retry path
- suggest routing path
- draft merchant response
- escalate sensitive cases
- prepare evidence for human review

Agents cannot directly release funds or override payment controls.

### 2. Reconciliation Breaks

Events:

```text
accounting_entry_mismatch
processor_batch_mismatch
bank_statement_diff
double_capture_suspected
unmatched_refund
settlement_amount_mismatch
```

Agent tasks:

- match records
- compare accounting ledger entries
- explain discrepancy
- prepare correction proposal
- attach supporting evidence
- route to finance operations
- generate audit packet

Agents cannot directly post accounting ledger adjustments in v1.

### 3. Fraud and Risk Case Triage

Events:

```text
velocity_spike
device_cluster_detected
chargeback_cluster
merchant_risk_alert
suspicious_payout
account_takeover_signal
high_risk_refund_pattern
```

Agent tasks:

- assemble evidence
- summarize risk pattern
- identify related entities
- recommend queue
- recommend investigation path
- draft investigator notes
- propose hold/review action

Agents cannot directly freeze accounts, block payouts, or approve high-impact actions without policy and human gates.

### 4. Compliance Case Preparation

Events:

```text
aml_alert_created
kyc_case_escalated
sanctions_match_detected
transaction_monitoring_alert
unusual_activity_detected
```

Agent tasks:

- collect evidence
- summarize customer or merchant profile
- prepare case narrative
- classify missing documents
- draft escalation packet
- route to compliance reviewer

Agents do not make final regulated compliance determinations in v1.

## Case Flow

```text
1. payment_failed event arrives
2. ingest_tile receives event
3. normalize_tile maps it to Tickoni schema
4. dedupe_tile checks for duplicates
5. case_router_tile creates case PAY-84721
6. policy_tile assigns allowed capabilities
7. payment_exception_agent investigates
8. agent calls approved tools through the MCP-compatible function-call broker
9. audit_tile records all prompts, tools, and outputs
10. agent drafts proposed merchant response
11. policy engine allows draft-only action
12. human reviews and approves response
13. downstream system receives approved response
14. replay capsule is generated
15. case moves to Audited
```
