# V2.21.S6 Security Audit

## No-live-effect boundary

The S6 fixture-backed demo path is constrained to deterministic local artifacts:

- manifest preflight requires `expected_no_live_effect = true`
- runner rejects `external_effects_disabled = false`
- blocked/tampered scenarios emit diagnostics rather than normal success artifacts
- CLI verification asserts blocked/tampered diagnostics remain machine-readable

## Current blocked diagnostic codes

- `unsupported_runtime_tier`
- `missing_fixture`
- `stale_manifest`
- `attempted_live_execution`
- `tampered_replay_artifact`
- `tampered_proposal_artifact`
- `missing_isolation_prerequisite`
- `policy_denied`
- `restricted_instrument`
