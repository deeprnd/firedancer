# Tickoni Interface Contract (Phase 7)

This document freezes the internal-facing interface contract for the
Tickoni runtime surface introduced in migration Phase 5/6.

## 1) Stable CLI Contract (`tickoni`)

### Invocation

`tickoni <SUBCOMMAND> [OPTIONS]`

### Binary-name compatibility

- Canonical binary: `tickoni`
- Compatibility binary: `firedancer` (shimmed alias to `tickoni`)

### Stable global options

- `--config <PATH>`: Load config from TOML path.
- `--version`: Print software version and exit.
- `--help`: Print command help and exit.

### Stable config selectors

- `--testnet`
- `--devnet`
- `--mainnet`
- `--testnet-jito`
- `--mainnet-jito`

### Stable environment compatibility

- Preferred: `TICKONI_CONFIG_TOML`
- Migration shim: `FIREDANCER_CONFIG_TOML` (accepted during migration window)

### Stable subcommands

- `run`
- `run1`
- `configure`
- `monitor`
- `keys`
- `ready`
- `mem`
- `netconf`
- `help`
- `metrics`
- `version`
- `shred-version`
- `watch`
- `add-authorized-voter`
- `set-identity`
- `monitor-gossip`

Subcommand additions/removals are breaking changes and must be reviewed
as interface updates.

## 2) Frozen Build / Script / Artifact Contract

### Build targets

- Canonical validator target: `tickoni`
- CI default target sets must include `tickoni` in:
  - `.github/workflows/tests.yml`
  - `.github/workflows/codeql.yml`
  - `contrib/test/ci_tests.sh` default `TARGETS`

### Artifact path contract

- Canonical runtime binary path pattern:
  - `$(OBJDIR)/bin/tickoni`
- Compatibility alias path:
  - `$(OBJDIR)/bin/firedancer` -> symlink to `tickoni`
  (see shim policy below).

### Script contract

- CI and automation scripts should invoke `tickoni` as the runtime binary
  for validator operations.
- New usages of `make firedancer` or `$(OBJDIR)/bin/firedancer` are not
  allowed outside explicitly documented legacy paths.

## 3) Migration Shim Policy

The only required shim in this phase is:

- Make alias: `firedancer -> tickoni`
  - Location: `src/app/firedancer/Local.mk`
  - Removal date: `2026-12-31`
  - Removal phase: Phase 8 (Legacy Surface Removal)

No additional name-compatibility shims should be introduced without an
explicit removal date in the same change.

## 4) Regression Policy

CI must fail if a change reintroduces removed names/paths or drifts from
the frozen contract above. The enforcement lives in:

- `contrib/lint/check_agave_regressions.sh`
- `.github/workflows/agave_guard.yml`
