<!--
Thanks for the PR. Please fill this out to speed up review.

Describe the change in terms of runtime behavior, isolation, observability,
auditability, replay, and performance when relevant.

Tips:
- Link issues with "Closes #123" / "Fixes #123"
- Keep scope focused; split unrelated changes into separate PRs
-->

# Summary

- Renames tile-local `schema.zig` files in `tiles/audit`, `tiles/model`, and `tiles/adapter`
  to `types.zig` or `messages.zig` where they define tile-owned request/response types
  rather than canonical cross-tile contracts.
- Updates all build.zig module imports, `mod.zig` re-exports, test blocks, and downstream
  consumer files (`backend.zig`, `run.zig`, `validator.zig`, `mock.zig`, `fixtures.zig`,
  `codec.zig`) to reference the new module names.
- Adds a Source-Tree Guide to `doc/execution/contribution/tickoni.md` documenting where
  runtime code, canonical contracts, codecs, tile types, scenarios, fixtures, and test
  support belong, plus naming rules for tile-local files.
- No functional or behavioral changes — purely a rename and documentation addition.

## Type of change

- [ ] ✨ New feature
- [ ] 🐛 Bug fix
- [x] 🧹 Refactor (no functional change)
- [ ] ⚡ Performance improvement
- [x] 📚 Documentation
- [ ] 🧪 Tests
- [ ] 🔧 Build/CI/DevEx
- [ ] 🛡️ Security fix
- [ ] ⏪ Revert

## Related work

- Issue(s): #687 — V1.14.S3: Normalize Tickoni source ownership and naming
- Epic: V1.14 — Firedancer Process And Shared-Memory Topology
- Notes: Part of the source-tree migration work in V1.14; follows V1.14.S1/S2 and
  precedes V1.14.S4/S5 which handle further restructuring.

## Risk & impact

- **Low.** This PR renames files and updates internal imports; no public API surface,
  runtime behavior, audit records, replay output, or financial semantics are affected.
- The only consumer-visible change is the contributor documentation (Source-Tree Guide).
- Existing public tile module exports (`AdapterOperation`, `FixtureBackendError`,
  `FixtureAdapter`, `audit_schema_version`, `SamplingParams`, `TkModlConfig`,
  `TkModlDecision`, etc.) remain available through `mod.zig` re-exports.

## How to test

1. `just test-unit-tk` — confirms all renamed modules still compile and unit tests pass.
2. `just test-integration-tk` — confirms integration tests pass with the renamed imports.
3. Verify no `schema.zig` file remains under `tiles/audit/`, `tiles/model/`, or `tiles/adapter/`:
   `git grep -l 'schema\.zig' src/tickoni/tiles/` should return zero results.

## Runtime / contract changes (if applicable)

- [x] No runtime/contract change
- [ ] Event/tool/policy contract changed and docs/comments are updated
- [ ] Tile/topology/runtime wiring changed and docs/comments are updated
- [ ] Metrics/audit/replay output changed and docs are updated

## Generated code / artifacts (if applicable)

- [x] No generated artifacts changed
- [ ] Metrics regenerated (`make -C src/disco/metrics metrics`)
- [ ] Feature map regenerated (`cd src/flamenco/features && make generate`)
- [ ] Protobufs regenerated (`make -C src/flamenco/runtime/tests protobufs`)

## Build / config / docs changes (if applicable)

- [ ] No env/config change
- [ ] Firedancer build/runtime config updated
- [ ] `justfile`/tooling updated
- [ ] README updated
- [x] Other project docs updated

## Firedancer scope (if applicable)

<!-- Most PRs should avoid touching Firedancer core/upstream-derived code unless necessary. -->

- [x] No Firedancer core/upstream-derived code changed
- [ ] Firedancer-facing integration changed only
- [ ] Firedancer core/upstream-derived code changed; rationale and scope are documented below
- [ ] x86-64 Linux / Firedancer assumptions considered where relevant
- [ ] Upstream Firedancer issue/PR created or updated; links are documented below

### Firedancer notes

<!-- If Firedancer code changed, explain why it was necessary, what was touched, whether an upstream sync/divergence risk exists, and link any upstream Firedancer issue/PR. -->

N/A — this project uses Tickoni (Zig financial event runtime), not Firedancer core code.

# Checklist

## Implementation

- [x] Scope is limited to the intended change
- [x] Code follows project conventions and style guidelines
- [ ] No secrets/tokens/sensitive data included (keys, DB creds)
- [x] Throughput, control, and isolation impact considered

## Tests

<!-- Check what applies and include links to CI runs if useful. -->

- [ ] Tests are not required for this change (explain below)
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] E2E tests added/updated
- [x] Existing tests updated to reflect behavior changes
- [ ] `just tests-all` command executed successfully
- [x] Relevant checks pass locally and/or in CI

### If tests were not added, explain why

Existing unit and integration tests cover the renamed modules through their
public `mod.zig` exports. The rename is transparent to callers — no new
test cases are needed.

## Observability / operations (if applicable)

- [ ] Logging is sufficient for troubleshooting
- [ ] Metrics / audit / replay impact considered
- [ ] Runbook/dashboard/alert impact considered

## Security & privacy (if applicable)

- [ ] Capability/policy/input validation reviewed
- [ ] Dependency/tooling changes reviewed for risk
- [ ] No sensitive data exposure introduced

## Release notes

- [x] No release note needed
- [ ] Release note provided below

### Release note (if needed)

<!-- One sentence in user-facing language. -->
