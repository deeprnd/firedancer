# T10 Security Audit — version-preflight branch

**Date:** 2026-07-22
**Scope:** `version-preflight` branch (PR #809)
**Audited modules:** `preflight.zig`, `manifest.zig`, `wire.zig`, `hash.zig`, `jsonl.zig`, `capsule.zig`, `audit_sink.zig`, `version.zig`, `main.zig`, `doctor/output.zig`
**Verdict:** SHIP-READY

## Findings

| # | Severity | Location | Description | Resolution |
|---|----------|----------|-------------|------------|
| 1 | **Critical** | `version.zig` | `semverFmt()` returned pointer to local stack buffer (UB) | Fixed: static string return, explicit `init(gpa)`/`deinit(gpa)` pair |

All remaining items are documented scaffold/T7 scope, not regression bugs:

- `tierNameFromIsolation()` — unused helper (info-level, no functional impact)
- `manifest.zig:59` — tier validation TODO (acknowledged as T7 scope)

## Test Coverage

### Preflight module (9 tests)
- `isAllPassed` true/false
- Runtime tier pass + fail
- Version check fail
- Isolation tier mismatch fail
- `no_live_effect=false` fail
- `formatFailure` includes check details
- Fixture missing detection

### Wire format sync
- Compile-time check ensures schema/wire `Payload` variants stay synchronized (catches drift at build time)

## Code Quality

### No code smell in:

| Module | Assessment |
|--------|------------|
| `hash.zig` | SipHash chain logic is clean, single responsibility |
| `wire.zig` | `toWireEvent`/`fromWireEvent` symmetric, `parseEnumByValue` handles unknowns |
| `jsonl.zig` | Header fields match `Header` struct, `writePayloadJson` covers all 13 variants |
| `capsule.zig` | ReplayCapsuleWire metadata fields nullable for backward compat |
| `audit_sink.zig` | `buildPolicyDecisionEvent` properly fills metadata |

### Buffer safety
- `preflight.zig` tier list: 256-byte buf with `tier_written + N <= 256` guards
- `preflight.zig` missing fixtures: 512-byte buf with `mw + fixture.len <= 512` guards
- `audit_sink.zig` memcpy: callers control source length, targets are 64-byte fixed arrays — safe per contract

### Memory management
- `VersionInfo` now has `init(gpa)`/`deinit(gpa)` pair for the allocated semver string
- Preflight result uses `allocPrint` freed in `deinit(preflight_result)`
- No leaks detected in test paths
- `Manifest.deinit()` properly frees heap-allocated slice elements (no literal pointer derefs)
- `loadManifest` returns `*Manifest` via `gpa.create()`, caller owns both `deinit()` and `destroy()`

## Architecture Alignment

### Structural coherence

| Component | Metadata Coverage |
|-----------|-------------------|
| `audit.zig` Header | 7 metadata fields |
| `wire.zig` extern Header | Mirrors `audit.zig` exactly |
| `hash.zig` SipHash chain | Includes all metadata fields |
| `jsonl.zig` | Serializes all metadata fields |
| `capsule.zig` replay path | Carries metadata with null defaults |
| `audit_sink.zig` `buildPolicyDecisionEvent` | Accepts metadata parameters |

### Modular design preserved
- `demo_manifest`, `demo_semver`, `demo_preflight` as separate build modules
- Import chain: `preflight.zig` → `demo_manifest`, `demo_semver`
- No circular dependencies in build graph

## Summary

One critical UB bug was found and fixed. The remaining warnings are documented scaffold items (T7 scope). All tests pass, format checks pass, structure is coherent, memory is managed correctly. The branch is ready for merge.
