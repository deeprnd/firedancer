# V1.21.S2.T4 — Target-Specific Linking Rules

**Epic:** V1.21 Cross-Platform Retail Runtime Support
**Story:** V1.21.S2 Build scope filter for retail targets
**Task:** V1.21.S2.T4 Define target-selected linking rules

## Summary

Tickoni C ABI shims link against exactly five Firedancer archives:
`libfd_tango.a`, `libfd_util.a`, `libfd_ballet.a`, `libfd_disco.a`,
`libfd_waltz.a`. Retail targets (macOS, Windows) may not link any of these
archives against Linux-only symbol sets. This task defines the linking rules
per target and per archive, so that when a retail build runs, it compiles only
the shims that have portable symbol resolution and fails the build for any
shim that pulls in a Linux-only symbol.

## Linking Matrix

| Archive | Linux (full-runtime) | macOS (retail) | Windows (retail) |
|---------|---------------------|----------------|-----------------|
| `libfd_tango.a` | Link as-is | Compile shim; resolve only mcache, dcache, fseq, fctl, cnc, tempo. Fail if rng.h or other tango symbols require Linux-only paths. | Link as compiled by cross-compiler or stub shim |
| `libfd_util.a` | Link as-is | Shim excludes sandbox.c (stubbed), wksp.c replaced with heap-backed adapter. Link only util symbols that resolve without hugetlbfs, mlock, io_uring, shmem_admin. | Shim excludes sandbox.c, wksp.c, io_uring, shmem. Link util subset that resolves on Windows. |
| `libfd_ballet.a` | Link as-is | Link as-is (protobuf encoder/tokenizer has no OS dependency) | Link as-is |
| `libfd_disco.a` | Link as-is | Compile shim; resolve topob, topo_run, tile_run only. Disco includes metrics.h and pod_format.h — verify no Linux-only dependencies. | Compile shim; resolve same subset. |
| `libfd_waltz.a` | Link as-is | Link as-is (HTTP server is POSIX; may need stub for Windows winsock/WSA) | Link as stubbed shim |

## Shims That Must Be Conditional

The following shims contain symbol references that may not resolve on retail targets:

1. `sandbox.c` — calls seccomp/Landlock/user namespaces. Must stub for retail.
2. `wksp.c` — calls hugetlbfs, mlock, shared memory. Must use heap-backed workspace for retail.
3. `tile_run.c` — depends on disco tile infrastructure; may need retail stub.
4. `topo_run.c` — depends on disco topology runner; verify symbol scope on retail.

Retail linking rules:

- Each shim must compile under `__APPLE__` (macOS) and `__MINGW32__`/`__MINGW64__` (Windows).
- If a shim cannot be made portable, it must be excluded from the retail shim set and documented as "disabled on retail".
- The Zig build must emit a compile error if any shim file is missing but a target still requires it.

## Zig Build Conditions

Use `build.zig` comptime conditions to gate shim compilation per target:

```zig
// Pseudocode — exact mechanism TBD in build-system integration task
const target = b.standardTargetOptions(.{});
const shim_list = [_][]const u8{
    "util.c",
    "ballet.c",
    "tango.c",
    if (target.result.os.tag != .windows) "wksp.c" else "wksp_retail.c",
    if (target.result.os.tag != .windows) "sandbox.c" else "sandbox_retail.c",
    "topo_run.c",
    "topob.c",
    "tile_run.c",
};
```

Retail shim set (`target.result.os.tag == .macOS or .windows`):
- `util.c` — yes (if symbols resolve)
- `ballet.c` — yes
- `tango.c` — yes (if symbols resolve)
- `wksp_retail.c` — yes (heap-backed workspace, no hugetlbfs/mlock/shmem)
- `sandbox_retail.c` — yes (no-op stub)
- `topo_run.c` — yes (if symbols resolve)
- `topob.c` — yes (if symbols resolve)
- `tile_run.c` — yes (if symbols resolve)

## Acceptance Criteria

- [ ] Given a Linux full-runtime build, when all five libraries are linked and all eight shims compile, then the build succeeds.
- [ ] Given a macOS retail build, when sandbox.c is replaced by a stub and wksp.c is replaced by a heap-backed adapter, then the build succeeds without Linux-only symbols.
- [ ] Given a Windows retail build, when sandbox.c and wksp.c are replaced by stubs, then the build succeeds.
- [ ] Given a retail build where a shim references a non-resolved Firedancer symbol (e.g. `fd_shmem_admin`, `fd_io_uring`), then compilation fails with a clear error naming the missing symbol and the affected shim.

### Conditional Acceptance

**Financial capability and policy** — N/A. Linking rules do not change policy.
**Audit and replay** — N/A. Build scope does not affect audit/replay semantics.
**Runtime topology and tile ownership** — N/A. This task defines compile-time linking rules, not runtime tile topology or ownership.
**Model, tool, adapter, or execution boundary** — N/A. Build-time linking does not modify model/tool/adapter boundaries.
**CaseOps API or UI** — N/A. Story affects build, not API or UI.

### Quality Gate

- [ ] Target-selected linking rules are codified before macOS/Windows implementation stories start.
- [ ] No retail shim can reference a Linux-only Firedancer symbol without a gate error.
- [ ] Documentation and roadmap status are updated when linking rules change.

### Notes And Open Questions

- Which Firedancer archives (`libfd_ballet.a`, `libfd_waltz.a`) have zero OS dependency and can be linked as-is on all targets?
- Should retail use pre-compiled Firedancer libraries (from a CI build artifact) or compile Firedancer source per-target?
- Does `libfd_disco.a` carry Solana semantics that Tickoni must not expose on retail targets?
