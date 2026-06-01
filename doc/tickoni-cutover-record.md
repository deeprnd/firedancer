# Tickoni Migration Cutover Record (Phase 10)

Cutover date: 2026-06-01

This record archives the post-migration steady-state policy for the
Agave-free Tickoni path and the remaining compatibility constraints.

## Final Cutover State

- Canonical runtime binary: `tickoni`
- Compatibility runtime synonym: `firedancer` (alias target to `tickoni`)
- Canonical config env var: `TICKONI_CONFIG_TOML`
- Compatibility config env var: `FIREDANCER_CONFIG_TOML` (deprecated fallback)
- Agave coupling removed from default build/test/workflow paths

## Baseline Coverage Policy

Performance and reliability baselines must be maintained by CI using:

- `.github/workflows/tests.yml` (unit/script/fuzz/integration reliability)
- `.github/workflows/backtest.yml` (ledger replay reliability)
- `.github/workflows/benchmark.yml` (performance regression tracking)
- `.github/workflows/migration_policy.yml` (migration invariants + synonym checks)

Entry points:

- `.github/workflows/on_pull_request.yml`
- `.github/workflows/on_nightly.yml`
- `.github/workflows/on_main_push.yml`

## Guardrails

Regression prevention scripts:

- `contrib/lint/check_agave_regressions.sh`
- `contrib/lint/check_tickoni_policy.sh`

These guards enforce:

- No new Agave/runtime coupling on canonical paths
- No reintroduction of removed legacy workflows/actions
- Tickoni-first identity across packaging and runtime metadata
- Required compatibility synonym invariants for `firedancer`

## Known Constraints

1. `firedancer` runtime naming must remain as a synonym for operator
   compatibility while external automation migrates.
2. Legacy config env fallback (`FIREDANCER_CONFIG_TOML`) remains
   supported with deprecation messaging.
3. Some source tree paths intentionally remain `src/app/firedancer*` to
   preserve upstream sync ergonomics.

## Follow-ups

1. Remove `firedancer` runtime alias only after explicit downstream
   migration sign-off.
2. Remove `FIREDANCER_CONFIG_TOML` fallback after deprecation window
   closes.
3. Keep the cutover record current when CI policy or compatibility
   exceptions change.
