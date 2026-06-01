# Alphadancer Migration Plan (Phase 1-4)

This document defines the first four migration phases from Frankendancer/Agave coupling to an Agave-free Alphadancer baseline.

## Scope Freeze

Effective immediately:

1. No new features may be added under Frankendancer-only paths.
2. No new direct references to `agave`, `run-agave`, or Agave-linked build artifacts may be introduced.
3. Solana-client expansion is frozen while this migration is active.

## Phase 1: Define Cut Scope

Cut scope for this phase:

1. Build graph references to Agave submodule artifacts.
2. `run-agave` command wiring in `fdctl`.
3. Frankendancer-only Agave version encoding and release coupling.
4. Frankendancer-specific Agave runtime settings in default config.

## Phase 2: Extract and Isolate Agave Boundary

Agave boundary is isolated behind explicit build/runtime toggles:

1. Build toggle: `FD_WITH_AGAVE` (default disabled).
2. Runtime toggle: existing `development.no_agave`.
3. Command surface: `run-agave` action only present when Agave hosting is enabled.

This keeps behavior for legacy builds while making Agave-free builds first-class.

## Phase 3: Switch Default Runtime/Build to Agave-Free

1. `FD_WITH_AGAVE` defaults to `0`.
2. Default versioning no longer requires Agave metadata.
3. Default path should be the `firedancer` binary/runtime.

## Phase 4: Remove Agave Artifacts and Frankendancer-Specific Config

This phase removes:

1. `agave` submodule declaration.
2. Agave-only make fragments and version coupling.
3. Frankendancer-only Agave config keys and comments.

Legacy opt-in support can be retained only if explicitly needed and gated by `FD_WITH_AGAVE=1`.

## Phase 5: Codebase Pruning and Rename Path

This phase transitions the default runtime surface from Firedancer naming to Tickoni while pruning dead Agave-only entrypoints from the default path:

1. Default build graph excludes `fdctl` and `fddev` make fragments.
2. `run-agave` command sources/wiring are removed from `fdctl`/`fddev`.
3. Primary runtime binary target is renamed from `firedancer` to `tickoni`.
4. A temporary `firedancer` binary alias is retained for compatibility during migration.
5. Default CI build targets are updated to compile `tickoni`.

## Phase 6: Workflow and Naming Convergence

This phase removes remaining migration-era compatibility and legacy naming from workflows and repository structure:

1. Remove or replace remaining `.github/actions/submodule-init` usage in workflows where Agave/submodule setup is no longer required.
2. Update CI/runtime scripts to call `tickoni` directly, then remove the temporary `firedancer` alias target.
3. Rename app paths from `src/app/tickoni` and `src/app/tickoni-dev` to Tickoni-native naming.
4. Complete shared config cleanup by removing residual Frankendancer wording and dead Agave-only fields in config structs/parsers.
5. Re-baseline validation by running full CI-equivalent build/test targets on a writable runner and addressing regressions.

## Phase 7: Interface Stabilization

This phase hardens the new Tickoni surface for internal consumers:

1. Publish a stable CLI contract for `tickoni` (commands, flags, config file compatibility expectations).
2. Freeze and document renamed build targets, scripts, and artifact paths.
3. Add migration shims only where required, with explicit removal dates.
4. Add regression checks that block reintroduction of removed names/paths in CI.

Reference implementation doc: `doc/tickoni-interface-contract.md`.

## Phase 8: Legacy Surface Removal

This phase fully removes compatibility shims once downstream callers are migrated:

1. Delete temporary alias targets and wrappers that still expose `firedancer` naming.
2. Remove obsolete workflows, actions, and scripts tied to Frankendancer-era assumptions.
3. Remove dead code paths guarded only for historical Agave/Frankendancer support.
4. Clean remaining docs/config examples that mention deprecated command paths.

## Phase 9: Tickoni Identity and Packaging

This phase makes Tickoni the canonical project identity in deliverables:

1. Rename release artifacts, container images, and package metadata to Tickoni naming.
2. Update operational docs and deployment playbooks to use Tickoni-only command paths.
3. Ensure telemetry, metrics labels, and runtime identifiers reflect Tickoni naming where safe.
4. Validate upgrade/rollback runbooks against the renamed artifacts.

## Phase 10: Post-Migration Hardening

This phase closes migration risk and establishes steady-state engineering policy:

1. Run full performance and reliability baselines on the Agave-free Tickoni path.
2. Add CI policy checks that prevent new Agave coupling and legacy-name regressions.
3. Archive migration notes into a final cutover record with known constraints and follow-ups.
4. Lift temporary migration freezes and define the new roadmap scope for HFT AI infrastructure work.
