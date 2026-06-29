# Tickoni UI Proposal: Bloomberg-Style Money Control Terminal

## Context

The reference image has the visual language of a dense financial terminal: dark background, ticker strip, status badges, large metric cards, execution pipeline, graph/network canvas, heatmaps, distribution charts, scatter plots, and live operational micro-panels.

That visual direction is useful for Tickoni, but the product should not become a trading-alpha cockpit. Tickoni should borrow the density, seriousness, and real-time feel of Bloomberg-like financial systems while centering the product around:

```text
intent → policy → proposal → approval → paper/sandbox action → audit/replay
```

The strongest UI direction is:

```text
Bloomberg terminal for safe financial actions.
```

Not:

```text
Bloomberg terminal for AI trading performance.
```

---

## Product Principle

Tickoni should look like a serious financial system, but the dominant visual object should be the policy-checked consequence, not agent performance, PnL rank, or trading ego.

A concise product line:

```text
Tickoni turns money intent into policy-checked, replayable financial proposals.
```

---

## Reference Image: Useful Visual Patterns

The image suggests several visual patterns worth adapting:

```text
┌─────────────────────────────┬─────────────────────────────┬───────────────┐
│ Large account/status cards  │ Decision/result cards       │ Market panel  │
├─────────────────────────────┴─────────────────────────────┴───────────────┤
│ Execution pipeline / lifecycle                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ Dense graph canvas / evidence map / relationship map                       │
├─────────────────────────────┬─────────────────────────────┬───────────────┤
│ Heatmap / robustness table   │ Scenario distribution       │ Scatter/gates │
└─────────────────────────────┴─────────────────────────────┴───────────────┘
```

For Tickoni, translate those into:

```text
trader rank            → policy outcome
biggest win            → safest allowed action
alpha / PnL            → impact, exposure, buying power
execution cycle        → intent-to-safe-action pipeline
force graph            → evidence / audit / replay graph
heatmap                → policy scope and exposure map
Monte Carlo            → affordability / consequence scenarios
scatter plot           → policy gates and blocked reasons
```

---

## Main UI Diagram

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ TICKONI TERMINAL     PAPER     USD     US-MKT     POLICY: v1.11   UTC 17:36 │
│ INTENT  SAFE-ACTION  CASEOPS  AUDIT  REPLAY  CAPS  ADAPTERS  HEALTH         │
├──────────────────────────────────────────────────────────────────────────────┤
│ ACCOUNT / PORTFOLIO                  │ ACTIVE SAFE-ACTION                    │
│ Cash              $5,240.18          │ Thesis: AI infrastructure, $2,000      │
│ Buying Power      $7,800.00          │ Mode: Paper                            │
│ Exposure Tech     22% → 31%          │ Universe: US equities + ETFs           │
│ Single Name Max   7.4% / 8.0%        │ Status: ALLOWED                        │
│ Daily Notional    $2,000 / $10,000   │ Action: Save / Paper Place             │
├──────────────────────────────────────┼───────────────────────────────────────┤
│ INTENT → SAFE ACTION PIPELINE        │ POLICY DECISION                        │
│ 01 Normalize  ██████████ OK          │ Cash check                 PASS        │
│ 02 Build      ██████████ OK          │ Buying power               PASS        │
│ 03 Validate   ██████████ OK          │ Venue: NYSE/NASDAQ         PASS        │
│ 04 Policy     ██████████ ALLOW       │ Denylist: options/SOXL     PASS        │
│ 05 Proposal   ██████████ SIGNED      │ Holding period             PASS        │
│ 06 Paper Fill ██████████ READY       │ Human approval             NOT REQUIRED│
├──────────────────────────────────────┴───────────────────────────────────────┤
│ PROPOSED BASKET                                                              │
│ TICKER   ROLE                         ALLOC   PRICE    STATUS    REASON      │
│ SMH      Semiconductor exposure        35%     225.14   PASS      thesis fit  │
│ CLOU     Cloud infra exposure          25%      19.40   PASS      ETF/diverse │
│ MSFT     Large-cap AI platform         25%     478.20   PASS      cap OK      │
│ ANET     Data-center networking        15%     104.10   PASS      weight OK   │
│ SOXL     Leveraged semiconductor ETF    0%      --      DENY      restricted  │
├──────────────────────────────────────────────────────────────────────────────┤
│ CASE GRAPH / EVIDENCE MAP                                                    │
│ intent ── thesis_parse ── catalog ── quotes ── basket ── ticket ── policy     │
│                         │          │          │          │                   │
│                         └─ rejected instruments ─────────┘                   │
│ Evidence refs: catalog_hash, quote_snapshot, account_snapshot, policy_hash    │
├──────────────────────────────────────┬───────────────────────────────────────┤
│ IMPACT                               │ AUDIT / REPLAY BLACK BOX              │
│ Cash before        $5,240.18         │ event_hash       92af...              │
│ Trade cost         $1,997.42         │ proposal_hash    b17c...              │
│ Cash after         $3,242.76         │ model_route      offline/mock         │
│ Tech exposure      +9.0 pts          │ adapter          paper_broker:v0      │
│ ETF exposure       +7.0 pts          │ replay           MATCH                │
│ Concentration      within mandate    │ tamper check     CLEAN                │
├──────────────────────────────────────┴───────────────────────────────────────┤
│ COMMAND:  /explain basket  /show denial  /paper place  /save proposal        │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Screen Architecture

```text
Tickoni
├─ Money Intent Console
│  ├─ Investment thesis input
│  ├─ Payment / payout / transfer input
│  └─ Natural-language normalization result
│
├─ Safe Action Workbench
│  ├─ Basket builder
│  ├─ Trade ticket preview
│  ├─ Payment retry / transfer proposal
│  ├─ Rejected candidates
│  └─ Save / paper-place / approval-required actions
│
├─ Policy Gate
│  ├─ Buying power
│  ├─ Notional limits
│  ├─ Market / venue / instrument scope
│  ├─ Beneficiary / wallet / rail / currency scope
│  ├─ Frequency / holding-period rules
│  └─ Allow / deny / approval-required decision
│
├─ Impact View
│  ├─ Cash before / after
│  ├─ Portfolio before / after
│  ├─ Exposure heatmap
│  ├─ Pending obligations
│  └─ Thesis health
│
├─ Audit Black Box
│  ├─ Event hash
│  ├─ Policy hash
│  ├─ Proposal hash
│  ├─ Model / tool / adapter attribution
│  ├─ Approval state
│  └─ Replay capsule
│
└─ Partner Control Plane
   ├─ Capability catalog
   ├─ Adapter status
   ├─ Approval paths
   ├─ Aggregate limits
   └─ Exportable proof bundle
```

---

## Bloomberg-Style Visual System

```text
Background
  near-black / dark navy

Typography
  condensed monospace for numbers
  compact sans for labels
  dense table typography for operational panels

Panel borders
  thin gray-blue lines
  sharp rectangular divisions
  minimal radius

Status colors
  green  = allowed / pass / replay match
  red    = denied / failed / tamper detected
  amber  = approval required / evidence missing / budget warning
  blue   = selected step / active workflow
  gray   = unavailable / pending / inactive

Density
  high information density
  no whitespace-heavy consumer dashboard
  all panels should have explicit operational purpose

Motion
  ticker strips
  queue counters
  adapter pings
  replay status
  policy gate transitions

Controls
  command bar
  keyboard-first navigation
  function-key style actions
  slash commands
```

---

## Avoid These Reference-Image Concepts

Do not copy the gamified trading ideas literally.

```text
Avoid:
  biggest win
  beating traders
  global rank
  alpha score
  trader leaderboard
  self-learn PnL hero card
  profit-first status panels
  dopamine-style celebration

Use instead:
  allowed
  denied
  approval required
  evidence missing
  replay match
  policy mismatch
  budget near cap
  adapter degraded
  proposal signed
  paper fill ready
```

---

## V1.1 Investment Terminal

```text
┌─ INVEST INTENT ──────────────────────────────────────────────────────────────┐
│ "Invest $2,000 in AI infrastructure, avoid single-name concentration,        │
│  keep it to US-listed ETFs or large-cap equities."                           │
├─ NORMALIZED INTENT ──────────────────────────────────────────────────────────┤
│ amount:        2,000 USD                                                     │
│ market:        US                                                            │
│ venues:        NYSE, NASDAQ                                                  │
│ asset classes: equity, ETF                                                   │
│ exclusions:    options, futures, leveraged ETFs, inverse ETFs                │
│ concentration: single-name below 8%                                           │
├─ BASKET + TICKET ────────────────────────────────────────────────────────────┤
│ SMH   35%   Semiconductor exposure       market order   PASS                 │
│ CLOU  25%   Cloud infrastructure ETF      market order   PASS                 │
│ MSFT  25%   Large-cap AI platform         market order   PASS                 │
│ ANET  15%   Data-center networking        market order   PASS                 │
├─ REJECTED ───────────────────────────────────────────────────────────────────┤
│ SOXL        leveraged semiconductor ETF                 DENY restricted      │
│ NVDA CALL   options contract                           DENY asset class      │
├─ POLICY ─────────────────────────────────────────────────────────────────────┤
│ cash check                    PASS                                           │
│ buying power                  PASS                                           │
│ per-order notional             PASS                                           │
│ daily notional                 PASS                                           │
│ market / venue scope           PASS                                           │
│ restricted instrument          PASS                                           │
│ same-day round trip            PASS                                           │
│ minimum holding period         PASS                                           │
└─ ACTION ─────────────────────────────────────────────────────────────────────┘
  [Save Proposal]  [Paper Place]  [Explain]  [Show Audit]
```

---

## V1.2 Payment / Transfer Guard

```text
┌─ FAILED PAYOUT ──────────────────────────────────────────────────────────────┐
│ supplier_acme_us       ACH       USD 1,240       status: failed              │
├─ FAILURE CLASSIFICATION ─────────────────────────────────────────────────────┤
│ reason: processor timeout                                                    │
│ retryable: yes                                                               │
│ evidence: processor_record, payout_event, beneficiary_profile                │
├─ POLICY CHECKS ──────────────────────────────────────────────────────────────┤
│ beneficiary known              PASS                                          │
│ rail ACH                       PASS                                          │
│ currency USD                   PASS                                          │
│ country US                     PASS                                          │
│ retry count 1 / 2              PASS                                          │
│ daily beneficiary limit        PASS  $8,760 remaining                         │
│ risk flags                     PASS  none active                              │
├─ DECISION ───────────────────────────────────────────────────────────────────┤
│ SAFE TO PROPOSE                                                              │
│ Execution requires approval.                                                 │
│ Approval expires in 4h.                                                       │
└─ ACTION ─────────────────────────────────────────────────────────────────────┘
  [Draft Supplier Message]  [Save Retry Proposal]  [Request Approval]
```

---

## V1.3 Portfolio + Cash Impact Loop

```text
┌─ COMBINED IMPACT ────────────────────────────────────────────────────────────┐
│ Scenario: AI basket + supplier payout proposal                               │
├─ BEFORE / AFTER ─────────────────────────────────────────────────────────────┤
│ Cash:                 $5,240.18 → $2,002.76                                  │
│ Technology exposure:  22% → 31%                                              │
│ ETF exposure:         36% → 43%                                              │
│ Single-name max:      7.4% → 7.8%                                            │
│ Pending obligation:   supplier payout awaiting approval                       │
├─ THESIS HEALTH ──────────────────────────────────────────────────────────────┤
│ represented by four positions                                                │
│ concentration within mandate                                                 │
│ no restricted instruments                                                     │
│ payout approval still unexecuted                                              │
├─ ALERTS ─────────────────────────────────────────────────────────────────────┤
│ approval expires in 4h                                                        │
│ cash buffer remains above target                                              │
│ rebalance not required                                                        │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Partner Trust Layer

```text
┌─ TRUST / AUDIT VIEW ─────────────────────────────────────────────────────────┐
│ case_id:              case_2026_06_26_000493                                 │
│ event_hash:           92af...                                                │
│ policy_hash:          84de...                                                │
│ proposal_hash:        b17c...                                                │
│ model_route:          offline/mock                                           │
│ adapter:              paper_broker:v0                                        │
│ actor:                user:victor                                            │
│ agent:                investment_case_agent                                  │
│ approval_state:       not_required                                           │
│ replay_status:        MATCH                                                  │
│ tamper_check:         CLEAN                                                  │
├─ TIMELINE ───────────────────────────────────────────────────────────────────┤
│ 01 event received                                                            │
│ 02 intent normalized                                                         │
│ 03 basket built                                                              │
│ 04 rejected instruments recorded                                             │
│ 05 ticket validated                                                          │
│ 06 policy decision: allow                                                    │
│ 07 proposal signed                                                           │
│ 08 paper fill ready                                                          │
│ 09 replay capsule sealed                                                     │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## CaseOps Board

```text
┌────────────────┬──────────────┬──────────────┬──────────────┬──────────────┐
│ New Event      │ Enriched     │ Agent Review │ Policy Gate  │ Human Review │
├────────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ payout failed  │ quotes ready │ basket built │ allow        │ approval req │
│ thesis input   │ acct loaded  │ msg drafted  │ deny SOXL    │ pending      │
└────────────────┴──────────────┴──────────────┴──────────────┴──────────────┘

┌────────────────┬──────────────┬──────────────┐
│ Action Proposed│ Resolved     │ Audited      │
├────────────────┼──────────────┼──────────────┤
│ paper ticket   │ fill saved   │ replay match │
│ retry proposal │ waiting      │ hash sealed  │
└────────────────┴──────────────┴──────────────┘
```

---

## Product Navigation

```text
Top-level navigation:
  INTENT
  SAFE-ACTION
  PORTFOLIO
  PAYMENTS
  CASEOPS
  AUDIT
  REPLAY
  CAPABILITIES
  ADAPTERS
  HEALTH

Primary command examples:
  /new thesis
  /check payout
  /explain denial
  /show policy
  /show impact
  /save proposal
  /paper place
  /request approval
  /replay case
  /export proof
```

---

## Implementation Guidance

The UI should prioritize the following screens first:

```text
1. V1.1 Investment safe-action screen
   - thesis input
   - normalized intent
   - basket
   - rejected candidates
   - trade ticket
   - policy decision
   - paper action
   - replay proof

2. V1.2 Payment guard screen
   - failed payout/payment event
   - beneficiary / rail / currency / retry checks
   - safe-to-propose decision
   - approval requirement
   - draft message
   - evidence packet

3. V1.3 Impact screen
   - before/after cash
   - before/after exposure
   - pending obligations
   - thesis health
   - approval state

4. Trust layer
   - audit timeline
   - replay capsule
   - policy hash
   - proposal hash
   - adapter attribution
   - exportable proof bundle
```

---

## Strong Final Direction

```text
Tickoni should look like a financial terminal, but behave like a safety-critical
money-control system.

The reference image gives the correct density and operational seriousness.
Tickoni should replace trader-gamification with policy, consequence, proof,
and replay.
```
