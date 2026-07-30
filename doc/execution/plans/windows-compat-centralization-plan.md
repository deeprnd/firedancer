# Windows Compatibility Glue Centralization Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Eliminate duplicated Windows compatibility policy by creating a single central header and consolidating build flag definitions.

**Architecture:** One canonical header (`fd_windows_compat.h`) owns ALL CRT/Windows compat mappings. Build flag definitions are deduplicated in both Makefile and Zig systems. Source files consume the central header instead of open-coding fragments.

---

## Scope Audit

| Duplication Pattern | Location | Count |
|---|---|---|
| CRT function mappings (`_stricmp`, `_strnicmp`) | `fd_windows_compat.h` | 2 mappings, 2 files included |
| Other CRT functions (`strdup`, `snprintf`, `vsnprintf`) | Scattered or absent | 0 centralized |
| Raw `_WIN32` in .S files | `fd_aes_gcm_aesni.S`, `fd_aes_gcm_avx10.S` | 2 locations |
| Build flag duplication: Makefile | `windows_clang.mk` + `config/base.mk` | 4 flags duplicated |
| Build flag duplication: Zig | `build.zig:shimCFlagsFor()` | Same 4 flags |
| `FD_IO_STYLE` default derivation | `fd_io.c` + `windows_clang.mk` + `build.zig` | 3 places |
| `FD_LOG_STYLE` default derivation | `fd_log.c` + `windows_clang.mk` + `build.zig` | 3 places |
| `strncasecmp` callers without compat header | `fd_rpc_client.c`, `fd_http_server.c`, `fd_ssresolve.c`, `fd_sshttp.c`, `fd_genesis_client.c` | 5 files |
| Windows stub files (`*_windows_stub.c`) | 13 files | Correctly gated (not touching) |
| `Local.mk` gates on `FD_HAS_WINDOWS` | 15 lines across 13 directories | Correctly structured |

---

### Task 1: Rewrite `fd_windows_compat.h` to own ALL CRT compat macros

**Status:** **DONE**

**Files:**
- Modified: `src/util/fd_windows_compat.h`

**Summary:** Expanded from 2 mappings to a complete Windows CRT compatibility layer:
- `strcasecmp → _stricmp`
- `strncasecmp → _strnicmp`
- `strdup → _strdup`
- `snprintf → _snprintf`
- `vsnprintf → _vsnprintf`
- `fd_windows_unsupported_enotsup()` inline helper
- `_CRT_SECURE_NO_WARNINGS` default
- `FD_IO_STYLE` and `FD_LOG_STYLE` defaults (both Windows and non-Windows paths)

**Verification:** Header compiles clean both with and without `FD_HAS_WINDOWS=1`.

---

### Task 2: Replace raw `_WIN32` in .S files with `FD_HAS_WINDOWS`

**Status:** **DONE**

**Files:**
- Modified: `src/ballet/aes/fd_aes_gcm_aesni.S:165`
- Modified: `src/ballet/aes/fd_aes_gcm_avx10.S:122`

**Change:** `#if defined(__linux__) || defined(_WIN32)` → `#if defined(__linux__) || FD_HAS_WINDOWS`

**Verification:** `grep -rn '_WIN32' src/ --include='*.S' | grep -v third_party` → empty.

---

### Task 3: Consolidate Windows build flags in Makefile

**Status:** **DONE**

**Files:**
- Modified: `config/machine/windows_clang.mk`

**Change:** Removed duplicate `FD_HAS_WINDOWS:=1`, `CPPFLAGS+=-DFD_HAS_WINDOWS=1 -D_CRT_SECURE_NO_WARNINGS -DFD_IO_STYLE=1`. These are already set by `config/base.mk` (MACHINE filter) and `config/extra/with-hosted.mk`. Replaced with a comment documenting the source of truth.

---

### Task 4: Deduplicate Windows flags in build.zig

**Status:** **DONE**

**Files:**
- Modified: `build.zig`

**Change:** Extracted `-D_CRT_SECURE_NO_WARNINGS`, `-DFD_IO_STYLE=1`, `-Wno-format`, `-Wno-format-extra-args` into a named `windows_cflags` constant. `shimCFlagsFor()` Windows case now uses `.windows => ... ++ windows_cflags`.

---

### Task 5: Fix all files using strcasecmp/strncasecmp

**Status:** **DONE**

**Files:**
- Added include to: `src/waltz/http/fd_http_server.c`
- Added include to: `src/app/shared_dev/rpc_client/fd_rpc_client.c`
- Added include to: `src/discof/restore/utils/fd_ssresolve.c`
- Added include to: `src/discof/restore/utils/fd_sshttp.c`
- Added include to: `src/discof/genesis/fd_genesis_client.c`

**Change:** Each file now includes `util/fd_windows_compat.h` at the top.

---

### Task 6: Centralize `FD_IO_STYLE` and `FD_LOG_STYLE` defaults

**Status:** **IN PROGRESS**

**Files to modify:**
- Modify: `src/util/io/fd_io.c` — remove duplicate default derivation (lines 3-14)
- Modify: `src/util/log/fd_log.c` — remove duplicate default derivation (lines 1-9)

**Change:** The central `fd_windows_compat.h` now defines `FD_IO_STYLE` and `FD_LOG_STYLE` defaults. Source files no longer need to re-derive them. The Makefile/Zig still pass `-DFD_IO_STYLE=1` / `-DFD_LOG_STYLE=1` as compile-time overrides for Windows.

**Verification command:**
```bash
# fd_io.c should no longer have the #ifndef FD_IO_STYLE block
grep -n 'FD_IO_STYLE' src/util/io/fd_io.c
# fd_log.c should no longer have the #ifndef FD_LOG_STYLE block
grep -n 'FD_LOG_STYLE' src/util/log/fd_log.c
```

---

### Task 7: Build verification on Linux

**Status:** **PENDING**

**Verification commands:**
```bash
cd /home/vicgenin/work/git/tickoni
just build-linux-clang
just test
```

---

### Task 8: Update plan doc with final status

**Status:** **PENDING**

---

## Verification Summary

After all tasks complete:

1. **No raw `_WIN32` in non-third-party .S files** — `grep -rn '_WIN32' src/ --include='*.S' | grep -v third_party` returns empty
2. **All strcasecmp/strncasecmp callers include `fd_windows_compat.h`** — audit returns no missing files
3. **Build flags defined in exactly one place per build system** — grep confirms no duplicate flag definitions
4. **Linux build passes** — `just build-linux-clang` and `just test` succeed
5. **No new compiler warnings or errors** — clean build

## Notes

- **Third-party code** (`third_party/` directory): Leave `_CRT_SECURE_NO_WARNINGS` definitions in third-party headers alone.
- **Windows stub files** (`*_windows_stub.c`): Don't touch — correctly gated on `#if FD_HAS_WINDOWS`.
- **`windows_crt.c`**: Don't touch — `_fltused` is a one-off CRT initializer.
- **`.S file assembly guards`**: Only change `_WIN32` → `FD_HAS_WINDOWS`.
