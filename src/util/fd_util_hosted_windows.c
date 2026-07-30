#include "fd_util.h"

#if FD_HAS_HOSTED && FD_HAS_WINDOWS

#include <errno.h>

void fd_yield( void ) { FD_SPIN_PAUSE(); }

int
fd_syscall_poll( struct pollfd * fds,
                 uint            nfds,
                 int             timeout ) {
  (void)fds;
  (void)nfds;
  (void)timeout;
  errno = ENOTSUP;
  return -1;
}

#endif
