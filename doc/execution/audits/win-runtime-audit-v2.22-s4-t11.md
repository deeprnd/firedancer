# V2.22.S4.T11 — `win-runtime` Branch Audit

**Date**: 2025-08-05
**Branch**: `win-runtime` (26 commits ahead of main)
**Scope**: Windows runtime support (Zig boot, CRT compat, logging, tile threading, CPU topo)
**Files changed**: 66 (+3851/-341)

---

## FINDING 1 — CRITICAL: OS switches in non-shim non-build code ✅ DONE

OS switches (`FD_HAS_WINDOWS`, `builtin.target.os.tag`) previously existed in non-shim, non-build files. Resolved by splitting into per-platform files following the `topo_run_platform_*` pattern:

- **`src/disco/topo/fd_cpu_topo.c`** — replaced with thin dispatcher (15 lines). Platform logic moved to `fd_cpu_topo_platform_linux.c` and `fd_cpu_topo_platform_windows.c`. `fd_cpu_topo_platform.h` provides declarations.
- **`src/disco/topo/fd_topo.h`** — PATH_MAX redefine and `sock_filter` fwd-decl moved to `fd_topo_platform.h`.
- **`src/util/tile/fd_tile_threads.c`** — replaced with thin dispatcher (9 lines). Platform logic moved to `fd_tile_threads_platform_linux.c` (full Linux/macOS impl), `fd_tile_threads_platform_windows.c` (stub), and `fd_tile_threads_platform_macos.c` (delegates to Linux source with `__MACH__` defined).

**Files changed by fix**:
- Created: `fd_cpu_topo_platform.h`, `fd_cpu_topo_platform_linux.c`, `fd_cpu_topo_platform_windows.c`, `fd_cpu_topo_platform_macos.c`, `fd_topo_platform.h`, `fd_tile_threads_platform.h`, `fd_tile_threads_platform_linux.c`, `fd_tile_threads_platform_macos.c`, `fd_tile_threads_platform_windows.c`
- Modified: `fd_cpu_topo.c`, `fd_cpu_topo.h`, `fd_topo.h`, `src/disco/topo/Local.mk`, `src/util/tile/Local.mk`
- Unchanged (correctly already platform files): `fd_log_windows.c`, `fd_windows_compat.h`

**Files changed by subsequent fix** (circular include + macOS stub):
- Created: `fd_cpu_topo_platform_macos.c`
- Modified: `src/disco/topo/Local.mk` (add platform objs + macOS ifdef), `src/disco/topo/fd_cpu_topo.h` (remove circular include)

**Remaining OS switches** (acceptable — gated in shim/build files only):
- `src/util/log/fd_log_windows.c` — entirely Windows-specific (new file)
- `src/util/fd_windows_compat.h` — entirely Windows-specific compat header (new file)

---

## FINDING 2 — CRITICAL: Windows implementation is a stub, not functional

`fd_tile_threads.c` Windows path:
- `fd_tile_private_stack_new` → returns NULL (no stack allocation)
- `fd_tile_private_stack_delete` → no-op
- `fd_tile_private_cpu_config` → no-op
- `fd_tile_exec_new`/`fd_tile_exec` → always NULL
- `fd_tile_cpus_init` → returns 1 CPU, 1 NUMA
- `fd_log_private_cpu_id` → hardcoded to 0
- `fd_log_private_main_stack_sz` → hardcoded 1MB

`fd_cpu_topo.c` Windows path:
- Returns 1 CPU, 1 NUMA node, no topology discovery

These aren't "incomplete implementations" — they're **explicitly non-functional stubs**. The code will compile on Windows but tiles will not run on actual hardware (no CPU pinning, no stack management, no multi-tile dispatch). This is not shippable as Windows support.

---

## FINDING 3 — CRITICAL: `fd_log_windows.c` has no error path logging

`fd_log_private_1` — the function that formats and outputs log lines at warn/info/notice levels — is a **no-op** (void, no output). The entire logging stack only produces output at ERROR/FATAL level (via `fd_log_private_2` → `ExitProcess`). **Normal logs are silently dropped on Windows.**

---

## FINDING 4 — HIGH: Zig OS switches in doctor module (3 files, 11 occurrences)

`src/tickoni/doctor/checks.zig` uses `builtin.target.os.tag` in 11 places:
- `detectOsVersion()` — platform-specific version detection (Linux: `/etc/os-release`, macOS: `sw_vers`, Windows: no-op)
- `detectEnvironment()` — WSL/container/VM detection via `/proc/` paths
- `WindowsChecks` struct — `checkWindowsBuildNumber`, `checkWSL2`, `checkDockerDesktop` all branch on `os_tag`

`src/tickoni/util/tier.zig` uses `builtin.target.os.tag` in 2 places (existing code, pre-branch).

**Assessment**: Doctor module is **expected** to be platform-aware (it's a diagnostic tool). This is acceptable, but the WSL2 and Docker checks access `/proc/` and `/sys/` paths that don't exist on Windows — the checks should detect the target platform and skip inapplicable checks at compile-time, not runtime, to avoid dead code in the Zig binary.

---

## FINDING 5 — HIGH: `topo_run.c` has Linux-only seccomp block in shim code

`src/tickoni/c_abi/shim/topo_run.c` (line 82-94) has:
```c
#if FD_HAS_LINUX
  struct sock_filter seccomp_filter[ 256UL ];
  ...
#else
  struct sock_filter * seccomp_filter = NULL;
  ulong seccomp_filter_cnt = 0UL;
#endif
```

This file is in the shim directory, so it's **acceptable**. But the `extern void tk_sandbox_enter()` call with seccomp is passed to the Firedancer sandbox which is Linux-only. On Windows, the sandbox will be called with `seccomp_filter_cnt=0` and `seccomp_filter=NULL`, which needs to be verified against the Firedancer sandbox implementation.

---

## FINDING 6 — MEDIUM: `MAP_ANONYMOUS`/`MAP_ANON` fallback in `fd_tile_threads.c`

Line 29-31 of `fd_tile_threads.c`:
```c
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif
```

This is inside the `!FD_HAS_WINDOWS` block, so it's fine. But it's a **duplicate** of what the compat header or platform headers should handle. If this pattern propagates, it will create scattered compat code across multiple files.

---

## FINDING 7 — MEDIUM: `__GLIBC__` and `__linux__` guards in `fd_tile_threads.c`

Three `#if defined(__linux__)` guards and two `# if __GLIBC__` guards exist. These are for Linux-specific features:
- `prctl(PR_SET_NAME)` for thread naming
- `madvise(MADV_DONTFORK)` for fork protection
- `sched_setaffinity` vs `pthread_attr_setaffinity_np`

**Assessment**: These are reasonable Linux-specific feature detection patterns. However, macOS (`__MACH__`) is handled inconsistently — thread naming uses `pthread_setname_np` but the `madvise(MADV_DONTFORK)` block only has Linux. macOS should use a different approach or fall back to no-op.

---

## FINDING 8 — MEDIUM: Magic numbers in `fd_log_windows.c`

Multiple hardcoded magic numbers without named constants:
- `(long)1e9` — nanoseconds-to-seconds conversion (appears 5+ times)
- `(long)0.1e9` — 100ms threshold (appears 2+ times)
- `116444736000000000LL` — Windows file time to UNIX epoch offset (no named constant)
- `(long)3600L`, `(long)86400L` — seconds-per-hour/day
- `1048576UL` — 1MB stack size

**Assessment**: This is consistent with Firedancer's existing style (e.g., `fd_log.c` on Linux also uses magic numbers). Acceptable but not ideal for maintainability.

---

## FINDING 9 — MEDIUM: `ExitProcess` vs `abort()` inconsistency

`fd_log_windows.c` uses `ExitProcess(1)` for fatal errors, while Linux uses `abort()`. This is architecturally inconsistent because:
- `abort()` raises SIGABRT and generates core dumps
- `ExitProcess(1)` silently terminates without stack trace or crash dump

On Windows, `ExitProcess` bypasses all CRT cleanup, atexit handlers, and structured exception handling. A Windows user debugging a crash will see an abrupt exit with no diagnostic information.

---

## FINDING 10 — MEDIUM: Windows logging uses `OutputDebugStringA`

The only Windows diagnostic output for fatal errors goes through `OutputDebugStringA` — which only appears in Visual Studio's Output window or DbgView. This is a **debug-only channel** and will be invisible in production/CI environments. A Windows user will see `ExitProcess(1)` with no explanation of why.

---

## FINDING 11 — LOW: Integration tests reference `/proc/` paths

`src/tickoni/test/integration/test_process_topology_linux.zig` and `test_process_pipeline.zig` reference `/proc/self/exe` and `/proc/{d}/status`. These tests are Linux-only and gated properly (Linux test files), but they confirm the integration test suite is Linux-hardcoded.

---

## FINDING 12 — LOW: Test coverage is heavy on Zig, light on C

- 145 `.zig` files in `src/tickoni/`, 655 test blocks (avg 4.5 per file)
- 111 `.zig` files have zero test blocks (including key files: `c_abi.zig`, `boot.zig`, `sandbox.zig`, `topob.zig`, `tile_process.zig`, `mod.zig`, and most tile modules)
- The Windows C shim files (`fd_log_windows.c`, `windows_crt.c`, `fd_cpu_topo.c`, `fd_tile_threads.c` Windows stubs) have **zero tests** — no unit tests for the Windows paths

---

## FINDING 13 — LOW: `fd_tile_private_manager_args_t` uses `pthread_t` on Windows

Line 426 of `fd_tile_threads.c`:
```c
pthread_t pthread;
```
This is in the `fd_tile_private[FD_TILE_MAX]` array which is inside the `!FD_HAS_WINDOWS` block, so it's fine. But the Windows stub path (line 898+) has no `pthread` field at all, meaning the struct layout differs between platforms. This is handled by preprocessor guards but worth noting for any future refactoring.

---

## FINDING 14 — LOW: `src/util/windows_crt.c` appears to be a new file

This file was added to `src/util/Local.mk` under `FD_HAS_WINDOWS`. The changes add `windows_crt` as an object to `fd_util`. This is the CRT compat layer for Windows. The file is small but follows the same pattern as `fd_log_windows.c` — a full Windows reimplementation in a separate source file. **No tests for this file.**

---

## FINDING 15 — INFORMATIONAL: Build system is coherent

- `shimCFlagsFor(.windows)` correctly sets `-DFD_HAS_WINDOWS=1` and `-DFD_IO_STYLE=1`
- No hardcoded C flags in test `addCSourceFiles` calls
- `Local.mk` properly uses `ifdef FD_HAS_WINDOWS` to include platform-specific objects
- `windows_clang.mk` uses proper Windows target detection
- No `_WIN32` or `_WIN64` in non-shim, non-build files (only `FD_HAS_WINDOWS` is used)

---

## FINDING 16 — INFORMATIONAL: CI pipeline changes are well-scoped

New/modified CI files (`tests-short.yml`, `setup-windows.ps1`, `action.yml`, `fd-build-windows.sh`, `install-zig*.py`, `zigw.sh`) are properly scoped to build/test infrastructure. No OS switches leaked into test logic.

---

## SHIPPABILITY ASSESSMENT

| Category | Status |
|---|---|
| OS switches outside shims/build | ✅ Resolved — all split to per-platform files |
| Windows implementation quality | ❌ Stubs only, not functional |
| Logging on Windows | ❌ Normal logs silently dropped |
| Test coverage (Windows C files) | ❌ Zero tests for new Windows code |
| Test coverage (Zig) | ⚠️ 77% of files have tests; key ABI files missing |
| Build system coherence | ✅ Coherent and follows patterns |
| CRT compat header | ✅ Well-structured |
| Zig OS switches | ⚠️ Doctor module — acceptable but could be compile-time gated |

**Bottom line**: The branch is **not shippable as-is**. The Windows implementation is a stub layer — it compiles but provides no functional runtime. Normal logging is broken on Windows. Critical architecture conventions are violated in `fd_cpu_topo.c` and `fd_topo.h`. However, the build system itself is sound, no raw `_WIN32` leaks into code, and the overall approach (separate platform files, central compat header) is the correct pattern.

---

## FILES WITH OS SWITCHES (non-shim, non-build)

```\
src/tickoni/doctor/checks.zig       — 11 builtin.target.os.tag usages (expected — diagnostic tool)
src/tickoni/util/tier.zig           — 2 builtin.target.os.tag usages (pre-existing, acceptable)
```\

## FILES WITH OS SWITCHES (shim/build — expected)

```\
src/disco/topo/fd_topo_platform.h            — PATH_MAX override, sock_filter fwd-decl
src/disco/topo/fd_cpu_topo_platform_linux.c  — Linux-only CPU/NUMA discovery
src/disco/topo/fd_cpu_topo_platform_windows.c — Stub Windows CPU topo
src/util/tile/fd_tile_threads_platform_linux.c  — Linux/macOS tile threading
src/util/tile/fd_tile_threads_platform_windows.c — Stub Windows tile threading
src/util/log/fd_log_windows.c               — #if FD_HAS_WINDOWS wrapper (lines 9, 473)
src/util/fd_windows_compat.h                — #if FD_HAS_WINDOWS (lines 21, 67)
src/tickoni/c_abi/shim/os.c                 — FD_HAS_WINDOWS guard, #include <windows.h>
src/tickoni/c_abi/shim/tango.c              — FD_HAS_WINDOWS guard
src/tickoni/c_abi/shim/tile_run.c           — FD_HAS_WINDOWS guard
src/tickoni/c_abi/shim/tile_run_test_stubs.c — FD_HAS_WINDOWS guard
src/tickoni/c_abi/shim/topo_run.c           — #if FD_HAS_LINUX for seccomp block
src/tickoni/c_abi/shim/topo_run_platform_linux.c  — FD_HAS_LINUX guard
src/tickoni/c_abi/shim/topo_run_platform_macos.c  — FD_HAS_MACOS guard
src/tickoni/c_abi/shim/topo_run_platform_windows.c — FD_HAS_WINDOWS guard
src/tickoni/c_abi/shim/topob.c              — FD_HAS_WINDOWS guard
src/tickoni/c_abi/shim/windows_crt.c        — FD_HAS_WINDOWS guard
src/tickoni/c_abi/shim/libuuid_stub.c       — Windows-only stub
build.zig                                   — shimCFlagsFor(.windows), Windows lib linking, manifest fixups
config/machine/windows_clang.mk             — Windows target detection
src/util/Local.mk                           — ifdef FD_HAS_WINDOWS for windows_crt object
src/util/log/Local.mk                       — ifdef FD_HAS_WINDOWS for fd_log_windows object
src/util/tile/Local.mk                      — ifdef FD_HAS_WINDOWS for platform tile objects
```\
