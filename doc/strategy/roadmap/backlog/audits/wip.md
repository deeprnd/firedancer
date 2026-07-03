# Tech Debt — Deferred Architectural Findings

Findings from `tech_debt.md` that were investigated but deliberately **not**
implemented in the 2026-07-02 pass, because each requires a framework/
architecture decision per `CLAUDE.md`'s "Ask Before You Change" list (tile
ownership/lifecycle, link semantics, audit schema, or a new abstraction that
alters the tile-based architectural style). Grouped by what would actually
have to change together, with the concrete design questions found while
reading the code — not just a restatement of the original findings.

Findings 1-6, 10, 13, 17 (partial), 14, 15 (partial), 18 (partial), 19, 21, 28,
31 were implemented in that same pass; see `tech_debt.md` for the original
text and `git log` (`audit findings wip*` commits) for the changes.

## A. Supervisor/tile-registry decoupling (findings 7, 20, 24)

**Files:** `src/app/tickoni/supervisor.zig`, `src/app/tickoni/tile_main.zig`,
`src/tickoni/runtime/tile.zig`, `src/tickoni/tiles/payment_pipeline/mod.zig`,
`src/tickoni/tiles/payment_pipeline/process.zig`

Confirmed concretely:
- `supervisor.zig`'s `snapshotProcessMetrics()` if/else-chains on raw tile-id
  strings (`"tkings"`, `"tknorm"`, `"tkdedu"`, `"tkpoly"`, `"tkaudt"`) with
  payment-pipeline-specific output field names (`produced`, `normalized`,
  `invalid`, `duplicates`, `allowed`, `denied`, `audited`) baked directly into
  the generic `ProcessMetricSnapshot` type.
- `startPaymentPipeline()` (thread mode) hardcodes 8 `self.handles[i].thread =
  try std.Thread.spawn(.{}, tiles_mod.runIngest, .{state})`-style calls, one
  per fixed array index, assuming the topology's tile order exactly matches.
- `tile_main.zig` does the equivalent by string dispatch for process mode
  (`if (std.mem.eql(u8, tile_id, "tkings")) ... else if (...)`).

**Design question to resolve before implementing:** what does the registry
entry look like? At minimum it needs: tile id → thread-mode run function,
tile id → process-mode work function (from `payment_pipeline/process.zig`),
and tile id → metric-field mapping for `snapshotProcessMetrics()`. Whether
this lives as a `comptime` table in `payment_pipeline/mod.zig` (keeping
`supervisor.zig` fully generic) or as a runtime-registered table the app
wires up at startup is an architecture call — the former is simpler but
`supervisor.zig` currently has zero `import` of payment-pipeline internals
except through the registry, so this changes where that import boundary sits.

## B. Tile lifecycle safety (findings 8, 9)

**Files:** `src/tickoni/runtime/tile_process.zig`,
`src/app/tickoni/supervisor.zig`,
`src/tickoni/test/integration/test_process_topology.zig`

Both are already documented as known gaps in `tile_process.zig`'s own doc
comments — not something discovered fresh:

- **Finding 8:** `run()` heartbeats once, signals RUN, then calls `work(...)`
  **synchronously** and only heartbeats again after `work` returns. A
  long-running or upstream-blocked tile looks dead to the supervisor even
  though it's alive. Confirmed this is the same code path exercised by
  `payment_pipeline/process.zig`'s `runNormalizeProcess` etc., which block
  inside `Consumer.consume()`/`Producer.publish()` for potentially a long
  time with no heartbeat in between.
- **Finding 9:** `run()` does an **unconditional** `c_abi.cnc.signal(cnc,
  c_abi.cnc.signal_run)` after boot — if the supervisor's `stopProcess()`
  already wrote HALT while this tile was still booting, that write is
  silently clobbered back to RUN, and the tile then blocks forever waiting on
  an upstream tile that already honored the same halt and stopped producing.
  The doc comment literally says: *"Callers must not request a stop before
  every tile has demonstrably reached RUN"* — i.e. today's mitigation is
  caller discipline, not a real fix.

**Directly relevant to the hang observed during this session's testing:**
`payment_pipeline/process.zig` also documents that its `stop_flag` (passed
into every `consume()`/`publish()` call) is **never actually set to true** —
the real CNC HALT signal is only checked *between* messages via
`halted(cnc)`, never *during* a blocked wait for the next fragment. If an
upstream tile stalls, every downstream tile blocks forever with no timeout.
This combination (findings 8 + 9 + the dead `stop_flag`) is almost certainly
why process-mode integration tests (`test_process_topology.zig`,
`test_process_demo_parity.zig`, `test_process_cpu_placement.zig`) hung
repeatedly under this session's system load — confirmed via a controlled
experiment (temporarily reverting the finding-5 spin/sleep change made no
difference; the hang is independent of that change).

**Design question:** fixing 8 means deciding whether `tile_process.zig`
spawns a heartbeat thread/timer independent of `work()`, or whether `work()`
itself must periodically yield control back to a driving loop (bigger API
change to every tile's work function signature). Fixing 9 means deciding
whether to check HALT immediately before the `signal_run` write (races if HALT
arrives a moment later) or to have the supervisor guarantee it never writes
HALT before observing RUN (current documented approach, just unenforced).

## C. LaunchSpec / link cardinality (findings 11, 23)

**Files:** `src/tickoni/runtime/launch_spec.zig`,
`src/app/tickoni/supervisor.zig`, `src/app/tickoni/tile_main.zig`,
`src/tickoni/test/integration/test_process_topology.zig`

Confirmed concretely:
- `LaunchSpec` has exactly one `input_link: LinkHandles` and one
  `output_link: LinkHandles` (each with a `has_*_link: bool` guard).
- `supervisor.zig`'s process-mode channel-selection loop
  (`startPaymentPipelineProcess`) is genuinely last-match-wins: `for
  (self.topo.channels) |ch| { if (ch.dst_idx == i) input_link =
  link_handles[ci]; if (ch.src_idx == i) output_link = link_handles[ci]; }` —
  a tile with two input or two output channels would silently get only the
  *last* one in iteration order, with no error. Currently latent because
  `paymentPipeline()`/`paymentPipelineProcess()` are linear chains (each tile
  has at most one in + one out); `investmentWorkflow()`'s graph already has
  real fan-in (multiple tiles feeding `tkaudt`) but that topology is marked
  `.planned` (not runnable) per the finding-19 status labeling added this
  pass, so the bug has no live trigger today.
- `LaunchSpec` also carries `event_count`, `policy_limit_cents`,
  `inject_duplicate`, `inject_malformed` — payment-pipeline-specific
  behavior fields — inside the otherwise-generic supervisor→child handoff
  struct (finding 23).

**Design question:** for 11, either (a) extend `LaunchSpec` to carry a bounded
array of input/output links (how many? `investmentWorkflow()`'s max fan-in
into `tkaudt` is 5) and make `supervisor.zig` assign every matching channel
instead of overwriting, or (b) explicitly validate at topology-build time that
process-mode topologies never exceed 1-in/1-out and fail closed otherwise,
deferring true multi-link support until a topology actually needs it. For 23,
the payment fields need to move into a payment-owned sidecar payload
(different file read by `payment_pipeline/process.zig` specifically) —
requires deciding the sidecar's own versioned-handoff format, mirroring how
`LaunchSpec` itself does magic/version/length checks.

## F. Schema/domain-service and taxonomy boundaries (findings 16, 29, 30)

**Files:** `src/tickoni/schema/consumer_money/thesis.zig`,
`src/tickoni/schema/consumer_money/basket.zig`,
`src/tickoni/schema/consumer_money/drift.zig`,
`src/tickoni/schema/consumer_money/catalog.zig`,
`src/tickoni/schema/classification/classification.zig`,
`src/tickoni/schema/portfolio/portfolio.zig`,
`src/tickoni/tiles/policy/mod.zig`, `src/tickoni/test/fixtures/**`

All three findings are "where should this code/data live" calls that ripple
through many `build.zig` module-import edges (thesis/basket/drift/catalog are
each separately-named modules imported by ~10+ test artifacts). Not attempted
because the physical-split option requires an ownership decision (finding 16
explicitly allows "or document an explicit exception" as a valid outcome —
which one applies per module needs a decision, not just execution), and
finding 29's catalog split requires designing a catalog-provider injection
point (mirroring the `Backend.from()` vtable pattern added for finding 15/E
this pass, which is now available as a template if that's the chosen
direction).

## I/J. Tile module structure + payment pipeline split (findings 22, 25)

**Files:** `src/tickoni/tiles/agent/mod.zig`, `src/tickoni/tiles/policy/mod.zig`,
`src/tickoni/tiles/replay/mod.zig` (918 lines), `src/tickoni/tiles/tool/mod.zig`,
`src/tickoni/tiles/case/mod.zig`, `src/tickoni/tiles/disp/mod.zig`,
`src/tickoni/tiles/model/*`, `src/tickoni/tiles/payment_pipeline/runtime.zig`
(539 lines), `src/tickoni/tiles/payment_pipeline/process.zig`

Pure reorganization (no behavior change), but touches every `build.zig`
module wiring for the affected tiles (each file split needs new `.imports`
edges, mirroring the `_test_mod`/`_int_mod` pattern already used throughout
`build.zig` — see the finding-15/E work this pass for a worked example of how
fiddly that gets when a module is reused as both a standalone test root and an
import elsewhere: reusing a module object as `root_module` for one `addTest`
and importing it into another mutates it via `linkTickoniCodec`'s
`addCSourceFiles`, causing duplicate-symbol link errors — the established fix
is a **fresh** `b.createModule()` per standalone test binary, never reusing
the shared module directly as a root). Given the mechanical size, this is
better done as its own dedicated pass per tile rather than folded into
unrelated work.

## F.16: schema/domain-service split for thesis, basket, drift

**Files:** `src/tickoni/schema/consumer_money/thesis.zig` (1312 lines),
`src/tickoni/schema/consumer_money/basket.zig` (1102 lines),
`src/tickoni/schema/consumer_money/drift.zig` (1870 lines)

F.30 and F.29's schema-only splits (`catalog.zig`/`catalog_schema.zig`,
`classification.zig`) worked cleanly because the contract type has zero
dependency on its behavior functions, so the fixture/behavior file could
import the pure-contract file one-way with no cycle, and the module's public
name (`"catalog"`) kept pointing at the same file so every consumer's
`@import("catalog")` surface stayed identical.

thesis.zig doesn't have that property: `normalize()`,
`computeThesisInputHash()`, and their private helpers (sort/pack/validate)
are declared in the same file as `ThesisInput`/`InvestorIntent` and need
those types. Pulling them into a separate `thesis_normalize.zig` that
imports `thesis.zig` for the types, while `thesis.zig` re-exports
`normalize`/`computeThesisInputHash` for existing callers, is a two-file
cycle. Breaking it means either (a) flipping which file the build module
name `"thesis"` points at — a thin aggregator re-exporting a contract file
+ a behavior file, the `payment_pipeline/mod.zig` pattern — or (b) accepting
that callers needing `normalize()` import a differently-named module than
callers needing `ThesisInput`. Same shape of problem for `basket.zig`
(screening/allocation logic vs. `Basket`/`BasketScreening` contract types)
and `drift.zig` (drift generation vs. `DriftContract`).

**Why not attempted this pass:** whichever option is chosen ripples through
`build.zig`, which currently wires `thesis_mod`/`basket_mod`/`drift_mod` as
named imports at 61 separate call sites (tkpoly, demo/investment code, every
basket/drift/trade_ticket test, etc.). That's real blast radius for what's
meant to be a pure reorganization, and the aggregator-vs-split-naming choice
is itself a decision, not just execution — same category as I/J below.

## F.29 (partial): catalog provider injection

**Files:** `src/tickoni/schema/consumer_money/basket.zig`,
`src/tickoni/tiles/policy/mod.zig` (tkpoly.buildBasket)

Finding 29's schema/fixture split is done: `catalog_schema.zig` now holds the
versioned contract (`InstrumentEntry`, `RestrictionReason`,
`catalog_schema_version`, `CatalogValidationError`), and `catalog.zig` holds
only the 24-entry fixture array, lookup functions
(`filterByTheme`/`lookupByTicker`/etc.), and fixture validation — re-exporting
the schema types so every existing `@import("catalog")` call site (chiefly
`basket.zig`, which uses `cat.InstrumentEntry`/`cat.filterByTheme`/
`cat.lookupByTicker` extensively) kept working with zero call-site changes.

**Not attempted:** the finding's other half — "basket construction receives a
catalog provider or explicit catalog snapshot instead of importing fixture
data directly." `basket.zig` still imports the concrete `catalog.zig` fixture
module by name (`const cat = @import("catalog");`) rather than taking a
catalog snapshot/provider as a parameter. Doing this for real means changing
`buildBasket`'s signature (and every caller: `tkpoly.buildBasket`, demo code,
every basket test) to thread a provider through, mirroring the `Backend.from()`
vtable pattern used for finding 15/E's model/adapter backends. That's a
second, separately-scoped change, not a file reorganization — deferred here
for the same reason 25/22 are (mechanical size, ripples through every caller).

## K. Audit ownership/schema (findings 26, 27, 32)

**Files:** `src/tickoni/tiles/payment_pipeline/audit_sink.zig`,
`src/tickoni/tiles/audit/*`, `src/tickoni/schema/audit/audit.zig`,
`src/tickoni/schema/proto/audit/audit.proto`,
`src/tickoni/codec/audit/{wire,protobuf,jsonl,hash}.zig`

Confirmed concretely:
- `audit_sink.zig` hardcodes `const tkpoly_tile_id: [6]u8 = "tkpoly".*;` and
  stamps it as the producer/event tile id on **every** audit record the
  payment pipeline emits, regardless of which stage (tkings/tknorm/tkdedu/
  tkpoly/tkaudt) actually produced that specific event.
- `schema/audit/audit.zig`'s canonical `AuditEvent` payload has a production
  `fixture_id: u32` field, mirrored through `wire.zig`, `hash.zig` (hashed
  into the record hash), and `audit.proto`.

**Design question for 26:** does per-stage identity get threaded through as
an explicit parameter to `audit_sink`'s record-building functions (one call
site per stage, each passing its own real tile id), or does `tkaudt` itself
own record construction entirely and each stage just submits a fact +
its own id? The latter matches CLAUDE.md's "tkaudt owns audit record
construction" framing better but is a bigger refactor of the payment-pipeline
call sites.

**Design question for 27/32:** `fixture_id` needs a domain-neutral
replacement (evidence reference / replay-substitution reference per the
finding text) — this changes the **hash-chained** canonical schema across all
four representations (Zig struct, proto, wire codec, hash) simultaneously,
and any existing captured audit fixtures (`.jsonl` files under
`src/tickoni/test/fixtures/**`) that reference `fixture_id` need
regenerating, same as the hash-migration fixture regeneration done for
finding 14 this pass (see `fixture_replay_capsule*.json` for the pattern:
capture real values via a temporary debug print in the verification path
rather than hand-computing hashes). Finding 32 (generate/mechanically-check
the four representations against one source of truth) is a prerequisite for
making 27 safe to repeat in the future without manual drift.
