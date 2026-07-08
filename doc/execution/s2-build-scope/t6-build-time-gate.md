# V1.21.S2.T6 — Build-Time Gate for Retail Targets

**Epic:** V1.21 Cross-Platform Retail Runtime Support
**Story:** V1.21.S2 Build scope filter for retail targets
**Task:** V1.21.S2.T6 Define the build-time gate mechanism

## Summary

Retail targets (macOS, Windows) must fail fast at compile time when they
reference a Firedancer symbol that is not included in the narrowed library
set. This task defines the gate mechanism — compile-time checks, error messages,
and fallback behavior — so that retail builds do not silently succeed with
missing symbols or silently pull in Linux-only code.

## Gate Mechanism

The build-time gate operates in three layers:

### Layer 1: Build Target Declarations

Each retail target (macOS, Windows) declares which Firedancer symbols it
requires. The build system validates that every required symbol is exported
by at least one included archive. If not, the build fails before compilation
starts.

Declaration location: per-target config in `build.zig` or a separate manifest
file (e.g., `build/fd-tickoni-fd/s2-target-declarations.json`).

Example declaration:

```json
{
  "target": "macos-retail",
  "required_symbols": [
    "fd_mcache_load",
    "fd_dcache_load",
    "fd_fseq_load",
    "fd_pod_find",
    "fd_pb_encode",
    "fd_pb_tokenize",
    "fd_http_server_listen"
  ],
  "excluded_symbols": [
    "fd_shmem_admin",
    "fd_io_uring_setup",
    "fd_sandbox_init",
    "fd_xdp_tile",
    "fd_quic_tile"
  ]
}
```

### Layer 2: Shim-Level Gate

Each C ABI shim must declare which Firedancer headers it depends on. At build
time, the gate checks that every header's required symbols are available in
the compiled archives for that target.

Shim dependency declarations (auto-generated or hand-written):

```
util.c     → fd_util.h, fd_util_base.h, fd_rng.h, fd_wksp.h, fd_sandbox.h
ballet.c   → fd_pb_encode.h, fd_pb_tokenize.h
tango.c    → fd_cnc.h, fd_dcache.h, fd_fctl.h, fd_fseq.h, fd_mcache.h, fd_rng.h, fd_tempo.h
wksp.c     → fd_util.h, fd_wksp.h
sandbox.c  → fd_sandbox.h, fd_util.h
topob.c    → fd_cnc.h, fd_dcache.h, fd_fseq.h, fd_mcache.h, fd_metrics.h, fd_pod_format.h, fd_topob.h, fd_util.h
topo_run.c → fd_topo.h, fd_util.h
tile_run.c → fd_topo.h, fd_util.h
```

Gate check: for each shim on a retail target, verify that all headers in the
dependency list are available in the retail-compiled Firedancer archives. If
any header resolves to a Linux-only definition, the build fails with:

```
ERROR: retail target cannot resolve symbol from shim 'wksp.c':
  required header: fd_wksp.h
  missing symbol: fd_wksp_hugetlb_alloc (defined in libfd_util.a, requires hugetlbfs)
  resolution: use wksp_retail.c (heap-backed workspace adapter) instead
```

### Layer 3: Zig Build-Time Assertions

The Zig build (`build.zig`) must include runtime assertions that verify the
C ABI shim set is complete before attempting compilation. If a required shim
file is missing, compilation stops with a clear error.

Pseudocode:

```zig
// build.zig — retail target gate
const retail_shim_set = .{
    .util_c = true,
    .ballet_c = true,
    .tango_c = true,
    .wksp_c = if (target.result.os.tag == .windows) .wksp_retail_c else .wksp_c,
    .sandbox_c = if (target.result.os.tag == .windows) .sandbox_retail_c else .sandbox_c,
    .topo_run_c = true,
    .topob_c = true,
    .tile_run_c = true,
};

// Gate: fail if any required shim is missing
for (retail_shim_set) |name| {
    if (!std.fs.path.exists(build_dir)) {
        @compileError("required shim missing for retail target: " ++ name);
    }
}
```

## Error Message Standards

All gate errors must include:
1. The target being built (e.g., `macos-retail`, `windows-retail`)
2. The shim or file that triggered the failure
3. The missing or unresolved symbol
4. The Firedancer archive that should contain it (or note that it's Linux-only)
5. A recommended resolution (use retail shim, exclude feature, or report as unsupported)

## Fallback Behavior

When a gate fails, the build does not attempt partial compilation. It stops
immediately with the structured error. No fallback to "best effort" linking.

Retail targets that cannot resolve all required symbols for their intended
feature set should be classified as "unsupported" rather than built with
partial functionality.

## Acceptance Criteria

- [ ] Given a retail build targeting a symbol not included in the narrowed archive set, when the build runs, then compilation fails with a structured error naming the symbol, the archive, and a recommended resolution.
- [ ] Given a retail build where a required shim file is missing, when the Zig build runs, then a compile-time error is produced naming the missing shim.
- [ ] Given a retail build where all required symbols and shims resolve, then compilation proceeds normally.

### Conditional Acceptance

**Financial capability and policy** — N/A. Build gate does not change policy outcomes.
**Audit and replay** — N/A. Build gate does not affect audit/replay semantics.
**Runtime topology and tile ownership** — N/A. Build gate is compile-time, not runtime topology.
**Model, tool, adapter, or execution boundary** — N/A. Build gate does not modify model/tool/adapter boundaries.
**CaseOps API or UI** — N/A. Story affects build, not API or UI.

### Quality Gate

- [ ] Build-time gate mechanism is codified before macOS/Windows implementation stories start.
- [ ] Every retail target has a declared symbol set and excluded symbol list.
- [ ] Gate errors follow the standard format (target, shim, symbol, archive, resolution).
- [ ] No retail build can succeed with unresolved symbols or missing required shims.
- [ ] Documentation and roadmap status are updated when gate rules change.

### Notes And Open Questions

- Should the gate be enforced at build time (compile errors) or also at runtime (startup checks)?
- How do we handle Firedancer updates that add or remove symbols in included archives?
- Should the gate produce a machine-readable report (JSON) in addition to human-readable errors?
