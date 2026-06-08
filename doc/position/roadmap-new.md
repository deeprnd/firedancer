# Tickoni Investment Roadmap

## Product Bet

Tickoni should lead with an investment experience, not an operations or
governance console.

The product should feel closer a modern AI investing
copilot than to a SecOps platform:

```text
I have a thesis.
Tickoni turns it into a tradable idea.
Tickoni checks whether I can afford it.
Tickoni shows how it changes my portfolio.
Tickoni lets me place or simulate the trade inside hard financial limits.
```

The control model still matters, but it should be felt as product magic:

- "You can afford this trade."
- "This exceeds your buying power."
- "This would make your portfolio too concentrated in semiconductors."
- "This instrument is outside your mandate."
- "This is a same-day round trip; wait until tomorrow or reduce scope."
- "Your USD 2,000 thesis fits as a 4-position AI infrastructure basket."

Audit, replay, approval, and policy are the engine room. They should not be the
headline for the first product story.

## Target User

V1 is for an active retail or prosumer investor who wants AI help turning market
views into disciplined trades:

- self-directed investor
- social/copy-trading user
- fintech demo user
- trading operations reviewer in a sandbox account
- founder/investor evaluating Tickoni as an agentic investing runtime

The user is not trying to audit an agent. The user is trying to make a better
investment decision quickly, with confidence that the system will not let them
overspend or violate their mandate.

## Product Principles

1. Lead with the investment thesis.
   The user starts with a market view, not a policy form.

2. Make constraints feel like intelligence.
   Buying power, notional limits, venue scope, restricted instruments, sector
   concentration, and holding-period rules should appear as helpful trade
   guidance.

3. The first wow is thesis-to-ticket.
   The user should see a vague idea become concrete instruments, position
   sizes, expected cost, portfolio impact, and a ready trade ticket.

4. Execution starts in sandbox or paper mode.
   Live execution can come later behind signed adapters, approval, and
   privileged executor paths. V1 should still make the trade flow feel real.

5. Keep the safety model finance-native.
   Use accounts, buying power, markets, venues, sectors, instruments, order
   types, notional, exposure, frequency, and holding period. Do not expose
   OS-style permissions as product language.

## Baseline: V1.0 Runtime Proof

Status: done.

What exists today is a technical proof: Tickoni can process deterministic
financial events, reject bad input, dedupe duplicates, make basic policy
decisions, write hash-chained audit records, replay a run, and report health.

That work is valuable infrastructure, but it is not yet the product story.

The remaining roadmap should turn the runtime into an investment product.

## Investment V1: Three Wow Features

V1 should be judged by whether a user can do three impressive things:

1. **Thesis to Basket**
   Turn an investment thesis into a concrete, explainable basket of stocks or
   ETFs.

2. **Buying-Power Trade Ticket**
   Convert the basket into a trade ticket that checks cash, exposure, account
   limits, venue, asset class, sector, order type, and affordability.

3. **Portfolio Impact Loop**
   Show how the trade changes the user's portfolio, then track whether the
   original thesis is still intact after market moves.

Everything else is support.

## Increment Roadmap

### V1.1: Thesis To Basket

User story:

As an investor, I can type a plain-English market thesis and Tickoni turns it
into a concrete investment basket.

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

Why this is cool:

The product turns a fuzzy market view into a disciplined investment idea in
seconds. The user does not need to start with ticker symbols.

What is better than V1.0:

- V1.0 proved Tickoni can process financial events.
- V1.1 gives the user an investing copilot that turns intent into an
  explainable basket.

Capability depth:

- `trading_portfolio.read`
- `market_event.read`
- `trading_order.recommend`
- account scope
- asset class scope: equity and ETF
- market and venue scope: US, NYSE, NASDAQ
- instrument denylist: options, futures, leveraged ETFs, inverse ETFs
- sector and theme tagging

Success demo:

An exec types one investment thesis and gets a polished basket with allocations,
explanations, and rejected out-of-scope ideas.

Non-goals:

- no live order placement
- no payment retry workflows
- no reconciliation workflows
- no CaseOps board
- no compliance-console UI

### V1.2: Buying-Power Trade Ticket

User story:

As an investor, I can turn the recommended basket into a trade ticket and
Tickoni tells me whether I can actually afford it.

Example:

```text
"Buy the AI infrastructure basket for USD 2,000."
```

Tickoni answers:

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

What the user can do:

- preview a buy or sell ticket from the basket
- change the amount, side, order type, or instrument weights
- see whether the order fits available cash and configured account limits
- see maximum affordable notional if the request is too large
- place the trade in paper/sandbox mode or save it as a proposal

What the user sees:

- estimated cost
- cash available
- buying power after trade
- per-instrument allocation
- sector exposure before and after
- rejected or resized orders with clear reasons
- a one-click paper trade action when the ticket fits

Why this is cool:

The product does not just recommend tickers. It turns the recommendation into a
trade the user can size, understand, and execute in a controlled sandbox.

What is better than V1.1:

- V1.1 produced a basket.
- V1.2 turns that basket into an actionable trade ticket with cash,
  affordability, account, exposure, venue, instrument, and frequency checks.

Capability depth:

- `trading_portfolio.read`
- `trading_order.recommend`
- `trading_order.propose`
- sandbox `trading_order.place` if paper execution is enabled
- account buying-power check
- per-order notional limit
- per-day notional limit
- asset class, market, venue, sector, side, and order type checks
- same-day round-trip and minimum holding-period checks

Success demo:

An exec asks to buy USD 2,000 of the AI basket. Tickoni produces a ticket,
checks buying power, shows portfolio impact, and places the paper trade. Then
the exec changes USD 2,000 to USD 25,000 and Tickoni explains the maximum
affordable amount and why the larger order is blocked.

Non-goals:

- no production broker integration
- no margin trading
- no options, futures, leveraged ETFs, or crypto
- no autonomous rebalancing

### V1.3: Portfolio Impact Loop

User story:

As an investor, I can see how a trade changes my portfolio before and after I
place it, and Tickoni keeps tracking whether the original thesis still holds.

Example:

```text
"If I buy this AI infrastructure basket, what changes in my portfolio?"
```

Tickoni answers:

```text
Technology exposure increases from 22% to 31%.
Single-name concentration remains below 8%.
ETF exposure increases from 36% to 43%.
Cash drops from USD 5,240.18 to USD 3,242.76.
Your AI infrastructure thesis is now represented by four positions.
```

What the user can do:

- compare portfolio before and after a proposed trade
- see sector, asset class, ticker, and cash impact
- save the thesis as a monitored investment idea
- receive thesis drift alerts, such as:
  - position moved outside target allocation
  - sector exposure exceeded threshold
  - market event affects one instrument in the thesis
  - buying power changed enough to resize the trade
- generate a rebalance suggestion in paper/proposal mode

What the user sees:

- before/after portfolio view
- thesis card
- position weights
- exposure heatmap
- cash and buying power
- thesis health status
- rebalance suggestion

Why this is cool:

The trade is not a one-off ticket. Tickoni remembers the investment reason and
keeps the portfolio connected to the thesis.

What is better than V1.2:

- V1.2 checked whether the user could afford and place a paper trade.
- V1.3 shows whether the trade actually fits the portfolio and keeps monitoring
  the thesis after the trade.

Capability depth:

- `trading_portfolio.read`
- `market_event.read`
- `trading_order.recommend`
- `trading_order.propose`
- thesis state tied to positions
- exposure and concentration limits
- rebalance recommendation only; no autonomous rebalance execution

Success demo:

An exec buys the AI basket in paper mode, sees the portfolio change instantly,
then sees Tickoni keep a thesis card alive with exposure, cash, and drift
signals.

Non-goals:

- no tax optimization
- no portfolio margin
- no autonomous trade placement
- no social copy trading yet

## Later Hardening And Expansion

The first three increments should create the wow. Later increments deepen trust,
execution, and distribution.

### V1.4: Guarded Live-Trading Sandbox

User story:

As a product evaluator, I can connect a broker sandbox account and place
approved small trades through the same thesis-to-ticket flow.

Adds:

- broker sandbox connector
- signed adapter manifest
- read-back of submitted orders
- deterministic action id
- paper/live mode switch
- kill switch

Still excludes:

- production live trading by default
- margin
- derivatives
- autonomous execution

### V1.5: Social Thesis Feed

User story:

As an investor, I can browse other thesis cards, inspect their basket and risk
checks, and copy a thesis into my own account with my own buying-power and
portfolio-fit checks.

Adds:

- shareable thesis cards
- copy-to-my-portfolio flow
- account-specific resizing
- "why my version differs" explanation
- creator performance snapshot

Still excludes:

- unbounded copy trading
- bypassing account-specific limits
- influencer-driven auto-execution

### V1.6: Trust Layer

User story:

As a regulated fintech or brokerage partner, I can inspect the proof behind
each recommendation and trade ticket.

Adds:

- audit timeline
- replay capsule
- policy version
- model/tool/adapter attribution
- approval state where required
- exportable trade-decision record

Product framing:

This is not the headline user experience. It is the enterprise trust layer that
makes the investing product credible for partners.

## Capability Depth Backlog

The capability model should support the investing product in this order:

| Capability area | V1.1 | V1.2 | V1.3 | Later |
| --- | --- | --- | --- | --- |
| Thesis | natural-language thesis to basket | thesis converted to ticket | thesis monitored after trade | social thesis feed |
| Portfolio | read demo holdings | buying power and cash checks | before/after exposure | broker sandbox/live read-back |
| Trading | recommend basket | propose and paper-place ticket | rebalance recommendation | guarded live sandbox |
| Limits | asset class, market, venue, instrument denylist | notional, cash, frequency, order type | concentration and drift | suitability, mandate, restricted list |
| Model | explainable basket generation | ticket explanation and resizing | thesis health explanation | creator/copier explanations |
| Tool/adapter | deterministic market/portfolio fixtures | paper trading adapter | position/thesis state adapter | broker sandbox adapter |
| Trust | minimal internal records | trade-ticket proof | thesis history | audit/replay export |

## V1 Completion Criteria

Investment V1 is complete when a user can:

1. type an investment thesis
2. receive an explainable basket of US-listed equities or ETFs
3. preview a buy ticket from that basket
4. see buying power, estimated cost, remaining cash, and max affordable amount
5. see portfolio impact before placing the trade
6. place the trade in paper/sandbox mode when it fits limits
7. get a clear reason when a trade is blocked or resized
8. monitor the thesis after the trade

## V1 Non-Goals

V1 should not include:

- production live trading by default
- margin trading
- options, futures, leveraged ETFs, inverse ETFs, or complex derivatives
- autonomous rebalancing
- quant strategy generation
- market-making
- tax optimization
- payment exception workflows
- reconciliation workflows
- fraud/risk triage workflows
- compliance-console-first UX
- open plugin marketplace
- unbounded agent swarms
