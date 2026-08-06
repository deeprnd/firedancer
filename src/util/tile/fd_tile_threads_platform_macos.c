/* macOS implementation of tile thread management.
   macOS differs from Linux only in:
   - _DARWIN_C_SOURCE vs _GNU_SOURCE
   - pthread_setname_np vs prctl(PR_SET_NAME)
   - madvise(MADV_DONTFORK) is Linux-only (already gated)
   - __GLIBC__ checks for pthread_attr_setaffinity_np (already gated)

   All those differences are preprocessor-gated in the shared Linux
   source, so we simply define __MACH__ before including it. */

#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#define __MACH__ 1
#define FD_HAS_MACOS 1

#include "fd_tile_threads_platform_linux.c"
