# Windows Builds CI (x86_64 + ARM64) Implementation Plan

> **For Hermes:** Use subagent-driven-development only after the contract and portability blockers below are resolved in order.

**Goal:** Add Windows build CI lanes for Tickoni on `windows-2025` and `windows-11-arm`, with the same intentionality as the current macOS lanes, while fixing the known OS-specific switches ahead of the first CI run so the initial workflow bring-up does not explode on obvious Linux/macOS assumptions.

**Architecture:** Treat this as a portability-and-CI story, not a YAML-only story. First make the shared repo entrypoints (`just`, composite actions, deps setup, Firedancer-lib build wrappers, Zig/C shims) capable of selecting a native Windows path without inline Linux/macOS assumptions. Then add Windows workflow jobs that call those same entrypoints. The Windows path should hide OS divergence behind scripts/shims/ABI boundaries rather than scattering `if windows` branches through product logic.

**Tech Stack:** GitHub Actions, Windows runners (`windows-2025`, `windows-11-arm`), PowerShell + Bash compatibility layer where needed, Zig 0.16, Firedancer GNU-make build surface, Tickoni C ABI shims, repo composite actions.

---

## What this plan is closing

This plan is for the CI/build substrate required before V2.22 Windows runtime work can move quickly.

It is specifically aimed at:
- adding Windows build lanes similar to the existing macOS CI shape
- preemptively fixing current Unix-only assumptions before CI reveals them one by one
- deciding which pieces are true native-Windows builds vs. intentionally unsupported / stubbed
- keeping OS branching behind reusable build/runtime abstractions

It is **not** trying to finish the full Windows retail runtime epic in one go.

---

## Current state audit

### Existing CI shape

Current workflows already split build responsibilities cleanly:
- `.github/workflows/build-fd.yml` — FD-subset engine builds on Linux + macOS
- `.github/workflows/build-tk.yml` — Tickoni harness builds on Linux + macOS
- `.github/actions/setup-public-gh-runner/action.yml` — shared runner bootstrap
- `.github/actions/deps/action.yml` — dependency install/cache layer
- `.github/actions/build-fd-tk-libs/action.yml` — shared FD-libs build entrypoint

That is the right place to add Windows. Do **not** add a one-off standalone workflow that bypasses these abstractions.

### Preemptive blockers already visible in repo

#### CI/bootstrap blockers
1. `.github/actions/setup-public-gh-runner/action.yml`
   - only knows `apt-get` and `brew`
   - macOS-specific GNU make install exists, no Windows branch
   - gitleaks installer is hardcoded to `linux_x64`
2. `.github/actions/deps/action.yml`
   - installs packages with `apt-get`
   - uses `brew` only for macOS zstd
   - compiler activation path assumes `/opt/<compiler>/...`
   - calls `update-alternatives`
3. `deps.sh`
   - supports `Darwin` and `Linux`; other OS prints unsupported
   - package-check/install code is Linux/macOS distro-specific

#### Build-script blockers
4. `justfile`
   - public FD recipes are Linux/macOS only: `build-fd`, `build-fd-gcc`, `build-fd-clang`, `build-fd-arm`, `build-fd-macos-intel`, `build-fd-macos-arm`
   - no Windows recipes or shell abstraction for Windows shell selection
5. `contrib/fd-build-linux.sh`
   - Linux-only entrypoint by name and behavior
6. `contrib/fd-build-lib.sh` + `contrib/fd-tk-libs.sh`
   - assume GNU make + bash + Unix path conventions
   - `fd_tk_libs.sh` only has a macOS-specific make fallback via `RUNNER_OS=macOS`

#### Runtime / shim blockers likely to break even a harness-only Windows build
7. `src/tickoni/c_abi/shim/os.c`
   - has Linux branch, Apple branch, and generic Unix fallback
   - no Windows implementation for monotonic clock, sleep, self exe path, parent pid, process kill, fd write
8. `src/tickoni/c_abi/shim/sandbox.c`
   - non-Linux fallback uses `<unistd.h>` and `getpid()`
   - that fallback is Unix-ish, not Windows
9. `src/app/tickoni/supervisor.zig`
   - explicit `std.posix.W.*`, `waitpid`, `SIGKILL` use in process supervision / teardown
   - this is a real Windows compile blocker unless abstracted
10. `src/tickoni/c_abi/boot.zig`
   - `haltForTileProcess()` is Linux-special-cased today; Windows policy must be made explicit
11. `src/tickoni/util/os_api.zig`
   - typed around `std.posix.pid_t` and `std.posix.fd_t`; may need a thinner platform-neutral surface

### Existing Windows intent already in docs/code

Windows is not greenfield conceptually:
- `src/tickoni/util/tier.zig` already defines `windows_retail`
- `src/tickoni/version.zig` and `src/tickoni/doctor/output.zig` already recognize Windows tiering
- roadmap epic `doc/strategy/roadmap/epics/v2.22.md` already expects a Windows retail path
- `doc/strategy/roadmap/stories/v2.22-s3.md` explicitly calls for Windows `tickoni --version` / `tickoni doctor`

So the repo already claims Windows at the planning/metadata layer. CI/build work now needs to make that honest.

### Operations that are explicitly not supported on Windows today

These are not speculative; they fall out of the current tier docs and the current code shape.

| Operation / surface | Current Windows status | Why unsupported today | Implication for CI / implementation |
| --- | --- | --- | --- |
| Full Linux shared-memory topology | Not supported | `doc/knowledge/platform-tiers.md` marks Windows retail as `no shared-memory topology`; current repo still treats Linux full-runtime as the only real shared-memory topology tier | Windows CI must not pretend to validate Linux full-runtime behavior; first Windows jobs should target retail build surfaces only |
| seccomp / Landlock / Firedancer sandbox entry | Not supported | `platform-tiers.md` explicitly says no seccomp/sandbox on Windows; `sandbox.c` only has Linux implementation plus Unix-ish fallback | Windows strategy must keep sandbox disabled/stubbed and make that visible, not try to emulate seccomp in CI |
| AF_PACKET / XDP / kernel-bypass networking | Not supported | `platform-tiers.md` says Windows retail uses socket networking, reduced tile set | Windows build CI should not include network/runtime checks that assume Linux packet path support |
| Replay proof on Windows retail | Not yet supported | `platform-tiers.md` has replay proof as `✗` for `windows_retail` | do not add replay/e2e expectations to first Windows CI lanes |
| Sandbox adapter substitute on Windows retail | Not yet supported | `platform-tiers.md` has sandbox adapter substitute as `✗` for `windows_retail` | first Windows CI pass should not include substitute-path tests as if they already exist |
| Live execution / privileged execution | Not supported | V2.22 epic and retail docs say paper/sandbox only, no live execution | CI should validate build + trust-surface commands, not any real execution path |
| Native direct source build as a documented retail promise | Required by user constraint, not yet supported by repo | V2.22 docs leave the Windows path unresolved, but the active implementation constraint is now native-only | the plan must treat native Windows build support as mandatory and remove VM/WSL/container fallback proposals from the support strategy |
| POSIX process supervision semantics | Not supported in current code | `supervisor.zig` uses `waitpid`, `std.posix.W.*`, `SIGKILL`; `os_api.zig` exposes POSIX-shaped types | this is a real compile blocker for `tickoni`; we must abstract it before Windows harness CI can be expected to pass |
| Unix process/file-descriptor OS shims | Not supported in current code | `os.c` has Linux + Apple + generic Unix fallback only; `sandbox.c` fallback uses `<unistd.h>` / `getpid()` | add real Win32 branches or explicit unsupported stubs hidden behind Tickoni ABI |

### How the current macOS workaround strategy maps poorly to Windows

The current macOS lanes are a mix of real platform work and shortcuts that are acceptable on Darwin but do not transfer directly to Windows.

| Existing macOS workaround | Why it worked on macOS | Why it is not enough for Windows | Recommended Windows adjustment |
| --- | --- | --- | --- |
| Homebrew-installed GNU make (`brew install make`) | macOS runner has Homebrew and a Unix shell environment; Firedancer build remains make/bash-centric | Windows runners do not have Homebrew, and GNU make availability is not implicit | define a native Windows toolchain bootstrap path explicitly (for example MSYS2 `pacman`, Chocolatey, or Scoop), then teach shared actions/recipes to use it |
| `fd_tk_libs.sh` special-cases `RUNNER_OS=macOS` for make lookup | enough to swap BSD `make` out for GNU make on Darwin | Windows needs a broader tool-resolution abstraction, not another one-off branch | replace the macOS-only make lookup with a general OS/tool resolver that can select `gmake`, `make`, or Windows-hosted GNU make path by platform |
| macOS Intel recipe injects `/usr/local/homebrew/bin` and `JUST_GMAKE` | GitHub macOS Intel runner needed nonstandard Homebrew prefix handling | Windows runner path layout will differ more radically and cannot be fixed by prefix injection alone | move toolchain/path setup into reusable Windows bootstrap scripts rather than recipe-local PATH hacks |
| macOS retail strategy disables Linux-only sandboxing and shared-memory parity but still uses native Unix process/ABI helpers | Darwin still has `unistd`, signals, `clock_gettime`, `_NSGetExecutablePath`, etc., so Unix-ish fallback was enough | Windows does not share those Unix APIs; generic non-Linux fallback is insufficient | create first-class Windows C ABI shims instead of extending the generic fallback path |
| macOS build jobs can still call bash-based `just`/script entrypoints directly | GitHub macOS runners already provide bash-compatible shell and Unix path semantics | Windows shell semantics, path separators, quoting, and environment activation differ | define which Windows shell each recipe/action expects (`pwsh` vs MSYS2 bash vs WSL bash) and encode that explicitly in workflows/actions |
| macOS lanes prove native build parity for two runner variants (`macos-15`, `macos-15-intel`, plus macOS 26 lanes for harness) | Darwin path decision for V2.21 is already made and documented as native retail path | Windows native path is required, but the repo is not yet ready for it | mirror the macOS matrix shape only after the native Windows toolchain/build substrate is made real; do not use WSL/container/VM as a fallback strategy |
| macOS retail docs defer CaseOps tier display and close trust surface through CLI + evidence | acceptable because the docs already explicitly call that deferment out | Windows can reuse this trust-surface idea, but should not inherit macOS-specific claims like native shared-memory exclusion wording unchanged | reuse the S7 trust-surface pattern, but write Windows-specific docs around native install/update/verification substrate (PowerShell, winget, per-user paths) |

### Strategy recommendation based on those unsupported operations

Recommended staged approach:

1. **Assume native Windows builds are required.**
   - Do not leave the substrate choice open in implementation planning.
   - The work now is to make the repo and CI genuinely support a native Windows toolchain/build path.

2. **Separate “native Windows build substrate” from “Windows retail runtime semantics”.**
   - CI can prove that native Windows runners can execute the chosen build pipeline.
   - That is different from proving all retail runtime operations are already natively supported.

3. **Promote the current macOS one-off fixes into general cross-platform abstractions.**
   - make/tool lookup
   - package/bootstrap selection
   - shell selection
   - process control abstraction
   - OS shim entrypoints
   Do this once, then let both macOS and Windows consume the same abstraction.

4. **Treat unsupported operations as explicit skips/stubs in first Windows CI.**
   - no replay lane
   - no seccomp lane
   - no Linux full-runtime claims
   - no live execution claims
   - no VM/WSL/container fallback presented as the support strategy

5. **Abstract process semantics, not Unix signal names.**
   - Do **not** design the Windows port around helpers like `isSigkill()` or other Unix-status questions.
   - Instead, introduce a platform-neutral process abstraction that answers questions like:
     - did the child exit normally?
     - did it crash?
     - was it force-terminated?
     - is it stale?
   - Linux can implement force termination with `SIGKILL`; Windows can implement it with native process termination APIs.
   - The supervisor should stop decoding raw `waitpid` / `std.posix.W.*` status directly and consume an already-decoded neutral result from a platform API.

6. **Use the macOS trust-surface closure pattern, not the macOS toolchain hacks.**
   - reuse: CLI-first trust surface, evidence bundle, explicit degraded guarantees
   - do not reuse blindly: Homebrew path hacks, Darwin-only shim assumptions, Unix fallback shims

---

## Design decision to lock before implementation

### Decision A — what exactly will the first Windows CI lanes prove?

Before writing YAML, freeze this contract:

**Recommended first-pass contract:**
1. `build-fd.yml` gains Windows x86_64 + ARM64 jobs that build the scoped Firedancer/Tickoni C-lib subset required by the harness.
2. `build-tk.yml` gains Windows x86_64 + ARM64 jobs that build `tickoni` after the FD subset succeeds.
3. No Windows test lanes in the first PR unless the build lanes are already stable.
4. The first-pass support strategy is native Windows on the named runners; do not use VM-, WSL2-, or container-backed fallback lanes as the official path.

If the user wants “similarly how we have macOS ones”, the clean mapping is:
- `Engine Build / Windows 2025`  → x86_64
- `Engine Build / Windows 11 ARM` → ARM64
- `Harness Build / Windows 2025`
- `Harness Build / Windows 11 ARM`

But those jobs must still call shared repo entrypoints, not inline ad-hoc commands.

---

## Recommended implementation sequence

### Phase 0: freeze the Windows CI closure contract — DONE

**Objective:** Define what counts as “Windows build CI added” before any code churn.

**Files:**
- Create: `doc/execution/V2.22/windows-build-ci.md`
- Modify: `doc/execution/ci.md`
- Modify: `/home/vicgenin/work/git/tickoni/.hermes/plans/2026-07-28_092215-win-builds-ci-plan.md`

**Required content:**
- exact runner labels: `windows-2025`, `windows-11-arm`
- exact first-pass jobs to add
- whether each job is native Windows on the runner (this plan assumes yes)
- explicit non-goals for first PR (for example: no sanitizer, no seccomp, no FD e2e)

**Verification:**
- plan doc references the four proposed jobs explicitly
- `ci.md` gets a placeholder “planned Windows lanes” note only after the contract is frozen

**Commit point:**
- `docs: freeze Windows build CI contract`

---

### Phase 1: make shared CI bootstrap actions OS-selectable — DONE

**Objective:** Ensure the shared GitHub Actions bootstrap layers can run on Windows without Linux/macOS-only assumptions.

**Files:**
- Modify: `.github/actions/setup-public-gh-runner/action.yml`
- Modify: `.github/actions/deps/action.yml`
- Possibly create: `.github/actions/setup-public-gh-runner/scripts/setup-windows.ps1`
- Possibly create: `.github/actions/deps/scripts/install-zstd-windows.ps1`

**Work:**
1. Add Windows branches for:
   - package/bootstrap steps
   - zstd availability
   - gitleaks install artifact selection by OS/arch
   - compiler/toolchain activation
2. Replace inline platform branching with helper scripts if the YAML becomes hard to read.
3. Ensure every `shell:` is explicit where Windows needs PowerShell or MSYS2 bash.
4. Partition cache keys by OS/arch/runner already; preserve that behavior.

**Preemptive fixes to include here:**
- stop assuming `apt-get` or `brew` exists
- stop assuming Linux tarball names for tools
- stop assuming `/opt/.../activate`
- stop assuming `update-alternatives`

**Verification:**
- read-through audit shows every composite-action step has a Windows path or a deliberate Windows skip
- no remaining unconditional `apt-get`, `brew`, `update-alternatives`, or Linux-only tarball reference in those two actions

**Commit point:**
- `ci: add Windows branches to shared runner setup actions`

---

### Phase 2: add Windows-aware repo build entrypoints before workflows — DONE

**Objective:** Create stable `just`/script entrypoints for Windows so workflows can call them the same way macOS/Linux workflows do.

**Files:**
- Modify: `justfile`
- Modify: `contrib/fd-build-lib.sh`
- Modify: `contrib/fd-tk-libs.sh`
- Create: `contrib/fd-build-windows.sh`
- Possibly create: `contrib/fd-build-windows.ps1`

**Work:**
1. Add explicit public recipes analogous to macOS ones, e.g.:
   - `build-fd-windows-x86`
   - `build-fd-windows-arm`
2. Decide how these recipes invoke a **native Windows** toolchain and shell environment on the runner.
3. Teach `fd-tk-libs.sh` how to select the right make/tool path on Windows.
4. Normalize path/tool resolution behind helpers, not inline special cases in workflows.

**Preemptive fixes to include here:**
- no hard dependency on `RUNNER_OS=macOS` special case only
- no unguarded Unix path assumptions in make discovery
- no assumption that bash path translation is unnecessary

**Verification:**
- `just --list` shows the new Windows recipes
- script inspection confirms workflows can call one recipe per runner/arch instead of inlining commands

**Commit point:**
- `build: add Windows FD build entrypoints`

---

### Phase 3: implement Windows C ABI shim support before trying to link Zig harness — DONE

**Objective:** Remove the obvious Windows compile blockers in C shims and OS helpers first.

**Files:**
- Modify: `src/tickoni/c_abi/shim/os.c`
- Modify: `src/tickoni/c_abi/shim/sandbox.c`
- Possibly modify: `src/tickoni/util/os_api.zig`
- Possibly modify: `src/tickoni/c_abi/boot.zig`

**Work:**
1. Add a real Windows branch in `os.c` for:
   - monotonic time
   - sleep
   - self executable path
   - parent pid behavior (or explicit unsupported return)
   - process termination
   - write-to-fd/handle behavior or explicit abstraction split
2. Make the non-Linux sandbox fallback genuinely Windows-safe.
3. If `os_api.zig` is too POSIX-shaped, replace POSIX types with Tickoni-local platform-neutral aliases.
4. Make Windows “unsupported direct source build” / “retail only” behavior explicit where needed instead of accidental fallback.

**Preemptive fixes to include here:**
- remove reliance on `<unistd.h>` in Windows path
- avoid leaking Win32 details up into application code; keep them in shims

**Verification:**
- every shim file compiles conceptually for Windows on inspection
- no remaining Unix-only include/function in the Windows branch

**Commit point:**
- `runtime: add Windows OS shim support for build path`

---

### Phase 4: abstract supervisor process control away from POSIX-only APIs

**Objective:** Fix the most obvious Zig-side Windows blockers before CI shows compile failures in `tickoni`.

**Files:**
- Modify: `src/app/tickoni/supervisor.zig`
- Modify: `src/tickoni/util/os_api.zig`
- Possibly create: `src/tickoni/util/process_api.zig`

**Work:**
1. Isolate:
   - `waitpid`
   - `std.posix.W.*`
   - `SIGKILL`
2. Move them behind a Tickoni platform abstraction.
3. Decide Windows semantics for stale child handling, forced stop, and reap status.
4. Model process lifecycle in platform-neutral terms rather than Unix signal vocabulary.
   - Do **not** add helpers like `isSigkill()` as the main abstraction.
   - Prefer a neutral result shape such as:
     - exited normally
     - crashed
     - force-terminated
     - stale
     - unknown
   - Linux may implement force termination with `SIGKILL`.
   - Windows should implement the same semantic using native process APIs.
5. If process-mode supervisor is not supported on first Windows build PR, gate it at compile/runtime explicitly instead of leaving implicit POSIX references in shared code.

**Preemptive fixes to include here:**
- do not branch inline throughout supervisor logic
- create a narrow status/terminate/reap abstraction that Linux/macOS/Windows can each satisfy
- keep raw Unix wait-status decoding inside the platform layer, not in `supervisor.zig`

**Verification:**
- no direct `std.posix.W.*`, `waitpid`, or `SIGKILL` references remain in cross-platform supervisor code without a platform abstraction
- the abstraction speaks in semantic process outcomes, not Unix signal names

**Commit point:**
- `runtime: hide supervisor process control behind platform API`

---

### Phase 5: wire Windows build jobs into CI only after entrypoints and shims exist

**Objective:** Add the actual GitHub Actions jobs after the build and portability substrate is ready.

**Files:**
- Modify: `.github/workflows/build-fd.yml`
- Modify: `.github/workflows/build-tk.yml`
- Modify: `doc/execution/ci.md`

**Work:**
1. Add Windows x86_64 + ARM64 jobs to `build-fd.yml`.
2. Add matching Windows x86_64 + ARM64 jobs to `build-tk.yml`.
3. Make the jobs call the new repo entrypoints (`just build-fd-windows-*`, `just build-tk` after FD libs exist), not bespoke workflow commands.
4. Keep the same detect-changes model unless a Windows-specific path addition is required.
5. Add timeouts and shell choice explicitly.

**Runner/job shape to target:**
- `runs-on: windows-2025`
- `runs-on: windows-11-arm`
- one engine job per runner
- one harness job per runner

**Verification:**
- each workflow job calls an existing `just` recipe or shared action
- `ci.md` workflow table and build section mention the new Windows lanes
- no workflow references a non-existent recipe

**Commit point:**
- `ci: add Windows build lanes for engine and harness`

---

### Phase 6: pre-CI verification sweep before opening the PR

**Objective:** Catch the obvious repo-level mismatches locally before relying on GitHub Actions.

**Files:**
- Create: `/tmp/hermes-verify-win-ci-XXXX.sh` (temporary)
- Optional create: `/tmp/hermes-verify-win-ci-XXXX.py`

**Checks to include:**
1. workflow recipe audit:
   - every `just <recipe>` referenced by modified workflows exists in `justfile`
2. shared-action audit:
   - every unconditional package-manager/tool install step has a Windows path or a deliberate skip
3. grep/search audit for remaining obvious blockers in changed files:
   - unconditional `apt-get`
   - unconditional `brew`
   - unconditional `update-alternatives`
   - unconditional `waitpid`
   - unconditional `std.posix.W.`
   - unconditional `SIGKILL`
4. if practical, local compile-only probes using Zig target selection for Windows to surface parser/import/type issues before CI

**Important:** report this as **ad-hoc verification**, not suite green, unless canonical Windows jobs have actually passed in GitHub Actions.

**Commit point:**
- no commit; this is the verification gate before PR/CI

---

## File-level task list

### Task 1: Document the Windows CI contract — DONE
**Files:**
- `doc/execution/V2.22/windows-build-ci.md`
- `doc/execution/ci.md`

### Task 2: Add Windows support branches to shared actions — DONE
**Files:**
- `.github/actions/setup-public-gh-runner/action.yml`
- `.github/actions/deps/action.yml`
- optional helper scripts under `.github/actions/**/scripts/`

### Task 3: Add repo-facing Windows build recipes — DONE
**Files:**
- `justfile`
- `contrib/fd-build-windows.sh`
- `contrib/fd-build-lib.sh`
- `contrib/fd-tk-libs.sh`

### Task 4: Fix C shims for Windows — DONE
**Files:**
- `src/tickoni/c_abi/shim/os.c`
- `src/tickoni/c_abi/shim/sandbox.c`
- `src/tickoni/c_abi/boot.zig`
- `src/tickoni/util/os_api.zig`

### Task 5: Fix supervisor/process portability
**Files:**
- `src/app/tickoni/supervisor.zig`
- optional `src/tickoni/util/process_api.zig`

### Task 6: Add Windows workflow jobs
**Files:**
- `.github/workflows/build-fd.yml`
- `.github/workflows/build-tk.yml`
- `doc/execution/ci.md`

### Task 7: Run ad-hoc verification and then CI
**Files:**
- temp verifier under `/tmp`

---

## Explicit pitfalls to avoid

1. **Do not** add Windows workflow YAML first and hope CI tells us the rest.
2. **Do not** hardcode Windows logic inline in four workflow jobs; put it in shared actions/recipes.
3. **Do not** leak OS branches into app/runtime logic when a shim/helper can own the divergence.
4. **Do not** weaken shared tests to hide Windows differences; keep unsupported behavior explicit.
5. **Do not** claim native Windows FD support until the native Windows toolchain/build path is actually implemented and verified.
6. **Do not** keep tool installers Linux-only (for example gitleaks artifact naming).
7. **Do not** make Windows CI depend on hand-edited PATH state without encoding it in actions/scripts.

---

## Suggested PR split

### PR 1 — substrate only
- shared actions gain Windows branches
- just/build scripts gain Windows entrypoints
- no workflow jobs yet

### PR 2 — portability fixes
- C shim + supervisor/platform abstraction changes
- compile-only local verification

### PR 3 — workflow wiring
- add `windows-2025` and `windows-11-arm` jobs to `build-fd.yml` / `build-tk.yml`
- run first CI

This split is safer than one giant PR because it makes failures attributable.

---

## First implementation step I recommend

Start with **Phase 0 + Phase 1** only:
1. freeze the Windows CI contract
2. make `setup-public-gh-runner` and `deps` Windows-aware

Reason: that work is unavoidable no matter which final Windows build substrate you choose, and it removes the biggest workflow-level unknowns before touching runtime code.

---

## Definition of done for this plan

This plan is complete when an implementer can answer, before touching CI:
- which Windows jobs will exist
- which repo entrypoints they call
- which files currently block Windows builds
- which blockers must be fixed before the first CI attempt
- how success will be verified without pretending the first PR is already full Windows support
