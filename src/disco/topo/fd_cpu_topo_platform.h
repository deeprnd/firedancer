#ifndef HEADER_fd_src_disco_topo_fd_cpu_topo_platform_h
#define HEADER_fd_src_disco_topo_fd_cpu_topo_platform_h

#include "fd_cpu_topo.h"

/* Platform-specific CPU topology initialization.
   Called once at boot to populate cpus->cpu[] with discovered topology. */
void
fd_topo_cpus_init_platform( fd_topo_cpus_t * cpus );

/* Platform-specific CPU topology printing.
   Called during boot diagnostics to display detected CPUs. */
void
fd_topo_cpus_printf_platform( fd_topo_cpus_t * cpus );

#endif /* HEADER_fd_src_disco_topo_fd_cpu_topo_platform_h */
