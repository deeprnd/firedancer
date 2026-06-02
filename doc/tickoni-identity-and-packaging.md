# Tickoni Identity and Packaging (Phase 9)

This document defines the canonical identity for build/release deliverables
while retaining `firedancer` runtime compatibility during migration.

## Canonical Deliverable Identity

- Runtime binary: `tickoni`
- Runtime compatibility alias: `firedancer` -> `tickoni`
- Primary build target: `tickoni`
- Container workspace path: `/data/tickoni`
- Container image examples: `tickoni-gcc:<version>`
- Release tag prefix: `tickoni-v<semver>`

Compatibility:
- Legacy `v<semver>` tags may be emitted as aliases.
- Legacy `firedancer` runtime invocation remains supported as a synonym.

## Packaging and Metadata Sources

- Release/version bump script:
  - `contrib/tag-release.py`
  - reads/writes `src/app/firedancer/version.mk`
  - emits canonical `tickoni-v<semver>` tags
- Container build references:
  - `contrib/containers/*.dockerfile`
  - `contrib/containers/README.md`

## Operational Command Paths

Operational docs and playbooks should use `tickoni` command paths by default.

Examples:
- `tickoni configure init all --config <path>`
- `tickoni run --config <path>`
- `tickoni mem --mainnet`

Compatibility note:
- `firedancer` may still be used where migration is incomplete.

## Telemetry and Runtime Identifier Policy

Where safe, runtime-emitted identifiers should use Tickoni naming:

- CLI version output uses Tickoni runtime version symbols.
- GUI/RPC/bundle runtime version identity uses Tickoni version symbols.
- SARIF tool identity for TSA output uses Tickoni naming.

Legacy symbol aliases may remain for ABI compatibility.

## Runbook Validation (Upgrade / Rollback)

Before publishing a release:

1. Build canonical and compatibility entry points:
   - `make -j tickoni`
   - `make -j firedancer`
2. Verify compatibility alias:
   - `build/<...>/bin/firedancer --version`
   - `build/<...>/bin/tickoni --version`
3. Verify config env compatibility:
   - `TICKONI_CONFIG_TOML=<path> tickoni <cmd>`
   - `FIREDANCER_CONFIG_TOML=<path> tickoni <cmd>` (deprecation warning expected)
4. Verify CI guard:
   - `bash contrib/lint/check_agave_regressions.sh`

Rollback guidance:
- If downstream tooling expects legacy names, use the `firedancer` alias
  while updating automation to canonical `tickoni` paths.
