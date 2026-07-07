# V1.21.S2.T5 — Package Inclusion Rules and Coverage Reporting

**Epic:** V1.21 Cross-Platform Retail Runtime Support
**Story:** V1.21.S2 Build scope filter for retail targets
**Task:** V1.21.S2.T5 Define package inclusion rules and coverage reporting

## Summary

Consumer packages (macOS/Windows retail builds) must include only Tickoni-owned
code and the exact Firedancer substrate Tickoni reuses. No Solana validator
tiles, RPC schemas, or unrelated Firedancer source may ship in retail artifacts.
This task defines the inclusion rules, the exclusion list, and the coverage
reporting mechanism so that reviewers can verify package contents.

## Inclusion Rules

### Always Include

| Item | Reason |
|------|--------|
| Tickoni Zig runtime (`src/tickoni/**/*.zig`, ~125 files) | Core Tickoni framework |
| Tickoni C ABI shims (`src/tickoni/c_abi/shim/*.c`) | Bridge between Zig and Firedancer libs |
| `libfd_tango.a` | Inter-tile queues (dcache, fseq, mcache, cnc, fctl) |
| `libfd_util.a` | Utility functions, RNG, workspace allocation |
| `libfd_ballet.a` | Protobuf encoding/tokenization |
| `libfd_disco.a` | Tile topology and metrics |
| `libfd_waltz.a` | HTTP server (POSIX) |

### Always Exclude

| Item | Reason |
|------|--------|
| Solana validator tiles (`fd_sign_tile`, `fd_shred_tile`, `fd_quic_tile`, `fd_pack_tile`, `fd_verify_tile`, `fd_repair_tile`, `fd_replay_tile`, `fd_execle_tile`, `fd_execrp_tile`, etc.) | Not used by Tickoni; Solana-specific |
| RPC schemas (`fd_rpc_tile`, `fd_solcap_tile`, `fd_genesis_tile`) | Not used by Tickoni |
| Unit tests (`build/*/unit-test/*`, `build/*/fuzz-test/*`) | Not shipped in retail artifacts |
| Binaries (`build/*/bin/*` — `fd_blockstore2shredcap`, `fd_wksp_ctl`, etc.) | Not shipped in retail artifacts |
| Fuzz test sources | Not shipped in retail artifacts |
| RocksDB, io_uring, XDP/AF_XDP, seccomp/Landlock tooling | Linux-only subsystems |
| Test fixtures (`test_*` binaries) | Not shipped in retail artifacts |

## Coverage Reporting

A build-scope manifest must be produced at build time that lists:

1. **Compiled sources** — every `.c`/`.cpp` file compiled into the retail Firedancer libraries
2. **Included headers** — every header from the Firedancer tree consumed by Tickoni shims
3. **Excluded source sets** — directories/files known to be unnecessary, with justification
4. **Archive contents** — symbol summary of each `.a` file (count of exported symbols)
5. **Net package size** — total bytes of retail artifacts

### Manifest Format (JSON)

```json
{
  "version": "1.0",
  "target": "macos-retail | windows-retail | linux-full-runtime",
  "compiled_sources": [ ... ],
  "included_headers": [ ... ],
  "excluded_source_sets": [
    {
      "path": "src/disco/bundle",
      "reason": "Solana validator bundle — not used by Tickoni"
    },
    ...
  ],
  "archive_sizes": {
    "libfd_tango.a": 2204912,
    "libfd_util.a": 11715946,
    "libfd_ballet.a": 34756412,
    "libfd_disco.a": 86654610,
    "libfd_waltz.a": 12597132
  },
  "total_package_bytes": 147929002,
  "tickoni_source_bytes": null
}
```

### How to Generate

A `just` recipe or script that:
- Calls `ar t` on each `.a` file to list object members
- Traces each shim's `#include` directives to Firedancer headers
- Produces the JSON manifest at `build/<bdir>/s2-inclusion-manifest.json`
- Can be called from CI and from the retail build pipeline

## Coverage Metrics

- **Reuse ratio** = (compiled Firedancer source lines) / (total Firedancer source lines). Target: <5% for retail builds.
- **Unnecessary sources excluded** = all files in the exclusion list above are absent from compiled set.
- **Solana-only tiles excluded** = zero symbols from Solana validator tiles in any shipped archive.

## Acceptance Criteria

- [ ] Given a retail build, when the inclusion manifest is generated, then only the five required Firedancer archives and their source members are listed as compiled.
- [ ] Given the inclusion manifest, when a reviewer checks it, then no Solana validator tiles, RPC schemas, or unrelated Firedancer source appear in the compiled list.
- [ ] Given a retail package, when coverage is measured, then the reuse ratio is <5% and all exclusion list items are confirmed absent.

### Conditional Acceptance

**Financial capability and policy** — N/A. Package inclusion does not change policy.
**Audit and replay** — N/A. Build scope does not affect audit/replay.
**Runtime topology and tile ownership** — N/A. Package rules are build-level, not runtime topology.
**Model, tool, adapter, or execution boundary** — N/A. Build scope does not modify boundaries.
**CaseOps API or UI** — N/A. Story affects build, not API or UI.

### Quality Gate

- [ ] Inclusion rules and manifest format are defined before retail packaging begins.
- [ ] CI validates the manifest against the exclusion list on every retail build.
- [ ] Documentation and roadmap status are updated when inclusion rules change.

### Notes And Open Questions

- Should the manifest be shipped as part of the retail package for transparency, or kept in CI logs only?
- How granular should "excluded source sets" be — by directory, by file, or by symbol?
- Should Tickoni-owned source lines be included in the coverage report, or only Firedancer sources?
