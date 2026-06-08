# Feature: Runtime Hooks for Auditable Agentic Finance

## Feature Summary

Implement a first-class runtime hook system for Tickoni so every meaningful agent, model, tool, adapter, policy, proposal, approval, and replay event is intercepted, policy-checked, audit-recorded, and replay-addressable.

This feature turns hooks into the concrete enforcement layer between:

```text
tkdisp -> tkagnt -> tkmodl
tkagnt -> tktool -> tkadpt
tkpoly -> tkaudt
tkrepl -> replay comparison
tkapi -> CaseOps audit timeline
future tkexec -> approved privileged execution
```

Hooks are not optional log callbacks. Hooks are the mandatory runtime checkpoints that make the agent harness auditable, transparent, bounded, and replayable.

## Design Principle

```text
Every agent action is a hook event.
Every hook event has an envelope.
Every envelope is policy-evaluated.
Every policy result is audit-recorded.
Every audit record is hash-chained.
Every material case can be replayed.
Every privileged effect is outside the agent.
```

## Runtime Flow

### Normal Agent Investigation Flow

```text
financial event
  -> tkings
  -> tknorm
  -> tkdedu
  -> tkcase
  -> tkpoly
  -> tkaudt
  -> tkdisp
  -> tkagnt

tkagnt emits AgentRunStarted hook
  -> tkaudt records run start

tkagnt requests model call
  -> PreModelCall hook
  -> tkpoly checks model capability, budget, context limits
  -> tkaudt records decision
  -> tkmodl performs model call
  -> PostModelCall hook
  -> tkaudt records model output hash, token usage, latency

model requests tool call
  -> PreToolUse hook
  -> tkpoly checks capability envelope
  -> tkaudt records allow / deny / require approval
  -> tktool executes allowed call through tkadpt
  -> PostToolUse hook
  -> tkaudt records adapter result hash, timing, result state

agent proposes action
  -> PreProposal hook
  -> tkpoly checks destination, amount, frequency, risk level
  -> tkaudt records proposal and decision
  -> CaseOps shows proposal

operator approves
  -> ApprovalRequested hook
  -> ApprovalResolved hook
  -> tkaudt records approver, decision, expiry, scope

future executor attempts mutation
  -> PrePrivilegedAction hook
  -> tkpoly verifies approval and policy version
  -> tkexec executes
  -> PostPrivilegedAction hook
  -> tkaudt records result
```

### Replay Flow

```text
replay capsule
  -> tkrepl disables external effects
  -> deterministic mock model/tool/adapter responses
  -> hook events are regenerated
  -> tkaudt comparison mode verifies expected hashes
  -> first divergence is reported
```

## Hook Event Types

### Agent Lifecycle Hooks

* `AgentRunStarted`
* `AgentRunCompleted`
* `AgentRunFailed`
* `AgentRunBudgetExceeded`
* `AgentRunCancelled`

### Model Hooks

* `PreModelCall`
* `PostModelCall`
* `ModelCallDenied`
* `ModelCallBudgetExceeded`
* `ModelCallReplaySubstituted`

### Tool / Adapter Hooks

* `PreToolUse`
* `PostToolUse`
* `ToolUseDenied`
* `ToolUseApprovalRequired`
* `AdapterCallStarted`
* `AdapterCallCompleted`
* `AdapterCallFailed`

### Finance Proposal Hooks

* `PreActionProposal`
* `PostActionProposal`
* `ProposalDenied`
* `ProposalApprovalRequired`
* `ProposalExpired`
* `ProposalSuperseded`

### Approval Hooks

* `ApprovalRequested`
* `ApprovalGranted`
* `ApprovalRejected`
* `ApprovalExpired`
* `ApprovalRevoked`

### Case Hooks

* `CaseCreated`
* `CaseStateChanged`
* `EvidenceAttached`
* `AgentFindingAttached`
* `PolicyDecisionAttached`
* `ReplayCapsuleSealed`

### Privileged Execution Hooks

* `PrePrivilegedAction`
* `PostPrivilegedAction`
* `PrivilegedActionDenied`
* `PrivilegedActionFailed`
* `PrivilegedActionReconciled`

### Replay Hooks

* `ReplayStarted`
* `ReplayHookMatched`
* `ReplayHookDiverged`
* `ReplayCompleted`

---

# Epic 1: Hook Envelope and Runtime Event Contract

## Goal

Define the canonical event envelope used by all hookable actions in the Tickoni runtime.

## User Story 1.1: Define canonical hook envelope

As a Tickoni runtime maintainer, I need a canonical hook envelope so every agent, model, tool, policy, and execution event has the same minimum auditable structure.

### Acceptance Criteria

* A `HookEnvelope` schema exists in the runtime.
* Envelope includes:

  * `hook_event_id`
  * `hook_type`
  * `timestamp_ns`
  * `case_id`
  * `run_id`
  * `actor_type`
  * `actor_id`
  * `agent_id`
  * `workflow`
  * `environment`
  * `policy_version`
  * `capability`
  * `risk_level`
  * `input_hash`
  * `output_hash`
  * `previous_audit_hash`
  * `schema_version`
* Envelope supports optional fields for:

  * `model_id`
  * `tool_name`
  * `adapter_id`
  * `approval_id`
  * `proposal_id`
  * `downstream_action_id`
  * `token_usage`
  * `latency_ns`
  * `resource_usage`
  * `error_code`
* Envelope serialization is deterministic.
* Envelope hash is stable across process restarts.
* Tests prove identical input produces identical hook hash.

## User Story 1.2: Add hook type registry

As a Tickoni developer, I need a typed hook registry so new hooks can be added without creating unstructured log events.

### Acceptance Criteria

* Hook type enum exists.
* Unknown hook type is rejected.
* Hook type maps to allowed required fields.
* Tests cover valid and invalid hook types.
* Registry is versioned.

## User Story 1.3: Add hook validation

As a Tickoni runtime maintainer, I need hook envelopes validated before entering audit so malformed or incomplete audit events cannot corrupt replay.

### Acceptance Criteria

* Missing required fields reject the hook.
* Invalid enum values reject the hook.
* Invalid hash format rejects the hook.
* Invalid timestamp format rejects the hook.
* Rejections are themselves audit-recorded as malformed hook events.
* Malformed hook event does not advance case state.

---

# Epic 2: Hook Bus and Tile Integration

## Goal

Create a bounded runtime hook bus that routes hook events from agent/model/tool tiles to policy, audit, metrics, diagnostics, and replay.

## User Story 2.1: Implement bounded hook link

As a systems engineer, I need hook events to move over bounded links so hooks preserve Tickoni’s backpressure and ownership model.

### Acceptance Criteria

* `tkagnt_hook` link exists.
* `tkmodl_hook` link exists.
* `tktool_hook` link exists.
* `tkadpt_hook` link exists.
* Correctness-bearing hook links are reliable and bounded.
* Overrun behavior is explicit.
* Metrics expose queue depth and dropped telemetry events.
* Tests simulate hook queue saturation.

## User Story 2.2: Add hook dispatcher

As a runtime maintainer, I need a hook dispatcher so hook events are routed to policy, audit, metrics, diagnostics, and replay consumers.

### Acceptance Criteria

* Dispatcher accepts validated hook envelopes.
* Dispatcher routes policy-bearing hooks to `tkpoly`.
* Dispatcher routes audit-bearing hooks to `tkaudt`.
* Dispatcher routes metrics to `tkmetr`.
* Dispatcher routes diagnostics to `tkdiag`.
* Dispatcher supports replay mode.
* Dispatcher has no model or adapter network access.

## User Story 2.3: Add hook failure behavior

As an operator, I need hook failure behavior to be safe by default so audit outages cannot silently allow unaudited financial actions.

### Acceptance Criteria

* If audit hook write fails, privileged action is blocked.
* If policy hook check fails, action is denied by default.
* If telemetry hook fails, action may continue but loss is counted.
* If replay hook comparison fails, replay reports divergence.
* Failure modes are documented.

---

# Epic 3: Policy-Gated Model Hooks

## Goal

Ensure every model call passes through `PreModelCall` and `PostModelCall` hooks for budget enforcement, model routing control, prompt capture, response hashing, and audit replay.

## User Story 3.1: Add `PreModelCall` hook in `tkagnt -> tkmodl`

As a platform operator, I need every model call checked before execution so agents cannot exceed model, context, or budget limits.

### Acceptance Criteria

* `tkagnt` cannot call `tkmodl` without emitting `PreModelCall`.
* `PreModelCall` includes:

  * `case_id`
  * `agent_id`
  * `model_route`
  * `requested_model`
  * `prompt_hash`
  * `context_hash`
  * `estimated_input_tokens`
  * `case_budget_remaining`
  * `agent_budget_remaining`
  * `policy_version`
* `tkpoly` can return `allow`, `deny`, or `require_approval`.
* Denied model calls do not reach `tkmodl`.
* Denied model calls are audit-recorded.

## User Story 3.2: Add `PostModelCall` hook

As an auditor, I need every model response captured by hash and usage metadata so model behavior can be reconstructed without storing sensitive payloads everywhere.

### Acceptance Criteria

* `PostModelCall` emits after every model response.
* Hook includes:

  * `model_id`
  * `provider_id`
  * `request_hash`
  * `response_hash`
  * `input_tokens`
  * `output_tokens`
  * `total_tokens`
  * `latency_ns`
  * `finish_reason`
  * `cost_estimate`
* Token usage updates case and agent budgets.
* Model errors emit `ModelCallFailed`.
* Model response payload is content-addressed.

## User Story 3.3: Enforce retry-loop limits

As a platform operator, I need retry loops bounded so agent inference spend cannot grow without limit.

### Acceptance Criteria

* Per-agent retry limit is configurable.
* Per-case retry limit is configurable.
* Retry count is attached to model hook envelope.
* Exceeding limit emits `AgentRunBudgetExceeded`.
* Exceeding limit stops the run.
* Audit records include retry-loop termination reason.

---

# Epic 4: Policy-Gated Tool and Adapter Hooks

## Goal

Ensure all model-native function calls, MCP-compatible tool calls, and financial adapter calls terminate at the same `tktool` boundary and are governed by capability envelopes.

## User Story 4.1: Normalize tool calls into capability envelopes

As a runtime maintainer, I need tool requests normalized so model-native function calls and MCP requests are evaluated identically.

### Acceptance Criteria

* Tool request schema supports:

  * `tool_name`
  * `tool_protocol`
  * `adapter_id`
  * `capability`
  * `case_scope`
  * `financial_object_scope`
  * `destination_scope`
  * `amount`
  * `currency`
  * `frequency_key`
  * `risk_level`
* MCP-compatible tools and native function calls produce the same envelope.
* Invalid tool arguments are rejected before adapter execution.
* Rejected calls are audit-recorded.

## User Story 4.2: Add `PreToolUse` hook

As an auditor, I need every tool call checked before execution so no agent can access evidence, adapters, or financial APIs outside scope.

### Acceptance Criteria

* `PreToolUse` fires before every `tktool` execution.
* `tkpoly` evaluates capability scope.
* Denied tool calls never reach `tkadpt`.
* Approval-required calls are paused.
* All decisions are recorded in `tkaudt`.
* Tests cover allow, deny, and approval-required outcomes.

## User Story 4.3: Add `PostToolUse` hook

As an auditor, I need every adapter result recorded so downstream evidence and case decisions are traceable.

### Acceptance Criteria

* `PostToolUse` fires after every allowed tool call.
* Hook includes:

  * `tool_name`
  * `adapter_id`
  * `input_hash`
  * `output_hash`
  * `latency_ns`
  * `result_status`
  * `error_code`
  * `evidence_ref`
* Adapter output is content-addressed.
* Case evidence can link to the adapter output.
* Adapter failures are audit-recorded.

## User Story 4.4: Block direct adapter access from agents

As a security engineer, I need agents prevented from bypassing `tktool` so policy and audit cannot be skipped.

### Acceptance Criteria

* Agent process has no direct adapter credentials.
* Agent process has no unrestricted network path to financial APIs.
* Adapter credentials are held only by signed adapter or executor path.
* Tests prove agent cannot call stub payment/trading adapter directly.
* Direct call attempt emits diagnostic and audit denial.

---

# Epic 5: Finance-Native Proposal Hooks

## Goal

Represent money-adjacent agent outputs as signed proposals rather than direct actions.

## User Story 5.1: Define action proposal schema

As a finance operations user, I need agent recommendations represented as formal proposals so they can be reviewed, approved, rejected, expired, and replayed.

### Acceptance Criteria

* Proposal schema includes:

  * `proposal_id`
  * `case_id`
  * `agent_id`
  * `workflow`
  * `proposed_action`
  * `financial_object`
  * `destination`
  * `amount`
  * `currency`
  * `limit_scope`
  * `frequency_scope`
  * `required_approval_role`
  * `expires_at_ns`
  * `proposal_hash`
  * `policy_version`
* Proposal is immutable after creation.
* Amendments create new proposal versions.
* Superseded proposals remain auditable.

## User Story 5.2: Add `PreActionProposal` hook

As a risk reviewer, I need proposed financial actions checked before they appear as valid proposals.

### Acceptance Criteria

* Agent cannot create proposal without `PreActionProposal`.
* Policy checks:

  * action class
  * amount limit
  * destination allowlist
  * frequency limit
  * approval requirement
  * environment
  * case scope
* Out-of-scope proposal is denied.
* Approval-required proposal is visible but not executable.
* Denial reason is shown in audit timeline.

## User Story 5.3: Add signed proposal output

As an auditor, I need proposals signed or hash-bound so later execution cannot substitute a different action.

### Acceptance Criteria

* Proposal hash covers all material fields.
* Proposal hash is included in audit record.
* Approval references proposal hash.
* Future execution references proposal hash.
* Mutating proposal content invalidates signature/hash comparison.

---

# Epic 6: Approval Hooks and CaseOps Visibility

## Goal

Expose hook-generated policy and approval state to operators in CaseOps.

## User Story 6.1: Add approval request hooks

As an operator, I need approval-required actions to become reviewable CaseOps items.

### Acceptance Criteria

* `ApprovalRequested` hook is emitted for approval-required proposal.
* Approval includes:

  * `approval_id`
  * `proposal_id`
  * `case_id`
  * `required_role`
  * `requested_by_agent`
  * `policy_version`
  * `expires_at_ns`
* CaseOps API can list pending approvals.
* Approval request appears on case card.

## User Story 6.2: Add approval resolution hooks

As an auditor, I need approval decisions recorded with scope and expiry.

### Acceptance Criteria

* `ApprovalGranted`, `ApprovalRejected`, and `ApprovalExpired` hooks exist.
* Approval record includes:

  * approver identity
  * role
  * timestamp
  * reason
  * approval scope
  * expiry
  * proposal hash
* Rejected approval blocks execution.
* Expired approval blocks execution.
* All approval outcomes appear in audit timeline.

## User Story 6.3: Add audit timeline view

As an auditor, I need a timeline showing agent, model, tool, policy, proposal, approval, and replay events for a case.

### Acceptance Criteria

* CaseOps timeline shows hook events in order.
* Timeline groups events by:

  * event ingestion
  * agent run
  * model calls
  * tool calls
  * policy decisions
  * proposals
  * approvals
  * replay
* Denied actions are visible.
* Approval-required actions are visible.
* Timeline can filter by hook type.
* Timeline can export JSONL audit slice.

---

# Epic 7: Audit Journal Hook Integration

## Goal

Make hook events first-class audit records in `tkaudt`.

## User Story 7.1: Convert hook envelope to audit record

As a runtime maintainer, I need every material hook to become a hash-chained audit record.

### Acceptance Criteria

* `tkaudt` accepts hook envelopes.
* `tkaudt` assigns `audit_event_id`.
* `tkaudt` links `previous_hash`.
* `tkaudt` computes `record_hash`.
* Hook-derived audit records are exported as JSONL.
* Hash-chain verification detects tampering.

## User Story 7.2: Add content-addressed payload references

As a privacy/security engineer, I need large or sensitive payloads referenced by hash instead of copied into every audit row.

### Acceptance Criteria

* Prompt payloads are stored by content address.
* Model responses are stored by content address.
* Tool inputs and outputs are stored by content address.
* Evidence blobs are stored by content address.
* Audit records contain hashes and references.
* Missing content-addressed object is detected during replay validation.

## User Story 7.3: Add audit verification command

As an auditor, I need a command to verify hook-derived audit records.

### Acceptance Criteria

* CLI command exists:

  * `tickoni audit verify <case_id>`
  * `tickoni audit verify --jsonl <path>`
* Command verifies:

  * hash chain
  * schema version
  * required fields
  * content-addressed references
  * policy decision presence
* Command reports first invalid record.
* Command exits non-zero on failure.

---

# Epic 8: Replay Capsules for Hooked Agent Runs

## Goal

Create replay capsules that can reproduce and compare case-level agent runs without invoking privileged external effects.

## User Story 8.1: Generate replay capsule from case

As an engineer, I need a replay capsule for each material case so agent behavior can be reproduced and compared.

### Acceptance Criteria

* Capsule includes:

  * source event hashes
  * normalized event hashes
  * case ID
  * case state hashes
  * policy version/hash
  * agent run ID
  * model request/response hashes or replay substitutes
  * tool call hashes
  * adapter result hashes
  * proposal hashes
  * approval records
  * expected final state hash
* Capsule is content-addressed.
* Capsule can be exported.
* Capsule is linked from CaseOps.

## User Story 8.2: Replay model calls without provider access

As a developer, I need replay to avoid live model calls so replay is deterministic and cheap.

### Acceptance Criteria

* Replay mode substitutes recorded model outputs.
* `PreModelCall` and `PostModelCall` hooks still fire in replay mode.
* Replay records `ModelCallReplaySubstituted`.
* Divergence is reported if prompt/context hash differs.
* Replay never calls external model provider by default.

## User Story 8.3: Replay tool calls without external mutation

As a security engineer, I need replay to avoid external adapter mutations.

### Acceptance Criteria

* Replay mode uses deterministic stub adapter outputs.
* External effects are disabled.
* Privileged action hooks are simulated only.
* Replay fails if a live adapter is called.
* Replay reports first divergent hook event.

---

# Epic 9: Telemetry and Diagnostics for Hooks

## Goal

Expose hook runtime behavior so operators can see agentic workload cost, latency, CPU/tool bottlenecks, denials, approvals, and replay divergence.

## User Story 9.1: Add hook metrics

As an operator, I need hook-level metrics to understand agent runtime behavior.

### Acceptance Criteria

* Metrics include:

  * hook count by type
  * policy allow/deny/approval counts
  * model call count
  * tool call count
  * adapter call latency
  * token usage by case
  * token usage by agent
  * budget-denial count
  * approval-required count
  * replay-divergence count
* Metrics are exported through `tkmetr`.
* Metrics are visible in dev telemetry endpoint.

## User Story 9.2: Add hook diagnostics

As an engineer, I need diagnostics for hook failures and queue pressure.

### Acceptance Criteria

* Diagnostics include:

  * hook queue depth
  * hook queue overrun
  * hook validation failure
  * audit write failure
  * policy timeout
  * adapter timeout
  * model timeout
* Diagnostics are exported through `tkdiag`.
* Failure records include tile ID and hook type.

## User Story 9.3: Add CPU/tool timing report

As a performance engineer, I need to measure time spent in model calls, tool calls, adapter calls, policy checks, and idle gaps.

### Acceptance Criteria

* Hook timestamps allow latency breakdown by phase.
* Report includes:

  * total agent run duration
  * model time
  * tool/adapter time
  * policy time
  * approval wait time
  * idle time
  * replay time
* Report can be generated per run and per case.
* JSON output is available for automated tests.

---

# Epic 10: Hook-Based Test Harness

## Goal

Provide integration tests proving hooks enforce policy, audit, replay, and isolation.

## User Story 10.1: Add golden path payment exception test

As a maintainer, I need a full end-to-end payment exception test so the hook system proves useful workflow behavior.

### Acceptance Criteria

* Synthetic `payment.failed` event creates deterministic case.
* Payment exception agent runs.
* Agent reads permitted evidence.
* Agent calls stub payment adapter.
* Agent proposes retry path.
* Proposal requires approval.
* Audit timeline includes all hook events.
* Replay matches.

## User Story 10.2: Add denied trading proposal test

As a risk reviewer, I need out-of-scope trading proposals denied and audited.

### Acceptance Criteria

* Agent proposes trading action above daily limit.
* `PreActionProposal` fires.
* `tkpoly` denies.
* No execution path is created.
* Denial appears in audit JSONL.
* Replay reproduces denial.

## User Story 10.3: Add direct execution bypass test

As a security engineer, I need proof that agents cannot bypass hooks or policy.

### Acceptance Criteria

* Agent attempts direct adapter call.
* Agent has no credentials.
* Network/path is blocked.
* Attempt emits diagnostic event.
* Attempt emits audit denial.
* Test passes only if no adapter result is produced.

## User Story 10.4: Add replay divergence test

As a maintainer, I need replay to detect changed policy or changed evidence.

### Acceptance Criteria

* Baseline case replay matches.
* Modify policy version or evidence hash.
* Replay reports first divergent hook.
* Replay exits non-zero.
* Divergence report includes expected and actual hook hashes.

---

# Epic 11: Developer-Facing Hook Configuration

## Goal

Allow Tickoni developers to configure hook behavior safely without turning hooks into arbitrary plugin execution.

## User Story 11.1: Add declarative hook policy config

As a developer, I need declarative hook configuration for which hooks are material, auditable, policy-gated, or telemetry-only.

### Acceptance Criteria

* Config supports:

  * `material: true/false`
  * `requires_policy: true/false`
  * `requires_audit: true/false`
  * `replay_required: true/false`
  * `telemetry_only: true/false`
* Invalid config is rejected at startup.
* Material hooks cannot disable audit.
* Privileged hooks cannot disable policy.
* Config version is included in audit records.

## User Story 11.2: Add development hook sink

As a developer, I need a local hook sink to inspect hook events during development.

### Acceptance Criteria

* Dev mode can write hook stream to JSONL.
* Hook JSONL includes all validated envelopes.
* Dev sink cannot replace `tkaudt` for material hooks.
* Dev sink is clearly marked non-authoritative.

## User Story 11.3: Add hook schema documentation

As an adapter developer, I need hook schema docs so signed adapters produce valid events.

### Acceptance Criteria

* Docs list all hook types.
* Docs list required and optional fields.
* Docs include examples for:

  * model call
  * tool call
  * adapter call
  * proposal
  * approval
  * replay divergence
* Docs specify which hooks are policy-gated.
* Docs specify which hooks are audit-required.

---

# Epic 12: Future Privileged Execution Hooks

## Goal

Prepare the hook system for `tkexec` without allowing autonomous money movement in V1.

## User Story 12.1: Define privileged action hook contract

As a future executor maintainer, I need a privileged action hook contract so approved mutations can be added later without changing the audit model.

### Acceptance Criteria

* `PrePrivilegedAction` schema exists.
* `PostPrivilegedAction` schema exists.
* Schema includes:

  * `approved_action_id`
  * `proposal_id`
  * `approval_id`
  * `executor_id`
  * `destination`
  * `amount`
  * `idempotency_key`
  * `expected_result_hash`
* Contract requires valid approval reference.
* Contract requires policy version/hash.
* Contract requires replay-safe mock mode.

## User Story 12.2: Add disabled-by-default executor stub

As a maintainer, I need an executor stub so the runtime path can be tested without real money movement.

### Acceptance Criteria

* `tkexec` stub cannot reach production systems.
* Stub accepts approved mock actions only.
* Stub emits privileged action hooks.
* Stub execution is disabled by default.
* Attempting to use executor without approval is denied and audited.

---

# MVP Cut Line

## MVP Must Include

* Hook envelope schema
* Hook type registry
* Bounded hook links
* `PreModelCall` / `PostModelCall`
* `PreToolUse` / `PostToolUse`
* `PreActionProposal`
* Hook-to-audit integration
* Policy allow/deny/approval-required decisions
* Content-addressed payload references
* Basic replay capsule
* Hook metrics
* End-to-end payment exception test
* Denied trading proposal test
* Direct bypass test

## MVP Should Exclude

* Production payment connector
* Production trading connector
* Production ledger mutation
* Arbitrary user-defined shell hooks
* Open plugin marketplace
* Natural-language policy editing
* Autonomous execution
* Multi-agent swarms

## MVP Demo Script

```text
1. Ingest synthetic payment.failed event.
2. Runtime creates deterministic case.
3. Payment exception agent starts.
4. PreModelCall hook checks budget and model route.
5. Model output requests processor evidence.
6. PreToolUse hook checks evidence-read capability.
7. Stub payment adapter returns evidence.
8. PostToolUse hook records output hash.
9. Agent proposes retry path.
10. PreActionProposal hook checks rail, amount, destination, frequency, approval.
11. Policy returns approval_required.
12. CaseOps shows proposal and audit timeline.
13. Operator approves or rejects.
14. Replay capsule is generated.
15. Replay reproduces hook sequence without external effects.
```

## Definition of Done

The feature is complete when:

* No model call can occur without a hook.
* No tool call can occur without a hook.
* No proposal can appear without policy evaluation.
* No approval-required action can proceed without approval state.
* No privileged path exists for agents.
* Every material hook is in the audit hash chain.
* Replay can compare hook sequences.
* Denied actions are as visible as allowed actions.
* CaseOps can show the full timeline.
* Tests prove bypass attempts fail.
