# V1.1 Investment Demo Integration Tests

## Purpose

This document defines the Tickoni integration-test scenarios for
`V1.1.S6: Investment demo and proof`.

The goal is to prove the V1.1 product story end to end:

```text
plain-English thesis
  -> basket
  -> trade ticket
  -> affordability check
  -> USD 2,000 allowed paper trade
  -> USD 25,000 blocked oversized variant
  -> restricted-instrument rejection
  -> audit-ready evidence
  -> replay without live external effects
```

Per [Tickoni Testing](../testing-tickoni.md), these are integration tests:
Tickoni-owned runtime paths stay real, while external systems are replaced at
the harness boundary with deterministic local fixtures.

## Assumptions

- This closes the `V1.1 Investment Intent To Paper Trade` epic from
  [roadmap.md](../position/roadmap.md) and
  [wbs.md](../position/wbs.md).
- The test command should become a real Tickoni integration recipe behind the
  existing `just test-integration-tk` placeholder or a narrower command that it
  invokes.
- The demo command may share fixtures with the integration tests, but the test
  assertion layer should validate machine-readable output, not terminal copy.
- `trading_order.place` is paper-only in V1.1 and must not imply broker
  sandbox or live execution authority.
- Replay must not call an LLM server, broker, market-data provider, payment
  system, trading API, or executor.
- The live model lane should use
  [`unsloth/gemma-4-E2B-it-qat-GGUF`](https://huggingface.co/unsloth/gemma-4-E2B-it-qat-GGUF)
  with the `UD-Q4_K_XL` GGUF quantization through a local
  OpenAI-compatible `llama.cpp` server. Hugging Face lists this model repo as
  GGUF, Apache-2.0 licensed, and provides `llama-server -hf
  unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL` examples. The model page also
  lists `UD-Q4_K_XL` around 2.62 GB and the model size as 5B params.
- The GitHub Actions public `ubuntu-latest` runner target is viable for a
  bounded smoke lane: GitHub lists public Linux `ubuntu-latest` runners as
  4 vCPU, 16 GB RAM, and 14 GB SSD. The smoke lane must cap prompt length,
  generated tokens, context size, and wall time so model download plus
  inference does not crowd out the rest of CI.

## Integration Boundary

The integration test keeps these Tickoni paths real:

- request framing and source offsets through `tkings`
- thesis normalization through `tknorm`
- dedupe through `tkdedu`
- deterministic synthetic case or run scope through `tkcase`
- capability decisions through `tkpoly`
- audit ordering through `tkaudt`
- bounded agent dispatch through `tkdisp` and `tkagnt`
- model access through `tkmodl`
- tool and adapter calls through `tktool` and `tkadpt`
- replay comparison through `tkrepl`
- metrics and diagnostics through `tkmetr` and `tkdiag`

The test replaces only external systems:

- `tkmodl` talks to a deterministic local model fixture or recorded model
  response, not a live cloud model.
- `tkadpt` talks to a paper trading adapter fixture for quotes, portfolio
  reads, and paper fills.
- `tkexec` remains disabled. Paper placement is represented by the V1.1 paper
  adapter result, not privileged execution.

This still exercises an LLM boundary. The model does not get bypassed. The
simple fixture lane uses captured model output for deterministic assertions,
the live-LLM smoke lane uses the real local model through `tkmodl`, and replay
substitutes the captured provider response by hash.

## Test Topology

The V1.1 integration topology should use one synthetic run id and one demo
account:

```text
demo command or fixture
  -> tkings
  -> tknorm
  -> tkdedu
  -> tkcase
  -> tkpoly
  -> tkaudt

tkcase -> tkdisp -> tkagnt
tkagnt -> tkmodl
tkagnt -> tktool -> tkadpt.paper_trading

tkpoly -> tkaudt
tkmodl -> tkaudt
tktool -> tkaudt
tkadpt -> tkaudt
tkagnt -> tkaudt

tkaudt -> replay capsule
tkrepl -> deterministic replay with model and adapter substitutions
```

Required links:

| Link | Producer | Consumer | Payload | Reliability |
| --- | --- | --- | --- | --- |
| `tkings_tknorm` | `tkings` | `tknorm` | accepted thesis request event | reliable |
| `tknorm_tkdedu` | `tknorm` | `tkdedu` | normalized investor intent | reliable |
| `tkdedu_tkcase` | `tkdedu` | `tkcase` | deduped intent event | reliable |
| `tkcase_tkpoly` | `tkcase` | `tkpoly` | case-scoped capability envelope | reliable |
| `tkcase_tkdisp` | `tkcase` | `tkdisp` | bounded agent work item | reliable |
| `tkdisp_tkagnt` | `tkdisp` | `tkagnt` | agent run request | reliable |
| `tkagnt_tkmodl` | `tkagnt` | `tkmodl` | model request with budget | reliable |
| `tkagnt_tktool` | `tkagnt` | `tktool` | finance-native tool request | reliable |
| `tktool_tkadpt` | `tktool` | `tkadpt` | adapter request envelope | reliable |
| `*_tkaudt` | all material boundary tiles | `tkaudt` | audit event | reliable |
| `tkaudt_tkrepl` | `tkaudt` | `tkrepl` | replay capsule reference | reliable |
| `*_tkmetr` | all tiles | `tkmetr` | metrics sample | counted-loss OK |
| `*_tkdiag` | all tiles | `tkdiag` | diagnostic sample | counted-loss OK |

## Test Lanes

The V1.1 suite should split the demo into three lanes so it stays useful in
developer loops and credible in CI:

- `simple integration`: `just test-integration-tk` or a delegated V1.1 command
  uses recorded model output. This is the fast deterministic gate for basket,
  ticket, affordability, paper execution, blocked variants, audit, and replay.
- `real-LLM smoke`: a narrower opt-in CI job or local demo command uses real
  `unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL` inference through `tkmodl`.
  This proves the AI harness actually runs a local model inside the governed
  model boundary.
- `replay`: the replay command uses the same fixture capsule as the simple and
  smoke lanes, with no live model call. This proves model and adapter outputs
  are substituted by hash with external effects disabled.

The simple integration lane should be the normal gate. The real-LLM smoke lane
should run on a small prompt, small context, deterministic sampling settings,
and a tight token cap. It should persist the model request, response, token
usage, prompt hash, response hash, model id, and runtime metadata into fixture
output so the replay lane can validate the same run without invoking the
model again.

The real-LLM lane must check for the GGUF before starting the local model
server:

```bash
just test-integration-tk
```

That command checks for:

```text
model_dir = ~/work/models/gemma/gemma-4-E2B-it-qat-GGUF
model_file = gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
```

If the file exists and is non-empty, it does nothing. If the file is missing,
it downloads only `gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf` from
`unsloth/gemma-4-E2B-it-qat-GGUF` using `hf download`. CI can use
`just test-integration-tk` when it needs a no-network
preflight that fails if the model is absent.

Simple integration tests in the normal gate:

- `ai_infrastructure_allowed_trade`: allowed thesis, account, quotes, and recorded model
  response produce basket, ticket, affordability `allow`, paper execution,
  audit, and replay.
- `v1_1_oversized_25000`: oversized thesis plus account or policy limit fixture
  produces a blocked ticket, max amounts, no paper fill, audit, and replay.
- `v1_1_restricted_instrument`: restricted ticker request and catalog fixture
  produce a restricted ticker rejection, no ticket line, no paper fill, audit,
  and replay.
- `v1_1_direct_place_denied`: place request without ticket or proposal hash is
  denied by `tkpoly` before any adapter call.
- `v1_1_malformed_thesis_denied`: empty text, missing amount, and unsupported
  asset class fail closed before model, tool, adapter, or paper execution.
- `v1_1_replay_divergence`: allowed replay capsule plus modified fixture hash
  reports the first divergent record and no external effects.

Order-type assumptions:

- Use market and limit orders because they are common investor order types and
  are the current V1.1-supported paper order types.
- Market orders are used for the simplest allowed paper execution path.
- Limit orders are tested in both positive and negative paths: marketable buy
  limits with line-level limit prices are allowed, while missing limit prices
  fail closed before paper execution.
- Do not add stop, stop-loss, bracket, options, margin, short sale, or live
  execution scenarios to V1.1.S6. They are outside the current V1.1 scope.
- Reference material:
  [Investor.gov order types][investor-order-types] and
  [SEC trade execution][sec-trade-execution].

[investor-order-types]: https://www.investor.gov/introduction-investing/investing-basics/how-stock-markets-work/types-orders
[sec-trade-execution]: https://www.sec.gov/about/reports-publications/investorpubstradexec

## Capability Configuration

The test policy should use one explicit V1.1 demo role:

```text
actor_role = trading_ops_reviewer
workflow = investment_intent_to_paper_trade
environment = demo
account = brokerage.demo_ops
policy_version = v1.1.demo.investment
budget_id = v1.1.s6.demo
```

Allowed capabilities:

```text
trading_portfolio.read
market_event.read
trading_order.recommend
trading_order.propose
trading_order.place        paper-only, demo environment only
```

Trading scope:

```text
asset_classes = equity, etf
market = US
venues = NYSE, NASDAQ
sector = Information Technology
sides = buy
order_types = market, limit
account = brokerage.demo_ops
restricted_instruments = option, future, leveraged_etf, inverse_etf, manual_denylist
max_notional_per_order_usd = 2500
max_notional_per_day_usd = 25000
max_notional_per_month_usd = 100000
same_day_round_trip = deny
min_holding_period_days = 1
paper_place_only = true
live_place = deny
```

Model scope:

```text
model_provider = recorded_fixture or local_openai_compatible_llama_cpp
model_allowlist = unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL
model_endpoint = http://127.0.0.1:8080/v1 in live-LLM lane
model_mode = recorded for simple/replay, live for real-LLM smoke
max_prompt_bytes = bounded fixture size
max_response_bytes = bounded fixture size
max_retries = 0 for replay, 1 for first-run demo
temperature = 0
top_p = fixed
max_output_tokens = small CI-safe cap
token_budget = fixed per run
```

Adapter scope:

```text
adapter_id = paper_broker_demo
allowed_reads = portfolio_snapshot, quote_snapshot, market_event_fixture
allowed_writes = paper_order_fixture only after allowed ticket
live_network = deny
broker_credentials = none
```

## Fixtures

The integration fixture set should include:

- thesis input:

  ```text
  I want to invest USD 2,000 in AI infrastructure, but avoid single-name
  concentration and keep it to US-listed ETFs or large-cap equities.
  ```
- oversized thesis variant with the same text and `target_notional = USD 25,000`
- restricted-instrument variant that requests or injects `SOXL` or `BULZ`
- account fixture equivalent to the V1.1 cash-rich demo account
- oversized account or policy fixture whose effective max paper-trade amount
  is below USD 25,000
- quote fixture for every eligible basket line
- paper fill fixture for the allowed ticket
- model response fixture that turns the thesis into a structured investment
  rationale and recommended basket intent
- adapter response fixture for portfolio, market-event, quote, and paper-fill
  calls
- replay capsule containing captured model and adapter outputs

Existing V1.1 schema fixtures under `src/tickoni/schema/` should be reused
where possible:

- `thesis.zig` for input and normalized investor intent
- `catalog.zig` for eligible and restricted instruments
- `basket.zig` for deterministic basket construction and rejected candidates
- `portfolio.zig` for demo accounts and affordability checks

Chosen fixture values:

- The allowed basket uses the currently supported AI infrastructure catalog:
  `NVDA`, `AMD`, `AVGO`, `MSFT`, `AMZN`, `BOTZ`, and `SOXX`.
- The default allowed ticket is a buy `market` order with `day`
  time-in-force. This matches the current V1.1 paper-trade scope and common
  retail trading-app behavior for simple stock and ETF orders.
- The additional allowed ticket is a marketable buy `limit` order, because
  V1.1 explicitly supports limit orders and limit orders must carry a limit
  price.
- The negative order-type fixture is a buy `limit` order with missing limit
  prices. It must fail before paper execution.
- The oversized USD 25,000 scenario uses a policy binding max of USD 2,500
  even though the demo account can afford more. This proves the max paper-trade
  amount is the minimum of account and policy controls.
- The restricted-instrument scenario uses a FAANG-style request plus SpaceX:
  `META`, `AAPL`, `AMZN`, `NFLX`, `GOOGL`, and `SPACEX`. `AMZN` is recognized
  by the current catalog; the other FAANG names are outside the V1.1 catalog
  until explicitly added; `SPACEX` is denied as a non-public/private-company
  manual denylist instrument.

Suggested fixture directory:

```text
src/tickoni/test/fixtures/investment/
```

Suggested fixture files:

- `thesis_allowed_2000.json`: product/test-owned plain-English AI
  infrastructure thesis and target notional.
- `thesis_oversized_25000.json`: product/test-owned oversized variant.
- `thesis_restricted_instrument.json`: product/test-owned explicit
  restricted-instrument request.
- `policy_investment.json`: policy/test-owned V1.1 paper-trade
  capability envelope and limits.
- `account_ops.json`: product/test-owned cash, buying power, limits,
  holdings, and open orders.
- `quotes.json`: adapter/test-owned quote snapshot used to build
  ticket line items.
- `market_events.json`: adapter/test-owned market-event fixture for
  the agent context.
- `model_request.json`: model/test-owned exact prompt sent through
  `tkmodl`.
- `model_response_gemma4.json`: model/test-owned captured real-LLM
  response and metadata.
- `ticket_allowed_2000.json`: product/test-owned expected ticket for the
  allowed paper trade.
- `ticket_oversized_25000_blocked.json`: product/test-owned expected blocked
  ticket and max amount evidence.
- `ticket_restricted_instrument_blocked.json`: product/test-owned expected
  restricted-instrument blocked ticket.
- `paper_execution_allowed_2000.json`: adapter/test-owned paper fill result
  for the allowed ticket.
- `audit_allowed_2000.jsonl`: audit/test-owned material audit records for the
  allowed flow.
- `audit_oversized_25000.jsonl`: audit/test-owned audit records for the
  oversized blocked flow.
- `audit_restricted_instrument.jsonl`: audit/test-owned audit records for the
  restricted flow.
- `replay_capsule.json`: replay/test-owned captured hashes and
  substitutions for replay.

Ticket fixture files should store real ticket information, not prose:

- ticket id
- basket id
- thesis id
- account id
- side
- order type
- time in force
- target notional
- estimated cost
- currency
- line items with ticker, asset class, venue, side, quantity, price,
  line notional, allocation weight, and rationale hash
- affordability result
- cash available
- buying power
- remaining daily and monthly notional
- max affordable amount
- effective max paper-trade amount
- policy outcome
- blocked reasons, when present
- proposal hash
- approval state
- evidence hashes
- model request and response hashes
- adapter request and response hashes

## Output Contract

The demo and integration run should emit a stable machine-readable summary,
with a polished terminal rendering allowed as a separate view.

Required summary sections:

- `thesis_summary`
- `basket`
- `rejected_candidates`
- `trade_ticket`
- `affordability_check`
- `paper_execution_summary` for allowed tickets
- `blocked_summary` for denied tickets
- `evidence`
- `audit`
- `replay`

Required evidence fields:

- synthetic run id or case id
- thesis input hash
- normalized intent hash
- basket id
- ticket id
- proposal hash
- policy version
- capability envelope id
- account id
- model request hash and response hash
- adapter request and response hashes
- quote fixture id
- paper execution fixture id when present
- affordability outcome
- max affordable amount
- effective max paper-trade amount after account and policy limits
- rejected instrument reasons
- audit record hashes
- replay capsule id

## Positive Tests

### S6-P1: USD 2,000 AI Infrastructure Paper Trade Is Allowed

Input:

- account `brokerage.demo_ops`
- target notional `USD 2,000`
- AI infrastructure thesis
- allowed asset classes `equity`, `etf`
- US market and NYSE/NASDAQ venues

Expected path:

```text
tkings -> tknorm -> tkdedu -> tkcase -> tkpoly -> tkaudt
tkcase -> tkdisp -> tkagnt -> tkmodl
tkagnt -> tktool -> tkadpt.paper_trading
tkpoly/tkmodl/tktool/tkadpt/tkagnt -> tkaudt
```

Assertions:

- thesis normalization succeeds
- model request goes through `tkmodl`
- model output is captured and hash-addressed
- portfolio and quote reads go through `tktool` and `tkadpt`
- basket contains at least four eligible AI infrastructure instruments
- restricted instruments do not appear in the basket
- ticket estimated cost is within the USD 2,000 target tolerance
- affordability outcome is `allow`
- `trading_order.recommend` and `trading_order.propose` are allowed
- paper-only `trading_order.place` is allowed for the validated ticket
- paper execution summary includes paper order id, filled lines, fill prices,
  resulting cash, and resulting holdings snapshot
- audit includes model, adapter, proposal, policy, destination, limit, paper
  execution, and replay-ready evidence records
- replay matches without model or adapter calls

What it shows:

- An exec can watch one plain-English thesis become a basket, ticket,
  affordability check, and paper trade.
- Tickoni is an AI harness: the LLM participates through `tkmodl`, but the
  financial action remains policy-checked, audited, and replayable.

### S6-P2: Restricted Candidates Are Rejected Before Ticket Construction

Input:

- same USD 2,000 AI infrastructure thesis
- catalog includes restricted AI infrastructure instruments such as `SOXL` and
  `BULZ`

Assertions:

- restricted catalog entries are emitted under `rejected_candidates`
- each restricted candidate has a stable reason such as `leveraged_etf`,
  `inverse_etf`, or `manual_denylist`
- no restricted ticker appears in basket line items
- no trade ticket line is created for a restricted ticker
- audit includes rejected-candidate evidence with catalog schema version

What it shows:

- Restricted instruments are not merely hidden from the UI. They are denied in
  the financial path and preserved as evidence.

### S6-P3: Replay Uses Captured Model And Adapter Outputs

Input:

- replay capsule from `S6-P1`

Assertions:

- `tkrepl` substitutes captured model response by hash
- `tkrepl` substitutes captured adapter portfolio, quote, and paper-fill
  responses by hash
- no live `tkmodl` provider call occurs
- no live `tkadpt` external call occurs
- no paper fill is emitted a second time
- normalized intent hash, basket id, ticket id, proposal hash, policy decision,
  and audit chain all match

What it shows:

- The demo is not a one-off presentation. It is reproducible without live
  model, market, broker, trading, payment, or execution effects.

### S6-P4: Real Gemma LLM Smoke Produces Capturable Ticket Evidence

Input:

- same USD 2,000 AI infrastructure thesis
- local `llama.cpp` OpenAI-compatible server serving
  `unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL`
- same paper trading fixtures used by the simple integration lane

Assertions:

- `tkmodl` performs the model call through the configured local endpoint
- agent and test code never call the model endpoint directly
- model id, endpoint identity, request hash, response hash, token usage,
  latency, and sampling settings are captured
- model output is parsed into the same structured thesis summary or basket
  recommendation contract as the recorded fixture lane
- any model-suggested out-of-scope instrument is preserved as rejected evidence
  and cannot enter the ticket
- allowed ticket evidence is written to `ticket_allowed_2000.json`
- replay of the captured run succeeds with no live model call

What it shows:

- The demo is genuinely an AI harness, not only a deterministic basket builder.
- The real model participates, but the financial result remains bounded by
  Tickoni's policy, adapter, audit, and replay boundaries.

## Negative Tests

These tests are expected to fail closed at the indicated boundary. A passing
test means Tickoni denied the unsafe flow and emitted audit-ready evidence.

### S6-N1: USD 25,000 Oversized Trade Is Blocked With Max Affordable Amount

Input:

- same AI infrastructure thesis
- target notional `USD 25,000`
- same demo account

Expected result:

- basket construction may succeed
- ticket preview may be created as blocked
- `trading_order.recommend` may be allowed
- `trading_order.propose` returns a blocked or non-placeable ticket
- paper `trading_order.place` is denied

Assertions:

- affordability outcome is not `allow`
- `max_affordable_amount` is present for the account check
- effective max paper-trade amount is present and equals the minimum binding
  account or policy limit from the fixture
- blocked reasons include the exact failed dimension, for example
  `per_order_notional`, `buying_power`, `daily_notional`, or
  `monthly_notional`
- no paper order id is created
- no adapter paper-fill call is made
- audit includes affordability, limit-check, denial, and blocked-ticket
  evidence
- replay reproduces the same blocked reason, max affordable amount, and
  effective max paper-trade amount

What it shows:

- Tickoni can turn the same thesis into a disciplined no, with a useful maximum
  affordable amount instead of a vague rejection.

### S6-N2: Explicit Restricted Instrument Request Is Rejected

Input:

- user requests a restricted instrument such as `SOXL` or `BULZ`
- target notional `USD 2,000`

Expected result:

- model may mention the requested ticker as rejected evidence
- basket excludes the ticker
- ticket creation for that ticker is denied
- paper placement is denied

Assertions:

- failed scope dimension is `restricted_instrument` or `asset_class`
- rejected reason identifies the restriction type
- no quote or paper-fill adapter call is made for the restricted instrument
- audit contains denial evidence and catalog version
- replay reproduces the denial without model or adapter calls

What it shows:

- The agent cannot smuggle a restricted ticker through a recommendation or
  model-native tool call.

### S6-N3: Direct Paper Placement Bypassing Ticket Validation Fails

Input:

- a `trading_order.place` request with no validated ticket id or proposal hash

Expected result:

- `tkpoly` denies before `tkadpt` paper placement

Assertions:

- failed scope dimension is `missing_validated_ticket`
- no adapter paper-fill call occurs
- audit includes a denial record with the attempted capability envelope

What it shows:

- Paper trading still respects Tickoni's proposal-first control model.

### S6-N4: Live Trading Capability Is Denied

Input:

- same allowed USD 2,000 ticket
- environment or capability asks for live `trading_order.place`

Expected result:

- `tkpoly` denies live placement
- `tkexec` remains disabled
- no broker adapter credentials are required or used

Assertions:

- failed scope dimension is `environment` or `execution_mode`
- paper-only policy is visible in the audit evidence
- no live network call occurs

What it shows:

- V1.1 proves paper execution only and does not accidentally grant future
  broker sandbox or live execution authority.

### S6-N5: Model Attempts An Out-Of-Scope Tool Call

Input:

- model fixture returns a tool call for an unsupported action, for example
  `trading_order.place_live`, `trading_order.cancel`, or an options order

Expected result:

- `tktool` normalizes the request into a finance-native envelope
- `tkpoly` denies it before `tkadpt`

Assertions:

- raw model tool call is captured by hash
- normalized denied envelope is captured
- failed capability or failed scope dimension is explicit
- no adapter call is made for the denied action
- audit links the model output to the denial

What it shows:

- The LLM can participate without becoming the trust boundary.

### S6-N6: Malformed Thesis Fails Before Model Invocation

Input examples:

- empty user text
- missing target amount
- unsupported asset class only, such as options or crypto

Expected result:

- `tknorm` fails closed
- no `tkdisp`, `tkagnt`, `tkmodl`, `tktool`, or `tkadpt` work item is created

Assertions:

- error is user-readable
- audit includes thesis denial evidence
- no model request hash exists
- no basket, ticket, proposal, or paper execution exists

What it shows:

- External input validation precedes agent and model work.

### S6-N7: Replay Divergence Is Detected

Input:

- valid replay capsule from `S6-P1`
- intentionally modified quote fixture, model response hash, catalog version,
  or policy version

Expected result:

- replay reports mismatch
- no external effects occur during mismatch detection

Assertions:

- first divergent record is identified
- divergence type is specific, such as `model_response_hash`,
  `adapter_response_hash`, `catalog_schema_version`, `policy_version`,
  `basket_id`, or `audit_chain`
- audit/replay result is exported for inspection

What it shows:

- Tickoni can prove when a polished demo no longer matches its captured
  evidence.

## Demo Checklist

The exec-facing V1.1.S6 demo should show:

1. The user enters one AI infrastructure thesis.
2. Tickoni shows the model-assisted thesis summary.
3. Tickoni shows the basket with allocation dollars and rationale.
4. Tickoni shows rejected restricted instruments and exact reasons.
5. Tickoni shows the trade ticket.
6. Tickoni shows cash, buying power, remaining limits, max affordable amount,
   and effective max paper-trade amount.
7. Tickoni paper-places the allowed USD 2,000 ticket.
8. Tickoni runs the USD 25,000 variant and blocks it with the max affordable
   amount and effective max paper-trade amount.
9. Tickoni exports audit-ready ticket evidence for allowed, oversized, and
   restricted-instrument flows.
10. Tickoni replays the run with model, broker, market, trading, payment, and
    execution effects disabled.

## Implementation Notes

- Prefer one canonical fixture directory for V1.1 integration data so demo,
  tests, and replay consume the same inputs.
- Keep the simple integration lane deterministic in CI by using captured model
  output. The real-LLM smoke lane should call the local Gemma model through
  `tkmodl`, capture the response, and immediately prove replay can substitute
  that response without invoking the model again.
- Cache the GGUF model artifact in CI when possible. If model download or
  inference exceeds the public-runner budget, keep the simple fixture lane as
  the merge gate and run the real-LLM lane as a scheduled or manually triggered
  proof until runtime is optimized.
- Do not let test code call the broker or quote fixtures directly. All
  portfolio, market-event, quote, proposal, and paper-fill reads go through
  `tktool` and `tkadpt`.
- Do not duplicate policy checks in the demo renderer. The renderer should show
  `tkpoly` outcomes and evidence, not recompute them.
- Keep negative-flow outputs polished. Blocked flows are first-class product
  proof, not test leftovers.

## Completion Criteria

V1.1.S6 is complete when:

- one local command or test fixture produces the full AI infrastructure demo
- the simple integration lane validates recorded model output and real ticket
  fixture files
- the real-LLM smoke lane runs
  `unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL` through `tkmodl` on a
  GitHub public-runner-sized budget or as a documented opt-in job
- positive and negative integration scenarios above pass
- allowed, oversized, and restricted-instrument flows emit audit-ready evidence
- replay succeeds without live model or adapter effects
- at least one intentional divergence test proves replay detects drift
- `just test-integration-tk` or its delegated V1.1 command runs these scenarios
  from the repository root
