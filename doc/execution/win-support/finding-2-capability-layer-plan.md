# Windows Unsupported-Runtime Capability Layer Plan

> **For Hermes:** Use `writing-plans` and `cross-platform-c-fixes`. Execute this plan slice-by-slice. Keep Windows support build-CI-only per `doc/execution/V2.22/windows-build-ci.md`. Do not expand scope into Windows runtime parity.

**Goal:** Reduce maintenance tax from repeated Windows unsupported-runtime stubs by collapsing common policy into a smaller capability/helper layer while keeping subsystem contracts readable and local.

**Architecture:** Keep the existing tile-stub helper as the solved pattern for `fd_topo_run_tile_t`-style tiles. For the remaining Windows stubs, group them by contract family and introduce a few narrow shared helpers instead of one giant macro system. Shared policy belongs in helper headers or small support files; exported subsystem symbols stay owned by each subsystem wrapper.

**Tech Stack:** Firedancer C/Make build graph, Tickoni Zig build, `Local.mk` object selection, Windows build-lane stubs, shared helper headers, GitHub Actions build-only Windows contract.

---

## 1. Contract

**Frozen contract inputs**
- `doc/execution/V2.22/windows-build-ci.md:9-12` — Windows support here is build-CI-only
- `doc/execution/V2.22/windows-build-ci.md:45-52` — lanes prove compile/build only
- `doc/execution/V2.22/windows-build-ci.md:72-77` — required constraint: keep OS divergence behind shared actions, scripts, shims, or platform APIs

**Finding scope**
This plan addresses the second maintainability finding:

> Unsupported Windows runtime is implemented as many per-subsystem stubs instead of a smaller capability layer.

This plan does **not**:
- enable Windows runtime parity,
- redesign `build.zig`,
- remove the build-only Windows support contract,
- replace explicit unsupported behavior with fake partial implementations,
- force unrelated Linux/macOS code movement.

**Success criteria**
- Repeated unsupported-runtime policy moves into a small number of shared helpers.
- `fd_topo_run_tile_t` tile stubs continue to use the existing centralized helper pattern.
- Non-tile Windows stubs are grouped by contract family rather than hand-maintained as isolated one-offs.
- Public subsystem files remain readable and still own their exported symbols.
- Future upstream contract changes should require touching fewer Windows-only files.

**Primary verification metrics**
1. Count of repeated unsupported-message / `errno = ENOTSUP` / sentinel boilerplate drops.
2. Shared helper count increases by a small amount, while per-subsystem wrappers shrink.
3. Linux + existing Windows build entrypoints still compile.

---

## 2. Family inventory

### 2.1 Already-solved family: tile runtime stubs

These already share `src/disco/common/fd_platform_tile_stub.h` and are **not** the main remaining problem:
- `src/disco/bundle/fd_bundle_windows_stub.c`
- `src/disco/diag/fd_diag_windows_stub.c`
- `src/disco/events/fd_event_windows_stub.c`
- `src/disco/metrics/fd_metric_windows_stub.c`
- `src/disco/pack/fd_pack_windows_stub.c`

**Current shape:** thin wrappers around `FD_PLATFORM_TILE_STUB(...)`

**Target pattern:** keep as-is unless upstream tile contract drift forces extension of the shared helper.

### 2.2 Opaque object stub family

These allocate or represent small stateful objects and duplicate lifecycle scaffolding:
- `src/disco/events/fd_event_client_windows_stub.c`
- `src/waltz/grpc/fd_grpc_client_windows_stub.c`
- `src/waltz/http/fd_http_server_windows_stub.c`
- `src/waltz/udpsock/fd_udpsock_windows_stub.c`

**Repeated patterns:**
- align/footprint helpers
- `new`/`join`/`leave`/`delete`
- zero-init or sentinel-init object state
- unsupported hosted operations returning `NULL`, `-1`, `ENOTSUP`, or disconnected state

**Target pattern:** shared object-lifecycle helper plus tiny unsupported-runtime helper; keep subsystem-specific behavior local.

### 2.3 Service / storage stub family

These expose smaller service APIs with repeated unsupported return semantics:
- `src/disco/store/fd_shredb_windows_stub.c`
- `src/waltz/resolv/fd_netdb_windows_stub.c`

**Repeated patterns:**
- valid alignment/constructor scaffolding where needed
- unsupported queries returning `-1`, `FD_EAI_NONAME`, `NULL`, `ENOENT`, or `ENOTSUP`
- repeated unsupported message wording

**Target pattern:** shared unsupported-return vocabulary; thin local wrappers keep subsystem semantics explicit.

### 2.4 Runtime/admin capability family

These encode the biggest unsupported-runtime policy surface:
- `src/util/shmem/fd_shmem_windows_stub.c`
- `src/util/wksp/fd_wksp_windows_stub.c`

**Repeated patterns:**
- build-lane unsupported logging
- `ENOTSUP`/`ENOENT` returns
- capability absence for shared-memory and checkpoint/restore workflows
- “minimally valid” fallback values to satisfy broader runtime invariants

**Target pattern:** shared capability-policy helper(s), but **not** a giant generated macro layer. Preserve explicit code where invariant-sensitive behavior matters.

### 2.5 Current branch-state summary

| Family | Files | Best refactor shape |
| --- | --- | --- |
| Tile runtime | 5 | Keep `fd_platform_tile_stub.h` |
| Opaque object | 4 | Shared lifecycle helper + unsupported-return helper |
| Service/storage | 2 | Shared unsupported-return helper |
| Runtime/admin | 2 | Shared capability-policy helper, explicit wrappers |

---

## 3. Helper design

### 3.1 Design rule

Do **not** create one universal “Windows stub DSL.” That would hide subsystem contracts behind macro soup and make drift harder to audit.

Use **2-3 narrow helpers** instead:
1. one tiny common unsupported-runtime helper,
2. one helper for repetitive opaque-object lifecycle boilerplate,
3. optional family-specific capability helper for runtime/admin surfaces.

### 3.2 Helper A: common unsupported-runtime vocabulary

**Candidate file:**
- Create: `src/util/fd_platform_unsupported.h`

**Responsibilities:**
- standardize unsupported Windows build-lane wording,
- centralize tiny helpers for `errno = ENOTSUP`, `return ENOTSUP`, `return ENOENT`, `return NULL`,
- keep logging strings or return shims consistent.

**Acceptable content:**
- small inline helpers/macros only,
- no subsystem state,
- no object-layout generation,
- no public API reshaping.

**Example helper scope:**
- unsupported log helper
- unsupported `NULL` helper
- unsupported `ENOTSUP` helper
- unsupported `ENOENT` helper
- unsupported `-1` helper with `errno = ENOTSUP`

### 3.3 Helper B: opaque-object lifecycle helper

**Candidate file:**
- Create: `src/util/fd_platform_stub_object.h`

**Responsibilities:**
- standardize boring object lifecycle scaffolding for Windows build-lane stubs:
  - align/footprint helpers,
  - basic `new` null/alignment checks,
  - zero-init/sentinel-init pattern,
  - trivial `join`/`leave`/`delete` patterns.

**Important constraint:**
This helper should only remove repetitive lifecycle boilerplate. It should **not** try to generate every subsystem method body.

**Intended consumers:**
- `fd_event_client_windows_stub.c`
- `fd_grpc_client_windows_stub.c`
- `fd_udpsock_windows_stub.c`
- maybe part of `fd_http_server_windows_stub.c`

### 3.4 Helper C: runtime/admin capability helper

**Candidate files:**
- Create: `src/util/fd_platform_runtime_caps.h`
- Optional create: `src/util/fd_platform_runtime_caps.c`

**Responsibilities:**
- make the build-lane capability policy explicit for Windows-hosted unsupported runtime features,
- centralize shared policy wording for shmem/wksp capability absence,
- expose tiny helpers/constants used by `fd_shmem_windows_stub.c` and `fd_wksp_windows_stub.c`.

**Important constraint:**
Do **not** compress these files into unreadable macro-generated code. They encode a real policy boundary and must stay debuggable.

### 3.5 Non-goal helper shapes

Do **not** implement:
- one mega-macro that defines whole subsystems,
- a helper that owns exported public symbols for many subsystems,
- a helper that hides invariant-sensitive fallback values in opaque generated logic,
- a combined tile + service + runtime admin abstraction layer.

---

## 4. Slice-by-slice execution tracker

### Task 1: Record the remaining stub families and target helper shapes
**Status:** DONE

**Objective:** Freeze the classification so later slices do not over-generalize incompatible stub families.

**Files:**
- Modify: `doc/execution/win-support/finding-2-capability-layer-plan.md`

**Step 1:** confirm current Windows stub inventory after finding-1 refactors.

**Step 2:** record the four-family breakdown:
- already-solved tile runtime stubs,
- opaque object stubs,
- service/storage stubs,
- runtime/admin capability stubs.

**Step 3:** note the target helper for each family.

**Step 4: Fresh verification**
Run:
```bash
grep -R "FD_HAS_WINDOWS" -n src --include='*_windows_stub.c' | cat
```
Expected: inventory aligns with this plan’s family table.

**Step 5: Commit**
```bash
git add doc/execution/win-support/finding-2-capability-layer-plan.md
git commit -m "docs: classify windows unsupported-runtime stub families"
```

**Resolution:** Re-checked the live branch state and confirmed 13 Windows stub files remain, with the 5 tile-runtime stubs already collapsed onto `FD_PLATFORM_TILE_STUB(...)` and the other 8 files fitting the opaque-object, service/storage, and runtime/admin families captured in this plan.

**Verification used:** `grep -R "FD_HAS_WINDOWS" -n src --include='*_windows_stub.c' | cat`; `grep -R "FD_PLATFORM_TILE_STUB(" -n src/disco | cat`; `grep -R "unsupported on Windows build lane" -n src --include='*_windows_stub.c' | cat`

**Commit subject:** `docs: classify windows unsupported-runtime stub families`

---

### Task 2: Add the common unsupported-runtime helper
**Status:** DONE

**Objective:** Centralize the smallest repeated unsupported-return/logging policy without changing subsystem behavior.

**Files:**
- Create: `src/util/fd_platform_unsupported.h`
- Modify: a small first batch of Windows stub files that duplicate unsupported return/logging behavior

**Step 1:** add only tiny helpers/macros for:
- unsupported log wording,
- `errno = ENOTSUP` + `return -1`,
- `return ENOTSUP`,
- `return ENOENT`,
- `return NULL`.

**Step 2:** convert the easiest consumers first:
- `src/waltz/resolv/fd_netdb_windows_stub.c`
- `src/disco/store/fd_shredb_windows_stub.c`

**Step 3:** keep exported subsystem behavior unchanged.

**Step 4: Fresh verification**
Run:
```bash
just build-fd
grep -R "errno = ENOTSUP\|return ENOTSUP\|return ENOENT" -n src/* src/*/* | cat
```
Expected: helper exists and raw repeated boilerplate count drops.

**Step 5: Commit**
```bash
git add src/util/fd_platform_unsupported.h \
        src/disco/store/fd_shredb_windows_stub.c \
        src/waltz/resolv/fd_netdb_windows_stub.c
git commit -m "refactor: centralize windows unsupported return helpers"
```

**Resolution:** Added `src/util/fd_platform_unsupported.h` as the shared home for tiny unsupported-runtime wording and return helpers. Switched `fd_netdb_windows_stub.c` to the shared resolver unsupported string and moved `fd_shredb_windows_stub.c` query failures onto the common `errno = ENOTSUP`/`return -1` helper.

**Verification used:** `just build-fd`; `grep -R "errno = ENOTSUP\|return ENOTSUP\|return ENOENT" -n src | cat`; `grep -R "FD_WINDOWS_UNSUPPORTED_REASON\|fd_windows_unsupported_fail" -n src | cat`

**Commit subject:** `refactor: centralize windows unsupported return helpers`

---

### Task 3: Add the opaque-object lifecycle helper
**Status:** TODO

**Objective:** Remove repetitive lifecycle scaffolding from the stateful-object Windows stubs while leaving per-subsystem behavior explicit.

**Files:**
- Create: `src/util/fd_platform_stub_object.h`
- Modify: `src/disco/events/fd_event_client_windows_stub.c`
- Modify: `src/waltz/grpc/fd_grpc_client_windows_stub.c`
- Modify: `src/waltz/udpsock/fd_udpsock_windows_stub.c`
- Optional modify: `src/waltz/http/fd_http_server_windows_stub.c`

**Step 1:** centralize null/alignment/zero-init/trivial join/leave/delete patterns.

**Step 2:** convert the smallest consumers first:
- `fd_event_client_windows_stub.c`
- `fd_grpc_client_windows_stub.c`
- `fd_udpsock_windows_stub.c`

**Step 3:** only fold `fd_http_server_windows_stub.c` into this helper where the lifecycle pattern clearly fits; leave its staging helpers explicit.

**Step 4: Fresh verification**
Run:
```bash
just build-fd
grep -R "join( void \*\|leave( .*\*\|delete( void \*" -n src/*/*_windows_stub.c | cat
```
Expected: repeated lifecycle scaffolding is reduced, but subsystem files remain readable.

**Step 5: Commit**
```bash
git add src/util/fd_platform_stub_object.h \
        src/disco/events/fd_event_client_windows_stub.c \
        src/waltz/grpc/fd_grpc_client_windows_stub.c \
        src/waltz/udpsock/fd_udpsock_windows_stub.c \
        src/waltz/http/fd_http_server_windows_stub.c
git commit -m "refactor: reduce windows stub object boilerplate"
```

---

### Task 4: Refactor the HTTP stub onto the shared helper vocabulary
**Status:** TODO

**Objective:** Shrink `fd_http_server_windows_stub.c` without hiding meaningful HTTP-specific behavior.

**Files:**
- Modify: `src/waltz/http/fd_http_server_windows_stub.c`
- Modify: helper headers from Tasks 2-3 if needed

**Step 1:** move only generic unsupported-return and lifecycle scaffolding to helpers.

**Step 2:** keep HTTP-specific methods explicit:
- staging buffer operations,
- connection-close reason string,
- method string mapping,
- response body staging behavior.

**Step 3:** standardize listen/send/broadcast unsupported paths via shared helper vocabulary.

**Step 4: Fresh verification**
Run:
```bash
just build-fd
grep -n "unsupported on Windows build lane\|ENOTSUP" src/waltz/http/fd_http_server_windows_stub.c
```
Expected: file is smaller and less repetitive, but still clearly documents the HTTP contract.

**Step 5: Commit**
```bash
git add src/waltz/http/fd_http_server_windows_stub.c src/util/fd_platform_unsupported.h src/util/fd_platform_stub_object.h
git commit -m "refactor: simplify windows http server stub policy"
```

---

### Task 5: Add a runtime/admin capability helper for shmem + wksp
**Status:** TODO

**Objective:** Share Windows build-lane runtime capability policy across `shmem` and `wksp` without collapsing their explicit invariant-sensitive behavior into macros.

**Files:**
- Create: `src/util/fd_platform_runtime_caps.h`
- Optional create: `src/util/fd_platform_runtime_caps.c`
- Modify: `src/util/shmem/fd_shmem_windows_stub.c`
- Modify: `src/util/wksp/fd_wksp_windows_stub.c`

**Step 1:** centralize shared capability-policy wording and tiny helpers only.

**Step 2:** preserve explicit fallback values that satisfy broader runtime invariants:
- shmem count/index helpers,
- checkpoint/restore failure semantics,
- preview/checkpoint/restore return codes.

**Step 3:** do not hide these files behind giant codegen macros.

**Step 4: Fresh verification**
Run:
```bash
just build-fd
grep -R "unsupported on Windows build lane" -n src/util/shmem src/util/wksp | cat
```
Expected: policy wording is more centralized while fallback semantics stay explicit.

**Step 5: Commit**
```bash
git add src/util/fd_platform_runtime_caps.h \
        src/util/fd_platform_runtime_caps.c \
        src/util/shmem/fd_shmem_windows_stub.c \
        src/util/wksp/fd_wksp_windows_stub.c
git commit -m "refactor: share windows runtime capability policy"
```

---

### Task 6: Final pass on leftover subsystem stubs and tracker update
**Status:** TODO

**Objective:** Confirm the remaining Windows stubs sit on the intended helper boundaries and this file reflects the real finished state.

**Files:**
- Modify: `doc/execution/win-support/finding-2-capability-layer-plan.md`
- Optional modify: any leftover stub file that still duplicates obvious helper-worthy policy

**Step 1:** scan all `*_windows_stub.c` files for boilerplate still worth centralizing.

**Step 2:** update this tracker after each finished slice with:
- `**Status:** DONE`
- short resolution note
- exact verification commands used
- commit subject

**Step 3:** before declaring the finding closed, confirm:
- no non-DONE tasks remain here,
- shared helpers own repeated policy,
- no accidental scope expansion into runtime-parity work.

**Step 4: Fresh verification**
Run:
```bash
just build-fd
just build-tk
grep -R "FD_HAS_WINDOWS" -n src --include='*_windows_stub.c' | cat
grep -R "unsupported on Windows build lane" -n src | cat
```
Expected: helperized policy is concentrated and both build entrypoints still pass.

**Step 5: Commit**
```bash
git add doc/execution/win-support/finding-2-capability-layer-plan.md
git commit -m "docs: update finding 2 capability-layer tracker"
```

---

## 5. Verification commands

**Build checks**
```bash
just build-fd
just build-tk
```

**Stub inventory checks**
```bash
grep -R "FD_HAS_WINDOWS" -n src --include='*_windows_stub.c' | cat
grep -R "FD_PLATFORM_TILE_STUB(" -n src/disco | cat
```

**Boilerplate reduction checks**
```bash
grep -R "unsupported on Windows build lane" -n src | cat
grep -R "errno = ENOTSUP" -n src | cat
grep -R "return ENOTSUP" -n src | cat
grep -R "return ENOENT" -n src | cat
```

**Family-specific checks**
```bash
grep -n "join( void \*\|leave( .*\*\|delete( void \*" src/disco/events/fd_event_client_windows_stub.c src/waltz/grpc/fd_grpc_client_windows_stub.c src/waltz/http/fd_http_server_windows_stub.c src/waltz/udpsock/fd_udpsock_windows_stub.c | cat

grep -R "unsupported on Windows build lane" -n src/util/shmem src/util/wksp | cat
```

**Interpretation rule**
- Success is **not** zero Windows stub files.
- Success is: unsupported-runtime policy is concentrated in a few helper layers, while subsystem-specific public contracts remain explicit and readable.

---

## 6. Finish line

This finding is closed when:
- the existing tile runtime helper remains the sole home for repeated `fd_topo_run_tile_t` unsupported policy,
- the remaining Windows stubs are grouped behind **2-3 small shared helper layers** instead of many isolated policy copies,
- `shmem` and `wksp` share a runtime-capability policy layer where appropriate,
- public subsystem wrappers still own their exported symbols and remain readable,
- and this tracker shows all tasks `DONE` with fresh verification recorded.
