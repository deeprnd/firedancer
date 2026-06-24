<!--
Increment story template.

Copy this file to doc/position/roadmap/vX.Y.md, replace every VX.Y placeholder,
and fill in each section. Delete HTML comments before committing.

Structure:
  Roadmap section  — product framing, user story, demo, non-goals.
  WBS section      — sub-stories with Tasks and Acceptance criteria.

Sub-story labels: VX.Y.SN
Task labels:      VX.Y.SN.TN   (e.g., V1.2.S3.T1)

Every WBS must include an evidence and quality sub-story (the last one).
Mark any item "N/A — reason" if the increment does not touch that boundary.
-->

# VX.Y: [Title]

**Status: [Planned | Next | Accepted baseline | Done] · Milestone: [M1 | M2 | M3]**

**Epic:** #[github-epic-issue] · **Issue:** #[github-story-issue]

<!-- One paragraph: what this increment builds on and what it closes. -->

---

## Product Intent

<!-- Context and starting point. What open findings or prior increment results
     motivate this scope? What does this increment close or unblock? -->

## User Story

<!-- "As a [actor], I can [action], so that [outcome]." One or two sentences. -->

## What The [User / Operator] Sees

<!-- Bullet list of visible outputs, screens, artifact locations, or UI states
     the actor interacts with after this increment. -->

## Success Demo

<!-- Exact sequence that one offline command must show to close this increment.
     Each bullet is a verifiable scenario, not a description of the feature. -->

- [ ] ...

## Release Gate

<!-- Conditions that must hold before this increment is marked done.
     Reference just targets where possible. -->

- `just test-unit-tk` passes with no unexpected skips
- `just test-integration-tk` passes offline against local mocks
- `just demo-tk` (or the increment-specific command) prints all required scenarios

## Non-Goals

<!-- What is explicitly out of scope for this increment. -->

---

## WBS

<!-- Sub-story naming: VX.Y.SN. Task naming: VX.Y.SN.TN.
     Each sub-story has a Tasks list and an Acceptance list.
     Add one sub-story per material boundary or concern. -->

### VX.Y.S1: [Sub-story title]

**Issue:** #[github-sub-story-issue]

Tasks:

- VX.Y.S1.T1: ...

Acceptance:

- ...

<!-- Repeat for each domain sub-story. Common sub-stories:
     - governed tile topology and link wiring
     - capability envelope and policy boundary
     - audit and hash-chain records
     - replay and source-driven reconstruction
     - agent run envelope and bounds
     - model gateway governance (tkmodl)
     - tool broker and adapter dispatch (tktool / tkadpt)
     - metrics and diagnostics export
     - demo gate and documentation reconciliation
-->

---

### VX.Y.SN: Evidence and quality gate

**Issue:** #[sub-story-issue]

<!-- Required sub-story. Mark inapplicable items "N/A — reason". -->

Tasks:

<!-- Demo and gate -->
- VX.Y.SN.T1: Add a documented local demo command or script that runs offline.
- VX.Y.SN.T2: Maintain a product demo checklist tied to this increment's user story and V1 success metrics.
- VX.Y.SN.T3: Add or update local increment gate commands in the justfile.
- VX.Y.SN.T4: Update phase and increment status in the roadmap file; make non-goals visible in demo materials.

<!-- Fixtures and test data -->
- VX.Y.SN.T5: Add deterministic fixtures for the product flow and each model, tool, adapter, market, portfolio, payment, transfer, and crypto boundary this increment touches.
- VX.Y.SN.T6: Add case or thesis fixture sets and replay capsule samples for the primary flow.
- VX.Y.SN.T7: Add sample configs and sample outputs for any new configuration surface.

<!-- Audit samples -->
- VX.Y.SN.T8: Emit audit output for the material user flow; include policy, destination, venue, wallet, and limit decisions where they apply; produce audit JSONL samples with valid hash chains.
- VX.Y.SN.T9: Produce approval and rejection audit samples where this increment introduces an approval path.

<!-- Metrics and diagnostics -->
- VX.Y.SN.T10: Export metrics and diagnostics for queue, policy, model, tool, adapter, audit, replay, and crash state; produce samples for any new surface.

<!-- Replay -->
- VX.Y.SN.T11: Run replay without external model, broker, payment, trading, crypto, or execution side effects; add replay match samples and divergence test output.

<!-- Blocked flows -->
- VX.Y.SN.T12: Include at least one blocked-flow or intentional divergence fixture.

<!-- Tests and quality -->
- VX.Y.SN.T13: Add focused tests for each schema, guardrail, adapter, and replay path the increment introduces or modifies.
- VX.Y.SN.T14: Add forbidden-shell, forbidden-network, forbidden-direct-adapter, and forbidden-direct-execution tests for any new boundary.
- VX.Y.SN.T15: Add malformed-envelope and malformed-hook fail-closed tests for any new hook or envelope type.
- VX.Y.SN.T16: Add fail-closed validation tests for policy, model, adapter, destination allowlist, and amount/exposure/frequency/holding-period limit configuration.
- VX.Y.SN.T17: Add provider configuration validation tests if the increment introduces or changes a provider configuration surface.
- VX.Y.SN.T18: Add adapter manifest validation tests if the increment introduces or changes an adapter.
- VX.Y.SN.T19: Add API integration tests for external ingestion and partner review endpoints if the increment introduces or changes those boundaries.

Acceptance:

- `just demo-tk` (or the increment-specific command) runs offline and prints all required scenarios.
- Replay produces no live model, broker, payment, trading, crypto, or execution calls.
- At least one blocked-flow or divergence fixture is present and fails as expected.
- Audit, metrics, diagnostics, and replay artifacts are reachable from the demo output.
- All gate commands pass: `just test-unit-tk` and `just test-integration-tk`.

## Evidence Gate

<!--
Answer each question from the Increment Gate Checklist in roadmap/README.md
before marking this increment done.
-->

- What can the user do now that they could not before this increment?
- What changed from the previous increment?
- What is the demo moment?
- Which account, beneficiary, IBAN, wallet, rail, currency, market, venue, asset class, instrument, notional, amount, exposure, and frequency checks are enforced?
- What happens when the user asks for too much money or an instrument is restricted?
- Is execution paper-only, draft-only, sandbox, live, or disabled?
- Which artifacts are needed for later partner trust?
- Which demo command closes the increment?
- Which fixture data covers each model, tool, adapter, and financial boundary?
- Are policy and limit decisions visible in audit output?
- Can replay run without side effects?
- What intentional divergence or blocked-flow example proves failure behavior?
