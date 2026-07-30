#define _GNU_SOURCE
#include "fd_util.h"

#if FD_HAS_HOSTED && !FD_HAS_WINDOWS

#include <poll.h>
#include <sched.h>
#include <time.h>

void fd_yield( void ) { sched_yield(); }

int
fd_syscall_poll( struct pollfd * fds,
                 uint            nfds,
                 int             timeout ) {
# if FD_HAS_LINUX
  if( timeout<0 ) {
    return ppoll( fds, nfds, NULL, NULL );
  } else {
    struct timespec ts = {
      .tv_sec  = (long)( timeout/1000 ),
      .tv_nsec = (long)((timeout%1000)*1000000),
    };
    return ppoll( fds, nfds, &ts, NULL );
  }
# else
  return poll( fds, nfds, timeout );
# endif
}

#endif
