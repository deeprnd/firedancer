# Tickoni Testing

This document summarizes the justfile-oriented test layers for the current
Tickoni repository.

The existing [Testing Tickoni](./testing.md) page is the Firedancer-style test
guide. This file is intentionally separate for now so the current `justfile`
command matrix can be documented without merging those two views.

## Test Layers

The repository currently has:

- Zig unit tests for Tickoni-owned supervisor, topology, queue, sandbox, and
  Phase 0 payment pipeline behavior
- Firedancer-derived C unit tests through the upstream unit-test Make target
- Firedancer-derived e2e/integration-test build and run target
- placeholder integration recipes for components that do not yet have a real
  Tickoni integration layer
- aggregate gates that compose build, quality, security, and test checks

## Core Commands

Tickoni-owned Zig:

- `just test-unit-tk`

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
- `just test-integration-tk`
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

## Command Selection

Use the narrowest relevant command first:

- Tickoni Zig runtime, topology, queue, sandbox, supervisor, or payment pipeline
  change: `just test-unit-tk`
- Firedancer C runtime change: `just test-unit-fd`
- Firedancer-side integration/e2e behavior: `just test-e2e-fd`
- quality-only change: `just quality-check-all`
- security-tooling change: `just security-check-all`
- full local gate: `just tests-all`

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

## Tickoni Zig Unit Tests

`just test-unit-tk` runs:

```bash
zig build test
```

The current Zig test graph is defined in [build.zig](../build.zig). It includes
standalone test roots for:

- `src/tickoni/runtime/topology.zig`
- `src/tickoni/runtime/tile.zig`
- `src/tickoni/c_abi/queue.zig`
- `src/tickoni/c_abi/sandbox.zig`
- `src/tickoni/tiles/payment_pipeline.zig`

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

## Firedancer Unit Tests

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

## Firedancer E2E

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

Both current integration component recipes are placeholders:

- `just test-integration-fd`
- `just test-integration-tk`

`just test-integration-fd` is intentionally `@true` because Firedancer does not
have a separate repo-facing intermediate integration layer between tile/unit
tests and full-topology `integration-test` binaries. `just test-integration-tk`
is also `@true` until Tickoni grows its own harness-level tests.

`just test-integration-all` still composes both so the command shape stays
stable as real Tickoni integration coverage is added.

## Quality And Security Gates

Broad validation commands:

- `just quality-check-all`
- `just security-check-all`
- `just test-all`
- `just tests-all`

`quality-check-all` covers formatting and lint checks. `security-check-all`
covers CodeQL, gitleaks, seccomp, proof, and sanitizer recipe variants, with
current no-op components documented in [Security](./security.md).

## Related Docs

- [Development](./development.md)
- [Security](./security.md)
- [Observability](./observability.md)
