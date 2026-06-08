# Tickoni Consumer Finance Roadmap

## Product Bet

Tickoni should lead as a consumer-money control product, not as an operations
or governance console.

The product should feel closer to Robinhood, eToro, PayPal, Payoneer, Binance,
Coinbase, or IBKR with a finance-native AI control layer underneath:

```text
I want to invest, send, hold, or move money.
Tickoni turns intent into a safe financial action.
Tickoni checks buying power, destination, exposure, and limits.
Tickoni explains why the action is allowed, resized, blocked, or needs review.
Tickoni keeps proof for every money-impacting recommendation.
```

The control model still matters, but the user should feel it as product magic:

- "You can afford this trade."
- "This exceeds your buying power."
- "This recipient is not on your trusted beneficiary list."
- "This stablecoin withdrawal exceeds your wallet limit."
- "This would make your portfolio too concentrated in semiconductors."
- "This instrument is outside your mandate."
- "This is a same-day round trip; wait until tomorrow or reduce scope."
- "This payment retry is safe to propose, but execution needs approval."
- "Your USD 2,000 thesis fits as a 4-position AI infrastructure basket."

Audit, replay, approval, and policy are the engine room. They should not be the
headline for the first product story.

## Target User

V1 is for a retail or prosumer money user who wants AI help making disciplined
financial decisions without losing control:

- self-directed investor
- social/copy-trading user
- cross-border freelancer or small merchant managing cash, payouts, and
  investments
- crypto or stablecoin user who needs destination and network safety checks
- brokerage or fintech power user managing multiple accounts
- fintech demo user
- trading operations reviewer in a sandbox account
- founder/investor evaluating Tickoni as an agentic investing runtime
- engineering operator validating queue, crash, budget, adapter, and replay
  behavior
- risk, compliance, or partner reviewer inspecting why a recommendation, trade
  ticket, payment proposal, transfer proposal, or withdrawal proposal was
  allowed, blocked, or approval-gated

The user is not trying to audit an agent. The user is trying to make a better
money decision quickly, with confidence that the system will not let them
overspend, send to the wrong destination, over-concentrate, or violate their
mandate.

## Product Principles

1. Lead with consumer money intent.
   The user starts with "buy this basket", "can I afford this?", "send this
   payout", or "move to this wallet", not a policy form.

2. Make constraints feel like intelligence.
   Buying power, recipient trust, wallet allowlists, rail/currency limits,
   notional limits, venue scope, restricted instruments, sector concentration,
   and holding-period rules should appear as helpful guidance.

3. The first wow is intent-to-safe-action.
   The user should see a vague investing or money-movement intent become a
   concrete basket, ticket, transfer proposal, payment retry proposal, or
   blocked reason.

4. Execution starts in sandbox or paper mode.
   Live brokerage, payment, banking, or crypto execution can come later behind
   signed adapters, approval, and privileged executor paths. V1 should still
   make the money flow feel real.

5. Keep the safety model finance-native.
   Use accounts, beneficiaries, IBANs, wallets, rails, currencies, custody
   accounts, buying power, markets, venues, sectors, instruments, order types,
   notional, exposure, frequency, and holding period. Do not expose OS-style
   permissions as product language.

6. Proposals beat autonomy.
   Agents may recommend, draft, route, prepare, and propose. Money movement,
   ledger posting, trading execution, crypto withdrawal, payout approval, and
   risk overrides stay approval-gated and executor-bound.

## Baseline: V1.0 Runtime Proof

Status: done.

What exists today is a technical proof: Tickoni can process deterministic
financial events, reject bad input, dedupe duplicates, make basic policy
decisions, write hash-chained audit records, replay a run, and report health.

That work is valuable infrastructure, but it is not yet the product story.

The remaining roadmap should turn the runtime into a consumer-finance product:
investment first, payments and cash movement second, crypto/stablecoin and
partner trust next.

## Priority Stack

The roadmap should be prioritized like a senior consumer-finance PM would
prioritize it:

1. **Invest And Trade Safely**
   The Robinhood/eToro/IBKR lane. Turn an investment thesis into a basket,
   ticket, affordability check, paper trade, portfolio impact, and later broker
   sandbox execution.

2. **Pay And Move Money Safely**
   The PayPal/Payoneer lane. Check recipient, rail, currency, amount, retry
   count, payout state, and approval requirement before proposing a payment,
   payout, or transfer action.

3. **Crypto And Stablecoin Safety**
   The Binance/Coinbase lane. Check wallet, network, custody account, asset,
   chain-risk tier, and travel-rule state before any withdrawal or transfer
   proposal.

4. **Trust And Replay**
   The enterprise fintech lane. Every consequential recommendation, proposal,
   approval, denial, and downstream result is attributable, policy-checked, and
   replayable.

Everything else supports one of these money loops.

## Increment Roadmap

### V1.1: Investment Intent To Paper Trade

User story:

As an investor, I can type a plain-English market thesis and Tickoni turns it
into a concrete basket, checks whether I can afford it, and lets me place or
save a paper trade inside hard limits.

Example:

```text
"I want to invest USD 2,000 in AI infrastructure, but avoid single-name
concentration and keep it to US-listed ETFs or large-cap equities."
```

What the user can do:

- enter an investment thesis in natural language
- choose an account or demo portfolio
- receive a basket of candidate instruments
- see why each instrument belongs in the thesis
- see a proposed allocation by dollars and percentages
- see which instruments were rejected because they are outside scope
- preview a trade ticket from the basket
- see estimated cost, cash available, buying power, remaining cash, and max
  affordable amount
- place the trade in paper mode or save it as a proposal

What the user sees:

- thesis summary
- investable universe: US equities and ETFs
- suggested basket, for example:
  - semiconductor ETF
  - cloud infrastructure ETF
  - large-cap AI platform equity
  - data-center or networking exposure
- proposed USD allocation
- confidence and evidence notes
- rejected ideas with reasons, such as options, leveraged ETFs, non-US venues,
  restricted instruments, or out-of-sector names
- trade ticket with per-instrument order lines
- affordability result: allowed, resized, blocked, or approval-required
- direct paper action when the ticket fits

Why this is cool:

The product turns a fuzzy market view into a disciplined, affordable trade in
seconds. The user does not need to start with ticker symbols or guess whether
the account can support the order.

What is better than V1.0:

- V1.0 proved Tickoni can process financial events.
- V1.1 gives the user a working investing copilot that turns intent into an
  explainable paper trade.

Capability depth:

- `trading_portfolio.read`
- `market_event.read`
- `trading_order.recommend`
- `trading_order.propose`
- paper `trading_order.place` if paper execution is enabled
- account scope
- buying-power and cash scope
- asset class scope: equity and ETF
- market and venue scope: US, NYSE, NASDAQ
- instrument denylist: options, futures, leveraged ETFs, inverse ETFs
- per-order and per-day notional limits
- same-day round-trip and minimum holding-period checks
- sector and theme tagging

Success demo:

An exec types one investment thesis and gets a polished basket, a ticket, an
affordability check, a USD 2,000 paper trade, and a blocked USD 25,000 variant
with max affordable amount and exact reasons.

Non-goals:

- no live order placement
- no margin trading
- no options, futures, leveraged ETFs, inverse ETFs, or crypto
- no autonomous rebalancing

### V1.2: Pay And Move Money Guard

User story:

As a consumer, freelancer, or small merchant, I can ask Tickoni whether a
payment, payout, retry, or transfer is safe to propose before money moves.

Example:

```text
"Retry this USD 1,240 supplier payout over ACH, but only if the recipient,
rail, currency, and retry count are still within policy."
```

Tickoni answers:

```text
Safe to propose.
Known beneficiary: supplier_acme_us
Rail: ACH
Currency: USD
Retry count after this attempt: 1 of 2
Daily beneficiary limit remaining: USD 8,760
Execution requires approval.
```

What the user can do:

- inspect a failed payment, delayed settlement, blocked payout, declined
  authorization, failed refund, or failed capture
- see why a payment or payout failed
- check beneficiary, IBAN, rail, currency, country, amount, retry count, and
  sanctions/KYC/risk flags
- draft a merchant, supplier, or customer response
- propose a retry, reroute, hold, or escalation
- see whether the action is allowed, denied, or approval-required

What the user sees:

- failed-money event summary
- trusted beneficiary or blocked destination status
- rail, currency, country, and amount checks
- retry timing and retry-count checks
- proposed next action
- approval requirement and expiry where applicable
- draft message and evidence packet

Why this is cool:

The product applies the same "safe action" magic to money movement that V1.1
applies to investing. The user gets a clear answer before a retry, payout, or
transfer creates financial consequence.

What is better than V1.1:

- V1.1 proved investment intent-to-ticket.
- V1.2 proves Tickoni is not only an investing feature. It is a consumer-finance
  harness that can govern payment and transfer proposals with the same
  finance-native capability model.

Capability depth:

- `payment_attempt.read`
- `processor_record.read`
- `payment_failure.classify`
- `payment_retry.recommend`
- `payment_retry.propose`
- `customer_contact.draft`
- `bank_transfer.propose`
- beneficiary, IBAN, rail, currency, country, amount, retry, and timing scope
- approval-required for money-impacting execution

Success demo:

An exec reviews a failed supplier payout. Tickoni classifies the failure,
checks the beneficiary and rail, proposes a safe retry with evidence and a
draft response, then blocks the same retry when the beneficiary or amount is
outside policy.

Non-goals:

- no autonomous money movement
- no direct payout approval
- no ledger posting
- no compliance final decision
- no generic CaseOps-first UI

### V1.3: Portfolio And Cash Impact Loop

User story:

As a money user, I can see how an investment or payment proposal changes my
portfolio, cash, exposure, and obligations before and after I act.

Example:

```text
"If I buy this AI infrastructure basket and retry the supplier payout, what
changes in my cash and portfolio?"
```

Tickoni answers:

```text
Technology exposure increases from 22% to 31%.
Single-name concentration remains below 8%.
ETF exposure increases from 36% to 43%.
Cash drops from USD 5,240.18 to USD 2,002.76 after trade and payout proposal.
Your AI infrastructure thesis is now represented by four positions.
The supplier payout remains approval-required and unexecuted.
```

What the user can do:

- compare portfolio before and after a proposed trade
- compare cash before and after a proposed payment, payout, or transfer
- see sector, asset class, ticker, cash, rail, and destination impact
- save the thesis as a monitored investment idea
- save a money-movement proposal as a pending obligation
- receive thesis drift alerts, such as:
  - position moved outside target allocation
  - sector exposure exceeded threshold
  - market event affects one instrument in the thesis
  - buying power changed enough to resize the trade
- receive cash or payment alerts, such as:
  - payout would reduce investable cash below target buffer
  - retry window expired
  - beneficiary limit changed
  - approval expired or was revoked
- generate a rebalance suggestion in paper/proposal mode

What the user sees:

- before/after portfolio view
- before/after cash and pending-obligation view
- thesis card
- payment or transfer proposal card
- position weights
- exposure heatmap
- cash and buying power
- thesis health status
- approval state
- rebalance suggestion

Why this is cool:

Money decisions are not isolated clicks. Tickoni connects investing, cash, and
pending payment obligations so the user sees the consequence before the action.

What is better than V1.2:

- V1.2 checked whether a payment or transfer proposal is safe.
- V1.3 shows how investment and payment proposals interact with cash,
  portfolio exposure, buying power, and approval state.

Capability depth:

- `trading_portfolio.read`
- `market_event.read`
- `trading_order.recommend`
- `trading_order.propose`
- `payment_attempt.read`
- `payment_retry.propose`
- `bank_transfer.propose`
- thesis state tied to positions
- pending payment or transfer proposal state tied to cash
- exposure and concentration limits
- cash-buffer and beneficiary/day/month limit checks
- rebalance recommendation only; no autonomous rebalance execution

Success demo:

An exec buys the AI basket in paper mode, reviews a supplier payout proposal,
sees cash and exposure impact together, then sees Tickoni keep thesis and
payment proposal cards alive with drift, cash, approval, and expiry signals.

Non-goals:

- no tax optimization
- no portfolio margin
- no autonomous trade placement
- no autonomous payment execution
- no social copy trading yet

## Later Hardening And Expansion

The first three increments should create the consumer-money wow. Later
increments deepen distribution, asset coverage, execution, and partner trust.

### V1.4: Social Thesis And Money Feed

User story:

As a user, I can browse thesis cards and money-decision cards, inspect their
risk checks, and copy an investing thesis or payment template into my own
account with my own limits.

Adds:

- shareable thesis cards
- shareable payment or transfer templates
- copy-to-my-portfolio flow
- copy-to-my-recipient flow for approved beneficiaries only
- account-specific resizing
- "why my version differs" explanation
- creator performance or reliability snapshot

Still excludes:

- unbounded copy trading
- bypassing account-specific limits
- influencer-driven auto-execution
- copying untrusted recipients or wallets

### V1.5: Crypto And Stablecoin Guard

User story:

As a crypto or stablecoin user, I can ask whether a withdrawal, transfer, or
portfolio move is safe before it touches a wallet, network, or custody account.

Adds:

- custody account read
- wallet address allowlist
- asset and network allowlist
- amount per transaction, day, month, wallet, and asset
- chain analytics risk tier
- travel-rule status where applicable
- internal transfer, withdrawal, and deposit-reconciliation proposal modes
- stablecoin cash-impact view alongside brokerage cash

Still excludes:

- direct autonomous crypto withdrawal
- unsupported tokens and networks
- bypassing wallet allowlists
- travel-rule bypass
- DeFi strategy execution

### V1.6: Guarded Broker, Payment, And Crypto Sandbox

User story:

As a product evaluator, I can connect sandbox broker, payment, bank, or crypto
accounts and submit approved small actions through the same safe-action flow.

Adds:

- broker sandbox connector
- payment processor sandbox connector
- bank-transfer sandbox connector
- crypto custody or wallet sandbox connector
- signed adapter manifest
- signed action envelope
- deterministic action id
- paper/sandbox/live mode switch
- read-back of submitted orders, payment retries, transfers, or withdrawals
- mismatch handling and reconciliation case creation
- kill switch

Still excludes:

- production live execution by default
- margin
- derivatives
- autonomous execution

### V1.7: Trust Layer

User story:

As a regulated fintech, brokerage, payments, or crypto partner, I can inspect
the proof behind each recommendation, payment proposal, transfer proposal,
trade ticket, approval, denial, and downstream result.

Adds:

- audit timeline
- replay capsule
- policy version and policy hash
- model/tool/adapter attribution
- actor, agent, tool, and invocation-protocol attribution
- approval state where required
- signed audit records
- exportable money-decision record for investing, payment, bank-transfer, and
  crypto flows

Product framing:

This is not the headline user experience. It is the enterprise trust layer that
makes the consumer-finance product credible for partners.

### V1.8: Capability Control Surface

User story:

As a fintech, brokerage, payments, crypto, treasury, risk, or compliance
partner, I can see and manage the financial action classes and policy outcomes
that govern every agent recommendation, proposal, approval, denial, escalation,
and execution path.

Adds:

- capability catalog surfaced in finance-native language
- action-class view: observe, analyze, draft, recommend, propose, prepare,
  execute, override, and administer
- policy outcome view: `allow`, `deny`, `require_approval`,
  `require_more_evidence`, and `escalate`
- scope viewer for account, customer, merchant, legal entity, beneficiary,
  IBAN, wallet, custody account, rail, currency, country, market, venue,
  sector, instrument, order type, amount, exposure, frequency, holding period,
  risk tier, jurisdiction, and environment
- later-lane capability templates for ledger corrections, accounting
  adjustments, reconciliation breaks, fraud/risk triage, compliance case
  preparation, treasury alerts, chargebacks, merchant risk review, bank
  transfers, crypto transfers, and trading execution
- evidence prerequisite display for proposal capabilities
- aggregate limit display by case, customer, account, beneficiary, wallet,
  instrument, and time window
- approval-path display with approver roles, expiry, revocation, and
  maker-checker requirements
- explicit denied-by-default execution and override list for money movement,
  ledger posting, payout approval, account freezing, risk-rule override,
  policy modification, and unsupported trading or crypto actions

Still excludes:

- agent-editable policy
- production policy administration without separate governance controls
- direct execution outside signed adapters, approvals, and privileged executor
  paths
- self-modifying agents or dynamic capability expansion

Product framing:

This is where the full `capabilities.md` model becomes inspectable product
surface. It is not a consumer hero screen; it is the partner control plane that
explains and governs what financial consequences agents may participate in.

## Carried-Forward Platform Backlog

The original roadmap and WBS contained important platform capabilities that are
not part of the first consumer-money wow. They should remain in the backlog so
the product does not lose its Tickoni advantage.

### P1: Durable Runtime Proof

Why it still matters:

The consumer-finance app needs durable proof when a partner asks, "why did this
trade, payment, transfer, or withdrawal pass, resize, block, or require
approval?"

Carry forward:

- durable audit JSONL export
- hash-chain verification
- signed audit records
- stable audit event id and nanosecond timestamp
- previous-hash linkage per audit event
- incomplete-run marker
- runtime metrics export
- diagnostics export
- backpressure, queue-depth, and crash diagnostics
- replay verification from exported records
- audit records for source events, policy decisions, destination checks, limit
  checks, model calls, tool calls, adapter calls, proposals, denials,
  approval-required decisions, operator approvals, and adapter results
- audit fields for case or thesis id, actor type, actor id, agent identity,
  model id, action, tool name, invocation protocol, input hash, output hash,
  policy version, policy decision, capability, result, and signature

Product framing:

This supports trade-ticket proof and partner review. It should not be the main
consumer experience.

### P2: Model And Tool Governance

Why it still matters:

The intent-to-safe-action experience depends on models and tools, but the agent
must not gain direct model-provider, broker, payment, bank, crypto, adapter,
shell, or unrestricted network access.

Carry forward:

- `tkmodl` model gateway
- deterministic model stubs for demos
- optional local/dev LLM backend
- provider scaffolding for OpenAI, Anthropic, Qwen, DeepSeek, local LLM server,
  and future local GPU
- model identifier format that selects a configured backend, such as
  `openai:*`, `anthropic:*`, `qwen:*`, `deepseek:*`, `llm-server:*`, or
  `stub:*`
- fail-closed handling for unknown, disabled, or unconfigured model identifiers
- provider configuration for base URL, API key or optional local key, endpoint
  URL, timeout, model allowlist, GGUF weight path, context size, and CUDA
  setting where applicable
- local GPU inference isolated behind `tkmodl`; agents never own GPU, weight,
  or local inference access directly
- context-size limits
- retry-loop limits
- per-run and per-agent token budgets
- per-run, per-role, and per-case or synthetic-run model-call limits
- max-output-token limits
- loop step limits
- budget-exhaustion stop state
- budget exhaustion audited as a policy-relevant event
- model usage attribution by role, workflow, thesis, basket, trade ticket,
  payment proposal, transfer proposal, crypto proposal, case or synthetic run,
  account, budget, and policy version
- model request fields for actor id, role, workflow, case or synthetic run id,
  policy version, model identifier, budget id, max output tokens, retry limit,
  and context limit
- model audit fields for request id, backend category, prompt or prompt
  reference, response or response reference, token usage, retry count, latency,
  policy decision id, budget id, and replay substitution id
- replay substitution from captured model output or deterministic fixture
  without cloud API, local LLM server, or GPU calls
- explicit agent identity and role context
- bounded agent runs with step, retry, and budget limits
- `tktool` broker for model-native function calls and MCP-compatible tools

Product framing:

The user sees fast, bounded AI recommendations. Partners can inspect model and
tool provenance later.

### P3: Runtime Hooks

Why it still matters:

Consumer-money actions need a consistent checkpoint model: thesis generated,
basket created, ticket checked, paper order placed, payment proposed, transfer
proposed, wallet checked, portfolio updated, cash impact computed, thesis drift
detected.

Carry forward:

- canonical hook envelope
- hook type registry
- bounded hook links
- `PreModelCall` and `PostModelCall`
- `PreToolUse` and `PostToolUse`
- `PreActionProposal` for trade tickets, payment retries, bank transfers, and
  crypto transfer proposals
- approval hooks for later broker/live modes
- replay hooks and first-divergence reporting
- hook telemetry and diagnostics

Product framing:

Hooks are not visible as hooks in the app. They power "show me why this trade,
payment, transfer, or withdrawal was allowed, blocked, resized, or changed."

### P4: Case, Evidence, And Replay Capsule

Why it still matters:

The consumer-finance product needs durable money-decision history: what the
user intended, why the basket or proposal was built, which evidence was used,
how the ticket, payment, transfer, or withdrawal was sized, and what cash,
portfolio, or destination impact was expected.

Carry forward:

- deterministic case or thesis id
- content-addressed evidence store
- replay capsule id
- ordered event-hash references
- policy version and policy hash references
- agent role, transcript hash, and tool-call hash references
- model output references
- adapter result references
- evidence references for processor logs, accounting entries, case history, or
  their investment equivalents such as market fixtures, portfolio snapshots,
  ticket previews, and paper-order results
- proposal/trade-ticket hashes
- replay capsule per material money-decision flow
- expected replay outcome, including final state, proposed action when present,
  and expected policy result
- divergence report for changed policy, evidence, market fixture, model output,
  or adapter output

Product framing:

This is "money memory" and "decision history", not a CaseOps-first board.

### P5: External Ingestion And Partner API

Why it still matters:

The consumer-finance product eventually needs APIs for account snapshots,
portfolio events, market events, payment events, payout events, crypto custody
events, thesis creation, basket reads, ticket preview, transfer proposal, and
partner review.

Carry forward:

- authenticated financial event ingestion API
- source identity and idempotency keys
- accepted, duplicate, malformed, and rejected responses
- case/thesis list and detail endpoints
- evidence reads
- audit/trust timeline reads
- replay status endpoint
- money-decision export endpoint
- operator review surface that shows recommendation evidence, policy decision,
  model usage, adapter behavior, approval state, and replay status without
  reading raw logs

Product framing:

This should serve the consumer-money UI and partners, not become a generic
operations board first.

### P6: Approval And Execution Trust

Why it still matters:

Paper trading and draft payment proposals can be user-clicked early. Broker,
payment, bank, crypto sandbox, and live execution need a stricter execution
path.

Carry forward:

- immutable proposal or trade-ticket hash
- immutable payment, transfer, withdrawal, or correction proposal hash
- approval state for sensitive or live execution modes
- approval expiry and revocation
- signed action envelope
- deterministic action id
- privileged executor boundary
- broker read-back and mismatch handling
- kill switch
- destination and venue allowlists for broker account, market, exchange, sector,
  instrument, beneficiary, IBAN, wallet, or other sensitive destination scopes
- explicit denial for direct order placement, autonomous money movement,
  autonomous ledger posting, account freezing, payout approval, or compliance
  decisions outside an approved executor path

Product framing:

For consumers this appears as paper/live mode, order confirmation, trusted
recipient checks, wallet checks, and "blocked for your protection." For
partners it is the execution control layer.

### P7: Non-Investment Workflow Shelf

Why it still matters:

The old roadmap included operations-heavy payment exceptions, reconciliation
breaks, fraud/risk triage, compliance case preparation, CaseOps, and
TigerBeetle. Those are still plausible Tickoni businesses, but they are no
longer the first consumer-money product path.

Carry forward as shelved or later product lines:

- payment exception workflow
- reconciliation break workflow
- fraud/risk triage workflow
- compliance case-preparation workflow
- CaseOps operations board
- TigerBeetle finance database integration
- accounting ledger connector
- payment, crypto, risk, and compliance adapters
- policy templates for non-investment workflows
- demo adapter fixtures and replayable sample data
- replay capsules for each shelved workflow demo
- non-investment event catalog for payment failures, settlement delays,
  payout blocks, authorization declines, processor timeouts, refund failures,
  capture failures, accounting mismatches, processor batch mismatches, bank
  statement differences, suspected double captures, unmatched refunds,
  settlement amount mismatches, velocity spikes, device clusters, chargeback
  clusters, merchant risk alerts, suspicious payouts, account takeover signals,
  AML alerts, KYC escalations, sanctions matches, transaction-monitoring
  alerts, and unusual activity alerts
- draft-only operator outputs such as merchant responses, investigator notes,
  correction proposals, hold or review proposals, escalation packets,
  compliance case narratives, missing-document classifications, and audit
  packets
- case lifecycle pattern: event arrives, ingest normalizes and dedupes, case is
  created, policy assigns allowed capabilities, agent investigates through the
  governed tool broker, audit records prompts/tools/outputs, draft-only action
  is proposed, human approves or rejects, downstream response is sent only
  after approval, replay capsule is generated, and case moves to audited

Product framing:

Do not delete the ideas. Do not let them distract from consumer money V1.

### P8: Build, Quality, Security, And Release Hygiene

Why it still matters:

The consumer-finance product will touch trade tickets, account state,
recipient and wallet state, payment proposals, transfer proposals, and
sandboxed connectors. Quality and security gates cannot be deferred until after
the demo works.

Carry forward:

- local increment gate commands
- focused tests for each schema, guardrail, adapter, and replay path
- forbidden shell, network, direct adapter, and direct execution tests
- malformed envelope and malformed hook fail-closed tests
- fail-closed validation for policy, model, adapter, destination allowlist, and
  amount/exposure/frequency/holding-period limit configuration
- provider configuration validation
- adapter manifest validation
- sample configs and sample outputs
- documented demo commands for investing, payment, transfer, crypto, and trust
  flows
- audit JSONL samples with valid hash chains
- metrics and diagnostics samples
- replay match samples and intentional divergence tests
- case or thesis fixture sets
- replay capsule samples
- case or thesis divergence test output
- API integration tests for external ingestion and partner review endpoints
- approval and rejection audit samples where approval paths exist
- product demo checklist tied to V1 success metrics
- phase/increment status updates
- V1 non-goals visible in demo materials

Product framing:

This keeps consumer-money demos credible and prevents impressive demos from
accidentally teaching the wrong safety model.

## Increment Evidence Gates

The old phase plan had useful delivery gates. Keep the evidence discipline, but
attach it to each vertical product increment instead of running a waterfall
sequence.

Every V1 increment should close with:

- a documented demo command or script
- fixture data for the thesis, portfolio, market, model, tool, and adapter
  boundaries used by the demo
- audit output for the material user flow
- policy decisions visible in the audit output
- destination checks and limit checks visible in the audit output where they
  apply
- metrics or diagnostics showing queue, policy, model, tool, adapter, audit,
  and replay state for the increment
- replay running without model, broker, payment, trading, or execution side
  effects
- at least one intentional divergence or blocked-flow example
- a product demo checklist that ties the evidence to the increment's user story

Additional gates by increment:

- V1.1 closes when thesis-to-paper-trade output is reproducible from fixtures,
  rejected instruments explain their scope failure, and oversized orders
  produce durable trade-ticket evidence.
- V1.2 closes when a safe payment or payout proposal and an unsafe blocked
  proposal both produce beneficiary, rail, amount, retry, approval, and replay
  evidence.
- V1.3 closes when before/after portfolio, cash, pending-obligation, thesis
  drift, and payment-approval state can be replayed from captured inputs.
- V1.4 closes when copied thesis and money-template flows are resized to the
  user's own account, beneficiary, wallet, and policy limits.
- V1.5 closes when crypto or stablecoin transfer proposals show wallet,
  network, asset, amount, chain-risk, and travel-rule controls.
- V1.6 closes only when sandbox connector behavior can be substituted by replay
  capsules and read-back mismatch handling is demonstrated.
- V1.7 closes when the trust export can show audit timeline, replay status,
  policy version, model/tool/adapter attribution, approval state, and signed
  money-decision records without reading logs.
- V1.8 closes when partners can inspect the capability catalog by action class,
  policy outcome, scope dimension, evidence prerequisite, aggregate limit,
  approval path, and denied-by-default execution or override path.

## Capability Depth Backlog

The capability model should support the consumer-finance product in this order:

| Capability area | V1.1 | V1.2 | V1.3 | Later |
| --- | --- | --- | --- | --- |
| Investment | thesis to basket, ticket, affordability, paper trade | cash impact from payment obligations | portfolio/cash impact loop | broker sandbox/live read-back |
| Payments | payment context visible only as cash fixture | retry, payout, transfer proposal with beneficiary and rail checks | pending obligation and approval state | payment/bank sandbox execution |
| Crypto | excluded from first trade lane | excluded from first payment lane | stablecoin cash preview only | wallet, network, asset, custody, chain-risk guard |
| Limits | market, venue, instrument denylist, notional, frequency | beneficiary, IBAN, rail, currency, amount, retry count | concentration, cash buffer, approval expiry | suitability, mandate, sanctions, travel-rule, restricted lists |
| Model | explainable basket and ticket generation | payment/payout explanation and draft response | thesis and cash-impact explanation | creator/copier and partner explanations |
| Tool/adapter | deterministic market/portfolio fixtures and paper trading adapter | payment and beneficiary fixtures | position/thesis/payment state adapters | broker, payment, bank, crypto sandbox adapters |
| Trust | trade-ticket proof | payment-proposal proof | money-decision history | audit/replay export and partner review |
| Capability control | implicit action classes in flows | explicit payment and transfer outcomes | approval and expiry state | V1.8 action classes, full policy outcomes, scope viewer, aggregate limits, evidence prerequisites |

## V1 Completion Criteria

Consumer Finance V1 is complete when a user can:

1. type an investment thesis
2. receive an explainable basket of US-listed equities or ETFs
3. preview a buy ticket from that basket
4. see buying power, estimated cost, remaining cash, and max affordable amount
5. place the trade in paper mode when it fits limits
6. inspect a failed or delayed payment/payout event
7. propose a retry, transfer, hold, route, or draft response only when
   beneficiary, rail, currency, country, amount, retry, and approval checks pass
8. get a clear reason when a trade, payment, transfer, or wallet proposal is
   blocked, resized, or approval-required
9. see portfolio, cash, and pending-obligation impact before acting
10. monitor the thesis and money proposal after the action
11. export replayable proof for the material money decision

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
