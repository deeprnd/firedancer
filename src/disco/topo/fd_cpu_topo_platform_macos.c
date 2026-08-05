/* macOS stub CPU topology — single CPU, single NUMA node.
   Full macOS implementation to be added when macOS support is active.
   macOS lacks /sys/devices/system/cpu/* that Linux topo uses. */

#include "fd_cpu_topo.h"

void
fd_topo_cpus_init_platform( fd_topo_cpus_t * cpus ) {
  cpus->numa_node_cnt = 1UL;
  cpus->cpu_cnt = 1UL;
  cpus->cpu[0].idx = 0UL;
  cpus->cpu[0].online = 1;
  cpus->cpu[0].numa_node = 0UL;
  cpus->cpu[0].sibling = ULONG_MAX;
}

void
fd_topo_cpus_printf_platform( fd_topo_cpus_t * cpus ) {
  FD_LOG_NOTICE(( "cpu0: online=1 sibling=%lu numa_node=0", cpus->cpu[0].sibling ));
}
