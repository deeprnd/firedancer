# Firedancer Philosophy And Style Guide

This document is a contributor guide for the Firedancer-derived C
runtime in this repository.  It complements `CONTRIBUTING.md`, which
defines syntax-level style, and focuses on the design philosophy that
explains why the code looks the way it does.

Unless a task explicitly says otherwise, read "Firedancer" here as the
full C runtime path: `src/app/firedancer`, common Firedancer tiles in
`src/disco`, full Firedancer tiles in `src/discof`, and the supporting
runtime in `src/tango`, `src/util`, `src/waltz`, `src/flamenco`, and
`src/funk`.  Avoid Frankendancer-specific paths such as `fdctl`,
`fddev`, and `discoh` unless the code is genuinely shared.

## Core Philosophy

Firedancer treats a system as a bounded, explicit, memory-resident
pipeline.  The major design objective is not "make C look like a higher
level language."  It is "make every byte of memory, every producer,
every consumer, every syscall, and every scheduling decision visible to
the code."

The most important consequences are:

- Prefer explicit topology over discovery.  Tiles, links, workspaces,
  objects, CPUs, permissions, and queue depths are declared up front.
- Prefer fixed capacity over unbounded allocation.  Runtime structures
  normally have `align`, `footprint`, `new`, `join`, `leave`, and
  `delete` APIs and are sized during topology construction or startup.
- Prefer one owner and many readers over shared mutation.  A hot object
  should usually have one writer.  Shared readers get read-only mappings
  or lag behind a producer through sequence numbers.
- Prefer bounded loss to global backpressure.  Reliable flow control is
  available, but the system tries hard to keep the number of reliable
  consumers low.  Backpressure in a distributed system is often worse
  than dropping or ignoring stale data.
- Prefer process isolation over in-process trust.  Production tiles run
  as sandboxed processes with explicit shared-memory mappings and
  seccomp policies.
- Prefer mechanical simplicity in hot loops.  It is normal to see
  macros, manual cache alignment, compiler fences, branch hints, and
  hand-written state machines where a general abstraction would hide
  cost or ownership.

The reader should be able to answer these questions for any change:

1. Which tile owns this state?
2. Which workspace holds it?
3. Which process maps it, and in what mode?
4. Which fields are written concurrently, and by whom?
5. What is the overrun, restart, and shutdown behavior?
6. Which metrics or logs will tell an operator it is unhealthy?

Example: adding a high-rate telemetry stream from a `worker` tile to a
`metric` tile.

1. Ownership:
   `worker` owns the output link and is the only producer.  `metric` is
   a consumer and never mutates the link metadata or payload.
2. Workspace:
   the link's mcache and dcache live in a named link workspace, for
   example `worker_metric`.  The topology creates the link with
   `fd_topob_link`.
3. Mapping mode:
   `fd_topob_tile_out` maps the link objects read-write for `worker`.
   `fd_topob_tile_in` maps those same link objects read-only for
   `metric`.
4. Concurrent fields:
   `worker` writes payload bytes into dcache and publishes fragment
   metadata into mcache.  `metric` reads metadata and payload, and
   writes only its own local counters and its own fseq/metrics objects.
5. Overrun, restart, shutdown:
   if telemetry is not correctness-critical, wire `metric` as
   `FD_TOPOB_UNRELIABLE`.  If `metric` falls behind, it detects the
   mcache sequence gap, counts the loss, skips to a fresh sequence, and
   continues.  On restart, `metric` initializes from the producer's
   published sequence instead of requiring old telemetry to be replayed.
   On shutdown, it publishes its final diagnostics but does not need to
   drain every old fragment.
6. Observability:
   count fragments received, bytes received, overruns, and drops in
   tile-local counters, then flush them to metrics during housekeeping.
   Log only configuration errors or impossible corruption, not every
   dropped telemetry fragment.

In topology-shaped code, the same answers look like:

```c
fd_topob_link( topo, "worker_metric", "worker_metric",
               depth, mtu, burst );

fd_topob_tile_out( topo, "worker", 0UL,
                   "worker_metric", 0UL );

fd_topob_tile_in( topo, "metric", 0UL, "metric_in",
                  "worker_metric", 0UL,
                  FD_TOPOB_UNRELIABLE,
                  FD_TOPOB_POLLED );
```

If the answers are vague, the design is not ready.  For example,
"both tiles update the shared table when needed" is not an ownership
model.  Split the table, add a single owner, add a sequence protocol, or
use a documented lock.

## Topology Vocabulary

The topology is the static description of the running system.  It names
the machines that run code, the memory regions they can map, and the
wires between them.  When reading or adding code, use these words
precisely.

### Tiles

A tile is a unit of execution.  In production it should be treated as a
separate sandboxed process, even if a test runs several tiles as
threads.  A tile has a name, `kind_id`, CPU placement, scratch memory,
metrics memory, input links, output links, and object-use declarations.

Example:

```c
fd_topo_tile_t * worker =
  fd_topob_tile( topo, "worker", "worker_wksp", "metrics",
                 cpu_idx, 0, 0, 0 );

fd_topo_tile_t * metric =
  fd_topob_tile( topo, "metric", "metric_wksp", "metrics",
                 metric_cpu_idx, 0, 0, 0 );
```

This creates the tile's standard memory objects and records that the
tile must map them when it starts.  The tile still cannot access an
arbitrary object just because that object exists in the topology.  It
must have an explicit input, output, or `fd_topob_tile_uses`
relationship.

### Workspaces

A workspace is a named shared-memory allocation arena.  Objects are
placed inside workspaces, then tile processes map the workspaces they
need.  A workspace is the protection granularity the OS sees: if a tile
maps a workspace read-write, page protection cannot distinguish two C
objects inside that same mapped page.

Example:

```c
fd_topob_wksp( topo, "worker_wksp" );
fd_topob_wksp( topo, "metrics" );
fd_topob_wksp( topo, "worker_metric" );
```

Use separate workspaces when the memory-protection boundary matters.
For example, keeping a producer's private state in `worker_wksp` and a
link in `worker_metric` lets consumers map only the link workspace.

### Objects

An object is a typed region inside a workspace: tile scratch, metrics,
cnc, fseq, mcache, dcache, a store, or another formatted structure.
Creating an object reserves memory in a workspace, but does not grant a
tile access to it.

Example:

```c
fd_topo_obj_t * table =
  fd_topob_obj_named( topo, "foo_table", "worker_wksp",
                      "worker_table" );

fd_topob_tile_uses( topo, worker, table,
                    FD_SHMEM_JOIN_MODE_READ_WRITE );
```

The `fd_topob_tile_uses` call is the access declaration.  Without it,
the tile should not be able to find the object through its topology
joins, and the tile's process may not map the containing workspace at
all.

### Links

A link is a bounded one-producer, one-or-more-consumer communication
path.  It normally consists of an mcache for metadata and, when the MTU
requires payload storage, a dcache for bytes.  A link is not an
unbounded queue of allocated messages.

Example:

```c
fd_topob_link( topo, "worker_metric", "worker_metric",
               depth, mtu, burst );

fd_topob_tile_out( topo, "worker", 0UL,
                   "worker_metric", 0UL );

fd_topob_tile_in( topo, "metric", 0UL, "metric_in",
                  "worker_metric", 0UL,
                  FD_TOPOB_UNRELIABLE,
                  FD_TOPOB_POLLED );
```

`fd_topob_tile_out` declares `worker` as a producer and maps the link
mcache/dcache read-write for that tile.  `fd_topob_tile_in` declares
`metric` as a consumer and maps the link mcache/dcache read-only for
that tile.  The input also creates or uses an fseq object in
`metric_in` so the consumer can publish read progress for diagnostics
and, when reliable, flow control.

### Mapping Modes

Mapping mode describes how a tile process maps the workspace that holds
an object:

- `FD_SHMEM_JOIN_MODE_READ_ONLY`: the tile can load from the mapped
  pages.  A store should fault through normal OS page protection.
- `FD_SHMEM_JOIN_MODE_READ_WRITE`: the tile can load and store through
  that mapping.
- No mapping: the tile has no virtual address for that workspace.
  Ordinary loads and stores cannot peek at it.

Examples:

```c
/* Producer owns this table. */
fd_topob_tile_uses( topo, worker, table,
                    FD_SHMEM_JOIN_MODE_READ_WRITE );

/* Observer can inspect it but must not mutate it. */
fd_topob_tile_uses( topo, metric, table,
                    FD_SHMEM_JOIN_MODE_READ_ONLY );

/* A third tile has no tile_uses call and no link to this workspace.
   It should not map worker_wksp at all. */
```

Use read-write mappings only for the tile that owns mutation.  Use
read-only mappings for observers.  Use no mapping when a tile has no
reason to see the object.  Remember that protection is at mapping/page
granularity; clear workspace layout still matters.

## Configuration, Layout, And Operator Surface

The book is mostly operator-facing: it explains tile counts, CPU
affinity, huge pages, networking setup, monitoring, and tuning symptoms.
For contributors, those topics become a source-code contract.  A
configuration change is not just TOML plumbing; it may change topology,
memory sizing, sandbox authority, monitor output, and operator failure
modes.

In the full Firedancer path, start with:

- `src/app/firedancer/config/default.toml`: documented defaults and
  operator-visible option names.
- `src/app/firedancer/config.c` and `src/app/firedancer/config.h`:
  embedded config files and config loading entry points.
- `src/app/firedancer/topology.c`: conversion from `config_t` into
  tiles, workspaces, links, objects, and CPU placement.
- `src/app/shared/fd_config_file.h` and nearby shared config helpers:
  parser and override mechanics used by app entry points.

When adding or changing an option, trace it through the whole path:

1. TOML name and default value.
2. Parsed field in `config_t`.
3. Validation and derived values.
4. Topology effect, if any.
5. Tile initialization effect.
6. Sandbox, file descriptor, rlimit, or capability effect.
7. Metrics, logs, monitor, or GUI visibility.
8. Failure behavior when the option is invalid or unsupported.

If any step is "it is picked up dynamically somewhere," inspect harder.
Firedancer tries to make configuration effects explicit.  Runtime
discovery is the exception, not the normal design.

### Layout Is A Contract

The book describes layout as the mapping of tile jobs to CPU cores.  In
code, layout is also a promise about ownership and throughput.  Tile
counts determine how many instances exist, which links are created, how
fan-out and load balancing work, how much scratch and workspace memory
is needed, and which cores are saturated by busy polling.

Before changing a tile count or adding a tile kind, answer:

- Does the new count change a one-producer or one-consumer assumption?
- Are all fan-in and fan-out links sized for the worst configured count?
- Does each tile instance get a unique `kind_id`, scratch object,
  metrics object, cnc object, and CPU placement?
- Does auto affinity still have enough cores, and does manual affinity
  fail loudly when it is too short?
- Does disabling a feature remove every dependent tile and link, or
  leave a half-wired topology?
- Do monitoring and generated metrics labels still identify each tile
  unambiguously?

Example: increasing `verify_tile_count` is not just a loop bound.  The
topology has to wire upstream QUIC output into all verify instances,
wire verify outputs into the downstream stage, allocate per-tile
scratch/metrics/cnc, and preserve the expected load-balancing policy.
If the downstream stage has one correctness-critical consumer, adding
more producers may require an explicit merge, partition, or ordering
rule rather than a larger queue.

### Defaults And Tuned Profiles

`default.toml` is both a default config and human documentation.  Keep
new options documented where operators will find them.  The comment
should explain the operational tradeoff, not repeat the field name:

```toml
# How many verify tiles to run.  Verify tiles perform signature
# verification on incoming transactions, an expensive operation that is
# often the bottleneck of the validator.
verify_tile_count = 6
```

Tuned profiles such as benchmark, devnet, testnet, or mainnet configs
should only override options that matter for that profile.  Do not hide
a required default by copying a large block of unrelated settings into a
profile.  If a default changes, check whether the profile intentionally
inherits it or intentionally diverges.

Prefer invalid configuration to fail at startup with a clear
operator-facing error.  Do not silently clamp tile counts, queue depths,
ports, memory sizes, or CPU ranges unless the local config code already
documents that behavior.  A validator that boots with an unintended
layout is usually worse than one that refuses to boot.

### Capacity, Memory, And Huge Pages

Operator-facing memory settings become concrete workspace and object
footprints.  A config option that increases count, depth, MTU, cache
size, or history length should be reviewed as a memory-layout change:

- Which workspace grows?
- Is the growth on huge or gigantic pages?
- Does the footprint computation detect overflow?
- Is the capacity fixed at startup?
- Does the new size affect TLB pressure, NUMA placement, or mmap
  permissions?
- Will a monitor or startup log make the resulting capacity visible?

Avoid adding runtime allocation because a config value is "rarely used."
If the maximum capacity is configured, size it during topology
construction or tile initialization and make the memory owner explicit.

### Networking And Sandbox Options

The book's networking sections describe AF_XDP, device queues, offloads,
and per-tile packet ownership.  In contributor terms, any option that
touches networking is also likely to touch sandbox setup:

- privileged setup before sandbox entry,
- file descriptors that must be opened and allow-listed,
- seccomp policy updates,
- capabilities and rlimits,
- workspace mappings visible to the kernel, NIC, net tile, and app
  tiles,
- read-only versus read-write access to RX and TX objects.

Do not add a post-sandbox syscall or device operation as a side effect
of a config option without updating the tile's permission model.  If the
operation can happen in `privileged_init`, keep it there.  If it must
happen after sandboxing, the seccomp policy and the reason should be
obvious to a reviewer.

### Diagnostics For Configured Behavior

Every operator-visible knob should have an operator-visible way to see
whether it did what it claimed.  That can be a startup log, a metric, a
monitor column, or a GUI/API surface, depending on the feature.

Use diagnostics to expose stable facts:

- effective tile counts and affinity,
- selected network mode and device queue mapping,
- link overruns, slow consumers, drops, and backpressure,
- configured capacities and saturation,
- disabled optional features,
- sandbox or permission failures.

Do not log every packet, transaction, or fragment affected by a setting.
High-rate effects should be counters flushed through metrics.  Logs are
for configuration facts, invalid operator input, impossible state, and
rate-limited diagnostics.

## Source Map

Start with these files when orienting a change:

- `src/app/firedancer/topology.c`: the full Firedancer topology.
- `src/disco/topo/fd_topo.h`: topology data model.
- `src/disco/topo/fd_topob.h`: topology builder API.
- `src/disco/topo/fd_topo_run.c`: tile launch, sandboxing, workspace
  joins, metrics registration, and run-loop entry.
- `src/disco/stem/fd_stem.c`: standard tile event-loop template.
- `src/tango/fd_tango_base.h`: message fragment model.
- `src/tango/mcache/fd_mcache.h`: metadata ring/cache.
- `src/tango/dcache/fd_dcache.h`: payload cache.
- `src/tango/fseq/fd_fseq.h`: consumer sequence publication.
- `src/tango/fctl/fd_fctl.h`: credit-based flow control.
- `src/tango/cnc/fd_cnc.h`: command and control state.
- `src/util/wksp/fd_wksp.h`: shared workspace allocator.
- `src/util/tmpl`: generated-by-inclusion data structure templates.
- `src/disco/metrics/fd_metrics.h` and `src/disco/metrics/metrics.xml`:
  metrics layout and definitions.

## C Dialect And Local Style

`CONTRIBUTING.md` remains the syntax guide.  The short version:

Use the repo's C17 style, not a formatter's default style:

```c
/* good */
if( FD_UNLIKELY( !ctx ) ) FD_LOG_ERR(( "NULL ctx" ));

fd_memcpy( dst, src, sz );

/* avoid */
if (unlikely(!ctx)) {
    FD_LOG_ERR(("NULL ctx"));
}
memcpy(dst, src, sz);
```

Use Firedancer primitive names from `fd_util_base.h`: `uchar`,
`ushort`, `uint`, `ulong`, `long`, and friends:

```c
/* good */
uchar const * pkt;
uint          ip4;
ulong         seq;
long          now;

/* avoid */
uint8_t const * pkt;
uint32_t        ip4;
uint64_t        seq;
int64_t         now;
```

Do not use `bool`; use `int` with `0` and `1`:

```c
/* good */
int enabled = 1;
if( enabled ) do_work();

/* avoid */
bool enabled = true;
if( enabled ) do_work();
```

Prefer `FD_STATIC_ASSERT`, `FD_TEST`, `FD_LIKELY`, `FD_UNLIKELY`,
`FD_FN_CONST`, and `FD_FN_PURE` where the local code does:

```c
FD_STATIC_ASSERT( sizeof(fd_frag_meta_t)==32UL, frag_meta_size );

FD_FN_CONST static inline ulong
foo_align( void ) {
  return 128UL;
}

FD_FN_PURE static inline ulong
foo_depth( foo_t const * foo ) {
  return foo->depth;
}

if( FD_UNLIKELY( depth & (depth-1UL) ) )
  FD_LOG_ERR(( "depth must be a power of two" ));

FD_TEST( ctx->out_cnt<=FD_TOPO_MAX_TILE_OUT_LINKS );
```

What these macros mean:

- `FD_STATIC_ASSERT( cond, token )` is a compile-time invariant.  Use it
  for layout, alignment, constant bounds, and template assumptions that
  must be true before the object file exists.  The second argument is a
  token-like error name, not a string.
- `FD_TEST( cond )` is a test/startup assertion.  It is appropriate in
  tests, self-checks, and initialization paths where failing fast is the
  right behavior.  Do not use it as normal operator-facing input
  validation in a long-running tile; log a clear error or return an
  explicit status there.
- `FD_LIKELY( cond )` and `FD_UNLIKELY( cond )` evaluate `cond` and give
  the compiler a branch-probability hint.  They should describe the
  steady-state hot path, not the author's hopes.  Mark rare corruptions,
  null setup errors, overrun recovery, and cold boundary cases
  `FD_UNLIKELY`; mark the dominant success path `FD_LIKELY` only when
  the local code already uses that style.
- `FD_FN_CONST` marks a function whose result depends only on explicit
  arguments, not memory.  Alignment, footprint, bit-manipulation, and
  simple numeric conversion helpers are typical candidates.
- `FD_FN_PURE` marks a function with no side effects whose result may
  depend on pointed-to memory.  Query helpers such as `foo_depth( foo )`
  are typical candidates.

`FD_LIKELY(c)` is `__builtin_expect( !!(c), 1L )`.
`FD_UNLIKELY(c)` is `__builtin_expect( !!(c), 0L )`.  The `!!` coerces
the expression to logical `0` or `1`; the builtin tells the optimizer
which result should be common.  It does not make the branch true or
false, it does not add a runtime check, and it does not synchronize
memory.

The compiler may use the hint to:

- arrange the hot path as fall-through code,
- move unlikely blocks away from the tight instruction-cache path,
- choose branch layout and prediction metadata,
- decide whether a small branch is worth if-conversion or should remain
  a branch.

This matters in loops that run at packet, fragment, or scheduler rate.
The normal path should be straight-line and nearby; the error path can
be farther away.  Typical uses are:

```c
/* Startup or boundary validation: invalid config is cold. */
if( FD_UNLIKELY( !ctx ) ) FD_LOG_ERR(( "NULL ctx" ));

/* Hot receive loop: no overrun is the common case. */
if( FD_UNLIKELY( seq_diff ) ) {
  overrun_cnt++;
  rx_seq = seq_found;
  continue;
}

/* Syscall wrapper: EAGAIN can be expected on non-blocking sockets. */
if( FD_UNLIKELY( msg_cnt<0 ) ) {
  if( FD_LIKELY( errno==EAGAIN ) ) return 0UL;
  FD_LOG_WARNING(( "recv failed (%i-%s)", errno,
                   fd_io_strerror( errno ) ));
}
```

Misusing branch hints usually does not make the program logically wrong,
but it can make the machine do the wrong work first.  A bad hint can:

- put the real hot path behind a taken branch,
- increase instruction-cache pressure by interleaving cold code with hot
  code,
- make branch prediction and layout worse under load,
- hide a missing model of the actual steady state,
- reduce readability because future readers infer the marked path is
  rare or common.

Do not wrap every `if` in `FD_LIKELY` or `FD_UNLIKELY`.  Use them when
the probability is part of the performance contract or the local code
already marks the same kind of branch.  If the branch frequency depends
on live configuration, peer behavior, or normal load, prefer no hint
unless measurement or nearby code makes the dominant case obvious.

`FD_FN_CONST` and `FD_FN_PURE` are contracts with the optimizer and the
reader.  In this tree they expand to nothing by default because compiler
interpretations of these attributes have caused surprises, especially
around functions that write through output pointers.  Keep using them
where nearby APIs use them: they document intent and can be enabled by
stricter build modes to find functions that violate their claimed
contract.

Do not annotate a function `FD_FN_CONST` or `FD_FN_PURE` if it:

- writes through a pointer,
- reads volatile or atomic state,
- depends on time, randomness, logging state, errno, thread-local state,
  file descriptors, sockets, or device state,
- mutates scratch, metrics, queues, maps, pools, or hidden globals.

Related macros and attributes show up for the same reason:

- `FD_RESTRICT` documents non-aliasing pointer arguments on hot helpers.
- `FD_FN_UNUSED` is for static header helpers that may not be used in
  every translation unit.
- `FD_VOLATILE` and `FD_VOLATILE_CONST` force volatile access, but they
  are not a synchronization protocol by themselves.
- `FD_COMPILER_MFENCE` prevents compiler reordering across a point, but
  it is not a hardware memory fence.
- `FD_PROTOTYPES_BEGIN` and `FD_PROTOTYPES_END` keep headers usable from
  C++ when they expose C symbols.

Keep function prototypes in the local style: return type on its own
line, one argument per line, vertically aligned types and names:

```c
/* good */
static inline ulong
foo_publish( foo_t *       foo,
             ulong         seq,
             uchar const * payload,
             ulong         payload_sz );

/* avoid */
static inline ulong foo_publish(foo_t *foo, ulong seq, const uint8_t *payload, size_t payload_sz);
```

Keep comments useful for invariants, ownership, memory layout, and
security behavior.  Avoid restating the next line of code:

```c
/* good: explains a real invariant */
/* Only the producer writes seq.  Readers use odd/even values to detect
   a torn read while the producer is updating value. */
FD_VOLATILE( state->seq ) = seq + 1UL;

/* good: explains memory layout */
/* Payload bytes follow the metadata header and are addressed by compact
   dcache chunks, not local pointers. */
uchar * payload = fd_chunk_to_laddr( base, chunk );

/* avoid: restates the code */
/* Increment seq by one. */
seq++;
```

Use the surrounding module as the authority.  `src/tango` is the
canonical style reference for low-level runtime code.

## Memory

### Address Spaces

Do not assume a pointer is globally meaningful.

Firedancer uses several address representations:

- Local address: a normal pointer valid only in the current process.
- Workspace global address, often `gaddr`: an offset-like address inside
  an `fd_wksp_t`.  It can be converted to a local address after joining
  the workspace.
- Compact chunk index: a 32-bit-ish fragment payload location used in
  Tango metadata.  Convert with `fd_chunk_to_laddr` or dcache helpers.
- Shared object base pointer: the first byte of the formatted memory
  region backing an object.
- Joined handle: the local handle returned by `join`.  This is often an
  interior pointer, not the same value as the shared object base.

This is why many APIs warn that `join` is not just a cast.  For example,
`fd_mcache_join` returns the metadata array, `fd_dcache_join` returns
the data region, and `fd_pool_join` may return element zero after a
private metadata header.  Always use the matching `leave` to get back
to the shared-memory base.

### The Object Lifecycle

Most shared or persistent structures follow this pattern:

```c
ulong  align     = thing_align();
ulong  footprint = thing_footprint( params );
void * shmem     = fd_wksp_alloc_laddr( wksp, align, footprint, tag );
void * formatted = thing_new( shmem, params );
thing_t * thing  = thing_join( formatted );
...
void * shmem2    = thing_leave( thing );
thing_delete( shmem2 );
```

Conventions:

- `align` and `footprint` must validate sizing and overflow.
- `footprint` returns zero for invalid parameters where practical.
- `new` formats memory and does not imply a join.
- `join` returns the process-local access handle.
- `leave` invalidates the join handle and returns the formatted region.
- `delete` assumes nobody is joined and returns ownership of memory.

Do not allocate hidden heap state inside these objects unless the local
module already does so and documents it.  If a structure must allocate,
prefer allocating from a workspace or from an explicit allocator whose
lifetime and concurrency group are visible.

### Workspaces

`fd_wksp_t` is the main backing store for inter-process state.  It sits
on huge or gigantic pages, is NUMA-aware, and is designed for large
startup allocations rather than many tiny runtime allocations.

Use workspace memory for state that must be:

- shared across tiles,
- inspectable by monitoring processes,
- persistent across tile restart,
- relocatable through a `gaddr`,
- large enough to matter for TLB and NUMA placement.

Avoid workspace allocation in hot paths.  The usual pattern is to size
everything in topology construction and format it during startup.  A
workspace allocator is closer to `mmap` than `malloc`.

### Scratch Memory

Tile-private working memory is usually a scratch object:

- The topology creates a tile object.
- The tile exposes `scratch_align` and `scratch_footprint`.
- `privileged_init` or `unprivileged_init` carves it with
  `FD_SCRATCH_ALLOC_INIT`, `FD_SCRATCH_ALLOC_APPEND`, and
  `FD_SCRATCH_ALLOC_FINI`.

The scratch layout is part of the contract.  Keep the footprint function
and the allocation sequence identical.  Most tiles explicitly check for
overflow after `FD_SCRATCH_ALLOC_FINI`; keep that pattern.

Scratch is for stable tile-local state.  Do not use it as an unbounded
heap and do not let pointers into one tile's scratch escape to another
tile unless the topology intentionally maps that object.

### Cache Lines And Alignment

Alignment is not cosmetic.  It encodes atomicity, false-sharing
avoidance, TLB behavior, and sometimes device requirements.

Common sizes:

- `FD_CHUNK_ALIGN` is 64 bytes.
- `FD_FRAG_META_ALIGN` is 32 bytes.
- `FD_MCACHE_ALIGN`, `FD_FSEQ_ALIGN`, and `FD_CNC_ALIGN` are 128 bytes.
- `FD_DCACHE_ALIGN` is 4096 bytes.

Use `FD_LAYOUT_APPEND` and `FD_LAYOUT_FINI` for compound footprints.
Avoid hand-rolled offset arithmetic unless the local code already does
so for a specific reason.

### Mutation Policy

The default hot-path pattern is:

- The producer writes payload data first.
- The producer publishes metadata last.
- Consumers copy or read metadata, then speculatively inspect payload.
- Consumers re-check sequence state to detect overrun.
- Flow-control state is updated lazily during housekeeping.

Favor in-place mutation when:

- there is one writer,
- the object's capacity is fixed,
- readers can detect version or sequence changes,
- mutation avoids a copy on the hot path.

For a small shared object, this often looks like one writer publishing a
version and many readers validating that they observed a stable version:

```c
struct hot_state {
  ulong seq;   /* Even means stable; odd means writer is mutating. */
  ulong value;
};

/* Writer tile: owns all mutation of state. */
ulong seq = state->seq;
FD_VOLATILE( state->seq ) = seq + 1UL; /* Mark update in progress. */
FD_COMPILER_MFENCE();

state->value = next_value;

FD_COMPILER_MFENCE();
FD_VOLATILE( state->seq ) = seq + 2UL; /* Publish stable version. */

/* Reader tile: maps state read-only and never mutates it. */
ulong seq0 = FD_VOLATILE_CONST( state->seq );
if( FD_UNLIKELY( seq0 & 1UL ) ) {
  /* Writer is in progress.  Retry, skip, or use the previous value. */
}

FD_COMPILER_MFENCE();
ulong value = state->value;
FD_COMPILER_MFENCE();

ulong seq1 = FD_VOLATILE_CONST( state->seq );
if( FD_UNLIKELY( seq0!=seq1 ) ) {
  /* Writer changed the object while we read it.  Treat value as stale. */
}
```

The important part is not this exact protocol.  The important part is
that the writer is named, readers are read-only, and readers can detect
when they lagged or raced the producer.  Tango mcaches use the same
idea at queue scale: producers publish sequence numbers, and consumers
handle gaps and overruns explicitly.

Favor copy-out when:

- the producer can overrun the consumer,
- the data will be used after advancing the input sequence,
- the callback documentation says the fragment may be corrupt or torn,
- the consumer needs a stable view across calls.

Prefer `const` joins, `*_const` accessors, or read-only mappings when a
tile should not mutate a shared object.  If mutation is necessary, name
the writer and describe the synchronization pattern in the code.

## Macros And Templates

Firedancer uses macros because they are often the lowest-overhead way to
express compile-time configuration in C17.  This is intentional.

Common macro roles:

- API generation: `src/util/tmpl/fd_map.c`, `fd_pool.c`, `fd_sort.c`,
  `fd_heap.c`, `fd_treap.c`, and similar files are included after
  defining names and element types.
- Fast multi-output operations: `FD_MCACHE_WAIT` returns multiple values
  without allocating or calling through a generic interface.
- Compile-time layout: `FD_LAYOUT_*`, `FD_*_FOOTPRINT`, and static
  assertions.
- Branch and compiler guidance: `FD_LIKELY`, `FD_UNLIKELY`,
  `FD_FN_CONST`, `FD_FN_PURE`, `FD_FN_UNUSED`.
- Memory ordering: `FD_VOLATILE`, `FD_VOLATILE_CONST`,
  `FD_COMPILER_MFENCE`, and explicit `__atomic_*` where required.
- Logging and testing: `FD_LOG_*`, `FD_TEST`, `FD_STATIC_ASSERT`.

Guidelines:

- Prefer existing macros and templates over inventing local variants.
- Keep macro arguments side-effect safe unless the macro's local family
  clearly documents otherwise.
- Undefine or isolate template configuration when including multiple
  templates in a file if names could leak into later includes.
- Use `static inline` for small typed helpers around macro-generated
  APIs when it improves readability without cost.
- Do not replace a hot template with a generic container unless the
  performance and memory model still fit.

The style may look unusual to C programmers used to library-first code.
Here, the generated API is intentionally specialized to the element
type, key type, hash function, index width, and memory layout.

### Mechanical Hot-Loop Examples

Mechanical simplicity means the hot loop shows the machine-level work it
is doing.  A general abstraction might look cleaner, but it can hide
ownership, memory ordering, branches, allocation, or cache-line traffic.

Real example: a consumer wants to read the next message fragment.  A
generic design might use a queue object with a virtual `pop()` or a
callback chain that returns an owned message object.  That would hide
whether the payload was copied, whether the producer can overwrite it,
and where backpressure is checked.  Firedancer keeps those mechanics
visible:

```c
FD_MCACHE_WAIT( meta, mline, seq_found, seq_diff, poll_max,
                mcache, depth, rx_seq );

if( FD_UNLIKELY( !poll_max ) ) {
  /* No fragment yet.  Do bounded housekeeping and poll again. */
  continue;
}

if( FD_UNLIKELY( seq_diff ) ) {
  /* Producer overran us.  Recover explicitly. */
  rx_seq = seq_found;
  continue;
}

/* Read or copy payload here, then verify the mcache line was not
   overwritten while we were processing it. */
ulong after = fd_frag_meta_seq_query( mline );
if( FD_UNLIKELY( fd_seq_ne( after, rx_seq ) ) ) {
  rx_seq = after;
  continue;
}

rx_seq = fd_seq_inc( rx_seq, 1UL );
```

How it is actually done: `src/tango/mcache/fd_mcache.h` implements
`FD_MCACHE_WAIT` as a macro because the hot loop needs multiple outputs
without allocation, callback dispatch, or a result object.  The macro
also leaves `poll_max`, `mline`, `seq_found`, and `seq_diff` explicit so
the caller must handle timeout, overrun, and speculative payload reads.

Real example: a producer publishes metadata only after payload bytes are
ready.  Instead of a lock around a queue entry, mcache publication uses a
small ordered protocol:

```c
FD_COMPILER_MFENCE();
meta->seq = fd_seq_dec( seq, 1UL ); /* Mark line in-progress. */
FD_COMPILER_MFENCE();

meta->sig    = sig;
meta->chunk  = (uint)chunk;
meta->sz     = (ushort)sz;
meta->ctl    = (ushort)ctl;
meta->tsorig = (uint)tsorig;
meta->tspub  = (uint)tspub;

FD_COMPILER_MFENCE();
meta->seq = seq; /* Publish stable metadata. */
FD_COMPILER_MFENCE();
```

How it is actually done: `fd_mcache_publish`,
`fd_mcache_publish_sse`, and `fd_mcache_publish_avx` specialize this
for scalar, SSE, and AVX-capable targets.  The code is explicit about
compiler fences, alignment, and atomic store assumptions because that is
the contract readers rely on.

Real example: payload allocation in a dcache is just chunk arithmetic,
not a heap allocation:

```c
chunk = fd_dcache_compact_next( chunk, sz, chunk0, wmark );
```

How it is actually done: `src/tango/dcache/fd_dcache.h` keeps payloads
in a compact cyclic region.  The producer advances by aligned chunk
footprints and wraps at a watermark.  This avoids per-message allocation
and makes the maximum live payload footprint part of topology sizing.

Real example: a network tile decides when to wake the kernel for XDP TX
with a tiny state machine, not a timer framework:

```c
int flush_level   = flusher->pending_cnt >= flusher->pending_wmark;
int flush_timeout = now >= flusher->next_tail_flush_ticks;
int flush         = flush_level || flush_timeout;
```

How it is actually done: `src/disco/net/xdp/fd_xdp_tile.c` keeps
`fd_net_flusher_t` as plain counters and deadlines in tile scratch.  The
run loop can see the pending count, watermark, timeout, and reset logic
without crossing an abstraction boundary.

Real example: expensive or lower-frequency work is not mixed into the
packet path.  Stem exposes explicit callbacks:

```c
/* Hot path: copy or inspect fragment while overrun checks protect it. */
STEM_CALLBACK_DURING_FRAG

/* Cold path: publish metrics, update fseq, service control state. */
STEM_CALLBACK_DURING_HOUSEKEEPING
```

How it is actually done: `src/disco/stem/fd_stem.c` is included as a
template by tiles that define the callbacks they need.  This gives each
tile a specialized run loop with direct calls, local scratch state, and
visible housekeeping cadence.

Use this style when a contribution is on a packet-rate, fragment-rate,
or scheduler-rate path.  It is less important for setup code, tests, or
operator-only command paths, where clarity and error reporting usually
matter more than removing every branch or call.

## Structural Patterns

Firedancer does not use C++ classes or inheritance, but the classic
GoF patterns still appear — expressed in the idioms already covered
in this guide: function pointer structs, macro-based template
instantiation, NULL-terminated registration arrays, and workspace
injection.  Knowing which pattern solves which problem lets contributors
pick the right tool without inventing a new one.

### Strategy — tile vtable

The central strategy type is `fd_topo_run_tile_t`
(`src/disco/topo/fd_topo.h:717`):

```c
typedef struct {
  char const * name;

  ulong (*scratch_align    )( void );
  ulong (*scratch_footprint)( fd_topo_tile_t const * tile );
  void  (*privileged_init  )( fd_topo_t const * topo,
                               fd_topo_tile_t const * tile );
  void  (*unprivileged_init)( fd_topo_t const * topo,
                               fd_topo_tile_t const * tile );
  void  (*run              )( fd_topo_t * topo,
                               fd_topo_tile_t * tile );
  ulong (*populate_allowed_seccomp)( fd_topo_t const * topo,
                                     fd_topo_tile_t const * tile,
                                     ulong out_cnt,
                                     struct sock_filter * out );
  /* ... */
} fd_topo_run_tile_t;
```

Each tile defines one named global instance and fills in the function
pointers it needs:

```c
/* src/disco/dedup/fd_dedup_tile.c */
fd_topo_run_tile_t fd_tile_dedup = {
  .name                = "dedup",
  .scratch_align       = scratch_align,
  .scratch_footprint   = scratch_footprint,
  .privileged_init     = privileged_init,
  .unprivileged_init   = unprivileged_init,
  .run                 = stem_run,
};
```

The dispatcher in `src/disco/topo/fd_topo_run.c` calls
`tile->run( topo, tile )` without knowing which tile kind it is.
No switch statement, no heap-allocated vtable pointer, no inheritance
chain.

**Problem solved:** identical lifecycle shape (init, sandbox, run loop)
with per-tile behavior.  Dispatch cost is one pointer dereference at
tile startup, not per fragment.

The same pattern appears for shared-memory object types.
`fd_topo_obj_callbacks_t` (`src/disco/topo/fd_topo.h:740`) stores
`footprint`, `align`, and `new` function pointers for each object kind
(mcache, dcache, fseq, metrics, …).

### Factory / Registry — NULL-terminated tile array

`src/app/firedancer-dev/main.h:112` lists every tile the binary knows:

```c
fd_topo_run_tile_t * TILES[] = {
  &fd_tile_net,
  &fd_tile_quic,
  &fd_tile_dedup,
  &fd_tile_pack,
  /* ... */
  NULL,
};
```

The runner walks the array once at startup to match topology tile names
to implementations.  Adding a new tile is two lines: an `extern`
declaration and a pointer in the array.

**Problem solved:** open-ended extensibility without a string-keyed hash
map or `#ifdef` chains.  The compiler sees every tile; the linker removes
unused ones.

### Template Method — macro-based stem instantiation

`src/disco/stem/fd_stem.c` is the reusable hot-loop backbone.  A tile
does not call it like a library; it instantiates it by defining callback
macros and including the file:

```c
/* src/disco/dedup/fd_dedup_tile.c */
#define STEM_BURST                  1UL
#define STEM_CALLBACK_CONTEXT_TYPE  fd_dedup_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN alignof(fd_dedup_ctx_t)
#define STEM_CALLBACK_METRICS_WRITE metrics_write
#define STEM_CALLBACK_DURING_FRAG   during_frag
#define STEM_CALLBACK_AFTER_FRAG    after_frag

#include "../stem/fd_stem.c"
```

This generates a specialized `stem_run` for the dedup tile with direct
calls to `during_frag` and `after_frag` — no function-pointer dispatch,
no `void *` context cast, the exact type inlined by the compiler.

**Problem solved:** shared polling loop, fan-in shuffling, credit
accounting, and housekeeping — without a per-fragment function-pointer
call overhead.  Each tile gets a separately compiled copy matched to its
context type and burst size.

Available callbacks and their purpose:

- `STEM_CALLBACK_BEFORE_CREDIT`: runs every loop iteration, including
  when the tile is backpressured.  Use for socket or timer service.
- `STEM_CALLBACK_AFTER_CREDIT`: runs when downstream credits are
  available.  Use for publishing data not triggered by an inbound
  fragment.
- `STEM_CALLBACK_BEFORE_FRAG`: fast signature check before reading
  payload.
- `STEM_CALLBACK_DURING_FRAG`: copy or read payload while overrun
  checks still protect the consumer.
- `STEM_CALLBACK_AFTER_FRAG`: publish downstream or update state after
  the fragment is accepted.
- `STEM_CALLBACK_DURING_HOUSEKEEPING`: lower-frequency work — publish
  metrics, update fseq, service control state.

### Adapter — wrapping fd_aio into a tango producer

`src/waltz/aio/fd_aio_tango.h` adapts the generic AIO interface so
callers that know only `fd_aio_t` end up writing into a tango
mcache/dcache pair:

```c
struct fd_aio_tango_tx {
  fd_aio_t         aio;     /* must be first — callers hold fd_aio_t * */
  fd_frag_meta_t * mcache;
  void *           dcache;
  void *           base;
  ulong            chunk0;
  ulong            wmark;
  /* ... */
};

/* Caller receives only the narrow fd_aio_t interface. */
FD_FN_CONST static inline fd_aio_t const *
fd_aio_tango_tx_aio( fd_aio_tango_tx_t const * self ) {
  return &self->aio;
}
```

Placing `fd_aio_t` as the first struct member makes the
`(fd_aio_tango_tx_t *)aio_ptr` cast valid under C's
common-initial-sequence rule.  The caller never sees tango internals.

**Problem solved:** network-protocol code written against `fd_aio_t`
works unchanged when the backing transport is a tango link instead of
a socket.

### Bridge — protocol discriminant in the fragment signature

`src/disco/fd_disco_base.h:67` packs a protocol tag into the 64-bit
tango fragment signature, letting multiple protocols share one physical
link:

```c
FD_FN_CONST static inline ulong
fd_disco_netmux_sig( uint   hash_ip_addr,
                     ushort hash_port,
                     uint   ip_addr,
                     ulong  proto,
                     ulong  hdr_sz ) {
  ulong hdr_sz_i = ((hdr_sz - 42UL)>>2)&0xFUL;
  ulong hash     = 0xfffffUL & fd_ulong_hash(
                     (ulong)hash_ip_addr | ((ulong)hash_port<<32) );
  return (hash<<44) | ((hdr_sz_i&0xFUL)<<40UL)
                    | ((proto&0xFFUL)<<32UL)
                    | ((ulong)ip_addr);
}

FD_FN_CONST static inline ulong
fd_disco_netmux_sig_proto( ulong sig ) {
  return (sig>>32UL) & 0xFFUL;
}
```

Protocol constants (`DST_PROTO_TPU_UDP`, `DST_PROTO_TPU_QUIC`,
`DST_PROTO_SHRED`, `DST_PROTO_GOSSIP`, …) are defined in the same
header.  Consumers call `fd_disco_netmux_sig_proto` on an incoming
fragment's `sig` to decide whether to process it or skip it.

**Problem solved:** a single link carries UDP, QUIC, shred, gossip, and
repair traffic without per-protocol links or extra copying.  The
abstraction is the link; the protocol tag is an attribute of each
fragment, extracted with zero allocation.

### Observer / Callback — QUIC async events

`src/waltz/quic/fd_quic.h:286` registers callbacks before starting the
QUIC engine:

```c
struct fd_quic_callbacks {
  void * quic_ctx;                                    /* passed to each callback */

  fd_quic_cb_conn_new_t                conn_new;      /* non-NULL */
  fd_quic_cb_conn_handshake_complete_t conn_hs_complete; /* non-NULL */
  fd_quic_cb_conn_final_t              conn_final;    /* non-NULL */
  fd_quic_cb_stream_notify_t           stream_notify; /* non-NULL */
  fd_quic_cb_stream_rx_t               stream_rx;     /* non-NULL */
  fd_quic_cb_tls_keylog_t              tls_keylog;    /* nullable  */
};
```

The QUIC tile installs its own functions into `quic->callbacks` during
`unprivileged_init`.  The QUIC engine fires them on connection and
stream events without owning or knowing the tile context type.

**Problem solved:** single-threaded, non-blocking QUIC implementation
that notifies application logic of async lifecycle events through a
registered struct rather than a blocking queue or thread.

### Dependency Injection — workspace injection

Tiles never allocate their own backing memory.  The topology builder
creates named workspace regions; the runner maps them into each tile
process before the run loop starts.  The tile receives pre-formatted,
NUMA-placed memory for scratch, metrics, and link objects:

```c
/* Topology side: declare workspace and tile */
fd_topob_wksp( topo, "dedup_wksp" );
fd_topob_tile( topo, "dedup", "dedup_wksp", "metrics",
               cpu_idx, 0, 0, 0 );

/* Tile side: memory already exists at init time */
static void
unprivileged_init( fd_topo_t const *      topo,
                   fd_topo_tile_t const * tile ) {
  fd_dedup_ctx_t * ctx = fd_topo_obj_laddr( topo, tile->tile_obj_id );
  /* ctx points into the pre-allocated workspace — no malloc. */
}
```

**Problem solved:** tiles stay independent of memory-management policy.
NUMA placement, huge-page backing, alignment, and TOML-driven capacity
are topology decisions, not tile code decisions.

### Pattern Summary

| Pattern | C mechanism | Primary source | Swap point |
|---------|-------------|----------------|------------|
| Strategy | function pointer struct | `fd_topo_run_tile_t` | global tile instance, matched by name at startup |
| Factory | NULL-terminated pointer array | `TILES[]` in `main.h` | compile-time; add `extern` + array entry |
| Template Method | `#define` + `#include` | `fd_stem.c` | macros defined before the include |
| Adapter | first-member struct embedding | `fd_aio_tango_tx_t` | construction site |
| Bridge | sig field protocol bits | `fd_disco_netmux_sig` | encoding at send, decoding at receive |
| Observer | function pointer struct | `fd_quic_callbacks_t` | `quic->callbacks` before run |
| Dependency Injection | workspace injection | `fd_topo_run_tile` launch | topology builder |

Each pattern has one or zero dynamic dispatch points.  None rely on heap
allocation as the enabling mechanism, none use type-erased `void *`
pointers beyond narrowly owned adapter boundaries, and none require a
global registry at runtime.  When writing new Firedancer-style C code,
reach for these patterns before inventing a new mechanism.

## Isolation

### Tiles

A tile is the unit of execution.  In the topology model, a tile has:

- a name and `kind_id`,
- a CPU affinity,
- input links,
- output links,
- scratch memory,
- metrics memory,
- object-use declarations with read-only or read-write mode.

Production Firedancer sandboxes tiles as separate processes for security
and failure containment.  Some test or development paths can run tiles
as threads in one process, but code should not rely on same-process
globals unless the tile explicitly runs that way.

### Processes, Threads, And Tpool

The system architecture is process-first.  A tile boundary should be
treated as a process boundary even when a test harness runs tiles as
threads.  That means no hidden dependence on global variables, inherited
file descriptors, ambient capabilities, or equal virtual addresses.

Threads appear in three main places:

- Launch/test modes that run tiles in one process for convenience.
- Utility thread pools (`fd_tpool_t`) used by explicit parallel
  algorithms.
- External library or sanitizer behavior that the runtime isolates from
  tile assumptions.

If a tile uses a tpool or helper thread, document which data is shared,
which thread owns each mutation, and how work completion is synchronized.
Do not add a background thread to a tile just to avoid modeling work in
the run loop; it weakens the topology and sandbox story.

### Launch Sequence

`fd_topo_run_tile` follows this shape:

1. Set process/thread names and logging identity.
2. Join required workspaces before sandboxing.
3. Run `privileged_init` while privileged operations are still possible.
4. Build allowed file-descriptor and seccomp lists.
5. Enter sandbox or switch uid/gid.
6. Fill topology joins for IPC objects.
7. Register metrics.
8. Run `unprivileged_init`.
9. Enter the tile run loop.

Put privileged setup only in `privileged_init`: opening sockets, XDP
setup, files that must exist before seccomp, or other operations needing
capabilities.  Put normal object joins and local state wiring in
`unprivileged_init`.

### Sandbox

Tiles use seccomp policies, dropped privileges, rlimits, explicit file
descriptor allow-lists, and explicit workspace mappings.  If a tile
needs a syscall after sandboxing, add it deliberately through its policy
and explain why.

Unexpected syscalls should crash.  That is part of the design: a tile's
runtime authority should be narrow enough that a mistake is immediately
visible.

### How Isolation Is Enforced

Process isolation and memory isolation are separate layers that work
together.

At launch, `fd_topo_run_tile` first maps the workspaces a tile needs by
calling `fd_topo_join_tile_workspaces`.  The topology decides this from
the tile's `uses_obj_*` list.  A workspace is joined with
`FD_SHMEM_JOIN_MODE_READ_ONLY` or `FD_SHMEM_JOIN_MODE_READ_WRITE`; that
mode becomes the `mmap` protection (`PROT_READ` or
`PROT_READ|PROT_WRITE`) used for the mapping.

Then the tile enters the sandbox.  After that point, the process should
not be able to open arbitrary files, map new shared-memory regions, gain
capabilities, or issue syscalls outside its policy.  Finally,
`fd_topo_fill_tile` resolves the already-mapped local addresses for the
tile's IPC objects and the tile starts its run loop.

The enforcement chain is:

1. Separate processes give each tile a separate virtual address space.
   A pointer in one tile is not valid in another tile unless both
   processes separately mapped the same shared memory.
2. Topology controls which workspaces are mapped into each tile at all.
   Unmapped memory cannot be peeked by normal loads; the CPU page tables
   do not contain it, so access faults.
3. The shared-memory join mode controls write permission.  A read-only
   mapping may be read, but a store into it faults through normal OS
   page protection.
4. The sandbox is entered after required mappings and privileged setup.
   Seccomp, landlock, namespaces, rlimits, dropped capabilities, and the
   file-descriptor allow-list prevent the tile from asking the kernel to
   regain broad access.
5. The tile's C code still has to follow the topology contract.  If a
   workspace is mapped read-write because the tile owns one object in
   that workspace, the OS protects at workspace/page granularity, not at
   C struct granularity.

That last point matters.  A tile cannot read an unmapped workspace, and
it cannot write a read-only mapping.  But if unrelated objects are placed
in a workspace that the tile legitimately maps read-write, page
protection alone will not distinguish those objects.  Use separate
workspaces, read-only mappings, and clear one-writer ownership to make
the memory protection boundary match the design boundary.

### Seccomp Policies

Seccomp is a Linux kernel facility for filtering syscalls.  Firedancer
uses seccomp-BPF: a small BPF program is installed into the kernel for a
tile process, and the kernel checks each syscall against that filter.
Allowed syscalls proceed.  Unexpected syscalls are denied or kill the
process, depending on the generated policy behavior.

Policies are kept as tile-specific `.seccomppolicy` files, for example
under network, GUI, RPC, and capture tile directories.  Generated
headers such as `generated/fd_xdp_tile_seccomp.h` provide the BPF
instruction arrays.  Each tile exposes `populate_allowed_seccomp` in
its `fd_topo_run_tile_t`; `fd_topo_run_tile` calls it before sandboxing
and passes the resulting filter to `fd_sandbox_enter`.

Seccomp does not protect C memory directly.  It protects the syscall
surface.  For example, it can prevent a tile from calling `open`,
`mmap`, `ptrace`, `clone`, or other operations that would expand what
the process can observe or mutate.  Memory access itself is enforced by
the process address space and page permissions that were established
before seccomp was installed.

When adding tile behavior, ask:

- Does this require a new syscall after sandboxing?
- Can the work instead happen in `privileged_init` before the sandbox?
- Is a file descriptor opened before sandboxing and included in the
  allow-list?
- Does the tile need host networking, `connect`, `renameat`, or another
  explicit sandbox exception?
- Does the new shared memory need to be mapped read-only or read-write,
  and should it live in a separate workspace?

### Shared Memory Modes

`fd_topob_tile_uses` records whether a tile maps an object read-only or
read-write.  Treat this as a design-level permission, not just a memory
protection detail.  During launch, these declarations are converted into
shared-memory join modes and then into OS page protections:

- read-only topology use becomes `FD_SHMEM_JOIN_MODE_READ_ONLY`, then
  `PROT_READ`,
- read-write topology use becomes `FD_SHMEM_JOIN_MODE_READ_WRITE`, then
  `PROT_READ|PROT_WRITE`,
- no declared use means the workspace does not need to be mapped into
  that tile process.

Examples:

- Network RX UMEM/dcache is writable by net/kernel/NIC, but normally
  read-only to app tiles.
- TX links from app tiles are read-only to net tile consumers, except
  the producing app owns its own write path.
- Metrics are written by the tile that owns them and read by monitoring
  or metric tiles.

If a change needs broader read-write sharing, assume it is suspicious
until the ownership and synchronization story is clear.

## Atomicity And Ordering

Firedancer targets x86-64 Linux for the production Firedancer path.  A
lot of Tango relies on x86's TSO properties: reads are not reordered
with reads, and writes by one processor are observed in order by other
processors.  That lets hot paths avoid expensive hardware fences while
using compiler fences to prevent the compiler from reordering stores and
loads.

Important distinctions:

- `FD_COMPILER_MFENCE` constrains the compiler.  It is not a hardware
  memory fence.
- `FD_VOLATILE` and `FD_VOLATILE_CONST` force volatile access, not a
  full synchronization protocol.
- `__atomic_store_n(..., __ATOMIC_RELEASE)` and related builtins are
  used where the code requires explicit release/acquire semantics.
- Naturally aligned scalar loads and stores are relied on where the
  architecture guarantees atomicity.
- SSE 128-bit aligned stores are used where x86 documents atomicity.
- AVX 256-bit metadata publication is used only under the assumptions
  documented in the mcache implementation.

Do not casually add atomics to "make it safer."  Atomics add cost and
can still be wrong if the protocol is wrong.  Instead, identify the
producer, consumer, published sequence, and overrun behavior.

Do not port Firedancer hot-path synchronization to ARM by search and
replace.  The repo-level guidance is that Firedancer only supports
x86-64 Linux because some designs assume TSO.

## Synchronization And Housekeeping

Synchronization in Firedancer is usually a protocol, not a mutex.  When
reviewing a shared object, identify the whole protocol:

- who is the only writer,
- which sequence, version, fseq, or state word publishes progress,
- which compiler or atomic ordering rule protects that publication,
- what a reader does on stale data, overrun, restart, or shutdown,
- where diagnostics are counted.

The common synchronization tools are:

- topology and workspace mappings for coarse access control,
- one-writer ownership for normal data mutation,
- mcache sequence publication for link fragments,
- fseq/fctl credit exchange for reliable consumers,
- cnc state and heartbeat for tile lifecycle,
- housekeeping for low-rate publication of diagnostics and control
  state.

Housekeeping is bounded periodic work performed by the tile run loop.  It
is not a separate garbage collector, not a background worker, and not an
unbounded queue that waits for a quiet time.  In stem-based tiles,
`lazy` controls the approximate cadence, and stem interleaves small async
events into the hot loop:

- receive reliable-consumer credits,
- publish input fseq progress and drain input diagnostics,
- write tile heartbeat and regime metrics,
- call `STEM_CALLBACK_METRICS_WRITE` if the tile provides one,
- call `STEM_CALLBACK_DURING_HOUSEKEEPING` for tile-local periodic work.

This keeps the packet or fragment path short.  The hot path increments
tile-local counters and advances local state.  Housekeeping later moves
those counters into shared metrics memory, refreshes flow-control state,
and services low-frequency control work.  Shutdown also writes final
metrics state so operators do not lose the last local counters.

Do not hide correctness-critical work in housekeeping.  It is lazy and
bounded.  It is appropriate for metrics, heartbeats, fseq updates,
credit refresh, timer checks, and compact state-machine maintenance.  It
is not appropriate for work that must happen before accepting the next
fragment unless the stem callback contract explicitly says so.

## Inter-Tile Communication

### Tango Messages

Tango is the internal message-passing substrate.  A message is made of
one or more ordered fragments.  Each fragment has:

- `seq`: global sequence number on the link,
- `sig`: application-defined signature for fast filtering,
- `chunk`: compressed payload location,
- `sz`: payload size,
- `ctl`: origin and SOM/EOM/ERR bits,
- `tsorig` and `tspub`: compressed diagnostic timestamps.

The two main shared objects are:

- `mcache`: metadata cache.  It maps recent sequence numbers to
  `fd_frag_meta_t` entries.
- `dcache`: payload cache.  It stores fragment bytes at chunk-aligned
  positions.

### Mcache Versus Dcache

The `mcache` and `dcache` are deliberately separate.  Treat the mcache
as the ordered publication index, and the dcache as the byte storage that
some publications point into.

The mcache answers:

- which sequence exists at this slot,
- what signature and control bits describe it,
- where the payload starts,
- how many bytes the payload has,
- when the producer observed and published it.

The dcache answers:

- where the payload bytes live,
- how large the payload region can be,
- where the producer should write the next fragment,
- when old payload bytes may be overwritten by wraparound.

Do not think of a link as "a queue of allocated messages."  It is closer
to a fixed-size metadata ring plus a fixed-size payload arena.  The
producer writes payload bytes into the dcache first, then publishes the
mcache entry that makes those bytes visible.  Consumers trust the mcache
for ordering and use the dcache only through `chunk` and `sz`.

Example:

```c
/* Producer owns output publication.  Payload is written before metadata. */
uchar * dst = fd_chunk_to_laddr( dcache_base, chunk );
fd_memcpy( dst, packet, packet_sz );

fd_mcache_publish( mcache, depth, seq, sig, chunk, packet_sz,
                   ctl, tsorig, tspub );

/* Consumer reads metadata, then converts the chunk to a local address. */
fd_frag_meta_t const meta = *mline;
uchar const * src = fd_chunk_to_laddr_const( dcache_base, meta.chunk );
ulong         sz  = meta.sz;
```

The consumer must still re-check the mcache line after reading or
copying payload.  A fast producer may have reused both the mcache slot
and the dcache bytes before the consumer finished.  The stable object is
not the pointer returned from `fd_chunk_to_laddr`; the stable contract is
the sequence validation protocol around it.

Use an mcache without meaningful dcache payload when the fragment is only
a signal, control marker, or tiny value encoded in metadata.  Use a
dcache when the fragment carries bytes that would be too large or too
variable to store in metadata.  If a consumer needs bytes after advancing
its input sequence, copy them out before advancing.

The mcache acts like a direct-mapped ring over sequence space.  Publishing
a new sequence implicitly evicts an older sequence.  Consumers must
handle gaps and overruns.

### Publish Pattern

The generic mcache publish sequence is:

1. Mark the line as being written by storing `seq-1`.
2. Store the rest of the metadata.
3. Publish by storing `seq`.

Consumers wait for a target sequence, copy metadata, process payload
speculatively, and then re-read the mcache line's sequence to ensure the
producer did not overwrite it during processing.

This pattern is a deliberate alternative to locks.  It makes overruns
detectable and keeps producer publication cheap.

### Links

A topology link is one producer and one or more consumers.  It has:

- an mcache,
- optionally a dcache,
- a depth,
- an MTU,
- a burst size,
- reliability settings per consumer.

There is no magical global bus.  If a tile receives data, the topology
must declare the link.  If a tile writes data, the topology must declare
the output link.  This makes capacity, memory use, and access control
visible.

### Reliable And Unreliable Consumers

Reliable consumers return progress through `fseq` objects.  Producers or
stem use `fctl` credit accounting to avoid overwriting data that a
reliable consumer still needs.

Unreliable consumers can be overrun.  This is often the right choice for
network ingress, monitoring, duplicate detection, or data that is
valuable only while fresh.  Unreliable does not mean unchecked: consumers
must detect gaps and recover.

`fd_fctl.h` says the quiet part plainly: backpressure is dangerous in a
large distributed system.  Use reliable flow control only when losing
the data would break correctness and when bounded queues are sized for
the real burst.

Real example: a telemetry tile reads a high-rate stream to build live
operator views.  If the telemetry tile is slow for 50 ms, stopping the
producer would also stop the rest of the processing pipeline.  That is
the wrong tradeoff: stale telemetry should be skipped, counted, and
recovered from the next fresh fragment.  A correctness-critical consumer
is different.  If a downstream tile must see every fragment to preserve
state, then the link should be reliable and the producer should wait for
credits.

In topology terms, that decision is made per consumer when wiring the
tile input:

```c
/* Monitoring can lag.  It should not stall the producer. */
fd_topob_tile_in( topo, "metric", 0UL, "metric_in",
                  "events", 0UL,
                  FD_TOPOB_UNRELIABLE,
                  FD_TOPOB_POLLED );

/* Correctness-critical state must not miss fragments. */
fd_topob_tile_in( topo, "state", 0UL, "state_in",
                  "events", 0UL,
                  FD_TOPOB_RELIABLE,
                  FD_TOPOB_POLLED );
```

What actually happens under the hood:

- The producer publishes every fragment to the link mcache.
- An unreliable consumer tracks the next expected sequence.  If the
  mcache no longer holds that sequence, the consumer detects an overrun,
  increments diagnostics, and jumps to a recoverable newer sequence.
- A reliable consumer publishes its progress through an `fseq`.
- The producer or stem checks reliable consumers through `fctl` credits
  before publishing more fragments.  If credits are exhausted, the
  producer is backpressured.

In run-loop form, the unreliable side is shaped like this:

```c
FD_MCACHE_WAIT( meta, mline, seq_found, seq_diff, poll_max,
                mcache, depth, rx_seq );

if( FD_UNLIKELY( seq_diff ) ) {
  /* We fell behind.  Count the loss and resume from a fresh sequence. */
  lost_cnt += (ulong)fd_long_max( seq_diff, 1L );
  rx_seq = seq_found;
  continue;
}

/* Process the fresh fragment. */
rx_seq = fd_seq_inc( rx_seq, 1UL );
```

The exact recovery policy is application-specific.  The architectural
rule is: use unreliable links for data that can be skipped, and keep
reliable links for data whose loss would corrupt state.

### Stem

Most tiles use `fd_stem.c` as an included template to generate a tile
run loop.  Stem:

- polls input mcaches,
- shuffles fan-in polling to avoid fixed-order bias,
- handles reliable-output credits,
- calls tile-defined callbacks,
- runs housekeeping on a lazy schedule,
- drains link and tile metrics.

Housekeeping in stem is a scheduled slice of the same run loop.  Stem
does not stop the tile and drain a large backlog.  It processes one
small async event at a time: a reliable-credit update, an input fseq and
diagnostic drain, or a metrics/control callback.  The event order is
shuffled with the rest of the polling machinery so no input is favored
forever under load.

Important callbacks:

- `BEFORE_CREDIT`: run every loop, even while backpressured.  Useful for
  servicing sockets or timers.
- `AFTER_CREDIT`: run when downstream credits are available.  Useful for
  publishing data not directly caused by a fragment.
- `BEFORE_FRAG`: fast signature filtering before reading payload.
- `DURING_FRAG`: copy or read payload while overrun checks still protect
  the consumer.
- `AFTER_FRAG`: publish downstream or update state after the fragment is
  accepted.  Do not rely on payload still being stable here unless the
  callback contract says it is.
- `DURING_HOUSEKEEPING`: do lower-frequency work, update fseq, publish
  metrics, service control state.

Keep stem callbacks small and deterministic.  If a callback can block on
I/O, allocate memory, or issue a syscall, it needs an explicit reason and
usually belongs outside the hot path.

Do not use housekeeping as a hidden repair queue.  If a tile needs to
preserve every item, the input or output needs reliable flow control and
bounded storage sized in topology.  If the item is non-critical, the
usual pattern is to count loss locally and move on.

## Intra-Tile Communication

Within one tile, prefer plain structs, arrays, rings, and generated
templates.  A tile usually has one thread of hot execution, so internal
state does not need locks unless a helper thread or tpool is involved.

Common patterns:

- Context struct in scratch, passed to callbacks.
- Hot counters accumulated in local fields and flushed to metrics during
  housekeeping.
- Ring indices kept as local cached producer/consumer values and
  written back periodically.
- State machines encoded as enum-like integers or explicit structs.
- Separate "privileged" and "unprivileged" initialization phases.

Avoid splitting tile-local state into many heap objects.  A contributor
should be able to inspect the context struct and understand the tile's
live memory.

## Data Processing Patterns

### Bounded Structures

Most data structures are bounded by construction:

- `fd_pool`: fixed-capacity object pools.
- `fd_map`, `fd_map_chain`, `fd_map_slot`, `fd_map_dynamic`: specialized
  hash maps.
- `fd_heap`, `fd_prq`: priority structures.
- `fd_treap`: ordered search with randomized priorities.
- `fd_slist`, `fd_dlist`, `fd_deque`, `fd_queue`, `fd_stack`: intrusive
  list and queue families.
- `fd_sort`: generated sort and select routines.
- `fd_bplus`: ordered block structure.

These are usually intrusive.  Elements include fields like `next`,
`prev`, `heap_left`, `heap_right`, `map_next`, or `treap_parent`.
Those fields are owned by the container while the element is in the
container and may be repurposed in another state.  The FEC resolver is a
good example: one union overlays map, treap, and free-list fields
depending on whether a context is active or free.

The advantage is zero per-element allocation, compact memory, and
predictable lifetime.  The cost is that the contributor must preserve
container invariants carefully.

### Sorting And Search

Use `fd_sort.c` rather than ad hoc sort code when sorting POD keys.
This file looks strange because it is a C template.  A caller defines a
few preprocessor symbols, includes the `.c` file, and gets a specialized
family of functions for that key type and ordering:

```c
#define SORT_NAME        sort_pair
#define SORT_KEY_T       pair_t
#define SORT_BEFORE(a,b) ((a).mykey<(b).mykey)
#include "../../util/tmpl/fd_sort.c"

sort_pair_inplace( pair, pair_cnt );
```

That include generates names such as:

- `sort_pair_insert`,
- `sort_pair_stable_scratch_align`,
- `sort_pair_stable_scratch_footprint`,
- `sort_pair_stable_fast`,
- `sort_pair_stable`,
- `sort_pair_inplace`,
- `sort_pair_select`,
- `sort_pair_split`,
- and, when requested, parallel variants.

The point is not cleverness for its own sake.  It gives C some of the
benefits of templates without introducing a runtime abstraction:

- The comparator is inlined.  There is no `qsort` callback call for
  every comparison.
- The key type is concrete.  The compiler can see the element size,
  alignment, copy pattern, and branch shape.
- The generated function names are type-specific, so there is no global
  generic sort state.
- Scratch memory is caller-provided and sized explicitly.  No hidden
  heap allocation appears in the sort path.
- The same specification can generate stable, in-place, select, split,
  and parallel routines with one comparator definition.

The generated routines include:

- insertion sort for small or nearly sorted arrays,
- stable merge sort with caller-provided scratch,
- in-place quicksort,
- selection,
- split/lower-bound style search over sorted arrays,
- optional parallel variants.

Choose the variant intentionally:

- Use `*_insert` for very small or nearly sorted arrays.
- Use `*_stable` when equal keys must keep input order and the result
  must end in the original array.
- Use `*_stable_fast` when the caller can accept the result being either
  in the input array or in the scratch array.
- Use `*_inplace` when scratch memory is undesirable and stability is
  not required.
- Use `*_select` when only one rank is needed, such as a median or
  cutoff.
- Use `*_split` after sorting when you need the partition point for a
  query key.

`SORT_BEFORE(a,b)` is a strict "a comes before b" predicate, not a
three-way comparator.  It must be consistent and should not have side
effects.  In particular, do not write subtraction comparators that can
overflow:

```c
/* good */
#define SORT_BEFORE(a,b) ((a).slot<(b).slot)

/* avoid */
#define SORT_BEFORE(a,b) (((long)(a).slot-(long)(b).slot)<0L)
```

If the key is a struct, keep the sorted value compact.  Sorting huge
objects by value can turn comparison work into memory bandwidth work.  A
common high-throughput pattern is to sort small descriptors, indices, or
keys that point at larger state owned elsewhere.

Use generated maps when lookup is hot and the key type is known.  Choose
the map family based on the needed concurrency, key/value storage, and
collision behavior already used nearby.

When comparing attacker-controlled numeric fields, avoid subtraction
that can overflow.  Use explicit less-than checks and `fd_*_if`
helpers, as in the FEC resolver's `(slot, fec_idx)` comparison.

### Hashing And Partitioning

Hash functions often encode ownership.  For example, store partitions
its map chains by shred tile index so parallel inserts cannot collide
across writers.  Do not change a hash function just for distribution
without checking whether it also encodes a concurrency guarantee.

When a data structure uses a seed, ask whether the seed is:

- randomness for collision hardening,
- a partition count,
- a map-chain count,
- an implementation detail for deterministic tests.

### In-Place And Append-Only

Many hot paths mutate in place or append only:

- mcache publication overwrites old sequence slots.
- dcache advances through compact chunks and wraps at a watermark.
- store inserts are append-only for shred tiles; remove is exclusive and
  infrequent.
- funk creates fork-aware transactions and records in preallocated
  shared structures.

In-place mutation is acceptable when it is paired with sequence checks,
ownership, or a lock.  It is dangerous when a reader can observe a
partially updated value with no way to detect it.

## Telemetry, Logs, And Diagnostics

### Logging

Use `FD_LOG_*` macros.  The double parentheses are part of the API:

```c
FD_LOG_NOTICE(( "booting tile %s:%lu", name, kind_id ));
```

Levels:

- `DEBUG`: normally suppressed.
- `INFO`: detailed log file.
- `NOTICE`: operator-visible normal events.
- `WARNING`: unexpected but survivable; flushes logs.
- `ERR`: logs then exits the program with error.
- `CRIT` and above: logs, backtraces if possible, aborts.

Guidelines:

- Do not log in packet-rate hot paths except through rate-limited,
  diagnostic, or impossible-corruption paths.
- Prefer counters for frequent events.
- Use `FD_LOG_ERR` when continuing would violate a required invariant.
- Use `FD_TEST` for internal invariants in tests and startup-like code,
  but prefer explicit error logs for operator-facing configuration
  failures.
- Do not call logger APIs from signal handlers.

### Metrics

Metrics live in shared memory as `ulong` arrays.  `fd_metrics_register`
sets thread-local base pointers, and macros such as `FD_MCNT_INC`,
`FD_MGAUGE_SET`, and `FD_MHIST_COPY` update fixed offsets generated from
`metrics.xml`.

The metrics region intentionally carries little metadata.  Consumers use
statically compiled metric definitions.  This keeps snapshots cheap.

Guidelines:

- Low-frequency counters may be updated directly.
- High-frequency counters should be accumulated in tile-local fields and
  flushed during housekeeping to reduce cache traffic.
- Do not `memcpy` arbitrary state into the metrics region.
- After editing `metrics.xml`, regenerate metrics as documented in
  `AGENTS.md`:

```sh
make -C src/disco/metrics metrics
```

### Observability Pattern

Non-critical observations are usually counted, not queued.  For a
high-rate telemetry link, the consumer should count fragments received,
bytes received, overruns, stale fragments, and local drops in tile-local
fields.  During housekeeping, it flushes those counters to the generated
metrics arrays.

That means telemetry is not normally held in an unbounded "better times"
queue.  If the telemetry consumer is slow and the link is unreliable,
old fragments are overwritten in the mcache or dcache, the consumer
detects the sequence gap, increments an overrun or drop counter, and
resumes from a fresh sequence.  If the data must not be lost, the link
should be reliable and the producer should participate in fseq/fctl
backpressure.

Logs are separate from metrics.  `FD_LOG_*` formats and writes the log
message when the log call is made, subject to configured levels and
duplicate suppression.  Warnings and errors may flush the logfile.  Do
not log one line per dropped telemetry fragment.  Log configuration
errors, impossible corruption, startup facts, shutdown facts, or
rate-limited diagnostics.  Use counters for frequent events.

Example:

```c
/* Hot path: no log call and no shared metrics write per fragment. */
ctx->telemetry_frag_cnt++;
ctx->telemetry_byte_cnt += sz;

if( FD_UNLIKELY( seq_diff ) ) {
  ctx->telemetry_overrun_cnt++;
  ctx->telemetry_drop_cnt += (ulong)fd_long_max( seq_diff, 1L );
  rx_seq = seq_found;
  continue;
}

/* Housekeeping: publish accumulated local counters.
   Assume metrics.xml defines these counters for this tile. */
FD_MCNT_INC( TILE, TELEMETRY_FRAGMENT_COUNT, ctx->telemetry_frag_cnt );
FD_MCNT_INC( TILE, TELEMETRY_BYTE_COUNT,     ctx->telemetry_byte_cnt );
FD_MCNT_INC( TILE, TELEMETRY_OVERRUN_COUNT,  ctx->telemetry_overrun_cnt );
FD_MCNT_INC( TILE, TELEMETRY_DROP_COUNT,     ctx->telemetry_drop_cnt );

ctx->telemetry_frag_cnt    = 0UL;
ctx->telemetry_byte_cnt    = 0UL;
ctx->telemetry_overrun_cnt = 0UL;
ctx->telemetry_drop_cnt    = 0UL;
```

The metric names above are illustrative.  Use generated metric names
from `metrics.xml`, and keep the local counters in the tile context or
stem input accumulator that owns the observation.

### Command And Control

`fd_cnc_t` is for low-bandwidth control and health state.  It has a
small state machine: BOOT, RUN, USER, HALT, FAIL.  Tiles heartbeat
through cnc so monitors can distinguish a live tile from a stalled or
dead one.

Do not use cnc for data-plane messages.  Use Tango links for data-plane
traffic and cnc for control-plane signals.

## Design Choices That Look Like Anti-Patterns

These choices are intentional in this codebase, but they come with
rules.

### Busy Polling

Many tiles never sleep.  A busy loop on a dedicated core can be cheaper
and more predictable than kernel wakeups.  This only makes sense when
CPU affinity, isolation, and operator expectations are explicit.

Do not add sleeps to hot loops to make them "polite" unless the tile is
not latency-sensitive and existing local code does the same.

### Macros As Generics

Template inclusion looks old-fashioned, but it avoids void pointers,
function-pointer dispatch, allocator hooks, and ABI constraints.  It
also lets each generated container know its element layout and index
width.

Use the template style already present in the module.

### Intrusive Containers

Container metadata inside elements would be a poor default for general
application code.  Here it reduces allocations, improves locality, and
lets memory be checkpointed or inspected as flat data.

Be careful when one field is shared by multiple container states.  The
state transition must remove from one container before reusing the field
for another.

### Shared Memory Instead Of RPC

Inside a host, shared memory avoids serialization, copies, and syscalls.
The price is that ownership and memory ordering are now part of the
program logic.

Do not introduce a socket or RPC-like channel between tiles unless the
communication crosses a host boundary or the local architecture already
requires it.

### Crash-Only Failure

Many invariant violations call `FD_LOG_ERR` or `FD_LOG_CRIT`.  In a
high-throughput system, silently continuing after corrupt queue metadata, unexpected
syscalls, or invalid topology is worse than a loud crash.

If a condition is caused by untrusted external input, handle it as data.
If it violates an internal invariant, crash early.

### Readable But Not Portable C

Firedancer uses C17, LP64 assumptions, x86 features, SIMD, huge pages,
Linux syscalls, XDP, seccomp, and TSO.  Portability exists where the
base utilities support it, but the full Firedancer runtime path is an
x86-64 Linux system.

Do not dilute hot-path code to chase portability the runtime does not
claim.

### Compiler Fences Instead Of Locks

The queue protocol often uses compiler fences and ordered scalar stores
rather than mutexes or full hardware fences.  This is correct only under
the documented ownership, alignment, and architecture assumptions.

Do not imitate this pattern in new shared state unless you can write
down the publication protocol and overrun detection.

## Contribution Checklist

Before changing a tile or shared primitive, answer:

- Does this belong in Firedancer paths, or is it Frankendancer-specific?
- If this changes configuration, have the TOML default, `config_t`
  field, validation, topology effect, sandbox effect, and diagnostics
  all been updated together?
- Which topology object, workspace, or link owns the new memory?
- Is capacity fixed at startup?  If not, why not?
- Is each shared field single-writer, locked, atomically published, or
  protected by sequence validation?
- Are read-only mappings preserved where possible?
- Does the tile need a new syscall, file descriptor, rlimit, or
  capability after sandboxing?
- Does the change add backpressure?  If yes, is it correctness-critical?
- Is payload data copied before the fragment can be overrun?
- Are metrics updated without adding cache-line traffic to hot paths?
- Are logs reserved for operator-relevant or impossible states?
- If generated code inputs changed, did you run the regeneration target?
- Does the test match the risk: unit for local logic, integration/system
  for topology, IPC, or sandbox behavior?

## Practical Rules Of Thumb

- If a shared object does not have an `align/footprint/new/join` style
  API, ask whether it should.
- If a pointer crosses tile boundaries, it is probably wrong unless it
  is a workspace-relative address, compact chunk, or documented
  same-process exception.
- If a consumer can lag, write the overrun path first.
- If a data path can drop, count drops.
- If a branch is a rare error path, mark it `FD_UNLIKELY`.
- If a branch handles attacker-controlled input, do not mark impossible
  states as impossible unless they truly are internal invariants.
- If a callback reads fragment bytes and uses them later, copy them in
  `DURING_FRAG`.
- If a tile needs to do periodic work, put it in housekeeping or a stem
  before/after-credit callback, not in a blocking side thread.
- If a data structure is in a workspace, store `gaddr` or compact
  indices for persistent references, not local pointers.
- If a change makes a queue deeper, also think about latency, memory
  footprint, TLB pressure, and overrun recovery.

## A Minimal Mental Model

Think of Firedancer as a set of small, isolated machines:

1. Topology builds the machines, their memory, and their wires.
2. The runner maps only the memory each machine is allowed to see.
3. The sandbox removes ambient OS authority.
4. Tango links carry bounded fragments between machines.
5. Each machine runs a hot loop, updates local state, and publishes
   metrics.
6. Shared state is either single-writer, explicitly locked, or published
   through sequence-aware protocols.

When contributing, keep that model intact.  The codebase is fast because
it refuses to hide ownership, capacity, isolation, and memory ordering
behind general-purpose abstractions.
