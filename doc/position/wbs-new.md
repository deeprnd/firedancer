# Tickoni Consumer Finance V1 Work Breakdown Structure

## Purpose

This WBS implements [`roadmap-new.md`](roadmap-new.md). It replaces the
investment-only plan with a consumer-finance plan centered on safe money
decisions:

```text
invest -> pay -> move -> hold -> prove
```

The product should feel closer to Robinhood, eToro, PayPal, Payoneer,
Binance, Coinbase, or IBKR with a finance-native AI control layer underneath.
Tickoni's internal runtime remains deterministic, audited, and replayable, but
the product language is:

- Can I afford this trade?
- Is this recipient trusted?
- Is this wallet safe?
- What does this do to my cash and portfolio?
- Why was this trade, payment, transfer, or withdrawal blocked?
- What proof can I show a partner or reviewer?

## Baseline

Status: done.

Existing completed work:

- V1.0 runtime proof is complete.
- E0 runtime spike is complete.
- E1.S1 audit record schema is complete.

Do not redo this work. Use it as infrastructure for the consumer-finance
product.

## Increment Summary

| Increment | Status | Product outcome |
| --- | --- | --- |
| V1.0 | Done | Technical runtime proof: deterministic events, policy decision, audit hash chain, replay, metrics, diagnostics |
| V1.1 | Next | Investment Intent To Paper Trade: thesis becomes basket, ticket, affordability check, and paper trade |
| V1.2 | Planned | Pay And Move Money Guard: failed payment, payout, retry, or transfer becomes an allowed, blocked, or approval-required proposal |
| V1.3 | Planned | Portfolio And Cash Impact Loop: user sees portfolio, cash, pending obligation, approval, and drift impact together |
| V1.4 | Later | Social Thesis And Money Feed: user copies thesis or money templates into their own limits |
| V1.5 | Later | Crypto And Stablecoin Guard: user checks wallet, network, asset, chain-risk, and travel-rule scope before transfer proposals |
| V1.6 | Later | Guarded Broker, Payment, And Crypto Sandbox: signed sandbox adapters and read-back for approved small actions |
| V1.7 | Later | Trust Layer: signed audit, replay, attribution, and exportable money-decision records |
| V1.8 | Later | Capability Control Surface: full finance-native action classes, outcomes, scopes, limits, evidence, and approval paths |

## Product Language Rules

Use consumer-money language in product-facing docs, APIs, and demos:

- thesis
- basket
- trade ticket
- buying power
- cash available
- recipient
- beneficiary
- IBAN
- wallet
- rail
- currency
- stablecoin
- pending obligation
- trusted destination
- blocked reason
- approval-required
- max affordable amount
- max transferable amount
- money-decision proof

Keep internal runtime language inside implementation details:

- `tkmodl`
- `tktool`
- `tkadpt`
- `tkexec`
- capability envelope
- audit record
- replay capsule
- adapter manifest
- signed action envelope

## V1.1: Investment Intent To Paper Trade

### User Story

As an investor, I can type a plain-English market thesis and Tickoni turns it
into a concrete basket, checks whether I can afford it, and lets me place or
save a paper trade inside hard limits.

Example:

```text
I want to invest USD 2,000 in AI infrastructure, but avoid single-name
concentration and keep it to US-listed ETFs or large-cap equities.
```

### Product Outcome

The user gets:

- thesis summary
- explainable basket
- rejected out-of-scope instruments
- trade ticket
- buying-power and cash check
- paper execution when allowed
- blocked oversized variant with max affordable amount

### V1.1.S1: Thesis input and investor intent

Tasks:

- V1.1.S1.T1: Define a thesis input schema with user text, target notional,
  account id, market scope, asset class preference, sector/theme preference,
  risk preference, and exclusion preferences.
- V1.1.S1.T2: Add deterministic demo fixtures for AI infrastructure, US
  dividends, cyber security, broad market, and cash preservation.
- V1.1.S1.T3: Normalize thesis intent into structured fields: theme, target
  amount, allowed asset classes, excluded asset classes, market, venue, sector,
  and concentration preference.
- V1.1.S1.T4: Reject malformed thesis requests with user-readable errors.

Acceptance:

- A thesis prompt produces structured investor intent without requiring ticker
  symbols.
- Missing target amount, unsupported market, or unsupported asset class fails
  closed with a clear error.

### V1.1.S2: Investable universe and instrument catalog

Tasks:

- V1.1.S2.T1: Define an instrument catalog fixture with ticker, name, asset
  class, market, venue, sector, theme tags, risk tier, expense ratio where
  relevant, and restricted-instrument flag.
- V1.1.S2.T2: Include US-listed equity and ETF examples for AI infrastructure,
  semiconductors, cloud, cyber security, broad market, and cash-like ETFs.
- V1.1.S2.T3: Mark unsupported instruments such as options, futures, leveraged
  ETFs, inverse ETFs, non-US venues, and restricted tickers.
- V1.1.S2.T4: Add catalog lookup by theme, sector, asset class, venue, and
  ticker.

Acceptance:

- The AI infrastructure demo produces at least four eligible candidate
  instruments and at least two rejected instruments with clear reasons.

### V1.1.S3: Basket construction

Tasks:

- V1.1.S3.T1: Define a basket schema with basket id, thesis id, account id,
  target notional, candidate instruments, allocation weights, allocation
  dollars, rationale, and rejected candidates.
- V1.1.S3.T2: Generate a deterministic basket from structured thesis intent
  and instrument catalog fixtures.
- V1.1.S3.T3: Enforce scope: US market, NYSE/NASDAQ venues, equity/ETF asset
  classes, allowed sector/theme tags, and restricted-instrument denylist.
- V1.1.S3.T4: Apply simple concentration rules such as max single-name
  allocation and ETF preference when requested.
- V1.1.S3.T5: Add explainability strings that say why each instrument was
  included or rejected.

Acceptance:

- The basket allocation sums to the target notional within rounding tolerance.
- Restricted instruments are rejected before they appear in a basket.

### V1.1.S4: Demo portfolio and buying power

Tasks:

- V1.1.S4.T1: Define a demo brokerage account schema with account id, cash,
  buying power, currency, holdings, open orders, day notional used, and month
  notional used.
- V1.1.S4.T2: Add deterministic portfolio fixtures for cash-rich, low-cash,
  technology-heavy, diversified, and restricted-account examples.
- V1.1.S4.T3: Compute cash available, buying power, remaining daily notional,
  remaining monthly notional, and max affordable basket size.
- V1.1.S4.T4: Add tests for sufficient cash, insufficient cash, day-limit
  exceeded, month-limit exceeded, and open-order limit.

Acceptance:

- Given a basket and account fixture, Tickoni can say whether the account can
  afford the requested notional and what the maximum affordable amount is.

### V1.1.S5: Trade ticket and paper execution

Tasks:

- V1.1.S5.T1: Define a trade ticket schema with ticket id, basket id, account
  id, side, order type, time-in-force, target notional, estimated cost, line
  items, status, and blocked reasons.
- V1.1.S5.T2: Convert basket allocations into line-item orders using
  deterministic fixture prices.
- V1.1.S5.T3: Support buy and sell preview in paper mode.
- V1.1.S5.T4: Support `market` and `limit` order types in paper mode, with
  limit price required for limit orders.
- V1.1.S5.T5: Enforce cash, buying power, notional, market, venue, sector,
  side, order type, restricted-instrument, same-day round-trip, and minimum
  holding-period checks.
- V1.1.S5.T6: Define a paper execution result schema with paper order id,
  ticket id, account id, filled line items, simulated fill prices, timestamp,
  and resulting cash/holdings snapshot.
- V1.1.S5.T7: Allow paper execution only for tickets whose guardrail status is
  allowed.
- V1.1.S5.T8: Reject direct paper execution attempts that bypass ticket
  validation.

Acceptance:

- A USD 2,000 eligible basket is allowed in the cash-rich paper account.
- A USD 25,000 request is blocked or resized with max affordable amount and
  exact reasons.
- A blocked ticket cannot be paper-placed.

### V1.1.S6: Investment demo and proof

Tasks:

- V1.1.S6.T1: Add one local demo command or test fixture for the AI
  infrastructure thesis.
- V1.1.S6.T2: Output a polished basket, ticket, affordability check, and paper
  execution summary.
- V1.1.S6.T3: Show allowed USD 2,000 paper trade.
- V1.1.S6.T4: Show blocked USD 25,000 trade with max affordable amount.
- V1.1.S6.T5: Show rejected restricted instrument.
- V1.1.S6.T6: Emit audit-ready ticket evidence for allowed, oversized blocked,
  and restricted-instrument flows.

Acceptance:

- An exec can watch one thesis become a basket, ticket, affordability check,
  paper trade, and blocked oversized variant.
- The demo can replay without live model, broker, market, trading, payment, or
  execution effects.

Capability mapping:

```text
trading_portfolio.read
market_event.read
trading_order.recommend
trading_order.propose
trading_order.place        paper-only until later sandbox approval
```

## V1.2: Pay And Move Money Guard

### User Story

As a consumer, freelancer, or small merchant, I can ask Tickoni whether a
payment, payout, retry, or transfer is safe to propose before money moves.

Example:

```text
Retry this USD 1,240 supplier payout over ACH, but only if the recipient,
rail, currency, and retry count are still within policy.
```

### Product Outcome

The user gets:

- failed-money event summary
- trusted beneficiary or blocked destination status
- rail, currency, country, amount, retry, and timing checks
- proposed next action
- approval requirement and expiry where applicable
- draft message and evidence packet

### V1.2.S1: Payment and payout event fixtures

Tasks:

- V1.2.S1.T1: Define event fixtures for `payment_failed`,
  `settlement_delayed`, `payout_blocked`, `authorization_declined`,
  `processor_timeout`, `refund_failed`, and `capture_failed`.
- V1.2.S1.T2: Normalize payment, payout, retry, and transfer intent into
  recipient, beneficiary, IBAN, rail, currency, country, amount, processor,
  retry count, timing, KYC/AML/risk flags, and approval path.
- V1.2.S1.T3: Add deterministic processor, beneficiary, and payout-state
  fixtures.
- V1.2.S1.T4: Reject malformed or ambiguous money-movement requests.

Acceptance:

- A failed supplier payout can be inspected without direct adapter access.
- Missing beneficiary, rail, amount, or currency fails closed.

### V1.2.S2: Destination, rail, and amount checks

Tasks:

- V1.2.S2.T1: Define beneficiary and IBAN allowlist fixtures.
- V1.2.S2.T2: Enforce rail, currency, country, processor, amount, retry-count,
  retry-timing, and beneficiary/day/month limits.
- V1.2.S2.T3: Check sanctions, KYC, AML, risk, chargeback, and dispute flags
  from deterministic fixtures.
- V1.2.S2.T4: Return `allow`, `deny`, `require_approval`,
  `require_more_evidence`, or `escalate` for payment and transfer proposals.
- V1.2.S2.T5: Show user-facing reasons for blocked or approval-required
  proposals.

Acceptance:

- A safe ACH retry to a known beneficiary is allowed as a proposal.
- A retry to an unknown beneficiary is denied before adapter execution.
- A proposal missing required evidence returns `require_more_evidence`.
- A high-risk or sanctions-flagged case returns `escalate`.

### V1.2.S3: Draft response and evidence packet

Tasks:

- V1.2.S3.T1: Define a draft response schema for merchant, supplier, or
  customer-facing messages.
- V1.2.S3.T2: Define an evidence packet with source event, processor record,
  beneficiary check, rail/currency check, retry state, risk flags, and policy
  decision.
- V1.2.S3.T3: Make draft responses review-only and non-executing.
- V1.2.S3.T4: Attach evidence hashes to retry, transfer, hold, route, and
  escalation proposals.

Acceptance:

- The user can see a draft response and evidence packet without moving money.
- Draft-only outputs cannot execute payouts or transfers.

### V1.2.S4: Payment guard demo

Tasks:

- V1.2.S4.T1: Add a demo flow for a failed supplier payout.
- V1.2.S4.T2: Show safe retry proposal to a known beneficiary.
- V1.2.S4.T3: Show blocked retry to an unknown beneficiary.
- V1.2.S4.T4: Show approval-required retry over a configured amount threshold.
- V1.2.S4.T5: Show `require_more_evidence` when processor evidence is missing.
- V1.2.S4.T6: Show `escalate` when risk or sanctions fixtures require human
  review.
- V1.2.S4.T7: Emit audit and replay artifacts for allowed, blocked,
  approval-required, evidence-required, and escalated flows.

Acceptance:

- An exec can see Tickoni classify a failed payout, propose a safe retry with
  evidence, block an unsafe retry, and escalate a risky case.

Capability mapping:

```text
payment_attempt.read
processor_record.read
payment_failure.classify
payment_retry.recommend
payment_retry.propose
customer_contact.draft
bank_transfer.propose
finance_queue.route
```

## V1.3: Portfolio And Cash Impact Loop

### User Story

As a money user, I can see how an investment or payment proposal changes my
portfolio, cash, exposure, and obligations before and after I act.

### Product Outcome

The user gets:

- before/after portfolio view
- before/after cash and pending-obligation view
- thesis card
- payment or transfer proposal card
- approval and expiry state
- thesis drift and cash-buffer alerts
- rebalance suggestion in proposal/paper mode

### V1.3.S1: Portfolio and cash impact model

Tasks:

- V1.3.S1.T1: Define impact fields for cash before/after, buying power
  before/after, pending obligations, asset class exposure, sector exposure,
  ticker concentration, thesis exposure, rail exposure, destination exposure,
  and estimated order or transfer cost.
- V1.3.S1.T2: Compute impact before paper execution or payment proposal.
- V1.3.S1.T3: Compute realized paper-trade impact and pending payment impact
  separately.
- V1.3.S1.T4: Add display-ready explanations for material changes.
- V1.3.S1.T5: Add tests for increased technology exposure, cash decrease,
  pending obligation increase, approval expiry, and cash-buffer threshold.

Acceptance:

- Before acting, the user can see what changes in cash, portfolio, and pending
  obligations.

### V1.3.S2: Thesis and money proposal cards

Tasks:

- V1.3.S2.T1: Define thesis card schema with thesis id, user text, basket id,
  linked positions, target exposure, current exposure, status, created time,
  and last checked time.
- V1.3.S2.T2: Define money proposal card schema with proposal id, source event,
  beneficiary, rail, currency, amount, approval state, expiry, evidence hash,
  and status.
- V1.3.S2.T3: Save a thesis card after paper execution.
- V1.3.S2.T4: Save a payment or transfer proposal card after proposal
  generation.
- V1.3.S2.T5: Link positions and pending obligations back to their rationale
  and evidence.

Acceptance:

- The AI infrastructure thesis and supplier payout proposal both remain visible
  after the demo action.

### V1.3.S3: Drift, approval, and rebalance signals

Tasks:

- V1.3.S3.T1: Define thesis drift conditions: allocation breach, sector
  exposure breach, concentration breach, instrument no longer eligible, and
  buying-power change.
- V1.3.S3.T2: Define payment drift conditions: retry window expired,
  beneficiary limit changed, evidence expired, approval expired, approval
  revoked, or cash buffer breached.
- V1.3.S3.T3: Add deterministic market, cash, and approval-state fixtures that
  trigger drift.
- V1.3.S3.T4: Generate a rebalance suggestion without autonomous execution.
- V1.3.S3.T5: Generate a payment-proposal update without autonomous execution.

Acceptance:

- The user can preview a rebalance ticket or updated payment proposal.
- No rebalance, retry, or transfer executes without explicit user action and
  policy path.

### V1.3.S4: Portfolio and cash demo

Tasks:

- V1.3.S4.T1: Extend the V1.1 demo to show before/after portfolio state.
- V1.3.S4.T2: Extend the V1.2 demo to show before/after cash and pending
  obligation state.
- V1.3.S4.T3: Save the AI infrastructure thesis card and supplier payout
  proposal card.
- V1.3.S4.T4: Apply deterministic market movement and approval-expiry fixtures.
- V1.3.S4.T5: Show thesis drift, cash-buffer alert, approval expiry, and
  rebalance suggestion.

Acceptance:

- An exec can see investment and payment decisions in one cash/portfolio view.

## V1.4: Social Thesis And Money Feed

### User Story

As a user, I can browse thesis cards and money-decision cards, inspect their
risk checks, and copy an investing thesis or payment template into my own
account with my own limits.

Tasks:

- V1.4.T1: Define public thesis card schema.
- V1.4.T2: Define public money-template schema for payment or transfer
  patterns that do not expose private recipient data by default.
- V1.4.T3: Add shareable thesis snapshot with basket, rationale, historical
  paper performance, and risk notes.
- V1.4.T4: Add shareable payment or transfer template with rail, amount range,
  risk notes, and evidence requirements.
- V1.4.T5: Add copy-to-my-portfolio action.
- V1.4.T6: Add copy-to-my-recipient action for approved beneficiaries only.
- V1.4.T7: Resize copied thesis or money template based on user's buying
  power, cash buffer, beneficiary limits, and policy.
- V1.4.T8: Explain why the copied version differs from the original.
- V1.4.T9: Prevent copy bypass of account, instrument, venue, sector,
  beneficiary, wallet, notional, amount, or concentration limits.

Acceptance:

- A user can copy a thesis or money template but cannot bypass their own
  financial constraints.

Non-goals:

- no unbounded copy trading
- no creator-driven auto-execution
- no influencer marketplace mechanics
- no copying untrusted recipients or wallets

## V1.5: Crypto And Stablecoin Guard

### User Story

As a crypto or stablecoin user, I can ask whether a withdrawal, transfer, or
portfolio move is safe before it touches a wallet, network, or custody account.

Tasks:

- V1.5.T1: Define crypto custody account fixture with custody account, network,
  asset, wallet, amount, counterparty or exchange account, chain-risk tier, and
  travel-rule status.
- V1.5.T2: Define wallet allowlist fixtures for BTC, ETH, USDC, USDT, SOL, and
  approved test assets.
- V1.5.T3: Enforce asset allowlist, network allowlist, wallet allowlist,
  custody account scope, chain-risk tier, travel-rule status, and
  transaction/day/month limits.
- V1.5.T4: Define proposal modes for internal transfer, withdrawal, deposit
  reconciliation, and stablecoin cash movement.
- V1.5.T5: Add stablecoin cash-impact view alongside brokerage cash.
- V1.5.T6: Return `deny`, `require_approval`, `require_more_evidence`, or
  `escalate` for unsupported token, unsafe wallet, high-risk chain signal, or
  missing travel-rule evidence.
- V1.5.T7: Emit audit and replay artifacts for allowed proposal, blocked
  wallet, unsupported network, high-risk chain signal, and missing evidence.

Acceptance:

- A stablecoin transfer proposal shows wallet, network, asset, amount,
  chain-risk, travel-rule, and approval controls.
- No crypto transfer executes autonomously.

Capability mapping:

```text
crypto_transfer.propose
crypto_transfer.initiate      denied until approved sandbox/live execution
```

## V1.6: Guarded Broker, Payment, And Crypto Sandbox

### User Story

As a product evaluator, I can connect sandbox broker, payment, bank, or crypto
accounts and submit approved small actions through the same safe-action flow.

Tasks:

- V1.6.T1: Define sandbox adapter manifests for broker, payment processor,
  bank transfer, and crypto custody or wallet connectors.
- V1.6.T2: Add paper/sandbox/live mode switch with safe default to paper or
  draft-only mode.
- V1.6.T3: Add signed action envelope for approved sandbox orders, payment
  retries, transfers, and crypto withdrawals.
- V1.6.T4: Add deterministic action id and idempotency key.
- V1.6.T5: Submit sandbox actions only after capability, evidence, limit, and
  approval checks pass.
- V1.6.T6: Read back downstream status and reconcile it with the local
  proposal.
- V1.6.T7: Create mismatch note or reconciliation case when read-back differs.
- V1.6.T8: Add kill switch that blocks all sensitive execution capabilities.
- V1.6.T9: Add tests for duplicate action id, stale approval, revoked approval,
  out-of-scope destination, read-back mismatch, and kill-switch behavior.

Acceptance:

- Small eligible actions can be submitted to sandbox connectors only after
  policy, evidence, approval, signed envelope, and action-id checks pass.
- Read-back confirms status or creates a mismatch artifact.

Non-goals:

- no production live execution by default
- no margin
- no derivatives
- no autonomous execution

## V1.7: Trust Layer

### User Story

As a regulated fintech, brokerage, payments, or crypto partner, I can inspect
the proof behind each recommendation, payment proposal, transfer proposal,
trade ticket, approval, denial, and downstream result.

Tasks:

- V1.7.T1: Add money-decision audit timeline for thesis, basket, ticket,
  payment proposal, transfer proposal, crypto proposal, guardrail checks,
  approval, sandbox execution, read-back, mismatch, and impact.
- V1.7.T2: Add replay capsule for investing, payment, transfer, and crypto
  flows.
- V1.7.T3: Include policy version, policy hash, capability envelope id,
  model/tool/adapter attribution, actor id, agent identity, tool name, and
  invocation protocol.
- V1.7.T4: Include signed audit records with stable event id, timestamp,
  previous hash, input hash, output hash, result, and signature.
- V1.7.T5: Export a money-decision record for partner review.
- V1.7.T6: Show blocked, resized, approval-required, evidence-required, and
  escalated reasons in partner-facing language.
- V1.7.T7: Show model usage, adapter behavior, approval state, replay status,
  and downstream result without requiring raw-log review.

Acceptance:

- A partner can inspect how intent became a recommendation or proposal, why it
  was allowed or blocked, and how replay reproduces the decision.
- A reviewer can understand the money decision without reading raw audit JSONL
  or tile logs.

## V1.8: Capability Control Surface

### User Story

As a fintech, brokerage, payments, crypto, treasury, risk, or compliance
partner, I can see and manage the financial action classes and policy outcomes
that govern every agent recommendation, proposal, approval, denial, escalation,
and execution path.

Tasks:

- V1.8.T1: Surface a capability catalog in finance-native language.
- V1.8.T2: Add action-class view: observe, analyze, draft, recommend, propose,
  prepare, execute, override, and administer.
- V1.8.T3: Add policy outcome view: `allow`, `deny`, `require_approval`,
  `require_more_evidence`, and `escalate`.
- V1.8.T4: Add scope viewer for account, customer, merchant, legal entity,
  beneficiary, IBAN, wallet, custody account, rail, currency, country, market,
  venue, sector, instrument, order type, amount, exposure, frequency, holding
  period, risk tier, jurisdiction, and environment.
- V1.8.T5: Add later-lane templates for ledger corrections, accounting
  adjustments, reconciliation breaks, fraud/risk triage, compliance case
  preparation, treasury alerts, chargebacks, merchant risk review, bank
  transfers, crypto transfers, and trading execution.
- V1.8.T6: Add evidence prerequisite display for proposal capabilities.
- V1.8.T7: Add aggregate limit display by case, customer, account,
  beneficiary, wallet, instrument, and time window.
- V1.8.T8: Add approval-path display with approver roles, expiry, revocation,
  and maker-checker requirements.
- V1.8.T9: Add explicit denied-by-default execution and override list for
  money movement, ledger posting, payout approval, account freezing, risk-rule
  override, policy modification, and unsupported trading or crypto actions.
- V1.8.T10: Add tests proving agents cannot edit policy, expand capabilities,
  administer allowlists, or execute outside signed adapter and privileged
  executor paths.

Acceptance:

- A partner can inspect the capability catalog by action class, policy outcome,
  scope dimension, evidence prerequisite, aggregate limit, approval path, and
  denied-by-default execution or override path.

## Cross-Increment Engineering Notes

### Likely New Modules

- `src/tickoni/schema/investment.zig`
- `src/tickoni/schema/instrument.zig`
- `src/tickoni/schema/portfolio.zig`
- `src/tickoni/schema/trade_ticket.zig`
- `src/tickoni/schema/thesis.zig`
- `src/tickoni/schema/payment.zig`
- `src/tickoni/schema/transfer.zig`
- `src/tickoni/schema/crypto.zig`
- `src/tickoni/schema/money_decision.zig`
- `src/tickoni/schema/capability_catalog.zig`
- `src/tickoni/tiles/model.zig`
- `src/tickoni/tiles/tool.zig`
- `src/tickoni/tiles/adapter.zig`
- `src/tickoni/tiles/policy.zig`

### Existing Modules To Reuse

- `src/tickoni/tiles/payment_pipeline.zig` for bounded pipeline patterns,
  metrics, diagnostics, and replay examples
- `src/tickoni/tiles/audit.zig` for stable schema/hash patterns
- `src/tickoni/runtime/topology.zig` for tile ids and topology style
- `src/app/tickoni/supervisor.zig` for lifecycle and tests

### Capability Mapping

V1 consumer-finance features should map to these finance-native capabilities:

```text
trading_portfolio.read
market_event.read
trading_order.recommend
trading_order.propose
trading_order.place        paper/sandbox only until later approval

payment_attempt.read
processor_record.read
payment_failure.classify
payment_retry.recommend
payment_retry.propose
customer_contact.draft

bank_transfer.propose
crypto_transfer.propose
evidence_packet.prepare
finance_queue.route
```

Explicitly deny by default:

```text
option_order.place
future_order.place
leveraged_etf_order.place
inverse_etf_order.place
margin_order.place
crypto_transfer.initiate
bank_transfer.initiate
ledger_adjustment.post
payout.approve
account.freeze
risk_rule.override
policy.modify
```

### Increment Gate Checklist

Every increment must answer:

- What can the consumer-money user do now?
- What changed from the previous increment?
- What is the demo moment?
- Which account, beneficiary, IBAN, wallet, rail, currency, market, venue,
  asset class, instrument, notional, amount, exposure, and frequency checks are
  enforced?
- What happens when the user asks for too much money?
- What happens when an instrument, recipient, wallet, rail, or network is
  restricted?
- Is execution paper-only, draft-only, sandbox, live, or disabled?
- Which artifacts are needed for later partner trust?
- Which demo command or script closes the increment?
- Which fixture data is used for thesis, portfolio, market, payment, transfer,
  crypto, model, tool, and adapter boundaries?
- Are policy decisions, destination checks, venue checks, wallet checks, and
  limit checks visible in audit output where they apply?
- Can replay run without model, broker, payment, trading, crypto, or execution
  side effects?
- What intentional divergence or blocked-flow example proves failure behavior?

### Increment Evidence Work Items

Every increment should include these work items unless the increment explicitly
does not touch that boundary:

- G.T1: Add a documented local demo command or script.
- G.T2: Add deterministic fixtures for the product flow and each model, tool,
  adapter, market, portfolio, payment, transfer, and crypto boundary it uses.
- G.T3: Emit audit output for the material user flow.
- G.T4: Show policy, destination, venue, wallet, and limit decisions in audit
  output where they apply.
- G.T5: Export metrics or diagnostics for queue, policy, model, tool, adapter,
  audit, replay, and crash state.
- G.T6: Run replay without external model, broker, payment, trading, crypto, or
  execution side effects.
- G.T7: Include at least one blocked-flow or intentional divergence fixture.
- G.T8: Maintain a product demo checklist tied to the increment's user story.

Acceptance:

- Each increment closes with product behavior and proof artifacts, not only
  implementation tasks.

## V1 Non-Goals

V1 should not include:

- production live trading by default
- margin trading
- options, futures, leveraged ETFs, inverse ETFs, or complex derivatives
- autonomous rebalancing
- autonomous money movement
- autonomous accounting ledger posting
- autonomous account freezing
- autonomous payout approval
- autonomous compliance decisions
- quant strategy generation
- market-making
- tax optimization
- operations-heavy payment exception CaseOps workflows beyond the V1.2 payment
  guard
- reconciliation CaseOps workflows
- fraud/risk triage CaseOps workflows
- compliance case-preparation CaseOps workflows
- compliance-console-first UX
- open plugin marketplace
- generic browser automation
- arbitrary custom workflows
- full enterprise RBAC
- unbounded agent swarms
- agent-editable policy
- self-modifying agents

## Backlog: Carried-Forward Platform Features

The consumer-finance roadmap pushes deep platform hardening and
operations-heavy CaseOps behind the first money-decision loops. The features
below remain visible. Pull them forward only when they strengthen investing,
payment, transfer, crypto, trust, or capability-control flows.

## B1: Durable Runtime Proof

Product use:

Partner asks why a trade, payment, transfer, or withdrawal passed, resized,
blocked, or required approval.

Tasks:

- B1.T1: Export money-decision audit records as JSONL in append order.
- B1.T2: Verify the audit hash chain for a material money-decision run.
- B1.T3: Mark audit output incomplete on crash shutdown.
- B1.T4: Export runtime metrics for events, model calls, tool calls, guardrail
  checks, ticket decisions, proposals, paper orders, sandbox actions, replay
  status, and crash state.
- B1.T5: Export diagnostics for crashed tile id, last source offset, audit
  record count, last audit hash, replay checked, replay matched, and
  divergence count.
- B1.T6: Add one local command that runs a consumer-money demo and emits audit,
  metrics, diagnostics, and replay artifacts.
- B1.T7: Expose backpressure and queue-depth diagnostics for demo runs.
- B1.T8: Audit source events, policy decisions, destination checks, limit
  checks, model calls, tool calls, adapter calls, proposals, denials,
  approval-required decisions, evidence-required decisions, escalations,
  operator approvals, and adapter results where those events exist.

Acceptance:

- A partner can receive a durable proof bundle for one money-decision flow.

## B2: Model Gateway And Inference Governance

Product use:

Consumer-money recommendations use AI, but agents must not call providers or
local LLM servers directly.

Tasks:

- B2.T1: Define model request and response envelopes for thesis, basket,
  ticket explanation, payment explanation, draft response, cash impact, thesis
  health, crypto explanation, and partner proof outputs.
- B2.T2: Route all model requests through `tkmodl`.
- B2.T3: Add deterministic model stubs for V1 demos.
- B2.T4: Add optional local/dev LLM endpoint configuration.
- B2.T5: Add provider enum scaffolding for OpenAI, Anthropic, Qwen, DeepSeek,
  local LLM server, and future local GPU.
- B2.T6: Enforce context length, request size, retry limit, per-run token
  budget, per-role model-call limit, max output tokens, and loop step limit.
- B2.T7: Attribute model usage by role, workflow, thesis id, basket id, ticket
  id, payment proposal id, transfer proposal id, crypto proposal id, case or
  synthetic run id, account id, budget id, and policy version.
- B2.T8: Carry explicit agent identity, role, workflow, account, and policy
  version on every model request.
- B2.T9: Bound agent runs with step limits, retry limits, cancellation, and
  budget-exhaustion stop states.
- B2.T10: Replay from captured model output or deterministic fixture without
  cloud API, local LLM server, or GPU calls.

Acceptance:

- No consumer-money model call can bypass `tkmodl`.

## B3: Financial Tool Broker And Adapter Boundary

Product use:

The AI can ask for portfolio, market, payment, transfer, crypto, and sandbox
actions, but all such requests become finance-native tool or adapter requests.

Tasks:

- B3.T1: Normalize model-native function calls and MCP-compatible tool calls
  into typed consumer-money requests.
- B3.T2: Define adapter requests for portfolio read, market event read,
  instrument catalog read, ticket preview, paper order submit, payment event
  read, beneficiary read, transfer preview, crypto wallet read, crypto transfer
  preview, sandbox action submit, and read-back.
- B3.T3: Validate the finance-native capability envelope before adapter
  routing.
- B3.T4: Deny malformed, unsupported, out-of-scope, over-limit, or
  evidence-missing tool requests before adapter execution.
- B3.T5: Keep adapter credentials, broker sandbox credentials, payment
  credentials, bank credentials, and crypto credentials out of agent state.
- B3.T6: Add tests proving direct adapter access fails closed.

Acceptance:

- Agents cannot read or mutate financial state except through `tktool` and
  `tkadpt`.

## B4: Runtime Hooks For Consumer-Money Actions

Product use:

The app needs to explain why a basket, ticket, payment proposal, transfer
proposal, crypto proposal, paper order, portfolio update, cash impact, or drift
event happened.

Tasks:

- B4.T1: Define a canonical hook envelope for consumer-money actions.
- B4.T2: Add hook types for thesis created, basket generated, ticket previewed,
  ticket blocked, ticket resized, payment proposed, transfer proposed, wallet
  checked, crypto transfer proposed, paper order submitted, portfolio impact
  computed, cash impact computed, thesis card created, money proposal card
  created, drift detected, rebalance suggested, approval expired, and
  escalation created.
- B4.T3: Add `PreModelCall` and `PostModelCall` hooks.
- B4.T4: Add `PreToolUse` and `PostToolUse` hooks.
- B4.T5: Add `PreActionProposal` for trade tickets, payment retries, bank
  transfers, crypto transfer proposals, and rebalance suggestions.
- B4.T6: Add bounded hook links and route hooks to policy, audit, metrics,
  diagnostics, and replay.
- B4.T7: Add hook telemetry for counts, latency, denials, resize decisions,
  budget denials, evidence-required decisions, escalations, and replay
  divergence.

Acceptance:

- Every material consumer-money action can be explained through hook-derived
  records without showing hook mechanics to the user.

## B5: Case, Evidence, And Replay Capsule As Money History

Product use:

The user and partner can reconstruct how intent became a basket, ticket,
payment proposal, transfer proposal, crypto proposal, paper order, sandbox
action, and cash/portfolio state.

Tasks:

- B5.T1: Define deterministic thesis id, case id, or money-decision id
  derivation from account, user, source event, intent hash, and created
  sequence.
- B5.T2: Define content-addressed evidence records for model outputs,
  instrument facts, market-event fixtures, portfolio snapshots, ticket
  previews, payment records, beneficiary checks, transfer previews, wallet
  checks, crypto risk fixtures, paper order results, sandbox read-back, and
  drift events.
- B5.T3: Store evidence hashes on thesis cards, trade tickets, payment
  proposal cards, transfer proposal cards, and crypto proposal cards.
- B5.T4: Define replay capsule schema for source intent, normalized request,
  proposal, guardrail decisions, model outputs, tool outputs, adapter fixtures,
  action result, impact, and final state.
- B5.T5: Replay money-decision flows without live model, market, broker,
  payment, bank, crypto, or adapter effects.
- B5.T6: Report first divergence by intent hash, proposal hash, policy version,
  evidence hash, model output hash, adapter output hash, action id, or
  portfolio/cash state hash.

Acceptance:

- A money-decision flow can be replayed from captured inputs and reports the
  first divergence.

## B6: Partner API And Review Surface

Product use:

Partners need APIs to inspect accounts, thesis cards, payment proposals,
transfer proposals, crypto proposals, proof artifacts, and replay status.

Tasks:

- B6.T1: Add authenticated API for thesis creation, basket read, ticket
  preview, paper order submit, payment event read, transfer proposal, crypto
  proposal, portfolio read, money proposal status read, and money-decision
  export.
- B6.T2: Validate source identity, idempotency key, account id, event
  timestamp, payload size, environment, and required financial fields.
- B6.T3: Return accepted, duplicate, malformed, or rejected responses.
- B6.T4: Add partner-facing timeline read endpoint for thesis, basket, ticket,
  payment proposal, transfer proposal, crypto proposal, guardrails, paper
  order, sandbox action, portfolio impact, cash impact, and drift.
- B6.T5: Add replay status endpoint.
- B6.T6: Add integration tests for valid, duplicate, malformed, oversized,
  unauthorized, and environment-mismatch requests.
- B6.T7: Add operator or partner review surface that shows recommendation
  evidence, policy decision, model usage, adapter behavior, approval state,
  capability outcome, and replay status without raw-log review.

Acceptance:

- A partner can integrate the consumer-money flow without direct access to
  model, tool, adapter, or executor internals.

## B7: Approval And Execution Trust

Product use:

Paper trading and draft proposals are allowed early. Broker, payment, bank,
crypto sandbox, and live execution need approval and signed controls.

Tasks:

- B7.T1: Hash-bind trade tickets, payment proposals, transfer proposals, crypto
  proposals, and rebalance suggestions.
- B7.T2: Add approval state for sandbox or live execution modes when
  configured.
- B7.T3: Add approval granted, rejected, expired, and revoked records.
- B7.T4: Add signed action envelope for approved sandbox actions.
- B7.T5: Add deterministic action id and idempotency key.
- B7.T6: Add privileged executor boundary for approved sandbox actions.
- B7.T7: Add read-back and mismatch handling.
- B7.T8: Add kill switch that blocks all sensitive execution capabilities
  immediately.
- B7.T9: Add destination and venue allowlists for broker account, market,
  exchange, sector, instrument, beneficiary, IBAN, wallet, custody account,
  network, and asset.
- B7.T10: Explicitly deny direct order placement, autonomous money movement,
  autonomous ledger posting, account freezing, payout approval, compliance
  decisions, and policy modification outside an approved executor path.

Acceptance:

- No sandbox or live action can execute outside account, destination, amount,
  frequency, approval, and action-id scope.

## B8: Operations-Heavy Workflow Shelf

Product use:

These were part of the original fintech-operations roadmap. Keep them visible
as later product lines, not the first consumer-money V1 path.

Backlog items:

- B8.T1: Payment exception CaseOps workflow beyond the V1.2 payment guard.
- B8.T2: Reconciliation break workflow: ledger mismatch evidence, discrepancy
  explanation, correction proposal.
- B8.T3: Fraud/risk triage workflow: suspicious activity evidence, severity
  classification, review queue recommendation.
- B8.T4: Compliance case-preparation workflow.
- B8.T5: CaseOps operations board for non-consumer-money workflows.
- B8.T6: TigerBeetle accounting ledger connector behind `tkexec`.
- B8.T7: Banking, crypto, payment, risk, and compliance adapters.
- B8.T8: Maker-checker approval workflows for money movement and ledger
  posting.
- B8.T9: Policy templates for payment, reconciliation, fraud/risk, banking
  destination, crypto destination, and compliance workflows.
- B8.T10: Demo adapter fixtures and replayable sample data for each shelved
  workflow family.
- B8.T11: Replay capsules for payment exception, reconciliation break,
  fraud/risk, and compliance demos.

Acceptance:

- These remain documented as later work and do not dilute consumer-money V1.

## B9: Build, Quality, Security, And Release Hygiene

Product use:

Consumer-money demos must be impressive without weakening Tickoni's safety
claim.

Tasks:

- B9.T1: Add one local verification command per increment.
- B9.T2: Keep Zig harness tests wired through `zig build test`.
- B9.T3: Add focused tests for thesis schema, instrument catalog, basket
  generation, portfolio fixtures, trade tickets, payment fixtures, transfer
  fixtures, crypto fixtures, guardrails, paper execution, thesis cards, money
  proposal cards, and drift rules.
- B9.T4: Add security tests for forbidden shell access, forbidden direct
  network access, forbidden direct adapter access, and forbidden direct
  execution paths as soon as each path exists.
- B9.T5: Add fail-closed tests for malformed capability envelopes, malformed
  hooks, unknown providers, missing allowlists, invalid limits, environment
  mismatch, unsupported instruments, unknown beneficiaries, unsafe wallets, and
  unsupported networks.
- B9.T6: Add adapter manifest validation before sandbox integration.
- B9.T7: Add sample configs and sample outputs for investing, payment,
  transfer, crypto, trust, and capability-control flows.
- B9.T8: Keep consumer-finance V1 non-goals visible in demo docs.
- B9.T9: Add fail-closed validation tests for policy, model, adapter,
  destination allowlist, amount limits, exposure limits, frequency limits, and
  holding-period configuration.
- B9.T10: Add audit JSONL samples with valid hash chains for main demos and
  blocked-flow demos.
- B9.T11: Add metrics and diagnostics samples for each increment.
- B9.T12: Add replay match samples and intentional divergence outputs.
- B9.T13: Add case, thesis, payment, transfer, crypto, and capability fixture
  sets and replay capsule samples.
- B9.T14: Add API integration tests for external ingestion and partner review
  endpoints when those endpoints exist.
- B9.T15: Add approval, rejection, evidence-required, and escalation audit
  samples when those paths exist.
- B9.T16: Keep increment status updates tied to V1 success metrics.

Acceptance:

- Each increment has a local command and focused tests proving the consumer
  flow, blocked paths, and no-bypass safety conditions.
- Each increment has evidence artifacts strong enough for an engineering,
  risk/compliance, or partner reviewer.
