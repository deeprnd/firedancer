# Tickoni Investment V1 Work Breakdown Structure

## Purpose

This WBS implements [`roadmap-new.md`](roadmap-new.md). It replaces the
operations-first WBS with an investment-first product plan.

The new V1 story is:

```text
thesis -> basket -> buying-power checked trade ticket -> paper trade
       -> portfolio impact -> thesis monitoring
```

The user-facing product should feel like an AI-native investing app, closer to
a trading platform than to a governance console. Tickoni's finance-native
capability model still powers the guardrails, but the product language is:

- Can I afford this trade?
- Does this fit my portfolio?
- Which instruments express my thesis?
- What changed after the trade?
- Why was this trade resized or blocked?

## Baseline

Status: done.

Existing completed work:

- V1.0 runtime proof is complete.
- E0 runtime spike is complete.
- E1.S1 audit record schema is complete.

Do not redo this work. Use it as infrastructure for the investing product.

## Increment Summary

| Increment | Status | Product outcome |
| --- | --- | --- |
| V1.0 | Done | Technical runtime proof: deterministic events, policy decision, audit hash chain, replay, metrics, diagnostics |
| V1.1 | Next | Thesis To Basket: user turns a plain-English investment thesis into an explainable basket |
| V1.2 | Planned | Buying-Power Trade Ticket: user turns the basket into a sized paper trade and sees affordability checks |
| V1.3 | Planned | Portfolio Impact Loop: user sees before/after portfolio impact and tracks thesis drift |
| V1.4 | Later | Guarded Live-Trading Sandbox: broker sandbox connector and signed paper/live execution boundary |
| V1.5 | Later | Social Thesis Feed: copy a thesis into the user's own portfolio with account-specific checks |
| V1.6 | Later | Trust Layer: audit, replay, and policy proof for fintech/brokerage partners |

## Product Language Rules

Use investor language in product-facing docs, APIs, and demos:

- thesis
- basket
- portfolio
- buying power
- cash available
- estimated cost
- remaining cash
- max affordable amount
- exposure
- concentration
- watchlist
- paper trade
- trade ticket
- blocked reason
- resize suggestion
- thesis drift

Keep internal runtime language inside implementation details:

- `tkmodl`
- `tktool`
- `tkadpt`
- policy envelope
- audit record
- replay capsule
- adapter manifest

## V1.1: Thesis To Basket

### User Story

As an investor, I can type a plain-English market thesis and Tickoni turns it
into a concrete investment basket.

Example thesis:

```text
I want to invest USD 2,000 in AI infrastructure, but avoid single-name
concentration and keep it to US-listed ETFs or large-cap equities.
```

### Product Outcome

The user gets:

- a concise thesis summary
- a list of candidate instruments
- proposed dollar and percent allocation
- explanation for each instrument
- rejected instruments with clear reasons
- a basket that can become a trade ticket in V1.2

### V1.1.S1: Thesis input and investor intent

Tasks:

- V1.1.S1.T1: Define a thesis input schema with user text, target notional, account id, market scope, asset class preference, sector/theme preference, risk preference, and exclusion preferences.
- V1.1.S1.T2: Add deterministic demo fixtures for common thesis prompts such as AI infrastructure, US dividends, cyber security, broad market, and cash preservation.
- V1.1.S1.T3: Normalize thesis intent into structured fields: theme, target amount, allowed asset classes, excluded asset classes, market, venue, sector, and concentration preference.
- V1.1.S1.T4: Reject malformed thesis requests with user-readable errors.

Acceptance:

- A thesis prompt produces structured investor intent without requiring the user
  to type tickers.
- Missing target amount, unsupported market, or unsupported asset class produces
  a clear error.

Implementation notes:

- Start with deterministic fixtures and rules, not live LLM or market data.
- Likely new file: `src/tickoni/schema/investment.zig`.
- Keep thesis parsing separate from trading policy checks.

### V1.1.S2: Investable universe and instrument catalog

Tasks:

- V1.1.S2.T1: Define an instrument catalog fixture with ticker, name, asset class, market, venue, sector, theme tags, risk tier, expense ratio where relevant, and restricted-instrument flag.
- V1.1.S2.T2: Include US-listed equity and ETF examples for AI infrastructure, semiconductors, cloud, cyber security, broad market, and cash-like ETFs.
- V1.1.S2.T3: Mark unsupported instruments such as options, futures, leveraged ETFs, inverse ETFs, non-US venues, and restricted tickers.
- V1.1.S2.T4: Add catalog lookup by theme, sector, asset class, venue, and ticker.

Acceptance:

- The AI infrastructure demo can produce at least four eligible candidate
  instruments and at least two rejected instruments with clear reasons.

Implementation notes:

- Likely new file: `src/tickoni/schema/instrument.zig`.
- Fixtures should live under a Tickoni-owned demo/test path.
- Do not add real-time market data yet.

### V1.1.S3: Basket construction

Tasks:

- V1.1.S3.T1: Define a basket schema with basket id, thesis id, account id, target notional, candidate instruments, allocation weights, allocation dollars, rationale, and rejected candidates.
- V1.1.S3.T2: Generate a deterministic basket from structured thesis intent and instrument catalog fixtures.
- V1.1.S3.T3: Enforce basic scope: US market, NYSE/NASDAQ venues, equity/ETF asset classes, allowed sector/theme tags, and restricted-instrument denylist.
- V1.1.S3.T4: Apply simple concentration rules such as max single-name allocation and ETF preference when requested.
- V1.1.S3.T5: Add explainability strings that say why each instrument was included or rejected.

Acceptance:

- The user receives a concrete basket with dollar allocations that sum to the
  target notional within rounding tolerance.
- Restricted instruments are rejected before they can appear in the basket.

Implementation notes:

- This is a recommendation, not an order.
- Capability names involved: `trading_portfolio.read`,
  `market_event.read`, `trading_order.recommend`.
- Do not create a generic portfolio optimizer yet.

### V1.1.S4: Thesis-to-basket demo

Tasks:

- V1.1.S4.T1: Add one local demo command or test fixture for the AI infrastructure thesis.
- V1.1.S4.T2: Output a polished basket summary suitable for a product demo.
- V1.1.S4.T3: Include eligible instruments, rejected instruments, allocation, and rationale.
- V1.1.S4.T4: Add tests for happy path, unsupported asset class, non-US market, restricted instrument, and concentration preference.

Acceptance:

- An exec can type or run one thesis example and see an explainable basket in
  under one demo step.

## V1.2: Buying-Power Trade Ticket

### User Story

As an investor, I can turn a basket into a trade ticket and Tickoni tells me
whether I can actually afford it.

Example request:

```text
Buy the AI infrastructure basket for USD 2,000.
```

Example answer:

```text
Allowed in paper account.
Estimated cost: USD 1,997.42
Cash available: USD 5,240.18
Remaining buying power: USD 3,242.76
Max allowed for this account today: USD 10,000
No restricted instruments found.
No same-day round-trip violation.
Portfolio technology exposure after trade: 31%.
```

### Product Outcome

The user gets:

- a trade ticket from the basket
- cash and buying-power check
- per-instrument order lines
- estimated cost
- max affordable amount when too large
- clear blocked/resized reasons
- one-click paper trade when allowed

### V1.2.S1: Demo portfolio and buying power

Tasks:

- V1.2.S1.T1: Define a demo brokerage account schema with account id, cash, buying power, currency, current holdings, open orders, day notional used, and month notional used.
- V1.2.S1.T2: Add deterministic demo portfolio fixtures for cash-rich, low-cash, technology-heavy, diversified, and restricted-account examples.
- V1.2.S1.T3: Compute available cash, estimated buying power, remaining daily notional, remaining monthly notional, and max affordable basket size.
- V1.2.S1.T4: Add tests for sufficient cash, insufficient cash, day-limit exceeded, month-limit exceeded, and open-order limit.

Acceptance:

- Given a basket and account fixture, Tickoni can say whether the account can
  afford the requested notional and what the maximum affordable notional is.

Implementation notes:

- Likely new file: `src/tickoni/schema/portfolio.zig`.
- This is not TigerBeetle. It is a deterministic brokerage demo fixture.
- Do not introduce margin or leverage.

### V1.2.S2: Trade ticket schema

Tasks:

- V1.2.S2.T1: Define a trade ticket schema with ticket id, basket id, account id, side, order type, time-in-force, target notional, estimated cost, line items, status, and blocked reasons.
- V1.2.S2.T2: Convert basket allocations into line-item orders using deterministic fixture prices.
- V1.2.S2.T3: Support buy and sell preview in paper mode.
- V1.2.S2.T4: Support order types `market` and `limit` for paper mode, with limit price required for limit orders.
- V1.2.S2.T5: Reject unsupported order types.

Acceptance:

- A basket becomes a trade ticket with concrete line items and estimated cost.
- Unsupported order types fail before ticket approval.

Implementation notes:

- Capability names involved: `trading_order.recommend`,
  `trading_order.propose`.
- Keep `trading_order.place` paper-only unless a later increment enables
  broker sandbox execution.

### V1.2.S3: Trade guardrails and affordability checks

Tasks:

- V1.2.S3.T1: Enforce account buying power and cash checks.
- V1.2.S3.T2: Enforce max notional per order, max notional per day, max notional per month, and max open orders.
- V1.2.S3.T3: Enforce asset class, market, venue, sector, side, and order type scope.
- V1.2.S3.T4: Enforce restricted-instrument denylist.
- V1.2.S3.T5: Enforce same-day round-trip and minimum holding-period checks in demo fixture state.
- V1.2.S3.T6: Return user-facing blocked reasons and resize suggestions.

Acceptance:

- A USD 2,000 eligible basket is allowed in the cash-rich paper account.
- A USD 25,000 request is blocked or resized with max affordable amount and
  exact reasons.
- Restricted instruments never reach paper execution.

Implementation notes:

- These are product guardrails, but they should map to the financial capability
  model in `capabilities.md`.
- Reasons should be written in investor language, not internal policy language.

### V1.2.S4: Paper trade execution

Tasks:

- V1.2.S4.T1: Define a paper execution result schema with paper order id, ticket id, account id, submitted line items, filled line items, simulated fill prices, timestamp, and resulting cash/holdings snapshot.
- V1.2.S4.T2: Allow paper execution only for tickets whose guardrail status is allowed.
- V1.2.S4.T3: Update the demo portfolio fixture state after paper execution.
- V1.2.S4.T4: Reject direct paper execution attempts that bypass ticket validation.
- V1.2.S4.T5: Add tests for allowed paper buy, insufficient cash rejection, restricted instrument rejection, and direct bypass rejection.

Acceptance:

- The user can place an allowed paper trade and immediately see cash and
  holdings update.
- The user cannot paper-place a blocked ticket.

Implementation notes:

- This is user-initiated paper execution, not autonomous agent execution.
- Keep production broker integration out of V1.2.

### V1.2.S5: Buying-power demo

Tasks:

- V1.2.S5.T1: Add a demo flow from V1.1 basket to V1.2 trade ticket.
- V1.2.S5.T2: Show allowed USD 2,000 paper trade.
- V1.2.S5.T3: Show blocked USD 25,000 trade with max affordable amount.
- V1.2.S5.T4: Show rejected restricted instrument.
- V1.2.S5.T5: Output a product-friendly ticket summary.

Acceptance:

- An exec can watch one basket become a trade ticket, see buying power checks,
  place a paper trade, and see an oversized trade blocked with a helpful reason.

## V1.3: Portfolio Impact Loop

### User Story

As an investor, I can see how a trade changes my portfolio before and after I
place it, and Tickoni keeps tracking whether the original thesis still holds.

### Product Outcome

The user gets:

- before/after portfolio view
- exposure changes
- concentration checks
- thesis card
- thesis drift alerts
- rebalance suggestion in proposal/paper mode

### V1.3.S1: Portfolio impact model

Tasks:

- V1.3.S1.T1: Define portfolio impact fields: cash before/after, buying power before/after, asset class exposure, sector exposure, ticker concentration, thesis exposure, and estimated order cost.
- V1.3.S1.T2: Compute impact before paper execution.
- V1.3.S1.T3: Compute realized impact after paper execution.
- V1.3.S1.T4: Add display-ready explanations for material changes.
- V1.3.S1.T5: Add tests for increased technology exposure, cash decrease, ETF exposure change, and single-name concentration threshold.

Acceptance:

- Before placing a paper trade, the user can see what will change.
- After placing a paper trade, the portfolio snapshot reflects the trade.

### V1.3.S2: Thesis card

Tasks:

- V1.3.S2.T1: Define thesis card schema with thesis id, user text, basket id, linked positions, target exposure, current exposure, status, created timestamp, and last checked timestamp.
- V1.3.S2.T2: Save a thesis card after a paper trade.
- V1.3.S2.T3: Link positions back to thesis rationale.
- V1.3.S2.T4: Show thesis status: active, under-allocated, over-concentrated, drifted, or closed.

Acceptance:

- After buying the AI infrastructure basket in paper mode, the user sees a
  thesis card tracking the positions tied to that thesis.

Implementation notes:

- This is product memory, not generic agent memory.
- Keep the thesis tied to deterministic portfolio state.

### V1.3.S3: Thesis drift and rebalance suggestion

Tasks:

- V1.3.S3.T1: Define drift conditions: target allocation breach, sector exposure breach, concentration breach, instrument no longer eligible, and buying-power change.
- V1.3.S3.T2: Add deterministic market movement fixtures that trigger drift.
- V1.3.S3.T3: Generate a rebalance suggestion without autonomous execution.
- V1.3.S3.T4: Convert a rebalance suggestion into a trade ticket preview.
- V1.3.S3.T5: Add tests for each drift condition.

Acceptance:

- The user can see when the thesis drifted and preview a paper rebalance ticket.
- No rebalance executes without explicit user action.

### V1.3.S4: Portfolio impact demo

Tasks:

- V1.3.S4.T1: Extend the V1.2 demo to show before/after portfolio state.
- V1.3.S4.T2: Save the AI infrastructure thesis card.
- V1.3.S4.T3: Apply a deterministic market movement fixture.
- V1.3.S4.T4: Show a thesis drift alert and rebalance suggestion.

Acceptance:

- An exec can see the paper trade change the portfolio, then see Tickoni keep
  monitoring the investment thesis.

## V1.4: Guarded Live-Trading Sandbox

### User Story

As a product evaluator, I can connect a broker sandbox account and place
approved small trades through the same thesis-to-ticket flow.

### Scope

This is later hardening. It should not block V1.1-V1.3.

Tasks:

- V1.4.T1: Define broker sandbox adapter manifest.
- V1.4.T2: Add paper/live mode switch with safe default to paper.
- V1.4.T3: Add signed action envelope for broker sandbox orders.
- V1.4.T4: Add deterministic action id and idempotency key.
- V1.4.T5: Submit sandbox orders only after ticket guardrails pass.
- V1.4.T6: Read back order status and reconcile it with the local ticket.
- V1.4.T7: Add kill switch that blocks all sensitive execution.

Acceptance:

- A small eligible order can be submitted to a broker sandbox.
- The same blocked tickets from V1.2 remain blocked.
- Read-back confirms submitted status or opens an order-status mismatch note.

Non-goals:

- no production live trading by default
- no margin
- no derivatives
- no autonomous execution

## V1.5: Social Thesis Feed

### User Story

As an investor, I can browse other thesis cards, inspect their basket and risk
checks, and copy a thesis into my own account with my own buying-power and
portfolio-fit checks.

Tasks:

- V1.5.T1: Define public thesis card schema.
- V1.5.T2: Add shareable thesis snapshot with basket, rationale, historical paper performance, and risk notes.
- V1.5.T3: Add copy-to-my-portfolio action.
- V1.5.T4: Resize copied thesis based on the user's buying power.
- V1.5.T5: Explain why the copied version differs from the original.
- V1.5.T6: Prevent copy-trade bypass of account-specific limits.

Acceptance:

- A user can copy a thesis but cannot bypass their own cash, instrument, venue,
  sector, notional, or concentration limits.

Non-goals:

- no unbounded copy trading
- no creator-driven auto-execution
- no influencer marketplace mechanics

## V1.6: Trust Layer

### User Story

As a regulated fintech or brokerage partner, I can inspect the proof behind
each recommendation and trade ticket.

Tasks:

- V1.6.T1: Add trade-decision audit timeline for thesis, basket, ticket, guardrail checks, paper/live execution, and portfolio impact.
- V1.6.T2: Add replay capsule for a thesis-to-trade flow.
- V1.6.T3: Include policy version, model/tool/adapter attribution, and capability envelope id.
- V1.6.T4: Export a trade-decision record for partner review.
- V1.6.T5: Show blocked trade reasons and policy scope in partner-facing language.

Acceptance:

- A partner can inspect how a recommendation became a ticket, why it was
  allowed or blocked, and how replay reproduces the decision.

Product framing:

This is the trust layer. It should support the investing experience, not become
the primary V1 user experience.

## Cross-Increment Engineering Notes

### Likely New Modules

- `src/tickoni/schema/investment.zig`
- `src/tickoni/schema/instrument.zig`
- `src/tickoni/schema/portfolio.zig`
- `src/tickoni/schema/trade_ticket.zig`
- `src/tickoni/schema/thesis.zig`
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

V1 investing features should map to these finance-native capabilities:

```text
trading_portfolio.read
market_event.read
trading_order.recommend
trading_order.propose
trading_order.place        paper/sandbox only until later approval
```

Explicitly deny in V1:

```text
option_order.place
future_order.place
leveraged_etf_order.place
inverse_etf_order.place
margin_order.place
crypto_transfer.initiate
bank_transfer.initiate
ledger_adjustment.post
policy.modify
```

### Increment Gate Checklist

Every increment must answer:

- What can the investor do now?
- What changed from the previous increment?
- What is the demo moment?
- Which account, market, venue, asset class, instrument, notional, exposure, and
  frequency checks are enforced?
- What happens when the user asks for too much money?
- What happens when an instrument is restricted?
- Is execution paper-only, broker-sandbox, or disabled?
- Which artifacts are needed for later partner trust?

## Backlog: Carried-Forward Features From The Original Roadmap

The investment roadmap intentionally pushes audit, replay, CaseOps, payment,
reconciliation, and fraud/risk work behind the first wow features. The features
below came from the original `roadmap.md` and `wbs.md` and should remain
visible. Pull them forward only when they strengthen the investing product.

## B1: Durable Runtime Proof

Product use:

Partner asks why a trade ticket was allowed, blocked, or resized.

Tasks:

- B1.T1: Export trade-decision audit records as JSONL in append order.
- B1.T2: Verify the audit hash chain for a thesis-to-ticket run.
- B1.T3: Mark audit output incomplete on crash shutdown.
- B1.T4: Export runtime metrics for events, model calls, tool calls, guardrail checks, ticket decisions, paper orders, replay status, and crash state.
- B1.T5: Export diagnostics for crashed tile id, last processed source offset, audit record count, last audit hash, replay checked, replay matched, and divergence count.
- B1.T6: Add one local command that runs an investing demo and emits audit, metrics, diagnostics, and replay artifacts.

Acceptance:

- A partner can receive a durable proof bundle for one thesis-to-ticket flow.

## B2: Model Gateway And Inference Governance

Product use:

Thesis generation and basket explanation use AI, but the investing product must
have bounded cost and no direct provider access from agents.

Tasks:

- B2.T1: Define model request and response envelopes for thesis, basket, ticket explanation, and thesis health outputs.
- B2.T2: Route all model requests through `tkmodl`.
- B2.T3: Add deterministic model stubs for V1 demos.
- B2.T4: Add optional local/dev LLM endpoint configuration.
- B2.T5: Add provider enum scaffolding for OpenAI, Anthropic, Qwen, DeepSeek, local LLM server, and future local GPU.
- B2.T6: Enforce context length, request size, retry limit, and per-run token budget.
- B2.T7: Attribute model usage by thesis id, basket id, ticket id, account id, workflow, and policy version.
- B2.T8: Carry explicit agent identity, role, workflow, account, and policy version on every thesis, basket, ticket, and thesis-health model request.
- B2.T9: Bound agent runs with step limits, retry limits, cancellation, and budget-exhaustion stop states.

Acceptance:

- No thesis, basket, ticket, or thesis-health model call can bypass `tkmodl`.

## B3: Financial Tool Broker And Adapter Boundary

Product use:

The AI can ask for portfolio, market, instrument, and paper-trade actions, but
all such requests become finance-native tool/adapter requests.

Tasks:

- B3.T1: Normalize model-native function calls and MCP-compatible tool calls into typed investment requests.
- B3.T2: Define adapter requests for portfolio read, market event read, instrument catalog read, ticket preview, paper order submit, and order-status read-back.
- B3.T3: Validate the finance-native capability envelope before adapter routing.
- B3.T4: Deny malformed, unsupported, out-of-scope, or over-limit tool requests before adapter execution.
- B3.T5: Keep adapter credentials and broker sandbox credentials out of agent state.
- B3.T6: Add tests proving direct adapter access fails closed.

Acceptance:

- The investing agent cannot read portfolio state, market fixtures, instrument data, or paper execution state except through `tktool` and `tkadpt`.

## B4: Runtime Hooks For Investment Actions

Product use:

The app needs to explain why a basket, ticket, paper order, portfolio update, or
thesis drift event happened.

Tasks:

- B4.T1: Define a canonical hook envelope for investment actions.
- B4.T2: Add hook types for thesis created, basket generated, ticket previewed, ticket blocked, ticket resized, paper order submitted, portfolio impact computed, thesis card created, drift detected, and rebalance suggested.
- B4.T3: Add `PreModelCall` and `PostModelCall` hooks.
- B4.T4: Add `PreToolUse` and `PostToolUse` hooks.
- B4.T5: Add `PreActionProposal` for trade tickets and rebalance suggestions.
- B4.T6: Add bounded hook links and route hooks to policy, audit, metrics, diagnostics, and replay.
- B4.T7: Add hook telemetry for counts, latency, denials, resize decisions, budget denials, and replay divergence.

Acceptance:

- Every material investment action can be explained through hook-derived records without showing hook mechanics to the user.

## B5: Case, Evidence, And Replay Capsule As Thesis History

Product use:

The user and partner can reconstruct how a thesis became a basket, ticket,
paper order, and portfolio state.

Tasks:

- B5.T1: Define deterministic thesis id or case id derivation from account, user, thesis text hash, and created sequence.
- B5.T2: Define content-addressed evidence records for model outputs, instrument facts, market-event fixtures, portfolio snapshots, ticket previews, paper order results, and thesis drift events.
- B5.T3: Store evidence hashes on thesis cards and trade tickets.
- B5.T4: Define replay capsule schema for source thesis, normalized intent, basket, ticket, guardrail decisions, model outputs, tool outputs, adapter fixtures, paper execution result, portfolio impact, and thesis state.
- B5.T5: Replay the thesis-to-trade flow without live model, market, broker, or adapter effects.
- B5.T6: Report first divergence by thesis hash, basket hash, ticket hash, policy version, evidence hash, model output hash, adapter output hash, or portfolio state hash.

Acceptance:

- A thesis-to-trade flow can be replayed from captured inputs and reports the first divergence.

## B6: Partner API And Review Surface

Product use:

Brokerage or fintech partners need APIs to inspect accounts, thesis cards,
trade decisions, proof artifacts, and replay status.

Tasks:

- B6.T1: Add authenticated API for thesis creation, basket read, ticket preview, paper order submit, portfolio read, thesis status read, and trade-decision export.
- B6.T2: Validate source identity, idempotency key, account id, event timestamp, payload size, and required financial fields.
- B6.T3: Return accepted, duplicate, malformed, or rejected responses.
- B6.T4: Add partner-facing timeline read endpoint for thesis, basket, ticket, guardrails, paper order, portfolio impact, and thesis drift.
- B6.T5: Add replay status endpoint.
- B6.T6: Add integration tests for valid, duplicate, malformed, oversized, unauthorized, and environment-mismatch requests.

Acceptance:

- A partner can integrate the thesis-to-trade flow without receiving direct access to model, tool, adapter, or executor internals.

## B7: Approval And Execution Trust

Product use:

Paper execution is allowed early. Broker sandbox and live execution need
approval and signed execution controls.

Tasks:

- B7.T1: Hash-bind trade tickets and rebalance suggestions.
- B7.T2: Add approval state for broker sandbox or live execution modes when configured.
- B7.T3: Add approval granted, rejected, expired, and revoked records.
- B7.T4: Add signed action envelope for approved broker sandbox orders.
- B7.T5: Add deterministic action id and idempotency key.
- B7.T6: Add privileged executor boundary for broker sandbox orders.
- B7.T7: Add order read-back and order-status mismatch handling.
- B7.T8: Add kill switch that blocks all sensitive execution capabilities immediately.

Acceptance:

- No broker sandbox or live order can execute outside its account, instrument, amount, frequency, approval, and action-id scope.

## B8: Non-Investment Workflow Shelf

Product use:

These were part of the original fintech-operations roadmap. Keep them visible
as later product lines, not part of investment V1.

Backlog items:

- B8.T1: Payment exception workflow: failed payment evidence, retry recommendation, retry proposal, customer/merchant draft.
- B8.T2: Reconciliation break workflow: ledger mismatch evidence, discrepancy explanation, correction proposal.
- B8.T3: Fraud/risk triage workflow: suspicious activity evidence, severity classification, review queue recommendation.
- B8.T4: CaseOps operations board for non-investing workflows.
- B8.T5: TigerBeetle accounting ledger connector behind `tkexec`.
- B8.T6: Banking, crypto, payment, risk, and compliance adapters.
- B8.T7: Maker-checker approval workflows for money movement and ledger posting.

Acceptance:

- These remain documented as later work and do not dilute the V1 thesis-to-trade product.

## B9: Build, Quality, Security, And Release Hygiene

Product use:

Investment demos must be impressive without weakening Tickoni's safety claim.

Tasks:

- B9.T1: Add one local verification command per investment increment.
- B9.T2: Keep Zig harness tests wired through `zig build test`.
- B9.T3: Add focused tests for thesis schema, instrument catalog, basket generation, portfolio fixtures, trade tickets, guardrails, paper execution, thesis cards, and drift rules.
- B9.T4: Add security tests for forbidden shell access, forbidden direct network access, forbidden direct adapter access, and forbidden direct execution paths as soon as each path exists.
- B9.T5: Add fail-closed tests for malformed capability envelopes, malformed hooks, unknown providers, missing allowlists, invalid limits, environment mismatch, and unsupported instruments.
- B9.T6: Add adapter manifest validation before broker sandbox integration.
- B9.T7: Add sample configs and sample outputs for thesis-to-basket, buying-power ticket, portfolio impact, and later partner trust flows.
- B9.T8: Keep investment V1 non-goals visible in demo docs.

Acceptance:

- Each increment has a local command and focused tests proving the investor flow,
  blocked paths, and no-bypass safety conditions.
