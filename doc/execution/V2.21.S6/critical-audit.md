# V2.21.S6 Critical Audit

## Verdict

**Not shippable.**

The branch moves the demo in the right architectural direction, but it still misses key parts of the story contract it claims to implement.

## What is aligned

### 1. Architecture direction is mostly coherent

The new work is concentrated under `src/tickoni/demo/`:

- `cli.zig`
- `manifest.zig`
- `preflight.zig`
- `conformance.zig`
- `diagnostic.zig`
- `comparator.zig`
- `runner.zig`
- `substitution.zig`

That keeps the deterministic demo/conformance logic out of unrelated runtime code.

### 2. The demo is fixture-backed and offline

The branch removed the old llama/system-demo shape from the CLI verification path and replaced it with a deterministic fixture-backed suite.

Evidence:

- `contrib/test/run_cli_demo_tests.sh`
- `justfile` `demo-tk`
- `src/app/tickoni/main.zig`
- `src/tickoni/demo/substitution.zig`

This is aligned with the project architecture and the no-live-effect requirement.

### 3. No new runtime OS switches were found in the demo path

The changed Zig demo/runtime files were checked for runtime OS branching patterns such as:

- `@import("builtin")`
- `builtin.os`
- `std.posix`
- `os.tag`
- `switch (...os...)`

No new runtime OS-switching was found in the demo code. The only observed platform switches were in `build.zig`, i.e. build/platform wiring, not product runtime/demo logic.

### 4. There are real tests, not just stubs

The branch includes real checks for:

- CLI usage failure
- JSON suite shape
- 4 deterministic scenarios
- plain-text suite output markers
- manifest validation
- preflight validation
- comparator behavior
- artifact hashing/serialization
- substitution fixture presence

Also verified live in this session:

- `just test-unit-tk` passed
- `just test-integration-all` passed
- `just test-cov-all` passed
- `just test-system-all` passed
- `just test-e2e-all` passed
- `just tests-all` still fails only in `test-unit-fd` due the host memlock blocker, not due the S6 demo code itself

## Critical findings

### 1. Preflight failures do not emit the explicit blocked-flow diagnostics the story requires

**Status:** DONE

Resolved in code by routing `cmdDemo()` through `demo_preflight.evaluate(...)` and formatting failures with `demo_preflight.formatFailure(...)` before exit.

Verified live during this session with temporary manifests for:

- unsupported runtime tier → `blocked_code: unsupported_runtime_tier`
- missing fixture → `blocked_code: missing_fixture`
- stale manifest → `blocked_code: stale_manifest`
- missing isolation prerequisite → `blocked_code: missing_isolation_prerequisite`

### 2. Several diagnostic codes exist only as definitions/tests, not as surfaced runtime behavior

**Status:** DONE

The preflight/runtime path now surfaces real blocked-flow codes through stderr output, including:

- `unsupported_runtime_tier`
- `missing_fixture`
- `stale_manifest`
- `missing_isolation_prerequisite`
- `attempted_live_execution` (mapped by the preflight formatter for `no_live_effect` failures)

That closes the earlier gap where the enum labels existed but were not emitted by the real CLI path.

### 3. The comparator exists, but there is no real cross-platform comparison workflow wired into the product path

**Status:** DONE

The demo command now computes a Linux-full baseline artifact set alongside the target runtime artifact set and emits a real comparison summary in both output modes:

- JSON now includes a top-level `comparison` object
- plain-text output now includes `comparison_*` lines before the per-scenario artifacts

The comparator is now exercised by the product command path instead of existing only as a standalone module with unit tests.

### 4. Important new test files are not all wired into the canonical Zig test lane

**Status:** DONE

`build.zig` now wires dedicated canonical test binaries for the new demo modules:

- `src/tickoni/demo/diagnostic.zig`
- `src/tickoni/demo/conformance.zig`
- `src/tickoni/demo/comparator.zig`
- `src/tickoni/demo/runner.zig`
- `src/tickoni/demo/substitution.zig`

Verified by rerunning `just test-unit-tk`, which now executes these roots inside the normal `zig build ... test --summary all` lane.

### 5. CI coverage is only partially wired

**Status:** DONE

The short-test workflow now runs `just test-cli-tk` on the full visible short-test matrix covered by this workflow:

- Linux
- macOS 15 Intel
- macOS 15 ARM
- macOS 26 Intel
- macOS 26 ARM

`contrib/test/run_cli_demo_tests.sh` was also extended to verify:

- comparison output is emitted in both JSON and plain-text modes
- unsupported runtime tier emits an explicit diagnostic
- missing fixture emits an explicit diagnostic
- stale manifest emits an explicit diagnostic
- missing isolation prerequisite emits an explicit diagnostic
- `expected_no_live_effect = false` emits `blocked_code: attempted_live_execution`

### 6. The branch is not fully coherent as a review unit

**Status:** DONE

The unrelated engine drift snapshot / engine-check hint changes and the `test-unit-fd` normal-page memlock tweak were removed from this S6 branch. The remaining branch scope is now centered on the deterministic demo, comparator, tests, CI wiring, and S6 execution docs.

## Test quality assessment

## Substantial enough to be meaningful

`contrib/test/run_cli_demo_tests.sh` is materially better than a smoke test. It validates:

- bare `demo` invocation fails
- JSON output parses
- suite contains 4 scenarios
- blocked/tampered paths appear in output
- plain-text output contains expected markers

## Still not substantial enough for story closure

It does **not** yet verify the most important negative-path contract end to end:

- unsupported runtime tier emits explicit diagnostic
- missing fixture emits explicit diagnostic
- stale manifest emits explicit diagnostic
- missing isolation prerequisite emits explicit diagnostic
- attempted live execution emits explicit diagnostic
- tampered proposal artifact emits explicit diagnostic

So the tests are useful, but not yet sufficient for the claimed story scope.

## Code smell assessment

### No major structural smell in module placement

The new files are grouped sensibly and the demo path remains isolated.

### Main remaining smell: dead contract surface

The biggest smell is not formatting or naming; it is the gap between:

- diagnostic types / documented contract
- and actual surfaced runtime behavior

That is a trust problem, because the branch appears more complete from its types/docs than it is in real execution.

## OS-switch assessment

### Pass, with one caveat

- No new runtime OS branching was found in the changed demo path.
- Platform branching observed during audit was in `build.zig`, which is acceptable build-layer/platform wiring.

So on the specific requirement **“no os switches besides in shims”**, this branch does not show a new red flag in the demo code reviewed here.

## Overall judgment

### Passes

- directionally aligned with architecture
- fixture-backed / offline / no-live-effect shape
- demo logic reasonably isolated
- no obvious new runtime OS-switch leakage in reviewed demo path
- contains non-trivial tests

### Fails

- explicit blocked-flow diagnostics not actually delivered for preflight failures
- comparator not wired into a real cross-platform equivalence workflow
- important new tests not all clearly wired into canonical Zig test lane
- CI matrix coverage partial
- branch polluted with unrelated engine/memlock work

## Final conclusion

**Critical audit result: reject in current form.**

The branch is close in direction, but it is not yet coherent and complete enough to call shippable.

## Recommended fix order

1. Wire `preflight.formatFailure(...)` into `cmdDemo()` and surface explicit per-failure diagnostics.
2. Ensure blocked-flow diagnostic codes map to real runtime failure paths, not just type definitions.
3. Add canonical `build.zig` test wiring for all new demo modules with embedded tests.
4. Extend CLI verification to cover the missing negative-path contracts explicitly.
5. Wire `just test-cli-tk` across the intended macOS matrix consistently.
6. Split unrelated engine/memlock work out of the S6 review branch or PR.
