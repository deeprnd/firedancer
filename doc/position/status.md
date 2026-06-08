# Tickoni Current Status

## Snapshot

| Field | Value |
| --- | --- |
| Status date | 2026-06-05 |
| Timezone | Asia/Jerusalem |
| Commit SHA | `7d20c1c27cc5425e52e2e0f6c490582c3d06277a` |
| Verification run | `zig build test` passed on 2026-06-05 |
| Worktree before this status file | clean |
| Current product phase | Phase 0 complete; Phase 1 planned next |

This status is based on the current repository documents under
[`doc/position/`](.) and a fresh local `zig build test` run.

## Roadmap Status

### Completed

| Roadmap item | Status | Evidence |
| --- | --- | --- |
| Completed Foundation Story: Tickoni Runtime Cutover | Done | [`roadmap.md`](roadmap.md) marks it completed on 2026-06-01 |
| Agave-free canonical runtime identity | Done | Runtime cutover delivered `tickoni`, `TICKONI_CONFIG_TOML`, release tag prefix, and container workspace path |
| Phase 0 technical spike | Done | [`wbs.md`](wbs.md) marks E0 complete; [`tile-plan.md`](tile-plan.md) marks Phase 0 topology complete |

### Current Position

Phase 0 is complete as an in-process spike. The current implemented topology is:

```text
tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
tkrepl
tkmetr
tkdiag
```

The spike proves:

1. bounded in-process queues
2. stable synthetic payment event hashes
3. normalization and malformed-event rejection
4. duplicate detection by idempotency key and content hash
5. allow, deny, malformed-drop, and duplicate-drop policy decisions
6. append-only audit ordering and hash chaining
7. deterministic replay comparison with external effects disabled
8. metric snapshots
9. crash, sandbox, audit, and replay diagnostics

### Planned Next

The next roadmap phase is Phase 1: Control-Plane Harness. It should keep stub
payment and trading systems and prove the governed control plane before real
external ingestion.

## WBS Status

### Done

| WBS item | Status | Notes |
| --- | --- | --- |
| E0: Runtime Spike | Done | Complete as an in-process Phase 0 spike |
| E0.S1: Tickoni supervisor starts product tiles | Done | Supervisor starts, stops, monitors, and marks crashed tile state |
| E0.S2: Synthetic payment pipeline proves runtime behavior | Done | Synthetic stream exercises ingest, normalize, dedupe, policy, audit, replay, metrics, and diagnostics |

### Not Started / Planned

| WBS item | Phase | Status |
| --- | --- | --- |
| E1: Durable audit and replay foundation | Phase 1 | Planned next |
| E2: Telemetry and diagnostics export | Phase 1 | Planned next |
| E3: Finance-native capability envelopes and policy decisions | Phase 1 | Planned next |
| E4: Model gateway and inference governance | Phase 1 | Planned next |
| E5: Agent, financial tool broker, and stub financial adapters | Phase 1 | Planned next |
| E6: Deterministic cases and evidence | Phase 2 | Future |
| E7: External ingestion API and CaseOps board | Phase 3 | Future |
| E8: Fintech workflow pack | Phase 4 | Future |
| E9: Build, quality, security, and release hygiene | All phases | Ongoing |

## Phase Gate Status

| Phase | Gate | Status |
| --- | --- | --- |
| Phase 0 | Technical spike | Complete |
| Phase 1 | Control-plane harness | Not started |
| Phase 2 | Deterministic case runtime | Not started |
| Phase 3 | External ingestion and CaseOps | Not started |
| Phase 4 | Workflow pack | Not started |

## Current Technical State

### Implemented

- Zig-native Tickoni scaffold under `src/app/tickoni/` and `src/tickoni/`
- `tickoni-supervisor` build path through `build.zig`
- Phase 0 in-process payment pipeline
- Static Phase 0 topology
- Supervisor wiring and tests
- Narrow C ABI declarations for selected queue and sandbox primitives

### Not Implemented Yet

- shared-memory queue backing for the Tickoni tile links
- sandboxed child-process tile execution
- durable audit storage
- production telemetry export
- full finance-native capability envelope implementation
- model gateway integration
- financial tool broker
- stub payment and trading adapters
- deterministic case routing
- content-addressed evidence storage
- replay capsule format
- external financial event ingestion API
- CaseOps API and board
- privileged action executor

## Open Product / Architecture Debt

| Debt | Status |
| --- | --- |
| Heap-backed queues in Phase 0 spike | Replace before leaving the spike topology |
| In-process thread tile mapping | Replace with process/sandbox mapping before production-like runs |
| Temporary `firedancer -> tickoni` compatibility behavior | Retain until downstream migration and deprecation window complete |
| `FIREDANCER_CONFIG_TOML` fallback | Retain until deprecation window complete |
| Validator source still present | Keep until Tickoni product topology is canonical and synchronization strategy is settled |

## Next Product Focus

The immediate product focus is Phase 1:

1. durable audit export and hash-chain verification
2. telemetry and diagnostics export
3. finance-native capability envelope
4. allow, deny, and require-approval policy decisions
5. governed `tkmodl` model path with deterministic stubs or local/dev LLM server
6. `tktool` financial broker path
7. stub payment adapter
8. stub trading adapter
9. replay with model, payment, trading, and execution side effects disabled
