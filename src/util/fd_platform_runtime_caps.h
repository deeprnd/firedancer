#ifndef HEADER_fd_src_util_fd_platform_runtime_caps_h
#define HEADER_fd_src_util_fd_platform_runtime_caps_h

#include "fd_platform_unsupported.h"

#define FD_WINDOWS_RUNTIME_CAPS_LOG_WARNING(api) FD_WINDOWS_UNSUPPORTED_LOG_WARNING( api )

FD_FN_CONST static inline ulong
fd_windows_runtime_caps_singleton_cnt( void ) {
  return 1UL;
}

FD_FN_CONST static inline ulong
fd_windows_runtime_caps_singleton_idx( ulong idx ) {
  return idx==0UL ? 0UL : ULONG_MAX;
}

#endif /* HEADER_fd_src_util_fd_platform_runtime_caps_h */
