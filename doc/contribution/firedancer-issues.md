# Firedancer Open Issues
Total: 217 open issues

## #10105 — zig cc support
- **URL:** https://github.com/firedancer-io/firedancer/issues/10105
- **Created:** 2026-06-05 by @ripatel-fd
- **Updated:** 2026-06-05

See if we can support `zig cc` as a Make extra to do a libc-free / statically linked build

---

## #10058 — CodeQL tests failing due to included filter and stale expected files
- **URL:** https://github.com/firedancer-io/firedancer/issues/10058
- **Created:** 2026-06-03 by @deeprnd
- **Updated:** 2026-06-03

Running the CodeQL test suite fails with 4 of 9 tests failing. The failures have two distinct root causes.

### Issue 1: filter.qll excludes test database files (ReturnZeroForPointer, TrivialMemcpy, NonBinaryIsFunction)
contrib/codeql/lib/filter.qll restricts analysis to files whose relative path starts with src/:
```
predicate included(Location loc) {
  loc.getFile().getRelativePath().prefix(4) = "src/"
}
```
In codeqL database source files have paths relative to the test project directory, like ReturnZeroForPointer.c with no directory prefix. 
The included() predicate returns false for all of them, so every query that calls included() produces zero results in tests. Every // $ Alert annotation reports Missing result: Alert.

This was introduced in commit f31473534 ("codeql: only analyse src/"). The affected queries added included() in commit c5a16bb74 without updating the .expected files or accounting for the test database path structure.

Fix: extend included() to also pass files with no directory separator in their path

### Issue 1: stale .expected file (LargeMemset)

Commit 8e7394ed4 ("codeql: factor out memset related predicates") changed the alert message from a hardcoded "call to memset" to "call to " + memset.getName(). For fd_memset calls the message is now "call to fd_memset", but LargeMemset.expected still contains "call to memset" for those lines.

Fix: regenerate LargeMemset.expected.

### Reproduction

codeql pack install contrib/codeql/test
codeql test run contrib/codeql/test

---

## #10035 — Telemetry: network stack
- **URL:** https://github.com/firedancer-io/firedancer/issues/10035
- **Created:** 2026-06-02 by @ripatel-fd
- **Updated:** 2026-06-02
- **Assignees:** kbhargava-jump, jherrera-jump

The following info is useful to collect:
- name of main network interface
- device drivers (bonding, mlx5, etc)
- PCIe ID of physical interfaces
- XDP feature flags (driver mode? zero copy? native bond?) 
- kernel version
- number of routes
- number of neighbors

---

## #10004 — Get rid of orphan requests
- **URL:** https://github.com/firedancer-io/firedancer/issues/10004
- **Created:** 2026-05-29 by @emwang-jump
- **Updated:** 2026-06-04

just request forward highest window idx instead periodically?
potential hold for ag

---

## #9998 — Agree on conformant RPC log format between FD and Agave
- **URL:** https://github.com/firedancer-io/firedancer/issues/9998
- **Created:** 2026-05-29 by @mjain-jump
- **Updated:** 2026-05-29

Current Agave syscall + program deployment logs are difficult to match in FD. Simpler formats for different error messages should be discussed and upstreamed into Agave, and then differentially fuzzed for correctness.

---

## #9980 — Consider stdatomic for util/tmpl
- **URL:** https://github.com/firedancer-io/firedancer/issues/9980
- **Created:** 2026-05-28 by @ripatel-fd
- **Updated:** 2026-05-28
- **Labels:** Priority: Low

The util/tmpl files use 3 concurrency patterns:
- seqlock
- spin-lock based mutex/rwlock
- atomic CAS/fetch-add with acquire/release semantics

Currently, templates use a mix of x86-TSO via compiler fences and volatile memory accesses, and the ancient GCC `__sync` API. 

C11 atomics are a clean replacement for the above two, and have two benefits:
- Correctness: ThreadSanitizer support, easier to review (reasonably well specified memory models), which helps find issues in buggy users even if the template code itself is correct 
- portability to weak memory models (doesn't really matter)

The changes required are fairly minimal. 
- Users of the existing `FD_ATOMIC` API would switch to `__atomic` which is the same API with an additional memory ordering argument (relaxed, acquire/release, seq-cst) 
- Compiler fences are replaced with atomic_thread_fence or acquire/release accesses on synchronization words

Trivial for pool_para, map_chain_para, and map_slot_para

---

## #9968 — Use mTLS for events
- **URL:** https://github.com/firedancer-io/firedancer/issues/9968
- **Created:** 2026-05-27 by @ripatel-fd
- **Updated:** 2026-05-27
- **Labels:** Priority: Low

Use mutual TLS auth (ideally Raw Public Keys) instead of custom signing scheme to authenticate event clients for telemetry

---

## #9961 — tower tile differential fuzzer
- **URL:** https://github.com/firedancer-io/firedancer/issues/9961
- **Created:** 2026-05-27 by @lidatong
- **Updated:** 2026-05-27

---

## #9915 — restore: vote account validation
- **URL:** https://github.com/firedancer-io/firedancer/issues/9915
- **Created:** 2026-05-22 by @ripatel-fd
- **Updated:** 2026-05-22
- **Labels:** Priority: High

---

## #9914 — restore: comprehensive sysvar sanity checking
- **URL:** https://github.com/firedancer-io/firedancer/issues/9914
- **Created:** 2026-05-22 by @ripatel-fd
- **Updated:** 2026-05-24
- **Labels:** Priority: High

---

## #9912 — txsend: conn state machine polishing
- **URL:** https://github.com/firedancer-io/firedancer/issues/9912
- **Created:** 2026-05-22 by @ripatel-fd
- **Updated:** 2026-05-22
- **Labels:** Priority: High
- **Assignees:** ripatel-fd

---

## #9897 — 4.1 Cleaned Up Features
- **URL:** https://github.com/firedancer-io/firedancer/issues/9897
- **Created:** 2026-05-21 by @topointon-jump
- **Updated:** 2026-06-09

List of features cleaned up or removed in 4.1.

Reverted in 4.1:
- `enable_extend_program_checked`
- `enable_loader_v4`
- `stake_minimum_delegation_for_rewards`
- `vote_only_retransmitter_signed_fec_sets`

Cleaned up in 4.1:
- [ ] `increase_cpi_account_info_limit` @topointon-jump 
-  [ ] `provide_instruction_data_offset_in_vm_r2` @topointon-jump 
- [ ] `vote_state_v4` @0x0ece 
- [ ] `disable_deploy_of_alloc_free_syscall` @topointon-jump 
- [ ] `static_instruction_limit` @topointon-jump 
- [ ] `require_static_nonce_account` @kbhargava-jump 
- [ ] `enable_secp256r1_precompile` @0x0ece 
- [ ] `raise_account_cu_limit` @topointon-jump 
- [ ] `relax_intrabatch_account_locks` @topointon-jump 
- [x] `enforce_fixed_fec_set`

---

## #9843 — quic ui page
- **URL:** https://github.com/firedancer-io/firedancer/issues/9843
- **Created:** 2026-05-15 by @ripatel-fd
- **Updated:** 2026-05-15
- **Assignees:** ripatel-fd

---

## #9842 — Bug with increase_tx_account_lock_limit
- **URL:** https://github.com/firedancer-io/firedancer/issues/9842
- **Created:** 2026-05-15 by @ripatel-fd
- **Updated:** 2026-05-26

Firedancer does not support increase_tx_account_lock_limit yet due to a wrong hardcoded constant in BPF_LOADER_SERIALIZATION_FOOTPRINT

---

## #9838 — stem fragment torn reads (non-x86)
- **URL:** https://github.com/firedancer-io/firedancer/issues/9838
- **Created:** 2026-05-15 by @ripatel-fd
- **Updated:** 2026-05-22
- **Labels:** Priority: Low

fd_stem.c can yield torn reads / corrupt fields to during_frag, this affects net_shred and net_repair in particular. 

As a workaround, stem was changed to do 32-byte atomic descriptor load/store on x86.

This remains an issue on other platforms or x86 with AVX disabled.

---

## #9829 — yyjson instead of cJSON
- **URL:** https://github.com/firedancer-io/firedancer/issues/9829
- **Created:** 2026-05-15 by @ripatel-fd
- **Updated:** 2026-05-15

Much nicer API, faster, and supports operation without a heap allocator

---

## #9825 — Rewrite test_xdp_tile
- **URL:** https://github.com/firedancer-io/firedancer/issues/9825
- **Created:** 2026-05-14 by @ripatel-fd
- **Updated:** 2026-05-14

Needs to cover a lot more edge cases

---

## #9824 — Backport execrp features to execle
- **URL:** https://github.com/firedancer-io/firedancer/issues/9824
- **Created:** 2026-05-14 by @ripatel-fd
- **Updated:** 2026-05-15

The execle tile is missing several featuers that execrp has

---

## #9818 — Replay leader handoff aborts at a 1023-slot parent offset because the `USHORT_MAX` skipped-tick guard treats the slot-distance shred field as a tick count
- **URL:** https://github.com/firedancer-io/firedancer/issues/9818
- **Created:** 2026-05-14 by @ibhatt-jumptrading
- **Updated:** 2026-05-14

Full Firedancer's replay tile gates the fd_became_leader_t publication through maybe_become_leader(), which computes total_skipped_ticks = ticks_per_slot * (next_leader_slot - reset_slot) and aborts when ticks_per_slot + total_skipped_ticks > USHORT_MAX. The justifying comment cites the 2-byte parent_offset shred field — but parent_offset is a slot distance, not a tick count. At mainnet ticks_per_slot=64 the guard fires at the first slot gap of 1023 (64 × 1023 + 64 = 65536 > 65535), 64× earlier than the actual u16 parent_off ceiling. After a long skipped-slot recovery (≥ 1023 slots, ~6.8 minutes at 400 ms/slot — well within historical Solana mainnet outage durations), a Firedancer validator scheduled for the recovery leader slot aborts inside replay before publishing BECAME_LEADER. FD_LOG_ERR calls SYS_exit_group(1); the supervisor reaps the non-graceful exit and calls fd_sys_util_exit_group, terminating the entire validator process group. Tested target: https://github.com/firedancer-io/firedancer on main at c1417286c712de2227776459d406e2316782a781 (2026-05-01); same code is present on v1.0 (1561b4570a8a717aa640d9d75cea2ede7678744d) — only line numbers shift.

---

## #9817 — Replay tile slides its leader-start deadline forward on every `FD_TOWER_SIG_SLOT_IGNORED` because `process_tower_slot_done` recomputes `next_leader_tickcount` unconditionally even when `reset_slot` did not advance
- **URL:** https://github.com/firedancer-io/firedancer/issues/9817
- **Created:** 2026-05-14 by @ibhatt-jumptrading
- **Updated:** 2026-05-14

---

## #9799 — far repair stall
- **URL:** https://github.com/firedancer-io/firedancer/issues/9799
- **Created:** 2026-05-13 by @ripatel-fd
- **Updated:** 2026-05-13
- **Assignees:** emwang-jump

after repairing far for a while, replay gets stuck,
shred is backpressured on shred->repair link 
repair tile is 100% busy 

<img width="983" height="786" alt="Image" src="https://github.com/user-attachments/assets/99d81a48-b1b3-46c6-bc6d-0386b09ec8c1" />

will try to grab a stack trace

---

## #9786 — repair logs 32k lines per second when catching up far
- **URL:** https://github.com/firedancer-io/firedancer/issues/9786
- **Created:** 2026-05-12 by @ripatel-fd
- **Updated:** 2026-05-12
- **Assignees:** emwang-jump

```
💬 GOSSIP...... RX  23.0 Mbit TX 118.1 Kbit CRDS      8.6 K PEERS        691 BUSY  18% BACKP   0%
🧱 REPAIR...... RX     0 bits TX   1.3 Mbit REPAIR SLOT 407586307 (-375489) TURBINE SLOT 407961796
💥 REPLAY...... SLOT 407583899 (-377897) CU/s     17.1 M TPS          - SPS       13.0 LEADER IN never ROOT DIST 31 BANKS 147
📡 EVENT....... STATE disconnected QUEUE          0 SENT        0.0 /s ACKED        0.0 /s BW     0 bits in     0 bits out DROPS          0 FULL   0%
```

```
INFO    2026-05-12 22:39:04.603246419 GMT+00 3361355:3361403 ripatel:tsfra2-ossdev-firedancer50:21   fd1:[group]:repair:0 src/discof/forest/fd_forest.c(1444)[fd_forest_fec_clear]: [fd_forest_fec_clear] cleared slot 407949633 fec set 128
INFO    2026-05-12 22:39:04.603247929 GMT+00 3361353:3361406 ripatel:tsfra2-ossdev-firedancer50:16   fd1:[group]:shred:0 src/disco/shred/fd_fec_resolver.c(624)[fd_fec_resolver_add_shred]: Spilled from fec_resolver in-progress map 407949634 0, data_shreds_rcvd 20, parity_shreds_rcvd 0
```

```
$ tail -f /tmp/validator.log | pv -l >/dev/null
 971k 0:00:26 [32.6k/s] 
```

---

## #9780 — forward duplicate confirmations invalid
- **URL:** https://github.com/firedancer-io/firedancer/issues/9780
- **Created:** 2026-05-12 by @lidatong
- **Updated:** 2026-05-12

---

## #9768 — chaining to parent < root
- **URL:** https://github.com/firedancer-io/firedancer/issues/9768
- **Created:** 2026-05-12 by @lidatong
- **Updated:** 2026-05-12

/* we don't want to add a slot to the forest that chains to a slot
       older than root, to avoid filling forest up with junk.
       Especially if we are close to full and we are having trouble
       rooting, we can't rely on publishing to prune these useless
       subtrees. TODO: do the same with reasm/store/shred? */
    if( FD_UNLIKELY( shred->slot - shred->data.parent_off < fd_forest_root_slot( ctx->forest ) ) ) return;

---

## #9731 — Replay tile slides its leader-start deadline forward on every `FD_TOWER_SIG_SLOT_IGNORED` because `process_tower_slot_done` recomputes `next_leader_tickcount` unconditionally
- **URL:** https://github.com/firedancer-io/firedancer/issues/9731
- **Created:** 2026-05-11 by @ibhatt-jumptrading
- **Updated:** 2026-05-11

When the local tower publishes FD_TOWER_SIG_SLOT_IGNORED for a replayed minority-fork slot whose parent has been pruned from ghost (a routine async event during normal cluster forking), the replay tile synthesizes an fd_tower_slot_done_t reusing the current ctx->reset_slot and ctx->reset_block_id (no advance) and re-enters process_tower_slot_done. The handler unconditionally recomputes ctx->next_leader_tickcount = (next_leader_slot - reset_slot - 1) * slot_duration_ticks + fd_tickcount() with no guard on whether msg->reset_slot actually advanced. With unchanged inputs but a later fd_tickcount(), the deadline slides forward. At the original deadline maybe_become_leader returns 0 because now < ctx->next_leader_tickcount, and the leader bank is not published until the refreshed deadline. Multiple ignored messages compound the slide — each refreshes the deadline back to now + (next_leader_slot - reset_slot - 1) * slot_duration_ticks, so if ignored messages keep arriving faster than slot_duration_ticks apart (≈400 ms on mainnet), the deadline can be bumped indefinitely and the leader slot is fully starved. No malicious input is required: publish_slot_ignored fires on every replayed slot whose parent is no longer in ghost — a routine async-processing event during normal cluster forking when tower roots past a pruned sibling.

---

## #9726 — Log slow hugetlbfs steps
- **URL:** https://github.com/firedancer-io/firedancer/issues/9726
- **Created:** 2026-05-11 by @ripatel-fd
- **Updated:** 2026-05-11

If any of these steps takes longer than 100ms, log it:

```
hugetlbfs.c(82): RUN: `echo "203748" > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages`
hugetlbfs.c(114): RUN: `echo "203748" > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages`
hugetlbfs.c(161): RUN: `mkdir -p /mnt/.fd/.huge`
hugetlbfs.c(168): RUN: `mount -t hugetlbfs none /mnt/.fd/.huge -o pagesize=2097152,min_size=427290525696`
hugetlbfs.c(161): RUN: `mkdir -p /mnt/.fd/.gigantic`
hugetlbfs.c(168): RUN: `mount -t hugetlbfs none /mnt/.fd/.gigantic -o pagesize=1073741824,min_size=0`
```

---

## #9714 — quic: fd_quic_tls_hs_cache_evict does not issue conn_free callback
- **URL:** https://github.com/firedancer-io/firedancer/issues/9714
- **Created:** 2026-05-10 by @ripatel-fd
- **Updated:** 2026-05-10

---

## #9704 — runtime: hard forks not applied at runtime
- **URL:** https://github.com/firedancer-io/firedancer/issues/9704
- **Created:** 2026-05-09 by @ripatel-fd
- **Updated:** 2026-05-15
- **Labels:** Priority: Low

Firedancer only "mixes in" hard forks into bank hash on startup (after snapshot load), but not during runtime. 
This breaks startup from a snapshot with a hard fork scheduled in the future.

This is a very minor conformance issue. Scheduling "hard fork" entries in the future is something not typically done. 

(Reported by several ImmuneFi audit contest participants)

---

## #9695 — maybe become leader just checks the direct descendants of the reset slot and doesn't walk down the descendant tree
- **URL:** https://github.com/firedancer-io/firedancer/issues/9695
- **Created:** 2026-05-08 by @ibhatt-jumptrading
- **Updated:** 2026-05-12

agave has the same behavior here.

---

## #9694 — eqvoc: cross-FEC chained-Merkle duplicate proofs should not be accepted until validate_chained_block_id is active
- **URL:** https://github.com/firedancer-io/firedancer/issues/9694
- **Created:** 2026-05-08 by @emwang-jump
- **Updated:** 2026-05-08

agave will reject all these proofs, whereas fd will accept

---

## #9688 — replay: boot from genesis runs PoH twice
- **URL:** https://github.com/firedancer-io/firedancer/issues/9688
- **Created:** 2026-05-08 by @ripatel-fd
- **Updated:** 2026-05-08

once in `fd_runtime_read_genesis` and once in `init_after_snapshot`, seems like a conformance issue

---

## #9686 — h2: WINDOW_UPDATE frames can overflow tx_wnd
- **URL:** https://github.com/firedancer-io/firedancer/issues/9686
- **Created:** 2026-05-08 by @ripatel-fd
- **Updated:** 2026-05-08
- **Labels:** Priority: Low

tx_wnd can go out of bounds with crafted WINDOW_UPDATE frames, low severity

---

## #9685 — [quic] CID randomness is poor
- **URL:** https://github.com/firedancer-io/firedancer/issues/9685
- **Created:** 2026-05-08 by @ripatel-fd
- **Updated:** 2026-05-08

---

## #9674 — Default -ffast-math Reward Drift Causes EpochRewards Bank-Hash Divergence
- **URL:** https://github.com/firedancer-io/firedancer/issues/9674
- **Created:** 2026-05-08 by @ibhatt-jumptrading
- **Updated:** 2026-05-08

problematic path is not reachable with mainnet values

"This can never be true in current mainnet-beta conditions: foundation_term is 0.0 as already shown above and year is always > 0.0. Therefore year < inflation->foundation_term is ALWAYS false."

found with help from contest and @intrigus-lgtm

---

## #9671 — repair: check_confirmed OOB log
- **URL:** https://github.com/firedancer-io/firedancer/issues/9671
- **Created:** 2026-05-07 by @drubin-fd
- **Updated:** 2026-05-07

If a leader sends a lot of FEC sets (more than 32), an incorrect indexing into `merkle_roots` will OOB read past the 1024 elements it has.

---

## #9666 — hfork: Missing garbage collection of 0-vote blocks in `fd_hfork` leads to permanent `blk_pool` exhaustion
- **URL:** https://github.com/firedancer-io/firedancer/issues/9666
- **Created:** 2026-05-07 by @ibhatt-jumptrading
- **Updated:** 2026-05-07
- **Assignees:** lidatong

---

## #9664 — difference between pack and firedancer compute budget tracking
- **URL:** https://github.com/firedancer-io/firedancer/issues/9664
- **Created:** 2026-05-07 by @ibhatt-jumptrading
- **Updated:** 2026-05-07

Firedancer's leader pack path accepts signed Solana transactions containing RequestHeapFrame compute-budget instructions when the requested heap value is merely 1024-byte aligned. Firedancer runtime and Agave reject the same transaction when the heap value is below FD_MIN_HEAP_FRAME_BYTES or above FD_MAX_HEAP_FRAME_BYTES.

---

## #9663 — microblocks currently are not rebated in the leader pipeline
- **URL:** https://github.com/firedancer-io/firedancer/issues/9663
- **Created:** 2026-05-07 by @ibhatt-jumptrading
- **Updated:** 2026-05-07

---

## #9662 — fd_reasm_insert unconditionally updates the xid block_id from any FEC with slot_complete=true
- **URL:** https://github.com/firedancer-io/firedancer/issues/9662
- **Created:** 2026-05-07 by @lidatong
- **Updated:** 2026-05-07

---

## #9648 — Full Firedancer cluster restart support
- **URL:** https://github.com/firedancer-io/firedancer/issues/9648
- **Created:** 2026-05-07 by @ripatel-fd
- **Updated:** 2026-05-07
- **Labels:** Priority: Low

Make sure full Firedancer supports cluster restart scenarios

(extend snapshot-create to inject hard forks and feature gate changes)

---

## #9642 — Stale epoch vote stake across voter-set updates
- **URL:** https://github.com/firedancer-io/firedancer/issues/9642
- **Created:** 2026-05-06 by @lidatong
- **Updated:** 2026-05-06

https://github.com/firedancer-io/auditor-internal/issues/511

---

## #9616 — Firedancer v1.0 accepts oversized `StakeHistory` length and aborts snapshot boot
- **URL:** https://github.com/firedancer-io/firedancer/issues/9616
- **Created:** 2026-05-01 by @ibhatt-jumptrading
- **Updated:** 2026-05-01

---

## #9613 — Remote gossip snapshot source can crash Firedancer v1.0 during snapshot boot via oversized SlotHistory read-before-size-check
- **URL:** https://github.com/firedancer-io/firedancer/issues/9613
- **Created:** 2026-05-01 by @ibhatt-jumptrading
- **Updated:** 2026-05-01

---

## #9591 — Snapshot manifest parser does not bound `authorized_voters_len`; `40 * length3` wraps to zero, re-frames the vote-state stream, and crashes the replay tile on `fd_top_votes_refresh`
- **URL:** https://github.com/firedancer-io/firedancer/issues/9591
- **Created:** 2026-04-30 by @ibhatt-jumptrading
- **Updated:** 2026-05-27
- **Assignees:** jvarela-jump

---

## #9582 — Redundant Lamport Balance Check in fd_runtime_save_account Due to fd_accdb_open_ro Pre-filtering
- **URL:** https://github.com/firedancer-io/firedancer/issues/9582
- **Created:** 2026-04-30 by @ibhatt-jumptrading
- **Updated:** 2026-04-30

---

## #9575 — resolv_tile_cnt > 1 causes firedancer to not boot up
- **URL:** https://github.com/firedancer-io/firedancer/issues/9575
- **Created:** 2026-04-29 by @ibhatt-jumptrading
- **Updated:** 2026-04-29

---

## #9571 — Integer Overflow in `epoch_authorized_voters` Parsing During Snapshot Boot Causes Restore Abort and Validator Startup Failure
- **URL:** https://github.com/firedancer-io/firedancer/issues/9571
- **Created:** 2026-04-29 by @ibhatt-jumptrading
- **Updated:** 2026-05-27
- **Assignees:** jvarela-jump

This affects all other types of authorized voter loading too (including but not limited v3/v4 accounts)

---

## #9559 — repair: fd_policy_peer_upsert() silently drops new peers when the pool is full
- **URL:** https://github.com/firedancer-io/firedancer/issues/9559
- **Created:** 2026-04-29 by @jherrera-jump
- **Updated:** 2026-04-29
- **Assignees:** emwang-jump

Add proper stake-weighted eviction mechanism

---

## #9521 — Agave 4.1 Feature Parity
- **URL:** https://github.com/firedancer-io/firedancer/issues/9521
- **Created:** 2026-04-27 by @topointon-jump
- **Updated:** 2026-06-07
- **Assignees:** topointon-jump

Tracking issue for Agave 4.1 features.

- [x] 4.1 Snapshot Parsing: @topointon-jump https://github.com/firedancer-io/firedancer/pull/9853

**Runtime**
- [x] `loader_v3_minimum_extend_program_size` - https://github.com/firedancer-io/firedancer/pull/9945 @mjain-jump 
  - [x] Corpus
  - [ ] Ledger
- [x] `direct_account_pointers_in_program_input` - https://github.com/firedancer-io/firedancer/pull/9690 @topointon-jump
  - [ ] Corpus
  - [x] Ledger
- [x] `enable_sha512_syscall` - https://github.com/solana-foundation/solana-improvement-documents/pull/512 @drubin-fd @0x0ece 
  - [x] Corpus
  - [ ] Ledger
- [x] `limit_instruction_accounts` - https://github.com/solana-foundation/solana-improvement-documents/pull/406 @topointon-jump 
  - [ ] Corpus
  - [x] Ledger
- [x] `disable_sbpf_v0_v1_v2_deployment` - https://github.com/firedancer-io/firedancer/pull/9732 @0x0ece 
  - [x] Corpus
  - [x] Ledger
- [x] `define_ltds_fee_only_semantics` - https://github.com/firedancer-io/firedancer/pull/9947 @topointon-jump 
  - [ ] Corpus
  - [x] Ledger

**In-Protocol Block Revenue Distribution**
- [x] `commission_rate_in_basis_points` - https://github.com/solana-foundation/solana-improvement-documents/pull/291 @mjain-jump 
  - [x] Corpus
  - [x] Ledger

**Alpenglow**

- [x] `bls_pubkey_management_in_vote_account` - @0x0ece @drubin-fd 
  - [x] Corpus
  - [x] Ledger
- [x] `validator_admission_ticket` - @ibhatt-jumptrading https://github.com/firedancer-io/firedancer/issues/9240
  - [ ] Corpus
  - [x] Ledger
- [x] `discard_unexpected_data_complete_shreds` - @topointon-jump https://github.com/firedancer-io/firedancer/pull/9823
  - [ ] Corpus
  - [ ] Ledger

---

## #9479 — streaming implementation of `query_vote_accs`
- **URL:** https://github.com/firedancer-io/firedancer/issues/9479
- **Created:** 2026-04-23 by @mmcgee-jump
- **Updated:** 2026-04-23

iterating and reading/parsing all vote accounts at end of a slot like this is a serialized bottleneck, and we can just keep the structure updated incrementally throughout block execution, so it's ready when needed

---

## #9478 — remove `fd_stake_delegations_refresh`
- **URL:** https://github.com/firedancer-io/firedancer/issues/9478
- **Created:** 2026-04-23 by @mmcgee-jump
- **Updated:** 2026-04-23

can be done while loading the snapshot during snapin

---

## #9462 — firedancer-dev single-node mode doesn't root
- **URL:** https://github.com/firedancer-io/firedancer/issues/9462
- **Created:** 2026-04-23 by @ripatel-fd
- **Updated:** 2026-04-23

tower never makes consensus progress wen single node cluster

---

## #9445 — External Block Production
- **URL:** https://github.com/firedancer-io/firedancer/issues/9445
- **Created:** 2026-04-22 by @cavemanloverboy
- **Updated:** 2026-04-22

## Overview

The harmonic patch is one ~4.4k‑line commit on top of `fd/main` that adds: a second gRPC connection in the bundle tile to a "TPU endpoint" (relayer) for packets + pre‑validated block streams, gossip TPU‑address advertisement, a block lifecycle through verify→dedup→resolv/h→pack (parallel to bundles), and an extern state machine in pack. We split it into 4 stacked PRs that each leave the tree green, with the feature gated by `tiles.bundle.external_block_mode` (default `false`) and `tpu_url = ""` so behavior only changes once an operator opts in.

Presently the patch explicitly mentions "harmonic" but we will be changing this to "external" or "block", e.g. `external_block_support`, `external_block_transactions`, `subscribeBlocks`.

## PRs

- [ ] **PR 0 — prep / mechanical (no behavior change).**
  Header + config + topology field additions, defaulted off:
  - `fd_txn_m.h`: new `FD_TXN_M_TPU_SOURCE_EXTERN/ETPU`, `FD_TXN_M_SIG_EXTERN_FLAG/FAIL_FLAG`, `bundle_id`/`extern_slot` union, `bundle_txn_cnt` ulong→ushort, **add missing `arrival_ns` field** (referenced by resolh in patch but never declared).
  - `tiles.h`: `fd_completed_bank.block_height`, `fd_became_leader.leader_next_slot`.
  - `fd_topo.h`: `tile->bundle.{tpu_url,tpu_sni,external_block_mode}`, `tile->pack.bundle.external_block_mode`.
  - `fd_config.{c,h}` + `fd_config_parse.c` + `default.toml`: `tiles.bundle.{tpu_url,tpu_tls_domain_name,external_block_mode}`.
 `gui/fd_gui_printf.c` (new TPU source labels)
  - Bump `STEM_BURST` 5→32 in `fd_bundle_tile.c` (max extern batch size).

- [ ] **PR 1 — bundle tile + relayer TPU subscription + gossip TPU advertisement.**
  Biggest PR. Ships an actually useful feature (Remote TPU support):
  - New `proto/tpu.proto` + regen, `block_engine.proto` `SubmitLeaderWindowInfo`.
  - `fd_bundle_tpu.h`, second gRPC client in bundle tile (`GetTpuConfigs`, `SubscribePackets`, `SubmitLeaderWindowInfo`), extern staging buffer (declared, only used when extern mode on).
  - B

_(truncated)_

---

## #9432 — sh_addr vs sh_offset conformance issue in SBPF loader
- **URL:** https://github.com/firedancer-io/firedancer/issues/9432
- **Created:** 2026-04-21 by @topointon-jump
- **Updated:** 2026-04-22
- **Assignees:** topointon-jump

_**Not exploitable but needs explanation comment in the code as to why not**_

- Impact: Conformance
- Code: [src/ballet/sbpf/fd_sbpf_loader.c#L406-L459](https://github.com/firedancer-io/firedancer/blob/7749015ae1651dd71c60dceee9223ef23f46a6ba/src/ballet/sbpf/fd_sbpf_loader.c#L406)
- Summary: Firedancer uses sh_offset where Agave uses sh_addr for rodata mapping size, which may diverge for certain ELF layouts.
- Ref: https://github.com/firedancer-io/auditor-internal/issues/308

---

## #9431 — Potentially different .text section from Agave
- **URL:** https://github.com/firedancer-io/firedancer/issues/9431
- **Created:** 2026-04-21 by @topointon-jump
- **Updated:** 2026-04-22
- **Assignees:** topointon-jump

- Impact: Conformance
- Code: [src/ballet/sbpf/fd_sbpf_loader.c#L180](https://github.com/firedancer-io/firedancer/blob/7749015ae1651dd71c60dceee9223ef23f46a6ba/src/ballet/sbpf/fd_sbpf_loader.c#L180)
- Summary: SBPF text section handling differs from Agave due to rodata buffer modification ordering.
- Ref: https://github.com/firedancer-io/auditor-internal/issues/366

**_Not exploitable but needs explanation comment in the code as to why not_**

---

## #9409 — PoH long range attack
- **URL:** https://github.com/firedancer-io/firedancer/issues/9409
- **Created:** 2026-04-20 by @ripatel-fd
- **Updated:** 2026-04-20

```
ERR     04-20 01:26:33.182024 1892512 20   poh:0 src/discof/poh/fd_poh.c(604): Too many skipped ticks from slot 402930613 to slot 402935723, chain must halt
```

Got this while developing on testnet, suspected DoS vulnerability in Firedancer v1.0 beta

---

## #9114 — Tune test_accounts_resize_delta
- **URL:** https://github.com/firedancer-io/firedancer/issues/9114
- **Created:** 2026-03-31 by @ripatel-fd
- **Updated:** 2026-04-03
- **Assignees:** ripatel-fd

Claude `/coverage` report:

```md
  Coverage Summary

  What the test covers well:
  - fd_borrowed_account_update_accounts_resize_delta (line 194-204): fully covered (9 hits) — the core delta accumulation logic
  - fd_borrowed_account_set_data_length (line 122-155): fully covered (9 hits) — the resize path
  - fd_borrowed_account_can_data_be_resized (line 209-237): covered (9 hits) for the happy path
  - fd_system_program_allocate (line 161): covered (8 hits, 1 hitting the max-space error at line 199)
  - Loader V4 shrink path: covered (2 hits from the shrink tests)

  Under-covered areas (0 hits):

  1. MAX_PERMITTED_ACCOUNT_DATA_ALLOCS_PER_TXN rejection branch (line 230-233): Never hit. The test test_allocate_25mib_fails does fail, but the failure likely comes from fd_system_program_allocate at line 193-199 (the MAX_PERMITTED_DATA_LENGTH per-account check), not from the per-txn 20 MiB
  resize delta limit. The 25 MiB test uses 15 MiB + 10 MiB — the 15 MiB single-account allocation hits MAX_PERMITTED_DATA_LENGTH (10 MiB) before reaching the per-txn delta limit.
  2. fd_borrowed_account_set_data_from_slice (line 91-118): 0 hits. This is an alternative resize path that also calls update_accounts_resize_delta. Not exercised.
  3. fd_borrowed_account_set_owner (line 24-57): 0 hits.
  4. fd_borrowed_account_set_executable (line 158-191): 0 hits.
  5. fd_borrowed_account_get_data_mut (line 4-21): 0 hits.

  Key finding: The test test_allocate_25mib_fails doesn't actually exercise the MAX_PERMITTED_ACCOUNT_DATA_ALLOCS_PER_TXN rejection. To properly test that limit, the test should allocate amounts that each individually pass the per-account limit (<=10 MiB) but together exceed 20 MiB — e.g.,
  three allocations of 7 MiB each (=21 MiB > 20 MiB limit). Currently line 231 (FD_EXECUTOR_INSTR_ERR_MAX_ACCS_DATA_ALLOCS_EXCEEDED) is never returned.
```

---

## #9091 — restore: filter gossip peers that do not serve snapshot requests
- **URL:** https://github.com/firedancer-io/firedancer/issues/9091
- **Created:** 2026-03-31 by @jvarela-jump
- **Updated:** 2026-04-06
- **Assignees:** jvarela-jump

Gossip peers may advertise an `rpc address` and still not respond to http requests.
( They may also advertise `{full,incr}_{slot,hash}` even if they do not serve snapshot requests ).
Perform an `http head` before requesting the snapshot from the peer.
If no response, then blacklist the peer (for snapshot-download purposes).
Do this for both full and incremental snapshots.

---

## #9066 — New rent behavior
- **URL:** https://github.com/firedancer-io/firedancer/issues/9066
- **Created:** 2026-03-27 by @0x0ece
- **Updated:** 2026-04-03
- **Assignees:** mjain-jump

While [upgrading solfuzz-agave to agave-v4.0.0-beta.5 ](https://github.com/firedancer-io/solfuzz-agave/pull/466) we noticed a new behavior for rent that we should adapt in our test infra.
The changes appear to be in agave-v4.0.0-beta.1.

TODO:
- in fd to remove rent from the bank
- in solfuzz-agave to do the same
- in protosol to deprecate the rent field from the message definition

---

## #8985 — replay housekeeping % too high
- **URL:** https://github.com/firedancer-io/firedancer/issues/8985
- **Created:** 2026-03-20 by @mmcgee-jump
- **Updated:** 2026-04-21
- **Assignees:** yufeng-jump

2.5%, shouldn't be this high

---

## #8956 — restore: incremental snapshot slot verification before download request
- **URL:** https://github.com/firedancer-io/firedancer/issues/8956
- **Created:** 2026-03-18 by @jvarela-jump
- **Updated:** 2026-04-06
- **Assignees:** jvarela-jump

Incremental slots advertised via gossip may be stale by the time we request the incremental snapshot from the peer, causing http 404 error.
This seems to be more noticeable on nodes far away (geographically).

---

## #8951 — gossip: handle larger # of accounts for wfs 
- **URL:** https://github.com/firedancer-io/firedancer/issues/8951
- **Created:** 2026-03-18 by @ibhatt-jumptrading
- **Updated:** 2026-03-31
- **Assignees:** jherrera-jump

---

## #8871 — solcap: belt sanding
- **URL:** https://github.com/firedancer-io/firedancer/issues/8871
- **Created:** 2026-03-13 by @yufeng-jump
- **Updated:** 2026-03-17
- **Assignees:** yufeng-jump

#7630 #7629

- fsync() should not be on the critical path

---

## #8801 — Size repair_out depending on catchup behind
- **URL:** https://github.com/firedancer-io/firedancer/issues/8801
- **Created:** 2026-03-10 by @emwang-jump
- **Updated:** 2026-04-06
- **Assignees:** emwang-jump

the FEC data flow now goes shred->repair->replay again, which re-introduces a possible issue from awhile ago
where is replay is far behind repair, this could cause backpressure which slows down the shred ingest pipeline. 

Investigate the average # FECs per mainnet block and size repair_out for that * either the average catchup distance from an incremental snapshot OR some supported threshold (like 4096 slots behind) if the memory usage isn't too high.

high repair_out can cause store size to blow up because it store_sz = shred_out + repair_out + reasm

---

## #8797 — firedancer missed votes higher than peers
- **URL:** https://github.com/firedancer-io/firedancer/issues/8797
- **Created:** 2026-03-10 by @mmcgee-jump
- **Updated:** 2026-04-21
- **Assignees:** ibhatt-jumptrading, yufeng-jump

e.g. https://reports.firedancer.io/?date=2026-03-09&tab=validators&validatorsTableState=%7B%22sort%22%3A%5B%22lat1_vote_rate%7Edesc%22%5D%7D

---

## #8682 — snapshot manifest gets too large with larger vote/stake account max values
- **URL:** https://github.com/firedancer-io/firedancer/issues/8682
- **Created:** 2026-03-03 by @ibhatt-jumptrading
- **Updated:** 2026-04-21
- **Assignees:** jvarela-jump

target ~30M vote accs and ~200M stake accounts

---

## #8673 — gossip: prevent table flush on boot, learning epoch stakes
- **URL:** https://github.com/firedancer-io/firedancer/issues/8673
- **Created:** 2026-03-03 by @mmcgee-jump
- **Updated:** 2026-04-06
- **Assignees:** mmcgee-jump, jherrera-jump

---

## #8636 — further slim down stake delegations
- **URL:** https://github.com/firedancer-io/firedancer/issues/8636
- **Created:** 2026-03-02 by @ibhatt-jumptrading
- **Updated:** 2026-03-31
- **Assignees:** ibhatt-jumptrading

use shared index for vote account and stake account pubkeys (see comment in fd_stake_delegations.h)

---

## #8628 — tower file support
- **URL:** https://github.com/firedancer-io/firedancer/issues/8628
- **Created:** 2026-03-02 by @ibhatt-jumptrading
- **Updated:** 2026-03-31
- **Assignees:** lidatong

used for set identity

---

## #8607 — Naming pattern genesis-[hash].bin
- **URL:** https://github.com/firedancer-io/firedancer/issues/8607
- **Created:** 2026-03-01 by @ripatel-fd
- **Updated:** 2026-04-06

Instead of `mainnet-genesis.bin`, call blobs `genesis-[hash].bin` to disambiguate

---

## #8499 — backtest configs are spammy
- **URL:** https://github.com/firedancer-io/firedancer/issues/8499
- **Created:** 2026-02-26 by @ripatel-fd
- **Updated:** 2026-03-17

Backtest configs include a ton of redundant config items like this.

This should just be default configuration:
- Select best snapshot locally available on disk, don't attempt to download snapshots
- Disable gossip by default (run without a gossip tile) 
- Sane defaults for layout
- Enable lthash verification

```
[snapshots]
    max_full_snapshots_to_keep = 5
    max_incremental_snapshots_to_keep = 5
    incremental_snapshots = false
    [snapshots.sources]
        servers = []
        [snapshots.sources.gossip]
            allow_any = false
            allow_list = []
[layout]
    snapshot_hash_tile_count = 1
[development]
    [development.snapshots]
        disable_lthash_verification = false
[gossip]
    entrypoints = [ "0.0.0.0:1" ]
```

---

## #8473 — Fix firedancer-dev bench with large configs
- **URL:** https://github.com/firedancer-io/firedancer/issues/8473
- **Created:** 2026-02-25 by @ripatel-fd
- **Updated:** 2026-03-31
- **Assignees:** ripatel-fd

---

## #8444 — gossip: all votes pushed with index 0
- **URL:** https://github.com/firedancer-io/firedancer/issues/8444
- **Created:** 2026-02-24 by @mmcgee-jump
- **Updated:** 2026-04-21
- **Assignees:** mmcgee-jump, jherrera-jump

---

## #8316 — add gossip duplicate_shred->index field
- **URL:** https://github.com/firedancer-io/firedancer/issues/8316
- **Created:** 2026-02-17 by @mmcgee-jump
- **Updated:** 2026-03-17
- **Assignees:** lidatong

---

## #8292 — Audit all possible values of bank and sysvar fields
- **URL:** https://github.com/firedancer-io/firedancer/issues/8292
- **Created:** 2026-02-12 by @topointon-jump
- **Updated:** 2026-04-03

Audit all current values of bank fields and sysvar fields on mainnet, testnet and devnet so that we are aware of all discrepancies. Make sure that the fuzzers have all the possible values as inputs.

---

## #8290 — 2026-02-04 Post-Mortem Follow-Up Items
- **URL:** https://github.com/firedancer-io/firedancer/issues/8290
- **Created:** 2026-02-12 by @topointon-jump
- **Updated:** 2026-04-03

Tracking issue for follow-up items from the 2026-02-04 testnet BHM.

---

## #8289 — Feature activation epoch boundary fuzzing
- **URL:** https://github.com/firedancer-io/firedancer/issues/8289
- **Created:** 2026-02-12 by @topointon-jump
- **Updated:** 2026-04-03
- **Assignees:** cmoyes-jump

Block fuzzer (or another new fuzz harness) needs to exercise feature activations at the epoch boundary. Several features have code which is only exercised in the `compute_and_apply_new_feature_activations` epoch boundary function. Check coverage data to make sure feature activations are enabled.

---

## #8234 — Add admin tile to co-ordinate key updates
- **URL:** https://github.com/firedancer-io/firedancer/issues/8234
- **Created:** 2026-02-10 by @mmcgee-jump
- **Updated:** 2026-03-31

---

## #8232 — config file full audit
- **URL:** https://github.com/firedancer-io/firedancer/issues/8232
- **Created:** 2026-02-10 by @mmcgee-jump
- **Updated:** 2026-03-03
- **Assignees:** mmcgee-jump

---

## #8231 — Firedancer as an entrypoint node
- **URL:** https://github.com/firedancer-io/firedancer/issues/8231
- **Created:** 2026-02-10 by @mmcgee-jump
- **Updated:** 2026-03-17

- port check
- genesis serving etc

---

## #8222 — increase max_live_banks to 4096
- **URL:** https://github.com/firedancer-io/firedancer/issues/8222
- **Created:** 2026-02-10 by @mmcgee-jump
- **Updated:** 2026-03-17
- **Assignees:** ibhatt-jumptrading

requires decreasing memory usage so still runs on 512g

---

## #8145 — Rent Reduction Feature Gates
- **URL:** https://github.com/firedancer-io/firedancer/issues/8145
- **Created:** 2026-02-03 by @topointon-jump
- **Updated:** 2026-03-17
- **Assignees:** topointon-jump

Not finalized in Agave yet but likely to be in 4.0

Don't implement until release is cut

---

## #8121 — SIMD-0232: Custom Commission Collector Account
- **URL:** https://github.com/firedancer-io/firedancer/issues/8121
- **Created:** 2026-02-02 by @topointon-jump
- **Updated:** 2026-03-17
- **Assignees:** topointon-jump

https://github.com/solana-foundation/solana-improvement-documents/pull/232

https://github.com/anza-xyz/agave/pull/9687

---

## #8106 — overhaul validator config management
- **URL:** https://github.com/firedancer-io/firedancer/issues/8106
- **Created:** 2026-01-30 by @ibhatt-jumptrading
- **Updated:** 2026-03-17
- **Assignees:** kbhargava-jump

---

## #8101 — increase `sz` on frag_meta_t and remove all the related hacks
- **URL:** https://github.com/firedancer-io/firedancer/issues/8101
- **Created:** 2026-01-30 by @mmcgee-jump
- **Updated:** 2026-03-17

---

## #8044 — fixup event tile seccomp policy
- **URL:** https://github.com/firedancer-io/firedancer/issues/8044
- **Created:** 2026-01-27 by @mmcgee-jump
- **Updated:** 2026-04-06
- **Labels:** security
- **Assignees:** mmcgee-jump

```
# client: need to be able to establish connections to the event server.
socket: (and (eq (arg 0) "AF_INET")
#             (eq (arg 1) "SOCK_STREAM|SOCK_NONBLOCK") TODO: UNCOMMENTING CAUSES SIGSYS ?
             (eq (arg 2) 0))
```

---

## #8029 — backtest: support forking during replay
- **URL:** https://github.com/firedancer-io/firedancer/issues/8029
- **Created:** 2026-01-27 by @ibhatt-jumptrading
- **Updated:** 2026-03-17

---

## #8009 — Verify multiple PoH chains simultaneously on a single core
- **URL:** https://github.com/firedancer-io/firedancer/issues/8009
- **Created:** 2026-01-26 by @yufeng-jump
- **Updated:** 2026-03-17
- **Assignees:** yufeng-jump

Suggested by @ptaffet-jump.  A single Zen 4 core should be able to do 3 chains simultaneously with roughly the same latency as 1.  Big throughput bump.

---

## #7923 — bank,tower: vote-only mode
- **URL:** https://github.com/firedancer-io/firedancer/issues/7923
- **Created:** 2026-01-20 by @lidatong
- **Updated:** 2026-03-17
- **Assignees:** lidatong

---

## #7906 — firedancer-dev stderr log has no color with --no-sandbox --no-clone
- **URL:** https://github.com/firedancer-io/firedancer/issues/7906
- **Created:** 2026-01-20 by @ripatel-fd
- **Updated:** 2026-03-17
- **Assignees:** mmcgee-jump

Seems to be a bug in Firedancer's boot procedure that treats stderr incorrectly -

Results in output being stuck/not line buffered (if watch is enabled), or have no color (if `--no-watch` is set)

---

## #7884 — implement port check server for agaves
- **URL:** https://github.com/firedancer-io/firedancer/issues/7884
- **Created:** 2026-01-16 by @mmcgee-jump
- **Updated:** 2026-03-17
- **Assignees:** mmcgee-jump

---

## #7883 — implement snapshot creation / server
- **URL:** https://github.com/firedancer-io/firedancer/issues/7883
- **Created:** 2026-01-16 by @mmcgee-jump
- **Updated:** 2026-03-17

---

## #7882 — implement repair server
- **URL:** https://github.com/firedancer-io/firedancer/issues/7882
- **Created:** 2026-01-16 by @lidatong
- **Updated:** 2026-03-31
- **Assignees:** drubin-fd

this will likely require retaining shreds on disk longer than the in-memory fd_store

---

## #7877 — speed up banks_new
- **URL:** https://github.com/firedancer-io/firedancer/issues/7877
- **Created:** 2026-01-15 by @ibhatt-jumptrading
- **Updated:** 2026-03-17
- **Assignees:** ibhatt-jumptrading

WARNING 01-15 22:15:28.746924 2203871 f0   main src/disco/topo/fd_topo.c(157): fd_topo_wksp_new(banks) took 411 ms

---

## #7849 — Clean up bundle txn account management
- **URL:** https://github.com/firedancer-io/firedancer/issues/7849
- **Created:** 2026-01-13 by @ripatel-fd
- **Updated:** 2026-06-05
- **Assignees:** ibhatt-jumptrading

Apply design discussed in Slack

---

## #7841 — equivocation / dos testing framework
- **URL:** https://github.com/firedancer-io/firedancer/issues/7841
- **Created:** 2026-01-13 by @lidatong
- **Updated:** 2026-03-31
- **Assignees:** lidatong

need a way to test whether the equivocation handling and dos mitigation works correctly for the TVU pipeline: shred / repair / replay / tower

braindump of test cases:

- [ ] receive a confirmation before replaying. then get the wrong version of the block to replay. this wrong version should NOT be replayed (reasm should withhold it)

---

## #7832 — bank,tower: check_propagation_for_start_leader
- **URL:** https://github.com/firedancer-io/firedancer/issues/7832
- **Created:** 2026-01-13 by @lidatong
- **Updated:** 2026-03-25
- **Assignees:** lidatong

`check_propagation_for_start_leader`

retransmit instead of starting a new leader block if last rotation isn't propagated

---

## #7817 — backtest choking up when solcap enabled
- **URL:** https://github.com/firedancer-io/firedancer/issues/7817
- **Created:** 2026-01-12 by @kbhargava-jump
- **Updated:** 2026-04-03
- **Assignees:** ripatel-fd

example:
```
NOTICE  01-12 22:47:13.702699 3146064 0    backt:0 src/discof/backtest/fd_backtest_tile.c(347): Bank hash matches! slot=387057973, hash=5XnAhmuUtGNGdwCmPDmuxX8qT35xPeAd5Rxdmw4zXxwz (switch 0.00 ms, begin 0.53 ms, exec  64.35 ms, finish 0.20 ms)
NOTICE  01-12 22:47:16.808957 3146064 0    backt:0 src/discof/backtest/fd_backtest_tile.c(347): Bank hash matches! slot=387057974, hash=9fV82umVgEvjpNi7DbJc9sUMKuY6n1C2fdULPeC3eeGb (switch 0.00 ms, begin 3053.12 ms, exec  52.94 ms, finish 0.19 ms)
NOTICE  01-12 22:47:16.866901 3146064 0    backt:0 src/discof/backtest/fd_backtest_tile.c(347): Bank hash matches! slot=387057975, hash=8Wgsh5TtqFbMP7aVQUmuWa9S6M1B3zk1g3Yi8rwnzvkz (switch 0.00 ms, begin 0.53 ms, exec  57.19 ms, finish 
```
exec looks fine but not before that

---

## #7809 — epoch boundary computation is way too slow and takes several seconds
- **URL:** https://github.com/firedancer-io/firedancer/issues/7809
- **Created:** 2026-01-12 by @ibhatt-jumptrading
- **Updated:** 2026-04-23
- **Assignees:** ibhatt-jumptrading, kbhargava-jump, yufeng-jump

---

## #7793 — Unit test for PF settlement
- **URL:** https://github.com/firedancer-io/firedancer/issues/7793
- **Created:** 2026-01-12 by @ripatel-fd
- **Updated:** 2026-03-17
- **Assignees:** ripatel-fd, topointon-jump

Priority fees settlement edge cases:
- Block had no transactions (no fees)
- Fee collector / leader does not exist
- PF payout is too low to pass rent exemption threshold
- Fee collector not owned by system program

---

## #7791 — Unit test for feature account activation
- **URL:** https://github.com/firedancer-io/firedancer/issues/7791
- **Created:** 2026-01-12 by @ripatel-fd
- **Updated:** 2026-03-17
- **Assignees:** ripatel-fd

Edge cases:
- Feature account is too small (1 byte) before activation, so activation would increase size past rent exemption

---

## #7790 — Unit test for stake account reward
- **URL:** https://github.com/firedancer-io/firedancer/issues/7790
- **Created:** 2026-01-12 by @ripatel-fd
- **Updated:** 2026-03-17
- **Assignees:** ripatel-fd, ibhatt-jumptrading

Exercise the following edge cases:
- Stake account does not exist
- Stake account is oversize (only override prefix)

---

## #7787 — Unit test for vote account reward
- **URL:** https://github.com/firedancer-io/firedancer/issues/7787
- **Created:** 2026-01-12 by @ripatel-fd
- **Updated:** 2026-03-17
- **Assignees:** ripatel-fd, ibhatt-jumptrading

Test vote reward payout with a few edge cases:
- account does not exist
- account not owned by the vote program

Write an equivalent test for Agave to verify behavior

---

## #7767 — Non-deterministic replay: `pubkey not found`, `already have bank in forks` when FD joins agave cluster
- **URL:** https://github.com/firedancer-io/firedancer/issues/7767
- **Created:** 2026-01-11 by @esemeniuc
- **Updated:** 2026-04-03

## Summary

When Firedancer joins an existing agave cluster, there is a non-deterministic failure mode where catchup fails with `pubkey not found` or `already have bank in forks` errors. This issue occurs approximately 40-50% of the time on catchup and requires wiping `~/.firedancer` to recover. Sometimes up to 3 wipes are required before the node successfully catches up. This can also happen after the local cluster has been running for a while (observed at slot ~65000). Error is logged from Agave code.

## Environment
- Firedancer version: v0.8 (263f8fd1b0e82cfeae34db8065218056fcf6cb7e), v0.805, 4x Agave 3.1.2 in local development mode
- Platform: Ubuntu 24.04.3 (kernel 6.8.0)
- Configuration: Local cluster with Firedancer joining agave validators
- Genesis config: `hashes_per_tick=12500`
- Network provider: socket (not XDP, due to localhost cluster)

## Log Evidence
`InvalidBlock(InvalidEntryHash)`:[fd-0.806.30102_3322159_core_eric-dev-box_2026_01_11_05_42_20_166933153_GMT+00.txt](https://github.com/user-attachments/files/24548619/fd-0.806.30102_3322159_core_eric-dev-box_2026_01_11_05_42_20_166933153_GMT%2B00.txt)

`pubkey not found`: [fd-0.806.30102_3340624_core_eric-dev-box_2026_01_11_05_46_57_692158684_GMT+00.txt](https://github.com/user-attachments/files/24548630/fd-0.806.30102_3340624_core_eric-dev-box_2026_01_11_05_46_57_692158684_GMT%2B00.txt)

`pubkey not found`: [fd-0.806.30102_3345777_core_eric-dev-box_2026_01_11_05_49_27_887718244_GMT+00.txt](https://github.com/user-attachments/files/24548638/fd-0.806.30102_3345777_core_eric-dev-box_2026_01_11_05_49_27_887718244_GMT%2B00.txt)
pcap for above (rename to remove .txt extension due to github limitation): [out.pcap.zst.txt](https://github.com/user-attachments/files/24548652/out.pcap.zst.txt)

## Workaround

Wipe the `~/.firedancer` directory and restart. May need to repeat this several times 

## Reproduction Steps

1. Set up a local cluster with multiple agave validators running
2. Start Firedancer to join t

_(truncated)_

---

## #7761 — CI tests for bank tile
- **URL:** https://github.com/firedancer-io/firedancer/issues/7761
- **Created:** 2026-01-10 by @ripatel-fd
- **Updated:** 2026-04-03

- [ ] test txn
- [ ] test txn fail
- [ ] test bundle
- [ ] test bundle revert

---

## #7755 — FD leader slots rejected with InvalidBlock(TooFewTicks) in low-power PoH mode (hashes_per_tick=None)
- **URL:** https://github.com/firedancer-io/firedancer/issues/7755
- **Created:** 2026-01-10 by @esemeniuc
- **Updated:** 2026-04-03

## Summary

Firedancer leader slots are skipped by agave validators with `InvalidBlock(TooFewTicks)` when running in local clusters configured with low-power PoH mode (`hashes_per_tick=None`). Confirmed by @ptaffet-jump 

## Environment
- Firedancer version: v0.8 (263f8fd1b0e82cfeae34db8065218056fcf6cb7e), v0.805
- Platform: Ubuntu 24.04.3 (kernel 6.8.0)
- Configuration: Local cluster with Firedancer joining agave validators
- Genesis config: `hashes_per_tick=None` (low-power/sleep PoH mode)
- Network provider: socket (not XDP, due to localhost cluster)

## Root Cause Analysis

The issue stems from how Firedancer handles the low-power PoH mode when `hashes_per_tick=None`:

1. **Genesis Configuration**: Local clusters use `create_genesis_config_with_leader_ex()` which creates genesis with default PoH Config set to sleep mode (`hashes_per_tick=None`). This can be verified with:
   ```
   agave-ledger-tool genesis --ledger bam/output/ledger/validator-1
   ```
   Output shows: `Hashes per tick: None`, `Ticks per slot: 64`

2. **Firedancer Mapping**: Firedancer maps `hashes_per_tick=None` to `hashcnt_per_tick=1` in `agave/poh/src/firedancer_poh_recorder.rs:102`. This enables the low-power path in the PoH tile.

## Observed Behavior
- Agave validators log: `replay-stage-mark_dead_slot error=error: InvalidBlock(TooFewTicks)`
- Issue observed across multiple slots
- FD skip rate remains at 100% while agave skip rate is 0%

## Key Log Evidence

From agave validator logs:
```
[solana_metrics::metrics] datapoint: replay-stage-mark_dead_slot error=error: InvalidBlock(TooFewTicks)* slot=36401
Too few entry ticks found in slot: 1100
```

From FD POH initialization:
```
fd_ext_poh_initialize params: tick_duration_nanos=54687500, hashes_per_tick=None, ticks_per_slot=64, tick_height=0
```

## Workaround

Setting `hashes_per_tick` to a specific value (e.g., 62500) in genesis resolves the issue.


## Expected Behavior

Firedancer should correctly emit the required number of ticks for 

_(truncated)_

---

## #7751 — [DZ] Let gossip advertise additional external TPUs
- **URL:** https://github.com/firedancer-io/firedancer/issues/7751
- **Created:** 2026-01-09 by @riptl
- **Updated:** 2026-03-24
- **Assignees:** jvarela-jump

Allow a Firedancer operator to configure secondary TPUvote ports, to be advertised in Gossip ContactInfo for redundancy.

E.g. an operator might operate DDoS-protected reverse proxies (continuity) as a failover, but prefer clients to send it traffic directly (IBRL)

---

## #7750 — [DZ] TPUvote client side redundancy
- **URL:** https://github.com/firedancer-io/firedancer/issues/7750
- **Created:** 2026-01-09 by @riptl
- **Updated:** 2026-03-24
- **Assignees:** jvarela-jump

Allow the Firedancer voter to failover across multiple TPU endpoints if a validator advertises multiple TPU ports in gossip. 

TBD how to implement the failover policy? (keep 1 conn or N conns open? what determines a conn failure? priority? etc)

---

## #7744 — [bp postmortem] audit possible value ranges of all bank fields
- **URL:** https://github.com/firedancer-io/firedancer/issues/7744
- **Created:** 2026-01-09 by @ripatel-fd
- **Updated:** 2026-03-31
- **Assignees:** mjain-jump

parameterize bank values in fuzzing

---

## #7738 — [bp postmortem] consensus events to clickhouse
- **URL:** https://github.com/firedancer-io/firedancer/issues/7738
- **Created:** 2026-01-09 by @ripatel-fd
- **Updated:** 2026-04-06
- **Assignees:** mmcgee-jump

---

## #7630 — solcap: .pcapng.zst compression
- **URL:** https://github.com/firedancer-io/firedancer/issues/7630
- **Created:** 2025-12-24 by @ripatel-fd
- **Updated:** 2026-03-17
- **Assignees:** ripatel-fd

Wireshark supports transparent decompression of compressed pcapng files.

Consider adding Zstandard streaming compression to the pcapng writer (probably using libc file cookie API)

---

## #7629 — solcap: fflush on shutdown
- **URL:** https://github.com/firedancer-io/firedancer/issues/7629
- **Created:** 2025-12-24 by @ripatel-fd
- **Updated:** 2026-04-03

The solcap tile logs crucial debug information to disk.

Some forms of crashes (e.g. FD_LOG_CRIT) result in buffered debug info getting lost because the solcap tile doesn't have sufficient time to flush its buffers on shutdown.

---

## #7540 — Generalize pzstd-style compression
- **URL:** https://github.com/firedancer-io/firedancer/issues/7540
- **Created:** 2025-12-03 by @ripatel-fd
- **Updated:** 2026-03-17
- **Assignees:** ripatel-fd

- [ ] Clean up the parallel compression algorithm in snapmk and refactor it into reusable components.
- [ ] Switch from the current custom framing format to pzstd framing (makes it much easier for Agave to support the same optimization) 
- [ ] Remove out-of-order block processing / parallel signal bits

---

## #7539 — [backtest] Document pcapng packet tagging
- **URL:** https://github.com/firedancer-io/firedancer/issues/7539
- **Created:** 2025-12-03 by @ripatel-fd
- **Updated:** 2026-04-03

The shredcap v0.1 spec lacks documentation for the Solana packet tagging scheme

---

## #7527 — ENOMEM when changing identity
- **URL:** https://github.com/firedancer-io/firedancer/issues/7527
- **Created:** 2025-12-02 by @HGuillemet
- **Updated:** 2026-04-03

Found in my logs during an identity switch, with v0.804:

```
WARNING 2025-12-02 16:39:03.673475400 GMT+01  89381:89381  mainnet:puffin3:f0   puffin:[group]:main src/util/shmem/fd_shmem_user.c(241)[fd_shmem_join]: fd_numa_mlock("/home/mainnet/.tlb/.gigantic/puffin_pack.wksp",2097152 KiB) failed (12-ENOMEM-cannot allocate memory); attempting to continue
WARNING 2025-12-02 16:39:03.673514051 GMT+01  89381:89381  mainnet:puffin3:f0   puffin:[group]:main src/util/shmem/fd_shmem_user.c(241)[fd_shmem_join]: fd_numa_mlock("/home/mainnet/.tlb/.huge/puffin_poh.wksp",18432 KiB) failed (12-ENOMEM-cannot allocate memory); attempting to continue
WARNING 2025-12-02 16:39:03.673551891 GMT+01  89381:89381  mainnet:puffin3:f0   puffin:[group]:main src/util/shmem/fd_shmem_user.c(241)[fd_shmem_join]: fd_numa_mlock("/home/mainnet/.tlb/.gigantic/puffin_shred.wksp",1048576 KiB) failed (12-ENOMEM-cannot allocate memory); attempting to continue
WARNING 2025-12-02 16:39:03.673572801 GMT+01  89381:89381  mainnet:puffin3:f0   puffin:[group]:main src/util/shmem/fd_shmem_user.c(241)[fd_shmem_join]: fd_numa_mlock("/home/mainnet/.tlb/.gigantic/puffin_gui.wksp",29360128 KiB) failed (12-ENOMEM-cannot allocate memory); attempting to continue
WARNING 2025-12-02 16:39:03.673580521 GMT+01  89381:89381  mainnet:puffin3:f0   puffin:[group]:main src/util/shmem/fd_shmem_user.c(241)[fd_shmem_join]: fd_numa_mlock("/home/mainnet/.tlb/.gigantic/puffin_bundle.wksp",1048576 KiB) failed (12-ENOMEM-cannot allocate memory); attempting to continue
WARNING 2025-12-02 16:39:04.340048947 GMT+01  28847:28862  mainnet:puffin3:42   puffin:[group]:poh:0 validator/src/admin_rpc_service.rs(826)[agave_validator::admin_rpc_service]: Identity set to puffinQSvKFriPbyE5atyx1ptfnyytovbzxybr1jsyy
```

This doesn't seem to prevent proper operation.

---

## #7495 — Snapshot tile unit tests
- **URL:** https://github.com/firedancer-io/firedancer/issues/7495
- **Created:** 2025-12-01 by @ripatel-fd
- **Updated:** 2026-04-03
- **Assignees:** ripatel-fd

---

## #7474 — Allow passing environment variables through to the agave process
- **URL:** https://github.com/firedancer-io/firedancer/issues/7474
- **Created:** 2025-11-29 by @SEJeff
- **Updated:** 2026-04-03

The metrics logging is a bit out of control and excessively logs.

```bash
# grep solana_metrics::metrics firedancer-since-09:30.log | grep -c 09:30:01
1328
```

With an agave instance, I can do `RUST_LOG=info,solana_metrics=warn` to suppress this, but I am unable to do the same for firedancer as the sandbox seems to be clearing them:

https://github.com/firedancer-io/firedancer/blob/076b3cfe37c6667e801e9d05658339b7959ff50d/src/util/sandbox/fd_sandbox.c#L122-L132

Can we add support for setting the env variables `RUST_LOG` and `RUST_BACKTRACE` to frankendancer for the agave bits until the full client is live?

I set that variable in the firedancer systemd unit and it didn't seem to be working. I confirmed this behaviour via:
```bash
# cat /proc/$(pgrep -f 'fdctl.*run-agave')/environ
#
```

This is an example of a single one of the log lines:

```
firedancer[20839]: INFO    2025-11-29 09:30:00.015801548 GMT+00  20838:7      firedancer:[${HOSTNAME_HERE}] :f10  fd1:[group]:0    metrics/src/metrics.rs(331)[solana_metrics::metrics]: datapoint: slot_stats_tracking_complete slot=128572897i last_index=63i num_repaired=0i num_recovered=0i min_turbine_fec_set_count=64i is_full=true is_rooted=true is_dead=false
```

---

## #7468 — Add gossip ping to websocket
- **URL:** https://github.com/firedancer-io/firedancer/issues/7468
- **Created:** 2025-11-28 by @HGuillemet
- **Updated:** 2026-04-03
- **Assignees:** jherrera-jump

Could you consider adding the Gossip ping time to validator information in the web socket ?
This could be a useful  information  in the gui, and would allow to estimate the distance of any validator to the cluster by querying several public FD gui.

---

## #7357 — use_consumed_cus = false broken on Frankendancer
- **URL:** https://github.com/firedancer-io/firedancer/issues/7357
- **Created:** 2025-11-20 by @ptaffet-jump
- **Updated:** 2025-11-20
- **Assignees:** ptaffet-jump

An operator is reporting that running with `use_consumed_cus = false` causes `link 19 (bank_pack:0) has 0 consumers`.
We probably need something like this
https://github.com/firedancer-io/firedancer/commit/cdc7ef227da217e71b8431b8d12a7a9695f34955
for Frankendancer.

---

## #7278 — Auto affinity improvements
- **URL:** https://github.com/firedancer-io/firedancer/issues/7278
- **Created:** 2025-11-17 by @mmcgee-jump
- **Updated:** 2026-03-31

- [x] Exclude core 0 from `auto` affinity by default https://github.com/firedancer-io/firedancer/pull/7964
- [x] Add an `excluded_cores` list to configuration file, which will not get scheduled on https://github.com/firedancer-io/firedancer/pull/7964
- [x] Investigate why `floating` tiles get a weird affinity assignment by default, they should be unpinned
   - upon investigation, this looks ok
- [x] If the CPU has more cores than tiles when excluding HT pairs, we do not need to schedule on HT pairs and should ignore them by default https://github.com/firedancer-io/firedancer/pull/8308
- [ ] If Firedancer is started with an affinity already (e.g. from systemd), we should constrain the available cores for "auto" to this set

---

## #7137 — snapshot-load should not touch NICs in offline mode
- **URL:** https://github.com/firedancer-io/firedancer/issues/7137
- **Created:** 2025-11-07 by @ripatel-fd
- **Updated:** 2026-01-14

---

## #7108 — Parse CLI args before creating log file
- **URL:** https://github.com/firedancer-io/firedancer/issues/7108
- **Created:** 2025-11-06 by @ripatel-fd
- **Updated:** 2025-11-14

It is a bit silly that we're creating a log file when running `--help` 

```
$ build/native/gcc/bin/firedancer-dev snapshot-load --help
Log at "/tmp/fd-0.101.30006_3541419_ripatel_REDACTEd_2025_11_06_18_20_17_120213350_GMT+00"

Usage: firedancer-dev snapshot-load [GLOBAL FLAGS] [FLAGS]

Flags:
  --snapshot-dir PATH  Load/save snapshots from this directory
  --db <funk/vinyl>    Database engine
  --vinyl-server       Indefinitely run a vinyl DB server for testing
  --offline            Do not attempt to download snapshots
```

---

## #7052 — resolv: wrong expiration logic
- **URL:** https://github.com/firedancer-io/firedancer/issues/7052
- **Created:** 2025-11-04 by @HGuillemet
- **Updated:** 2025-11-14

There is a confusion in `resolv` `after_frag` between slot and block height. 
Example: A transaction received during slot S referencing the blockhash of slot S-153 should not expire if 4 slots were skipped in-between (which is common), because the block height difference is 149 only.
The result is that many transactions are wrongly ignored by a leader if there were skips during last 151 slots.

[The offending code](https://github.com/firedancer-io/firedancer/blob/e97dd839818a30be7a22a3c1c28bcfcaa567e192/src/discoh/resolv/fd_resolv_tile.c#L394-L403).

A similar check is done in [pack](https://github.com/firedancer-io/firedancer/blob/e97dd839818a30be7a22a3c1c28bcfcaa567e192/src/disco/pack/fd_pack_tile.c#L37-L41), but this time including some arbitrary margin to cope with block height/slot difference.

* A simple fix would be to replace 151 in `resolv` with this `TRANSACTION_LIFETIME_SLOTS` constant, but it's not satisfactory. 

* I would personally remove these imperfect expiration checks in both `resolv` and `pack` and rely only on checks done in `bank`. 
If these checks are security barriers, then they don't hold long. An attacker could clutter pack with transactions that won't land using other ways. During normal operation, transactions not being forwarded anymore, the number of expired txs is not high.

* Another option is to have `bank` send the true block height along with the block hash and use it for expiration checks.

If you are interested, I can post a PR implementing the option you think is best.

---

## #6997 — backtest watch feature hides important error messages
- **URL:** https://github.com/firedancer-io/firedancer/issues/6997
- **Created:** 2025-10-30 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** mmcgee-jump

The 'watch' feature regresses dev UX sometimes because it drops important log messages

without `--no-watch`

```
NOTICE  10-30 17:49:53.066822 684837 f0   main src/app/shared/commands/configure/configure.c(86): vinyl ... unconfigured ... `/data/r/vinyl` needs to be resized (have 85899345920 bytes, want 10737418240 bytes)
NOTICE  10-30 17:49:53.066832 684837 f0   main src/app/shared/commands/configure/configure.c(103): vinyl ... configuring
Aborted
```

with `--no-watch`

```
NOTICE  10-30 17:51:39.203949 685151 f0   main src/app/shared/commands/configure/configure.c(86): vinyl ... unconfigured ... `/data/r/vinyl` does not exist
NOTICE  10-30 17:51:39.203958 685151 f0   main src/app/shared/commands/configure/configure.c(103): vinyl ... configuring
NOTICE  10-30 17:51:39.222750 685151 f0   main src/disco/topo/fd_topo_run.c(359): running single threaded topology with 15 tiles and 93 GiB memory
CRIT    10-30 17:51:39.225395 685181 13   snapin:0 src/disco/topo/fd_topo.c(17): invalid obj_id ULONG_MAX
NOTICE  10-30 17:51:39.225599 685178 10   snapct:0 src/discof/restore/fd_snapct_tile.c(450): reading full snapshot from local file `/data/r/firedancer/dump/local-multi-boundary/snapshot-1175-3bzwLh1Bfoh9g4a5bd6gvRydYUtCTxctmSNHse6UEWcw.tar.zst`
ERR     10-30 17:51:39.225898 685181 13   snapin:0 src/util/log/fd_log.c(1036): Received signal SIGABRT-Aborted
/data/r/firedancer/build/native/gcc/bin/firedancer-dev(+0x8b01b4) [0x555555e041b4
```

---

## #6996 — Dedup snapshot loader topology definition
- **URL:** https://github.com/firedancer-io/firedancer/issues/6996
- **Created:** 2025-10-30 by @ripatel-fd
- **Updated:** 2026-01-14

The snapshot loader topology is pretty complex now (7 different tiles, >7 link kinds, many more objects) 

We have 3 nearly identical constructors of this topology in topology.c, backtest.c, and snapshot-load.c.
Deduplicate them

---

## #6750 — progcache: chaos tests
- **URL:** https://github.com/firedancer-io/firedancer/issues/6750
- **Created:** 2025-10-14 by @ripatel-fd
- **Updated:** 2025-11-14

---

## #6609 — Doublezero not working if connected after validator start
- **URL:** https://github.com/firedancer-io/firedancer/issues/6609
- **Created:** 2025-10-05 by @HGuillemet
- **Updated:** 2026-06-10

At the time of writing, 1/3 of all Firedancers connected to Doublezero cannot receive any packet from other Doublezero validators.
I tested this by trying to connect to their TPU from another Doublezero-connected machine.

This happens when `doublezero connect` is executed while Firedancer is already running.

---

## #6576 — Write proper gossip / CH indexer
- **URL:** https://github.com/firedancer-io/firedancer/issues/6576
- **Created:** 2025-10-01 by @mmcgee-jump
- **Updated:** 2026-03-17
- **Assignees:** mmcgee-jump

---

## #6542 — trim txncache memory use
- **URL:** https://github.com/firedancer-io/firedancer/issues/6542
- **Created:** 2025-09-29 by @mmcgee-jump
- **Updated:** 2026-03-17

We can cut memory in half by only reserving 2*MAX_TXN_PER_SLOT for rooted slots, others don't need the raised limit

---

## #6361 — Remove `FD_RUNTIME_INITIAL_BLOCK_ID`
- **URL:** https://github.com/firedancer-io/firedancer/issues/6361
- **Created:** 2025-09-13 by @mmcgee-jump
- **Updated:** 2026-06-10
- **Labels:** security
- **Assignees:** emwang-jump

```
/* The initial block id hash is a dummy value for the initial block id
   as one is not provided in snapshots.  This does not have an
   equivalent in Agave.

   TODO: This should be removed in favor of repairing the last shred of
   the snapshot slot to get the actual block id of the snapshot slot. */

#define FD_RUNTIME_INITIAL_BLOCK_ID (0xF17EDA2CE7B1DUL)
```

block id in snapshot will be in agave 4.1

---

## #6280 — bank,tower: maybe_retransmit_unpropagated_slots
- **URL:** https://github.com/firedancer-io/firedancer/issues/6280
- **Created:** 2025-09-08 by @mmcgee-jump
- **Updated:** 2026-03-25
- **Assignees:** lidatong

Prevents us becoming leader again if our previous leader rotation didn't propagate to 1/3 of the cluster, to prevent a deep side fork, creates deep lockouts

---

## #6222 — Cannot run fdctl without logs
- **URL:** https://github.com/firedancer-io/firedancer/issues/6222
- **Created:** 2025-09-01 by @ripatel-fd
- **Updated:** 2025-11-14

```
$ build/native/gcc/bin/fdctl mem --config bundle_test.toml --log-path ''
Log at "/tmp/fd-0.101.20306_2374700_ripatel_gusc1c-ossdev-firedancer66_2025_09_01_13_29_06_403378734_GMT+00"
ERR     09-01 13:29:06.403762 2374700 f0   main src/app/shared/boot/fd_boot.c(318): unknown argument `--log-path`
```

---

## #6113 — Negative solfuzz fixture test
- **URL:** https://github.com/firedancer-io/firedancer/issues/6113
- **Created:** 2025-08-20 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** ripatel-fd

Add integration test that ensures that a solfuzz fixture mismatch has a non-zero return code

---

## #6112 — Negative fd_ledger test
- **URL:** https://github.com/firedancer-io/firedancer/issues/6112
- **Created:** 2025-08-20 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** kbhargava-jump

Add integration test that ensures that a CI ledger failure has a non-zero return code

---

## #6082 — snapshots: add 'manifest only' mode
- **URL:** https://github.com/firedancer-io/firedancer/issues/6082
- **Created:** 2025-08-18 by @ripatel-fd
- **Updated:** 2026-01-14
- **Assignees:** cali-jumptrading

Extend the snapshot tile arguments (in topo) to support a 'manifest only' mode. 

The manifest only mode should shut down snapshot tiles as soon as the manifest was published.

This is useful for dev commands that require epoch stakes but not accounts.

---

## #6038 — gcc + UBSAN leads to build issues
- **URL:** https://github.com/firedancer-io/firedancer/issues/6038
- **Created:** 2025-08-13 by @two-heart
- **Updated:** 2025-11-14
- **Assignees:** ptaffet-jump

Multiple people reported issues with building with the ubsan extra using gcc.
For any sanitizer clang typically has the more precise and well supported version.
But we should either fix these build errors, or early fail clearly stating that we don't support gcc + ubsan.

Reproducer:
```
gcc version 13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04) 
```
(clean) build with
```
MACHINE=linux_gcc_icelake make -j all
```
works
```
MACHINE=linux_gcc_icelake EXTRAS="ubsan" make -j -k all
```
reports a multiple errors
```
...
In file included from /usr/include/stdio.h:980,
                 from src/util/log/fd_log.c:25:
In function ‘sprintf’,
    inlined from ‘fd_log_private_hexdump_msg’ at src/util/log/fd_log.c:737:5:
/usr/include/x86_64-linux-gnu/bits/stdio2.h:30:10: error: null destination pointer [-Werror=format-overflow=]
   30 |   return __builtin___sprintf_chk (__s, __USE_FORTIFY_LEVEL - 1,
      |          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   31 |                                   __glibc_objsize (__s), __fmt,
      |                                   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   32 |                                   __va_arg_pack ());
      |                                   ~~~~~~~~~~~~~~~~~
In function ‘sprintf’,
    inlined from ‘fd_log_private_hexdump_msg’ at src/util/log/fd_log.c:740:3:
/usr/include/x86_64-linux-gnu/bits/stdio2.h:30:10: error: null destination pointer [-Werror=format-overflow=]
   30 |   return __builtin___sprintf_chk (__s, __USE_FORTIFY_LEVEL - 1,
      |          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   31 |                                   __glibc_objsize (__s), __fmt,
      |                                   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   32 |                                   __va_arg_pack ());
      |                                   ~~~~~~~~~~~~~~~~~
src/disco/topo/fd_topob.c: In function ‘fd_topob_new’:
src/disco/topo/fd_topob.c:26:3: error: ‘__builtin_strncpy’ specified bound 256 equals destination

_(truncated)_

---

## #6025 — pack tile crank flood
- **URL:** https://github.com/firedancer-io/firedancer/issues/6025
- **Created:** 2025-08-12 by @ripatel-fd
- **Updated:** 2026-03-17
- **Assignees:** ptaffet-jump

Running `fddev` with the following config and a bundle test service causes pack to flood the local chain with crank transactions. 

```
[tiles.bundle]
enabled = true
url = "http://127.0.0.1:50051"
tip_distribution_program_addr = "F2Zu7QZiTYUhPd7u9ukRVwxh7B71oA3NMJcHuCHc29P2"
tip_payment_program_addr = "GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy"
tip_distribution_authority = "B1mrQSpdeMU9gCvkJ6VsXVVoYjRGkNA7TtjMyqxrhecH"

[tiles.gui]
enabled = true
```

---

## #5978 — [bundle] support endpoint discovery
- **URL:** https://github.com/firedancer-io/firedancer/issues/5978
- **Created:** 2025-08-08 by @ripatel-fd
- **Updated:** 2025-11-14

https://github.com/jito-labs/mev-protos/commit/46ead86a13a55a0ef2c139db96a8ee93bf7505e3

---

## #5837 — Snapshots missing feature activation status
- **URL:** https://github.com/firedancer-io/firedancer/issues/5837
- **Created:** 2025-07-28 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** kbhargava-jump

TLDR: Solana snapshot/RocksDB ledgers used for regression testing lack information required for clients to determine if their software version (feature gate set) is able to replay. This is due to missing feature accounts for activated (and optionally hardcoded) features.

Solana typically uses feature program accounts to signal activations of features (breaking protocol changes).
Live clusters keep an invariant that a feature account is created before the corresponding feature is activated. 

When restoring execution state from a snapshot, these feature accounts determine which features get reactivated.

Additionally, Agave and Firedancer have a concept of feature "hardcoding" or "cleanup". 
When a feature is "cleaned up" on a client version, that client loses the ability to execute blocks with that feature _deactivated_.

A client can check whether it is compatible with a specific ledger is as follows:
- Ensure that all "cleaned up" features on a client version have activated feature accounts on the ledger being replayed
- Ensure that all other activated feature accounts on that ledger are known/supported on the client version

The issue arises when a feature gets "cleaned up" but a feature account does not get created. This is currently the case due to bugs in the agave-ledger-tool "create-snapshot" command: `activate-feature` is not supported, and https://github.com/anza-xyz/agave/issues/7087 

Older versions might still think they are compatible (there are no activated feature accounts that the old client does not support), but would encounter bank hash mismatches when replaying. It is preferable to crash cleanly than to emit a rogue BHM.

---

## #5614 — fddev flame doesn't work on Ubuntu
- **URL:** https://github.com/firedancer-io/firedancer/issues/5614
- **Created:** 2025-07-10 by @ripatel-fd
- **Updated:** 2025-11-14

Most of our operators use Ubuntu, would be nice to have a proper flamegraph solution for Debian. 
the `perf script flamegraph` package seems to be Fedora only

---

## #5490 — Clean up net tile flow steering
- **URL:** https://github.com/firedancer-io/firedancer/issues/5490
- **Created:** 2025-06-28 by @ripatel-fd
- **Updated:** 2026-03-31
- **Assignees:** ripatel-fd

sock, xdp, and ibeth tiles redundantly look for hardcoded link names and port numbers. 
To make the network stack parts more reusable, they should just map port numbers to RX/TX topo link IDs.

---

## #5240 — Remove fd_quic_conn_tx
- **URL:** https://github.com/firedancer-io/firedancer/issues/5240
- **Created:** 2025-06-01 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** ripatel-fd

fd_quic currently uses a two-step receive and transmit model.

```
fd_quic_process_packet();
// ... buffers up information about a received packet

fd_quic_conn_tx();
// ... traverses all buffered information and crafts a packet
```

However, it results in additional complexity like [fd_quic_tx_enc_level](https://github.com/firedancer-io/firedancer/blob/eece8113f6c2cb70d1e24d91976e15148fbed67d/src/waltz/quic/fd_quic.c#L823), which is error prone.

Consider generating response frames ASAP in the RX handler instead.
Doing that reduces code complexity and could reduce state size. 
Some tests currently assume that the RX handler never issues TX callbacks, that will have to be fixed.

---

## #5190 — resolv: seccomp policy integration test
- **URL:** https://github.com/firedancer-io/firedancer/issues/5190
- **Created:** 2025-05-26 by @ripatel-fd
- **Updated:** 2025-11-14

Write test harnesses that hit all syscalls done by fd_getaddrinfo.
Ensure that these don't crash if executed under the bundle tile's seccomp policy.

---

## #5186 — [QUIC] CRYPTO stream reorder buffer
- **URL:** https://github.com/firedancer-io/firedancer/issues/5186
- **Created:** 2025-05-24 by @ripatel-fd
- **Updated:** 2025-11-14

quic-go clients deliberately reorder CRYPTO frames within a packet: [discussion](https://github.com/quic-go/quic-go/pull/5107#issuecomment-2906937841)

Two options:

- Add another rule to Solana's QUIC dialect to ban this behavior analogous to how we did with STREAM fragmentation rules.
- Add support for handshake data reordering to fd_quic.

---

## #5173 — Switch to mbedTLS
- **URL:** https://github.com/firedancer-io/firedancer/issues/5173
- **Created:** 2025-05-22 by @riptl
- **Updated:** 2026-03-17

Ditch OpenSSL and switch to mbedTLS for the snapshot downloader and bundle client.

Potentially delete fd_tls and also use MbedTLS for the QUIC server.

MbedTLS aligns better with Firedancer's coding practices and sandboxing model.

---

## #5163 — Enable authorized voter to be added via admin interface
- **URL:** https://github.com/firedancer-io/firedancer/issues/5163
- **Created:** 2025-05-21 by @bartenbach
- **Updated:** 2025-11-14

I’d like to propose a feature that would significantly improve security for validator operators: a CLI-based admin interface to configure the authorized voter(s).

IE
`fdctl authorized-voter add identity.json`

I have outlined the process for this (using Agave) here: https://pumpkins-pool.gitbook.io/pumpkins-pool/keyless-operation

**Problem**

Currently, F(ire|ranken)dancer requires the authorized voter keypair(s) be physically present on the server’s filesystem. This poses a security risk - particularly on bare metal servers hosted by third-party providers - as any compromise of that machine exposes those critical keys.

Agave addresses this (whether intentionally or accidentally) by allowing operators to remotely set the identity and authorized voter via a secure socket (e.g., over SSH), storing the keys only in memory. This avoids ever having sensitive key material written to disk.

**Proposal**

Implement a CLI-admin interface in Firedancer that allows:
	•	Assignment of the authorized voter

**Benefits**
	•	Greatly improved security posture, reducing the attack surface for validator keys
	•	Supports best practices for key custody (single local encrypted location, no persistent disk storage on remote machines)

![Image](https://github.com/user-attachments/assets/046ae453-3579-4657-ac5f-9ec8b57a5305)

---

## #5098 — Allow overriding config options via command-line
- **URL:** https://github.com/firedancer-io/firedancer/issues/5098
- **Created:** 2025-05-12 by @ripatel-fd
- **Updated:** 2025-11-14

```
fddev --hugetlbfs.max_page_size huge ...
```

---

## #5093 — [MSan] Unit tests / fuzz regtests in CI
- **URL:** https://github.com/firedancer-io/firedancer/issues/5093
- **Created:** 2025-05-12 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** Priority: High
- **Assignees:** ripatel-fd

---

## #5092 — [MSan] Solfuzz support
- **URL:** https://github.com/firedancer-io/firedancer/issues/5092
- **Created:** 2025-05-12 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** Priority: High
- **Assignees:** ripatel-fd

---

## #4905 — fd_topob unit tests
- **URL:** https://github.com/firedancer-io/firedancer/issues/4905
- **Created:** 2025-04-29 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** ripatel-fd

Topology construction code is almost entirely unit tested, but essential for performance (e.g. NUMA affinity)

---

## #4647 — Config should warn if tiles.net.interface is set in socket mode
- **URL:** https://github.com/firedancer-io/firedancer/issues/4647
- **Created:** 2025-03-27 by @ripatel-fd
- **Updated:** 2026-03-31
- **Assignees:** ripatel-fd

The socket tile silently ignores the interface hint.
Could be confusing to operators.

---

## #4630 — Checksec CI integration
- **URL:** https://github.com/firedancer-io/firedancer/issues/4630
- **Created:** 2025-03-25 by @nlgripto
- **Updated:** 2025-11-14
- **Labels:** security
- **Assignees:** ripatel-fd

https://github.com/asymmetric-research/checksec-action/tree/main

feel free to reassign to me or @marcograss

---

## #4591 — heap_verify fails if two elements with the same key are inserted
- **URL:** https://github.com/firedancer-io/firedancer/issues/4591
- **Created:** 2025-03-20 by @ripatel-fd
- **Updated:** 2025-11-14

bug in fd_heap.c

```
HEAP_TEST( HEAP_(lt)( pool + i, pool + l ) ); /* Make sure heap property satisfied */
```

---

## #4580 — Add XDP/socket hybrid mode
- **URL:** https://github.com/firedancer-io/firedancer/issues/4580
- **Created:** 2025-03-19 by @ripatel-fd
- **Updated:** 2025-11-14

Net mode where XDP serves as a fast receive path, sockets serve as a generic fallback.

---

## #4574 — Use long for timestamps in fd_quic
- **URL:** https://github.com/firedancer-io/firedancer/issues/4574
- **Created:** 2025-03-19 by @ripatel-fd
- **Updated:** 2026-06-10

---

## #4540 — fdctl mem does a user check
- **URL:** https://github.com/firedancer-io/firedancer/issues/4540
- **Created:** 2025-03-17 by @ripatel-fd
- **Updated:** 2025-11-14

```
$ fdctl mem --config /data/etc/fd_config.toml
src/app/fdctl/config.c(590): running as uid 1009, but config specifies uid 1003
```

---

## #4444 — [net 2.0] Reverse path filtering
- **URL:** https://github.com/firedancer-io/firedancer/issues/4444
- **Created:** 2025-03-10 by @ripatel-fd
- **Updated:** 2026-04-06
- **Assignees:** ripatel-fd

The net tile currently accepts traffic for all dst IPs. 
Should be filtered according to route table, possibly with rp_filter.

Implementation notes:
- [ ] Add a new fib4 containing only local routes  (fib_local)
- [ ] Add optional fib4 filter for reverse path (eliminate local routes that don't meet criteria for rp_filter) 
- [ ] Add config option for reverse path filter
- [ ] Install fib_local to RX path

---

## #4436 — [net 2.0] Don't hardcode addresses
- **URL:** https://github.com/firedancer-io/firedancer/issues/4436
- **Created:** 2025-03-09 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** Priority: Low

Modify fd_xdp_tile.c to read the MAC address and fallback source IP from the interface table (MIB), instead of hardcoding it on startup

---

## #4428 — Auto affinity fails for offline CPUs`
- **URL:** https://github.com/firedancer-io/firedancer/issues/4428
- **Created:** 2025-03-08 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** mmcgee-jump

```
$ echo 0 | sudo tee /sys/devices/system/cpu/cpu10/online
$ build/native/gcc/bin/fddev
...
ERR     03-08 20:48:42.163545 815486 f0   pidns src/app/fdctl/run/run.c(200): Unable to set the thread affinity for tile sign:0 on cpu 10. It is likely that the affinity you have specified for this tile in [layout.affinity] of your configuration file contains a CPU (10) which does not exist on this machine.
```

---

## #4341 — ibverbs tile
- **URL:** https://github.com/firedancer-io/firedancer/issues/4341
- **Created:** 2025-02-28 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** Priority: Low
- **Assignees:** ripatel-fd

Use libibverbs in 'raw packet' / Ethernet mode for high performance mlx5 operation

Low priority R&D item

---

## #4296 — CLI should not require config file for running validators
- **URL:** https://github.com/firedancer-io/firedancer/issues/4296
- **Created:** 2025-02-25 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** mmcgee-jump

**Problem**

fdctl has several CLI commands used to interact with a running validator like "monitor" or "set-identity".

Currently, these commands need to be provided with the same config file as the running validator.

This results in confusing error messages in the following scenarios
- CLI command spawned without a `--config` flag
- Config file changed after validator was started

**Expected Behavior**

Only `fdctl run` should require a `--config` flag. All auxiliary commands should discover the production validator config automatically.

---

## #4254 — Quic: Instant ACK if packet number gap
- **URL:** https://github.com/firedancer-io/firedancer/issues/4254
- **Created:** 2025-02-18 by @akhinvasara-jumptrading
- **Updated:** 2026-06-10
- **Labels:** quic

Spec says we should immediately ACK if there's a packet number gap. We don't do that yet. 

```
In order to assist loss detection at the sender, an endpoint SHOULD generate and send an ACK frame without delay when it receives an ack-eliciting packet either:

- when the received packet has a packet number less than another ack-eliciting packet that has been received, or
- when the packet has a packet number larger than the highest-numbered ack-eliciting packet that has been received and there are missing packets between that packet and this packet.

```

https://www.rfc-editor.org/rfc/rfc9000.html#section-13.2.1-7

---

## #4252 — Revive test_dedup
- **URL:** https://github.com/firedancer-io/firedancer/issues/4252
- **Created:** 2025-02-18 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** Priority: Low

src/disco/dedup/test_dedup.c was commented out after the stem-ification of the dedup tile

---

## #4214 — Fix fddev netns (network namespaces)
- **URL:** https://github.com/firedancer-io/firedancer/issues/4214
- **Created:** 2025-02-13 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** Priority: Low
- **Assignees:** ripatel-fd

This feature is untested and broken

---

## #4192 — Export netlink interface stats to Prometheus metrics
- **URL:** https://github.com/firedancer-io/firedancer/issues/4192
- **Created:** 2025-02-11 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** ripatel-fd

---

## #4126 — Fix issue where GUI sankey shows occasional -1s due to unaligned counts
- **URL:** https://github.com/firedancer-io/firedancer/issues/4126
- **Created:** 2025-02-07 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** Priority: Medium, operator, gui
- **Assignees:** jherrera-jump

All of the tiles sample metrics at random intervals in housekeeping (METRICS_WRITE). The problem is that, when the GUI snaps transaction counts, it might see an updated sample from one tile, but a not-updated sample from another.

Suggested fix is probably just to align the METRICS_WRITE intervals on the relevant tiles so they happen at the same time. You might want to modify `fd_stem.c` with a new `FIXED_METRICS_WRITE_INTERVAL` or something, so other tiles can keep the existing behavior.

---

## #3994 — QUIC Conformance test for PING
- **URL:** https://github.com/firedancer-io/firedancer/issues/3994
- **Created:** 2025-01-22 by @nbridge-jump
- **Updated:** 2025-11-14
- **Labels:** quic, Priority: Medium

Need to add a conformance test to ensure PING is working correctly

---

## #3962 — http: return error response rather than closing connection
- **URL:** https://github.com/firedancer-io/firedancer/issues/3962
- **Created:** 2025-01-15 by @mmcgee-jump
- **Updated:** 2026-03-17
- **Labels:** Priority: Medium, debugging, operator
- **Assignees:** jherrera-jump

Will help operators debug configuration / proxying issues much easier.

---

## #3792 — Ignore SCID changes in Initial Packets
- **URL:** https://github.com/firedancer-io/firedancer/issues/3792
- **Created:** 2024-12-27 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** quic

fd_quic doesn't enforce this rule:

> Once a client has received a valid Initial packet from the server, it MUST discard any subsequent packet it receives on that connection with a different Source Connection ID.
...
Any further changes to the Destination Connection ID are only permitted if the values are taken from NEW_CONNECTION_ID frames; if subsequent Initial packets include a different Source Connection ID, they MUST be discarded. This avoids unpredictable outcomes that might otherwise result from stateless processing of multiple Initial packets with different Source Connection IDs.

Should be fixed

---

## #3791 — Respond to QUIC path challenges
- **URL:** https://github.com/firedancer-io/firedancer/issues/3791
- **Created:** 2024-12-27 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** quic

fd_quic currently ignores PATH_CHALLENGE frames.
This is a potential source of conn failures since TPU clients might require a path challenge before sending stream data.

---

## #3618 — net 2.0: AF_XDP preferred busy polling
- **URL:** https://github.com/firedancer-io/firedancer/issues/3618
- **Created:** 2024-12-04 by @ripatel-fd
- **Updated:** 2026-06-03
- **Labels:** perf, Priority: Medium

Tracking issue for the net tile rewrite.

Ships the following features:
- [ ] AF_XDP busy polling support (to reduce ksoftirqd) load
- [x] Removal of xsk_aio
- [x] Zero copy support
- [x] Faster TX path

---

## #3615 — Add quic agave-compat test to CI
- **URL:** https://github.com/firedancer-io/firedancer/issues/3615
- **Created:** 2024-12-04 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** quic, testing

Need to continuously ensure that our QUIC client and server stays compatible with Agave

By building contrib/quic/agave_compat and running the ping-client and ping-server tests

---

## #3525 — QUIC client API should use opaque handles
- **URL:** https://github.com/firedancer-io/firedancer/issues/3525
- **Created:** 2024-11-22 by @ripatel-fd
- **Updated:** 2026-06-10
- **Labels:** quic, Priority: Low

fd_quic_connect should return a stable/unique conn identifier instead of a pointer

---

## #3510 — QUIC should only time out clients if the conn table is full
- **URL:** https://github.com/firedancer-io/firedancer/issues/3510
- **Created:** 2024-11-21 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** quic, Priority: Low

- Advertise an idle_timeout of zero
- Never time out clients below a certain conn table load factor

---

## #3505 — Document GUI reverse proxy setup
- **URL:** https://github.com/firedancer-io/firedancer/issues/3505
- **Created:** 2024-11-20 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** operator

Putting the GUI behind a NGINX reverse proxy without further config doesn't work.
The GUI will try to make insecure WebSocket requests. Either allow the GUI to do secure WebSockets requests or document how to inject `content-security-policy: upgrade-insecure-requests`

---

## #3476 — Reproduce and triage LLVM memcpy sz==0 bug
- **URL:** https://github.com/firedancer-io/firedancer/issues/3476
- **Created:** 2024-11-18 by @ripatel-fd
- **Updated:** 2025-11-14
- **Assignees:** ripatel-fd

Create a minimal reproducible example for the memcpy sz==0 bug and report it to LLVM

---

## #3464 — fdctl metadata descriptors (fd_pod) for better object discovery
- **URL:** https://github.com/firedancer-io/firedancer/issues/3464
- **Created:** 2024-11-16 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** Priority: Low

**Problem**

Joining shared memory objects of a production fdctl instance is excessively difficult. 

Object discovery currently involves recreating all setup steps (parsing a config file, constructing the topology, and simulating tile initialization code to recover object offsets). It also breaks across different versions.

**Suggested Fix**

Use fd_pod or similar to place "directories" at known locations of workspaces, so that objects can be easily discovered.

---

## #3463 — Support DPDK PMDs
- **URL:** https://github.com/firedancer-io/firedancer/issues/3463
- **Created:** 2024-11-16 by @ripatel-fd
- **Updated:** 2026-04-11
- **Labels:** perf, Priority: Low
- **Assignees:** ripatel-fd

The DPDK project includes a collection of open-source userspace network drivers.
These are possible alternatives to AF_XDP.

Intel i40e and ice devices in particular provide a promising end-to-end solution for userspace networking while sharding hardware with the host. Intel Flow Director is a replacemenet for the XDP_REDIRECT program we use, and an Intel Virtual Function NIC via vfio-pci is a replacement for the AF_XDP API.

An example of how DPDK PMDs can be integrated into a separate repo is here: https://github.com/FDio/vpp/blob/80ae7e5307fc73077c6291ccfd2f5bf4888ca5e1/src/plugins/dpdk/device/common.c#L293

Thanks to @leoluk for the pointers.

---

## #3339 — Add an option for `make asm` Intel syntax
- **URL:** https://github.com/firedancer-io/firedancer/issues/3339
- **Created:** 2024-11-06 by @ripatel-fd
- **Updated:** 2025-11-14

Some developers prefer Intel assembly syntax, when using `make asm` to review generated code

---

## #3113 — CodeQL lint for implicit integer truncation
- **URL:** https://github.com/firedancer-io/firedancer/issues/3113
- **Created:** 2024-10-12 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** linting, Priority: Low

Implicit integer conversions to a shorter type, such as ulong to ushort, can cause compile failures. 

Under `-Werror=all`, GCC 8.3 does not even allow `uchar x[2] = {3,4}`; (3 gets promoted to int, then converted to char)

GCC 8.5 is less strict but often broken on main. GCC 12 is least strict, but effectively the default compiler of the Firedancer development team.

We can use CodeQL to detect all such implicit conversions without having to rely on compiler warnings.

---

## #2567 — Check file permissions in fd_keyload_load
- **URL:** https://github.com/firedancer-io/firedancer/issues/2567
- **Created:** 2024-08-01 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** operator

OpenSSH refuses to load private keys with too open permissions (e.g. world-readable).
This forces operators to at least minimally protect their keys.

We might want to do this in fd_keyload_load too.

---

## #2554 — fd_keyload_load should check that keypair matches
- **URL:** https://github.com/firedancer-io/firedancer/issues/2554
- **Created:** 2024-07-31 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** security, Priority: Medium

Ed25519 security breaks down when signing messages with a public key that doesn't match the private key.
Loading certain key files can result in compromise of the private key.

This can happen due to user error (e.g. user uses a broken script to turn a private key into a JSON key file).
And should thus be fixed.

---

## #2466 — Wait until all tiles finished privileged_init before entering run loop
- **URL:** https://github.com/firedancer-io/firedancer/issues/2466
- **Created:** 2024-07-19 by @ripatel-fd
- **Updated:** 2026-03-31
- **Labels:** security
- **Assignees:** mmcgee-jump

---

## #2353 — [util] Improve validation in MAP_(remove)
- **URL:** https://github.com/firedancer-io/firedancer/issues/2353
- **Created:** 2024-07-09 by @0x0ece
- **Updated:** 2025-11-14
- **Labels:** security, Priority: Low

`map_remove` doesn't validate that `entry` (still) is a valid entry in the map. 
Removing an entry twice can lead to an underflow of `key_cnt` and passing an invalid entry can lead to an OOB write.

Current callers seem fine, but I think the quic connection / stream handling code is complex enough that a double free of a connection or stream entry could happen.

I think validating the entry and crashing if it's invalid would be a nice defense-in-depth addition. 

```
static inline void
MAP_(remove)( MAP_T * map,
              MAP_T * entry ) {
  MAP_(private_t) * hdr = MAP_(private_from_slot)( map );

  /* FIXME: CONSIDER VALIDATING KEY_CNT AND/OR ENTRY ISN'T VALID */
  hdr->key_cnt--;

  ulong slot_mask = hdr->slot_mask;
  ulong slot      = MAP_(slot_idx)( map, entry );
```

---

## #2352 — [fd-mux] Handling of cross-tile shared memory may lead to OOB read
- **URL:** https://github.com/firedancer-io/firedancer/issues/2352
- **Created:** 2024-07-09 by @0x0ece
- **Updated:** 2025-11-14
- **Labels:** security, Priority: Low
- **Assignees:** mmcgee-jump

In fd_mux_tile (src/disco/mux/fd_mux.c), it appears a compromised tile could cause an out-of-bounds read in another tile (e.g. if you achieved remote code execution the quic tile, you may be able to make the verify tile read out-of-bounds memory):

```
ulong depth    = fd_mcache_depth( this_in->mcache ); min_in_depth = fd_ulong_min( min_in_depth, depth );  
if( FD_UNLIKELY( depth > UINT_MAX ) ) { FD_LOG_WARNING(( "in_mcache[%lu] too deep", in_idx )); return 1; }  
this_in->depth = (uint)depth;  
this_in->idx   = (uint)in_idx;  
this_in->seq   = fd_mcache_seq_query( this_in_sync ); /* FIXME: ALLOW OPTION FOR MANUAL SPECIFICATION? */  
this_in->mline = this_in->mcache + fd_mcache_line_idx( this_in->seq, this_in->depth );  
```
The depth variable is set from the underlying shared memory for the input workspace. Note there's a bounds check to ensure that the depth is less than UINT_MAX (4GB). The fd_mcache_line_idx function can return a value between [0,depth). Since the workspace shared memory mapping is 1GB (e.g. for fd1_quic_verify.wksp), this looks like it could result in an mline value that points out of bounds.

In certain scenarios, OOB read issues like this may lead to cross-tile information leak or other undefined behavior.

---

## #2300 — Let 'fdctl configure' set up smp_affinity
- **URL:** https://github.com/firedancer-io/firedancer/issues/2300
- **Created:** 2024-07-03 by @ripatel-fd
- **Updated:** 2026-03-31
- **Labels:** perf, fdctl
- **Assignees:** ripatel-fd

Relates to #2297 

A default configuration Fedora 40 will clumsily schedule ksoftirqd processes onto the same CPUs as Firedancer tiles. 

This is mostly not noticeable but can lead to sporadic drops in performance at high packet rates (>15Mpps)

We should teach `fdctl configure` to adapt the smp_affinity sysfs knob to forbid such IRQs from running on any Firedancer-assigned CPUs.

---

## #2298 — Handle multiple RX channels per net tile
- **URL:** https://github.com/firedancer-io/firedancer/issues/2298
- **Created:** 2024-07-03 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** perf, fdctl
- **Assignees:** ripatel-fd

On i40e (Intel X710 class NICs), the AF_XDP kernel side running in ksoftirqd is considerably more expensive than the userspace fd_xsk code.

fd_xsk can forward at least ~28Mpps from 3 AF_XDP rings to an mcache on one EPYC 7502P core.
But the kernel requires about ~3 cores running ksoftirqd to fill the same AF_XDP rings from the network device queues.

Therefore, a 1:1 mapping between tiles and rings is wasteful. 
And reducing the ring count can lead to performance issues because of insufficient ksoftirqd time.

---

## #2297 — Warn if IRQ overlaps with fixed tile assignments
- **URL:** https://github.com/firedancer-io/firedancer/issues/2297
- **Created:** 2024-07-03 by @ripatel-fd
- **Updated:** 2026-04-06
- **Labels:** Priority: Low

Any tile with a fixed CPU assignment will use 100% time share of that CPU. 

This can cause issues if a IRQ/soft-IRQ is scheduled on the same core. 
irqbalance seems to be not very smart and occasionally reassigns net channels on Firedancer-reserved CPUs even if there are lots of other CPUs free.

We should start by printing a warning to the user if the smp_affinity mask is set incorrectly.

---

## #2070 — Use memfd_create and fexecve to run tiles with no memory overlap
- **URL:** https://github.com/firedancer-io/firedancer/issues/2070
- **Created:** 2024-06-11 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** security, fdctl

Running the fdctl binary from disk will map certain sections of memory shared with other tiles (eg, .TEXT). We want to prevent any memory being shared at all.

---

## #1933 — Missing pre-image checks for shreds in keyguard / keyguard finishing touches
- **URL:** https://github.com/firedancer-io/firedancer/issues/1933
- **Created:** 2024-05-23 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** Priority: High
- **Assignees:** ptaffet-jump

fd_keyguard does not verify that the pre-image of Merkle shreds is valid and unambiguous with other inputs.

The shred tile could thus sign 
- gossip pings
- repair pings
- any arbitrary 32 byte message

This is currently not a very severe issue, but it defeats the purpose of the ambiguity checks.

---

## #1883 — Ensure memory consumption is minimal
- **URL:** https://github.com/firedancer-io/firedancer/issues/1883
- **Created:** 2024-05-16 by @mmcgee-jump
- **Updated:** 2026-03-31
- **Assignees:** ibhatt-jumptrading

Audit link and buffer sizes to ensure everything is minimal for 1M.

---

## #1830 — Support retiring connection IDs in QUIC
- **URL:** https://github.com/firedancer-io/firedancer/issues/1830
- **Created:** 2024-05-10 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** quic, Priority: Low

- [ ] Add implied retiring in NEW_CONN_ID frame
- [ ] Support RETIRE_CONN_ID frame

---

## #1768 — Add comprehensive QUIC DOS testing
- **URL:** https://github.com/firedancer-io/firedancer/issues/1768
- **Created:** 2024-05-08 by @mmcgee-jump
- **Updated:** 2026-06-10
- **Labels:** Priority: High

---

## #1496 — Consider using memfd_secret for signer secret
- **URL:** https://github.com/firedancer-io/firedancer/issues/1496
- **Created:** 2024-04-12 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** security, Priority: Medium
- **Assignees:** mmcgee-jump

Use memfd_secret to store the node's private key

Not supported on all kernels, so needs a fallback 

https://lwn.net/Articles/865256/

---

## #1495 — Add comprehensive unit tests for tiles
- **URL:** https://github.com/firedancer-io/firedancer/issues/1495
- **Created:** 2024-04-12 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** Priority: Medium, testing

---

## #1481 — Add latency metrics for TPU
- **URL:** https://github.com/firedancer-io/firedancer/issues/1481
- **Created:** 2024-04-11 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** perf, Priority: Low, operator

We want to log txn latency through the TPU pipeline, until bank, where txn may get held. From there, we can record latency again from bank -> shred.

---

## #1456 — fddev flame doesn't show kernel time
- **URL:** https://github.com/firedancer-io/firedancer/issues/1456
- **Created:** 2024-04-05 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** perf, Priority: Low, debugging

if the thread is in WAITING state in kernel due a futex etc, I think our perf invocation does not record this time

---

## #1389 — Prevent duplicate slot / shred ever being published
- **URL:** https://github.com/firedancer-io/firedancer/issues/1389
- **Created:** 2024-03-27 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** Priority: High, consensus, operator
- **Assignees:** mmcgee-jump

We need a durable slot / leader store variable to ensure that when the validator is restarted, we don't publish in the same leader slot as we have before.

We also potentially need to survive a reboot. In that case, we could just wait 32 slots after a fresh reboot to ensure we haven't published, or use a file to save state.

---

## #1376 — Ensure QUIC can survive DoS (QoS/credit management)
- **URL:** https://github.com/firedancer-io/firedancer/issues/1376
- **Created:** 2024-03-25 by @mmcgee-jump
- **Updated:** 2026-06-10
- **Labels:** quic

---

## #1360 — Implement futex based co-operative core sharing for tiles
- **URL:** https://github.com/firedancer-io/firedancer/issues/1360
- **Created:** 2024-03-23 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** platform, perf, Priority: Medium, operator
- **Assignees:** mmcgee-jump

Will let us reduce core count by sharing core for non-perf critical tiles

---

## #1357 — Set up `bench2` command with leader + follower and optimize
- **URL:** https://github.com/firedancer-io/firedancer/issues/1357
- **Created:** 2024-03-23 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** perf, Priority: High, testing, consensus
- **Assignees:** mmcgee-jump

---

## #1247 — ci: C problem matcher
- **URL:** https://github.com/firedancer-io/firedancer/issues/1247
- **Created:** 2024-02-07 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** Priority: Low

**Problem**

Spotting build failures in CI log is currently like finding a needle in the haystack due to high build parallelism. 

**Suggested Fix**

Consider using [problem matchers](https://github.com/actions/toolkit/blob/main/docs/problem-matchers.md) to make errors render inline on PRs like so:

![image](https://github.com/firedancer-io/firedancer/assets/113896534/25b9bbc8-8041-419a-92f3-45675fc3a8e2)

---

## #1220 — Run with MemorySanitizer in CI
- **URL:** https://github.com/firedancer-io/firedancer/issues/1220
- **Created:** 2024-02-03 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** security, Priority: High
- **Assignees:** ripatel-fd

Our CI configuration does not test for uninitialized reads. 
MemorySanitizer is a highly accurate tool for detecting such.
Unlike the other sanitizers, it requires special setup however. 

Namely, we have to build a custom libc++ with MSan instrumentation, and then a custom Clang toolchain. 

- [ ] Add MSan build config
- [ ] Add documentation how to create an MSan-capable LLVM build and how to instrument Firedancer with it
- [ ] Run it in CI

---

## #1152 — Split metrics workspace into N, 1 per tile
- **URL:** https://github.com/firedancer-io/firedancer/issues/1152
- **Created:** 2024-01-12 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** security, Priority: Medium
- **Assignees:** mmcgee-jump

---

## #1149 — Add canaries to workspace allocations
- **URL:** https://github.com/firedancer-io/firedancer/issues/1149
- **Created:** 2024-01-12 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** security, Priority: Medium

---

## #1013 — Switch metrics tile to do chunked response encoding, and not buffer metrics
- **URL:** https://github.com/firedancer-io/firedancer/issues/1013
- **Created:** 2023-11-30 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** perf, Priority: Low, telemetry

It should just `memcpy()` the metrics out of shared memory, and then slowly write them as the connection is writable with chunked encoding.

---

## #989 — Add guard pages around workspaces
- **URL:** https://github.com/firedancer-io/firedancer/issues/989
- **Created:** 2023-11-22 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** security, Priority: Medium
- **Assignees:** alpeng-jump

See #968 . The workspaces are mapped to a random address, but it's possible (about 1/400,000) that gigantic pages would end up adjacent, and so an overrun could step into another workspace. This can be prevented by adding guard pages around each workspace.

---

## #911 — Update wiredancer demo/readme for latest main
- **URL:** https://github.com/firedancer-io/firedancer/issues/911
- **Created:** 2023-11-05 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** build, Priority: Low, fpga, operator

Firedancer is still using some old frank scripts which don't work, eg, see #888 . We can probably set it up to configure WD as part of the topology now and just run it with the normal fdctl run path.

---

## #826 — standardize dcache bounds checking for links
- **URL:** https://github.com/firedancer-io/firedancer/issues/826
- **Created:** 2023-10-21 by @mmcgee-jump
- **Updated:** 2026-05-01
- **Labels:** security, Priority: Medium

Since all links are now specified in the topology, we can automatically bounds check messages received on links (mtu, chunk, wmark etc) to make sure they are valid, rather than every tile needing to remember to do this in `during_frag` etc

---

## #811 — Async signal deadlock in fd_log / FD_ONCE
- **URL:** https://github.com/firedancer-io/firedancer/issues/811
- **Created:** 2023-10-19 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** Priority: Low

```(gdb) bt
#0  0x00007f513352912b in sched_yield () from /lib64/libc.so.6
#1  0x000000000627e129 in fd_yield () at src/util/fd_util.c:26
#2  0x0000000006233b25 in fd_log_private_cleanup () at src/util/log/fd_log.c:925
#3  0x0000000006233c64 in fd_log_private_sig_abort (sig=2, info=0x7ffe5ebc1770, context=0x7ffe5ebc1640) at src/util/log/fd_log.c:965
#4  <signal handler called>
#5  0x00007f51335298bb in sync () from /lib64/libc.so.6
#6  0x0000000006233ad0 in fd_log_private_cleanup () at src/util/log/fd_log.c:922
#7  0x00007f513354126c in __run_exit_handlers () from /lib64/libc.so.6
#8  0x00007f51335413a0 in exit () from /lib64/libc.so.6
#9  0x000000000623397e in fd_log_private_2 (level=4, now=1697739996844136477, file=0xf13ac5f "src/app/fdctl/topology.c", line=225, func=0xf13b2f0 <__func__.32139> "fd_topo_workspace_fill", 
    msg=0x7f5134a25070 "workspace footprint 18446744073555893248 not aligned to page size 0") at src/util/log/fd_log.c:864
#10 0x00000000060f39b7 in fd_topo_workspace_fill (topo=0x7ffe5ebc3bd0, wksp=0x7ffe5ebc3be8, mode=0) at src/app/fdctl/topology.c:225
#11 0x00000000060f3db2 in fd_topo_fill (topo=0x7ffe5ebc3bd0, mode=0) at src/app/fdctl/topology.c:266
#12 0x0000000006149925 in expected_pages (config=0x7ffe5ebc39d0, out=0x7ffe5ebc2608) at src/app/fdctl/configure/large_pages.c:51
#13 0x0000000006149c2b in check (config=0x7ffe5ebc39d0) at src/app/fdctl/configure/large_pages.c:98
#14 0x0000000006143ebf in configure_cmd_perm (args=0x7ffe5ebc28c0, caps=0x7ffe5ebc2950, config=0x7ffe5ebc39d0) at src/app/fdctl/configure/configure.c:60
#15 0x00000000060b19e5 in dev_cmd_perm (args=0x7ffe5ebc3960, caps=0x7ffe5ebc2950, config=0x7ffe5ebc39d0) at src/app/fddev/dev.c:36
#16 0x00000000060ad89d in main (argc=0, _argv=0x7ffe5ec21958) at src/app/fddev/main.c:131```

---

## #752 — Support validator vote only mode
- **URL:** https://github.com/firedancer-io/firedancer/issues/752
- **Created:** 2023-10-05 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** Priority: Medium, debugging, operator
- **Assignees:** ptaffet-jump

Just need to drop packets at TPU arrival time if in vote only mode

---

## #682 — Add stress and MTBF testing for TPU
- **URL:** https://github.com/firedancer-io/firedancer/issues/682
- **Created:** 2023-09-07 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** Priority: Medium, testing

---

## #673 — Add checks on /proc/maps as part of sandboxing
- **URL:** https://github.com/firedancer-io/firedancer/issues/673
- **Created:** 2023-09-06 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** security, Priority: Medium
- **Assignees:** mmcgee-jump

- Ensure no unexpected shared pages are mapped, since that could lead to a sandbox escape.
- Try to reduce mapped memory list as well, to eliminate gadgets etc

---

## #664 — Move logging into separate tile, eliminate `write`, `fsync` calls from other tiles
- **URL:** https://github.com/firedancer-io/firedancer/issues/664
- **Created:** 2023-09-05 by @mmcgee-jump
- **Updated:** 2025-11-14
- **Labels:** security, Priority: Low, debugging, telemetry

---

## #177 — Add line number info to backtraces
- **URL:** https://github.com/firedancer-io/firedancer/issues/177
- **Created:** 2023-03-06 by @ripatel-fd
- **Updated:** 2025-12-12
- **Labels:** platform, Priority: Low, debugging

**Feature Request**

Add line number info to backtraces, e.g. `fd_crasher.c(1234)`.

Gives some useful debugging info during development and to some extent during production issues without having to spin up GDB.

Low prio

---

## #148 — util: improve fd_cstr test coverage
- **URL:** https://github.com/firedancer-io/firedancer/issues/148
- **Created:** 2023-02-28 by @ripatel-fd
- **Updated:** 2025-11-14
- **Labels:** good first issue, Priority: Low, testing

The following functions in //src/util/cstr:test_cstr.c are not covered by unit tests yet:

- fd_cstr_casecmp
- fd_cstr_to_ulong_octal
- fd_cstr_append_printf
- fd_cstr_append_cstr
- fd_cstr_append_cstr_safe
- fd_cstr_hash
- fd_cstr_hash_append

---

## #77 — Code style guide and automatic formatter
- **URL:** https://github.com/firedancer-io/firedancer/issues/77
- **Created:** 2023-01-30 by @ripatel-fd
- **Updated:** 2026-06-04
- **Labels:** docs, linting, Priority: Low

This project is missing a code style guide

Should be a basic list of rules in a markdown doc

---

