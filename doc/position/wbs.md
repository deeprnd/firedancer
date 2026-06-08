# Tickoni V1 Work Breakdown Structure

## Purpose

This document turns the V1 roadmap into executable engineering work. It is not
the product narrative and it is not the tile topology reference.

- [`roadmap.md`](roadmap.md) defines why and in what order.
- [`prd.md`](prd.md) defines V1 requirements and success metrics.
- [`phase-plan.md`](phase-plan.md) defines phase gates and close criteria.
- [`tile-plan.md`](tile-plan.md) defines runtime shape and tile ownership.
- [`inference-governance.md`](inference-governance.md) defines model access and
  budget controls.
- [`capabilities.md`](capabilities.md) defines finance-native capability
  scopes, destination allowlists, limits, and the P0-P4 capability roadmap.
- This WBS defines epics, stories, tasks, and acceptance criteria.

## Phase Gates

| Phase | Gate | Required outcome |
| --- | --- | --- |
| Phase 0 | Technical spike | Synthetic payment pipeline proves bounded flow, audit hashing, replay, telemetry snapshots, and crash diagnostics |
| Phase 1 | Control-plane harness | Stub payment and trading workflows run end to end through audit, telemetry, finance-native capabilities, destination allowlists, runtime hooks, model gateway, financial tool broker, and stub adapters |
| Phase 2 | Deterministic case runtime | Stub workflows produce deterministic cases, evidence records, hook-derived replay capsules, and case divergence reports |
| Phase 3 | External ingestion and CaseOps | Real ingestion API and operator board expose case review, hook-derived audit timeline, replay status, and approval workflow |
| Phase 4 | Workflow pack | Payment exception, reconciliation, and fraud/risk demos are policy-gated, auditable, and replayable |

## Epic Summary

| Epic | Phase | Description |
| --- | --- | --- |
| E0 | Phase 0 | Complete and maintain the Tickoni-only runtime spike |
| E1 | Phase 1 | Durable audit, runtime hook contract, and replay foundation |
| E2 | Phase 1 | Telemetry and diagnostics export, including hook behavior |
| E3 | Phase 1 | Finance-native capability envelopes and policy decisions |
| E4 | Phase 1 | Model gateway, policy-gated model hooks, and inference governance |
| E5 | Phase 1 | Agent hook bus, financial tool broker, and stub financial adapters |
| E6 | Phase 2 | Deterministic cases, evidence, and hook replay capsules |
| E7 | Phase 3 | External ingestion API, hook timeline, and CaseOps board |
| E8 | Phase 4 | Fintech workflow pack |
| E9 | All phases | Build, quality, security, and release hygiene |

## E0: Runtime Spike

Status: complete as an in-process Phase 0 spike.

### E0.S1: Tickoni supervisor starts product tiles

As a Tickoni maintainer, I need a Zig supervisor that starts Tickoni-owned tiles
so product work does not depend on validator tiles.

Tasks:

- E0.S1.T1: Define static Phase 0 topology with `tkings`, `tknorm`, `tkdedu`, `tkpoly`, `tkaudt`, `tkrepl`, `tkmetr`, and `tkdiag`.
- E0.S1.T2: Start each tile as an in-process thread for deterministic unit tests.
- E0.S1.T3: Stop and join all tile threads through supervisor-owned lifecycle handles.
- E0.S1.T4: Expose monitor state for stopped and crashed tiles.

Acceptance:

- `zig build test` covers normal start, stop, monitor, and crash states.

### E0.S2: Synthetic payment pipeline proves runtime behavior

As a runtime engineer, I need one synthetic stream that exercises flow,
dedupe, policy, audit, replay, and diagnostics.

Tasks:

- E0.S2.T1: Generate stable synthetic payment events with source offsets.
- E0.S2.T2: Normalize events into canonical payment facts.
- E0.S2.T3: Deduplicate by idempotency key and content hash.
- E0.S2.T4: Emit allow, deny, malformed-drop, and duplicate-drop decisions.
- E0.S2.T5: Append hash-chained audit records.
- E0.S2.T6: Replay the stream with external effects disabled and report divergence.
- E0.S2.T7: Simulate sandbox failure and propagate crash state.

Acceptance:

- Phase 0 tests prove stable hashes, append-only audit ordering, backpressure,
  replay match, duplicate detection, malformed rejection, policy deny, and
  sandbox failure diagnostics.

## E1: Durable Audit And Replay Foundation

Phase: 1.

### E1.S1: Audit record schema

As an auditor, I need every material runtime event represented as a typed audit
record so replay and investigation do not depend on logs or UI state.

Tasks:

- E1.S1.T1: Define audit record types for source events, normalization, policy decisions, model calls, financial adapter calls, proposals, destination checks, limit checks, approvals-required, denials, telemetry checkpoints, and replay results.
- E1.S1.T2: Include sequence, source offset, tile id, logical actor id, policy version, capability envelope id, previous hash, and record hash.
- E1.S1.T3: Add schema versioning and unknown-field handling.
- E1.S1.T4: Add tests for stable binary and JSON encodings.

Acceptance:

- Audit records have deterministic hashes across process runs and compiler
  optimization modes.

### E1.S2: Durable audit export

As an operator, I need the audit chain exported durably so a completed run can
be inspected and replayed after process exit.

Tasks:

- E1.S2.T1: Add configured audit output path for development runs.
- E1.S2.T2: Write JSONL audit records in append order.
- E1.S2.T3: Flush and close audit output on clean shutdown.
- E1.S2.T4: Mark audit output incomplete on crash shutdown.
- E1.S2.T5: Add hash-chain verification command or test helper.

Acceptance:

- A Phase 1 demo run produces a JSONL file whose full hash chain verifies.

Tech debt:
- JSON fixture pinning (T4 partial): The WBS says "pinned JSON test — assert the exact JSON string produced by the serializer." Binary bytes are pinned and verified. The JSON codec (audit_json.c) is implemented but tk_audit_format_jsonl is not called from any test in audit.zig. The binary round-trip covers correctness, but the JSON path has no pinned test on this branch. This is acceptable for E1.S1 since audit_json.c is wired for E1.S2 (durable export), but worth tracking.
- audit_json.c is compiled via libfd_ballet? No — it's in src/tickoni/codec/ and is not yet added to build.zig. It will need to be added when E1.S2 wires the JSONL export path.


### E1.S3: Replay input capture

As an auditor, I need replay inputs captured at every nondeterministic boundary
so replay does not invoke external systems.

Tasks:

- E1.S3.T1: Capture model request and response bodies at the `tkmodl` boundary.
- E1.S3.T2: Capture tool requests and adapter responses at the `tktool` and `tkadpt` boundaries.
- E1.S3.T3: Capture approval-required and denied decisions.
- E1.S3.T4: Add replay mode that substitutes captured boundary responses.
- E1.S3.T5: Add divergence checks for missing, reordered, or changed boundary records.

Acceptance:

- Replay of a Phase 1 stub workflow completes without model, adapter, payment,
  trading, or execution side effects.

### E1.S4: Runtime hook contract and registry

As a Tickoni runtime maintainer, I need one canonical hook envelope and typed
registry so agent, model, tool, adapter, policy, proposal, approval, and replay
events cannot become unstructured logs.

Tasks:

- E1.S4.T1: Define `HookEnvelope` fields for hook event id, hook type, timestamp, case id, run id, actor type, actor id, agent id, workflow, environment, policy version, capability, risk level, input hash, output hash, previous audit hash, and schema version.
- E1.S4.T2: Add optional fields for model id, tool name, adapter id, approval id, proposal id, downstream action id, token usage, latency, resource usage, and error code.
- E1.S4.T3: Add a versioned hook type enum for agent lifecycle, model, tool, adapter, proposal, approval, case, replay, and future privileged execution hooks.
- E1.S4.T4: Define required fields per hook type and reject unknown or incomplete hook types before audit ingestion.
- E1.S4.T5: Add deterministic serialization and stable hook hash tests across process restarts.
- E1.S4.T6: Audit malformed hook rejections without advancing case state.

Acceptance:

- Identical hook inputs produce identical hook hashes, malformed hooks fail
  closed, and every accepted material hook can be converted into a typed audit
  record.

### E1.S5: Hook-to-audit integration

As an auditor, I need material hooks to become hash-chained audit records with
content-addressed payload references.

Tasks:

- E1.S5.T1: Let `tkaudt` accept validated hook envelopes and assign audit event ids.
- E1.S5.T2: Link each hook-derived audit record with `previous_hash` and compute `record_hash`.
- E1.S5.T3: Store prompt, model response, tool input, tool output, adapter output, and evidence payloads by content address rather than duplicating sensitive payloads into every audit row.
- E1.S5.T4: Export hook-derived audit records as JSONL.
- E1.S5.T5: Extend hash-chain verification to validate hook schema version, required fields, content-addressed references, and policy decision presence.

Acceptance:

- Hash-chain verification detects tampering, missing content-addressed payloads,
  and hook records without required policy decisions.

## E2: Telemetry And Diagnostics Export

Phase: 1.

### E2.S1: Runtime metrics model

As an operator, I need runtime counters and gauges for the control-plane harness
so queue pressure and policy, model, financial adapter, proposal, destination,
and limit behavior are visible.

Tasks:

- E2.S1.T1: Define counters for produced, normalized, duplicate, denied, approval-required, model-call, financial-adapter-call, proposal, destination-check, limit-check, replay-divergence, and crash events.
- E2.S1.T2: Define gauges for queue depth, max queue depth, latency hops, active agent runs, model queue depth, and adapter queue depth.
- E2.S1.T3: Attribute model, financial adapter, proposal, destination, and limit metrics by tile, role, policy version, workflow, and stub adapter.
- E2.S1.T4: Add tests for monotonic counters and bounded gauge updates.

Acceptance:

- Phase 1 tests can assert metric snapshots after a complete stub run.

### E2.S2: Metrics export

As an SRE, I need metrics exported in a scrapeable or machine-readable format.

Tasks:

- E2.S2.T1: Add text or JSON metrics export for development runs.
- E2.S2.T2: Include queue, policy, model, financial adapter, proposal, destination, limit, audit, and replay metrics.
- E2.S2.T3: Add final metrics snapshot on shutdown.
- E2.S2.T4: Document metric names and labels.

Acceptance:

- A demo run emits metrics that show policy decisions, model usage, adapter
  calls, replay status, and queue watermarks.

### E2.S3: Diagnostics export

As an operator, I need diagnostics that explain crashes and sandbox failures
without reading internal tile state.

Tasks:

- E2.S3.T1: Export crashed tile id, exit code, crash reason, and last processed source offset.
- E2.S3.T2: Export sandbox failure count and owning tile.
- E2.S3.T3: Export audit record count and last audit hash.
- E2.S3.T4: Export replay checked, replay matched, and divergence count.

Acceptance:

- A simulated sandbox failure produces a diagnostic record that names the failed
  tile and reason.

### E2.S4: Hook telemetry and diagnostics

As an operator, I need hook-level metrics and diagnostics so model, tool,
adapter, policy, approval, and replay behavior are visible without reading
internal tile state.

Tasks:

- E2.S4.T1: Add metrics for hook count by type, policy allow/deny/approval counts, model calls, tool calls, adapter latency, token usage by case and agent, budget denials, approval-required decisions, and replay divergence.
- E2.S4.T2: Add diagnostics for hook queue depth, hook queue overrun, hook validation failure, audit write failure, policy timeout, adapter timeout, and model timeout.
- E2.S4.T3: Include tile id, hook type, workflow, role, policy version, and case/run id where applicable.
- E2.S4.T4: Add timing breakdowns for total agent duration, model time, tool/adapter time, policy time, approval wait time, idle time, and replay time.
- E2.S4.T5: Export hook telemetry through `tkmetr` and hook diagnostics through `tkdiag`.

Acceptance:

- A Phase 1 stub run emits hook metrics and diagnostics that show cost, latency,
  queue pressure, denials, approvals, and replay divergence.

## E3: Finance-Native Capability Envelopes And Policy

Phase: 1.

### E3.S1: Capability envelope schema

As a security engineer, I need every model, adapter, and proposed financial
action to carry a finance-native capability envelope so authorization is
business-scoped, data-driven, and auditable.

Tasks:

- E3.S1.T1: Define envelope fields: actor id, role, workflow, financial domain, financial object, action class, scope, environment, policy version, budget id, and request id.
- E3.S1.T2: Define deterministic envelope id generation.
- E3.S1.T3: Add scope fields for payment rail, processor, ledger book, beneficiary, IBAN hash, crypto wallet, broker account, market, venue, sector, instrument, side, and order type.
- E3.S1.T4: Add amount, exposure, frequency, holding-period, per-day, and per-month limit fields.
- E3.S1.T5: Add validation for missing identity, unsupported financial domain, unsupported action class, invalid scope, missing allowlist match, invalid limit, and environment mismatch.
- E3.S1.T6: Add canonical encoding tests.

Acceptance:

- Invalid envelopes are rejected before model, adapter, proposal, or privileged
  execution paths.

### E3.S2: Policy decision engine

As a product engineer, I need allow, deny, and require-approval decisions for
stub workflows so the harness proves financial consequence boundaries.

Tasks:

- E3.S2.T1: Define static development policy for `payment_attempt.read`, `payment_retry.propose`, `ledger_correction.propose`, `trading_portfolio.read`, `trading_order.propose`, and forbidden execution capabilities.
- E3.S2.T2: Return allow, deny, or require-approval with reason code.
- E3.S2.T3: Attach policy version and rule id to each decision.
- E3.S2.T4: Enforce destination allowlists for bank, crypto, and trading destinations even when P1 uses deterministic stubs.
- E3.S2.T5: Enforce trading proposal scope for US markets, NYSE/NASDAQ venues, Information Technology sector, allowed asset classes, USD 10,000/day proposal cap, minimum proposal interval, and denied same-day round trips.
- E3.S2.T6: Audit every decision before any model, adapter, proposal, or execution path proceeds.
- E3.S2.T7: Add tests for allow, deny, require-approval, missing allowlist, over-limit, wrong market, wrong sector, too-frequent, and forbidden execution paths.

Acceptance:

- A Phase 1 run demonstrates all three decision outcomes, denies out-of-scope
  financial consequences, and audits the exact destination, limit, frequency,
  and approval checks.

### E3.S3: Budget and loop limits

As an operator, I need bounded inference and financial action loops so a stub
demo cannot run indefinitely, spend without control, or repeatedly propose
money-adjacent actions.

Tasks:

- E3.S3.T1: Define per-run, per-role, and per-workflow model-call limits.
- E3.S3.T2: Define token budget accounting fields.
- E3.S3.T3: Deny model calls that exceed configured budget.
- E3.S3.T4: Stop agent loops after configured retry or step limits.
- E3.S3.T5: Stop repeated proposal loops after configured payment retry, ledger correction, or trading recommendation limits.
- E3.S3.T6: Audit budget exhaustion and loop-limit termination.

Acceptance:

- Tests cover budget exhaustion and runaway-loop prevention without external
  model calls.

### E3.S4: Hook policy failure behavior

As an operator, I need hook failures to be safe by default so audit or policy
outages cannot silently allow unaudited financial actions.

Tasks:

- E3.S4.T1: Deny action by default if a policy-bearing hook cannot be evaluated.
- E3.S4.T2: Block privileged or money-adjacent action if a required audit hook cannot be written.
- E3.S4.T3: Allow telemetry-only hook loss only when the loss is counted and visible.
- E3.S4.T4: Report replay comparison failures as replay divergence, not as successful replay.
- E3.S4.T5: Document hook failure modes in the phase gate notes.

Acceptance:

- Material model, tool, adapter, proposal, approval, and future execution paths
  cannot proceed when required policy or audit hooks fail.

## E4: Model Gateway And Inference Governance

Phase: 1.

### E4.S1: `tkmodl` request path

As an agent developer, I need a single model gateway so agents never own direct
model-provider or LLM-server access.

Tasks:

- E4.S1.T1: Define model request and response envelopes.
- E4.S1.T2: Route requests by model identifier.
- E4.S1.T3: Enforce context length and request size before outbound calls.
- E4.S1.T4: Record prompt, response, token estimate, latency, retry count, and selected backend in audit.
- E4.S1.T5: Return deterministic stub responses when configured for tests.

Acceptance:

- Unit tests can run `tkmodl` without network access and still produce audited
  model records.

### E4.S2: Local/dev LLM backend

As a demo builder, I need optional local or development LLM server integration
that still goes through Tickoni's policy and audit path.

Tasks:

- E4.S2.T1: Add configured OpenAI-compatible endpoint URL.
- E4.S2.T2: Add request timeout and retry limit.
- E4.S2.T3: Add API key or no-auth development mode configuration.
- E4.S2.T4: Parse response content and token usage when present.
- E4.S2.T5: Fall back to estimated token accounting when usage is absent.

Acceptance:

- A configured local/dev endpoint can be called only through `tkmodl`, and all
  requests are audited.

### E4.S3: Cloud and local GPU backend scaffolding

As a maintainer, I need backend boundaries clear before implementing provider
details.

Tasks:

- E4.S3.T1: Add provider enum for OpenAI, Anthropic, Qwen, DeepSeek, local LLM server, and local GPU.
- E4.S3.T2: Add configuration validation for API key, endpoint, model id, local weight path, and context size.
- E4.S3.T3: Keep local GPU path disabled until llama.cpp/CUDA integration is explicitly implemented.
- E4.S3.T4: Add tests that reject unconfigured providers.

Acceptance:

- Misconfigured model identifiers fail closed before any outbound call.

### E4.S4: Policy-gated model hooks

As a platform operator, I need every model call to pass through `PreModelCall`
and `PostModelCall` so model routing, prompt capture, context limits, token
budgets, retry loops, and replay substitution are enforced before provider
access.

Tasks:

- E4.S4.T1: Require `tkagnt` to emit `PreModelCall` before any `tkmodl` request.
- E4.S4.T2: Include case id, agent id, model route, requested model, prompt hash, context hash, estimated input tokens, remaining case budget, remaining agent budget, retry count, and policy version in `PreModelCall`.
- E4.S4.T3: Let `tkpoly` return allow, deny, or require-approval for model hooks.
- E4.S4.T4: Prevent denied model calls from reaching `tkmodl` and audit the denial.
- E4.S4.T5: Emit `PostModelCall` with model id, provider id, request hash, response hash, input tokens, output tokens, total tokens, latency, finish reason, and cost estimate.
- E4.S4.T6: Emit model failure, budget exceeded, and replay-substitution hooks when those states occur.
- E4.S4.T7: Update case and agent budgets from accepted model hook records.

Acceptance:

- No model provider or local/dev LLM server can be called unless the matching
  model hooks were policy-checked and audit-recorded.

## E5: Agent, Financial Tool Broker, And Stub Financial Adapters

Phase: 1.

### E5.S1: Controlled stub agent run

As a product engineer, I need one bounded agent path that can investigate a
synthetic event without creating real cases or external effects.

Tasks:

- E5.S1.T1: Define agent role config for payment exception and trading review.
- E5.S1.T2: Feed synthetic event context into `tkdisp`.
- E5.S1.T3: Execute a bounded `tkagnt` plan with model calls through `tkmodl`.
- E5.S1.T4: Stop the run on budget exhaustion, denied financial adapter call, denied proposal, or completion.
- E5.S1.T5: Audit agent start, step, model request, model response, financial adapter request, proposal, and final output.

Acceptance:

- A Phase 1 demo produces an agent output without shell access, direct network
  access, unaudited adapter calls, or authority outside the configured financial
  capability envelope.

### E5.S2: Tool broker

As a security engineer, I need all model-native function calls and future MCP
requests normalized through one broker so they become financial adapter or
proposal requests with the same capability boundary.

Tasks:

- E5.S2.T1: Define financial adapter request, proposal request, and response envelopes.
- E5.S2.T2: Normalize model function-call output into finance-native requests such as payment retry proposal, ledger correction proposal, and trading order proposal.
- E5.S2.T3: Validate the finance-native capability envelope before routing.
- E5.S2.T4: Route to a named stub adapter only after destination, amount, frequency, and approval checks pass.
- E5.S2.T5: Audit allowed, denied, and approval-required financial adapter calls and proposals.

Acceptance:

- Forbidden financial consequences are denied before adapter execution and
  appear in the audit chain with the failed scope dimension.

### E5.S3: Stub payment adapter

As a demo builder, I need a deterministic payment adapter so payment exception
workflows can run without a processor integration.

Tasks:

- E5.S3.T1: Define `payment_attempt.read` request and response schema.
- E5.S3.T2: Define `payment_retry.propose` request and response schema with rail, processor, amount, retry count, beneficiary, and approval state.
- E5.S3.T3: Return deterministic fixture data keyed by source offset or payment id.
- E5.S3.T4: Validate payment rail, processor, amount, retry count, and destination allowlist from the capability envelope.
- E5.S3.T5: Mark retry proposals as require-approval, not executed.
- E5.S3.T6: Audit adapter request, response, deterministic fixture id, and financial scope.

Acceptance:

- Payment exception demo can read payment state and propose a retry without
  executing a mutation.

### E5.S4: Stub trading adapter

As a demo builder, I need a deterministic trading adapter so trading-control
boundaries can be demonstrated without market connectivity.

Tasks:

- E5.S4.T1: Define `trading_portfolio.read` request and response schema.
- E5.S4.T2: Define `trading_order.propose` request and response schema with broker account, market, venue, sector, asset class, instrument, side, order type, notional, and frequency metadata.
- E5.S4.T3: Return deterministic fixture positions, balances, and risk flags.
- E5.S4.T4: Validate US market, NYSE/NASDAQ venue, Information Technology sector, allowed asset classes, daily/monthly notional cap, minimum proposal interval, and no same-day round-trip policy.
- E5.S4.T5: Mark order proposals as require-approval, not executed.
- E5.S4.T6: Deny any direct order execution request.

Acceptance:

- Trading demo can propose an in-scope action, deny an out-of-scope market or
  sector proposal, deny an over-limit or too-frequent proposal, require
  approval for valid proposals, and prove direct execution is denied and
  audited.

### E5.S5: Bounded hook bus and dispatcher

As a systems engineer, I need hook events to move over bounded links so hooks
preserve Tickoni's backpressure, ownership, and failure model.

Tasks:

- E5.S5.T1: Define reliable bounded hook links for `tkagnt_hook`, `tkmodl_hook`, `tktool_hook`, and `tkadpt_hook`.
- E5.S5.T2: Define producer, consumer, depth, MTU, overrun behavior, restart behavior, shutdown behavior, and health metrics for each correctness-bearing hook link.
- E5.S5.T3: Add a hook dispatcher that accepts validated hook envelopes.
- E5.S5.T4: Route policy-bearing hooks to `tkpoly`, audit-bearing hooks to `tkaudt`, metrics hooks to `tkmetr`, diagnostics hooks to `tkdiag`, and replay hooks to `tkrepl`.
- E5.S5.T5: Ensure the dispatcher has no model, adapter, ledger, trading, payment, or unrestricted network access.
- E5.S5.T6: Add saturation tests for hook queues.

Acceptance:

- Hook dispatch preserves bounded flow control, reports queue pressure, and
  cannot bypass the owning policy, audit, metrics, diagnostics, or replay tiles.

### E5.S6: Policy-gated tool and adapter hooks

As a security engineer, I need model-native function calls, MCP-compatible
requests, and financial adapter calls to terminate at the same `tktool`
boundary and emit policy-checked hooks.

Tasks:

- E5.S6.T1: Normalize tool calls into capability envelopes with tool name, tool protocol, adapter id, capability, case scope, financial object scope, destination scope, amount, currency, frequency key, and risk level.
- E5.S6.T2: Reject invalid tool arguments before adapter execution and audit the rejection.
- E5.S6.T3: Emit `PreToolUse` before every `tktool` execution and route it through `tkpoly`.
- E5.S6.T4: Prevent denied tool calls from reaching `tkadpt` and pause approval-required calls.
- E5.S6.T5: Emit `PostToolUse` with tool name, adapter id, input hash, output hash, latency, result status, error code, and evidence reference.
- E5.S6.T6: Content-address adapter outputs and link them to case evidence.
- E5.S6.T7: Prove agents have no direct adapter credentials or unrestricted network path to stub payment or trading adapters.

Acceptance:

- Allowed, denied, approval-required, and failed tool/adapter calls are visible
  in the audit chain, and direct adapter access attempts fail closed.

### E5.S7: Finance-native proposal hooks

As a finance operations user, I need money-adjacent agent outputs represented
as immutable proposals that can be reviewed, approved, rejected, expired, and
replayed.

Tasks:

- E5.S7.T1: Define proposal schema with proposal id, case id, agent id, workflow, proposed action, financial object, destination, amount, currency, limit scope, frequency scope, required approval role, expiry, proposal hash, and policy version.
- E5.S7.T2: Emit `PreActionProposal` before any proposal becomes valid.
- E5.S7.T3: Check action class, amount limit, destination allowlist, frequency limit, approval requirement, environment, and case scope.
- E5.S7.T4: Deny out-of-scope proposals and mark valid money-adjacent proposals as approval-required, not executable.
- E5.S7.T5: Hash-bind proposals so approvals and future execution reference the exact proposal content and policy version.
- E5.S7.T6: Keep superseded proposal versions auditable instead of mutating proposal content.

Acceptance:

- No proposal appears as valid unless `PreActionProposal` was policy-checked,
  audit-recorded, and hash-bound to immutable proposal content.

## E6: Deterministic Cases And Evidence

Phase: 2.

### E6.S1: Case router

As an operator, I need events grouped into deterministic cases so investigations
are repeatable.

Tasks:

- E6.S1.T1: Define case id derivation from workflow, entity id, source offset, and event hash.
- E6.S1.T2: Add `tkcase` lifecycle events for opened, updated, assigned, resolved, and replayed.
- E6.S1.T3: Route stub payment and trading workflows into cases.
- E6.S1.T4: Audit every case transition.

Acceptance:

- Replaying the same input creates the same case ids and lifecycle sequence.

### E6.S2: Evidence store

As an auditor, I need content-addressed evidence so model outputs, adapter
responses, and artifacts can be verified.

Tasks:

- E6.S2.T1: Define evidence record schema with content hash, media type, source tile, and case id.
- E6.S2.T2: Store model outputs, adapter responses, and selected audit exports as evidence.
- E6.S2.T3: Reject evidence whose stored hash does not match content.
- E6.S2.T4: Link evidence records from case history.

Acceptance:

- Case history can be verified against content-addressed evidence records.

### E6.S3: Replay capsule

As an auditor, I need one replay capsule per material case so a case can be
replayed without external effects.

Tasks:

- E6.S3.T1: Define replay capsule schema for source event hashes, normalized event hashes, case id, case state hashes, policy version/hash, agent run id, model request/response hashes, tool call hashes, adapter result hashes, proposal hashes, approval records, evidence hashes, and expected final state hash.
- E6.S3.T2: Export capsule from completed case history.
- E6.S3.T3: Re-run case logic from capsule.
- E6.S3.T4: Regenerate `PreModelCall`, `PostModelCall`, `PreToolUse`, `PostToolUse`, proposal, approval, and replay hooks in replay mode.
- E6.S3.T5: Substitute recorded model outputs and deterministic adapter fixtures instead of calling external model providers, payment APIs, trading APIs, or execution systems.
- E6.S3.T6: Report the first divergence by case transition, audit record, hook hash, evidence hash, prompt/context hash, policy version, or boundary response.
- E6.S3.T7: Fail replay if a live model provider, live adapter, or privileged mutation path is called.

Acceptance:

- Replay can detect changed case state, changed evidence, changed hook sequence,
  changed policy, and missing boundary responses without invoking external
  effects.

## E7: External Ingestion And CaseOps

Phase: 3.

### E7.S1: Financial event ingestion API

As an integrator, I need a real ingestion API after the control-plane harness
is proven.

Tasks:

- E7.S1.T1: Define request schema for payment exception, reconciliation break, fraud/risk, and trading-control events.
- E7.S1.T2: Validate authentication, source identity, idempotency key, event timestamp, and payload size.
- E7.S1.T3: Assign stable source offsets.
- E7.S1.T4: Return accepted, duplicate, malformed, or rejected responses.
- E7.S1.T5: Add integration tests for valid, duplicate, malformed, oversized, and unauthorized requests.

Acceptance:

- Real API events enter the same deterministic pipeline as synthetic events.

### E7.S2: CaseOps API

As a frontend user, I need a case API that exposes reviewable state without
allowing unaudited mutation.

Tasks:

- E7.S2.T1: Add list, detail, evidence, audit timeline, replay status, and approval endpoints.
- E7.S2.T2: Require policy checks for approval actions.
- E7.S2.T3: Audit all approval and rejection decisions.
- E7.S2.T4: Keep privileged execution disabled by default.

Acceptance:

- Operator actions are visible in case history and audit export.

### E7.S3: CaseOps board

As an operator, I need a compact board to review cases, evidence, findings,
policy decisions, and replay status.

Tasks:

- E7.S3.T1: Build case list with status, workflow, severity, age, and replay status.
- E7.S3.T2: Build case detail with event facts, evidence, agent findings, and policy decisions.
- E7.S3.T3: Build approval panel for proposed sensitive actions.
- E7.S3.T4: Build audit timeline with hash-chain status.
- E7.S3.T5: Add empty, loading, error, and replay-divergence states.

Acceptance:

- An operator can review a demo case end to end and approve or reject a
  proposed action.

### E7.S4: Approval hooks and audit timeline

As an operator and auditor, I need approval-required actions and hook-derived
audit records to become reviewable CaseOps state.

Tasks:

- E7.S4.T1: Emit `ApprovalRequested` for approval-required proposals with approval id, proposal id, case id, required role, requesting agent, policy version, and expiry.
- E7.S4.T2: Emit `ApprovalGranted`, `ApprovalRejected`, and `ApprovalExpired` with approver identity, role, timestamp, reason, approval scope, expiry, and proposal hash.
- E7.S4.T3: Block rejected or expired approvals from any future execution path.
- E7.S4.T4: Expose pending approvals through the CaseOps API and show them on the case card.
- E7.S4.T5: Build an audit timeline that shows hook events in order and groups them by ingestion, agent run, model calls, tool calls, policy decisions, proposals, approvals, and replay.
- E7.S4.T6: Add timeline filtering by hook type and JSONL audit-slice export.

Acceptance:

- Denied, approval-required, approved, rejected, expired, and replay-divergent
  hook events are visible in CaseOps and exported in audit order.

## E8: Fintech Workflow Pack

Phase: 4.

### E8.S1: Payment exception workflow

Tasks:

- E8.S1.T1: Define failed payment event fixture set.
- E8.S1.T2: Retrieve stub processor records.
- E8.S1.T3: Classify failure reason.
- E8.S1.T4: Propose retry or routing path.
- E8.S1.T5: Draft customer or merchant response.
- E8.S1.T6: Export replayable demo capsule.

Acceptance:

- Demo produces a useful recommendation, evidence packet, audit trail, and
  replay result.

### E8.S2: Reconciliation break workflow

Tasks:

- E8.S2.T1: Define ledger mismatch fixture set.
- E8.S2.T2: Compare source and ledger records.
- E8.S2.T3: Identify likely discrepancy reason.
- E8.S2.T4: Prepare non-executing correction proposal.
- E8.S2.T5: Route to finance operations review.
- E8.S2.T6: Export replayable demo capsule.

Acceptance:

- Demo explains the discrepancy and creates an auditable correction proposal.

### E8.S3: Fraud/risk triage workflow

Tasks:

- E8.S3.T1: Define suspicious activity fixture set.
- E8.S3.T2: Assemble related evidence.
- E8.S3.T3: Summarize risk pattern.
- E8.S3.T4: Classify severity.
- E8.S3.T5: Recommend review queue.
- E8.S3.T6: Export replayable demo capsule.

Acceptance:

- Demo produces a risk summary, severity, recommendation, audit trail, and
  replay result without executing regulated action.

## E9: Build, Quality, Security, And Release Hygiene

Phase: all.

### E9.S1: Build and test integration

Tasks:

- E9.S1.T1: Keep Zig harness tests wired through `zig build test`.
- E9.S1.T2: Add focused tests for each new schema, tile, and adapter.
- E9.S1.T3: Add integration tests for Phase 1, Phase 2, and Phase 3 gates.
- E9.S1.T4: Keep developer tooling in `justfile`, not Firedancer makefiles.

Acceptance:

- Each phase gate has a local command that verifies the gate.

### E9.S2: Security checks

Tasks:

- E9.S2.T1: Add tests for forbidden shell, forbidden direct network, and forbidden direct execution paths.
- E9.S2.T2: Add policy fail-closed tests for malformed envelopes and unknown providers.
- E9.S2.T3: Add adapter manifest validation before replacing stubs with real adapters.
- E9.S2.T4: Add audit completeness checks for model, financial adapter, proposal, destination check, limit check, approval, and denial paths.

Acceptance:

- No model, financial adapter, proposal, or privileged action path can proceed without policy
  decision and audit record.

### E9.S3: Demo and release readiness

Tasks:

- E9.S3.T1: Add sample configs for Phase 1 local/dev LLM and deterministic stub responses.
- E9.S3.T2: Add sample audit, metrics, and replay outputs.
- E9.S3.T3: Document phase gate commands.
- E9.S3.T4: Keep V1 non-goals visible in demo materials.

Acceptance:

- A new developer can run the current phase demo and inspect audit, telemetry,
  policy, and replay output from documented commands.

### E9.S4: Hook-based integration tests

Tasks:

- E9.S4.T1: Add golden-path payment exception test that ingests a synthetic `payment.failed` event, runs the payment exception agent, reads permitted evidence, calls the stub payment adapter, creates an approval-required retry proposal, records hook events in the audit timeline, and replays successfully.
- E9.S4.T2: Add denied trading proposal test that proposes an action above the daily limit, emits `PreActionProposal`, receives a `tkpoly` denial, creates no execution path, records the denial in audit JSONL, and reproduces the denial in replay.
- E9.S4.T3: Add direct execution bypass test that proves the agent has no credentials or network path for direct adapter access, emits diagnostic and audit denial events, and produces no adapter result.
- E9.S4.T4: Add replay divergence test that matches a baseline case, modifies policy version or evidence hash, reports the first divergent hook, exits non-zero, and includes expected and actual hook hashes.

Acceptance:

- The phase gates prove no model call, tool call, adapter call, proposal, or
  privileged path can bypass required hooks, policy decisions, and audit
  records.

### E9.S5: Developer hook configuration and docs

Tasks:

- E9.S5.T1: Add declarative hook config fields for material, requires-policy, requires-audit, replay-required, and telemetry-only behavior.
- E9.S5.T2: Reject invalid hook config at startup, including material hooks without audit and privileged hooks without policy.
- E9.S5.T3: Include hook config version in audit records.
- E9.S5.T4: Add a development hook JSONL sink for local inspection that cannot replace `tkaudt` for material hooks and is clearly marked non-authoritative.
- E9.S5.T5: Document hook types, required and optional fields, policy-gated hooks, audit-required hooks, and examples for model calls, tool calls, adapter calls, proposals, approvals, and replay divergence.

Acceptance:

- Developers can inspect hook streams locally and build valid adapters without
  turning hooks into arbitrary plugin execution or bypassing authoritative audit.

### E9.S6: Future privileged execution hook contract

Tasks:

- E9.S6.T1: Define disabled-by-default `PrePrivilegedAction` and `PostPrivilegedAction` schemas for future `tkexec` work.
- E9.S6.T2: Include approved action id, proposal id, approval id, executor id, destination, amount, idempotency key, expected result hash, policy version/hash, and replay-safe mock mode fields.
- E9.S6.T3: Require valid approval references for any future privileged action hook.
- E9.S6.T4: Add a disabled executor stub that accepts approved mock actions only, emits privileged action hooks, and cannot reach production systems.
- E9.S6.T5: Deny and audit attempts to use the executor without approval.

Acceptance:

- V1 can test the future execution audit shape without enabling autonomous money
  movement, ledger posting, trading execution, or production connector access.
