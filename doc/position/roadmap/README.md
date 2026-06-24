# Roadmap — Tickoni Consumer Finance V1

Each increment has one file that combines its roadmap description and WBS tasks.
Use this folder for per-increment planning, tracking, and reference.

## Increments

| Increment | Description | Status |
| --- | --- | --- |
| [V1.0](v1.0.md) | Runtime Proof | Done |
| [V1.1](v1.1.md) | Investment Intent To Paper Trade | Accepted baseline |
| [V1.11](v1.11.md) | Investment Demo Release Closure | Next |
| [V1.2](v1.2.md) | Pay And Move Money Guard | Planned |
| [V1.3](v1.3.md) | Portfolio And Cash Impact Loop | Planned |
| [V1.12](v1.12.md) | Runtime Hooks | Planned |
| [V1.4](v1.4.md) | Social Thesis And Money Feed | Later |
| [V1.5](v1.5.md) | Crypto And Stablecoin Guard | Later |
| [V1.6](v1.6.md) | Guarded Broker, Payment, And Crypto Sandbox | Later |
| [V1.7](v1.7.md) | Trust Layer | Later |
| [V1.8](v1.8.md) | Capability Control Surface | Later |
| [V1.9](v1.9.md) | Crypto Thesis To Guarded Spot Trade | Later |
| [V1.13](v1.13.md) | Non-Investment Operations Workflows | Later |

Platform backlog: [platform/p1-p8.md](platform/p1-p8.md).

## How Each File Is Organized

Every story file has two sections:

**Roadmap section** — product intent, user story, what the user can do,
what the user sees, capability depth, success demo, non-goals.

**WBS section** — sub-stories (S1, S2, ...), each with numbered tasks
and acceptance criteria.

## Status Legend

- **Done** — completed, no further work.
- **Accepted baseline** — engineering demo exists, not externally release-ready.
- **Next** — the immediate focus.
- **Planned** — scoped, not started.
- **Later** — on the backlog, out of scope for near-term V1.

## Cross-References

- Product bet, target user, and priority stack: [`positioning.md`](../positioning.md).
- V1 completion criteria and non-goals: [`positioning.md`](../positioning.md).
- V1 capability set, denied-by-default list, and capability depth by increment: [`capabilities.md`](../capabilities.md).
- Product language conventions: [`doc/contribution/tickoni.md`](../../contribution/tickoni.md).
- Platform backlog (P1–P8): [`platform/p1-p8.md`](platform/p1-p8.md).

## Increment Gate Checklist

Every increment must answer before closing:

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

## Increment Evidence Work Items

Every increment should include these work items unless the increment explicitly
does not touch that boundary. For the full story template that combines these items
with the P8 build, quality, security, and release requirements, see
[`doc/position/templates/story_template.md`](../templates/story_template.md).

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
