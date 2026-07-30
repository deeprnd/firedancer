# Windows Support Spill Reduction Plan

> **For Hermes:** Use `writing-plans` and `cross-platform-c-fixes`. Execute this plan slice-by-slice. Keep Windows support build-CI-only per `doc/execution/V2.22/windows-build-ci.md`. Do not expand scope into Windows runtime parity.

**Goal:** Reduce the amount of Windows-specific behavior living in shared/upstream-derived Firedancer code so future upstream syncs carry fewer merge conflicts.

**Architecture:** Apply the existing macOS resolver pattern as the default shape: one shared platform-neutral algorithm/contract file, per-platform implementation files selected in `Local.mk`, and Tickoni-owned shim boundaries for runtime/product divergence. Leave inline `#if FD_HAS_WINDOWS` only for tiny declaration/feature-test compatibility shims.

**Tech Stack:** Firedancer C/Make build graph, Tickoni Zig build, `Local.mk` object selection, Tickoni C ABI shims, GitHub Actions build-only Windows contract.

**Scope boundary:** This plan fixes **finding 1 only** from the maintainability review: “too much Windows support spilled into shared/upstream-derived code.” It does **not** attempt to redesign the Windows link-closure problem in `build.zig`, enable new Windows runtime features, or remove the build-only Windows contract.

---

## Contract and success criteria

**Frozen contract inputs**
- `doc/execution/V2.22/windows-build-ci.md:9-12` — Windows support here is build-CI-only
- `doc/execution/V2.22/windows-build-ci.md:45-52` — lanes prove compile/build only
- `doc/execution/V2.22/windows-build-ci.md:72-77` — required constraint: keep OS divergence behind shared actions, scripts, shims, or platform APIs

**Success criteria**
- Fewer shared/upstream-derived `.c` / `.h` files contain Windows-specific behavioral logic.
- Repeated Windows tile-stub boilerplate is centralized.
- More platform selection happens in `Local.mk` and per-platform `.c` files.
- Tickoni-owned shims own more runtime/product divergence.
- Shared files retain only tiny compatibility guards where a platform-file split would be overkill.

**Primary verification metrics**
1. Count of shared/upstream-derived files matching `FD_HAS_WINDOWS` drops.
2. Count of repeated `unsupported on Windows build lane` implementations drops.
3. Linux + macOS + existing Windows build entrypoints still compile.

---

## Current inventory (starting point)

**Windows tile-stub files added in this branch**
- `src/disco/bundle/fd_bundle_windows_stub.c`
- `src/disco/diag/fd_diag_windows_stub.c`
- `src/disco/events/fd_event_windows_stub.c`
- `src/disco/events/fd_event_client_windows_stub.c`
- `src/disco/metrics/fd_metric_windows_stub.c`
- `src/disco/pack/fd_pack_windows_stub.c`
- `src/disco/store/fd_shredb_windows_stub.c`
- `src/util/shmem/fd_shmem_windows_stub.c`
- `src/util/wksp/fd_wksp_windows_stub.c`
- `src/waltz/grpc/fd_grpc_client_windows_stub.c`
- `src/waltz/http/fd_http_server_windows_stub.c`
- `src/waltz/resolv/fd_netdb_windows_stub.c`
- `src/waltz/udpsock/fd_udpsock_windows_stub.c`

**Shared/upstream-derived files currently carrying Windows logic that need classification**
- `src/util/cstr/fd_cstr.c`
- `src/ballet/toml/fd_toml.c`
- `src/util/io/fd_io.c`
- `src/util/fd_util.c`
- `src/disco/store/fd_shredb.c`
- `src/disco/bundle/fd_bundle_client.c`
- `src/disco/bundle/fd_bundle_tile.c`
- `src/disco/diag/fd_diag_tile.c`
- `src/tango/cnc/fd_cnc.c`
- `src/waltz/neigh/fd_neigh4_netlink.c`
- `src/disco/topo/fd_topo.h`
- `src/disco/topo/fd_topo.c`
- utility width/compat headers such as `src/util/fd_util_base.h`, `src/util/bits/fd_bits.h`, `src/util/bits/fd_bits_find_msb.h`

**Known good pattern already in repo**
- `src/waltz/resolv/fd_res_msend.c`
- `src/waltz/resolv/fd_res_msend_linux.c`
- `src/waltz/resolv/fd_res_msend_macos.c`
- `src/waltz/resolv/Local.mk`

**Known good Tickoni-owned boundary pattern**
- `src/tickoni/c_abi/shim/os.c`
- `src/tickoni/c_abi/shim/sandbox.c`
- `src/tickoni/c_abi/shim/topo_run_platform_linux.c`
- `src/tickoni/c_abi/shim/topo_run_platform_macos.c`
- `src/tickoni/c_abi/shim/topo_run_platform_windows.c`
- `src/tickoni/util/os_api.zig`
- `src/tickoni/util/process_api.zig`

---

## Execution tracker

### Task 1: Record the exact spill inventory and classify every Windows touchpoint
**Status:** DONE

**Objective:** Produce the decision table that drives the rest of the cleanup so later slices do not “fix” the wrong kind of file.

**Files:**
- Modify: `doc/execution/win-support/finding-1-spill-reduction-plan.md`

**Classification buckets:**
1. **Keep inline tiny compat shim**
2. **Split into per-platform implementation file**
3. **Keep Windows unsupported and centralize stub policy**
4. **Move behavior into Tickoni-owned shim/API boundary**

**Exact files to classify first:**
- `src/util/cstr/fd_cstr.c`
- `src/ballet/toml/fd_toml.c`
- `src/util/io/fd_io.c`
- `src/util/fd_util.c`
- `src/disco/store/fd_shredb.c`
- `src/disco/bundle/fd_bundle_client.c`
- `src/disco/bundle/fd_bundle_tile.c`
- `src/disco/diag/fd_diag_tile.c`
- `src/tango/cnc/fd_cnc.c`
- `src/waltz/neigh/fd_neigh4_netlink.c`
- `src/disco/topo/fd_topo.h`
- `src/disco/topo/fd_topo.c`
- all `*_windows_stub.c` files listed above

**Classification table (branch state before code cleanup)**

| Path | Current Windows pattern | Target pattern | Reason | Slice owner |
| --- | --- | --- | --- | --- |
| `src/util/cstr/fd_cstr.c` | `_stricmp` / `_strnicmp` compat shim next to includes | Keep inline tiny compat shim | Declarative header/name gap only; no behavioral fork | Task 6 |
| `src/ballet/toml/fd_toml.c` | `_stricmp` compat shim next to includes | Keep inline tiny compat shim | Declarative header/name gap only; no behavioral fork | Task 6 |
| `src/util/io/fd_io.c` | `FD_IO_STYLE` forced off POSIX hosted path on Windows | Keep inline tiny compat shim | Build-style selection macro only; acceptable while it stays branch-free below the selector | Task 6 (optional) |
| `src/util/fd_util.c` | Hosted `fd_yield` / `fd_syscall_poll` implemented under `#if FD_HAS_WINDOWS` in shared file | Split into per-platform implementation file | Real hosted behavior divergence belongs in build-selected files | Task 3 |
| `src/disco/store/fd_shredb.c` | No current Windows branch in real impl; Windows support lives beside it as a stub object | Keep Windows unsupported and centralize stub policy | Real file should stay non-Windows-focused while `Local.mk` selects stub | Task 5 |
| `src/disco/bundle/fd_bundle_client.c` | Windows compile shims for `pollfd`, `_write`, socket close, `PATH_MAX`-style hosted gaps | Keep Windows unsupported and centralize stub policy | Bundle client is POSIX/socket heavy and should not keep accumulating build-lane compatibility churn in shared code | Task 5 |
| `src/disco/bundle/fd_bundle_tile.c` | Windows include / write-path branches inside shared tile implementation | Keep Windows unsupported and centralize stub policy | Unsupported tile policy should live in shared tile-stub helper + `Local.mk`, not shared tile body | Task 2 + Task 5 |
| `src/disco/diag/fd_diag_tile.c` | Narrow `!FD_HAS_WINDOWS` include guard around POSIX hosted declarations | Keep inline tiny compat shim | Include gating only; no material behavioral split today | Task 5 review |
| `src/tango/cnc/fd_cnc.c` | Hosted POSIX branch excludes Windows via `&& !FD_HAS_WINDOWS` | Keep Windows unsupported and centralize stub policy | Windows should remain off the hosted POSIX path without adding deeper inline behavior | Task 5 |
| `src/waltz/neigh/fd_neigh4_netlink.c` | No current Windows branch in real impl | Keep Windows unsupported and centralize stub policy | Netlink implementation is Linux-only and should stay selected out by build graph | Task 5 |
| `src/disco/topo/fd_topo.h` | `PATH_MAX` fallback and non-Linux `sock_filter` forward declaration | Keep inline tiny compat shim | Shared-header compile-time storage/prototype aid only | Task 6 review |
| `src/disco/topo/fd_topo.c` | No direct Windows behavior branch today | Keep shared file platform-neutral | No spill to clean right now; watch for future runtime drift only | Task 7 review |
| `src/disco/bundle/fd_bundle_windows_stub.c` | Full repeated unsupported tile stub | Keep Windows unsupported and centralize stub policy | Boilerplate should collapse into shared helper | Task 2 |
| `src/disco/diag/fd_diag_windows_stub.c` | Full repeated unsupported tile stub | Keep Windows unsupported and centralize stub policy | Boilerplate should collapse into shared helper | Task 2 |
| `src/disco/events/fd_event_windows_stub.c` | Full repeated unsupported tile stub | Keep Windows unsupported and centralize stub policy | Boilerplate should collapse into shared helper | Task 2 |
| `src/disco/events/fd_event_client_windows_stub.c` | Windows-only API/client stub | Keep Windows unsupported and centralize stub policy | Not a `fd_topo_run_tile_t` tile stub; leave for later/no helperization in this plan | Task 5 review |
| `src/disco/metrics/fd_metric_windows_stub.c` | Full repeated unsupported tile stub | Keep Windows unsupported and centralize stub policy | Boilerplate should collapse into shared helper | Task 2 |
| `src/disco/pack/fd_pack_windows_stub.c` | Full repeated unsupported tile stub | Keep Windows unsupported and centralize stub policy | Boilerplate should collapse into shared helper | Task 2 |
| `src/disco/store/fd_shredb_windows_stub.c` | Windows-only store stub | Keep Windows unsupported and centralize stub policy | `Local.mk` should own store-vs-stub selection | Task 5 |
| `src/util/shmem/fd_shmem_windows_stub.c` | Windows-only shmem stub | Keep Windows unsupported and centralize stub policy | POSIX-heavy subsystem intentionally stubbed on Windows build lane | Task 4 |
| `src/util/wksp/fd_wksp_windows_stub.c` | Windows-only wksp/checkpoint stub | Keep Windows unsupported and centralize stub policy | POSIX-heavy subsystem intentionally stubbed on Windows build lane | Task 4 |
| `src/waltz/grpc/fd_grpc_client_windows_stub.c` | Windows-only client stub | Keep Windows unsupported and centralize stub policy | Build-graph selection should carry unsupported client policy | Task 4 |
| `src/waltz/http/fd_http_server_windows_stub.c` | Windows-only HTTP server stub | Keep Windows unsupported and centralize stub policy | Build-graph selection should carry unsupported socket-server policy | Task 4 |
| `src/waltz/resolv/fd_netdb_windows_stub.c` | Windows-only resolver/netdb stub | Keep Windows unsupported and centralize stub policy | Build-graph selection should carry unsupported resolver policy | Task 4 |
| `src/waltz/udpsock/fd_udpsock_windows_stub.c` | Windows-only UDP socket stub | Keep Windows unsupported and centralize stub policy | Build-graph selection should carry unsupported socket policy | Task 4 |

**Resolution:** Added a full classification table covering every shared/upstream-derived file and every currently listed Windows stub so later slices have a single explicit target pattern per path.

**Verification used:** `grep -n '^| \`src/' doc/execution/win-support/finding-1-spill-reduction-plan.md`

**Commit subject:** `docs: classify windows spill cleanup targets`

---

### Task 2: Create a shared helper for unsupported Windows tile stubs
**Status:** DONE

**Objective:** Stop repeating the same no-op/unsupported tile boilerplate in multiple `*_windows_stub.c` files.

**Files:**
- Create: `src/disco/common/fd_platform_tile_stub.h`
- Modify: `src/disco/bundle/fd_bundle_windows_stub.c`
- Modify: `src/disco/diag/fd_diag_windows_stub.c`
- Modify: `src/disco/events/fd_event_windows_stub.c`
- Modify: `src/disco/metrics/fd_metric_windows_stub.c`
- Modify: `src/disco/pack/fd_pack_windows_stub.c`

**Non-goal for this slice:** do not redesign client/API stubs like `fd_http_server_windows_stub.c` yet. This slice is only about `fd_topo_run_tile_t`-style tile stubs.

**Step 1: Read the current repeated tile-stub bodies and identify common pieces**
Review these files:
- `src/disco/bundle/fd_bundle_windows_stub.c`
- `src/disco/diag/fd_diag_windows_stub.c`
- `src/disco/events/fd_event_windows_stub.c`
- `src/disco/metrics/fd_metric_windows_stub.c`
- `src/disco/pack/fd_pack_windows_stub.c`

Expected repeated pieces:
- `scratch_align`, `scratch_footprint`, `loose_footprint`
- `populate_allowed_seccomp`, `populate_allowed_fds`
- no-op init hooks
- `run()` that logs unsupported
- full `fd_topo_run_tile_t` definition

**Step 2: Add a shared header that defines the common callbacks/macros**
`src/disco/common/fd_platform_tile_stub.h` should provide:
- a common zero-footprint callback set
- a common unsupported `run()` helper or macro-generated `run`
- a macro to instantiate a `fd_topo_run_tile_t` with:
  - exported symbol name
  - display name string
  - optionally a custom `run` body if needed later

**Step 3: Rewrite each tile stub file to use the shared helper**
Each file should shrink to the minimum declaration surface needed to export the correct symbol name.

**Step 4: Fresh verification**
Run:
```bash
just build-fd
```
Expected: Linux build still passes.

Run a textual check:
```bash
grep -R "unsupported on Windows build lane" -n src/disco | cat
```
Expected: fewer repeated full implementations; message may still appear, but helperization should reduce boilerplate.

**Step 5: Commit**
```bash
git add src/disco/common/fd_platform_tile_stub.h \
        src/disco/bundle/fd_bundle_windows_stub.c \
        src/disco/diag/fd_diag_windows_stub.c \
        src/disco/events/fd_event_windows_stub.c \
        src/disco/metrics/fd_metric_windows_stub.c \
        src/disco/pack/fd_pack_windows_stub.c
git commit -m "refactor: centralize windows tile stub boilerplate"
```

**Resolution:** Added `src/disco/common/fd_platform_tile_stub.h` as the single home for zero-footprint callbacks, no-op init hooks, and unsupported-tile `run()` generation. The five tile stubs now collapse to tiny wrappers, with only diag/pack keeping local allowed-fd helpers.

**Verification used:** `just build-fd`; `grep -R "unsupported on Windows build lane" -n src/disco/common src/disco/bundle src/disco/diag src/disco/events src/disco/metrics src/disco/pack | cat`; `grep -R "FD_PLATFORM_TILE_STUB(" -n src/disco | cat`

**Commit subject:** `refactor: centralize windows tile stub boilerplate`

---

### Task 3: Split `src/util/fd_util.c` behavioral Windows divergence into platform files
**Status:** DONE

**Objective:** Remove substantive Windows behavior branching from the shared utility implementation.

**Files:**
- Create: `src/util/fd_util_hosted_posix.c` or `src/util/fd_util_hosted_unix.c`
- Create: `src/util/fd_util_hosted_windows.c`
- Modify: `src/util/fd_util.c`
- Modify: `src/util/Local.mk`
- Optional create if clearer: `src/util/fd_util_hosted.h`

**Current behavior to extract:**
- `fd_yield`
- `fd_syscall_poll`

Current shared-file branch:
- `src/util/fd_util.c:30-77`

**Step 1: Isolate shared non-hosted / boot/halt logic in `fd_util.c`**
Keep only logic that is truly common and stable.

**Step 2: Move hosted POSIX implementation into a dedicated file**
Target responsibilities:
- include `<poll.h>`, `<sched.h>`, `<time.h>`
- implement `fd_yield`
- implement `fd_syscall_poll`

**Step 3: Move hosted Windows implementation into its own file**
Target responsibilities:
- implement `fd_yield` via `FD_SPIN_PAUSE()`
- implement `fd_syscall_poll` as Windows build-lane unsupported behavior if that remains the contract

**Step 4: Select implementation in `src/util/Local.mk`**
Use build-graph selection, not shared-file branching.

**Step 5: Fresh verification**
Run:
```bash
just build-fd
```
Expected: Linux build passes.

Textual check:
```bash
grep -n "FD_HAS_WINDOWS" src/util/fd_util.c
```
Expected: no substantive behavioral Windows branch remains in `fd_util.c`.

**Step 6: Commit**
```bash
git add src/util/fd_util.c src/util/Local.mk src/util/fd_util_hosted_*.c
git commit -m "refactor: split hosted util behavior by platform"
```

**Resolution:** Kept `src/util/fd_util.c` down to boot/halt/shared tickcount logic and moved hosted `fd_yield`/`fd_syscall_poll` into build-selected `src/util/fd_util_hosted_posix.c` and `src/util/fd_util_hosted_windows.c`.

**Verification used:** `just build-fd`; `grep -n "FD_HAS_WINDOWS" src/util/fd_util.c || true`; `find src/util -maxdepth 1 -name 'fd_util_hosted_*.c' | sort`

**Commit subject:** `refactor: split hosted util behavior by platform`

---

### Task 4: Normalize `Local.mk` platform selection for POSIX-heavy subsystems
**Status:** DONE

**Objective:** Make platform selection explicit and consistent so Windows behavior is owned by the build graph instead of leaking into shared implementation files.

**Files:**
- Modify: `src/disco/store/Local.mk`
- Modify: `src/util/shmem/Local.mk`
- Modify: `src/util/wksp/Local.mk`
- Modify: `src/waltz/http/Local.mk`
- Modify: `src/waltz/grpc/Local.mk`
- Modify: `src/waltz/resolv/Local.mk`
- Modify: `src/waltz/udpsock/Local.mk`
- Modify: `src/disco/bundle/Local.mk`
- Modify: `src/disco/diag/Local.mk`
- Modify: `src/disco/events/Local.mk`
- Modify: `src/disco/metrics/Local.mk`
- Modify: `src/disco/pack/Local.mk`

**Step 1: Normalize each file to one of two shapes**

**Shape A: real per-platform implementation**
```make
ifdef FD_HAS_WINDOWS
$(call add-objs,foo_windows,lib)
else ifdef FD_HAS_LINUX
$(call add-objs,foo_linux,lib)
else
$(call add-objs,foo_macos,lib)
endif
```

**Shape B: unsupported Windows build lane**
```make
ifdef FD_HAS_WINDOWS
$(call add-objs,foo_windows_stub,lib)
else
$(call add-objs,foo_real,lib)
endif
```

**Step 2: Ensure comments accurately describe contract**
Examples:
- “Windows build lane uses stub; non-Windows keeps real implementation.”
- “Shared algorithm + platform impl selected here.”

**Step 3: Fresh verification**
Run:
```bash
just build-fd
```
Expected: build still passes.

Textual review:
```bash
grep -R "ifdef FD_HAS_WINDOWS" -n src/*/Local.mk src/*/*/Local.mk | cat
```
Expected: platform selection remains, but is structurally consistent and easier to audit.

**Step 4: Commit**
```bash
git add src/**/Local.mk
git commit -m "refactor: normalize platform selection in local mk files"
```

**Resolution:** Normalized the listed `Local.mk` files onto explicit build-graph comments and Windows-stub vs non-Windows-real selection blocks, while preserving the resolver's existing shared-algorithm/per-platform-impl split.

**Verification used:** `just build-fd`; `grep -R "ifdef FD_HAS_WINDOWS" -n src/*/Local.mk src/*/*/Local.mk | cat`; `git diff --stat -- src/disco/*/Local.mk src/util/shmem/Local.mk src/util/wksp/Local.mk src/waltz/*/Local.mk`

**Commit subject:** `refactor: normalize platform selection in local mk files`

---

### Task 5: Remove Windows behavioral branches from shared files that should stay non-Windows-only under current contract
**Status:** DONE

**Objective:** Where Windows is intentionally unsupported for a subsystem, remove inline behavioral Windows logic from the real implementation and let the Windows stub own the policy.

**Primary files to inspect:**
- `src/disco/store/fd_shredb.c`
- `src/disco/bundle/fd_bundle_client.c`
- `src/disco/bundle/fd_bundle_tile.c`
- `src/disco/diag/fd_diag_tile.c`
- `src/tango/cnc/fd_cnc.c`
- `src/waltz/neigh/fd_neigh4_netlink.c`

**Step 1: For each file, answer one question**
Under the frozen build-only Windows contract, should Windows:
- have a real implementation here, or
- stay on a build-graph-selected stub?

If **stub**, remove any further inline Windows behavioral churn from the real shared file if possible.

**Step 2: Apply the macOS resolver standard**
If the subsystem deserves a real Windows implementation, split it into:
- shared contract/algorithm file
- `*_windows.c`
- `*_linux.c` and/or `*_macos.c`
- `Local.mk` selection

If the subsystem remains unsupported on Windows, keep the real implementation non-Windows-focused and let `Local.mk` select the stub.

**Step 3: Fresh verification**
Run:
```bash
just build-fd
```
Expected: Linux build passes.

Run targeted grep:
```bash
grep -R "FD_HAS_WINDOWS" -n \
  src/disco/store/fd_shredb.c \
  src/disco/bundle/fd_bundle_client.c \
  src/disco/bundle/fd_bundle_tile.c \
  src/disco/diag/fd_diag_tile.c \
  src/tango/cnc/fd_cnc.c \
  src/waltz/neigh/fd_neigh4_netlink.c || true
```
Expected: only tiny compat guards remain; behavioral branches should have moved or disappeared.

**Step 4: Commit**
Use one commit per subsystem or small cluster.

Suggested messages:
- `refactor: keep shred store windows support at build-graph boundary`
- `refactor: move bundle windows policy out of shared implementation`
- `refactor: reduce windows branching in shared hosted code`

**Resolution:** Reviewed all listed subsystems. `fd_shredb.c` and `fd_neigh4_netlink.c` already stayed on the build-graph-selected real/stub path, so no code change was needed there. Removed the remaining Windows-only compile shims from shared bundle and diag implementations, and collapsed a redundant nested Windows include guard in `fd_cnc.c`. The only remaining targeted `FD_HAS_WINDOWS` reference is the top-level hosted-policy gate in `fd_cnc.c`.

**Verification used:** `just build-fd`; `grep -R "FD_HAS_WINDOWS" -n src/disco/store/fd_shredb.c src/disco/bundle/fd_bundle_client.c src/disco/bundle/fd_bundle_tile.c src/disco/diag/fd_diag_tile.c src/tango/cnc/fd_cnc.c src/waltz/neigh/fd_neigh4_netlink.c || true`; `git diff --stat -- src/disco/store/fd_shredb.c src/disco/bundle/fd_bundle_client.c src/disco/bundle/fd_bundle_tile.c src/disco/diag/fd_diag_tile.c src/tango/cnc/fd_cnc.c src/waltz/neigh/fd_neigh4_netlink.c`

**Commit subject:** `refactor: move bundle windows policy out of shared implementation`

---

### Task 6: Add one shared Windows compat header only if duplication persists
**Status:** DONE

**Objective:** centralize repeated tiny declaration/macro compatibility shims, but do not overuse this pattern for behavioral divergence.

**Candidate files showing duplication now:**
- `src/util/cstr/fd_cstr.c`
- `src/ballet/toml/fd_toml.c`

**Potential new file:**
- `src/util/fd_windows_compat.h`

**Step 1: Measure whether duplication is real enough to justify a header**
If the same mappings are present in only two files, this may be optional. If more files need them in later cleanup, centralize.

**Step 2: If creating the header, move only tiny declarative shims**
Acceptable content:
- `_stricmp` / `_strnicmp` mappings
- tiny constants/prototype fallbacks
- compile-time declaration aids

Do **not** put subsystem behavior or Windows build-lane policy here.

**Step 3: Fresh verification**
Run:
```bash
just build-fd
```
Expected: Linux build passes.

**Step 4: Commit**
```bash
git add src/util/fd_windows_compat.h src/util/cstr/fd_cstr.c src/ballet/toml/fd_toml.c
git commit -m "refactor: centralize tiny windows compatibility shims"
```

**Resolution:** Duplication was still concentrated in the same two case-insensitive string-call sites, so this slice introduced `src/util/fd_windows_compat.h` and moved the `_stricmp` / `_strnicmp` mappings there instead of leaving the copied shim blocks in both sources.

**Verification used:** `just build-fd`; `grep -R "_stricmp\|_strnicmp" -n src | cat`; `grep -n "strcasecmp\|strncasecmp\|strings.h" src/util/fd_windows_compat.h`

**Commit subject:** `refactor: centralize tiny windows compatibility shims`

---

### Task 7: Pull any remaining runtime/product divergence back into Tickoni-owned shims
**Status:** DONE

**Objective:** if cleanup discovers Windows runtime/product behavior leaking into shared Firedancer-derived code, move it behind Tickoni-owned boundaries first.

**Primary Tickoni-owned boundaries:**
- `src/tickoni/c_abi/shim/os.c`
- `src/tickoni/c_abi/shim/sandbox.c`
- `src/tickoni/c_abi/shim/topo_run_platform_windows.c`
- `src/tickoni/util/os_api.zig`
- `src/tickoni/util/process_api.zig`

**Step 1: Audit remaining Windows logic in shared files for runtime semantics**
Examples of runtime semantics:
- pid/tid behavior
- kill/terminate behavior
- sandbox policy
- topo/tile launch semantics

**Step 2: If found, move that logic into Tickoni-owned shim/API layer**
Keep shared Firedancer-derived files closer to upstream.

**Step 3: Fresh verification**
Run:
```bash
just build-tk
```
Expected: supervisor/CLI still compile against the same shim contract.

**Step 4: Commit**
```bash
git add src/tickoni/c_abi/shim/* src/tickoni/util/*
git commit -m "refactor: keep windows runtime divergence inside tickoni shims"
```

**Resolution:** Re-audited the remaining Windows references after Tasks 1-6. The remaining runtime/product semantics already sit in Tickoni-owned boundaries (`src/tickoni/c_abi/shim/os.c`, `src/tickoni/c_abi/shim/sandbox.c`, `src/tickoni/c_abi/shim/windows_crt.c`), so this slice needed no further code movement.

**Verification used:** `just build-tk`; `grep -R "FD_HAS_WINDOWS" -n src/tickoni/c_abi/shim src/tickoni/util | cat`; `grep -R "FD_HAS_WINDOWS" -n src --include='*.c' --include='*.h' | cat`

**Commit subject:** `docs: record windows runtime shim audit`

---

### Task 8: Update this execution tracker after each slice
**Status:** DONE

**Objective:** keep this file as the real execution tracker, not a stale design note.

**Files:**
- Modify: `doc/execution/win-support/finding-1-spill-reduction-plan.md`

**Step 1: After each completed slice**
Update:
- `**Status:** DONE` for the task
- short “Resolution” note
- exact verification command used
- commit SHA or commit subject

**Step 2: Before declaring the finding closed**
Confirm:
- no remaining non-DONE tasks here
- grep/count metrics improved
- no accidental scope expansion into runtime parity work

**Suggested commit message:**
`docs: update windows spill reduction tracker`

**Resolution:** All slices in this tracker are now marked `DONE` with per-slice resolution, verification, and commit subject notes. Final pass confirmed the finding stayed inside build-CI-only Windows scope.

**Verification used:** `grep -R "**Status:** TODO" -n doc/execution/win-support/finding-1-spill-reduction-plan.md || true`; `grep -R "FD_HAS_WINDOWS" -n src --include='*.c' | cat`; `grep -R "unsupported on Windows build lane" -n src | cat`; `just build-fd`; `just build-tk`

**Final metrics:**
- Task-1 target-set shared files still carrying `FD_HAS_WINDOWS`: `2` (`src/util/io/fd_io.c`, `src/tango/cnc/fd_cnc.c`)
- Raw `.c` match count for `FD_HAS_WINDOWS`: `24` (now concentrated in stubs, platform files, and Tickoni-owned shims)
- Raw `unsupported on Windows build lane` match count: `17` (centralized tile message now lives in `src/disco/common/fd_platform_tile_stub.h`)
- Remaining non-DONE tasks in this tracker: `0`

**Commit subject:** `docs: update windows spill reduction tracker`

---

## Recommended execution order

1. **Task 1** — classify all spill points
2. **Task 2** — centralize repeated tile-stub boilerplate
3. **Task 3** — split `fd_util.c` hosted behavior by platform
4. **Task 4** — normalize `Local.mk` selection style
5. **Task 5** — remove remaining shared-file behavioral Windows branches where Windows should stay stubbed
6. **Task 6** — optional tiny compat header if duplication persists
7. **Task 7** — move any lingering runtime/product semantics into Tickoni shims
8. **Task 8** — keep tracker current after every slice

---

## Verification commands summary

**Linux/fresh build checks**
```bash
just build-fd
just build-tk
```

**Textual maintainability checks**
```bash
grep -R "FD_HAS_WINDOWS" -n src | cat
grep -R "unsupported on Windows build lane" -n src | cat
grep -R "ifdef FD_HAS_WINDOWS" -n src/*/Local.mk src/*/*/Local.mk | cat
```

**Targeted checks after refactors**
```bash
grep -n "FD_HAS_WINDOWS" src/util/fd_util.c || true
grep -n "FD_HAS_WINDOWS" src/disco/store/fd_shredb.c || true
grep -n "FD_HAS_WINDOWS" src/disco/bundle/fd_bundle_tile.c || true
```

**Interpretation rule**
- Success is **not** “zero Windows references everywhere.”
- Success is: Windows references are concentrated in the right places:
  - platform files
  - `Local.mk`
  - Tickoni-owned shims
  - tiny compat helpers

---

## Finish line

This finding is closed when:
- repeated Windows tile-stub boilerplate is centralized,
- major shared behavioral branches have moved into platform files or build-graph selection,
- runtime/product divergence is kept in Tickoni-owned shims,
- remaining inline Windows guards are limited to tiny compatibility shims,
- and this tracker shows all tasks `DONE` with fresh verification recorded.
