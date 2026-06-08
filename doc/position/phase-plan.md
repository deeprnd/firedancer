# Tickoni V1 Phase Plan

## Purpose

This document defines phase gates for product delivery. It is the product
manager's checkpoint document: what must be true before a phase starts, what
must be delivered, and what evidence closes the phase.

Detailed stories and tasks live in [`wbs.md`](wbs.md). Tile ownership lives in
[`tile-plan.md`](tile-plan.md).

## Phase 0: Technical Spike

### Goal

Prove the Tickoni-only runtime shape with a synthetic payment stream.

### Entry Criteria

- Zig build path exists.
- Tickoni-owned runtime and tile directories exist.
- Firedancer validator tile reuse boundary is documented.

### Exit Criteria

- Synthetic pipeline runs through ingest, normalize, dedupe, policy, audit,
  replay, metrics, and diagnostics.
- Audit hash chain is deterministic.
- Replay comparison works with external effects disabled.
- Supervisor can start, stop, monitor, and mark a tile crashed.

### Evidence

- `zig build test` passes.
- `doc/position/tile-plan.md` records Phase 0 tile ownership and link answers.

## Phase 1: Control-Plane Harness

### Goal

Make the runtime useful end to end with stub payment and trading systems before
external ingestion or real financial connectors.

### Entry Criteria

- Phase 0 tests pass.
- Tile topology for `tkdisp`, `tkagnt`, `tkmodl`, `tktool`, and `tkadpt` is
  accepted at the ownership level.
- V1 non-goals are unchanged.

### Deliverables

- durable audit export and hash-chain verification
- telemetry and diagnostics export
- versioned capability envelope
- policy decisions for allow, deny, and require-approval
- `tkmodl` integration with deterministic stub responses or a configured
  local/dev LLM server
- `tktool` broker path
- stub payment adapter
- stub trading adapter
- model, tool, adapter, denial, approval-required, token, retry, and budget
  audit records

### Exit Criteria

- A synthetic payment event can trigger an audited stub investigation.
- A synthetic trading-control event can trigger an audited stub investigation.
- Forbidden execution is denied and audited.
- Approval-required proposals are recorded but not executed.
- Telemetry shows queue, policy, model, tool, adapter, audit, and replay state.
- Replay completes without invoking model, payment, trading, or execution
  side effects.

### Evidence

- A documented demo command.
- Audit JSONL sample with valid hash chain.
- Metrics or diagnostics sample.
- Replay match and at least one intentional divergence test.

## Phase 2: Deterministic Case Runtime

### Goal

Turn stub investigations into deterministic, replayable case records with
content-addressed evidence.

### Entry Criteria

- Phase 1 demo is stable.
- Capability envelopes and policy decisions are audited.
- Model/tool/adapter boundary records can be replayed from captured inputs.

### Deliverables

- deterministic case id derivation
- `tkcase` lifecycle events
- `tkevid` content-addressed evidence records
- case-scoped audit journal
- replay capsule format
- case divergence reporting

### Exit Criteria

- Same input stream creates the same case ids and lifecycle sequence.
- Agent outputs and adapter results attach as evidence.
- Evidence hashes verify.
- Replay detects changed case state, changed evidence, and missing boundary
  responses.

### Evidence

- Case fixture set.
- Replay capsule sample.
- Case divergence test output.

## Phase 3: External Ingestion And CaseOps

### Goal

Introduce real ingestion and make operator review usable.

### Entry Criteria

- Phase 2 case replay is deterministic.
- External connector behavior can be substituted by replay capsules.
- Approval-required action semantics are proven with stubs.

### Deliverables

- financial event ingestion API
- CaseOps API
- CaseOps board
- evidence panel
- agent findings panel
- policy decision panel
- approval workflow
- audit timeline
- replay status indicator

### Exit Criteria

- Real API events enter the same deterministic pipeline as synthetic events.
- An operator can review a case end to end.
- An operator can approve or reject a proposed action.
- Approval and rejection decisions are audited.
- Replay status is visible without reading logs.

### Evidence

- API integration tests.
- CaseOps demo script.
- Approval and rejection audit samples.

## Phase 4: Fintech Workflow Pack

### Goal

Prove buyer-relevant workflows with replayable sample data.

### Entry Criteria

- CaseOps can review a case end to end.
- Stubs can be replaced by signed demo adapters without weakening policy.
- Replay capsules are stable.

### Deliverables

- payment exception workflow
- reconciliation break workflow
- fraud/risk triage workflow
- demo adapter fixtures
- policy templates
- audit exports
- replayable sample data

### Exit Criteria

- Each workflow produces a useful operator-facing recommendation.
- Each workflow is policy-gated.
- Each workflow has a replay capsule.
- Each workflow avoids autonomous money movement and autonomous trading.

### Evidence

- Three workflow demos.
- Three replay capsules.
- Product demo checklist tied to V1 success metrics.

## Phase Gate Review Checklist

Use this checklist before closing any phase:

1. Are V1 non-goals still enforced?
2. Can the demo be run from documented commands?
3. Are policy decisions visible in audit output?
4. Are queue, model, tool, adapter, and replay states visible in telemetry?
5. Can replay run without external side effects?
6. Are any product claims unsupported by the implementation evidence?
7. Did new scope belong in this phase, or should it move to the WBS backlog?
