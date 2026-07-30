#include "fd_udpsock.h"
#include "../../util/fd_platform_stub_object.h"

#include <errno.h>

#if FD_HAS_WINDOWS

struct __attribute__((aligned(FD_UDPSOCK_ALIGN))) fd_udpsock {
  fd_aio_t         aio_self;
  fd_aio_t const * aio_rx;
  uint             ip_self_addr;
  ushort           udp_self_port;
  uint             layer;
  int              fd;
};

static int
fd_udpsock_send( void *                    ctx,
                 fd_aio_pkt_info_t const * batch,
                 ulong                     batch_cnt,
                 ulong *                   opt_batch_idx,
                 int                       flush ) {
  (void)ctx; (void)batch; (void)batch_cnt; (void)flush;
  if( opt_batch_idx ) *opt_batch_idx = 0UL;
  errno = ENOTSUP;
  return FD_AIO_ERR_INVAL;
}

FD_FN_CONST ulong
fd_udpsock_align( void ) {
  return FD_UDPSOCK_ALIGN;
}

FD_FN_CONST ulong
fd_udpsock_footprint( ulong mtu,
                      ulong rx_pkt_cnt,
                      ulong tx_pkt_cnt ) {
  if( FD_UNLIKELY( !mtu || !rx_pkt_cnt || !tx_pkt_cnt ) ) return 0UL;
  return fd_platform_stub_object_footprint( fd_udpsock_align(), sizeof( fd_udpsock_t ) );
}

void *
fd_udpsock_new( void * shmem,
                ulong  mtu,
                ulong  rx_pkt_cnt,
                ulong  tx_pkt_cnt ) {
  (void)mtu; (void)rx_pkt_cnt; (void)tx_pkt_cnt;
  fd_udpsock_t * sock = fd_platform_stub_object_new( shmem,
                                                     fd_udpsock_align(),
                                                     sizeof( fd_udpsock_t ) );
  if( FD_UNLIKELY( !sock ) ) return NULL;

  sock->fd    = -1;
  sock->layer = FD_UDPSOCK_LAYER_ETH;
  sock->aio_self = (fd_aio_t){ .ctx = sock, .send_func = fd_udpsock_send };
  return shmem;
}

fd_udpsock_t *
fd_udpsock_join( void * shsock,
                 int    fd ) {
  fd_udpsock_t * sock = fd_platform_stub_object_join( shsock, fd_udpsock_align() );
  if( FD_UNLIKELY( !sock ) ) return NULL;
  sock->fd = fd;
  return sock;
}

void *
fd_udpsock_leave( fd_udpsock_t * sock ) {
  return fd_platform_stub_object_leave( sock );
}

void *
fd_udpsock_delete( void * shsock ) {
  return fd_platform_stub_object_delete( shsock, fd_udpsock_align() );
}

void
fd_udpsock_set_rx( fd_udpsock_t *   sock,
                   fd_aio_t const * aio ) {
  if( FD_UNLIKELY( !sock ) ) return;
  sock->aio_rx = aio;
}

FD_FN_CONST fd_aio_t const *
fd_udpsock_get_tx( fd_udpsock_t * sock ) {
  return sock ? &sock->aio_self : NULL;
}

void
fd_udpsock_service( fd_udpsock_t * sock ) {
  (void)sock;
}

FD_FN_PURE uint
fd_udpsock_get_ip4_address( fd_udpsock_t const * sock ) {
  return sock ? sock->ip_self_addr : 0U;
}

FD_FN_PURE uint
fd_udpsock_get_listen_port( fd_udpsock_t const * sock ) {
  return sock ? (uint)sock->udp_self_port : 0U;
}

fd_udpsock_t *
fd_udpsock_set_layer( fd_udpsock_t * sock,
                      uint           layer ) {
  if( FD_UNLIKELY( !sock ) ) return NULL;
  sock->layer = layer;
  return sock;
}

#endif /* FD_HAS_WINDOWS */
