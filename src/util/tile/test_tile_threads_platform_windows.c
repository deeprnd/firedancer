/* Unit tests for Windows tile threading stub (fd_tile_threads_platform_windows.c).
 *
 * Tests:
 *   - fd_tile_private_boot() — verify no crash, tile_id0 > 0
 *   - fd_tile_private_halt() — verify no crash
 *   - fd_tile_id(), fd_tile_cnt(), fd_tile_idx() — verify boot sets values
 *   - fd_tile_exec_new() — verify returns NULL (stub)
 *   - fd_tile_exec_done() — verify returns 1 (stub)
 *   - fd_tile_exec_delete() — verify returns NULL (stub)
 *   - fd_tile_private_cpus_parse() — verify returns 1 (stub)
 *
 * On non-Windows, this is a no-op stub. */

#include "fd_util.h"
#include "fd_tile.h"
#include "fd_tile_private.h"

#if FD_HAS_WINDOWS

int
main( int argc, char **argv ) {
  fd_boot( &argc, &argv );

  /* Test 1: fd_tile_private_boot() — verify no crash, deterministic values */
  {
    int pargc = 1;
    char *pargv[] = { (char *)"test", NULL };

    fd_tile_private_boot( &pargc, &pargv );

    /* Verify tile_id0 > 0 (from thread_id on Windows) */
    ulong id0 = fd_tile_id0();
    FD_TEST( id0 > 0 );
    ulong cnt = fd_tile_cnt();
    FD_TEST( cnt == 1 ); /* Stub creates 1 tile */
    FD_LOG_NOTICE( ( "boot: tile_id0=%lu, cnt=%lu (correct)", id0, cnt ) );
  }

  /* Test 2: fd_tile_id(), fd_tile_idx() after boot */
  {
    ulong id = fd_tile_id();
    ulong idx = fd_tile_idx();

    /* After boot, id should be tile_id0, idx should be 0 */
    FD_TEST( id == fd_tile_id0() );
    FD_TEST( idx == 0 );
    FD_LOG_NOTICE( ( "boot: id=%lu, idx=%lu (correct)", id, idx ) );
  }

  /* Test 3: fd_tile_exec_new() — verify returns NULL (stub) */
  {
    fd_tile_exec_t *exec = fd_tile_exec_new( 0, NULL, 0, NULL );
    FD_TEST( exec == NULL );
    FD_LOG_NOTICE( ( "exec_new: NULL (correct for stub)" ) );
  }

  /* Test 4: fd_tile_exec_done() — verify returns 1 (stub says "done") */
  {
    int done = fd_tile_exec_done( NULL );
    FD_TEST( done == 1 );
    FD_LOG_NOTICE( ( "exec_done(NULL): 1 (correct for stub)" ) );
  }

  /* Test 5: fd_tile_exec_delete() — verify returns NULL (stub) */
  {
    int opt_ret = 0;
    char const *result = fd_tile_exec_delete( NULL, &opt_ret );
    FD_TEST( result == NULL );
    FD_TEST( opt_ret == 0 );
    FD_LOG_NOTICE( ( "exec_delete(NULL): NULL, opt_ret=0 (correct for stub)" ) );
  }

  /* Test 6: fd_tile_exec accessor stubs — verify no crash */
  {
    (void)fd_tile_exec_id;
    (void)fd_tile_exec_idx;
    (void)fd_tile_exec_task;
    (void)fd_tile_exec_argc;
    (void)fd_tile_exec_argv;
    /* Just verify they don't crash when called with NULL */
    FD_TEST( fd_tile_exec_id( NULL ) == 0 );
    FD_TEST( fd_tile_exec_idx( NULL ) == 0 );
    FD_TEST( fd_tile_exec_task( NULL ) == NULL );
    FD_TEST( fd_tile_exec_argc( NULL ) == 0 );
    FD_TEST( fd_tile_exec_argv( NULL ) == NULL );
    FD_LOG_NOTICE( ( "exec accessors: OK" ) );
  }

  /* Test 7: fd_tile_private_cpus_parse() — verify returns 1 (stub) */
  {
    ushort tile_to_cpu[ FD_TILE_MAX ];
    ulong result = fd_tile_private_cpus_parse( NULL, tile_to_cpu );
    FD_TEST( result == 1 );
    FD_LOG_NOTICE( ( "cpus_parse: returns 1 (correct for stub)" ) );
  }

  /* Test 8: fd_tile_private_halt() — verify no crash */
  {
    fd_tile_private_halt();
    FD_LOG_NOTICE( ( "halt: OK" ) );
  }

  FD_LOG_NOTICE( ( "pass" ) );
  fd_halt();
  return 0;
}

#else

/* On non-Windows, this file is a no-op stub. */
int
main( int argc, char **argv ) {
  (void)argc;
  (void)argv;
  return 0;
}

#endif
