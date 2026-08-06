#ifndef HEADER_fd_src_util_tile_fd_tile_threads_platform_h
#define HEADER_fd_src_util_tile_fd_tile_threads_platform_h

/* This header is included by all platform-specific fd_tile_threads_platform_*.c
   files. It provides the common platform-independent declarations that those
   files implement. See fd_tile_threads.c (the dispatcher) for public-facing
   prototypes. */

#include "fd_tile_private.h"

/* Platform-specific CPU config type — defined separately per platform. */
struct fd_tile_private_cpu_config {
  int prio;
};

typedef struct fd_tile_private_cpu_config fd_tile_private_cpu_config_t;

#endif /* HEADER_fd_src_util_tile_fd_tile_threads_platform_h */
