#ifndef HEADER_fd_src_disco_topo_fd_topo_platform_h
#define HEADER_fd_src_disco_topo_fd_topo_platform_h

#include "../../util/fd_util.h"

/* Platform-specific constants and forward-declarations.
   This file keeps fd_topo.h free of inline OS switches. */

/* struct sock_filter: include the header that actually defines it so
   that the function-pointer type in fd_topo_run_tile_t matches the
   one seen by callers (fd_metric_tile.c, fd_diag_tile.c, etc.).

   Linux:     <linux/filter.h>   (also pulled in by seccomp headers)
   macOS/bsd: <sys/bpf.h>
   Windows:   forward-decl only (seccomp not available)
   Fallback:  forward-decl (type is opaque anyway — we only pass
              pointers, never dereference)
   */
#if defined(__linux__)
#include <linux/filter.h>
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
#include <sys/bpf.h>
#else
/* Windows or other: forward-declare only. */
struct sock_filter;
#endif

#if FD_HAS_WINDOWS

/* Windows uses different limits; override PATH_MAX here. */
#ifdef PATH_MAX
#undef PATH_MAX
#endif
#define PATH_MAX 4096

#else

/* Non-Windows: ensure PATH_MAX is defined, pull from limits.h if needed. */
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#endif /* FD_HAS_WINDOWS */

#endif /* HEADER_fd_src_disco_topo_fd_topo_platform_h */
