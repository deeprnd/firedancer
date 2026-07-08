# V1.21.S2.T3 — Reusable Package Surface

**Epic:** V1.21 Cross-Platform Retail Runtime Support
**Story:** V1.21.S2 Build scope filter for retail targets
**Task:** V1.21.S2.T3 Define the reusable package surface

## Summary

Tickoni's C ABI shims depend on exactly **8 Firedancer headers**, traced from 8 shim files. This defines the minimal package surface — nothing else is required for Tickoni's runtime.

## Dependency Map (Header-Level)

### Shim → Firedancer Header → Library

| Shim file | Firedancer headers | Library |
|-----------|-------------------|---------|
| `util.c` | fd_util.h, fd_util_base.h | libfd_util.a |
| `ballet.c` | fd_pb_encode.h, fd_pb_tokenize.h | libfd_ballet.a |
| `tango.c` | fd_cnc.h, fd_dcache.h, fd_fctl.h, fd_fseq.h, fd_mcache.h, fd_rng.h, fd_tempo.h, fd_util.h | libfd_tango.a |
| `wksp.c` | fd_util.h, fd_wksp.h | libfd_util.a |
| `sandbox.c` | fd_sandbox.h, fd_util.h | libfd_util.a |
| `topob.c` | fd_cnc.h, fd_dcache.h, fd_fseq.h, fd_mcache.h, fd_metrics.h, fd_pod_format.h, fd_topob.h, fd_util.h | libfd_disco.a |
| `topo_run.c` | fd_topo.h, fd_util.h | libfd_disco.a |
| `tile_run.c` | fd_topo.h, fd_util.h | libfd_disco.a |

### Minimum Required Headers

For Tickoni's full runtime (Linux):

**libfd_util.a:** fd_util.h, fd_util_base.h, fd_rng.h, fd_wksp.h, fd_sandbox.h
**libfd_tango.a:** fd_cnc.h, fd_dcache.h, fd_fctl.h, fd_fseq.h, fd_mcache.h, fd_rng.h, fd_tempo.h
**libfd_disco.a:** fd_topo.h, fd_topob.h, fd_metrics.h, fd_pod_format.h
**libfd_ballet.a:** fd_pb_encode.h, fd_pb_tokenize.h

For retail runtime (no hugetlbfs, no mlock, no sandbox, no XDP, no io_uring):

**libfd_util.a:** fd_util.h, fd_util_base.h, fd_rng.h, fd_wksp.h (no fd_sandbox.h)
**libfd_tango.a:** fd_cnc.h, fd_dcache.h, fd_fctl.h, fd_fseq.h, fd_mcache.h, fd_rng.h, fd_tempo.h
**libfd_disco.a:** fd_topo.h, fd_topob.h, fd_metrics.h, fd_pod_format.h
**libfd_ballet.a:** fd_pb_encode.h, fd_pb_tokenize.h

### Removed: fd_sandbox.h, fd_wksp.h (mlock-dependent)

The retail build replaces sandbox.c with a no-op stub (retail sandbox is disabled). wksp.c needs a heap-backed workspace adapter instead of the mlock-dependent shared-memory path.

## Architecture Diagram

```
Zig runtime (src/tickoni/**/*.zig)
    │
    └── C ABI shims (src/tickoni/c_abi/shim/)
        ├── util.c     → libfd_util.a       (fd_util, fd_util_base, fd_rng)
        ├── wksp.c     → libfd_util.a       (fd_wksp) [retail: heap-backed adapter]
        ├── sandbox.c  → libfd_util.a       (fd_sandbox) [retail: stub]
        ├── tango.c    → libfd_tango.a      (fd_cnc, fd_dcache, fd_fctl, fd_fseq, fd_mcache, fd_rng, fd_tempo)
        ├── topob.c    → libfd_disco.a      (fd_topo, fd_topob, fd_metrics, fd_pod_format)
        ├── topo_run.c → libfd_disco.a      (fd_topo)
        ├── tile_run.c → libfd_disco.a      (fd_topo)
        └── ballet.c   → libfd_ballet.a     (fd_pb_encode, fd_pb_tokenize)
```

## Package Surface Definition

The **reusable package surface** for retail targets consists of:

1. **libfd_util.a** — utility functions, RNG, workspace allocation
2. **libfd_tango.a** — inter-tile queues (dcache, fseq, mcache, cnc, fctl)
3. **libfd_disco.a** — tile topology and metrics
4. **libfd_ballet.a** — protobuf encoding/tokenization
5. **src/tickoni/c_abi/shim/*.c** — Zig ↔ Firedancer C ABI bridge
6. **src/tickoni/**/*.zig** — Tickoni's own Zig runtime (125 files)

## Files NOT in the Package Surface

These Firedancer modules compile under tickoni_fd scope but Tickoni does not reference:

**libfd_util.a (unused):** fd_io.c, fd_io_uring/*, fd_numa_linux.c, fd_shmem_admin.c, fd_shmem_user.c, fd_sandbox.c (direct), fd_env_strip.c, fd_spin.c, fd_align.c, fd_checkpt.c, fd_archive.c, fd_bits.c, fd_bytes.c, fd_hash.c, fd_log.c, fd_mem.c, fd_pod.c, fd_scratch.c, fd_stxt.c, fd_template.c, fd_tile.c, fd_ts.c, fd_winch.c, etc.

**libfd_tango.c (unused):** src/tango/Local.mk includes files beyond the 8 headers Tickoni actually needs

**libfd_disco.a (unused):** Most of disco/, except fd_topo.h, fd_topob.h, fd_metrics.h, fd_pod_format.h

**libfd_ballet.a (unused):** All of ballet/ except fd_pb_encode.h and fd_pb_tokenize.h

**libfd_waltz.a:** Not used by any Tickoni shim

## Retail Package Adjustments

Retail must exclude or replace:

| Library | Exclude | Replace |
|---------|---------|---------|
| libfd_util.a | fd_sandbox.c (seccomp/Landlock) | retail_sandbox.c stub |
| libfd_util.a | fd_numa_linux.c (mlock via SYS_mlock) | fd_numa_stub.c (already exists) |
| libfd_util.a | fd_shmem_admin.c (mlock-based workspace) | retail_wksp.c (heap-backed) |
| libfd_util.a | fd_shmem_user.c (mlock) | retail_wksp.c (heap-backed) |
| libfd_io | fd_io_uring/* (io_uring) | retail_io.c (POSIX blocking I/O) |
| libfd_waltz.a | fd_xsk.c, fd_xdp_tile.c (XDP/AF_XDP) | Not linked |
