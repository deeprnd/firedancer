# V1.21.S2.T2 — Linux-only Assumptions Classification

**Epic:** V1.21 Cross-Platform Retail Runtime Support
**Story:** V1.21.S2 Build scope filter for retail targets
**Task:** V1.21.S2.T2 Classify each Linux-only assumption

## Summary

351 unique files across 15 Linux-specific assumption categories. Each assumption is classified as:

- **full-runtime only** — Linux subsystem with no reasonable retail substitute; retail demos must exclude or stub
- **retail-runtime substitute** — Linux primitive that can be replaced with a portable equivalent (heap-backed queues, mock sandbox, portable hashing)
- **packaging precondition** — Linux host setup required for full runtime but not for retail demos (hugepages, sysctl, hugetlbfs mounts)
- **unsupported** — No viable substitute; retail builds must explicitly exclude any reference to these
- **decision-needed** — Classification requires a product-level decision

## Classification Table

| # | Assumption | Files | Scope | Classification | Retail path |
|---|-----------|-------|-------|---------------|-------------|
| 1 | hugetlbfs / hugepages | 15 | build, test, runtime, docs | **full-runtime only** | Retail builds must exclude hugetlbfs; use heap-backed allocations for demo mode |
| 2 | /proc access (setgroups, sysctl, pagemap, nr_hugepages) | 20 | build, test, runtime | **full-runtime only** | Retail builds must stub /proc reads; runtime detects absence and fails gracefully for full mode, uses safe defaults for retail |
| 3 | CPU affinity (sched_setaffinity, pthread_setaffinity, cpu_set) | 96 | test, topology, sandboxing | **retail-runtime substitute** | Retail uses a no-op or thread-local counter; topology docs note reduced core pinning |
| 4 | NUMA awareness (fd_shmem_numa, fd_shmem_cpu, NUMA placement) | 97 | build, test, shared-memory, sandboxing | **retail-runtime substitute** | Retail falls back to single-node (node 0); topology uses default NUMA placement on Linux |
| 5 | memlock / RLIMIT_MEMLOCK / prlimit | 15 | build, test, sandboxing, shared-memory | **full-runtime only** | Retail builds must exclude mlock-based workspace setup; use process-local heap memory for paper demos |
| 6 | mmap / MAP_SHARED for shared memory | 10 | build, test, runtime | **retail-runtime substitute** | Retail uses thread-safe heap queues (already done in Phase 0 payment pipeline per S4 proposal) |
| 7 | seccomp / Landlock / user namespaces / prctl | 118 | build, test, sandboxing | **full-runtime only** | Retail uses a "no sandbox" or "restricted sandbox" mode; seccomp profiles are Linux-specific |
| 8 | XDP / AF_XDP / xsk_ring | 45 | build, test, runtime | **full-runtime only** | Retail excludes network tile; networking is full-Linux-only |
| 9 | io_uring (fd_io_uring, fd_vinyl_io) | 9 | build, test, runtime | **full-runtime only** | Retail falls back to blocking I/O or epoll |
| 10 | netlink / rtnetlink (AF_NETLINK, RTM_) | 51 | build, test, config | **retail-runtime substitute** | Retail uses a no-op netlink stub for config; no real network tuning |
| 11 | eBPF / SBPF (fd_sbpf_loader, bpf_prog, bpf_obj) | 25 | build, test, runtime | **retail-runtime substitute** | SBPF loader is portable (already compiles on non-Linux in some contexts); keep but test carefully |
| 12 | SSE / AVX / AVX512 compile-time feature flags | 6 | build | **decision-needed** | x86-64 is required for full-runtime; retail targets may relax or use portable fallbacks |
| 13 | x86_64 TSO memory model | 18 | build, runtime | **full-runtime only** | x86-64 TSO is the baseline; ARM requires separate memory ordering treatment |
| 14 | Linux /proc/self/pagemap (sandbox test) | 20 | build, test, sandboxing | **full-runtime only** | Retail excludes /proc/self/pagemap sandbox checks |
| 15 | fdctl command recipes (fd_shmem_ctl, fd_wksp_ctl, fd_fseq_ctl) | 8 | docs, build | **packaging precondition** | Retail builds exclude fdctl; Tickoni CLI replaces these for retail demos |
| 16 | justfile Linux ops (sudo, nproc, prlimit, hugepages, /sys, /proc) | 15 | build, test | **packaging precondition** | Retail justfile targets use portable alternatives or are excluded |
| 17 | Linux-only build profiles (linux_gcc_icelake, linux_clang_zen2, etc.) | 2 | build | **packaging precondition** | Retail targets use a generic gcc/clang profile without Linux-specific CPU feature detection |
| 18 | Native compiler feature detection (native_config.sh) | 1 | build | **decision-needed** | retail targets need a portable feature detection path or explicit compile-time flags |
| 19 | signal handling (SIGRT, SIG_IGN, signal(), raise()) | 8 | build, runtime, test | **retail-runtime substitute** | Retail uses portable signal handling; some Linux-specific signal masks are no-ops |
| 20 | fd_shmem_admin mlock-based workspace setup | 3 | build, runtime | **full-runtime only** | Retail builds must exclude the mlock path; use heap-backed workspaces for demos |
| 21 | fd_topo_mlock (topology-level memory locking) | 4 | build, runtime | **full-runtime only** | Retail topologies must skip mlock; topology docs must note degraded isolation |
| 22 | fd_cap_chk (Linux capability checks) | 2 | build, runtime | **full-runtime only** | Retail builds exclude capability enforcement; report "no cap enforcement" in doctor output |
| 23 | fd_keyload mlock on private key pages | 1 | build, runtime | **full-runtime only** | Retail must exclude key mlock; keys in retail demo mode are synthetic/no-op |
| 24 | fd_io_uring setup (fd_io_uring_setup.c) | 3 | build, runtime | **full-runtime only** | Retail excludes io_uring; use standard POSIX I/O or blocking I/O |
| 25 | Vinyl I/O layer (fd_vinyl_io.h) | 1 | build | **decision-needed** | Check if fd_vinyl_io is used by retail targets; if yes, provide a portable I/O backend |

## Classification Logic

### Why "full-runtime only" means what it means

These are subsystems that depend on Linux kernel primitives with no portable equivalent at the C level. Retiring them from retail builds is mandatory:

- **hugetlbfs** — Linux kernel filesystem; no macOS/Windows alternative at the OS level
- **mlock** — POSIX but effectively Linux-only in Firedancer's usage pattern (fd_numa_mlock wraps SYS_mlock syscall directly)
- **seccomp/Landlock** — Linux-only security subsystems
- **XDP/AF_XDP** — Linux kernel networking subsystem
- **io_uring** — Linux kernel I/O subsystem
- **/proc access** — Linux-specific virtual filesystem for kernel introspection

### Why "retail-runtime substitute" means what it means

These use Linux APIs but have clear portable replacements or no-op stubs:

- **CPU affinity** — sched_setaffinity → no-op (threads run on whatever cores the scheduler assigns)
- **NUMA** — fd_shmem_numa → single-node allocation (already the default when NUMA is absent)
- **netlink** — rtnetlink → no-op stub (network config is pre-set for retail demos)
- **eBPF/SBPF** — SBPF loader is actually portable; already used in Firedancer's Solana validator on non-Linux contexts

### Why "packaging precondition" means what it means

These affect the build system and developer workflow but don't affect the retail binary itself:

- **justfile Linux ops** — sudo/nproc/prlimit are build/test only; the retail binary doesn't need them
- **Linux build profiles** — machine/ profiles are build-time only; retail targets can use generic ones
- **fdctl command recipes** — admin tools for full runtime, not needed in retail

### Why "decision-needed" needs product decisions

These affect both build and runtime in ways that need explicit choices:

- **SSE/AVX feature flags** — Are retail targets restricted to x86-64 baseline, or do we allow portable fallbacks?
- **native_config.sh** — How do retail targets detect available CPU features without native detection?
- **fd_vinyl_io** — Unknown usage pattern; need to trace actual callers before classifying

## Retail-Build Exclusion Rules (Draft)

Retail build targets must **never compile or link** these files:

1. All files in `src/util/io_uring/` (io_uring is Linux-only)
2. All files in `src/waltz/xdp/` (XDP/AF_XDP is Linux-only)
3. `src/util/shmem/fd_numa_linux.c` (Linux NUMA + mlock)
4. `src/util/shmem/fd_io_uring_setup.c` (already in 1, listed for completeness)
5. `src/util/sandbox/fd_sandbox.c` (seccomp/Landlock/userns — Linux-only)
6. Any file that directly calls `SYS_mlock`, `SYS_landlock_create_ruleset`, `SYS_landlock_restrict_self`, `SYS_io_uring_setup`

Retail build targets **may compile** these files with portable stubs:

1. `src/util/shmem/fd_numa_stub.c` — already exists; used for non-Linux builds
2. `src/ballet/sbpf/` — portable SBPF loader
3. `src/util/io/fd_io.c` — portable I/O (not io_uring)
4. Files that use CPU affinity — no-op implementation for retail

## Key References

- `mac_windows_consumer_runtime_proposal.md` — existing proposal for Mac/Win support
- `tickoni_fd.mk` — current build scope filter for Firedancer libs
- `native_config.sh` — Linux-only feature detection
- `fd_sandbox.c` — full Linux sandbox implementation
- `fd_numa_linux.c` vs `fd_numa_stub.c` — pattern for Linux vs portable
