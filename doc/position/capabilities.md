# Tickoni Financial Capability Model

## Purpose

Tickoni capabilities are financial permissions, not operating-system
permissions.

Generic agent systems ask whether an agent can call a tool, open a shell, read a
file, or access a network. Tickoni asks what financial consequence an agent may
participate in:

- which workflow
- which financial object
- which action class
- which destination or venue
- which amount, exposure, frequency, and time window
- which approval path
- which audit and replay obligations

The capability model should feel familiar to banking, payments, brokerage,
treasury, fraud, and compliance teams. Internal tiles such as `tktool`,
`tkadpt`, `tkmodl`, and `tkexec` enforce these capabilities, but agent
manifests and policy templates should not expose tile or OS concepts.

## Product Principles

1. Finance-native language wins over runtime language.
   Use `payment_retry.propose`, not `tool.payment_stub.read`.

2. Scope is part of the permission.
   A capability without account, rail, destination, venue, instrument, amount,
   and frequency constraints is incomplete for sensitive domains.

3. Agents are proposal-first.
   Agents may inspect, classify, summarize, draft, recommend, prepare evidence,
   route cases, and propose actions. Money-impacting execution requires policy
   and human approval.

4. Dangerous actions fail closed.
   Payout approval, ledger posting, account freezing, trading order placement,
   crypto transfer, and risk-rule override are denied by default.

5. Destination allowlists are first-class controls.
   For banking, this means known beneficiaries, IBANs, routing destinations, and
   payment rails. For crypto, this means wallets, networks, and custody
   accounts. For trading, this means broker accounts, asset classes,
   instruments, venues, sectors, and markets.

6. Frequency controls are financial controls.
   Trading permissions need minimum holding periods, minimum order intervals,
   daily/monthly notional limits, round-trip restrictions, and cool-down
   windows. These are not rate limits; they are risk policy.

7. Audit records must explain the consequence.
   Audit should record the financial capability, scope, policy version, decision,
   case, agent role, evidence, proposal, approval state, and downstream result.

## Capability Shape

A Tickoni capability has a finance-native name plus scoped constraints.

```text
domain.object.action
```

Examples:

```text
payment_attempt.read
payment_retry.recommend
payment_retry.propose
processor_record.read
merchant_profile.read_limited
customer_contact.draft

ledger_entry.read
ledger_mismatch.classify
ledger_correction.propose
ledger_adjustment.post

fraud_alert.inspect
risk_signal.read
risk_severity.classify
risk_action.propose_non_executing
account.freeze

trading_portfolio.read
trading_order.recommend
trading_order.propose
trading_order.place
trading_order.cancel

bank_transfer.propose
bank_transfer.initiate
crypto_transfer.propose
crypto_transfer.initiate
```

The name is never enough. The policy scope defines the permitted envelope.

```toml
capability = "trading_order.place"

[scope]
accounts = ["brokerage.demo_ops"]
asset_classes = ["equity", "etf"]
markets = ["US.NYSE", "US.NASDAQ"]
sectors = ["Information Technology"]
sides = ["buy", "sell"]
excluded_instruments = ["option", "future", "leveraged_etf", "inverse_etf"]

[limits]
max_notional_per_order_usd = 2500
max_notional_per_day_usd = 10000
max_notional_per_month_usd = 50000
max_open_orders = 5

[frequency]
min_order_interval_minutes = 60
min_holding_period_days = 1
same_day_round_trip = "deny"
cooldown_after_loss_minutes = 240

[approval]
required = true
approver_roles = ["trading_ops_reviewer"]
```

## Action Classes

Capabilities should be grouped by the consequence of the action.

| Class | Meaning | Default |
| --- | --- | --- |
| Observe | Read financial facts, case context, evidence, balances, positions, alerts | Allow only by workflow and case scope |
| Analyze | Classify, summarize, compare, score, detect discrepancy, estimate risk | Allow only with budget and audit |
| Draft | Draft customer, merchant, finance, compliance, or operator-facing text | Allow only with review state |
| Recommend | Produce a non-binding recommendation | Allow only with evidence and confidence metadata |
| Propose | Create a structured action proposal for approval | Require policy check and audit |
| Prepare | Build a signed or deterministic action envelope without executing it | Require policy check; usually approval-required |
| Execute | Invoke a money, ledger, trading, risk, or compliance effect | Deny by default; require approval and privileged executor |
| Override | Override risk, compliance, policy, ledger, or approval controls | Deny by default; out of V1 |
| Administer | Change policies, limits, credentials, adapters, or allowlists | Deny to agents |

## Scope Dimensions

Every sensitive capability should be scoped across the relevant financial
dimensions.

### Identity And Case Scope

- agent role
- workflow lane
- case id or synthetic run id
- customer, merchant, account, portfolio, or legal entity
- policy version
- environment: development, demo, staging, production

### Payment And Banking Scope

- payment rail: card, ACH, SEPA, SWIFT, RTP, FedNow, local bank transfer
- processor: Stripe, Adyen, Checkout, Airwallex, stub provider, internal
- beneficiary allowlist
- IBAN allowlist or hashed IBAN allowlist
- routing number and account hash allowlist
- country and currency allowlist
- amount per payment, day, month, beneficiary, customer, merchant
- retry count and retry timing
- chargeback or dispute status
- sanctions, KYC, AML, and risk flags

### Crypto Scope

- custody account
- network: Bitcoin, Ethereum, Solana, stablecoin network, L2
- asset: BTC, ETH, USDC, USDT, SOL, approved token list
- wallet address allowlist
- counterparty or exchange account allowlist
- chain analytics risk tier
- travel-rule status where applicable
- amount per transaction, day, month, wallet, asset
- transfer type: internal transfer, withdrawal, deposit reconciliation

### Trading Scope

- broker or OMS account
- asset class: equity, ETF, bond, fund, FX, crypto asset, option, future
- instrument allowlist or denylist
- market: US, EU, UK, APAC, local market
- venue: NYSE, NASDAQ, Cboe, LSE, Xetra, Euronext, OTC, broker dark pool
- sector: GICS or internal sector taxonomy
- side: buy, sell, sell-to-close, buy-to-cover
- order type: market, limit, stop, stop-limit
- notional and quantity limits
- per-order, per-day, per-month exposure limits
- issuer concentration limits
- minimum order interval
- minimum holding period
- same-day round-trip restrictions
- trading session limits
- restricted list and insider list checks
- suitability and mandate constraints

### Ledger And Accounting Scope

- ledger account or book
- legal entity
- accounting period
- journal type
- adjustment type
- source system
- reconciliation batch
- correction proposal amount
- posting destination
- approval threshold
- close-period lock status

### Fraud, Risk, And Compliance Scope

- alert type
- risk tier
- review queue
- entity: customer, merchant, account, transaction, payout
- allowed non-executing action types
- prohibited final decisions
- required evidence set
- escalation threshold
- compliance jurisdiction

## Destination Allowlists

Destination allowlists are a core part of Tickoni's permission model.

### Banking Destinations

```toml
[destinations.bank]
allowed_beneficiaries = ["supplier_acme_us", "processor_settlement_main"]
allowed_ibans_sha256 = [
  "sha256:9f4b...",
  "sha256:61aa..."
]
allowed_rails = ["SEPA", "SWIFT"]
allowed_currencies = ["EUR", "USD"]
allowed_countries = ["DE", "NL", "US"]
```

### Crypto Destinations

```toml
[destinations.crypto]
allowed_wallets = [
  "eth:0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
  "btc:bc1q..."
]
allowed_assets = ["BTC", "ETH", "USDC"]
allowed_networks = ["Bitcoin", "Ethereum"]
max_chain_risk_tier = "low"
```

### Trading Destinations

```toml
[destinations.trading]
allowed_accounts = ["brokerage.ops_us_01"]
allowed_markets = ["US"]
allowed_venues = ["NYSE", "NASDAQ"]
allowed_sectors = ["Information Technology"]
allowed_asset_classes = ["equity", "etf"]
restricted_instruments = ["option", "future", "leveraged_etf", "inverse_etf"]
```

## Example Agent Manifests

### Payment Exception Investigator

```toml
name = "payment-exception-investigator"
role = "payment_exception_investigator"
workflow = "payment_exception"

capabilities = [
  "payment_attempt.read",
  "processor_record.read",
  "merchant_profile.read_limited",
  "payment_failure.classify",
  "payment_retry.recommend",
  "payment_retry.propose",
  "customer_contact.draft",
  "finance_queue.route"
]

[scope]
processors = ["stub_payment_processor"]
rails = ["card", "ACH", "SEPA"]
case_status = ["open", "needs_investigation"]
amount_max_usd = 25000

[approval]
money_impacting_actions = "require_human_approval"
```

### Reconciliation Break Agent

```toml
name = "reconciliation-break-agent"
role = "reconciliation_investigator"
workflow = "reconciliation_break"

capabilities = [
  "ledger_entry.read",
  "processor_record.read",
  "settlement_batch.read",
  "ledger_mismatch.classify",
  "ledger_correction.propose",
  "evidence_packet.prepare",
  "finance_queue.route"
]

[scope]
books = ["payments_clearing_demo"]
legal_entities = ["demo_us"]
correction_amount_max_usd = 10000
posting = "deny"
```

### Trading Control Agent

```toml
name = "trading-control-agent"
role = "trading_ops_reviewer"
workflow = "trading_control"

capabilities = [
  "trading_portfolio.read",
  "market_event.read",
  "trading_order.recommend",
  "trading_order.propose",
  "risk_queue.route"
]

[scope]
accounts = ["brokerage.demo_ops"]
asset_classes = ["equity", "etf"]
markets = ["US"]
venues = ["NYSE", "NASDAQ"]
sectors = ["Information Technology"]
sides = ["buy", "sell"]

[limits]
max_recommended_notional_per_day_usd = 10000
max_recommended_notional_per_month_usd = 50000

[frequency]
min_recommendation_interval_minutes = 60
same_day_round_trip = "deny"
min_holding_period_days = 1

[execution]
place_order = "deny"
```

## Policy Outcomes

Every capability check returns one of:

| Outcome | Meaning |
| --- | --- |
| `allow` | The agent may perform the scoped action now |
| `deny` | The action is outside scope or blocked by policy |
| `require_approval` | The action is valid as a proposal but needs human approval |
| `require_more_evidence` | The proposal cannot proceed until required evidence is attached |
| `escalate` | The case must move to a human or specialist queue |

## Capability Roadmap

### P0: Financial Capability Foundation

Goal: prove that Tickoni can express and enforce finance-native permissions over
synthetic event flows without relying on OS-style permissions.

Must have:

- finance-native capability naming convention
- capability envelope schema with role, workflow, case/run id, scope, and policy version
- `allow`, `deny`, and `require_approval` policy outcomes
- audit records for every capability decision
- default-deny for unknown capabilities
- default-deny for all execution capabilities
- synthetic payment exception capability set
- synthetic reconciliation capability set
- synthetic trading-control capability set with proposal-only trading
- destination allowlist schema for bank, crypto, and trading destinations
- amount and frequency limit schema, even if P0 uses stubs only
- replay-stable policy decisions for deterministic tests

P0 initial capability catalog:

```text
payment_attempt.read
processor_record.read
payment_failure.classify
payment_retry.recommend
payment_retry.propose
customer_contact.draft

ledger_entry.read
settlement_batch.read
ledger_mismatch.classify
ledger_correction.propose

fraud_alert.inspect
risk_signal.read
risk_severity.classify
risk_action.propose_non_executing

trading_portfolio.read
market_event.read
trading_order.recommend
trading_order.propose

evidence_packet.prepare
finance_queue.route
```

P0 explicitly denies:

```text
bank_transfer.initiate
crypto_transfer.initiate
ledger_adjustment.post
trading_order.place
trading_order.cancel
payout.approve
account.freeze
risk_rule.override
policy.modify
```

Exit criteria:

- a synthetic payment event can trigger allowed investigation capabilities
- an out-of-scope payment retry proposal is denied and audited
- a trading proposal over USD 10,000/day or outside US Information Technology is denied
- any order placement attempt is denied
- replay produces the same policy decisions

### P1: Controlled Stub Financial Harness

Goal: use the capability model across stub payment, trading, model, tool, and
adapter paths.

Add:

- stub adapter capability manifests
- scoped processor and settlement reads
- scoped trading portfolio and market-event reads
- destination allowlist validation against stub bank, crypto, and trading destinations
- per-capability approval requirements
- policy templates for payment exception, reconciliation, and fraud/risk workflows
- proposal envelopes with deterministic proposal ids
- model/tool calls attributed to financial capability and workflow, not just provider
- evidence requirements for proposal capabilities

P1 examples:

- `payment_retry.propose` requires processor evidence and retry limit check
- `ledger_correction.propose` requires source record and ledger entry evidence
- `trading_order.propose` requires market, sector, notional, and frequency checks
- `risk_action.propose_non_executing` cannot freeze or block accounts

Exit criteria:

- all model, tool, and adapter calls map to finance-native capabilities
- stub payment and trading workflows run end to end with approvals recorded
- destination allowlist failures are denied before adapter execution
- capability decisions are visible in telemetry and audit export

### P2: Deterministic Case-Scoped Capabilities

Goal: make capabilities case-aware and replayable over durable case records.

Add:

- case-scoped capability derivation
- customer, merchant, account, portfolio, and legal-entity scopes
- evidence prerequisites by capability
- proposal state machine: drafted, policy_checked, approval_required, approved, rejected, expired
- deterministic action ids for approved proposals
- aggregate limits by case, customer, account, beneficiary, instrument, and time window
- replay substitution for model, adapter, and proposal records
- scoped capability changes when case status changes

P2 examples:

- an agent may read only payment attempts attached to the active case
- a reconciliation agent may propose a correction but cannot post it
- a fraud triage agent may route to review but cannot freeze an account
- a trading-control agent may propose only within the case portfolio and policy sector scope

Exit criteria:

- the same event stream creates the same case capability decisions
- proposals remain tied to evidence and policy version
- replay detects changed capability scope or missing evidence
- aggregate limits survive restart and replay

### P3: Real Ingestion And CaseOps Approval Controls

Goal: connect real event ingestion and operator approval workflows without
opening execution autonomy.

Add:

- read-only production connector scopes
- operator approval UI tied to capability outcome
- maker-checker approval model for sensitive proposals
- destination allowlist management with audit
- restricted-list and sanctions/risk checks before approval
- trading market, venue, sector, and instrument policy display in CaseOps
- banking beneficiary and crypto wallet allowlist display in CaseOps
- approval expiry and revocation
- escalation rules for high-risk cases

P3 examples:

- payment retry proposals can be approved by payment operations but still execute only through a controlled executor path
- ledger correction proposals require finance reviewer approval and close-period checks
- trading order proposals show notional, market, sector, venue, frequency, and holding-period constraints before approval
- crypto transfer proposals show network, wallet, asset, and chain-risk controls before approval

Exit criteria:

- operators can inspect why a capability was allowed, denied, or approval-required
- approvals are tied to exact proposal hashes and policy versions
- changing the destination allowlist is audited and not available to agents
- replay never invokes production adapters or execution paths

### P4: Approved Execution And Advanced Financial Controls

Goal: support tightly controlled, human-approved execution for selected
money-adjacent workflows while preserving Tickoni's safety claim.

Add:

- privileged executor capabilities behind `tkexec`
- signed action envelopes for approved bank, ledger, trading, and crypto actions
- multi-approver thresholds by action class and amount
- per-day and per-month exposure controls
- pre-trade checks: market, sector, restricted list, order type, concentration, frequency, holding period
- banking controls: beneficiary allowlist, rail, currency, country, amount, sanctions state
- crypto controls: wallet allowlist, network, asset, custody account, chain-risk tier
- ledger controls: close period, legal entity, book, adjustment type, idempotency key
- post-execution read-back and reconciliation
- emergency kill switch and policy rollback

P4 example: approved trading execution scope:

```toml
capability = "trading_order.place"

[scope]
accounts = ["brokerage.ops_us_01"]
asset_classes = ["equity", "etf"]
markets = ["US"]
venues = ["NYSE", "NASDAQ"]
sectors = ["Information Technology"]
sides = ["buy", "sell"]
order_types = ["limit"]

[limits]
max_notional_per_order_usd = 2500
max_notional_per_day_usd = 10000
max_notional_per_month_usd = 50000
max_symbol_concentration_pct = 5

[frequency]
min_order_interval_minutes = 60
min_holding_period_days = 1
same_day_round_trip = "deny"
max_orders_per_day = 8

[approval]
required = true
approver_roles = ["trading_ops_reviewer", "risk_reviewer"]
expires_after_minutes = 30
```

P4 explicitly remains non-autonomous unless a later roadmap changes the product
positioning. An agent may recommend, propose, and prepare. Execution requires
policy, approval, signed envelope, privileged executor, audit, and read-back.

Exit criteria:

- no approved action can execute outside its destination, amount, frequency, and approval scope
- duplicate execution is prevented by deterministic action ids
- every execution has before-and-after audit records
- read-back confirms downstream result or opens a reconciliation case
- kill switch blocks all sensitive execution capabilities immediately

## Open Product Questions

1. Should trading capabilities remain demo-only in V1, or should P4 include a
   regulated sandbox broker integration?
2. Which sector taxonomy should be canonical: GICS, NAICS, internal, or adapter-provided?
3. Should crypto destinations be included in V1 examples, or reserved for V2 due
   to travel-rule and custody complexity?
4. What is the minimum viable maker-checker model for payment and ledger
   proposals?
5. How should policy templates be versioned when financial regulations or
   internal risk policies change?
