# Development

This document covers local setup, repo-facing commands, and the main Tickoni
development workflow.

All developer tooling entrypoints live in the `justfile`. Do not add Tickoni
developer tooling targets to `config/everything.mk` or upstream Firedancer
Makefiles.

## Prerequisites

Core requirements:

- Linux on x86-64 for Firedancer-derived runtime work
- `just`
- `make`
- GCC for the default Firedancer build path
- Zig for Tickoni-owned runtime and supervisor work
- Python 3

Useful local tools for full gates:

- `pre-commit`
- `shellcheck`
- `gitleaks`
- `codeql`
- Clang for sanitizer builds
- CBMC/proof tooling used by Firedancer proof checks

Firedancer only supports x86-64 Linux. Other targets are not valid for the
Firedancer runtime because the code relies on x86-64 memory-ordering
assumptions.

## Install

Install common Python tooling used by repo maintenance, codegen, and tests:

```bash
just python-dev-install
```

Install the wider optional Python surface:

```bash
just python-dev-install-all
```

The wider install includes optional extras for protobuf generators, math
generators, simulation helpers, Solana helpers, and agave-cluster CLI
dependencies.

## Build

Tickoni-owned Zig supervisor:

```bash
just build-tk
```

Firedancer-derived `tickoni` C binary:

```bash
just build-fd
```

Firedancer dev validator:

```bash
just build-fd-dev
```

Combined default build:

```bash
just build-all
```

`build-all` badge-wraps `just build-tk && just build-fd` through
`contrib/readme/run-badged-command.py`.

## Run

Print the Phase 0 Tickoni topology:

```bash
zig build run -- status
```

Run the Phase 0 payment pipeline spike:

```bash
zig build run -- start
```

The supervisor currently supports only:

- `start`
- `status`

## Test

Main test entrypoints:

- `just test-unit-tk`
- `just test-unit-fd`
- `just test-unit-all`
- `just test-integration-all`
- `just test-e2e-all`
- `just test-all`
- `just tests-all`

For the detailed test command matrix, see
[Tickoni Testing](./testing-tickoni.md). The existing
[Testing Tickoni](./testing.md) page remains the Firedancer-style testing guide
and has not been merged with the justfile-oriented guide.

## Quality

Formatting:

- `just quality-format-check-fd`
- `just quality-format-fix-fd`
- `just quality-format-check-tk`
- `just quality-format-fix-tk`
- `just quality-format-check-all`
- `just quality-format-fix-all`

Lint:

- `just quality-lint-check-fd`
- `just quality-lint-check-tk`
- `just quality-lint-check-all`

Aggregate:

- `just quality-check-all`

The Firedancer-side quality script scopes checks to changed, tracked, cached,
and untracked files outside `src/app/tickoni` and `src/tickoni`. The Tickoni
format path runs `zig fmt` on the Zig-owned source trees.

## Security

Security entrypoints:

- `just security-gitleaks-check-all`
- `just security-codeql-check-all`
- `just security-seccomp-check-all`
- `just security-proof-check-all`
- `just security-sanitize-check-all`
- `just security-check-all`

For scanner details and current no-op recipes, see [Security](./security.md).

## Memory And Huge Pages

Firedancer-side unit tests prefer gigantic pages. The helper recipes are:

- `just mem-init`
- `just mem-query`
- `just mem-reset`
- `just mem-fini`
- `just mem-alloc`
- `just mem-alloc-auto`
- `just mem-free`

`just test-unit-fd` also attempts to free previous gigantic pages, allocate an
automatic amount based on system RAM, raise the current shell's memlock limit,
and fall back to `TEST_OPTS="--page-sz normal"` when gigantic pages are not
available.

## Project Layout

Tickoni-owned areas:

- `build.zig`: Zig build graph
- `justfile`: repo-facing developer commands
- `src/app/tickoni/`: supervisor CLI and startup
- `src/tickoni/runtime/`: topology and tile runtime abstractions
- `src/tickoni/tiles/`: Phase 0 payment pipeline tile logic
- `src/tickoni/c_abi/`: narrow C ABI declarations for selected runtime
  primitives
- `doc/`: Tickoni architecture, build, security, testing, observability, and
  product docs

Firedancer-derived areas:

- `src/app/firedancer/`: full C runtime application
- `src/disco/`: common Firedancer tiles and metrics
- `src/discof/`: full Firedancer tiles
- `src/tango/`, `src/util/`, `src/waltz/`, `src/flamenco/`, `src/funk/`:
  supporting C runtime substrate

Avoid Frankendancer-specific paths such as `fdctl`, `fddev`, and `discoh`
unless a task explicitly requires shared legacy behavior.

## Generated Code

After changing `src/disco/metrics/metrics.xml`, run:

```bash
make -C src/disco/metrics metrics
```

After changing `src/flamenco/features/feature_map.json`, run:

```bash
cd src/flamenco/features && make generate
```

After changing protosol proto definitions, run:

```bash
make -C src/flamenco/runtime/tests protobufs
```

Generated outputs are checked into the repository.

## Related Docs

- [Build](./build.md)
- [Build System](./build-system.md)
- [Architecture](./architecture.md)
- [Security](./security.md)
- [Observability](./observability.md)
