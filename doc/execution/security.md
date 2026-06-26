# Tickoni Security

This document summarizes Tickoni's security model and the repo security
checks exposed through the `justfile`.

Tickoni retains a Firedancer-derived runtime foundation. Agent harness code
should live above that foundation instead of being mixed into low-level
networking, shared-memory channel, tile runtime, or kernel-interface code.

The rule is:

```text
keep agent harness code above the engine boundary unless a reviewed runtime
change is necessary
```

## Security Model

Tickoni assumes agents are not inherently trustworthy.

Security posture:

- agents are untrusted by default
- tools are capability-scoped
- production actions require policy checks
- money-impacting actions require approval
- secrets are never exposed directly to agents
- audit records are immutable
- deleted history is not allowed
- policy decisions are logged
- denied actions are logged
- replay divergence is treated as a serious event

Phase 0 currently runs a synthetic payment pipeline in dev/test mode. It proves
bounded queues, stable event hashes, append-only audit records, replay checks,
observable backpressure, and crash diagnostics. It does not yet grant agents
tool authority or privileged external actions.

## Isolation Boundary

Tickoni follows Firedancer's process-oriented isolation principles. The Phase 0
implementation still runs tiles as in-process Zig threads for spike and test
simplicity, but the architecture remains tile-shaped:

```text
tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
                         \-> tkrepl / tkmetr / tkdiag
```

Each future process tile must have:

- one responsibility
- owned mutable state
- bounded resources
- explicit capabilities
- no shared mutable state outside designated channels
- crash-only failure behavior

Runtime-foundation changes require explicit review. They are not routine
agent-harness implementation work.

## Commands

Security check entrypoints:

- `just security-gitleaks-check-fd`
- `just security-gitleaks-check-tk`
- `just security-gitleaks-check-all`
- `just security-codeql-check-fd`
- `just security-codeql-check-tk`
- `just security-codeql-check-all`
- `just security-seccomp-check-fd`
- `just security-seccomp-check-tk`
- `just security-seccomp-check-all`
- `just security-proof-check-fd`
- `just security-proof-check-tk`
- `just security-proof-check-all`
- `just security-sanitize-check-fd`
- `just security-sanitize-check-tk`
- `just security-sanitize-check-all`
- `just security-check-all`

`security-check-all` currently runs the all-variants in this order:

1. `security-codeql-check-all`
2. `security-gitleaks-check-all`
3. `security-seccomp-check-all`
4. `security-proof-check-all`
5. `security-sanitize-check-all`

The aggregate command is badge-wrapped through
`contrib/readme/run-badged-command.py` so README security status is updated by
the same command developers run locally.

## Scanner Scope

Gitleaks:

- `security-gitleaks-check-fd` scans `src/` with
  `contrib/gitleaks-fd.toml`
- `security-gitleaks-check-tk` scans `src/tickoni` and `src/app/tickoni`

CodeQL:

- the `just` CodeQL recipes are currently no-ops
- `security-codeql-check-fd` documents the blocked local path and points at the
  open Firedancer issue in the `justfile`
- the real implementation remains in `contrib/security.sh codeql-check-fd`
  for when that path is re-enabled

Seccomp:

- `security-seccomp-check-fd` is currently a no-op in the `justfile`
- the real script command is `contrib/security.sh seccomp-check-fd`
- Tickoni-owned Zig code has no active seccomp policy checker yet

Proof:

- `security-proof-check-fd` runs `./contrib/make-j proof`
- `security-proof-check-tk` is currently a no-op because there is no Zig proof
  harness yet

Sanitizers:

- `security-sanitize-check-fd` builds and checks the Firedancer-derived
  `tickoni` target with Clang ASan + UBSan in `build/clang-asan-ubsan`
- `security-sanitize-check-tk` runs `zig build test -Doptimize=ReleaseSafe`

## Local Expectations

Install developer Python tooling before running quality or security gates:

```bash
just python-dev-install
```

The optional wider Python surface is:

```bash
just python-dev-install-all
```

Security tools such as `gitleaks`, `codeql`, and CBMC-related proof tooling must
be installed by the developer or CI image when their corresponding non-no-op
commands are used. Scripts under `contrib/security.sh` intentionally run real
commands and fail if required tools are absent.

## Agent Capability Boundary

Every tool request must resolve to an agent identity, case scope, policy
version, and explicit capability. Model-native function calls and MCP-compatible
requests are untrusted input until the broker validates that envelope.

High-impact actions are proposals routed to a separate privileged executor.
Policy can constrain action type, resource scope, value, rate, environment, and
required approval before any downstream change is executed.

Example capability shape:

```yaml
agent: payment_exception_agent
environment: production

allowed:
  - read_payment_event
  - read_processor_log
  - read_case_history
  - draft_merchant_response
  - propose_retry_path
  - route_case

requires_approval:
  - send_merchant_response
  - retry_payment
  - change_payment_route

denied:
  - release_payout
  - post_ledger_adjustment
  - freeze_account
  - approve_refund
  - delete_audit_record
```

## Related Docs

- [Development](development.md)
- [Tickoni Testing](testing-tickoni.md)
- [Observability](observability.md)
