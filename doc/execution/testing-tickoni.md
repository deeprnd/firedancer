# Tickoni Testing

This document summarizes the justfile-oriented test layers for the current
Tickoni repository.

The [Testing Firedancer](../testing.md) page is the Firedancer-style test
guide. This file is intentionally separate for now so the current `justfile`
command matrix can be documented without merging those two views.

## Test Layers

The repository currently has:

- Harness unit tests for Tickoni-owned supervisor, topology, queue, sandbox,
  Phase 0 payment pipeline, audit, case, disp, schema, model, and adapter behavior
- Tickoni integration tests for schema pipeline fixture contracts and
  tile-boundary scenario coverage (tkcase, tkdisp, tkagnt, replay, audit)
- explicit Tickoni system tests for live `tkmodl` compatibility against a local
  `llama.cpp` server and downloaded GGUF model
- Firedancer-derived C unit tests through the upstream unit-test Make target
- Firedancer-derived e2e/integration-test build and run target
- aggregate gates that compose build, quality, security, and test checks

## Core Commands

Tickoni-owned Zig:

- `just test-unit-tk`
- `just test-integration-tk`
- `just test-system-tk`

Firedancer-derived C:

- `just test-unit-fd`
- `just test-e2e-fd`

Aggregates:

- `just test-unit-all`
- `just test-integration-all`
- `just test-e2e-all`
- `just test-all`
- `just tests-all`

Current placeholders:

- `just test-integration-fd`
- `just test-e2e-tk`

The placeholders return `@true` directly in the `justfile`, following the repo
tooling rule that no-op component variants live in the `justfile` and not in
shell scripts.

## What `tests-all` Runs

`just tests-all` runs these commands in order:

1. `just build-all`
2. `just quality-check-all`
3. `just security-check-all`
4. `just test-all`

`just test-all` runs these commands in order:

1. `just test-unit-all`
2. `just test-integration-all`
3. `just test-e2e-all`

`just test-unit-all` and `just test-e2e-all` are badge-wrapped through
`contrib/readme/run-badged-command.py`, so the README status badges reflect the
same aggregate commands developers use locally.

## Test Selection Rules

Run the narrowest relevant set first, then broaden when risk is high. The
current test task source of truth is the repository root `justfile`; run these
commands from the repository root unless noted otherwise.

- Tickoni Zig supervisor, topology, tile lifecycle, queue wrapper, sandbox
  wrapper, or Phase 0 payment pipeline change: `just test-unit-tk`
- Tickoni coverage-sensitive change: `just test-cov-tk`
- Firedancer-derived C infrastructure, Tango, Disco, Discof, Waltz HTTP,
  utility, or Tickoni C build integration change: `just test-unit-fd`
- Firedancer coverage-sensitive change: `just test-cov-fd`
- Cross-boundary Tickoni/Firedancer unit-impacting change:
  `just test-unit-all`
- Runtime topology, workspace setup, local process startup, Firedancer dev path,
  or e2e/system behavior change: `just test-e2e-fd`
- Live `tkmodl` HTTP compatibility, llama.cpp startup, GGUF model wiring, or
  local OpenAI-compatible server behavior change: `just test-system-tk`
- Cross-cutting local runtime validation: `just test-all`
- Broad coverage validation: `just test-cov-all`
- Full repository validation with build, quality, security, and tests:
  `just tests-all`

Current placeholder test recipes are intentionally kept in the `justfile` so the
command shape remains stable while Tickoni-specific integration and e2e layers
are still being built:

- `just test-integration-fd`
- `just test-e2e-tk`

Do not remove, rename, or repurpose these placeholders as part of ordinary
focused changes unless the user explicitly asks for that migration. When a
change may affect behavior that is currently covered only by the Firedancer
runtime path, or before broad handoff on risky work, run:

- `just test-e2e-fd`

If you do not run a relevant check, say so explicitly in the handoff.

## Layer Boundaries And Mocking

The test layer is determined by where replacement happens.

Unit tests replace direct collaborators at the function, tile helper, or module
boundary. A unit test may use a deterministic allocator, fixed payment pipeline
configuration, synthetic input event, fake clock value, direct queue instance,
or in-process supervisor state so the behavior under test stays one small unit
of code. Unit tests should not prove Firedancer process startup, seccomp policy
installation, real shared-memory workspace behavior, full Make integration-test
targets, or live external tool compatibility.

Integration tests keep Tickoni internals real and replace whole outside tools
at the harness boundary. Runtime topology, tile wiring, bounded queue behavior,
event normalization, deduplication, policy evaluation, audit hashing, replay
comparison, serialization, and C ABI wrappers should run through production-like
paths. The harness may substitute external systems with deterministic local
fixtures: a temporary filesystem store instead of a durable deployment store, a
localhost HTTP/RPC stub instead of a future payment processor or model gateway,
or a test shared-memory/workspace harness instead of an operator-managed host
setup. This is the same kind of replacement as using a compatible test engine
for an external database: the outside tool is substituted, but the application
path that talks to it remains real.

E2E and system tests use the actual local runtime tools in a local topology:
the Firedancer-derived Make targets, the `tickoni-supervisor` Zig binary,
wrapper scripts, huge-page setup where needed, and local process or future
container orchestration. These tests verify startup, command contracts, runtime
wiring, persistence or audit output, telemetry surface, and local tool
compatibility. They do not claim production scalability, high availability, or
managed-service parity: a local process topology is not a production supervised
deployment, and local huge-page allocation is not an operator-tuned host fleet.

Firedancer does not map cleanly onto the three-layer application-test split
used by many service repos. Its C tests are mostly:

- unit tests for libraries and individual tiles, often with adjacent tile/link
  behavior mocked or injected directly into the tile under test
- app-level `integration-test` binaries that bring up the Firedancer dev
  runtime path and full local topology pieces

There is not a normal "2 or 3 real tiles only" integration layer for
Firedancer-side work. A tile test such as `test_verify_tile` builds a mock
topology and injects mock inputs into the `verify` tile. A tile test such as
`test_repair_tile` overrides adjacent stem publication/sign behavior so the
repair tile lifecycle can be tested without real tile infrastructure. The
`test_firedancer_dev` integration test is the opposite end of the spectrum: it
initializes Firedancer config/topology and forks the configure, workspace, dev,
and ready command paths.

That is why this repo routes `just test-e2e-fd` to Firedancer's
`make integration-test && make run-integration-test`, while
`just test-integration-fd` is only a placeholder. In Tickoni's repo-facing
taxonomy, Firedancer's Make `integration-test` target behaves like an
e2e/system check because it exercises the local runtime topology rather than an
intermediate subset of real tiles.

Practical rule of thumb:

- unit: mock or fix the direct collaborator function, module, tile helper, or
  runtime input
- integration: substitute the external tool through the shared harness while
  keeping Tickoni internals real
- e2e/system: run the real local toolchain and avoid internal mocks

## Harness Unit Tests

`just test-unit-tk` runs:

```bash
zig build test
```

The current Zig test graph is defined in [build.zig](../../build.zig). It includes
standalone test roots for:

- `src/tickoni/runtime/topology.zig`
- `src/tickoni/runtime/tile.zig`
- `src/tickoni/c_abi/queue.zig`
- `src/tickoni/c_abi/sandbox.zig`
- `src/tickoni/tiles/audit/mod.zig`
- `src/tickoni/tiles/payment_pipeline/mod.zig`
- `src/tickoni/tiles/case/mod.zig`
- `src/tickoni/tiles/disp/mod.zig`
- `src/tickoni/schema/classification/classification.zig`
- `src/tickoni/schema/investment/thesis.zig`
- `src/tickoni/schema/investment/catalog.zig`
- `src/tickoni/schema/investment/basket.zig`
- `src/tickoni/schema/investment/trade_ticket.zig`
- `src/tickoni/schema/investment/impact.zig`
- `src/tickoni/schema/investment/cards.zig`
- `src/tickoni/schema/investment/drift.zig`
- `src/tickoni/schema/portfolio/portfolio.zig`
- `src/tickoni/test/fixtures/portfolio/portfolio_fixtures.zig`
- `src/tickoni/tiles/model/mod.zig`
- `src/tickoni/tiles/adapter/mod.zig`

It also builds a supervisor test binary for:

- `src/app/tickoni/supervisor.zig`

The Phase 0 pipeline tests cover:

- deterministic event hashing
- bounded queue behavior
- duplicate detection
- policy allow and deny decisions
- audited malformed payment rejection
- append-only JSONL audit formatting
- deterministic replay comparison
- sandbox failure diagnostics

## Engine Unit Tests

`just test-unit-fd` runs a wrapper around the Firedancer-derived unit-test
Make targets.

It performs these steps:

1. attempts to free previous gigantic page allocations
2. computes an automatic gigantic-page allocation target from available RAM
3. allocates gigantic pages on NUMA node `0` when possible
4. raises the current shell's memlock limit with `sudo prlimit`
5. builds unit tests with `make -j"$(nproc)" unit-test`
6. runs `make run-unit-test`
7. falls back to `make run-unit-test TEST_OPTS="--page-sz normal"` when
   gigantic pages are unavailable

This wrapper is the preferred repo-facing Firedancer unit-test command. Do not
invoke raw compiler commands for Firedancer tests.

## Engine E2E

`just test-e2e-fd` runs:

```bash
make -j"$(nproc)" integration-test && make run-integration-test
```

This intentionally uses Firedancer's Make `integration-test` class. In
Firedancer terminology, `test_firedancer_dev` is an integration test. In this
repo's `justfile` taxonomy, that same target is treated as e2e/system because
it starts the Firedancer dev command path and local topology pieces instead of
testing a small intermediate group of tiles.

`just test-e2e-tk` is currently a no-op placeholder.

## Integration Layer

`just test-integration-fd` is a placeholder (`@true`). Firedancer does not have
a separate repo-facing intermediate integration layer between tile/unit tests
and full-topology `integration-test` binaries.

`just test-integration-tk` runs:

```bash
zig build integration-test
```

This executes two real test binaries:

- `src/tickoni/test/fixtures/investment/allowed_trade.zig` — fixture contract
  tests for the schema pipeline (thesis → basket → portfolio) with external
  systems replaced by recorded fixtures; no live model, adapter, or execution
  call.
- `src/tickoni/test/integration/allowed_trade.zig` — tile-boundary integration
  tests covering tkcase, tkdisp, tkagnt, replay, and audit scenarios. Tickoni
  internals run through production-like paths; model and adapter backends are
  substituted with fixture backends so no network calls are made.

`just test-integration-all` composes both lanes so the aggregate command shape
stays stable as coverage grows.

## Explicit System Lane

`just test-system-tk` runs:

```bash
bash contrib/test/run_integration_model_tests.sh
```

This lane starts a real local `llama.cpp` server, waits for its health endpoint,
and runs:

```bash
zig build integration-test-live-model
```

It is intentionally not part of `just test-integration-all` or `just test-all`.
The live model server, downloaded GGUF asset, and localhost HTTP surface make
this a system/smoke compatibility check rather than the default integration
lane.

## Quality And Security Gates

Preferred validation commands in order:

- `just quality-format-check-tk` validates `zig fmt --check` for the
  Tickoni-owned Zig source trees.
- `just quality-format-check-fd` validates trailing whitespace for changed
  non-Tickoni-owned paths, including Firedancer-derived C, docs, and scripts.
- `just quality-format-check-all` runs both formatting lanes.
- If formatting fails, prefer `just quality-format-fix-tk`,
  `just quality-format-fix-fd`, or `just quality-format-fix-all`, then only
  apply targeted manual formatting if automatic fixing still leaves failures.
- `just quality-lint-check-tk` runs Tickoni-owned lint checks.
- `just quality-lint-check-fd` runs Firedancer-derived lint checks and
  `shellcheck` when that tool is installed.
- `just quality-lint-check-all` runs both lint lanes.
- `just quality-check-all` runs the main repository quality bundle:
  format-check all lanes, then lint-check all lanes.
- `just security-gitleaks-check-all` scans the current Tickoni and
  Firedancer-owned source scopes for secret leaks.
- `just security-codeql-check-all` runs the configured CodeQL recipe variants.
  Some current variants are no-op placeholders while local setup is blocked or
  not yet wired.
- `just security-seccomp-check-all` runs the configured seccomp recipe variants.
  Current placeholder components are documented in [Security](./security.md).
- `just security-proof-check-all` runs proof-related checks for the lanes that
  currently expose them.
- `just security-sanitize-check-all` runs sanitizer-oriented checks, including
  Tickoni `ReleaseSafe` Zig tests and the Firedancer sanitizer path.
- `just security-check-all` runs the full repository security bundle:
  CodeQL, gitleaks, seccomp, proof, and sanitizer checks.
- `just test-unit-tk` runs Tickoni Zig harness unit tests.
- `just test-unit-fd` runs Firedancer-derived C unit tests through the
  repository wrapper that manages huge-page setup and normal-page fallback.
- `just test-unit-all` runs both unit lanes.
- `just test-integration-all` currently runs placeholder integration lanes so
  the aggregate command shape remains stable.
- `just test-e2e-fd` runs the Firedancer-derived local runtime integration-test
  build and execution path, surfaced as this repo's e2e/system lane.
- `just test-e2e-all` runs the Firedancer e2e/system lane plus the current
  Tickoni e2e placeholder.
- `just test-cov-tk` runs Tickoni harness coverage.
- `just test-cov-fd` runs Firedancer-derived C coverage with reduced
  parallelism for local and CI memory limits.
- `just test-cov-all` runs both coverage lanes.
- `just test-all` runs the broad test bundle: unit, integration, and e2e.
- `just tests-all` runs the full local handoff gate: build, quality, security,
  and tests.

For broad changes, use:

- `just test-all`

For full handoff validation when build, quality, security, and runtime risk are
all in scope, use:

- `just tests-all`

If you skip a relevant gate because it is too expensive, needs unavailable
local tools, or requires host privileges such as huge-page or memlock setup,
call that out explicitly in the handoff.

## Related Docs

- [Development](./development.md)
- [Security](./security.md)
- [Observability](./observability.md)
