# Firedancer

This repo contains two validator clients:

- **Firedancer** — A fully C-based Solana validator client.
- **Frankendancer** — Legacy Rust/C hybrid validator.

Unless prompted, only focus on Firedancer and avoid Frankendancer
specific parts (fdctl, fddev, discoh).  Focus on Firedancer equivalents
(firedancer-dev, discof).

Firedancer only supports x86-64 on Linux, other targets are not correct
for example ARM due to TSO assumptions.

Topology: `src/app/firedancer/topology.c`.
Tiles: `src/disco`, `src/discof`.

## Building

`make -j` - builds everything
`make -j firedancer-dev` - builds dev validator
`make -j test_blake3` - builds a test

The default make parameters are:
- CC=gcc
- MACHINE=native
- EXTRAS=''

Always isolate build dirs when changing Make params, e.g.:
- `make -j BUILDDIR=clang-fuzz-asan CC=clang EXTRAS="fuzz asan"`
- `make -j BUILDDIR=clang-cov CC=clang EXTRAS=cov`

For Firedancer builds:
- keep a single flat name for BUILDDIR
- never pass arbitrary other make variables
- never invoke raw gcc

## Auto-generated Code

- **Metrics:** After changing `metrics.xml`, run:
  ```bash
  make -C src/disco/metrics metrics
  ```
  Regenerates all files in `src/disco/metrics/generated/` and `book/api/metrics-generated.md`.

- **Features:** After changing `feature_map.json`, run:
  ```bash
  cd src/flamenco/features && make generate
  ```
  Regenerates `fd_features_generated.h` and `fd_features_generated.c`.

- **Protobufs:** After protosol proto definitions change, run:
  ```bash
  make -C src/flamenco/runtime/tests protobufs
  ```
  Regenerates all files in `src/flamenco/runtime/tests/generated/`.

## Code Style

Follow the coding conventions in `CONTRIBUTING.md` when making code changes.

### CLI Tooling Guidance

All developer tooling lives in `justfile` only. Never add dev tool targets to
`config/everything.mk` or any upstream Makefile — those are Firedancer's build
system and must not be modified for our tooling.

**Recipe naming convention:** `category-scope-verb-component`

- **category:** `quality` | `security` | `test`
- **scope:** `format` | `lint` | `codeql` | `gitleaks` | `seccomp` | `proof` | `sanitize` | `unit` | `integration`
- **verb:** `check` | `fix` — tests have no verb
- **component:** `fd` (Firedancer C code) | `tk` (tickoni Zig code) | `all`

Every scope must have `-fd`, `-tk`, and `-all` variants. If a tool only applies
to one component, the other returns `@true` directly in the justfile — not in
the shell script. `-all` always composes both, even if one is a no-op.

Badge-updating aggregators follow `category-check-all` (e.g.,
`quality-check-all`, `security-check-all`) and compose all `-all` variants for
their category.

**Shell scripts** (`contrib/quality.sh`, `contrib/security.sh`) contain only
real implementations. No skip stubs, no `need_cmd` guards, no `|| true`
fallbacks — those are mocks and belong in the justfile if needed. If a command
is in the shell script, it must do real work and fail if the tool is absent.

**Ownership:** `contrib/quality.sh` and `contrib/security.sh` are our files.
`contrib/lint.sh` is upstream Firedancer — do not modify it.
