#ifndef HEADER_fd_src_util_fd_windows_compat_h
#define HEADER_fd_src_util_fd_windows_compat_h

#if FD_HAS_WINDOWS

/* CRT function name mappings — Windows uses underscore-prefixed names
   for POSIX-standard functions. These macros make Windows compile
   standard C code without modification. */
#define strcasecmp  _stricmp
#define strncasecmp _strnicmp
#define strdup      _strdup
#define snprintf    _snprintf
#define vsnprintf   _vsnprintf

/* STDOUT_FILENO — Windows CRT uses _fileno(stderr), but the numeric
   value is the same on both platforms. Provide it here so
   fd_log.h can use FD_LOG_STDOUT() without including <unistd.h>. */
#if !defined(STDOUT_FILENO)
#define STDOUT_FILENO 1
#endif

/* POSIX file permission mode bits — Windows doesn't expose these
   in sys/stat.h. Provide fallbacks on all platforms so code that
   uses S_IRUSR/S_IWUSR compiles regardless of _XOPEN_SOURCE level. */
#if !defined(S_IRUSR)
#define S_IRUSR 0600
#endif
#if !defined(S_IWUSR)
#define S_IWUSR 0600
#endif

/* Windows CRT errno helper — returns EOPNOTSUPP for unsupported
   POSIX features in Windows stub code. */
#include <errno.h>
static __inline int fd_windows_unsupported_enotsup( void ) { return EOPNOTSUPP; }

/* Windows CRT security macro */
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

/* Default I/O and logging styles for Windows — match what
   windows_clang.mk / build.zig set via -DFD_IO_STYLE=1.
   Source files that select POSIX vs generic style should just
   check FD_IO_STYLE / FD_LOG_STYLE without re-deriving the default. */
#ifndef FD_IO_STYLE
#define FD_IO_STYLE 1
#endif
#ifndef FD_LOG_STYLE
#define FD_LOG_STYLE 1
#endif

#else

/* Non-Windows: include standard headers for POSIX functions */
#include <strings.h>

/* Fallback defaults for standalone builds that don't go through
   the Makefile/Zig flag propagation. */
#ifndef FD_IO_STYLE
#define FD_IO_STYLE 0
#endif
#ifndef FD_LOG_STYLE
#define FD_LOG_STYLE 0
#endif

#endif /* FD_HAS_WINDOWS */

#endif /* HEADER_fd_src_util_fd_windows_compat_h */
