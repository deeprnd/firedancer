#define _GNU_SOURCE /* SYS_close */
#include <sys/syscall.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>

#include "fd_res_msend.h"

int
fd_socket_create( int family, int type ) {
  return socket( family, type|SOCK_CLOEXEC|SOCK_NONBLOCK, 0 );
}

void
fd_close( int fd ) {
  syscall( SYS_close, fd );
}

int
fd_start_tcp( struct pollfd * pfd,
              int             family,
              void const *    sa,
              socklen_t       sl,
              uchar const *   q,
              int             ql ) {
  int fd = socket( family, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0 );
  pfd->fd = fd;

  /* TCP Fast Open (Linux only) */
  if( !setsockopt( fd, IPPROTO_TCP, TCP_FASTOPEN_CONNECT,
      &(int){1}, sizeof(int) ) ) {
    /* Build msghdr for sendmsg (Fast Open path). */
    struct msghdr mh = {
      .msg_name    = (void *)sa,
      .msg_namelen = sl,
      .msg_iovlen  = 2,
      .msg_iov = (struct iovec [2]){\
        { .iov_base = (uchar[]){ (uchar)(ql>>8), (uchar)ql }, .iov_len = 2 },\
        { .iov_base = (void *)q, .iov_len = (size_t)ql } },\
      .msg_control    = NULL,\
      .msg_controllen = 0,\
      .msg_flags      = 0\
    };
    int r = (int)sendmsg( fd, &mh, MSG_FASTOPEN|MSG_NOSIGNAL );
    if( r == ql+2 ) pfd->events = POLLIN;
    if( r >= 0 ) return r;
    if( errno == EINPROGRESS ) return 0;
  }

  int r = connect( fd, sa, sl );
  if( !r || errno == EINPROGRESS ) return 0;
  close( fd );
  pfd->fd = -1;
  return -1;
}
