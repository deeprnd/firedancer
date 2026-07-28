# Windows Build CI Contract

This document freezes the first-pass Windows build CI contract for V2.22.

---

## Goal

Add native Windows build lanes on GitHub-hosted runners for both the scoped Firedancer engine subset and the Tickoni harness, using the same shared repo entrypoints and shared GitHub Actions layers already used by Linux and macOS.

This contract is for **build CI only**. It does not claim full Windows runtime parity.

---

## Runner contract

The first-pass Windows build lanes must run natively on these GitHub-hosted runners:

| Runner label | Architecture | Mode |
| --- | --- | --- |
| `windows-2025` | x86_64 | native Windows |
| `windows-11-arm` | ARM64 | native Windows |

WSL2, containers, and VMs are not the official first-pass support path and must not be presented as the repo's Windows CI strategy.

---

## Jobs to add

The first PR series must land these four jobs:

| Workflow | Job | Runner | Entrypoint |
| --- | --- | --- | --- |
| `build-fd.yml` | `Engine Build / Windows 2025` | `windows-2025` | `just build-fd-windows-x86` |
| `build-fd.yml` | `Engine Build / Windows 11 ARM` | `windows-11-arm` | `just build-fd-windows-arm` |
| `build-tk.yml` | `Harness Build / Windows 2025` | `windows-2025` | `just build-tk` after shared FD libs are built |
| `build-tk.yml` | `Harness Build / Windows 11 ARM` | `windows-11-arm` | `just build-tk` after shared FD libs are built |

Each workflow job must call existing repo entrypoints or shared composite actions. No job may inline a bespoke one-off Windows build sequence.

---

## What these lanes prove

The first-pass Windows lanes prove only that:

1. shared runner bootstrap actions can select a native Windows setup path,
2. shared FD/Tickoni build entrypoints can execute on native Windows runners,
3. the scoped Firedancer subset needed by Tickoni can build on Windows x86_64 and ARM64,
4. `tickoni` can compile on those same runners once the required shims and process abstractions are in place.

They do **not** prove full retail runtime support.

---

## Explicit non-goals for the first PR

The first Windows build CI PR must not claim or add:

- Windows sanitizer lanes
- Windows seccomp or sandbox validation
- Windows Firedancer end-to-end/runtime lanes
- replay-proof/runtime parity claims
- Linux shared-memory topology validation
- live execution support
- VM/WSL/container fallback lanes as the official support path

Unsupported Windows runtime behavior must stay explicit in docs and code gates.

---

## Required implementation constraints

1. Keep OS divergence behind shared actions, scripts, shims, or platform APIs.
2. Do not scatter inline Windows conditionals through product logic when a platform layer can own the difference.
3. Replace macOS-only tool lookup special cases with general cross-platform tool resolution.
4. Abstract process supervision around semantic outcomes rather than raw POSIX wait status details.

---

## CI doc note

`doc/execution/ci.md` should list these as active native Windows build lanes and point back to this frozen V2.22 contract for scope and non-goals.
