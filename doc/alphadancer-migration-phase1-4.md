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

