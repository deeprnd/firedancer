/* Thin wrappers around Firedancer's per-process tile launcher
   (fd_topo_run_tile) and the two workspace/link-join steps it composes.
   This is the only file in Tickoni that includes fd_topo.h.

   _GNU_SOURCE matches fd_topo_run.c's own first line: fd_topo.h's tile
   union needs PATH_MAX (glibc only exposes it under _GNU_SOURCE/POSIX
   feature-test macros). */
#define _GNU_SOURCE
#include "../../../util/fd_util.h"
#include "../../../disco/events/fd_event_report.h"
#include "../../../disco/metrics/fd_metrics.h"
#include "../../../disco/topo/fd_topo.h"
#include "../../../util/wksp/fd_wksp.h"

#include <unistd.h>

#if FD_HAS_MACOS
#include <pthread.h>
#endif

void
tk_topo_join_tile_workspaces( void * topo, void * tile, int core_dump_level ) {
  fd_topo_join_tile_workspaces( (fd_topo_t *)topo, (fd_topo_tile_t *)tile, core_dump_level );
}

void
tk_topo_fill_tile( void * topo, void * tile ) {
  fd_topo_fill_tile( (fd_topo_t *)topo, (fd_topo_tile_t *)tile );
}

static void
tk_topo_set_thread_name( fd_topo_tile_t const * tile ) {
  char thread_name[ 20 ];
  if( FD_UNLIKELY( !fd_cstr_printf_check( thread_name, sizeof( thread_name ), NULL, "%s:%lu", tile->name, tile->kind_id ) ) ) return;

#if FD_HAS_LINUX
  if( FD_UNLIKELY( prctl( PR_SET_NAME, thread_name, 0, 0, 0 ) ) )
    FD_LOG_ERR(( "prctl(PR_SET_NAME) failed (%i-%s)", errno, fd_io_strerror( errno ) ));
#elif FD_HAS_MACOS && defined(__APPLE__)
  (void)pthread_setname_np( thread_name );
#else
  (void)tile;
#endif
}

static void
tk_topo_attach_workspaces( fd_topo_t * topo ) {
  char workspace_name[ 272 ];
  for( ulong i = 0UL; i < topo->wksp_cnt; i++ ) {
    fd_topo_wksp_t * wksp = &topo->workspaces[ i ];
    if( FD_LIKELY( wksp->wksp ) ) continue;
    if( FD_UNLIKELY( !fd_cstr_printf_check( workspace_name, sizeof( workspace_name ), NULL,
                                            "%s_%s.wksp", topo->app_name, wksp->name ) ) )
      FD_LOG_ERR(( "workspace name too long for %s:%s", topo->app_name, wksp->name ));
    wksp->wksp = fd_wksp_attach( workspace_name );
    if( FD_UNLIKELY( !wksp->wksp ) )
      FD_LOG_ERR(( "fd_wksp_attach failed for workspace %s", workspace_name ));
  }
}

/* Tickoni process mode uses normal-page workspaces created via wkspNewNamed,
   not Firedancer's huge/gigantic-page fd_topo_join_tile_workspaces path.
   Reattach the deterministic "<app>_<wksp>.wksp" regions directly, then
   preserve Firedancer's remaining launch order. */
static void
tk_topo_run_tile_no_sandbox( fd_topo_t *          topo,
                             fd_topo_tile_t *     tile,
                             int                  core_dump_level,
                             fd_topo_run_tile_t * tile_run ) {
  (void)core_dump_level;
  tk_topo_set_thread_name( tile );
  tk_topo_attach_workspaces( topo );

  if( FD_UNLIKELY( tile_run->privileged_init ) )
    tile_run->privileged_init( topo, tile );

  fd_topo_fill_tile( topo, tile );

  FD_TEST( tile->metrics );
  fd_metrics_register( tile->metrics );
  fd_event_register( topo, tile );

  ulong pid = (ulong)getpid();
  FD_MGAUGE_SET( TILE, PID, pid );
  FD_MGAUGE_SET( TILE, TID, pid );

  if( FD_UNLIKELY( tile_run->unprivileged_init ) )
    tile_run->unprivileged_init( topo, tile );

  tile_run->run( topo, tile );
  if( FD_UNLIKELY( !tile->allow_shutdown ) ) FD_LOG_ERR(( "tile %s:%lu run loop returned", tile->name, tile->kind_id ));

  FD_MGAUGE_SET( TILE, STATUS, 2UL );
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
#if FD_HAS_LINUX
  if( FD_LIKELY( sandbox ) ) {
    fd_topo_run_tile( (fd_topo_t *)topo, (fd_topo_tile_t *)tile, sandbox,
                      keep_controlling_terminal, core_dump_level, uid, gid,
                      allow_fd, (fd_topo_run_tile_t *)tile_run );
    return;
  }
#else
  (void)keep_controlling_terminal;
  (void)uid;
  (void)gid;
  (void)allow_fd;
#endif
  (void)sandbox;
  tk_topo_run_tile_no_sandbox( (fd_topo_t *)topo, (fd_topo_tile_t *)tile,
                               core_dump_level, (fd_topo_run_tile_t *)tile_run );
}
