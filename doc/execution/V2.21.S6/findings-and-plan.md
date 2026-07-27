# V2.21.S6 — Cross-Platform Deterministic Demo And Conformance Suite

## Purpose

This note captures the current findings and the execution plan required to close
`V2.21.S6` from `doc/strategy/roadmap/stories/v2.21-s6.md`.

Story intent: prove that Tickoni can run a deterministic retail demo whose
policy, audit, replay, and no-live-effect behavior matches Linux full-runtime
for the scope the retail tier claims equivalent, while blocked or tampered flows
fail closed.

## What Must Be True To Close V2.21.S6

`V2.21.S6` is only closeable when Tickoni can run one deterministic retail demo
and prove all of the following:

- Linux full-runtime and macOS retail produce equivalent conformance artifacts
  for the scope dimensions the tier claims equivalent.
- Unsupported, tampered, stale, missing-prerequisite, or live-effect attempts
  fail closed with explicit diagnostics.
- All model, tool, adapter, and execution effects are fixture-backed, mocked,
  or replay-substituted.
- The story has the required tests, docs, CI wiring, and evidence artifacts per
  `doc/execution/quality.md`.

## Relevant Source Documents

- `doc/strategy/roadmap/stories/v2.21-s6.md`
- `doc/strategy/roadmap/epics/v2.21.md`
- `doc/knowledge/platform-tiers.md`
- `doc/execution/quality.md`
- `doc/strategy/roadmap/stories/v2.21-s1.md`
- `doc/strategy/roadmap/stories/v2.21-s3.md`
- `doc/strategy/roadmap/stories/v2.21-s4.md`
- `doc/strategy/roadmap/stories/v2.21-s7.md`

## Current Repo State

### Already Present

The repo already has a useful base for S6:

- Tier definitions exist in `doc/knowledge/platform-tiers.md`.
- Version / doctor / manifest / preflight scaffolding exists:
  - `src/tickoni/version.zig`
  - `src/tickoni/doctor/checks.zig`
  - `src/tickoni/doctor/output.zig`
  - `src/tickoni/demo/manifest.zig`
  - `src/tickoni/demo/preflight.zig`
- There is already a substantial investment-demo fixture/audit/replay baseline:
  - `src/tickoni/test/integration/test_investment_replay.zig`
  - `src/tickoni/test/integration/test_investment_blocked_limits.zig`
  - `src/tickoni/test/integration/test_investment_restricted_instrument.zig`
  - `src/tickoni/test/demo/investment/support.zig`
  - `src/tickoni/test/fixtures/investment/scenarios/...`
- Existing fixture material already covers the right shape of scenarios:
  - allowed paper trade
  - oversized blocked trade
  - restricted instrument deny
  - tampered replay capsule

### Direct Gaps And Problems

#### 1. `tickoni demo` is still a stub

`src/app/tickoni/main.zig` currently implements `cmdDemo()` as a preflight-only
placeholder.

Current behavior:

- loads manifest
- runs preflight
- prints `preflight: passed`
- prints `demo: completed`
- does not run a real deterministic demo
- does not emit conformance outputs
- does not produce audit JSONL output
- does not produce replay comparison output

This is the main implementation blocker for S6.

#### 2. `cmdDemo()` hardcodes platform state

`src/app/tickoni/main.zig` currently hardcodes:

- runtime tier = `linux_full`
- isolation tier = `retail`

That cannot be the real S6 implementation basis. S6 needs actual tier-aware
execution and comparison.

#### 3. CLI contract mismatch

The repo currently has conflicting expectations for the demo surface:

- `justfile` expects:
  - `tickoni demo investment --fixture --thesis ...`
- `contrib/test/run_cli_demo_tests.sh` expects:
  - `tickoni demo investment --json --thesis ...`
- current `main.zig` accepts only:
  - `tickoni demo <manifest-path>`

S6 cannot close while the command contract is inconsistent across the CLI,
`justfile`, and tests.

#### 4. Manifest sample semantics are suspicious

`src/tickoni/demo/fixtures/demo.manifest.json` currently says:

- `supported_runtime_tiers = ["linux_full", "macos_retail"]`
- `required_isolation_tier = "retail"`

That does not cleanly fit Linux full-runtime semantics. If Linux full-runtime is
part of the comparison set, the manifest model likely needs either:

- per-tier expectations, or
- separate manifests, or
- one shared manifest plus a separate conformance expectation file.

A single exact `required_isolation_tier` equality check is likely too rigid for
Linux full vs macOS retail comparison.

#### 5. V2.21.S6 story text still leaks Windows scope

`doc/strategy/roadmap/stories/v2.21-s6.md` includes wording that says
"macOS or Windows retail path" even though epic `V2.21` is macOS-only and
Windows belongs in `V2.22`.

This should be corrected before closure so S6 scope is unambiguous.

## Recommendation: First Demo Candidate

Use the existing investment paper-trade fixture path as the first retail demo
manifest for S6.

Why this is the best first candidate:

- the repo already has meaningful allowed / denied / tampered fixture coverage
- replay and audit fixtures already exist
- the workflow naturally fits the story's no-live-effect requirement
- it avoids inventing a new fixture family just to satisfy S6

Recommended first scenario family:

- allowed paper trade
- oversized blocked trade
- restricted instrument deny
- tampered replay capsule
- attempted live execution / direct bypass deny

## Required Implementation Work

## 1. Lock The Demo Contract First

Before implementation expands, freeze the S6 contract:

- exact demo command shape
- exact manifest format
- exact output format
- exact artifact paths
- exact comparison rules

This decision must be reflected consistently in:

- `doc/strategy/roadmap/stories/v2.21-s6.md`
- new S6 execution documentation under `doc/execution/V2.21.S6/`
- `src/app/tickoni/main.zig`
- any new demo runner / comparator modules

## 2. Replace The Stub With A Real Demo Runner

Implement a real deterministic demo runner that:

- loads a manifest
- runs preflight
- selects a fixture set
- runs the investment demo path
- emits machine-readable conformance output
- references or writes audit JSONL artifacts
- references or writes replay capsule artifacts
- verifies no-live-effect boundaries
- never touches live providers, live adapters, or `tkexec`

Likely new modules:

- `src/tickoni/demo/runner.zig`
- `src/tickoni/demo/conformance.zig`
- `src/tickoni/demo/diagnostic.zig`
- `src/tickoni/demo/substitution.zig`

`src/app/tickoni/main.zig` should stay thin: parse args, call the runner, print
plain or JSON output.

## 3. Define A Canonical Conformance Artifact Schema

S6 needs a stable machine-readable artifact schema so Linux and macOS outputs
can be compared deterministically.

Minimum recommended fields:

- manifest id / manifest version
- Tickoni version
- runtime tier
- isolation tier
- fixture set id
- normalized event hash
- policy outcome
- proposal hash
- audit JSONL path and/or content hash
- replay capsule path and/or content hash
- replay result
- blocked-flow diagnostic, when applicable
- `external_effects_disabled = true`

This schema should live in code and be documented in a dedicated S6 document.

## 4. Separate Demo Execution From Conformance Comparison

S6 should not mix these responsibilities into one opaque command path.

Two layers are needed:

1. **Runner**
   - executes one fixture-backed demo on one platform tier
   - produces conformance artifacts
2. **Comparator**
   - compares two artifact sets
   - reports exact field-level equivalence or permitted differences

This separation is what CI needs:

- Linux generates baseline artifacts
- macOS retail generates retail artifacts
- comparator verifies equivalence for the fields the tier claims equivalent

Timing, scheduling, or runtime-only metadata should not be treated as
conformance-critical if the tier definition does not claim them equivalent.

## 5. Fix Platform Detection And Manifest Semantics

Remove hardcoded runtime and isolation values from `cmdDemo()`.

Instead:

- derive actual runtime tier from the same logic the doctor/version path uses
- derive actual isolation tier consistently
- enforce manifest compatibility based on real runtime metadata

Most likely viable designs:

- **Option A:** one manifest per tier
- **Option B:** one manifest with per-tier expectations
- **Option C:** one shared manifest plus a tier-specific conformance expectation
  file

Recommendation: use **Option B or C**, not the current single exact isolation
match, because Linux full-runtime and macOS retail are intentionally not the
same isolation tier.

## 6. Reuse Existing Investment Fixtures As The First Conformance Suite

The current repo already has the right fixture family to seed S6.

Use these as the first conformance suite:

- allowed paper trade
- oversized blocked trade
- restricted instrument deny
- tampered replay capsule
- attempted live execution / direct bypass deny

Existing files that should be reused rather than replaced:

- `src/tickoni/test/integration/test_investment_replay.zig`
- `src/tickoni/test/integration/test_investment_blocked_limits.zig`
- `src/tickoni/test/integration/test_investment_restricted_instrument.zig`
- `src/tickoni/test/demo/investment/support.zig`
- `src/tickoni/test/fixtures/investment/scenarios/...`

## 7. Add Explicit Blocked-Flow Coverage For Every S6 Failure Mode

Per the story acceptance criteria, S6 needs deterministic blocked-flow coverage
for all of these:

- unsupported runtime tier
- missing fixture
- stale manifest
- attempted live execution
- tampered replay artifact
- tampered proposal artifact
- missing isolation prerequisite

Each one needs:

- a deterministic trigger
- a machine-readable diagnostic
- proof that no proposal / audit side effects were emitted when preflight or
  conformance should fail closed

## 8. Prove The No-Live-Effect Boundary

S6 is not done until the demo path is structurally incapable of going live.

Need explicit checks/tests that prove:

- no direct model-provider bypass outside `tkmodl`
- no direct adapter bypass outside `tktool` / `tkadpt`
- no `tkexec` path is reachable from the retail demo
- replay substitutes captured outputs rather than calling live systems
- a live-execution attempt is denied before any effectful boundary

## 9. Align CLI, `justfile`, And Test Scripts

S6 needs one final supported public surface for:

- `tickoni demo ...`
- `just demo-tk`
- `just test-cli-tk`
- any S6-specific fixture or comparison recipes

Files that must be reconciled together:

- `src/app/tickoni/main.zig`
- `justfile`
- `contrib/test/run_cli_demo_tests.sh`

## 10. Add The S6 Test Matrix

Minimum closure test matrix:

| Layer | Required coverage |
| --- | --- |
| Unit | manifest rules, conformance comparator, diagnostic formatting |
| Integration | fixture-backed allowed / blocked / tampered demo runs |
| CLI | `tickoni demo` plain and JSON output contract |
| Cross-platform | Linux baseline vs macOS retail comparison |
| Security / fail-closed | live-attempt and tamper denial |
| Replay | substituted replay with zero external effects |

Tests should be wired into the existing `just` lanes, not left as ad hoc manual
commands.

## 11. Add A Focused CI Matrix

S6 needs a narrow, explicit CI contract rather than a broad platform slogan.

Recommended V2.21 S6 matrix:

- Linux job generates baseline conformance artifacts
- macOS job runs the retail deterministic demo
- comparator step verifies equivalence on claimed deterministic fields
- blocked/tampered lane proves fail-closed behavior
- uploaded artifacts include:
  - conformance JSON
  - audit JSONL
  - replay capsule
  - blocked-flow diagnostic

## 12. Finish Docs And Evidence Closure

S6 should end with a linked evidence bundle under `doc/execution` and roadmap
references.

Recommended evidence set:

- chosen manifest definition
- fixture set definition
- Linux sample output
- macOS sample output
- conformance comparison result
- blocked-flow sample
- tampered replay sample
- security audit
- telemetry / observability audit
- final quality-gate checklist per `doc/execution/quality.md`

## Recommended Execution Order

1. Fix the scope/docs inconsistency so `V2.21.S6` is macOS-only in wording.
2. Freeze the CLI + manifest + output contract.
3. Implement a real demo runner.
4. Implement the conformance artifact schema.
5. Implement the comparator.
6. Wire the existing investment fixtures into the runner.
7. Add blocked / tampered / live-attempt fail-closed cases.
8. Reconcile `main.zig`, `justfile`, and CLI test scripts.
9. Add CI matrix wiring.
10. Write evidence docs and close the story gate.

## Main Closure Blockers

These are the concrete blockers that prevent `V2.21.S6` from being marked done
right now:

- `tickoni demo` is still a stub
- no real conformance comparator exists
- no canonical Linux/macOS conformance artifact schema exists
- CLI / `justfile` / test script contract is inconsistent
- manifest semantics for Linux full vs macOS retail are not coherent yet
- `V2.21.S6` wording still partially mixes in Windows scope

## Concrete Implementation Checklist

This section converts the findings above into an implementation checklist with
exact file edits, intended outputs, and verification commands.

### Phase 1 — Fix Scope And Freeze The Contract

#### 1. Make `V2.21.S6` macOS-only in roadmap wording

**Status:** DONE

**Edit:** `doc/strategy/roadmap/stories/v2.21-s6.md`

**Required edits:**
- Replace "macOS or Windows retail path" with "macOS retail path".
- Replace any Linux-vs-"macOS or Windows" comparison wording with
  Linux-vs-macOS wording.
- Keep Windows language only in `V2.22.S6`.

**Verification commands:**
```bash
rg -n "Windows retail path|macOS or Windows retail path" doc/strategy/roadmap/stories/v2.21-s6.md
rg -n "macOS retail path" doc/strategy/roadmap/stories/v2.21-s6.md
```

**Expected result:**
- first command returns no matches
- second command shows the corrected wording

#### 2. Freeze the supported S6 CLI contract

**Status:** DONE

**Edit:** `src/app/tickoni/main.zig`

**Decide and implement one public surface. Recommended:**
```text
tickoni demo investment --json --manifest <path>
tickoni demo investment --plain --manifest <path>
```

Optional convenience flags may remain, but `justfile`, CLI tests, and docs must
all use the same contract.

**Required edits:**
- Replace `tickoni demo <manifest-path>` parsing with subcommand parsing for
  `investment`.
- Support `--json` and `--plain` output selection.
- Support explicit `--manifest <path>`.
- Reject unknown or mixed arguments fail-closed.

**Files to edit:**
- `src/app/tickoni/main.zig`
- `justfile`
- `contrib/test/run_cli_demo_tests.sh`
- this document if the final contract differs from the recommendation

**Verification commands:**
```bash
zig build
zig-out/bin/tickoni demo
zig-out/bin/tickoni demo investment --help || true
```

**Expected result:**
- build succeeds
- bare `tickoni demo` fails with usage
- help/usage text shows the final supported contract

#### 3. Fix manifest semantics for Linux full vs macOS retail comparison

**Status:** DONE

**Edit:**
- `src/tickoni/demo/manifest.zig`
- `src/tickoni/demo/preflight.zig`
- `src/tickoni/demo/fixtures/demo.manifest.json`

**Required edits:**
- Remove the assumption that one exact `required_isolation_tier` value applies
  identically to both Linux full and macOS retail.
- Implement one of:
  - per-tier expectations inside the manifest, or
  - a separate conformance expectation file loaded next to the manifest.
- Update validation logic and manifest fixture accordingly.

**Recommended exact change direction:**
- keep `supported_runtime_tiers`
- replace single `required_isolation_tier` with per-tier expectations, e.g.
  Linux full -> `full`, macOS retail -> `retail`

**Verification commands:**
```bash
zig build test --summary all
zig-out/bin/tickoni doctor --json
zig-out/bin/tickoni demo investment --json --manifest src/tickoni/demo/fixtures/demo.manifest.json
```

**Expected result:**
- manifest parses and validates
- doctor reports real tier metadata
- demo preflight no longer depends on hardcoded mismatched isolation values

### Phase 2 — Implement The Real Demo Runner

#### 4. Add the demo runner module

**Status:** DONE

**Create:** `src/tickoni/demo/runner.zig`

**Responsibilities:**
- load manifest / expectation config
- run preflight
- select the investment fixture scenario
- execute the demo using existing deterministic investment fixture paths
- return a conformance result object
- never call live systems

**Likely imports/reuse:**
- `src/tickoni/demo/preflight.zig`
- `src/tickoni/version.zig`
- `src/tickoni/test/demo/investment/support.zig`
- existing investment replay/audit helpers

**Edit:** `src/app/tickoni/main.zig`
- replace stub `cmdDemo()` body with a call into `demo.runner`

**Verification commands:**
```bash
zig build
zig-out/bin/tickoni demo investment --json --manifest src/tickoni/demo/fixtures/demo.manifest.json
```

**Expected result:**
- output is real machine-readable demo data, not just
  `preflight: passed` / `demo: completed`

#### 5. Define the conformance artifact schema in code

**Status:** DONE

**Create:** `src/tickoni/demo/conformance.zig`

**Required fields:**
- manifest id / version
- Tickoni version
- runtime tier
- isolation tier
- fixture set id
- normalized event hash
- policy outcome
- proposal hash
- audit JSONL path/hash
- replay capsule path/hash
- replay result
- blocked diagnostic, if present
- `external_effects_disabled`

**Required edits:**
- add serializer for plain and JSON output
- make the schema stable enough for diff/comparison in CI

**Verification commands:**
```bash
zig build test --summary all
zig-out/bin/tickoni demo investment --json --manifest src/tickoni/demo/fixtures/demo.manifest.json | jq .
```

**Expected result:**
- JSON parses cleanly
- all required fields are present

#### 6. Add explicit blocked-flow diagnostic schema

**Status:** DONE

**Create:** `src/tickoni/demo/diagnostic.zig`

**Required cases:**
- unsupported runtime tier
- missing fixture
- stale manifest
- attempted live execution
- tampered replay artifact
- tampered proposal artifact
- missing isolation prerequisite

**Required edits:**
- return one stable diagnostic shape for all blocked flows
- ensure blocked diagnostics can be emitted without producing normal demo
  artifacts

**Verification commands:**
```bash
zig build test --summary all
```

**Expected result:**
- unit tests cover every blocked diagnostic type

### Phase 3 — Reuse Existing Investment Fixtures Instead Of Inventing New Ones

#### 7. Wire the allowed paper-trade scenario into the runner

**Status:** DONE

**Reuse existing files:**
- `src/tickoni/test/integration/test_investment_replay.zig`
- `src/tickoni/test/demo/investment/support.zig`
- `src/tickoni/test/fixtures/investment/scenarios/fixture_audit_allowed_2000.jsonl`

**Required edits:**
- expose the reusable helper path from existing test/demo support into the new
  runner code
- produce conformance output for the allowed case

**Verification commands:**
```bash
zig build integration-test
just test-integration-tk
zig-out/bin/tickoni demo investment --json --manifest src/tickoni/demo/fixtures/demo.manifest.json
```

**Expected result:**
- allowed scenario emits normalized event hash, allow policy, proposal hash,
  audit reference, replay result

#### 8. Wire the blocked oversized scenario into the runner

**Status:** DONE

**Reuse existing file:**
- `src/tickoni/test/integration/test_investment_blocked_limits.zig`

**Required edits:**
- make oversized deny path available as a deterministic blocked-flow demo mode
- emit blocked diagnostic without paper execution

**Verification commands:**
```bash
just test-integration-tk
zig-out/bin/tickoni demo investment --json --manifest src/tickoni/demo/fixtures/demo.manifest.json
```

**Expected result:**
- blocked scenario reports deny, blocked reason, failed scope dimension, and no
  paper execution

#### 9. Wire the restricted-instrument scenario into the runner

**Status:** DONE

**Reuse existing file:**
- `src/tickoni/test/integration/test_investment_restricted_instrument.zig`

**Required edits:**
- expose restricted ticker deny path through the runner
- emit stable blocked diagnostic for restricted instruments

**Verification commands:**
```bash
just test-integration-tk
just test-cli-tk
```

**Expected result:**
- restricted ticker path denies before live model/adapter effects

#### 10. Wire tampered replay detection into the runner/comparator path

**Status:** DONE

**Reuse existing files:**
- `src/tickoni/test/integration/test_investment_replay.zig`
- `src/tickoni/test/demo/investment/support.zig`
- `src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_tampered_paper_fill.json`

**Required edits:**
- expose a tampered replay check in the conformance/comparison layer
- return divergence or tamper diagnostic without external effects

**Verification commands:**
```bash
just test-integration-tk
```

**Expected result:**
- tampered replay is detected deterministically and reported as blocked/fail

### Phase 4 — Add The Comparator And Platform-Aware Execution

#### 11. Add a conformance comparator

**Status:** DONE

**Create:** `src/tickoni/demo/comparator.zig`

**Responsibilities:**
- compare Linux baseline vs macOS retail conformance outputs
- compare only fields the tier claims equivalent
- report exact mismatched field names
- ignore timing/runtime-only metadata not covered by tier equivalence

**Required edits:**
- define field-by-field equivalence rules
- expose comparator to tests and CI

**Verification commands:**
```bash
zig build test --summary all
```

**Expected result:**
- comparator tests prove equal artifacts pass and intentionally changed fields
  fail with precise diagnostics

#### 12. Remove hardcoded tier/isolation values from `cmdDemo()`

**Status:** DONE

**Edit:**
- `src/app/tickoni/main.zig`
- possibly `src/tickoni/doctor/output.zig` if a shared runtime-tier helper is
  needed

**Required edits:**
- derive runtime tier from the same platform detection path used by doctor
- derive isolation tier consistently
- pass real values into preflight and the runner

**Verification commands:**
```bash
zig build
zig-out/bin/tickoni doctor --plain
zig-out/bin/tickoni doctor --json
zig-out/bin/tickoni demo investment --json --manifest src/tickoni/demo/fixtures/demo.manifest.json
```

**Expected result:**
- doctor and demo agree on runtime tier and isolation tier
- no hardcoded Linux/retail pair remains in the demo path

### Phase 5 — Align Public Commands, Tests, And CI

#### 13. Reconcile `justfile` with the final CLI contract

**Status:** DONE

**Edit:** `justfile`

**Required edits:**
- update `demo-tk` to call the final CLI contract
- update `test-cli-tk` or add a narrower S6-specific recipe if needed
- add a dedicated comparison recipe if S6 needs one, e.g.
  `test-conformance-tk`

**Verification commands:**
```bash
just demo-tk
just test-cli-tk
```

**Expected result:**
- recipes invoke the same surface the CLI actually supports

#### 14. Reconcile `contrib/test/run_cli_demo_tests.sh`

**Status:** DONE

**Edit:** `contrib/test/run_cli_demo_tests.sh`

**Required edits:**
- update the script to call the final CLI shape
- assert the new conformance JSON fields
- keep blocked/replay/no-live-effect assertions

**Verification commands:**
```bash
bash contrib/test/run_cli_demo_tests.sh
```

**Expected result:**
- CLI test script passes against the real demo implementation

#### 15. Add focused S6 test files

**Status:** DONE

**Create or extend tests under:**
- `src/tickoni/demo/*.zig` unit tests
- `src/tickoni/test/integration/` for runner/comparator integration
- CLI contract assertions via existing shell script or Zig CLI tests

**Required coverage:**
- manifest validation
- per-tier expectation logic
- allowed conformance output
- blocked oversized output
- restricted instrument output
- tampered replay output
- comparator equality / mismatch behavior
- fail-closed live-attempt path

**Verification commands:**
```bash
just test-unit-tk
just test-integration-tk
just test-cli-tk
```

**Expected result:**
- every new S6 behavior is exercised through the normal test lanes

#### 16. Add CI matrix wiring for Linux baseline vs macOS retail

**Status:** DONE

**Edit:** relevant CI workflow files under `.github/workflows/`

**Implemented edits:**
- `tests-short.yml` now includes a Linux demo-conformance bundle job
- `tests-short.yml` now includes a macOS 15 ARM retail demo-conformance bundle job
- both jobs upload:
  - `conformance.json`
  - `comparison.json`
  - `blocked-diagnostics.json`
  - copied referenced audit / replay artifacts
- a follow-up compare job downloads both bundles and checks deterministic-field equivalence with `contrib/test/compare_demo_conformance.py`
- change detection now watches the S6 demo CI helper scripts:
  - `contrib/test/run_cli_demo_tests.sh`
  - `contrib/test/export_demo_conformance_bundle.py`
  - `contrib/test/compare_demo_conformance.py`

**Verification commands:**
```bash
python3 contrib/test/export_demo_conformance_bundle.py . /tmp/hermes-demo-bundle
python3 contrib/test/compare_demo_conformance.py /tmp/hermes-demo-bundle/conformance.json /tmp/hermes-demo-bundle/conformance.json
python3 - <<'PY'
import yaml, pathlib
print('YAML_OK' if yaml.safe_load(pathlib.Path('.github/workflows/tests-short.yml').read_text()) is not None else 'YAML_EMPTY')
PY
rg -n "demo-conformance|upload-artifact|download-artifact|compare_demo_conformance|export_demo_conformance_bundle|test-cli-tk" .github/workflows/tests-short.yml
```

**Expected result:**
- workflow definitions explicitly show Linux/macOS S6 artifact generation and comparison
- comparison helper passes on identical conformance bundles
- workflow YAML parses cleanly

### Phase 6 — Finish Evidence And Closure Docs

#### 17. Add an S6 artifact/evidence doc set under `doc/execution/V2.21.S6/`

**Status:** DONE

**Create or update:**
- `doc/execution/V2.21.S6/findings-and-plan.md`
- `doc/execution/V2.21.S6/manifest-contract.md`
- `doc/execution/V2.21.S6/conformance-artifacts.md`
- `doc/execution/V2.21.S6/quality-gate.md`
- `doc/execution/V2.21.S6/security-audit.md`
- `doc/execution/V2.21.S6/telemetry-audit.md`

**Required contents:**
- chosen manifest contract
- fixture set definition
- Linux sample output
- macOS sample output
- comparator result sample
- blocked-flow sample
- tampered replay sample
- final checklist against `doc/execution/quality.md`

**Verification commands:**
```bash
rg -n "V2\.21\.S6|conformance|manifest|quality gate" doc/execution/V2.21.S6
```

**Expected result:**
- evidence docs exist and are internally consistent with the implemented CLI and
  test outputs

## Final Verification Command Set

After the implementation is complete, the minimum focused command set for S6
should be:

```bash
zig build -Dfd-lib-dir=build/fd-tickoni-fd/lib --summary all
just test-unit-tk
just test-integration-tk
just test-cli-tk
just quality-check-all
just security-check-all
just demo-tk
zig-out/bin/tickoni-supervisor doctor --json
zig-out/bin/tickoni-supervisor demo investment --json --manifest src/tickoni/demo/fixtures/demo.manifest.json
```

If CI wiring is added in the same change, also verify the workflow references:

```bash
rg -n "macos|demo-tk|test-cli-tk|test-integration-tk|conformance" .github/workflows
```

## Definition Of Done For This File's Plan

S6 is ready to mark `Done` only when all of the following are true:

- roadmap wording is macOS-only for `V2.21.S6`
- demo CLI contract is unified across `main.zig`, `justfile`, tests, and docs
- `tickoni demo` runs a real deterministic investment demo rather than a stub
- Linux and macOS conformance artifacts can be compared mechanically
- blocked/tampered/live-attempt flows fail closed with stable diagnostics
- no-live-effect boundaries are explicitly proven by tests
- S6 evidence docs exist under `doc/execution/V2.21.S6/`
- the focused verification command set passes

## Short Summary

To close `V2.21.S6`, Tickoni needs to convert the existing investment demo
fixtures into a real manifest-driven no-live-effect conformance runner, compare
Linux full-runtime and macOS retail outputs on declared deterministic fields,
add blocked/tampered/live-attempt fail-closed coverage, wire that into CLI and
CI, and capture the full evidence bundle required by `doc/execution/quality.md`.
