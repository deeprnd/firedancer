# Windows `build.zig` Link-Closure Plan

> **For Hermes:** Use `writing-plans` and `zig-build-script`. Execute this plan slice-by-slice. Keep Windows support build-CI-only per `doc/execution/V2.22/windows-build-ci.md`. Do not expand scope into Windows runtime parity.

**Goal:** Remove Firedancer-internal Windows link-closure knowledge from `build.zig` so Zig consumes a narrower FD-produced contract instead of hardcoded object paths.

**Architecture:** Keep Tickoni-owned C shim selection in Zig, but move the Windows-specific FD closure description behind an FD-side/generated artifact emitted into `build/fd-tickoni-fd/lib/`. `build.zig` should consume that artifact mechanically and stop naming individual `build/fd-tickoni-fd/obj/...` members directly.

**Tech Stack:** Zig 0.16 `build.zig`, Firedancer GNU make build outputs, Tickoni `contrib/` build scripts, Windows build-only CI contract.

---

## 1. Contract

**Frozen contract inputs**
- `doc/execution/V2.22/windows-build-ci.md:9-12` — Windows support here is build-CI-only
- `doc/execution/V2.22/windows-build-ci.md:45-52` — lanes prove compile/build only
- `doc/execution/V2.22/windows-build-ci.md:72-77` — required constraint: keep OS divergence behind shared actions, scripts, shims, or platform APIs

**Finding scope**
This plan addresses the third maintainability finding:

> `build.zig` carries Windows-specific link-closure knowledge for Firedancer internals instead of consuming a narrower build-layer contract.

This plan does **not**:
- enable Windows runtime parity,
- redesign Tickoni-owned shim semantics,
- inline more FD object-path knowledge into Zig helpers,
- change the build-only Windows support contract,
- claim local Windows verification on a Linux host.

**Success criteria**
- `build.zig` no longer contains raw `build/fd-tickoni-fd/obj/...` fixup paths.
- Windows FD closure knowledge moves into a generated artifact under the FD build output tree.
- Zig consumes that artifact through one small helper instead of hardcoded object arrays.
- Linux `just build-fd` and `just build-tk` still pass.
- The tracker records exact verification evidence and commits per slice.

**Primary verification metrics**
1. `build.zig` contains zero `build/fd-tickoni-fd/obj/` references.
2. `build/fd-tickoni-fd/lib/` contains generated Windows Zig link-contract artifacts.
3. Existing non-Windows build entrypoints still pass after the refactor.

---

## 2. Current closure inventory

### 2.1 Current Zig-owned Windows closure hooks

**Supervisor path**
- `build.zig:417-419` — Windows supervisor build links Tickoni shim lib and then injects FD fixups via `addWindowsFdSupervisorFixups(exe)`.
- `build.zig:2223-2247` — `addWindowsFdSupervisorFixups` hardcodes 21 FD object paths under `build/fd-tickoni-fd/obj/...`.

**Codec / CLI path**
- `build.zig:1743-1747` — Windows CLI build links Tickoni codec shim lib and then injects FD fixups via `addWindowsFdCodecFixups(cli_exe)`.
- `build.zig:2249-2260` — `addWindowsFdCodecFixups` hardcodes 8 FD object paths under `build/fd-tickoni-fd/obj/...`.

**Shared library-link retry policy**
- `build.zig:2090-2100` — `linkTickoniSystemLibraries` repeats the same static libs on Windows to cope with COFF archive-member discovery.

### 2.2 Closure-member families currently hardcoded in Zig

| Consumer | Current hardcoded members | Why they leak FD internals |
| --- | --- | --- |
| Supervisor | `tango/*`, `util/wksp/*`, `util/log/fd_log.o`, `util/pod/fd_pod.o`, `util/fd_util.o`, `disco/topo/*`, `disco/events/fd_event_report.o`, `disco/metrics/fd_metrics.o`, `third_party/cjson/cJSON.o`, `ballet/*`, `util/cstr/fd_cstr.o`, `util/tile/fd_tile_threads.o`, `util/shmem/fd_shmem_windows_stub.o` | Encodes FD object layout, archive membership, and Windows-stub choice directly in Zig |
| Codec | `ballet/*`, `third_party/cjson/cJSON.o`, `util/log/fd_log.o`, `util/env/fd_env.o`, `util/cstr/fd_cstr.o`, `util/alloc/fd_alloc.o`, `util/wksp/fd_wksp_admin.o` | Same FD object-layout dependency, but for the smaller codec/CLI surface |

### 2.3 Target exported contract

**Preferred long-term shape:** FD-side closure archives.

**First implementation slice for this branch:** generated FD-side manifest files under `build/<BUILDDIR>/lib/` that list the extra object-file closure for each consumer class.

This fallback is acceptable because it:
- removes raw object-path ownership from Zig,
- keeps the contract emitted by the build layer,
- allows a later archive-producing follow-up without reintroducing Zig path lists.

---

## 3. Slice-by-slice execution tracker

### Task 1: Record the current closure inventory and freeze the generated-contract target
**Status:** DONE

**Objective:** Create the plan/tracker with the exact current Zig-owned closure surface and the chosen first-step contract shape.

**Files:**
- Create: `doc/execution/win-support/finding-3-build-zig-link-closure-plan.md`

**Step 1:** capture the current supervisor and codec fixup entrypoints in `build.zig`.

**Step 2:** record the current hardcoded object-path families by consumer class.

**Step 3:** freeze the first implementation target as FD-side generated manifest files under `build/<BUILDDIR>/lib/`.

**Step 4: Fresh verification**
Run:
```bash
grep -n "addWindowsFdSupervisorFixups\|addWindowsFdCodecFixups\|build/fd-tickoni-fd/obj/" build.zig | cat
python3 - <<'PY'
from pathlib import Path
text = Path('doc/execution/win-support/finding-3-build-zig-link-closure-plan.md').read_text()
print('task_count=', text.count('### Task '))
print('has_generated_contract=', 'generated-contract target' if 'generated-contract target' in text else 'missing')
PY
```
Expected: the doc records the two current fixup hooks and at least one `build/fd-tickoni-fd/obj/...` reference remains in `build.zig` before the refactor.

**Step 5: Commit**
```bash
git add doc/execution/win-support/finding-3-build-zig-link-closure-plan.md
git commit -m "docs: add windows link closure plan"
```

**Resolution:** Added the finding-3 execution tracker, froze the current Zig-owned closure surface for supervisor and codec consumers, and committed to a generated FD-side manifest contract as the first maintainability step.

**Verification used:** `grep -n "addWindowsFdSupervisorFixups\|addWindowsFdCodecFixups\|build/fd-tickoni-fd/obj/" build.zig | cat`; ad-hoc Python structural check over the new plan document.

**Commit subject:** `docs: add windows link closure plan`

---

### Task 2: Emit generated Windows Zig link manifests from the FD build layer
**Status:** DONE

**Objective:** Move the Windows closure lists out of `build.zig` and into generated FD-side artifacts.

**Files:**
- Create: `contrib/fd-write-zig-link-manifests.sh`
- Modify: `contrib/fd-build-lib.sh`
- Optional modify: `contrib/fd-build-windows.sh`

**Step 1:** add one script that writes exactly two manifest files under `build/<BUILDDIR>/lib/`:
- `fd_windows_zig_supervisor_link.txt`
- `fd_windows_zig_codec_link.txt`

**Step 2:** keep the object lists in that FD-side script, not in `build.zig`.

**Step 3:** wire `contrib/fd-build-lib.sh` to call the manifest writer after successful library builds so the artifacts exist before `zig build` consumes them.

**Step 4:** keep the manifest format simple: newline-separated relative object paths, one per line, no JSON parser needed.

**Step 5: Fresh verification**
Run:
```bash
just build-fd
python3 - <<'PY'
from pathlib import Path
for name in ['fd_windows_zig_supervisor_link.txt', 'fd_windows_zig_codec_link.txt']:
    path = Path('build/fd-tickoni-fd/lib') / name
    print(path, path.exists(), sum(1 for line in path.read_text().splitlines() if line.strip()))
PY
```
Expected: both manifest files exist and contain non-zero closure entries.

**Step 6: Commit**
```bash
git add contrib/fd-write-zig-link-manifests.sh contrib/fd-build-lib.sh contrib/fd-build-windows.sh
git commit -m "build: emit windows zig link manifests"
```

**Resolution:** Added `contrib/fd-write-zig-link-manifests.sh` as the FD-side owner of the supervisor and codec closure lists and wired `contrib/fd-build-lib.sh` to emit the manifests after each successful FD build. The generated artifacts now live under `build/<BUILDDIR>/lib/` instead of leaving the closure shape implicit in Zig.

**Verification used:** `just build-fd`; Python existence/entry-count check for `build/fd-tickoni-fd/lib/fd_windows_zig_supervisor_link.txt` and `build/fd-tickoni-fd/lib/fd_windows_zig_codec_link.txt`

**Commit subject:** `build: emit windows zig link manifests`

---

### Task 3: Teach `build.zig` to consume the generated link contract
**Status:** DONE

**Objective:** Replace hardcoded Windows object arrays in Zig with one manifest-consuming helper.

**Files:**
- Modify: `build.zig`

**Step 1:** add one helper that reads a newline-separated manifest file and adds each listed object via `addObjectFile`.

**Step 2:** replace:
- `addWindowsFdSupervisorFixups`
- `addWindowsFdCodecFixups`

with manifest-consuming helpers that point at the generated files in `build/fd-tickoni-fd/lib/`.

**Step 3:** delete raw `build/fd-tickoni-fd/obj/...` literals from `build.zig`.

**Step 4:** keep the existing Windows repeated-library loop for now unless verification proves it is redundant; this finding is about raw closure ownership first.

**Step 5: Fresh verification**
Run:
```bash
just build-tk
grep -n "build/fd-tickoni-fd/obj/" build.zig || true
grep -n "fd_windows_zig_.*_link.txt" build.zig | cat
```
Expected: `just build-tk` still passes on Linux, `build.zig` contains zero raw FD object paths, and the new manifest filenames are referenced.

**Step 6: Commit**
```bash
git add build.zig
git commit -m "refactor: consume windows zig link manifests"
```

**Resolution:** Replaced the supervisor and codec Windows fixup arrays with one manifest-reading helper in `build.zig`. Zig now points at `fd_windows_zig_supervisor_link.txt` / `fd_windows_zig_codec_link.txt` under `fd_lib_dir` and no longer embeds raw `build/fd-tickoni-fd/obj/...` paths.

**Verification used:** `just build-tk`; `grep -n "build/fd-tickoni-fd/obj/" build.zig || true`; `grep -n "fd_windows_zig_.*_link.txt" build.zig | cat`

**Commit subject:** `refactor: consume windows zig link manifests`

---

### Task 4: Final tracker update and closure sweep
**Status:** TODO

**Objective:** Record the finished state, verification, and any intentionally deferred follow-up.

**Files:**
- Modify: `doc/execution/win-support/finding-3-build-zig-link-closure-plan.md`

**Step 1:** update Tasks 2-4 to `DONE` with resolution notes, exact verification commands, and commit subjects.

**Step 2:** confirm the finding-close criteria:
- no raw `build/fd-tickoni-fd/obj/...` references remain in `build.zig`,
- generated link artifacts exist under `build/fd-tickoni-fd/lib/`,
- no runtime-scope claims were added.

**Step 3:** explicitly note that closure archives remain a possible later cleanup, but are **not** required for this finding to be closed once Zig consumes the generated manifest contract.

**Step 4: Fresh verification**
Run:
```bash
just build-fd
just build-tk
grep -n "build/fd-tickoni-fd/obj/" build.zig || true
python3 - <<'PY'
from pathlib import Path
for name in ['fd_windows_zig_supervisor_link.txt', 'fd_windows_zig_codec_link.txt']:
    path = Path('build/fd-tickoni-fd/lib') / name
    print(path.name, path.exists(), path.stat().st_size if path.exists() else 0)
PY
```
Expected: both build entrypoints pass, no raw object paths remain in `build.zig`, and the generated artifacts are present.

**Step 5: Commit**
```bash
git add doc/execution/win-support/finding-3-build-zig-link-closure-plan.md
git commit -m "docs: update windows link closure tracker"
```

---

## 4. Verification commands

**Build checks**
```bash
just build-fd
just build-tk
```

**Manifest generation checks**
```bash
python3 - <<'PY'
from pathlib import Path
for name in ['fd_windows_zig_supervisor_link.txt', 'fd_windows_zig_codec_link.txt']:
    path = Path('build/fd-tickoni-fd/lib') / name
    print(path)
    print(path.read_text())
PY
```

**Closure ownership checks**
```bash
grep -n "build/fd-tickoni-fd/obj/" build.zig || true
grep -n "fd_windows_zig_supervisor_link.txt\|fd_windows_zig_codec_link.txt" build.zig | cat
```

**Interpretation rule**
- Success is **not** full Windows runtime support.
- Success is: `build.zig` stops owning the FD object-path closure directly, and the build layer emits a narrower contract Zig consumes.

---

## 5. Finish line

This finding is closed when:
- `build.zig` contains no raw FD object-fixup paths,
- the FD build layer emits generated Windows Zig link manifests under `build/fd-tickoni-fd/lib/`,
- Zig consumes those manifests through one helper,
- Linux `just build-fd` and `just build-tk` still pass,
- the tracker is fully marked `DONE` with fresh verification evidence.
