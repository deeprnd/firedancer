#ifndef HEADER_fd_src_disco_topo_fd_topo_platform_h
#define HEADER_fd_src_disco_topo_fd_topo_platform_h

#include "../../util/fd_util.h"

/* Platform-specific constants and forward-declarations.
   This file keeps fd_topo.h free of inline OS switches. */

#if FD_HAS_WINDOWS

/* Windows uses different limits; override PATH_MAX here. */
#ifdef PATH_MAX
#undef PATH_MAX
#endif
#define PATH_MAX 4096

/* struct sock_filter is Linux-only (<linux/seccomp.h>).
   Forward-declare on other platforms since we only ever pass pointers to it. */
struct sock_filter;

#else

/* Non-Windows: ensure PATH_MAX is defined, pull from limits.h if needed. */
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#endif /* FD_HAS_WINDOWS */

#endif /* HEADER_fd_src_disco_topo_fd_topo_platform_h */
