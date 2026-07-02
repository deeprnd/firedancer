A. Supervisor/tile-registry decoupling (7, 20, 24) — supervisor.zig's snapshotProcessMetrics() if/else-chains on raw tile-id strings with payment-specific field names, thread-mode start hardcodes 8 handles[i].thread = spawn(tiles_mod.runX, ...) calls by index, and tile_main.zig does the same by string dispatch for process mode. Real fix: one tile registry/descriptor table (id → run-fn, id → metric-field) that all three read from instead of duplicating tile knowledge three ways.

Decision: TBD to be delayed after all are done.

B. Tile lifecycle safety (8, 9) — tile_process.zig's run() heartbeats once, then calls work() synchronously (so a slow/blocked tile looks dead), and unconditionally writes signal_run after boot even if a supervisor HALT already arrived (the halt gets silently clobbered — already documented as a known race in process.zig's own comments). Fixing either changes the CNC signal protocol's behavior under concurrency.

Decision: TBD to be delayed after all are done.

C. LaunchSpec / link cardinality (11, 23) — LaunchSpec has exactly one input_link/output_link, and supervisor.zig's channel-selection loop is genuinely last-match-wins (silently drops earlier fan-in/fan-out channels — currently latent since payment topologies are linear chains). LaunchSpec also carries payment-specific fields (event_count, policy_limit_cents, inject_duplicate/malformed) that don't belong in a generic runtime handoff struct. Fixing 11 means deciding the real multi-link contract; fixing 23 means designing a sidecar payload split.

Decision: TBD to be delayed after all are done.

F. Schema/domain-service boundaries (16, 29, 30) — thesis/basket/drift normalization logic living in schema modules,
the instrument catalog being both contract aector/taxonomy vocab duplicated acrossthesis.zig/catalog.zig/classification.zig. All are "where should this code live" calls that ripple through many import
sites.

Decision: should be clean data types granular enough and split across different files to be able to import without issues. use domain driven design for this.

I. Tile module structure (22) — reorganizingse/disp/model into a consistentmod/messages/backend/validator/run file layout.  

Decision:  should be clean data types granular enough and split across different files to be able to import without issues. use domain driven design for this.

J. Payment pipeline split (25) — breaking ruer-role files.

Decision:   should be clean data types granular enough and split across different files to be able to import without issues. use domain driven design for this.

K. Audit ownership/schema (26, 27, 32) — audit_sink.zig hardcodes "tkpoly" as the producer tile id for every audit record regardless of which stage actually emitted it; the canonical audit schema (Zig struct + proto + wire + hash) has a production fixture_id field; and there's no generated/mechanically-checked sync between the four audit representations.

 Decision: audit needs to be aware from where the message came and audit it correctly.
