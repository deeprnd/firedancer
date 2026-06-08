# Tickoni Product Management

## Purpose

This directory separates product management decisions from architecture and tile
implementation details. Each document has one job, and the roadmap should stay
readable instead of becoming a backlog.

## Source Of Truth

| Document | Owns | Does not own |
| --- | --- | --- |
| [`positioning.md`](positioning.md) | Market position, differentiation, buyer framing, non-positioning | Delivery sequencing or implementation tasks |
| [`prd.md`](prd.md) | V1 product requirements, personas, success metrics, non-goals | Tile topology or sprint-level task lists |
| [`roadmap.md`](roadmap.md) | Phase narrative, long-term sequencing, strategic tradeoffs | Detailed stories and tasks |
| [`phase-plan.md`](phase-plan.md) | Phase gates, entry criteria, exit criteria, demo readiness | Individual engineering task ownership |
| [`wbs.md`](wbs.md) | Epics, stories, tasks, acceptance criteria | Market narrative or tile topology |
| [`tile-plan.md`](tile-plan.md) | Tile IDs, tile ownership, topology, validator-tile replacement decisions | Product backlog, PRD, phase gates |
| [`inference-governance.md`](inference-governance.md) | Model-provider, LLM-server, token-budget, and inference-control requirements | Tile map beyond `tkmodl` boundary ownership |
| [`capabilities.md`](capabilities.md) | Finance-native permission model, scopes, destination allowlists, and capability roadmap | OS sandbox permissions or implementation-specific tile APIs |

## Product Operating Model

### Planning Cadence

- Roadmap review: update when phase ordering or strategic scope changes.
- Phase gate review: update before starting or closing a phase.
- WBS grooming: update when stories split, merge, or change acceptance criteria.
- PRD review: update when the V1 buyer, user, requirement, or non-goal changes.

### Decision Rules

1. If the question is "why are we building this?", update `positioning.md` or `prd.md`.
2. If the question is "when does this happen?", update `roadmap.md` or `phase-plan.md`.
3. If the question is "what exact work remains?", update `wbs.md`.
4. If the question is "which tile owns this?", update `tile-plan.md`.
5. If the question is "which model path is allowed?", update `inference-governance.md`.
6. If the question is "which financial action is allowed?", update `capabilities.md`.

### Senior Product Constraints

- Keep V1 narrow enough to demonstrate trust, not breadth.
- Prove audit, permissions, telemetry, and replay before real financial APIs.
- Prefer deterministic stubs until the control-plane harness is measurable.
- Treat model integration as governed infrastructure, not a feature shortcut.
- Keep autonomous money movement and autonomous trading outside V1.

## Current V1 Narrative

V1 proves that Tickoni can run AI-assisted financial operations with strict
runtime control:

1. deterministic event processing
2. explicit capability checks
3. isolated model and tool access
4. durable audit and replay
5. operator review before sensitive action

Phase 1 is intentionally not "real API first." It is the control-plane harness:
audit, telemetry, permissions, model gateway, tool broker, and stub
payment/trading adapters running end to end.
