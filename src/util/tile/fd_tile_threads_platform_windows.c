/* Windows stub implementation of tile thread management.
   Full Windows implementation to be added when Windows support is active. */

#include <windows.h>
#include <process.h>

#include "../sanitize/fd_sanitize.h"
#include "../fd_util_base.h"
#include "fd_tile.h"
#include "fd_tile_private.h"
#include "fd_tile_threads_platform.h"

/* Windows stub uses the same struct type as the platform header so that
   the definition is consistent across all platforms. */
static inline void
fd_tile_private_cpu_config( fd_tile_private_cpu_config_t * save,
                            ulong                          cpu_idx ) {
  (void)cpu_idx; *save = 0;
}

static inline void
fd_tile_private_cpu_restore( fd_tile_private_cpu_config_t * save ) {
  (void)save;
}


void *
fd_tile_private_stack_new( int   optimize, ulong cpu_idx ) {
  (void)optimize; (void)cpu_idx; return NULL;
}

static void
fd_tile_private_stack_delete( void * _stack ) {
  (void)_stack;
}


static ulong fd_tile_private_id0;
static ulong fd_tile_private_id1;
static ulong fd_tile_private_cnt;
static FD_TL ulong fd_tile_private_id;
static FD_TL ulong fd_tile_private_idx;
FD_TL ulong fd_tile_private_stack0;
FD_TL ulong fd_tile_private_stack1;
static ushort fd_tile_private_cpu_id[ FD_TILE_MAX ];

ulong fd_tile_id0( void ) { return fd_tile_private_id0; }
ulong fd_tile_id1( void ) { return fd_tile_private_id1; }
ulong fd_tile_cnt( void ) { return fd_tile_private_cnt; }
ulong fd_tile_id( void ) { return fd_tile_private_id; }
ulong fd_tile_idx( void ) { return fd_tile_private_idx; }

ulong
fd_tile_cpu_id( ulong tile_idx ) {
  if( FD_UNLIKELY( tile_idx>=fd_tile_private_cnt ) ) return ULONG_MAX;
  return fd_ulong_if( fd_tile_private_cpu_id[ tile_idx ]<65535UL,
                      fd_tile_private_cpu_id[ tile_idx ], ULONG_MAX-1UL );
}

fd_tile_exec_t *
fd_tile_exec_new( ulong          idx, fd_tile_task_t task,
                  int            argc, char ** argv ) {
  (void)idx; (void)task; (void)argc; (void)argv;
  return NULL;
}

fd_tile_exec_t *
fd_tile_exec( ulong tile_idx ) {
  (void)tile_idx; return NULL;
}

ulong          fd_tile_exec_id( fd_tile_exec_t const * exec ) { (void)exec; return 0UL; }
ulong          fd_tile_exec_idx( fd_tile_exec_t const * exec ) { (void)exec; return 0UL; }
fd_tile_task_t fd_tile_exec_task( fd_tile_exec_t const * exec ) { (void)exec; return NULL; }
int            fd_tile_exec_argc( fd_tile_exec_t const * exec ) { (void)exec; return 0; }
char **        fd_tile_exec_argv( fd_tile_exec_t const * exec ) { (void)exec; return NULL; }

int
fd_tile_exec_done( fd_tile_exec_t const * exec ) {
  (void)exec; return 1;
}

char const *
fd_tile_exec_delete( fd_tile_exec_t * exec, int * opt_ret ) {
  (void)exec; (void)opt_ret;
  return NULL;
}

ulong
fd_tile_private_cpus_parse( char const * cstr, ushort * tile_to_cpu ) {
  (void)cstr; (void)tile_to_cpu;
  return 1UL;
}

void
fd_tile_private_map_boot( ushort * tile_to_cpu, ulong tile_cnt ) {
  (void)tile_to_cpu;
  fd_tile_private_id0 = fd_log_thread_id();
  fd_tile_private_id1 = fd_tile_private_id0 + tile_cnt;
  fd_tile_private_cnt = tile_cnt;
  fd_tile_private_id = fd_tile_private_id0;
  fd_tile_private_idx = 0UL;
  fd_tile_private_stack1 = 0UL;
  fd_tile_private_stack0 = 0UL;
  FD_LOG_INFO(( "fd_tile: boot success" ));
}

void
fd_tile_private_boot( int * pargc, char *** pargv ) {
  char const * cpus = fd_env_strip_cmdline_cstr( pargc, pargv, "--tile-cpus", "FD_TILE_CPUS", NULL );
  if( !cpus ) FD_LOG_INFO(( "fd_tile: --tile-cpus not specified" ));
  else FD_LOG_INFO(( "fd_tile: --tile-cpus \"%s\"", cpus ));
  ushort tile_to_cpu[ FD_TILE_MAX ];
  tile_to_cpu[0] = (ushort)65535;
  fd_tile_private_map_boot( tile_to_cpu, 1UL );
}

void
fd_tile_private_halt( void ) {
  fd_memset( fd_tile_private_cpu_id, 0, fd_tile_private_cnt*sizeof(ushort) );
  fd_tile_private_stack1 = 0UL;
  fd_tile_private_stack0 = 0UL;
  fd_tile_private_idx = 0UL;
  fd_tile_private_id = 0UL;
  fd_tile_private_cnt = 0UL;
  fd_tile_private_id1 = 0UL;
  fd_tile_private_id0 = 0UL;
  FD_LOG_INFO(( "fd_tile: halt success" ));
}
