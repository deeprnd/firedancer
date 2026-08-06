# V2.21.S7 Security Audit

## Scope

This audit checks the V2.21 retail runtime closure story against:
- `doc/execution/security.md`
- `doc/execution/retail-runtime-support.md`
- `doc/execution/V2.21.S7/quality-gate.md`
- generated evidence snapshots under `doc/execution/V2.21.S7/`

It also records the focused security verification actually run for this story.

## Verification run

### 1. Secret scanning
Command:

```bash
just security-gitleaks-check-tk
```

Result: **PASS**
- `gitleaks tk` reported `no leaks found`
- `gitleaks app/tickoni` reported `no leaks found`

### 2. Zig safety/sanitizer lane
Command:

```bash
just security-sanitize-check-tk
```

Result: **PASS**
- exited 0
- this is the documented ReleaseSafe Zig security lane for Tickoni-owned code

## Checklist

### No elevated permissions
**Status:** PASS

The retail runtime guide documents only user-scoped paths (`$HOME/.tickoni/...`) and explicit no-`sudo` install/update/uninstall flows.

Evidence:
- `doc/execution/retail-runtime-support.md`
- `doc/execution/security.md` (`No Elevated Permissions`)

### Live execution disabled in retail modes
**Status:** PASS

The retail guide explicitly states that consumer retail modes are paper/sandbox/no-live-effect by default and do not support live trading, live payments, live crypto transfers, TigerBeetle writes, or privileged money-moving execution.

Evidence:
- `doc/execution/retail-runtime-support.md`
- `doc/execution/V2.21.S7/doctor-json-sample.json`
- `doc/execution/V2.21.S7/blocked-flow-sample.txt`

### Manual verification route is explicit
**Status:** PASS

The retail guide documents SHA256-based manual verification for release artifacts, built binaries, and the manifest used to generate deterministic evidence.

Evidence:
- `doc/execution/retail-runtime-support.md`

### Unsupported/deferred work is not hidden
**Status:** PASS

The docs now say explicitly that V2.21 does not claim:
- macOS throughput parity with Linux full runtime
- shared-memory topology parity on macOS
- CaseOps UI tier/degraded-guarantee display in this epic
- Windows retail support (belongs to V2.22)
- signed release assets unless they are actually published

Evidence:
- `doc/execution/retail-runtime-support.md`
- `doc/knowledge/platform-tiers.md`
- `doc/execution/V2.21.S7/quality-gate.md`

### Secrets are not required for install/demo evidence generation
**Status:** PASS

The retail path is documented to avoid broker/payment/crypto/live-provider credentials during install and deterministic demo flows.

Evidence:
- `doc/execution/retail-runtime-support.md`
- `doc/execution/V2.21.S7/demo-json-sample.json`

### Fail-closed blocked flow exists
**Status:** PASS

The evidence packet includes a captured stale-manifest failure proving the deterministic demo path blocks unsupported or stale inputs instead of silently degrading.

Evidence:
- `doc/execution/V2.21.S7/blocked-flow-sample.txt`
- `doc/execution/V2.21.S7/conformance-result-summary.json`

## Conclusion

V2.21.S7 satisfies the story-level security closure requirements for the retail runtime trust surface:
- user-scoped / no-sudo documented path
- explicit no-live-effect defaults
- manual verification route
- fail-closed blocked-flow evidence
- no hidden claim of UI/platform/support work that does not exist
- focused secret scan and Zig ReleaseSafe lane both passed
