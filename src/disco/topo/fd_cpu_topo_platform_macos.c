/* macOS stub CPU topology.
   macOS lacks the /sys/devices/system/cpu/ filesystem that Linux topo uses.
   Full macOS implementation to be added when macOS support is active. */

#include "fd_cpu_topo.h"

void
fd_topo_cpus_init_platform( fd_topo_cpus_t * cpus ) {
  cpus->cpu_cnt          = 1UL;
  cpus->numa_node_cnt    = 1UL;
  cpus->cpu[ 0 ].idx     = 0UL;
  cpus->cpu[ 0 ].online  = 1;
  cpus->cpu[ 0 ].numa_node = 0UL;
  cpus->cpu[ 0 ].sibling = ULONG_MAX;
}

void
fd_topo_cpus_printf_platform( fd_topo_cpus_t * cpus ) {
  for( ulong i=0UL; i<cpus->cpu_cnt; i++ )
    FD_LOG_NOTICE(( "cpu%lu: online=%i sibling=%lu numa_node=%lu",
                     i, cpus->cpu[ i ].online,
                     cpus->cpu[ i ].sibling, cpus->cpu[ i ].numa_node ));
}
