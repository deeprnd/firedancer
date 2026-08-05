/* Thin dispatcher for CPU topology platform functions.
   Platform-specific implementations live in fd_cpu_topo_platform_*.c.
   This file stays identical across Linux, macOS, and Windows. */

#include "fd_cpu_topo_platform.h"

void
fd_topo_cpus_init( fd_topo_cpus_t * cpus ) {
  fd_topo_cpus_init_platform( cpus );
}

void
fd_topo_cpus_printf( fd_topo_cpus_t * cpus ) {
  fd_topo_cpus_printf_platform( cpus );
}
