# V2.21.S6 Conformance Artifacts

## Artifact schema

The code-backed schema lives in:

- `src/tickoni/demo/conformance.zig`
- `src/tickoni/demo/diagnostic.zig`
- `src/tickoni/demo/comparator.zig`
- `src/tickoni/demo/runner.zig`
- `src/tickoni/demo/substitution.zig`

Each emitted artifact includes:

- `manifest_id`
- `manifest_version`
- `tickoni_version`
- `runtime_tier`
- `isolation_tier`
- `fixture_set_id`
- `scenario`
- `normalized_event_hash`
- `policy_outcome`
- `proposal_hash`
- `audit_jsonl_path`
- `audit_jsonl_sha256`
- `replay_capsule_path`
- `replay_capsule_sha256`
- `replay_result`
- optional `blocked_diagnostic`
- `external_effects_disabled`

## Suite scenarios

The current fixture-backed suite covers:

| Scenario | Outcome | Source fixture |
| --- | --- | --- |
| `allowed` | allow | `fixture_audit_allowed_2000.jsonl`, `fixture_replay_capsule.json` |
| `oversized_blocked` | deny | `fixture_replay_capsule_oversized_25000.json` |
| `restricted_instrument` | deny | `fixture_replay_capsule_restricted_soxl.json` |
| `tampered_replay` | fail-closed diagnostic | `fixture_replay_capsule_tampered_paper_fill.json` |

## Comparator rules

The comparator treats these as deterministic-equivalence fields:

- manifest id/version
- Tickoni version
- fixture set id
- scenario
- normalized event hash
- policy outcome
- proposal hash
- audit JSONL hash
- replay capsule hash
- replay result
- `external_effects_disabled`

It intentionally ignores runtime-only differences such as `runtime_tier` and `isolation_tier` when comparing Linux full vs macOS retail artifacts.
