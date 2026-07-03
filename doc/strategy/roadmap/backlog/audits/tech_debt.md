# Tech Debt Tasks

Readable backlog for small cleanup work in the Tickoni runtime and supervisor.

## 1. Extract sandbox defaults into named constants

**Files:** `src/tickoni/runtime/sandbox.zig`

**Task:** Replace hardcoded sandbox defaults such as `65534`, `64`, `1 << 30`,
and `1 << 28` with named constants. If there are standard sizes the runtime
will reuse, define them once and reference them from `SandboxConfig` and tests.

**Clarification:** the consts need to be "global" for tickoni and reused across all tikoni code - maybe under commons.zip? essentially any << operations that calculate on fly one of the 8mb->>8gb need to be defined and reused.

**Done when:**

- `SandboxConfig` defaults use shared constant names.
- Tests assert against the shared constants instead of repeating literals.

## 2. Replace numeric tile phases with an enum

**Files:** `src/tickoni/runtime/topology.zig`

**Task:** Replace `TileDescriptor.phase: u8` with a dedicated enum for the tile
plan phases (`core`, `case`, `agent`, `api`, `exec`) so the topology is typed
and self-explanatory.

**Clarification:**
- Keep roadmap phases in docs/backlog.
- Remove `Phase 0/1/2/3/4` language from product structs.
- Either:
  1. remove `TileDescriptor.phase` entirely if it is only decorative; or
  2. rename it to a stable product concept like `layer`, `domain`, `capability`, or `boundary`.

The current enum names `.core`, `.case`, `.agent`, `.api`, `.exec` are closer to a product architecture concept, but the name `phase` and numeric mapping `0..4` make it smell like roadmap state leaking into runtime code.

**Done when:**

- `TileDescriptor.phase` is an enum, not a raw integer.
- Comments no longer need to explain what `0..4` means.

## 3. Stop repeating raw tile-id strings in topology tests

**Files:** `src/tickoni/runtime/topology.zig`

**Task:** Update tests like `TileId equality` to use shared tile-id constants
instead of repeating `"tknorm"` and `"tkdedu"` string literals inline.

**Done when:**

- Topology tests use shared constants or helpers for known tile ids.
- The same tile id is not duplicated as raw text in multiple assertions.

## 4. Use shared constants for sandbox limit tests

**Files:** `src/tickoni/runtime/sandbox.zig`

**Task:** The test for minimum address-space limits should reference named size
constants instead of open-coded shifts like `1 << 28`.

**Done when:**

- Memory-size tests use shared constants.
- The file has one clear source of truth for sandbox size defaults.

## 5. Rework the busy-wait sleep in shared-memory consumer loops

**Files:** `src/tickoni/runtime/shm_link.zig`,
`src/tango/mcache/fd_mcache.h`, `src/disco/stem/fd_stem.c`

**Task:** Review `Consumer.consume()` and related loops that call
`process.sleepNanos(100_000)` while polling for data. Compare the implementation
against Firedancer's fragment-consumer path before changing it.

Firedancer's hot shared-memory receive path does not use a fixed nanosleep for
normal mcache polling. `FD_MCACHE_WAIT` in `src/tango/mcache/fd_mcache.h` polls
up to `poll_max`, uses `FD_SPIN_PAUSE()` between polls, and times out so the
run loop can do housekeeping. `src/disco/stem/fd_stem.c` similarly polls input
mcaches and uses `FD_SPIN_PAUSE()` when backpressured. Sleep/yield behavior
does exist elsewhere, such as `fd_cnc_wait()` for OS-friendly command/control
waiting, but that is not the hot fragment-consumer pattern.

Replace the Tickoni fixed sleep with a deliberate wait strategy that follows
the Firedancer pattern where appropriate: bounded polling, spin pause or a
Tickoni wrapper around it, explicit housekeeping/stop checks, and measured
backpressure/idle counters.

**Done when:**

- The consumer loop no longer relies on an unexplained fixed sleep.
- The code or task notes cite the Firedancer behavior that the Tickoni loop is
  intentionally following or intentionally not following.
- The chosen wait behavior is documented in code comments or tests.

## 6. Reuse Firedancer-backed workspace constants where appropriate

**Files:** `src/tickoni/c_abi/wksp.zig`

**Task:** Review `shmem_normal_page_sz: usize = 4096` and use the shared
Firedancer value if the runtime is meant to follow the same workspace page-size
contract. Keep a local constant only if there is a clear boundary reason.

**Done when:**

- The page-size value comes from the correct shared source of truth, or
- The file documents why Tickoni intentionally keeps its own constant.

## 7. Remove payment-pipeline knowledge from the generic supervisor

**Files:** `src/app/tickoni/supervisor.zig`

**Task:** Replace hardcoded tile-id dispatch in `snapshotProcessMetrics()` and
the named payment-pipeline thread spawning in `startPaymentPipeline()` with a
registry-driven approach. The supervisor should stay generic; payment-specific
field names and tile behavior should live in payment-pipeline code, not in the
generic process supervisor.

**Done when:**

- Supervisor logic does not branch on tile ids with `if/else` chains.
- Tile startup and metric collection are driven by a registry or descriptor
  table.
- Payment-specific metrics/config are moved out of generic supervisor types.

## 8. Make `tile_process` own live heartbeat and halt handling

**Files:** `src/tickoni/runtime/tile_process.zig`, `src/app/tickoni/tile_main.zig`, `src/tickoni/tiles/payment_pipeline/process.zig`

**Task:** Refactor process-mode tile work so the generic lifecycle keeps
heartbeating and checking for HALT while tile work is still running. The
current `run()` path heartbeats once, signals `RUN`, calls `work`
synchronously, and only heartbeats again after `work` returns. That makes a
long-running or blocked tile look dead even when it is alive, and pushes halt
responsiveness into tile-specific loops instead of the generic process
lifecycle.

**Done when:**

- [ ] A process-mode tile continues to advance CNC heartbeats while its work is
      still in progress.
- [ ] HALT handling for normal tile execution is owned by the generic
      `tile_process` lifecycle instead of requiring each tile implementation to
      poll for it independently.
- [ ] Tests cover a long-running or multi-step tile work path and prove the
      tile remains heartbeating until it halts or finishes.

## 9. Make the BOOT-to-RUN transition halt-safe

**Files:** `src/tickoni/runtime/tile_process.zig`, `src/app/tickoni/supervisor.zig`, `src/tickoni/test/integration/test_process_topology.zig`

**Task:** Remove the documented boot-time stop race in process mode. Today a
supervisor HALT sent during child boot can be clobbered by the child's
unconditional `RUN` signal. The lifecycle should preserve a supervisor stop
request sent during boot instead of relying on caller timing to avoid the race.

**Done when:**

- [ ] `tile_process.run()` no longer blindly overwrites a pre-existing HALT
      with `RUN`.
- [ ] A boot-time supervisor stop request causes the child to exit cleanly
      instead of entering normal work and waiting on upstream progress.
- [ ] Process-mode test coverage reproduces the race and proves it is fixed.

## 10. Make CPU placement validation ownership explicit

**Files:** `src/tickoni/runtime/topology.zig`, `src/tickoni/runtime/cpu_placement.zig`, `src/tickoni/runtime/tile.zig`, `src/tickoni/test/integration/test_process_cpu_placement.zig`

**Task:** Consolidate CPU placement validation behind one explicit runtime
boundary. Static placement conflicts, host-aware availability checks, and
effective placement storage are split across different modules with overlapping
ownership. Refactor the API so callers can tell whether they are performing
structural-only validation or full fail-closed runtime validation.

**Done when:**

- [ ] The public API makes the difference between structural placement
      validation and host-aware placement validation explicit.
- [ ] Malformed and unavailable CPU ids fail through the documented owner path,
      not by call-order convention.
- [ ] Tests cover duplicate placement conflicts, malformed ids, and
      unavailable ids through the intended validation entrypoints.

## 11. Fail closed on unsupported multi-link process topologies

**Files:** `src/tickoni/runtime/launch_spec.zig`, `src/app/tickoni/supervisor.zig`, `src/app/tickoni/tile_main.zig`, `src/tickoni/test/integration/test_process_topology.zig`

**Task:** Align the process-mode launch contract with the generic topology
graph. `Topology` allows arbitrary channel graphs, but `LaunchSpec` currently
has only one `input_link` and one `output_link`, and supervisor selection is
effectively last-match-wins. Replace that silent truncation with explicit
validation for the supported cardinality, or deliberately extend the launch
contract if process mode must support fan-in or fan-out now.

**Done when:**

- [ ] Process-mode startup does not silently discard extra input or output
      links for a tile.
- [ ] Unsupported fan-in or fan-out fails with a clear error before any child
      process is spawned, unless the launch contract is deliberately extended
      to represent multiple links.
- [ ] Tests cover at least one multi-input or multi-output topology and assert
      the chosen behavior.

## 12. Type tile-plan phases end to end

**Files:** `src/tickoni/runtime/tile.zig`, `src/tickoni/runtime/topology.zig`, `src/app/tickoni/topologies.zig`, `src/tickoni/test/integration/test_process_cpu_placement.zig`, `src/tickoni/test/integration/test_process_demo_parity.zig`

**Task:** Replace raw integer phase values in the generic runtime descriptor
and product topology definitions with a dedicated enum for the documented tile
plan phases (`core`, `case`, `agent`, `api`, `exec`). This removes the current
integer drift risk between topology declarations and the documented tile plan.

**Done when:**

- [ ] `TileDescriptor.phase` is a named enum rather than a raw `u8`.
- [ ] Product topology definitions and related tests assign named phases
      instead of raw integers.
- [ ] Validation or tests fail if a topology attempts to encode an unknown
      phase value.

## 13. Align crash-reason reporting with implemented supervisor checks

**Files:** `src/tickoni/runtime/tile.zig`, `src/app/tickoni/supervisor.zig`, `src/tickoni/test/integration/test_process_topology.zig`

**Task:** Align the generic crash taxonomy with the supervisor behavior that
actually exists. `CrashReason.cnc_fail` is part of the public runtime status
model, but the current process-mode supervisor only classifies exit-code and
signal-style failures. Either wire CNC signal or heartbeat failure into the
implemented monitoring path, or remove/de-scope the unused crash reason until
that detection exists.

**Done when:**

- [ ] Every retained `CrashReason` value can be produced by an implemented
      supervisor path.
- [ ] The code clearly documents whether CNC signal or heartbeat failure is
      classified today or intentionally deferred.
- [ ] Tests cover each retained crash classification that process mode can
      emit.

## 14. Define one runtime hash-boundary contract

**Files:** `src/tickoni/tiles/case/mod.zig`, `src/tickoni/schema/consumer_money/drift.zig`, `src/tickoni/tiles/replay/mod.zig`, `src/tickoni/tiles/model/backend.zig`, `src/tickoni/tiles/model/run.zig`, `src/tickoni/tiles/payment_pipeline/runtime.zig`, `src/tickoni/schema/consumer_money/thesis.zig`, `src/tickoni/schema/consumer_money/basket.zig`, `src/tickoni/codec/audit/hash.zig`

**Task:** Define and apply an explicit hash-boundary rule for runtime-facing
stable identifiers, replay lookup keys, proposal/result hashes, and local-only
lightweight hashes. The codebase currently mixes Firedancer-backed SipHash,
Wyhash, and ad hoc byte mixing without a clear contract for when each is
allowed. Move stable runtime identifiers to the shared boundary unless a
different primitive is explicitly justified.

**Done when:**

- [ ] Runtime-facing hash sites either use the shared Firedancer-backed hash
      boundary or clearly justify a different primitive for that use case in
      code comments or module docs.
- [ ] The codebase has one obvious source of truth for canonical hashes,
      replay lookup hashes, proposal/result hashes, and lightweight local/test
      hashes.
- [ ] `deriveSyntheticRunId()` and any retained stable runtime hash helper use
      explicit domain/version constants instead of unexplained local hash
      choices.
- [ ] Tests prove the chosen runtime hash derivations stay deterministic and
      change only when the intended inputs change.

## 15. Remove production dependencies on test fixtures and mocks

**Files:** `src/tickoni/tiles/adapter/backend.zig`, `src/tickoni/tiles/model/backend.zig`, `src/tickoni/tiles/agent/mod.zig`, `src/tickoni/tiles/tool/mod.zig`, `src/tickoni/schema/consumer_money/trade_ticket.zig`, `src/tickoni/test/mocks/mock_adapter.zig`, `src/tickoni/test/mocks/mock_model.zig`, `src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig`

**Task:** Move test-only mocks and fixture-backed defaults out of production
tile and schema modules. Production modules should depend on explicit backend
interfaces or fixture-neutral implementations; test modules should inject mock
or fixture variants from `src/tickoni/test/**`.

**Done when:**

- [ ] No production module under `src/tickoni/tiles/**` or
      `src/tickoni/schema/**` imports `mock_*` or `fixture_*` modules.
- [ ] Mock and fixture backends are wired only from test/demo build modules.
- [ ] Unit and integration tests still cover mock-backed and fixture-backed
      paths through explicit test-only injection.

## 16. Split schema contracts from domain services

**Files:** `src/tickoni/schema/consumer_money/thesis.zig`, `src/tickoni/schema/consumer_money/basket.zig`, `src/tickoni/schema/portfolio/portfolio.zig`, `src/tickoni/schema/consumer_money/drift.zig`, `src/tickoni/tiles/policy/mod.zig`

**Task:** Move behavior-heavy domain services such as thesis normalization,
basket screening/allocation, affordability checks, and drift generation out of
canonical schema modules or clearly separate them behind domain-service modules.
Keep schema modules focused on cross-tile data contracts and versioned payload
types.

**Done when:**

- [ ] Schema modules expose contract types, constants, and minimal accessors
      only, or document an explicit exception.
- [ ] Domain behavior lives in tile-owned or domain-service modules with clear
      owners.
- [ ] Existing tests are relocated or renamed so contract tests and behavior
      tests are easy to distinguish.

## 17. Make `tkpoly` the clear policy authority

**Files:** `src/tickoni/tiles/policy/mod.zig`, `src/tickoni/schema/consumer_money/trade_ticket.zig`, `src/tickoni/schema/consumer_money/basket.zig`, `src/tickoni/schema/portfolio/portfolio.zig`, `src/tickoni/tiles/agent/mod.zig`

**Task:** Consolidate finance-native policy outcomes, guardrails, and blocked
scope derivation behind `tkpoly` instead of spreading policy mutation across
schema and agent helpers. `tkpoly` should own policy decisions; schemas should
carry the resulting fields.

**Done when:**

- [ ] Policy outcome enums and blocked-scope decision helpers have one owner.
- [ ] Trade-ticket schema code does not apply policy decisions itself.
- [ ] Agent code requests a `tkpoly` decision instead of mutating proposal
      policy fields directly.

## 18. Make tile messages serializable boundary contracts

**Files:** `src/tickoni/tiles/adapter/messages.zig`, `src/tickoni/tiles/model/messages.zig`, `src/tickoni/tiles/tool/mod.zig`, `src/tickoni/runtime/link/types.zig`

**Task:** Replace process-local pointer and slice-heavy tile messages with
bounded, serializable request/response contracts suitable for process and
shared-memory boundaries. Pointers and caller-owned slices may remain in
internal helpers, but not in cross-tile messages.

**Done when:**

- [ ] `AdapterRequest` no longer carries a raw pointer to `TradeTicket`.
- [ ] `TkModlRequest` and provider messages have bounded owned or encoded
      fields at tile boundaries.
- [ ] Tests prove representative messages can round-trip through the selected
      tile-boundary encoding.

## 19. Align declared product topologies with runnable entrypoints

**Files:** `src/app/tickoni/topologies.zig`, `src/app/tickoni/main.zig`, `src/app/tickoni/tile_main.zig`, `src/app/tickoni/supervisor.zig`

**Task:** Clarify which topology definitions are runnable product surfaces and
which are future architectural declarations. Either add runnable entrypoints for
declared workflows such as `investmentWorkflow()`, or mark them as non-runnable
plans so operators and tests do not infer unsupported runtime behavior.

**Done when:**

- [ ] Every public topology has an explicit status: runnable, test-only, or
      planned.
- [ ] CLI commands and supervisor paths support all runnable topologies.
- [ ] Tests fail if a runnable topology contains tiles with no process/thread
      dispatch path.

## 20. Decouple the supervisor from one concrete topology shape

**Files:** `src/app/tickoni/supervisor.zig`, `src/app/tickoni/topologies.zig`, `src/tickoni/runtime/tile.zig`, `src/tickoni/tiles/payment_pipeline/mod.zig`

**Task:** Replace fixed tile-count assertions and index-based startup with
descriptor-driven tile registration. The app supervisor should not need to know
that the payment pipeline has exactly eight tiles or which function lives at
each index.

**Done when:**

- [ ] Supervisor startup does not assume `topo.tiles.len == 8`.
- [ ] Tile run functions are selected through a registry or descriptor table.
- [ ] Reordering topology tiles does not require changing supervisor control
      flow.

## 21. Normalize tile phase naming and values

**Files:** `src/tickoni/runtime/tile.zig`, `src/app/tickoni/topologies.zig`, `src/tickoni/runtime/topology.zig`

**Task:** Resolve the mismatch between documented phase meanings and product
topology assignments. Replace raw numeric phases with named phases and update
the current topology so `tkcase`, agent, model, tool, adapter, API, and exec
tiles use the intended names consistently.

**Done when:**

- [ ] Phase assignments use named enum values, not raw integers.
- [ ] `tkcase` and agent-harness tiles match the documented phase plan.
- [ ] Topology tests assert semantic phase names rather than numeric values.

## 22. Standardize tile module structure

**Files:** `src/tickoni/tiles/agent/mod.zig`, `src/tickoni/tiles/policy/mod.zig`, `src/tickoni/tiles/replay/mod.zig`, `src/tickoni/tiles/tool/mod.zig`, `src/tickoni/tiles/case/mod.zig`, `src/tickoni/tiles/disp/mod.zig`, `src/tickoni/tiles/model/*`

**Task:** Bring mature tile modules into the documented `mod/messages/types/
backend/validator/run/codec` shape where they own messages, backend variants,
validation, or orchestration. Keep placeholder tiles small, but avoid large
multi-responsibility `mod.zig` files.

**Done when:**

- [ ] Tiles with request/response contracts have `messages.zig`.
- [ ] Tiles with backend variants have `backend.zig`.
- [ ] Tiles with orchestration or validation have `run.zig` and
      `validator.zig` where appropriate.

## 23. Remove payment-domain fields from generic launch specs

**Files:** `src/tickoni/runtime/launch_spec.zig`, `src/app/tickoni/supervisor.zig`, `src/tickoni/tiles/payment_pipeline/process.zig`

**Task:** Move payment-specific launch fields such as event counts, policy
limits, duplicate injection, and malformed-event injection out of the generic
runtime `LaunchSpec`. Keep the generic spec focused on tile identity,
workspace, links, CPU placement, lifecycle, and handoff metadata.

**Done when:**

- [ ] `LaunchSpec` contains no payment-pipeline behavior fields.
- [ ] Payment process configuration is encoded in a payment-owned launch
      payload or sidecar contract.
- [ ] Process-mode payment tests still prove thread/process parity.

## 24. Replace string-based child tile dispatch with a registry

**Files:** `src/app/tickoni/tile_main.zig`, `src/tickoni/runtime/tile.zig`, `src/tickoni/tiles/payment_pipeline/process.zig`

**Task:** Replace the `if/else` chain that dispatches child tile work by raw
tile-id strings with a registry keyed by typed tile IDs. Keep unsupported tile
IDs fail-closed with clear errors.

**Done when:**

- [ ] `tile_main.zig` does not branch on raw `"tk..."` strings.
- [ ] Each runnable process-mode tile is registered in one table.
- [ ] Unsupported or unregistered tile IDs fail before joining links or doing
      tile work.

## 25. Split the payment pipeline into tile-owned modules

**Files:** `src/tickoni/tiles/payment_pipeline/runtime.zig`, `src/tickoni/tiles/payment_pipeline/process.zig`, `src/tickoni/tiles/payment_pipeline/mod.zig`

**Task:** Break the monolithic payment-pipeline runtime into modules that make
tile ownership explicit: ingestion, normalization, dedupe, policy, audit,
replay, metrics, and diagnostics. Preserve the current deterministic behavior
while reducing shared-state coupling.

**Done when:**

- [ ] Each payment pipeline tile has an owning module or clearly named file.
- [ ] Shared state is limited to explicit channel/message contracts and
      documented shared runtime state.
- [ ] Existing Phase 0 thread and process tests pass without relying on one
      central all-tile implementation file.

## 26. Make `tkaudt` own audit record construction for the payment pipeline

**Files:** `src/tickoni/tiles/payment_pipeline/audit_sink.zig`, `src/tickoni/tiles/payment_pipeline/runtime.zig`, `src/tickoni/tiles/audit/*`

**Task:** Move payment-pipeline audit record construction behind the audit tile
boundary. Avoid hardcoding `tkpoly` as the event tile ID inside an audit sink
that represents append-only audit ownership.

**Done when:**

- [ ] Payment audit records identify the correct producer and audit owner
      fields according to the audit contract.
- [ ] Payment pipeline code passes audited boundary facts to `tkaudt` instead
      of locally constructing policy-only records.
- [ ] Tests cover source, normalization, dedupe, policy, and audit records
      where those records are expected.

## 27. Remove fixture vocabulary from canonical audit contracts

**Files:** `src/tickoni/schema/audit/audit.zig`, `src/tickoni/schema/proto/audit/audit.proto`, `src/tickoni/codec/audit/wire.zig`, `src/tickoni/codec/audit/protobuf.zig`, `src/tickoni/codec/audit/hash.zig`

**Task:** Replace production audit fields such as `fixture_id` with domain
neutral evidence, adapter response, or replay-substitution references. Test
fixtures can populate those references, but the canonical audit schema should
not name fixture concepts.

**Done when:**

- [ ] Canonical audit schema/proto/wire fields do not include `fixture_id`.
- [ ] Fixture-backed tests encode fixture provenance through a test-only or
      domain-neutral evidence reference.
- [ ] Audit codec and hash tests are updated for the renamed/replaced field.

## 28. Centralize replay and proposal hash helpers

**Files:** `src/tickoni/tiles/replay/mod.zig`, `src/tickoni/test/demo/investment/audit_trace.zig`, `src/tickoni/codec/audit/hash.zig`, `src/tickoni/schema/consumer_money/trade_ticket.zig`, `src/tickoni/schema/consumer_money/drift.zig`

**Task:** Move replay-critical hash helpers for quote snapshots,
affordability, trade tickets, paper results, and proposal/drift records into a
single canonical module. Demo and replay code should call the shared helpers
instead of reimplementing field-by-field hashing.

**Done when:**

- [ ] `replay/mod.zig` and `audit_trace.zig` no longer duplicate equivalent
      hash functions.
- [ ] Each replay-critical artifact hash has one named helper and one version
      contract.
- [ ] Tests prove demo audit traces and replay checks use the same hash
      derivations.

## 29. Move the instrument catalog out of schema fixture code

**Files:** `src/tickoni/schema/consumer_money/catalog.zig`, `src/tickoni/schema/proto/consumer_money/catalog.proto`, `src/tickoni/schema/consumer_money/basket.zig`, `src/tickoni/test/fixtures/**`

**Task:** Separate the instrument catalog contract from the concrete fixture
catalog data and lookup service. Keep the versioned schema in schema code; move
the sample instrument list and fixture lookup tables to fixture or data modules
with explicit runtime wiring.

**Done when:**

- [ ] `catalog.zig` is no longer both the catalog schema and the hardcoded
      fixture instrument database.
- [ ] Basket construction receives a catalog provider or explicit catalog
      snapshot.
- [ ] Tests can swap fixture catalogs without changing schema modules.

## 30. Define one source of truth for taxonomy and known values

**Files:** `src/tickoni/schema/consumer_money/thesis.zig`, `src/tickoni/schema/consumer_money/catalog.zig`, `src/tickoni/schema/classification/classification.zig`

**Task:** Consolidate known theme IDs, sector codes, industry codes, taxonomy
versions, and known ticker lists so thesis validation and catalog validation do
not maintain parallel vocabularies.

**Done when:**

- [ ] Known themes, sectors, industries, and taxonomy versions have one owner.
- [ ] Thesis and catalog validation import that owner instead of duplicating
      lists.
- [ ] Tests fail if a catalog entry or thesis fixture references a value
      outside the shared vocabulary.

## 31. Catalog finance-native capability constants

**Files:** `src/tickoni/tiles/agent/mod.zig`, `src/tickoni/test/demo/investment/mod.zig`, `src/tickoni/tiles/model/messages.zig`, `src/tickoni/tiles/policy/mod.zig`

**Task:** Replace scattered capability, workflow, actor-role, policy-version,
budget-id, and capability-envelope string literals with a typed capability
catalog or shared constants module. Keep demo-specific values clearly separated
from reusable runtime vocabulary.

**Done when:**

- [ ] `trading_order.propose`, `trading_control`,
      `trading_ops_reviewer`, policy versions, and budget IDs are not repeated
      as raw strings across production and demo modules.
- [ ] Capability-envelope identifiers are constructed or validated through one
      helper.
- [ ] Tests assert against shared names instead of retyping literals.

## 32. Generate or centralize audit schema/wire/proto definitions

**Files:** `src/tickoni/schema/audit/audit.zig`, `src/tickoni/schema/proto/audit/audit.proto`, `src/tickoni/codec/audit/wire.zig`, `src/tickoni/codec/audit/protobuf.zig`, `src/tickoni/codec/audit/jsonl.zig`, `src/tickoni/codec/audit/hash.zig`

**Task:** Remove manual parallel definitions of audit fields across typed Zig
schema, protobuf schema, extern wire structs, codecs, and hash logic. Choose
one source of truth and generate or mechanically validate the others.

**Done when:**

- [ ] Adding, removing, or renaming an audit field requires changing one
      canonical definition.
- [ ] Generated or validation checks prove Zig schema, proto schema, wire
      layout, codec, and hash coverage are synchronized.
- [ ] The audit codec tests fail when a schema field exists but is not encoded,
      decoded, or hashed.
