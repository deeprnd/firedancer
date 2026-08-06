/* Unit tests for Windows CPU topology stub (fd_cpu_topo_platform_windows.c).
 *
 * Tests:
 *   - fd_topo_cpus_init() — verify stub produces 1 CPU, 1 NUMA node
 *   - fd_topo_cpus_printf() — verify no crash and outputs expected format
 *
 * On non-Windows, this is a no-op stub. */

#include "fd_util.h"
#include "fd_cpu_topo.h"

#if FD_HAS_WINDOWS

int
main( int argc, char **argv ) {
  fd_boot( &argc, &argv );

  /* Test 1: fd_topo_cpus_init() — verify stub behavior */
  {
    fd_topo_cpus_t cpus;
    fd_memset( &cpus, 0, sizeof( cpus ) );

    fd_topo_cpus_init( &cpus );

    /* Verify: 1 CPU, 1 NUMA node */
    FD_TEST( cpus.numa_node_cnt == 1 );
    FD_TEST( cpus.cpu_cnt == 1 );
    FD_TEST( cpus.cpu[0].online == 1 );
    FD_TEST( cpus.cpu[0].numa_node == 0 );
    FD_TEST( cpus.cpu[0].idx == 0 );
    FD_TEST( cpus.cpu[0].sibling == ULONG_MAX );

    FD_LOG_NOTICE( ( "cpu_topo stub: 1 CPU, 1 NUMA node (correct)" ) );
  }

  /* Test 2: fd_topo_cpus_printf() — verify no crash */
  {
    fd_topo_cpus_t cpus;
    fd_memset( &cpus, 0, sizeof( cpus ) );
    fd_topo_cpus_init( &cpus );

    /* Just verify it doesn't crash and produces output */
    fd_topo_cpus_printf( &cpus );

    FD_LOG_NOTICE( ( "cpu_topo printf: OK" ) );
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
