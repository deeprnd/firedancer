# Retail Runtime Support

This document is the canonical user-facing trust surface for Tickoni retail runtime support.

It explains what a retail user can run today, which binary is the supported product entrypoint, what the supported runtime tiers mean, where artifacts live, how to verify them manually, and which features are intentionally unavailable outside Linux full-runtime mode.

## Supported tiers in V2.21

| Tier | OS / host | Supported in V2.21 | What it is for | What it is not for |
| --- | --- | --- | --- | --- |
| `linux_full` | Linux x86_64 | Yes | Full Tickoni runtime, supervisor flows, deterministic demo, audit/replay evidence | macOS retail UX |
| `macos_retail` | macOS ARM64 / x86_64 | Yes | Deterministic paper/sandbox demo, version/doctor trust surface, audit/replay proof artifacts | Linux throughput parity, shared-memory topology parity, live execution |
| `windows_retail` | Windows | No, belongs to V2.22 | N/A in this epic | Any V2.21 claim of shipped support |
| `container_assisted` / VM-assisted | Hosted or layered environments | Not an official V2.21 primary path | Context that may be documented later | A silently supported parity tier |
| `unsupported` | Any unsupported OS / architecture | Yes, as a fail-closed result | Explicit diagnostics only | Demo or live workflows |

See also: `doc/knowledge/platform-tiers.md`.

## Supported product binary

The supported retail-facing product binary is:

```bash
./zig-out/bin/tickoni
```

The internal/runtime harness binary:

```bash
./zig-out/bin/tickoni-supervisor
```

is still used by tests and lower-level runtime flows, but it is not the primary product trust surface for retail users.

## Core commands

### Version identity

```bash
./zig-out/bin/tickoni --version
```

Expected fields:
- Tickoni version
- build id
- git revision / digest
- OS and architecture
- runtime tier
- isolation tier
- policy schema version
- replay schema version
- demo manifest version
- compiler

### Doctor / host report

```bash
./zig-out/bin/tickoni doctor --plain
./zig-out/bin/tickoni doctor --json
```

These commands are the user-facing host preflight and trust report. They identify the active platform tier and expose degraded-guarantee information on retail tiers.

### Deterministic demo

The deterministic conformance/demo runner is currently implemented in the supervisor binary:

```bash
./zig-out/bin/tickoni-supervisor demo investment --plain --manifest src/tickoni/demo/fixtures/demo.manifest.json
./zig-out/bin/tickoni-supervisor demo investment --json --manifest src/tickoni/demo/fixtures/demo.manifest.json
```

This is acceptable for V2.21 because the retail trust surface is closed by `tickoni --version` + `tickoni doctor` plus the demo evidence artifacts documented below. The product/docs must not claim that live execution or Linux full-runtime parity exists on macOS retail mode.

## Build path vs install path

### Local developer / reviewer build path

Build Firedancer substrate libs and Tickoni binaries:

```bash
just build-fd
just build-tk
```

Generated binaries:
- `zig-out/bin/tickoni`
- `zig-out/bin/tickoni-supervisor`

Generated Firedancer libs used by Tickoni build:
- `build/fd-tickoni-fd/lib/`

### Retail install path in V2.21

V2.21 documents a **user-scoped** install shape. It does **not** require `sudo`.

If a release artifact is unpacked manually, the supported user-scoped target is:

```text
$HOME/.tickoni/bin/tickoni
$HOME/.tickoni/bin/tickoni-supervisor
```

If the user is working from source, the equivalent local build artifacts remain under:

```text
<repo>/zig-out/bin/
```

## Storage locations

The expected user-scoped storage root is:

```text
$HOME/.tickoni/
```

Retail-runtime docs and checks should treat the following as the expected shape:

| Path | Purpose |
| --- | --- |
| `$HOME/.tickoni/bin/` | User-scoped installed binaries |
| `$HOME/.tickoni/demos/` | Demo manifests and fixture bundles |
| `$HOME/.tickoni/evidence/` | Audit/replay/exported proof artifacts |
| `$HOME/.tickoni/logs/` | Local runtime logs if present |
| `$HOME/.tickoni/tmp/` | Temporary local runtime scratch space |

The repo-local source build path (`zig-out/`, `build/`) is a development workspace, not the long-term user evidence location.

## Manual verification path

V2.21 documents a checksum-based manual verification path.

### Verify a release artifact

```bash
sha256sum tickoni-linux-x86_64.tar.gz
sha256sum tickoni-macos-arm64.tar.gz
```

Compare the result against the published SHA256 checksum list for the release.

### Verify a built binary locally

```bash
sha256sum zig-out/bin/tickoni
sha256sum zig-out/bin/tickoni-supervisor
```

### Verify the demo manifest used for evidence generation

```bash
sha256sum src/tickoni/demo/fixtures/demo.manifest.json
```

V2.21 does **not** claim release signatures, attestations, or signed installer metadata unless those assets are actually published alongside the release.

## Update path

V2.21 supports two honest update paths:

### Source build update

```bash
git pull --ff-only
just build-fd
just build-tk
```

### Release artifact update

1. Download the new user-scoped release artifact.
2. Verify the SHA256 checksum.
3. Replace the old binary under `$HOME/.tickoni/bin/`.
4. Re-run:

```bash
$HOME/.tickoni/bin/tickoni --version
$HOME/.tickoni/bin/tickoni doctor --plain
```

## Uninstall path

V2.21 does not require an elevated uninstaller.

### Remove a user-scoped install

```bash
rm -f "$HOME/.tickoni/bin/tickoni"
rm -f "$HOME/.tickoni/bin/tickoni-supervisor"
```

### Remove retail runtime data and evidence

```bash
rm -rf "$HOME/.tickoni/demos"
rm -rf "$HOME/.tickoni/evidence"
rm -rf "$HOME/.tickoni/logs"
rm -rf "$HOME/.tickoni/tmp"
```

If the user wants a full reset of the user-scoped retail runtime footprint:

```bash
rm -rf "$HOME/.tickoni"
```

### Remove a source-build workspace only

```bash
rm -rf zig-out build .zig-cache .zig-global-cache
```

## Retail-runtime privacy defaults

- Installer telemetry is **disabled by default**.
- Demo, version, and doctor flows do **not** require outbound telemetry.
- Retail evidence is local/offline by default unless a later explicit product decision approves opt-in diagnostics or managed export.
- V2.21 docs must not imply that analytics, usage telemetry, or remote collection are required for the macOS retail path.

## Live execution defaults

Consumer retail modes are **paper/sandbox/no-live-effect** by default.

That means V2.21 does **not** permit or claim support for:
- live trading
- live payments
- live crypto transfers
- TigerBeetle writes
- privileged money-moving execution
- hidden credential-driven side effects during install or demo

## Unsupported features / explicit non-goals

V2.21 does **not** ship or claim:
- macOS parity with Linux full-runtime throughput
- shared-memory topology parity on macOS
- seccomp/Landlock parity on macOS
- CaseOps UI tier/degraded-guarantee display in this epic
- Windows retail runtime support (owned by V2.22)
- silent fallback from unsupported hosts into an implied supported tier
- signed release assets unless actually published

## Trust surfaces that matter in V2.21

### CLI
- `tickoni --version`
- `tickoni doctor --plain`
- `tickoni doctor --json`

### Audit / replay / demo proof
- deterministic demo output
- audit JSONL sample
- replay capsule sample
- blocked-flow sample
- conformance comparison result

### CaseOps
CaseOps platform-tier display is **deferred** in V2.21. The docs must say so explicitly. The shipped trust surface for this epic is CLI + audit/replay/demo evidence, not a completed CaseOps UI story.

## Evidence outputs produced by the deterministic demo flow

The V2.21 evidence set includes:
- version output sample
- doctor plain-text sample
- doctor JSON sample
- successful demo output sample
- blocked-flow output sample
- audit JSONL artifact path
- replay capsule artifact path
- conformance comparison result

The canonical index for those artifacts is:

- `doc/execution/V2.21.S7/evidence-index.md`

## Minimum reviewer flow

A reviewer should be able to do the following without `sudo`:

```bash
just build-fd
just build-tk
./zig-out/bin/tickoni --version
./zig-out/bin/tickoni doctor --plain || true
./zig-out/bin/tickoni-supervisor demo investment --plain --manifest src/tickoni/demo/fixtures/demo.manifest.json
```

Expected reviewer outcome:
- active runtime tier is visible
- isolation tier is visible
- deterministic paper/sandbox proof runs
- live execution remains disabled
- evidence artifacts can be inspected locally
