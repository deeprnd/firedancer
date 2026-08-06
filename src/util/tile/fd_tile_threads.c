/* Thin dispatcher for tile thread management platform functions.
   Platform-specific implementations live in fd_tile_threads_platform_*.c.
   This file stays identical across Linux, macOS, and Windows.

   Public prototypes are declared in fd_tile.h. Internal declarations
   live in fd_tile_private.h. Platform implementations implement the
   symbols declared in fd_tile_threads_platform.h. */

#include "fd_tile_threads_platform.h"
