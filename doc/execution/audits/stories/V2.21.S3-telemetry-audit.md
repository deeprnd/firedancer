# T11 Telemetry Audit — version-preflight branch

**Date:** 2026-07-22
**Scope:** `version-preflight` branch (PR #809)
**Audited modules:** `audit.zig` (schema), `wire.zig` (codec), `hash.zig` (SipHash), `main.zig` (CLI telemetry output), `preflight.zig` (demo preflight), `doctor/output.zig` (environment checks)
**Verdict:** SHIP-READY

## Telemetry Checkpoint Schema

| Field | Type | Coverage |
|-------|------|----------|
| `metric_set_hash` | u64 | ✅ schema, wire, hash |
| `source_offset_watermark` | u64 | ✅ schema, wire, hash |

`TelemetryCheckpointPayload` (record type 10) is fully covered across all four audit representations:
- **Schema** (`audit.zig:130-133`) — canonical struct definition
- **Wire** (`wire.zig:108-111`) — extern struct mirrored
- **Hash** (`hash.zig:122-126`) — SipHash chain includes both fields
- **Wire sync** — compile-time check in `wire.zig:414-437` validates schema/wire variant alignment

## CLI Telemetry Output

### `--version` command (main.zig:39-52)

Outputs 10 fields:
- Tickoni semver (from `build_options`)
- Build ID
- Git SHA (truncated to 12 chars)
- OS + architecture
- Runtime tier
- Isolation tier
- Policy schema version
- Replay schema version
- Demo manifest version
- Compiler string

**Data quality:**
- ✅ Semver computed from `build_options`, not `info.semver` (avoids stack UB)
- ✅ Git SHA truncated to min(12, len) — safe for short SHAs
- ✅ OS/arch detected via `tier_detectOsString()`/`tier_detectArchString()`
- ✅ Runtime tier via `tierName(tier_detectTier())`
- ✅ Isolation tier via `isolationTierStr()` — deterministic mapping:
  - `linux_full` → `"full"`
  - `macos_retail`/`windows_retail` → `"retail"`
  - `unsupported` → `"degraded"`

### `start` command (main.zig:115-167)

Outputs pipeline metrics:
```
metrics: produced={d} audited={d} duplicates={d} denied={d} backpressure_waits={d} max_queue_depth={d} max_latency_hops={d}
diag: sandbox_failures={d} replay_checked={s} replay_match={s}
```

**Data quality:**
- ✅ All metrics from `state.snapshotMetrics()` and `state.snapshotDiag()`
- ✅ Replay status output as human-readable booleans
- ✅ Buffer: 256-byte fixed buf, format limits to ~180 chars — safe

### `start-process` command (main.zig:172-211)

Outputs per-tile process metrics:
```
metrics: produced={d} normalized={d} invalid={d} duplicates={d} allowed={d} denied={d} audited={d}
```

**Data quality:**
- ✅ Metrics from `snapshotProcessMetrics()`
- ✅ Poll loop bounded at 2000 iterations (10s max)
- ✅ Sleep interval 5ms — reasonable for progress monitoring

### `doctor` command (main.zig:76-81)

Outputs environment checks with optional `--json` format:
- OS version + arch
- Degraded dimensions (platform tier, isolation tier, runtime tier)
- Tiles excluded due to constraints

**Data quality:**
- ✅ Exit code 0 for pass/warn, 1 for fail
- ✅ 20-slot result array, bounded by `runAll()` return count
- ✅ Degradation dimensions output added per `platform-tiers.md`

### `demo` command (main.zig:234-276)

Preflight-gated demo execution:
```
preflight: passed
demo: completed
```

**Data quality:**
- ✅ Fail-closed: demo doesn't run if preflight fails
- ✅ Error messages include manifest path and error type
- ✅ `VersionInfo.init(gpa)` / `deinit(gpa)` pair — no leaks
- ✅ `deinitManifest(m, init.gpa)` — no leaks

## Telemetry Gap Analysis

| Area | Status | Notes |
|------|--------|-------|
| Schema coverage | ✅ Complete | All 14 record types defined |
| Wire sync | ✅ Compile-time check | Catches drift at build time |
| Hash coverage | ✅ Complete | All payloads hashed including telemetry checkpoint |
| JSONL serialization | ✅ Complete | All 14 payloads covered |
| Replay substitution | ✅ Present | `replay_substitution_id` in ModelCall + FinancialAdapterCall |
| CLI metrics output | ✅ Complete | Version, pipeline, process, doctor, demo |
| Telemetry checkpoint | ⚠️ Schema-only | `TelemetryCheckpointPayload` defined but no tile currently emits it |

**Note on telemetry checkpoint:** The schema wire for `TelemetryCheckpointPayload` is fully implemented, but no tile in the current pipeline (`cmdStart`/`cmdStartProcess`) emits telemetry checkpoint records. This is intentional — telemetry checkpoints are a future enhancement (part of the real-time monitoring roadmap). The schema exists to prevent drift when tiles start emitting them.

## Information Disclosure Assessment

| Output | Risk | Assessment |
|--------|------|------------|
| `--version` | Low | Shows semver, git SHA, OS, arch, compiler. No secrets, no tokens, no file paths. |
| Pipeline metrics | Low | Shows counts and diagnostics. No PII, no financial data, no policy decisions. |
| Doctor output | Low | Shows system info and degradation dimensions. No secrets. |
| Demo preflight errors | Low | Shows manifest path and check names. Safe for dev/test environments. |

## Memory Management

| Allocation | Free path | Leak check |
|------------|-----------|------------|
| `VersionInfo.semver` (gpa.dupe) | `deinit(gpa)` | ✅ |
| `PreflightResult.checks` (ArrayList) | `deinit(result, gpa)` | ✅ |
| `Manifest` fields (gpa.dupe/dupe slice) | `deinitManifest(m, gpa)` | ✅ |
| `Fixture path` buffers (allocPrint) | freed in `run()` after loop | ✅ |
| Preflight tier list buf (256-byte stack) | Stack-local | ✅ |
| Preflight missing fixtures buf (512-byte stack) | Stack-local | ✅ |

## Verdict

All telemetry instrumentation is complete and correct:
- Schema wire sync prevents field-level drift
- Hash chain covers all payloads including telemetry checkpoint
- CLI output is well-structured with bounded buffers
- No secrets or sensitive data in telemetry output
- Memory management is sound with explicit free paths
- Telemetry checkpoint schema exists for future tile integration

**SHIP-READY.**
