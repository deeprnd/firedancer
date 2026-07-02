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
