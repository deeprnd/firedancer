# V2.21.S6 Manifest Contract

## CLI surface

```text
tickoni-supervisor demo investment --json --manifest <path>
tickoni-supervisor demo investment --plain --manifest <path>
```

`tickoni demo` with no scenario or manifest fails closed with usage.

## Manifest fields in use

`src/tickoni/demo/fixtures/demo.manifest.json` currently defines:

- `demo_manifest_version`
- `min_tickoni_version`
- `supported_runtime_tiers`
- `required_isolation_tier`
- `required_isolation_by_tier`
- `required_fixtures`
- `replay_schema_version`
- `policy_schema_version`
- `expected_no_live_effect`

## Tier semantics

Per-tier isolation expectations are explicit:

| Runtime tier | Required isolation |
| --- | --- |
| `linux_full` | `full` |
| `macos_retail` | `retail` |

Legacy `required_isolation_tier` remains as a fallback for tiers without an explicit override.

## Fixture contract

The manifest fixture root is `src/tickoni/demo/fixtures/`.

The current manifest requires:

- `investment_sample.json`

That fixture acts as the entrypoint to the deterministic investment conformance suite.
