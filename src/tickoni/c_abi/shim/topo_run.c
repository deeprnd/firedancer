/* Thin wrappers around Firedancer's per-process tile launcher
   (fd_topo_run_tile) and the two workspace/link-join steps it composes.
   This is the only file in Tickoni that includes fd_topo.h.

   _GNU_SOURCE matches fd_topo_run.c's own first line: fd_topo.h's tile
   union needs PATH_MAX (glibc only exposes it under _GNU_SOURCE/POSIX
   feature-test macros). */
#define _GNU_SOURCE
#include "../../../util/fd_util.h"
#include "../../../disco/topo/fd_topo.h"

void
tk_topo_join_tile_workspaces( void * topo, void * tile, int core_dump_level ) {
  fd_topo_join_tile_workspaces( (fd_topo_t *)topo, (fd_topo_tile_t *)tile, core_dump_level );
}

void
tk_topo_fill_tile( void * topo, void * tile ) {
  fd_topo_fill_tile( (fd_topo_t *)topo, (fd_topo_tile_t *)tile );
}

void
tk_topo_run_tile( void * topo,
                  void * tile,
                  int    sandbox,
                  int    keep_controlling_terminal,
                  int    core_dump_level,
                  uint   uid,
                  uint   gid,
                  int    allow_fd,
                  void * tile_run ) {
  fd_topo_run_tile( (fd_topo_t *)topo, (fd_topo_tile_t *)tile, sandbox,
                    keep_controlling_terminal, core_dump_level, uid, gid,
                    allow_fd, (fd_topo_run_tile_t *)tile_run );
}
