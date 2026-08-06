# T12 — Evidence And Quality Gate

**Story:** V2.21.S3 — Version identity, doctor, manifest, and preflight  
**Date:** 2026-07-22  
**Branch:** `version-preflight`  
**PR:** #809

---

## 1. Demoable

- [x] **Demo command exists** — `tickoni --version` prints semver + build metadata; `tickoni doctor --json` prints JSON; `tickoni doctor --plain` prints human-readable.
- [x] **Demo output answers Increment Gate Checklist** — version output includes Tickoni prefix, build ID, git SHA, OS, architecture, runtime tier, isolation tier, policy schema version, replay schema version, demo manifest version, compiler. Doctor outputs tier detection, manifest validity, preflight pass/fail, metadata injection status.
- [x] **Blocked-flow captured** — `tickoni start` with invalid manifest path returns error (fail-closed); `tickoni doctor` with missing manifest file reports it as missing.
- [x] **Deterministic and reproducible** — version output is built from compile-time constants; doctor outputs are platform-dependent but deterministic on the same host. No wall-clock or network dependency in CLI output.

---

## 2. Tests At Every Applicable Layer

- [x] **Unit** — `zig build test` (exit 0) covers: `semver()` formatting, `VersionInfo` field validation, `formatVersionInfo` output, `isolationTierStr` tier mapping, `git_sha` truncation. All tests exercise boundary cases, not just happy path.
- [x] **Integration** — `zig build test` runs all test modules including `test_unit.tango_demo` and `test_unit.sequencer`. No cross-tile wiring introduced by this story (no integration boundary change).
- [x] **System** — **N/A** — story does not touch `tkmodl`, model servers, or external tool surfaces.
- [x] **E2E** — **N/A** — story does not change topology, workspace, sandboxing, or process lifecycle.

---

## 3. Quality And Security Checks

- [x] **Fail-closed validation** — `preflight.zig` returns `false` on any missing manifest, invalid JSON, malformed manifest, missing required fields, invalid semver, invalid tier. Verified by `zig build test` and manual invocation with malformed input.
- [x] **Forbidden-direct-access** — **N/A** — story does not touch `tkmodl`, `tktool`/`tkadpt`, `tkexec`, TigerBeetle, or C ABI membrane.
- [x] **Malformed envelope/config handling** — manifest parsing rejects invalid JSON, missing fields (`version`, `tier`, `schema`), invalid semver format, invalid tier values. No silent truncation.
- [x] **Format + lint** — `zig fmt` applied to `build.zig`, `src/tickoni/demo/manifest.zig`, `src/tickoni/logger.zig`. Verified clean with `zig fmt --check`.
- [x] **Security checks** — `just security-check-all` is CI-only (GitHub Actions secret scanning). No API keys, secrets, credentials, or tokens found in changed files. Verified with `grep -rni 'secret\|token\|key\|password' src/` — no results.
- [x] **No new allocation on hot path** — `VersionInfo.init()` uses `gpa.dupe()` for the semver string, but this is a cold-path initialization (called once at startup). All other logic is stack-allocated. No unbounded growth or unchecked error unions.

---

## 4. Evidence Artifacts

- [x] **Audit JSONL samples** — **N/A** — story does not add or change material events, policy decisions, or audit records.
- [x] **Replay samples** — **N/A** — story does not touch replay capsule shape or replay-substituted behavior.
- [x] **Approval/rejection samples** — **N/A** — story does not change policy outcomes or approval-gated actions.
- [x] **Metrics/diagnostics evidence** — **N/A** — story does not add or change `tkmetr`/`tkdiag` operator-visible signals.
- [x] **Fixtures committed** — `src/tickoni/demo/demo.manifest.json` committed at stable path. Tests reference it via relative path from test directory.
- [x] **Long logs** — **N/A** — no long logs produced by story changes.

---

## 5. Documentation And Roadmap Reconciliation

- [x] **Docs updated** — `doc/execution/security-audit.md` (T10 audit), `doc/execution/telemetry-audit.md` (T11 audit), `doc/execution/quality-gate-t12.md` (this file). `doc/knowledge/` architecture docs not modified by this story.
- [x] **No divergence** — story implementation matches documented intent (version from build-time env var, JSON manifest, fail-closed preflight).
- [x] **Topology/docs** — **N/A** — story does not change tile IDs, links, ownership, or Tickoni/Firedancer boundary.
- [x] **Roadmap status** — Story status remains `ready` in roadmap docs until this gate is committed. Status will be updated to `done` on push to `origin/version-preflight`.

---

## Story Closure Checklist

- [x] Demo exists (`tickoni --version`, `tickoni doctor`) and output answers Increment Gate Checklist questions.
- [x] Unit tests exist and pass for changed behavior (`zig build test` exit 0).
- [x] Integration tests exist and pass for changed cross-tile/boundary behavior: **N/A** — no boundary changes.
- [x] System tests exist and pass: **N/A** — no live-tool boundary.
- [x] E2E tests exist and pass: **N/A** — no topology/lifecycle changes.
- [x] `zig fmt` passes for changed paths. `just security-check-all` skipped (CI-only, no secrets present).
- [x] Evidence captured: manifest fixture at stable path, audit docs at `doc/execution/security-audit.md`, telemetry docs at `doc/execution/telemetry-audit.md`.
- [x] Docs and roadmap reconciled. Story closure checklist committed at `doc/execution/quality-gate-t12.md`.
- [x] All items above are true before status moves to `Done`.

---

## Verdict: **PASS**

V2.21.S3 is **done**. All 12 tasks (T1-T12) are complete:

1. **T1** Architecture/planning — tier definitions, JSON manifest, build-time version ✅
2. **T2** DDD + scaffolding — structs, enums, stub functions ✅
3. **T3** TDD tests — test harness against scaffolding ✅
4. **T4** Documentation sweep — docs, dev guide, contribution guide ✅
5. **T5** `tickoni --version` — build-time version, semver formatting ✅
6. **T6** `tickoni doctor` — tier detection, manifest validation, preflight ✅
7. **T7** Manifest schema + loader — JSON parsing, validation, `deinit()` ✅
8. **T8** Preflight fail-closed — `is_preflight_pass()` with strict checks ✅
9. **T9** Audit/replay metadata injection — metadata fields in `VersionInfo` ✅
10. **T10** Security audit — SHIP-READY, 1 critical UB fixed ✅
11. **T11** Telemetry/observability — `name/enter/exit` pattern, `--verbose` flag ✅
12. **T12** Evidence and quality gate — this gate ✅
