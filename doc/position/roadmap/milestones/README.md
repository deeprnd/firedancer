# Milestones — Tickoni Consumer Finance V1

The consumer-finance roadmap is grouped into higher-level milestones.
These files provide the milestone view only; the increment files under
[`stories/README.md`](../stories/README.md) remain the source of truth for
version order, product narrative, priority tradeoffs, and increment detail.

Use this folder when the question is:

```text
Which larger product milestones do the roadmap epics roll up into?
```

An "epic" here means a named roadmap increment such as `V1.1` or a
carried-forward platform backlog item such as `P1`.

## Milestones

| Milestone | Included roadmap epics | Product result |
| --- | --- | --- |
| [M1](m1.md): Safe Money Decisions | `V1.1`, `V1.11`, `V1.3`, supported by `P4`, `P8` | Investment intent becomes a paper trade; portfolio and cash impact is visible |
| [M2](m2.md): Governed Harness Runtime | `V1.14`, `V1.15`, `V1.16`, `V1.17`, supported by `P8` | Tile processes are real, agent runs are bounded, tool dispatch is normalized, model limits are enforced |
| [M3](m3.md): Proof And Trust | `V1.12`, `V1.18`, `V1.7`, `V1.8`, supported by `P4`, `P8` | Observable checkpoints, tamper-evident capsules, and partner-inspectable trust and capability surfaces |
| [M4](m4.md): Social Thesis And Money Feed | `V1.4`, supported by `P5`, `P8` | Users can copy thesis and money-decision templates into their own account limits |
| [M5](m5.md): Approved Payment And Broker Sandbox | `V1.2`, `V1.6`, `V1.13`, supported by `P5`, `P6`, `P8` | Payment proposals, approved sandbox execution, and operations workflows governed by the same harness |
| [M6](m6.md): Crypto Guard And Spot Trade | `V1.5`, `V1.9`, supported by `P5`, `P6`, `P8` | Crypto and stablecoin guardrails with trading authority separate from transfer authority |

## Cross-References

- Product bet, target user, and priority stack: [`positioning.md`](../positioning.md).
- V1 completion criteria and non-goals: [`positioning.md`](../positioning.md).
- V1 capability set, denied-by-default list, and capability depth by increment: [`capabilities.md`](../capabilities.md).
- Product language conventions: [`doc/contribution/tickoni.md`](../../contribution/tickoni.md).
