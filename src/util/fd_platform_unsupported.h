#ifndef HEADER_fd_src_util_fd_platform_unsupported_h
#define HEADER_fd_src_util_fd_platform_unsupported_h

#include "fd_util_base.h"
#include <errno.h>

#define FD_WINDOWS_UNSUPPORTED_REASON(api) api " unsupported on Windows build lane"
#define FD_WINDOWS_UNSUPPORTED_CSTR        "unsupported on Windows build lane"
#define FD_WINDOWS_UNSUPPORTED_LOG_WARNING(api) FD_LOG_WARNING(( FD_WINDOWS_UNSUPPORTED_REASON( api ) ))

FD_FN_CONST static inline int
fd_windows_unsupported_enotsup( void ) {
  return ENOTSUP;
}

FD_FN_CONST static inline int
fd_windows_unsupported_enoent( void ) {
  return ENOENT;
}

FD_FN_CONST static inline void *
fd_windows_unsupported_null( void ) {
  return NULL;
}

static inline int
fd_windows_unsupported_fail( void ) {
  errno = ENOTSUP;
  return -1;
}

#endif /* HEADER_fd_src_util_fd_platform_unsupported_h */
