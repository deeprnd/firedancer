Codec and schema cleanup work log

1. Split the packed audit codec into focused modules under `src/tickoni/codec/audit/` (`mod.zig`, `wire.zig`, `hash.zig`, `protobuf.zig`, `binary.zig`, `jsonl.zig`) while keeping `src/tickoni/codec/audit.zig` as a thin root. done

2. Move the canonical audit schema into `src/tickoni/schema/audit/audit.zig` and turn `src/tickoni/tiles/audit/types.zig` into a compatibility re-export so audit contracts have one source of truth. done

3. Remove pure Zig `pub fn tk_*` exports from codec code and replace them with lower-camel public APIs in `src/tickoni/codec/thesis.zig` and the new consumer-money codec wrappers. done

4. Reverse the schema-to-codec dependency for consumer-money hashing so `src/tickoni/schema/consumer_money/thesis.zig` and `basket.zig` no longer import `thesis_codec`. done

5. Split the old mixed thesis/basket/trade-ticket/paper-order codec root into consumer-money hash wrappers under `src/tickoni/codec/consumer_money/`; keep only the currently canonical thesis and basket hash surfaces and remove the stale mixed `tk_*` hash exports. done

6. Harden audit protobuf parsing so narrow integer fields fail closed instead of truncating oversized varints, including explicit validation for boolean wire values. done

7. Move binary framing ownership into the audit codec so length-prefix handling, protobuf body formatting, hash validation, and parse/format round-trips are owned by one codec boundary. done

8. Add regression coverage for audit binary round-trips, unknown enum rejection, and oversized varint rejection. done

9. Update build wiring so `audit_schema` is a named shared module, audit consumers import it explicitly, and thesis/basket schema modules pull `c_abi` directly. done

10. Verification run: `zig build test`. done


High: Production modules depend on test fixtures/mocks.** `adapter/backend.zig` imports `fixture_portfolio` and `mock_adapter` directly, despite comments saying the mock is a pure test double: [backend.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/adapter/backend.zig:4), [backend.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/adapter/backend.zig:7). Same pattern appears in `model/backend.zig`, `agent/mod.zig`, `tool/mod.zig`, and even schema `trade_ticket.zig`. This is the biggest dependency-graph smell because production, fixture, mock, and demo concerns are not separable.

- **High: The schema layer is doing too much domain/application work.** `schema/consumer_money/basket.zig` owns deterministic basket construction and screening, not just contracts: [basket.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/basket.zig:366), [basket.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/basket.zig:376). `thesis.zig` owns normalization and fixtures: [thesis.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/thesis.zig:261), [thesis.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/thesis.zig:584). `portfolio.zig` owns affordability evaluation: [portfolio.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/portfolio/portfolio.zig:161). This blurs DDD boundaries between contracts, domain services, policy, and fixtures.

- **High: `tkpoly` is structurally thin and policy ownership is scattered.** `policy/mod.zig` delegates basket construction/screening to schema modules and applies guardrails into `trade_ticket`: [mod.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/policy/mod.zig:22), [mod.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/policy/mod.zig:56). Meanwhile `trade_ticket` owns `PolicyOutcome` and `applyPolicyDecision`: [trade_ticket.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/trade_ticket.zig:16), [trade_ticket.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/trade_ticket.zig:197). Structurally, `tkpoly` is not yet the clear policy authority described by the architecture.

- **Medium-high: Tile messages are not clean cross-boundary interfaces.** `AdapterRequest` carries a raw pointer to a `TradeTicket`: [messages.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/adapter/messages.zig:17). `model/messages.zig` uses process-local slices throughout requests/responses: [messages.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/model/messages.zig:10), [messages.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/model/messages.zig:29). That is fine for in-process tests, but weak as a tile interface contract and not composable across shared memory/process boundaries.

- **Medium-high: Declared topology and executable runtime are drifting.** `investmentWorkflow()` declares 14 product tiles including `tkcase`, `tkdisp`, `tkagnt`, `tkmodl`, `tktool`, and `tkadpt`: [topologies.zig](/home/vicgenin/work/git/tickoni/src/app/tickoni/topologies.zig:34). The CLI only starts/statuses the payment pipeline: [main.zig](/home/vicgenin/work/git/tickoni/src/app/tickoni/main.zig:39). Process-mode child dispatch explicitly says `tkrepl/tkmetr/tkdiag` have no process role yet and only dispatches the payment core: [tile_main.zig](/home/vicgenin/work/git/tickoni/src/app/tickoni/tile_main.zig:28). This makes it unclear which topology is architectural intent versus runnable product surface.

- **Medium: The app supervisor is tightly coupled to one concrete topology shape.** `startPaymentPipeline` asserts exactly 8 tiles and starts each tile by fixed array index: [supervisor.zig](/home/vicgenin/work/git/tickoni/src/app/tickoni/supervisor.zig:108), [supervisor.zig](/home/vicgenin/work/git/tickoni/src/app/tickoni/supervisor.zig:125). This is explicit and simple, but not composable: adding/reordering tiles requires app-layer changes instead of using tile descriptors/dispatch tables.

- **Medium: Phase naming is internally inconsistent.** `TileDescriptor` documents `phase: 0=core, 1=case, 2=agent, 3=api, 4=exec`: [tile.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/tile.zig:30). But `investmentWorkflow()` marks `tkcase` as phase `2` and agent/model/tool/adapter tiles as phase `1`: [topologies.zig](/home/vicgenin/work/git/tickoni/src/app/tickoni/topologies.zig:38), [topologies.zig](/home/vicgenin/work/git/tickoni/src/app/tickoni/topologies.zig:41). This is a project-coherency/naming smell, not just a comment issue.

- **Medium: Tile module structure has high standard deviation.** `model` follows the documented `messages/backend/validator/run` split, but `agent`, `policy`, `replay`, `tool`, `case`, and `disp` are mostly single `mod.zig` modules. `replay/mod.zig` imports many domain modules directly: [mod.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/replay/mod.zig:1). `model/backend.zig` combines fixture, HTTP, replay, mock dispatch, and tests in one file: [backend.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/model/backend.zig:306). This makes the codebase feel like multiple maturity levels rather than one consistent tile pattern.

10 More Structural Findings**
1. **Generic runtime carries payment-domain fields.** `LaunchSpec` is in `src/tickoni/runtime`, but it embeds `event_count`, `policy_limit_cents`, `inject_duplicate`, and `inject_malformed`: [launch_spec.zig](/home/vicgenin/work/git/tickoni/src/tickoni/runtime/launch_spec.zig:44). That makes the runtime launch contract less reusable for non-payment tiles.

2. **Child tile dispatch is hardcoded by string tile IDs.** `tile_main.zig` branches on `"tkings"`, `"tknorm"`, `"tkdedu"`, `"tkpoly"`, and `"tkaudt"` directly: [tile_main.zig](/home/vicgenin/work/git/tickoni/src/app/tickoni/tile_main.zig:34). This duplicates topology knowledge and blocks composable tile registration.

3. **The payment pipeline is structurally one module, not eight tile modules.** `PaymentPipelineState` owns all queues, counters, dedupe state, audit state, and lifecycle flags centrally, while `runIngest`, `runNormalize`, `runDedupe`, `runPolicy`, `runAudit`, `runReplay`, `runMetric`, and `runDiag` sit in one file: [runtime.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/payment_pipeline/runtime.zig:75), [runtime.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/payment_pipeline/runtime.zig:224). Tile ownership is expressed by convention, not by code structure.

4. **Audit ownership is blurred in the payment spike.** `payment_pipeline/audit_sink.zig` builds only policy-decision audit events and hardcodes the event tile ID to `tkpoly`: [audit_sink.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/payment_pipeline/audit_sink.zig:19), [audit_sink.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/payment_pipeline/audit_sink.zig:49). That makes `tkaudt` look like a sink for `tkpoly` records, not a clear audit tile boundary.

5. **Test vocabulary leaked into canonical audit contracts.** `fixture_id` is present in the production audit schema, proto, and wire mirror: [audit.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/audit/audit.zig:82), [audit.proto](/home/vicgenin/work/git/tickoni/src/tickoni/schema/proto/audit/audit.proto:75), [wire.zig](/home/vicgenin/work/git/tickoni/src/tickoni/codec/audit/wire.zig:58). A stable audit event should not encode “fixture” as a first-class domain field.

6. **Hashing logic is duplicated outside the codec/domain boundary.** `replay/mod.zig` has local hash functions for quote snapshots, affordability, tickets, and paper results: [mod.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/replay/mod.zig:163). `test/demo/investment/audit_trace.zig` reimplements similar hashing: [audit_trace.zig](/home/vicgenin/work/git/tickoni/src/tickoni/test/demo/investment/audit_trace.zig:68). Replay-critical hashes should have one canonical home.

7. **The catalog is labeled as a fixture but lives in schema.** `catalog.zig` says “Instrument catalog fixture” and stores 24 concrete instruments directly in schema code: [catalog.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/catalog.zig:1), [catalog.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/catalog.zig:198). That mixes reference data, demo data, schema, and lookup service concerns.

8. **Taxonomy and known-value lists are duplicated.** `thesis.zig` defines known themes/sectors/industries/tickers: [thesis.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/thesis.zig:77). `catalog.zig` independently defines known themes/sectors/industries: [catalog.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/consumer_money/catalog.zig:80). This is a classic drift point for domain vocabulary.

9. **Capability envelope literals are scattered.** Agent code has `investment_capability`, `investment_capability_envelope_id`, `investment_policy_version`, and `investment_budget_id`: [mod.zig](/home/vicgenin/work/git/tickoni/src/tickoni/tiles/agent/mod.zig:13). Demo code repeats similar live constants: [mod.zig](/home/vicgenin/work/git/tickoni/src/tickoni/test/demo/investment/mod.zig:25). These should be typed/cataloged rather than repeated strings.

10. **Proto/Zig/wire schemas are parallel manual contracts.** Audit has a typed Zig schema, a proto schema, and an extern wire mirror that all repeat the same fields: [audit.zig](/home/vicgenin/work/git/tickoni/src/tickoni/schema/audit/audit.zig:149), [audit.proto](/home/vicgenin/work/git/tickoni/src/tickoni/schema/proto/audit/audit.proto:10), [wire.zig](/home/vicgenin/work/git/tickoni/src/tickoni/codec/audit/wire.zig:9). Without generation or a single source of truth, maintainability depends on manual synchronization.
