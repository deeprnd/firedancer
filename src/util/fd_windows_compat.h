#ifndef HEADER_fd_src_util_fd_windows_compat_h
#define HEADER_fd_src_util_fd_windows_compat_h

#if FD_HAS_WINDOWS
#define strcasecmp  _stricmp
#define strncasecmp _strnicmp
#else
#include <strings.h>
#endif

#endif /* HEADER_fd_src_util_fd_windows_compat_h */
