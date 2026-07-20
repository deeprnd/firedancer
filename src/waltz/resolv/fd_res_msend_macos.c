#define _DARWIN_C_SOURCE /* POSIX/C99 extensions on macOS */
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <fcntl.h>
#include <signal.h>

#include "fd_res_msend.h"

/* macOS does not expose SOCK_CLOEXEC / SOCK_NONBLOCK.
 * Create a plain socket then set O_CLOEXEC + O_NONBLOCK via fcntl.
 * Also no MSG_NOSIGNAL — block SIGPIPE in fd_start_tcp instead.
 *
 * In cross-compile environments (<signal.h> may not define
 * SIGPIPE/SIG_IGN/SIG_DFL), define them ourselves. */
#ifndef SIGPIPE
#define SIGPIPE 13
#endif
#ifndef SIG_IGN
#define SIG_IGN ((void(*)(int))-1)
#endif
#ifndef SIG_DFL
#define SIG_DFL ((void(*)(int))0)
#endif

static int
fd_set_nonblocking_cloexec( int fd ) {
  int flags = fcntl( fd, F_GETFL );
  if( flags < 0 ) return -1;
  if( fcntl( fd, F_SETFL, flags | O_NONBLOCK ) < 0 ) return -1;
  if( fcntl( fd, F_SETFD, fcntl( fd, F_GETFD ) | FD_CLOEXEC ) < 0 ) return -1;
  return 0;
}

int
fd_socket_create( int family, int type ) {
  int fd = socket( family, type, 0 );
  if( fd >= 0 && fd_set_nonblocking_cloexec( fd ) < 0 ) {
    close( fd );
    return -1;
  }
  return fd;
}

void
fd_close( int fd ) {
  close( fd );
}

int
fd_start_tcp( struct pollfd * pfd,
              int             family,
              void const *    sa,
              socklen_t       sl,
              uchar const *   q,
              int             ql ) {
  int fd = fd_socket_create( family, SOCK_STREAM );
  pfd->fd = fd;

  if( fd < 0 ) return -1;

  /* macOS: no TCP_FASTOPEN_CONNECT or MSG_NOSIGNAL.
   * Block SIGPIPE, use plain send(). */
  int r = connect( fd, sa, sl );
  if( !r || errno == EINPROGRESS ) return 0;

  /* Block SIGPIPE for this send */
  (void)signal( SIGPIPE, SIG_IGN );

  /* Send length prefix */
  uchar header[2] = { (uchar)(ql>>8), (uchar)ql };
  int sent = (int)send( fd, header, 2U, 0 );
  if( sent < 2 ) goto fail;

  /* Send query data */
  sent = (int)send( fd, q, (size_t)ql, 0 );
  if( sent < ql ) goto fail;

  /* Restore SIGPIPE */
  (void)signal( SIGPIPE, SIG_DFL );

  pfd->events = POLLIN;
  return 0;

fail:
  (void)signal( SIGPIPE, SIG_DFL );
  close( fd );
  pfd->fd = -1;
  return -1;
}
