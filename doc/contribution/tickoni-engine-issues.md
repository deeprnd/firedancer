# Tickoni-Applicable Firedancer Issues

These are open Firedancer issues that are not Solana-specific and are relevant
to Tickoni's execution engine. The selection is based on what Tickoni directly
reuses from Firedancer:

- `src/tango` — shared-memory queues and flow control
- `src/util/sandbox` — seccomp, Landlock, process isolation
- `src/disco/topo` / `fd_topob` — process lifecycle and workspace construction
- `src/disco/stem` — bounded polling loops and backpressure
- `src/disco/metrics` — per-tile metrics
- `fd_http_server` — tile-local HTTP/WebSocket used by `tkapi`
- Build system (make, gcc, clang, UBSAN, MSan)
- Zig integration (`build.zig`, `zig cc`)

Issues about Solana consensus, validator protocol, shreds, gossip, PoH, SBPF,
accounts database, or Agave compatibility are excluded.

---

## Infrastructure Substrate

### #9838 — stem fragment torn reads (non-x86)
- **URL:** https://github.com/firedancer-io/firedancer/issues/9838
- **Relevance:** `fd_stem.c` is the bounded polling loop substrate Tickoni wraps in `src/disco/stem` for its tile pipeline. The torn-read bug affects `during_frag` correctness on any non-x86 platform and is only papered over on x86 via a 32-byte atomic AVX load. Tickoni inherits this latent correctness bug in its tile event path.

### #8101 — increase `sz` on frag_meta_t and remove all the related hacks
- **URL:** https://github.com/firedancer-io/firedancer/issues/8101
- **Relevance:** `frag_meta_t` lives in `src/tango`, the core shared-memory queue layer Tickoni uses for inter-tile channels (`tkings_tknorm`, `tkpoly_tkaudt`, etc.). The current size cap and downstream hacks constrain financial event envelope sizes.

### #826 — Standardize dcache bounds checking for links
- **URL:** https://github.com/firedancer-io/firedancer/issues/826
- **Labels:** security, Priority: Medium
- **Relevance:** Topology knows all link MTU, chunk bounds, and wmark values. Currently every tile must remember to validate these in `during_frag`. The proposal is to do automatic bounds checking at the link layer, so `tkings`, `tknorm`, `tkdedu`, `tkpoly`, and `tkaudt` cannot be exploited via oversized or out-of-bounds fragments. Directly applicable to Tickoni's tile pipeline.

### #2352 — [fd-mux] Handling of cross-tile shared memory may lead to OOB read
- **URL:** https://github.com/firedancer-io/firedancer/issues/2352
- **Labels:** security
- **Relevance:** `fd_mux` is the multiplexing layer on top of `src/tango` queues. A compromised tile could trigger an OOB read in a downstream tile via a crafted `depth` value. Directly relevant to Tickoni's tile isolation model, where each tile must be unable to corrupt adjacent tile state.

### #3464 — fdctl metadata descriptors (fd_pod) for better object discovery
- **URL:** https://github.com/firedancer-io/firedancer/issues/3464
- **Relevance:** Joining workspace objects (shared memory) for an already-running Tickoni runtime is difficult without recreating the full topology. An `fd_pod`-style directory at known workspace offsets would let operators, tools, and `tkdiag` discover audit/metric workspaces without re-parsing the topology.

### #4905 — fd_topob unit tests
- **URL:** https://github.com/firedancer-io/firedancer/issues/4905
- **Relevance:** `fd_topob` is the topology construction library Tickoni uses in `src/tickoni/runtime/topology.zig` via C ABI. It is nearly entirely untested. NUMA affinity correctness of workspace allocation directly affects Tickoni's tile performance and memory locality.

### #2466 — Wait until all tiles finished privileged_init before entering run loop
- **URL:** https://github.com/firedancer-io/firedancer/issues/2466
- **Labels:** security
- **Relevance:** Tile startup sequencing: all tiles must complete `privileged_init` (seccomp install, capability drops, fd setup) before any tile enters its run loop. Tickoni's supervisor inherits this startup ordering requirement and must enforce it or inherit the race condition.

### #1360 — Implement futex based cooperative core sharing for tiles
- **URL:** https://github.com/firedancer-io/firedancer/issues/1360
- **Labels:** platform, perf, Priority: Medium
- **Relevance:** Non-critical tiles (`tkmetr`, `tkdiag`, and future `tkevid`) do not need dedicated cores. Futex-based cooperative sharing would let Tickoni run on a laptop or small VM for development without needing to dedicate one physical core per tile.

### #664 — Move logging into separate tile, eliminate `write`/`fsync` calls from other tiles
- **URL:** https://github.com/firedancer-io/firedancer/issues/664
- **Labels:** security, Priority: Low
- **Relevance:** Tiles that call `write`/`fsync` need those syscalls in their seccomp profile, widening the attack surface. A dedicated log tile would let Tickoni's `tkaudt`, `tkpoly`, and `tknorm` run with a minimal syscall set. Also directly relevant to audit record flushing behavior under crash paths.

### #1883 — Ensure memory consumption is minimal
- **URL:** https://github.com/firedancer-io/firedancer/issues/1883
- **Relevance:** Audit of link and buffer sizes to ensure minimal footprint. Tickoni needs to run on development machines without 50 GB RAM. Right-sizing tango ring depths, workspace allocations, and buffer pools for realistic Tickoni financial event throughputs (not mainnet Solana validator scale) is necessary for developer adoption.

---

## Runtime Primitives

### #9980 — Consider stdatomic for util/tmpl
- **URL:** https://github.com/firedancer-io/firedancer/issues/9980
- **Relevance:** The `src/util/tmpl` files (pool_para, map_chain_para, map_slot_para) use a mix of volatile + compiler fences and the old `__sync` GCC API. Tickoni's C-ABI wrappers call into these templates for shared state. C11 atomics would add ThreadSanitizer support and portable acquire/release semantics, improving Tickoni's ability to run under TSan in CI.

### #4591 — heap_verify fails if two elements with the same key are inserted
- **URL:** https://github.com/firedancer-io/firedancer/issues/4591
- **Relevance:** Bug in `fd_heap.c`. `fd_heap` is a generic utility data structure. Tickoni uses Firedancer's util layer and would inherit this verification failure if it uses heaps for priority scheduling (e.g., in `tkdisp` for agent run ordering).

### #2353 — [util] Improve validation in MAP_(remove)
- **URL:** https://github.com/firedancer-io/firedancer/issues/2353
- **Labels:** security
- **Relevance:** `map_remove` does not validate that the entry is still a valid map member. Double-remove causes `key_cnt` underflow; invalid entry pointer causes OOB write. Tickoni's C substrate uses these map templates for deduplication (`tkdedu`), case lookup, and adapter tables.

---

## HTTP / Tile API

### #9686 — h2: WINDOW_UPDATE frames can overflow tx_wnd
- **URL:** https://github.com/firedancer-io/firedancer/issues/9686
- **Labels:** security (Priority: Low)
- **Relevance:** `fd_http_server` is used by Tickoni's `tkapi` tile to serve case board queries, evidence reads, and audit timeline reads over HTTP/WebSocket. A crafted `WINDOW_UPDATE` can push `tx_wnd` out of bounds, which is a security concern for any operator-facing HTTP endpoint.

### #3962 — http: return error response rather than closing connection
- **URL:** https://github.com/firedancer-io/firedancer/issues/3962
- **Relevance:** `fd_http_server` currently silently closes the connection on parse errors. Tickoni's `tkapi` tile will expose an operator-facing HTTP API; silent connection close makes debugging configuration and proxy issues difficult. Proper error responses reduce operational friction.

---

## CPU Affinity / Tile Scheduling

### #7278 — Auto affinity improvements
- **URL:** https://github.com/firedancer-io/firedancer/issues/7278
- **Relevance:** Tickoni tiles use the same CPU affinity and pinning mechanism as Firedancer tiles. The outstanding item (constrain `auto` affinity to the process's existing CPU set, e.g. from systemd) directly affects containerized/cgroup-managed Tickoni deployments.

### #4428 — Auto affinity fails for offline CPUs
- **URL:** https://github.com/firedancer-io/firedancer/issues/4428
- **Relevance:** When a CPU is taken offline (e.g. power management, container limit), the affinity assignment crashes rather than skipping. Tickoni's tile supervisor inherits this failure mode.

### #2300 — Let 'fdctl configure' set up smp_affinity
- **URL:** https://github.com/firedancer-io/firedancer/issues/2300
- **Relevance:** ksoftirqd processes scheduled on the same cores as Firedancer/Tickoni tiles cause sporadic performance drops at high event rates. Automating IRQ affinity configuration is part of production hardening for Tickoni deployments.

---

## Observability

### #9726 — Log slow hugetlbfs steps
- **URL:** https://github.com/firedancer-io/firedancer/issues/9726
- **Relevance:** Tickoni uses hugetlbfs-backed workspaces for shared-memory queues between tiles. Slow `mount` or `echo nr_hugepages` steps during startup silently delay the supervisor without surfacing which step caused the pause. Logging steps that exceed 100ms makes startup performance observable.

### #4126 — Fix issue where GUI sankey shows occasional -1s due to unaligned counts
- **URL:** https://github.com/firedancer-io/firedancer/issues/4126
- **Relevance:** The root cause is that tiles write metrics snapshots at different times in their housekeeping loops (`METRICS_WRITE`), so the metric consumer sees partially-updated counts. Tickoni's `tkmetr` tile reads per-tile counters from multiple tiles; without aligned write intervals, queue-depth and throughput snapshots will have the same transient -1 artifact.

### #7629 — solcap: fflush on shutdown
- **URL:** https://github.com/firedancer-io/firedancer/issues/7629
- **Relevance:** The issue describes a general problem: tiles that write critical data (in solcap's case, capture data; in Tickoni's case, `tkaudt` audit records) do not flush their buffers on certain crash paths like `FD_LOG_CRIT`. Tickoni's audit correctness claim requires that in-flight audit records reach disk or the JSONL buffer before the process exits.

### #811 — Async signal deadlock in fd_log / FD_ONCE
- **URL:** https://github.com/firedancer-io/firedancer/issues/811
- **Labels:** Priority: Low
- **Relevance:** Re-entrant signal delivery (SIGINT arriving while another signal is being handled) can deadlock `fd_log_private_cleanup` via `fd_yield` in a spin loop waiting for a lock already held by the interrupted signal handler. All Tickoni tiles use `fd_log` for crash reporting. A deadlock on `FD_LOG_CRIT` during an audit write or policy evaluation crash would silently suppress the crash report.

### #1013 — Switch metrics tile to do chunked response encoding
- **URL:** https://github.com/firedancer-io/firedancer/issues/1013
- **Labels:** perf, Priority: Low, telemetry
- **Relevance:** The metrics HTTP endpoint currently buffers all metrics in memory before writing them to the connection. For Tickoni's `tkmetr` tile, which exports per-tile financial event counters and queue depths, chunked streaming avoids an unbounded buffer allocation proportional to tile count.

### #1456 — fddev flame doesn't show kernel time
- **URL:** https://github.com/firedancer-io/firedancer/issues/1456
- **Labels:** perf, Priority: Low, debugging
- **Relevance:** When a tile is blocked in a futex or kernel call, the current `perf` invocation doesn't record that time in flamegraphs. For Tickoni tile profiling (e.g., understanding why `tkaudt` write latency spikes), knowing how much time is spent in kernel vs. userspace is critical. The fix (different perf sampling flags) would also benefit Tickoni tile profiling.

---

## Build Tooling

### #10105 — zig cc support
- **URL:** https://github.com/firedancer-io/firedancer/issues/10105
- **Relevance:** Tickoni is Zig-native and already uses `build.zig`. Supporting `zig cc` as a Make extra for the Firedancer C substrate would enable libc-free / statically linked builds of the C primitives Tickoni wraps, reducing runtime dependencies and simplifying containerized deployment.

### #6038 — gcc + UBSAN leads to build issues
- **URL:** https://github.com/firedancer-io/firedancer/issues/6038
- **Relevance:** UBSAN with GCC fails to build several files in `src/util/log` and `src/disco/topo`, which are part of Tickoni's C substrate. Fixing or clearly documenting GCC+UBSAN support unblocks sanitizer builds of Tickoni's inherited C layer.

### #5093 — [MSan] Unit tests / fuzz regtests in CI
- **URL:** https://github.com/firedancer-io/firedancer/issues/5093
- **Labels:** Priority: High
- **Relevance:** MSan CI for the unit tests and fuzz regression corpus catches uninitialised-read bugs in the C substrate Tickoni wraps. Particularly important for `src/tango`, `src/util`, and `src/disco/topo` — all directly used by Tickoni's tile runtime.

### #5614 — fddev flame doesn't work on Ubuntu
- **URL:** https://github.com/firedancer-io/firedancer/issues/5614
- **Relevance:** Most Tickoni development and deployment happens on Ubuntu. The `fddev flame` flamegraph command uses `perf script flamegraph` which is Fedora-only. A portable flamegraph solution is needed for Tickoni performance work and tile hot-path profiling.

### #3476 — Reproduce and triage LLVM memcpy sz==0 bug
- **URL:** https://github.com/firedancer-io/firedancer/issues/3476
- **Relevance:** An LLVM bug where `memcpy` with `sz==0` generates incorrect code affects the C substrate shared by Tickoni. Producing a minimal reproducer and filing it upstream would protect Tickoni from silent miscompilations in its C ABI layer.

### #3339 — Add an option for `make asm` Intel syntax
- **URL:** https://github.com/firedancer-io/firedancer/issues/3339
- **Relevance:** Developer tooling: `make asm` is used to review generated assembly for hot paths in `src/tango` and `src/util`. Intel syntax is preferred by many developers and is more readable for reviewing Tickoni tile hot paths.

---

## Code Quality / Static Analysis

### #10058 — CodeQL tests failing due to included filter and stale expected files
- **URL:** https://github.com/firedancer-io/firedancer/issues/10058
- **Relevance:** The CodeQL test suite (ReturnZeroForPointer, TrivialMemcpy, NonBinaryIsFunction) checks C code quality across `src/`. Tickoni's C substrate lives in those same paths. Broken CodeQL tests mean these checks are silently not running on the shared C layer.

### #3113 — CodeQL lint for implicit integer truncation
- **URL:** https://github.com/firedancer-io/firedancer/issues/3113
- **Labels:** linting
- **Relevance:** Implicit `ulong → ushort` truncations in `src/util` and `src/tango` are a source of subtle bugs (wrong queue depths, wrong sizes). Tickoni's financial event envelopes pass sizes through this substrate; silent truncations could corrupt message framing.

---

## Workspace Memory Safety

### #989 — Add guard pages around workspaces
- **URL:** https://github.com/firedancer-io/firedancer/issues/989
- **Labels:** security, Priority: Medium
- **Relevance:** Workspaces are mapped to random addresses, but adjacent gigantic-page allocations (~1 in 400k chance) could end up contiguous. A workspace overrun then silently corrupts the next workspace. Tickoni's audit (`tkaudt`) and event-queue workspaces hold financial records; guard pages prevent silent inter-workspace corruption.

### #1149 — Add canaries to workspace allocations
- **URL:** https://github.com/firedancer-io/firedancer/issues/1149
- **Labels:** security, Priority: Medium
- **Relevance:** Canary values around workspace sub-allocations detect overruns before they corrupt adjacent objects. Directly applicable to Tickoni's tile workspaces for event queues, audit buffers, and dedup tables.

### #1152 — Split metrics workspace into N, one per tile
- **URL:** https://github.com/firedancer-io/firedancer/issues/1152
- **Labels:** security, Priority: Medium
- **Relevance:** All tiles currently write to a single shared metrics workspace. A compromised tile can corrupt every other tile's metrics. Per-tile metric workspaces confine blast radius: a compromised `tkadpt` adapter tile cannot poison `tkaudt` or `tkpoly` metric counters.

### #2070 — Use memfd_create and fexecve to run tiles with no memory overlap
- **URL:** https://github.com/firedancer-io/firedancer/issues/2070
- **Labels:** security
- **Relevance:** Launching tiles from a shared binary on disk maps the `.TEXT` section into all tile processes. `memfd_create` + `fexecve` eliminates this shared mapping. Tickoni's crash-only tile model requires strong tile isolation; shared text pages are a lateral-movement vector between tiles.

---

## Security Hardening

### #4630 — Checksec CI integration
- **URL:** https://github.com/firedancer-io/firedancer/issues/4630
- **Labels:** security
- **Relevance:** `checksec` verifies that binaries are built with stack canaries, NX, RELRO, and PIE. Tickoni binaries are built on the same Makefile infrastructure and should pass the same binary hardening checks before any production deployment.

### #2554 — fd_keyload_load should check that keypair matches
- **URL:** https://github.com/firedancer-io/firedancer/issues/2554
- **Labels:** security, Priority: Medium
- **Relevance:** Ed25519 security requires that the public key matches the private key; loading a mismatched JSON key file can compromise the private key. Tickoni will load signing keys for `tkexec` signed action envelopes and `tksign`. This validation should be enforced before any key material is used.

### #2567 — Check file permissions in fd_keyload_load
- **URL:** https://github.com/firedancer-io/firedancer/issues/2567
- **Relevance:** World-readable key files are a common operator mistake. Tickoni loads key material for signed adapter envelopes and executor boundaries. Refusing to load world-readable keys (like OpenSSH) adds a safety rail for operators.

### #8044 — fixup event tile seccomp policy
- **URL:** https://github.com/firedancer-io/firedancer/issues/8044
- **Labels:** security
- **Relevance:** The event tile's seccomp rule for `socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, 0)` is commented out because enabling it causes SIGSYS — meaning the actual syscall arguments don't match the filter. Tickoni tiles that connect to external systems (e.g., `tkmodl` connecting to an LLM server endpoint) need the same socket syscall pattern. This shows the seccomp filter writing process needs test coverage.

### #673 — Add checks on /proc/maps as part of sandboxing
- **URL:** https://github.com/firedancer-io/firedancer/issues/673
- **Labels:** security, Priority: Medium
- **Relevance:** After entering the sandbox, verify that no unexpected shared pages are mapped; shared pages could enable cross-tile sandbox escape via ROP gadgets. Tickoni's tile sandbox model inherits this gap. Particularly important for `tkpoly` and `tkaudt` tiles that must not be escapable via a compromised adjacent tile.

### #5173 — Switch to mbedTLS
- **URL:** https://github.com/firedancer-io/firedancer/issues/5173
- **Relevance:** mbedTLS aligns better with Firedancer's (and Tickoni's) sandboxing model than OpenSSL. Tickoni's `tkadpt` adapters will connect to HTTPS financial APIs; mbedTLS's small footprint and explicit memory management fit the sandboxed tile environment better than OpenSSL's large attack surface.

---

## CI / Developer Tooling

### #1247 — ci: C problem matcher
- **URL:** https://github.com/firedancer-io/firedancer/issues/1247
- **Relevance:** Add a GCC/Clang problem matcher JSON file and wire it into GitHub Actions with `::add-matcher`. Build errors from parallel `make -j` then appear as inline PR annotations instead of buried log lines. Tickoni uses the same Makefile CI and has the same needle-in-a-haystack problem with parallel C builds. Pure config — no code change.

### #177 — Add line number info to backtraces
- **URL:** https://github.com/firedancer-io/firedancer/issues/177
- **Relevance:** Tickoni's crash-only tile model means tiles crash and the supervisor reaps them. Without line numbers, the backtrace from a crashed `tkaudt`, `tkpoly`, or `tknorm` is nearly useless for post-mortem. For a financial harness where a crash during audit write or policy evaluation needs a clear root cause, symbol+line resolution in the backtrace is essential. No special hardware needed to implement or test.

---

## Testing Infrastructure

### #1495 — Add comprehensive unit tests for tiles
- **URL:** https://github.com/firedancer-io/firedancer/issues/1495
- **Labels:** Priority: Medium, testing
- **Relevance:** Generic request to add per-tile unit tests covering normal operation, error paths, and boundary inputs. Directly applicable to Tickoni: `tkings`, `tknorm`, `tkdedu`, `tkpoly`, and `tkaudt` all need unit tests that exercise the same patterns (normal event flow, malformed input, backpressure, replay).

### #4252 — Revive test_dedup
- **URL:** https://github.com/firedancer-io/firedancer/issues/4252
- **Labels:** Priority: Low
- **Relevance:** `src/disco/dedup/test_dedup.c` was commented out after the stem-ification of the dedup tile. Tickoni's `tkdedu` is built on the same stem-based pattern. Restoring this test shows how to write a unit test for a stem-based tile, which is the exact pattern Tickoni needs for testing its dedup and normalization tiles.

### #5190 — resolv: seccomp policy integration test
- **URL:** https://github.com/firedancer-io/firedancer/issues/5190
- **Relevance:** Write harnesses that exercise every syscall a tile makes and verify they don't cause SIGSYS under the tile's seccomp policy. This is the testing pattern Tickoni needs for all its sandboxed tiles (`tkpoly`, `tkaudt`, `tkmodl`, `tkadpt`). Fixing it for the resolv tile establishes the template.

### #148 — util: improve fd_cstr test coverage
- **URL:** https://github.com/firedancer-io/firedancer/issues/148
- **Labels:** good first issue, Priority: Low, testing
- **Relevance:** `fd_cstr_casecmp`, `fd_cstr_to_ulong_octal`, `fd_cstr_append_printf`, `fd_cstr_append_cstr`, `fd_cstr_hash` and related functions are uncovered. These are utility functions used throughout Tickoni's C substrate for config parsing and event field handling.

---

## CLI / Developer UX

### #7108 — Parse CLI args before creating log file
- **URL:** https://github.com/firedancer-io/firedancer/issues/7108
- **Relevance:** Tickoni's dev binary (`tickoni-dev` or equivalent) will have CLI subcommands. Creating a log file when running `--help` or `--version` is confusing and leaves unwanted temp files. The same fix should be applied to the Tickoni CLI.

### #5098 — Allow overriding config options via command-line
- **URL:** https://github.com/firedancer-io/firedancer/issues/5098
- **Relevance:** Tickoni's supervisor loads a TOML config. Being able to override individual fields from the command line (`tickoni-dev --hugetlbfs.max_page_size huge`) is important for tile-count experiments, test fixture overrides, and CI parametrization without maintaining many config files.

### #6222 — Cannot run fdctl without logs
- **URL:** https://github.com/firedancer-io/firedancer/issues/6222
- **Relevance:** Running Tickoni commands with `--log-path ''` should suppress file logging. The same boot-path issue exists in the shared `fd_boot.c` that Tickoni's C ABI layer calls into.

### #7906 — firedancer-dev stderr log has no color with --no-sandbox --no-clone
- **URL:** https://github.com/firedancer-io/firedancer/issues/7906
- **Relevance:** `tickoni-dev` uses the same boot procedure and `--no-sandbox` / `--no-clone` flags for local development. The stderr buffering and color bug affects developer UX during tile debugging.

### #6997 — backtest watch feature hides important error messages
- **URL:** https://github.com/firedancer-io/firedancer/issues/6997
- **Relevance:** The `--watch` terminal UI can drop or hide `CRIT`/`ERR` log lines from the boot sequence (e.g., workspace resize needed, topology abort). Tickoni's `tickoni-dev --watch` mode has the same issue. When a tile crashes during startup, the error is swallowed by the TUI, making it appear to hang rather than fail.

### #4540 — fdctl mem does a user check
- **URL:** https://github.com/firedancer-io/firedancer/issues/4540
- **Relevance:** The `mem` diagnostic command refuses to run if the current UID differs from the config's UID, preventing operators or CI scripts from inspecting memory layout without switching users. Tickoni's `tickoni mem` command would have the same limitation.

### #4296 — CLI should not require config file for running validators
- **URL:** https://github.com/firedancer-io/firedancer/issues/4296
- **Relevance:** Auxiliary commands (`monitor`, `mem`, `configure check`) should auto-discover the running instance's config rather than requiring `--config`. The same usability gap exists for Tickoni's diagnostic commands (`tickoni monitor`, `tickoni diag`), which operators may run without having the original config at hand.

### #2297 — Warn if IRQ overlaps with fixed tile assignments
- **URL:** https://github.com/firedancer-io/firedancer/issues/2297
- **Labels:** Priority: Low
- **Relevance:** Tiles with fixed CPU assignments use 100% of that core. If irqbalance schedules a soft-IRQ on the same core, throughput drops unpredictably. Tickoni's policy and audit tiles are latency-sensitive. A startup warning when IRQ affinity overlaps with tile assignments would surface this class of operator configuration error.

### #3505 — Document reverse proxy setup
- **URL:** https://github.com/firedancer-io/firedancer/issues/3505
- **Labels:** operator
- **Relevance:** Tickoni's `tkapi` WebSocket endpoint will face the same issue as Firedancer's GUI when placed behind an NGINX or Caddy reverse proxy: the browser or client initiates an insecure WebSocket request, which the proxy rejects or mangles. Documenting the required `upgrade-insecure-requests` CSP header or WSS configuration applies directly to `tkapi` deployment.

---

## Network Tile Infrastructure

### #5490 — Clean up net tile flow steering
- **URL:** https://github.com/firedancer-io/firedancer/issues/5490
- **Relevance:** The sock, xdp, and ibeth net tiles hardcode link names and port numbers. Making them use topo link IDs instead would make the net tile stack reusable for Tickoni's ingestion path (`tkings`) without Solana-specific port assumptions baked in.

---

## Compression / JSONL

### #9829 — yyjson instead of cJSON
- **URL:** https://github.com/firedancer-io/firedancer/issues/9829
- **Relevance:** Tickoni's `tkaudt` tile emits JSONL audit records. yyjson is faster, has a cleaner API, and supports operation without a heap allocator — all relevant for a high-throughput tile that emits a JSON line per audited event.

### #7540 — Generalize pzstd-style compression
- **URL:** https://github.com/firedancer-io/firedancer/issues/7540
- **Relevance:** At volume, Tickoni's audit JSONL output will need compression for durable export and partner review. The parallel Zstandard framing being cleaned up here, switched to the standard pzstd format, would give Tickoni a reusable compression primitive for audit log rotation and export.


# Priority

Issues sorted by effort. The main corrections versus earlier notes: #4630 and
#3113 are config/Easy, not Moderate; #4428 and #4591 are Easy, not Trivial
(each requires understanding a non-obvious invariant before touching a line);
#7108 is Medium, not Small (reordering boot init requires confirming nothing
depends on the log being live before the item being moved).

---

## Trivial

Config, text, or 1-line change. Verifiable without running the full system.

| Issue | What to do |
| --- | --- |
| #1247 — CI C problem matcher | Add a JSON problem-matcher file and one `add-matcher` line in the workflow. No code. |
| #3339 — make asm Intel syntax | Add `ASMFMT ?= att` and pass `-masm=$(ASMFMT)` in the Makefile. One line. |
| #4630 — Checksec CI | New `.github/workflows/checksec.yml`; install `checksec-action`, run against built binaries. No code change. |
| #3505 — Reverse proxy docs | Document the `upgrade-insecure-requests` CSP header / WSS config for NGINX/Caddy. Markdown only. |
| #10058 — CodeQL expected-file cleanup | Fix stale filter paths and expected-output files so the existing CodeQL checks actually run. Pure config. |

---

## Easy

5–30 lines, self-contained, any development laptop, well-bounded blast radius.

| Issue | What to do |
| --- | --- |
| #4591 — heap_verify equal-key crash | `fd_heap.c:643–651`: change `HEAP_TEST( HEAP_(lt)( pool+i, pool+r ) )` to `HEAP_TEST( !HEAP_(lt)( pool+r, pool+i ) )`. Two lines — but confirm the heap invariant ("child not less than parent") before touching anything. |
| #4428 — Auto affinity offline CPUs | Add `\|\| !cpus->cpu[ cpu_ordering[cpu_idx] ].online` to the skip condition in `auto_tile_cpu` (fd_topob.c:474). The same pattern exists at line 660. Reproduce with `echo 0 \| sudo tee /sys/devices/system/cpu/cpu10/online`. |
| #2567 — Keyload file permissions | After `open()` in `fd_keyload.c:63`, add `fstat(key_fd, &st)` and check `st.st_mode & (S_IROTH \| S_IWOTH)`. `FD_LOG_ERR` and close if world-readable. ~8 lines. |
| #2554 — Keypair consistency | After loading 64 bytes, derive the expected public key from `bytes[0..31]` via `fd_ed25519_public_from_private()`, then `memcmp` against `bytes[32..63]`. Zeroize and `FD_LOG_ERR` on mismatch. Crypto primitive is in `src/ballet/ed25519/`. ~15 lines. |
| #3962 — HTTP 400 on parse error | In the parse-error branch of `src/waltz/http/`, invoke the existing error-response path before connection teardown. ~10 lines; no new machinery. |
| #3476 — LLVM memcpy sz==0 reproducer | Write a ~10-line C file that triggers the miscompilation and file it upstream with LLVM. No in-repo fix needed. |
| #148 — fd_cstr test coverage | Add test cases for `fd_cstr_casecmp`, `fd_cstr_append_printf`, `fd_cstr_hash`, etc. to the existing test harness. No new infrastructure. |
| #6222 — Run without logs | Pass `NULL` to the log-path handler; the plumbing in `fd_log.c:1002` already accepts `NULL` to disable file logging. |
| #7906 — Stderr color `--no-sandbox` | Fix the tty detection / buffering path so color works on stderr when running without the sandbox clone. Small. |
| #1456 — fddev flame kernel time | Change the `perf` sampling flags (add `-g --call-graph dwarf` or equivalent) so kernel time appears in flamegraphs. Script change only. |
| #5614 — fddev flame Ubuntu | Replace the Fedora-only `perf script flamegraph` invocation with a portable alternative (e.g. `flamegraph.pl` from Brendan Gregg's repo). |
| #4540 — mem user check | Remove or conditionalize the UID equality guard so operators and CI scripts can run `tickoni mem` without switching users. |
| #9726 — Log slow hugetlbfs steps | Add a timestamp before and after each hugetlbfs startup step (`mount`, `echo nr_hugepages`, etc.) and log any step that exceeds 100 ms. |
| #2353 — MAP_remove validation | In `map_remove`, validate that the entry pointer is non-null and still a valid map member before decrementing `key_cnt`. ~10 lines. |
| #3113 — CodeQL integer-truncation query | Write a new `.ql` file in `contrib/codeql/src/` using the existing implicit-conversion predicate to flag `ulong → ushort` (and similar) truncations in `src/`. `filter.qll` already handles path scoping. |

---

## Medium

Requires understanding a subsystem or touching multiple files. No specialized
hardware. Expect 1–3 days of focused work.

| Issue | What to do |
| --- | --- |
| #7108 — CLI args before log file | Move log-file creation in `fd_boot.c` past the `--help`/`--version` exits. Confirm nothing between those exits and the current log-init call depends on the log being live. |
| #9829 — yyjson instead of cJSON | Migrate every cJSON call site to the yyjson API. Audit `src/` for all uses before starting. |
| #6038 — gcc+UBSAN build errors | Track down each `-Werror` failure in `src/util/log` and `src/disco/topo` under GCC+UBSAN; fix or clearly document suppressions. |
| #2466 — privileged_init barrier | Enforce that all tiles complete `privileged_init` before any tile enters its run loop. Requires a startup-sequencing change in the supervisor. |
| #4252 — Revive test_dedup | Restore `test_dedup.c`, adapt it to the current stem-based tile API, and wire it into the build. This establishes the unit-test template for stem tiles. |
| #4905 — fd_topob unit tests | Write unit tests for `fd_topob` covering NUMA affinity, workspace allocation, and topology construction. No new code in the library; tests only. |
| #5098 — CLI config overrides | Add a `--set key=value` mechanism for TOML config overrides on the command line. Touches config parsing and all downstream consumers. |
| #6997 — Watch hides boot errors | Fix the TUI so CRIT/ERR lines from the boot sequence are not swallowed when running with `--watch`. |
| #4296 — Auto-discover config | Allow `monitor`, `mem`, and `diag` subcommands to find the running instance config via `/proc` or a pid file rather than requiring `--config`. |
| #177 — Backtrace line numbers | Integrate `addr2line` or DWARF line-info lookup into `fd_log`'s crash-report path so backtraces from crashed tiles include file:line. |
| #1883 — Right-size memory | Audit all tango ring depths, workspace allocations, and buffer pools against realistic Tickoni event rates (not mainnet Solana scale). Right-size and document. |
| #8101 — Increase frag_meta_t sz | Enlarge the `sz` field in `frag_meta_t` and remove all the hacks that work around the current cap. Audit every downstream size-check site. |
| #9980 — stdatomic for util/tmpl | Migrate `pool_para`, `map_chain_para`, and `map_slot_para` from `volatile` + `__sync` GCC API to C11 `stdatomic`. Enables TSan. |
| #826 — dcache bounds at link layer | Move fragment bounds checking from per-tile `during_frag` into the link layer so all tiles get automatic protection. Touches the tile pipeline interface. |
| #4126 — Metrics aligned counts | Coordinate housekeeping `METRICS_WRITE` intervals across tiles so metric consumers see consistent snapshots rather than transient −1s. |
| #7629 — fflush on crash paths | Add buffer flush to the `FD_LOG_CRIT` crash handler for tiles that write critical data (audit records, capture data) so in-flight writes reach disk before exit. |
| #1013 — Chunked metrics response | Switch the metrics HTTP endpoint from buffering all metrics before writing to chunked streaming. Prevents an unbounded allocation proportional to tile count. |
| #10105 — zig cc Makefile support | Add `CC ?= zig cc` support to the Firedancer Makefile so the C substrate can be built with `zig cc` for static / libc-free deployments. |
| #5093 — MSan CI | Wire MSan into CI for unit tests and fuzz regression corpus. Investigate and fix each uninitialised-read finding in `src/tango`, `src/util`, `src/disco/topo`. |
| #989 — Guard pages for workspaces | Insert `mprotect(PROT_NONE)` guard pages between adjacent hugetlb workspace allocations to catch inter-workspace overruns. |
| #1149 — Workspace allocation canaries | Write magic-value canaries around workspace sub-allocations and verify them on teardown to catch overruns before they corrupt adjacent objects. |
| #1152 — Split metrics workspace per tile | Give each tile its own metrics workspace so a compromised tile cannot corrupt another tile's counters. Changes workspace layout and all metric readers. |
| #8044 — Seccomp policy socket fix | Determine why `socket(AF_INET, SOCK_STREAM\|SOCK_NONBLOCK, 0)` causes SIGSYS under the event tile's seccomp filter, fix the rule, and add a test that would have caught the mismatch. |
| #673 — /proc/maps check post-sandbox | After entering the sandbox, parse `/proc/self/maps` and assert no unexpected shared pages are present. |
| #7278 — Auto affinity respects CPU set | Make the `auto` affinity mode call `sched_getaffinity` first and constrain tile placement to the process's existing CPU set (cgroup/systemd). |
| #2300 — IRQ affinity configure | Automate sysfs IRQ pinning in the `configure` step so ksoftirqd is not scheduled on the same cores as latency-sensitive tiles. |
| #3464 — fd_pod workspace directory | Design and implement an `fd_pod`-style metadata directory at a known offset in each workspace so tools and `tkdiag` can discover objects without re-parsing the topology. |
| #5190 — Seccomp integration test template | Write a harness that exercises every syscall a tile makes and verifies none cause SIGSYS under that tile's seccomp policy. The `resolv` tile is the first target; the pattern then applies to all Tickoni tiles. |
| #5490 — Net tile flow steering cleanup | Replace hardcoded link names and port numbers in `sock`, `xdp`, and `ibeth` with topo link IDs so the net tile stack is reusable outside Solana port assumptions. |
| #7540 — Generalize pzstd compression | Switch the parallel Zstandard framing to the standard pzstd format and clean up the API for reuse as a compression primitive in audit log rotation. |

---

## Hard

Specialized platform knowledge, security-critical correctness, or major
architectural change. Budget a week or more; some require non-x86 hardware.

| Issue | Why it is hard |
| --- | --- |
| #9838 — Torn reads in fd_stem | The AVX atomic is x86-only. A correct portable fix requires understanding the non-x86 memory model and finding a substitute with comparable performance — and hardware to test on. |
| #2352 — fd-mux OOB via crafted depth | The fix must close an adversarial-tile OOB path in the hot fragment-receive loop without adding overhead or breaking correctness for honest tiles. |
| #2297 — Warn on IRQ overlap | At startup, compare each tile's fixed CPU affinity mask against `/proc/irq/*/smp_affinity`. Log a warning on overlap. |
| #1360 — Futex cooperative core sharing | Requires deep OS scheduling knowledge, futex API, and careful benchmarking to confirm that non-critical tiles sharing a core do not starve critical tiles under load. |
| #664 — Move logging to dedicated tile | Architectural: all existing tile log calls become IPC to a new log tile. Affects every tile, the supervisor, and crash-path guarantees. |
| #811 — Async signal deadlock in fd_log | Signal handler reentrancy is extremely subtle. The spin-lock in `fd_log_private_cleanup` and the `fd_yield` path interact with signal delivery in ways that are hard to reason about and easy to re-introduce in a fix. |
| #2070 — memfd_create + fexecve | Changes the whole-process launch model: the supervisor must create and `fexecve` a per-tile in-memory binary. Affects how the tile image is built, linked, and verified. |
| #5173 — Switch to mbedTLS | Large TLS library migration. mbedTLS and OpenSSL have very different APIs, memory models, and feature sets; all HTTPS-touching code in `tkadpt` and beyond must be ported. |
| #1495 — Comprehensive tile unit tests | Requires mocked tango queues, a full stem-tile test harness, and coverage of normal flow, malformed input, backpressure, and replay — new infrastructure that does not exist yet. |