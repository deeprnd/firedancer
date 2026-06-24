# Roadmap — Tickoni Consumer Finance V1

Each increment has one file that combines its roadmap description and WBS tasks.
Use this folder for per-increment planning, tracking, and reference.

## Increments

| Increment | Description |
| --- | --- |
|| [V1.0](v1.0.md) | Runtime Proof |
|| [V1.1](v1.1.md) | Investment Intent To Paper Trade |
|| [V1.11](v1.11.md) | Investment Demo Release Closure |
|| [V1.2](v1.2.md) | Pay And Move Money Guard |
|| [V1.3](v1.3.md) | Portfolio And Cash Impact Loop |
|| [V1.12](v1.12.md) | Runtime Hooks |
|| [V1.4](v1.4.md) | Social Thesis And Money Feed |
|| [V1.5](v1.5.md) | Crypto And Stablecoin Guard |
|| [V1.6](v1.6.md) | Guarded Broker, Payment, And Crypto Sandbox |
|| [V1.7](v1.7.md) | Trust Layer |
|| [V1.8](v1.8.md) | Capability Control Surface |
|| [V1.9](v1.9.md) | Crypto Thesis To Guarded Spot Trade |
|| [V1.13](v1.13.md) | Non-Investment Operations Workflows |
|| [V1.14](v1.14.md) | Firedancer Process And Shared-Memory Topology |
|| [V1.15](v1.15.md) | Bounded Agent Run Governance |
|| [V1.16](v1.16.md) | Tool Broker And MCP-Compatible Dispatch |
|| [V1.17](v1.17.md) | Tkmodl Budget And Call-Limit Governance |
|| [V1.18](v1.18.md) | Replay Proof Bundle And Evidence Integrity |

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

- Product bet, target user, and priority stack: [`positioning.md`](../../positioning.md).
- V1 completion criteria and non-goals: [`positioning.md`](../../positioning.md).
- V1 capability set, denied-by-default list, and capability depth by increment: [`capabilities.md`](../../capabilities.md).
- Product language conventions: [`doc/contribution/tickoni.md`](../../../contribution/tickoni.md).

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

Every increment should include the story template that combines quality, security, and release requirements, see
[`doc/position/templates/story_template.md`](../../templates/story_template.md).