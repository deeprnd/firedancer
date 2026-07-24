#include "fd_shmem_private.h"

ulong
fd_numa_node_cnt( void ) {
  FD_LOG_WARNING(( "no numa support for this build target" ));
  return 1UL;
}

ulong
fd_numa_cpu_cnt ( void ) {
  FD_LOG_WARNING(( "no numa support for this build target" ));
  return 1UL;
}

ulong
fd_numa_node_idx( ulong cpu_idx ) {
  (void)cpu_idx;
  FD_LOG_WARNING(( "no numa support for this build target" ));
  return 0UL;
}

#include <errno.h>

/* Stub NUMA functions for non-Linux platforms.
 * These are no-ops that succeed silently, since NUMA is not available
 * but Firedancer's workspace creation code expects the calls to succeed. */

int
fd_numa_mlock( void const * addr,
               ulong        len ) {
  (void)addr; (void)len;
  return 0;
}

int
fd_numa_munlock( void const * addr,
                 ulong        len ) {
  (void)addr; (void)len;
  return 0;
}

long
fd_numa_get_mempolicy( int *   mode,
                       ulong * nodemask,
                       ulong   maxnode,
                       void *  addr,
                       uint    flags ) {
  (void)nodemask; (void)maxnode; (void)addr; (void)flags;
  if (mode) *mode = MPOL_DEFAULT;
  return 0;
}

long
fd_numa_set_mempolicy( int           mode,
                       ulong const * nodemask,
                       ulong         maxnode ) {
  (void)mode; (void)nodemask; (void)maxnode;
  return 0;
}

long
fd_numa_mbind( void *        addr,
               ulong         len,
               int           mode,
               ulong const * nodemask,
               ulong         maxnode,
               uint          flags ) {
  (void)addr; (void)len; (void)mode; (void)nodemask; (void)maxnode; (void)flags;
  return 0;
}

long
fd_numa_move_pages( int         pid,
                    ulong       count,
                    void **     pages,
                    int const * nodes,
                    int *       status,
                    int         flags ) {
  (void)pid; (void)count; (void)pages; (void)nodes; (void)status; (void)flags;
  return 0;
}
