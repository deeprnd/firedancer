# V2.21.S6 Telemetry Audit

## Observable outputs

The S6 suite currently emits deterministic, reviewable outputs through the CLI:

- JSON suite artifacts for automation / CI
- plain-text artifact summaries for operator inspection
- blocked diagnostic metadata for fail-closed cases

## Artifact references

The emitted artifacts reference committed fixture evidence under:

- `src/tickoni/demo/fixtures/`
- `src/tickoni/test/fixtures/investment/scenarios/`

This keeps the demo path reproducible without requiring live providers or live adapters.
