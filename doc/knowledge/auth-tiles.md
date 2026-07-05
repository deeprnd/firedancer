# Tickoni Tile Authentication and Key Management

## Overview

Each Firedancer tile has two optional keyswitch objects in its topology descriptor:
`id_keyswitch_obj_id` and `av_keyswitch_obj_id`. When these are set to `ULONG_MAX` (the default),
no keyswitch shared memory is allocated and the tile never needs to rotate keys at runtime.

For Tickoni, the default `ULONG_MAX` (pass 0 for `uses_id_keyswitch` and `uses_av_keyswitch`
in `fd_topob_tile()`) is the correct starting point. Phase 0 tiles have no runtime auth
rotation requirements. This document explains what keyswitches are, what the state machine does,
and when Tickoni might want to enable them.

## The Keyswitch Object

### Structure

`fd_keyswitch_t` is a 128-byte shared memory region (128-byte aligned) with the following
layout:

```
+--------+--------+--------+--------+-------------------+
|  magic | state  | result | param  |   bytes[64]       |
| 8 bytes| 8 bytes| 8 bytes| 8 bytes|   64 bytes        |
+--------+--------+--------+--------+-------------------+
```

- **magic** — `0xf17eda2c37830000UL` (version marker, `FD_KEYSWITCH_MAGIC`). Verified on join.
- **state** — Current state of the keyswitch state machine (see below).
- **result** — Set by the tile to indicate whether the key rotation succeeded or failed.
- **param** — Binary flag (0 or 1), set by the external process to convey additional info.
- **bytes[64]** — Holds the actual key material:
  - 32 bytes for identity key (the tile's signing/private key)
  - 64 bytes for identity + authority voter key pair

### State Machine

```
UNLOCKED (0) → LOCKED (1) → SWITCH_PENDING (2) → COMPLETED (5)
                                        ↘ FAILED (4)
```

The transitions are:

| Transition | Direction | Who triggers it | Meaning |
|---|---|---|---|
| UNLOCKED → LOCKED | Init | `fd_keyswitch_new()` | Object created, no key material loaded yet |
| LOCKED → SWITCH_PENDING | Rotate | External process | An admin/daemon writes a new key into `bytes[64]` and sets `state=SWITCH_PENDING` |
| SWITCH_PENDING → UNHALT_PENDING | Reconnect | External process | Tile is about to restart; new key is posted so the tile can pick it up on unhalting |
| SWITCH_PENDING → COMPLETED | Apply | Tile's run loop | Tile calls `fd_keyswitch_state_query()`, sees SWITCH_PENDING, reads new key from `bytes[64]`, applies it, sets `state=COMPLETED` |
| SWITCH_PENDING → FAILED | Reject | Tile's run loop | Tile detects the new key is invalid (bad format, wrong length, etc.) and sets `state=FAILED` |

The external process is OUT-OF-BAND from the tile's process. It can be:
- A separate admin CLI (e.g., `fdctl identity set`)
- A background daemon watching for new credentials
- A configuration management system

The tile's run loop calls `fd_keyswitch_state_query()` periodically (via
`FD_COMPILER_MFENCE()` barriers for volatile access) to check for state transitions.

### Two Objects Per Tile

Each tile gets two independent keyswitch objects:

1. **id_keyswitch** (identity key) — Used by tiles that sign or authenticate as a validator:
   `shred`, `gossip`, `gossvf`, `replay`, `repair`, `rserve`, `txsend`, `tower`,
   `sign`, `gui`, `guih`, `rpc`, `poh`, `pohh`, `bundle`, `event`, `dedup`.

2. **av_keyswitch** (authorized voter key) — Used only by tiles that vote:
   `sign` and `tower`. Holds the vote account key for signing voter transactions.

### How the External Process Writes a New Key

The set-identity commands (`fdctl identity set`, `add_authorized_voter`) find the
keyswitch object in the topology, map it into their address space via
`fd_topo_obj_laddr()`, write the new key bytes, and set the state. The tile then
detects the pending state and applies the key in its own run loop.

### How the Tile Reads the Key

A tile that uses a keyswitch:
1. Joins the keyswitch object: `fd_keyswitch_join(fd_topo_obj_laddr(topo, tile->id_keyswitch_obj_id))`
2. In its run loop, periodically checks: `fd_keyswitch_state_query(ctx->keyswitch)`
3. If the state is `SWITCH_PENDING`, the tile reads `bytes[64]`, applies the new key, and sets state to `COMPLETED`
4. If validation fails, it sets state to `FAILED`

## Solana Union Fields in `fd_topo_tile_t`

### The Union

`fd_topo_tile_t` has a large `union` containing Solana-specific configuration for each tile
type. Every union field is zeroed by `fd_topob_new()`'s `memset`. The union contains:

- **net** — Base network config (bind address, ports for shred, quic, gossip, repair)
- **xdp** — XDP/Umem/AF_XDP options (queue sizes, zero-copy, device names, routes, FIB, neighbors)
- **sock** — Raw socket options (send/receive buffer sizes)
- **netlink** — Netlink config (routes, FIB, neighbor table)
- **gossvf** — Gossip validator config (identity key path, entrypoints, boot timestamp)
- **gossip** — Gossip RPC config (identity key path, ports, hash validation)
- **quic** — QUIC transport config (idle timeout, retries, key log path, SSL)
- **verify** — Verification config (tcache depth)
- **dedup** — Dedup config (tcache depth)
- **bundle** — Bundle config (URL, identity key, SSL, action)
- **event** — Event config (URL, identity key, action)
- **pack** — Pack config (max pending tx, blocklist, schedule strategy)
- **pohh** — PoH hash config (identity key, bundle, plugins)
- **poh** — PoH config (identity key, execle count)
- **shred** — Shred config (identity key, ports, FEC, destination lists)
- **store** — Store config (blockstore disable slot)
- **sign** — Sign config (identity key, authorized voter paths)
- **gui** — GUI config (listen, voting, cluster, SSL, accdb)
- **rpc** — RPC config (listen, accdb, live slots)
- **metric** — Prometheus config (listen addr/port)
- **diag** — Diagnostics config (is voting flag)
- **replay** — Replay config (accdb, genesis, heap, features, snapshots)
- **execrp** — Execute rollback config (accdb, snapshots, syscall filters)
- **execle** — Execute leader config (accdb, live slots)
- **benchs/bencho** — Benchmark configs
- **benchg** — Bench generate config
- **repair/rserve** — Repair configs (identity key, shredb)
- **txsend** — Transaction send config (identity key)
- **pktgen** — Packet generator config (fake dst IP)
- **archiver** — Archiver config (rocksdb, capture paths)
- **backtest/forktest** — Backtest/fork test configs (ledger paths)
- **tower** — Tower config (accdb, voter paths, genesis hash)
- **accdb/resolv** — Account DB / DNS resolver configs
- **snapct/snapld/snapin/snapwr** — Snapshot configs (paths, servers, gossip)
- **ipecho** — IP echo config
- **solcap** — Solana cap (capture path, recent slots)

### Why These Are Zeroed and Safe

1. `fd_topob_new()` does `memset(topo, 0, sizeof(fd_topo_t))` — every union field is zeroed.
2. The launch path (`fd_topo_run_tile` in `fd_topo_run.c`) reads only:
   - `tile->name` — tile name string (non-Solana, generic)
   - `tile->kind_id` — tile instance ID within the name (generic)
   - `tile->cpu_idx` — CPU assignment (generic)
   - `tile->allow_shutdown` — graceful shutdown flag (generic)
   - `tile->metrics` — shared memory metrics pointer (generic)
3. None of these are union fields. Solana union fields are accessed by individual tiles
   via their own C code after `fd_topo_run_tile` has initialized them, but only Solana tiles
   (or tiles with those union fields populated) actually populate and read them.
4. `fd_topo_run_single_process()` reads `is_agave` (lines 326, 335) but Tickoni uses
   per-process `execve` mode, not single-process mode.

For Tickoni, passing `0` for all three Solana flags in `fd_topob_tile()`:
- `is_agave=0` — Tickoni does not run in Agave/single-process mode
- `uses_id_keyswitch=0` — no identity keyswitch object allocated (`id_keyswitch_obj_id=ULONG_MAX`)
- `uses_av_keyswitch=0` — no authorized voter keyswitch object allocated (`av_keyswitch_obj_id=ULONG_MAX`)

## Tickoni Application

### Phase 0: No Keyswitches

For Phase 0, pass `0` for both keyswitch flags:

```c
fd_topob_tile(topo, "tkings", tickoni_wksp, metrics_wksp, cpu_idx, 0, 0, 0);
fd_topob_tile(topo, "tknorm", tickoni_wksp, metrics_wksp, cpu_idx, 0, 0, 0);
fd_topob_tile(topo, "tkdedu", tickoni_wksp, metrics_wksp, cpu_idx, 0, 0, 0);
fd_topob_tile(topo, "tkpoly", tickoni_wksp, metrics_wksp, cpu_idx, 0, 0, 0);
fd_topob_tile(topo, "tkaudt", tickoni_wksp, metrics_wksp, cpu_idx, 0, 0, 0);
fd_topob_tile(topo, "tkmetr", tickoni_wksp, metrics_wksp, cpu_idx, 0, 0, 0);
fd_topob_tile(topo, "tkdiag", tickoni_wksp, metrics_wksp, cpu_idx, 0, 0, 0);
fd_topob_tile(topo, "tkdisp", tickoni_wksp, metrics_wksp, cpu_idx, 0, 0, 0);
```

No keyswitch shared memory objects are allocated. No runtime key rotation support.

### Future: Runtime Auth Rotation

If a Tickoni tile needs runtime auth rotation (e.g., an adapter that rotates GCP/GCS
OAuth tokens, an LLM tile that rotates API keys, or a compliance tile that rotates
AWS credentials), enable keyswitch for that tile:

```c
// Tile that needs runtime auth rotation
fd_topob_tile(topo, "tkadpt", tickoni_wksp, metrics_wksp, cpu_idx, 0, 1, 0);
// 0 = is_agave (no)
// 1 = uses_id_keyswitch (yes — for auth token refresh)
// 0 = uses_av_keyswitch (no — no voting)
```

The `bytes[64]` could then hold:
- 32 bytes: current auth token or credential handle
- 64 bytes: if a tile needs two secrets (e.g., primary + fallback, or client id + client secret)

The state machine would work the same:
1. Admin/daemon writes new credential into `bytes[64]` + sets `state=SWITCH_PENDING`
2. Tile's run loop detects `SWITCH_PENDING`, validates the new credential, applies it
3. Tile sets state to `COMPLETED` or `FAILED`

### Solana Union Fields for Tickoni Tiles

For Phase 0, Tickoni tiles use NONE of the Solana union fields. The union remains fully
zeroed. Future Tickoni tiles that need network config could potentially reuse the `net`
struct (bind address, ports) as a non-Solana base, but this would require careful
consideration of the Firedancer naming semantics (the union is discriminant-based — the
tile's C code reads from the union variant that matches its Solana tile identity).

**Recommendation:** Keep the union zeroed for Tickoni tiles. If a Tickoni tile needs network
configuration, it should use a separate Tickoni-owned config mechanism, not the Firedancer
Solana union, to avoid coupling Tickoni product concepts to Solana topology structure.

## Summary

| Feature | Phase 0 | Future |
|---|---|---|
| `is_agave` | 0 | 0 |
| `uses_id_keyswitch` | 0 | 1 (for auth rotation tiles) |
| `uses_av_keyswitch` | 0 | 0 (Tickoni has no voting) |
| Keyswitch objects | None allocated | Per-tile, as needed |
| Solana union fields | All zeroed | All zeroed (unless tile needs net config) |
| Runtime auth rotation | Not supported | Supported via keyswitch state machine |

The keyswitch mechanism is generic: a 128B shared memory region with a state machine
(`UNLOCKED→LOCKED→SWITCH_PENDING→COMPLETED/FAILED`) that allows an out-of-band process
to push new credential material to a running tile. Solana uses it for validator identity
and authority voter key rotation. Tickoni can reuse it for anything that needs runtime
credential refresh without restart.
