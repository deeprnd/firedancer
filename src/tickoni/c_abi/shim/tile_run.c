/* V1.14.S8.T4: builds Tickoni's fd_topo_run_tile_t and exposes the
   simplified per-process entry point tile_process.zig calls.

   Deliberately a separate file from topo_run.c: this file's static
   TK_TILE_RUN struct references tk_tile_privileged_init/tk_tile_run,
   which are Zig `export fn`s defined only in
   src/tickoni/runtime/tile_process.zig. Any consumer that links this
   file must also link tile_process.zig's object code — true for the
   supervisor exe and the process-mode integration tests, but not for
   topo_run.c/topob.c's own standalone adapter unit tests, which is why
   this stays out of topo_run.c itself. */
#define _GNU_SOURCE
#include "../../../util/fd_util.h"
#include "../../../disco/topo/fd_topo.h"

#include <unistd.h>

/* fd_topo_run_tile_t's callbacks have a fixed C signature
   (fd_topo_t*, fd_topo_tile_t*) with no room for Zig closure state.
   Resolved the way Firedancer's own fdctl_tile_run pattern resolves it:
   these symbols are Zig `export fn`s taking (*anyopaque, *anyopaque) —
   never Firedancer types by name, satisfying tile_process.zig's "no
   Firedancer types" rule — that read a single per-process global Zig
   variable set once before tk_topo_run_tile_simple is called. Safe
   because Tickoni runs exactly one tile per process. */
extern void tk_tile_privileged_init( void * topo, void * tile );
extern void tk_tile_run( void * topo, void * tile );

/* sandbox=0-mode defaults throughout (V1.14.S8.T5 wires real sandbox
   entry later): keep_host_networking/allow_connect/allow_renameat/rlimit_*
   are only read inside fd_sandbox_enter, which only runs when sandbox=1
   (see fd_topo_run.c line ~102's `if (FD_LIKELY(sandbox))` branch), so
   leaving them 0 here is inert, not a real policy choice yet. */
static fd_topo_run_tile_t TK_TILE_RUN = {
  .name                     = "tickoni",
  .keep_host_networking     = 0,
  .allow_connect            = 0,
  .allow_renameat           = 0,
  .rlimit_file_cnt          = 0,
  .rlimit_address_space     = 0,
  .rlimit_data              = 0,
  .rlimit_nproc             = 0,
  .for_tpool                = 0,
  .max_event_sz             = NULL,
  .populate_allowed_seccomp = NULL,
  .populate_allowed_fds     = NULL,
  .scratch_align            = NULL,
  .scratch_footprint        = NULL,
  .loose_footprint          = NULL,
  .privileged_init          = (void (*)( fd_topo_t const *, fd_topo_tile_t const * ))tk_tile_privileged_init,
  .unprivileged_init        = NULL, /* nothing to do here yet; mcache/dcache/fseq/metrics
                                        auto-joined by fd_topo_fill_tile before this point,
                                        cnc already joined in privileged_init */
  .run                      = (void (*)( fd_topo_t *, fd_topo_tile_t * ))tk_tile_run,
  .rlimit_file_cnt_fn       = NULL,
};

/* Simplified entry point for Tickoni's one-tile-per-process model:
   sandbox=0 (T5 wires real sandbox entry), keep_controlling_terminal=1,
   regular core dumps, current process's real uid/gid (no user switch —
   fd_sandbox_switch_uid_gid still runs when sandbox=0, so passing the
   process's own identity makes that a no-op), no extra allowed fd. */
void
tk_topo_run_tile_simple( void * topo, void * tile ) {
  fd_topo_run_tile( (fd_topo_t *)topo, (fd_topo_tile_t *)tile,
                    /* sandbox */ 0, /* keep_controlling_terminal */ 1,
                    FD_TOPO_CORE_DUMP_LEVEL_REGULAR,
                    (uint)getuid(), (uint)getgid(), /* allow_fd */ -1,
                    &TK_TILE_RUN );
}
