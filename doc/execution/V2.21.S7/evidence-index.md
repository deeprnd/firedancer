# V2.21.S7 Evidence Index

This document is the canonical index for the V2.21 retail runtime trust/evidence packet.

It tells a reviewer exactly where each required artifact comes from, which command generates it, and why it matters.

## Closure artifacts

| Artifact | Path | Source / generation command | Why it matters |
| --- | --- | --- | --- |
| Support matrix / retail runtime guide | `doc/execution/retail-runtime-support.md` | committed documentation | Canonical user-facing trust surface |
| Tier definitions | `doc/knowledge/platform-tiers.md` | committed documentation | Source of truth for runtime tiers and degraded guarantees |
| Version/doctor design record | `doc/knowledge/version-identity.md` | committed documentation | Contract for version identity and preflight output |
| Version sample | `doc/execution/V2.21.S7/version-sample.txt` | `./zig-out/bin/tickoni --version > ...` | Proves product binary exposes version/provenance fields |
| Doctor plain sample | `doc/execution/V2.21.S7/doctor-plain-sample.txt` | `./zig-out/bin/tickoni doctor --plain > ...` | Proves human-readable host/tier report surface |
| Doctor JSON sample | `doc/execution/V2.21.S7/doctor-json-sample.json` | `./zig-out/bin/tickoni doctor --json > ...` | Proves machine-readable preflight/report surface |
| Successful demo sample | `doc/execution/V2.21.S7/demo-plain-sample.txt` | `./zig-out/bin/tickoni-supervisor demo investment --plain --manifest ... > ...` | Shows deterministic no-live-effect proof output |
| Successful demo JSON sample | `doc/execution/V2.21.S7/demo-json-sample.json` | `./zig-out/bin/tickoni-supervisor demo investment --json --manifest ... > ...` | Structured conformance result for review and automation |
| Blocked-flow sample | `doc/execution/V2.21.S7/blocked-flow-sample.txt` | fail-closed demo invocation captured to file | Proves unsupported/stale/tampered flow closes safely |
| Conformance result summary | `doc/execution/V2.21.S7/conformance-result-summary.json` | distilled from successful JSON demo/conformance output | Shows comparison verdict and scenario set |
| Audit JSONL sample path | `src/tickoni/test/fixtures/investment/scenarios/fixture_audit_trace_paper_investment_allowed.jsonl` | committed fixture path referenced by demo substitution backend | Shows audit artifact location used by deterministic proof |
| Replay capsule sample path | `src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_paper_investment_allowed.json` | committed fixture path referenced by demo substitution backend | Shows replay artifact location used by deterministic proof |
| Telemetry audit | `doc/execution/V2.21.S7/telemetry-audit.md` | committed documentation audit | Proves privacy/telemetry defaults are explicit |
| Security audit | `doc/execution/V2.21.S7/security-audit.md` | committed documentation audit | Proves no-sudo/no-live-effect/manual-verification claims |
| Quality gate | `doc/execution/V2.21.S7/quality-gate.md` | committed documentation gate | Frozen closure contract for the story |

## Reviewer flow

1. Read `doc/execution/retail-runtime-support.md`.
2. Confirm the tier model in `doc/knowledge/platform-tiers.md`.
3. Inspect `version-sample.txt` and `doctor-*.txt/json`.
4. Inspect `demo-plain-sample.txt`, `blocked-flow-sample.txt`, and `conformance-result-summary.json`.
5. Follow the audit/replay fixture paths for the deterministic evidence payloads.
6. Read `telemetry-audit.md`, `security-audit.md`, and `quality-gate.md`.

## Notes

- CaseOps display is intentionally deferred from V2.21 and is therefore documented, not claimed as a shipped evidence artifact here.
- Windows retail runtime artifacts belong to V2.22, not this evidence packet.
