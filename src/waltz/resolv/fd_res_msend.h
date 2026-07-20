#ifndef HEADER_fd_src_waltz_resolv_fd_res_msend_h
#define HEADER_fd_src_waltz_resolv_fd_res_msend_h

#include "../../util/fd_util_base.h"
#include <poll.h>

FD_PROTOTYPES_BEGIN

/* Platform-abstracted socket creation.
 * On Linux: socket(family, type|SOCK_CLOEXEC|SOCK_NONBLOCK, 0)
 * On macOS: socket(family, type, 0), then fcntl(O_CLOEXEC|O_NONBLOCK)
 *
 * Returns file descriptor, or -1 on error.
 * Sets errno on failure. */
int
fd_socket_create( int family, int type );

/* Close a file descriptor.
 * On Linux: syscall(SYS_close, fd)
 * On macOS: close(fd) */
void
fd_close( int fd );

/* Create a TCP socket and send the query via connect + sendmsg.
 * On Linux: uses TCP_FASTOPEN_CONNECT.
 * On macOS: plain connect + send.
 *
 * Returns bytes sent (>0), 0 if EINPROGRESS, or -1 on error.
 * On success, sets *pfd->fd to the socket and *pfd->events to POLLIN.
 * On EINPROGRESS, leaves pfd->fd set but events=0 (caller does poll).
 * On error, sets pfd->fd=-1. */
int
fd_start_tcp( struct pollfd * pfd,
              int             family,
              void const *    sa,
              socklen_t       sl,
              uchar const *   q,
              int             ql );

FD_PROTOTYPES_END

#endif /* HEADER_fd_src_waltz_resolv_fd_res_msend_h */
