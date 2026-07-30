#include "fd_grpc_client.h"
#include "../h2/fd_h2_callback.h"
#include "../../util/fd_platform_stub_object.h"

#include <errno.h>
#include <string.h>

#if FD_HAS_WINDOWS

struct fd_grpc_client_private {
  fd_grpc_client_callbacks_t const * callbacks;
  fd_grpc_client_metrics_t *         metrics;
  void *                             ctx;
  uchar                              version_len;
  char                               version[ FD_GRPC_CLIENT_VERSION_LEN_MAX+1UL ];
  uchar                              host_len;
  char                               host[ 256UL ];
  ushort                             port;
};

fd_h2_callbacks_t const fd_grpc_client_h2_callbacks = {0};

ulong
fd_grpc_client_align( void ) {
  return alignof( fd_grpc_client_t );
}

ulong
fd_grpc_client_footprint( ulong buf_max ) {
  (void)buf_max;
  return fd_platform_stub_object_footprint( fd_grpc_client_align(), sizeof( fd_grpc_client_t ) );
}

fd_grpc_client_t *
fd_grpc_client_new( void *                             mem,
                    fd_grpc_client_callbacks_t const * callbacks,
                    fd_grpc_client_metrics_t *         metrics,
                    void *                             app_ctx,
                    ulong                              buf_max,
                    ulong                              rng_seed ) {
  (void)buf_max;
  (void)rng_seed;
  fd_grpc_client_t * client = fd_platform_stub_object_new( mem,
                                                           fd_grpc_client_align(),
                                                           sizeof( fd_grpc_client_t ) );
  if( FD_UNLIKELY( !client ) ) return NULL;

  *client = (fd_grpc_client_t){
    .callbacks = callbacks,
    .metrics   = metrics,
    .ctx       = app_ctx,
    .version_len = 5,
    .port      = 0
  };
  memcpy( client->version, "0.0.0", 6UL );
  memset( client->host, 0, sizeof(client->host) );
  if( metrics ) *metrics = (fd_grpc_client_metrics_t){0};
  return client;
}

void *
fd_grpc_client_delete( fd_grpc_client_t * client ) {
  return fd_platform_stub_object_delete( client, fd_grpc_client_align() );
}

void
fd_grpc_client_reset( fd_grpc_client_t * client ) {
  if( client && client->metrics ) *client->metrics = (fd_grpc_client_metrics_t){0};
}

void
fd_grpc_client_set_version( fd_grpc_client_t * client,
                            char const *       version,
                            ulong              version_len ) {
  if( FD_UNLIKELY( !client ) ) return;
  if( FD_UNLIKELY( version_len > FD_GRPC_CLIENT_VERSION_LEN_MAX ) ) return;
  if( version_len && version ) memcpy( client->version, version, version_len );
  client->version[ version_len ] = '\0';
  client->version_len = (uchar)version_len;
}

void
fd_grpc_client_set_authority( fd_grpc_client_t * client,
                              char const *       host,
                              ulong              host_len,
                              ushort             port ) {
  if( FD_UNLIKELY( !client ) ) return;
  host_len = fd_ulong_min( host_len, sizeof(client->host)-1UL );
  if( host_len && host ) memcpy( client->host, host, host_len );
  client->host[ host_len ] = '\0';
  client->host_len = (uchar)host_len;
  client->port = port;
}

#if FD_HAS_OPENSSL
int
fd_grpc_client_rxtx_ossl( fd_grpc_client_t * client,
                          SSL *              ssl,
                          int *              charge_busy ) {
  (void)client; (void)ssl;
  if( charge_busy ) *charge_busy = 0;
  errno = ENOTSUP;
  return -1;
}
#endif

int
fd_grpc_client_rxtx_socket( fd_grpc_client_t * client,
                            int                sock_fd,
                            int *              charge_busy ) {
  (void)client; (void)sock_fd;
  if( charge_busy ) *charge_busy = 0;
  errno = ENOTSUP;
  return -1;
}

fd_grpc_h2_stream_t *
fd_grpc_client_request_start( fd_grpc_client_t *   client,
                              char const *         path,
                              ulong                path_len,
                              ulong                request_ctx,
                              pb_msgdesc_t const * fields,
                              void const *         message,
                              char const *         auth_token,
                              ulong                auth_token_sz,
                              int                  is_streaming ) {
  (void)client; (void)path; (void)path_len; (void)request_ctx;
  (void)fields; (void)message; (void)auth_token; (void)auth_token_sz; (void)is_streaming;
  return NULL;
}

fd_grpc_h2_stream_t *
fd_grpc_client_request_start1( fd_grpc_client_t *   client,
                               char const *         path,
                               ulong                path_len,
                               ulong                request_ctx,
                               uchar const *        protobuf,
                               ulong                protobuf_sz,
                               char const *         auth_token,
                               ulong                auth_token_sz,
                               int                  is_streaming ) {
  (void)client; (void)path; (void)path_len; (void)request_ctx;
  (void)protobuf; (void)protobuf_sz; (void)auth_token; (void)auth_token_sz; (void)is_streaming;
  return NULL;
}

int
fd_grpc_client_stream_send_msg( fd_grpc_client_t *    client,
                                fd_grpc_h2_stream_t * stream,
                                pb_msgdesc_t const *  fields,
                                void const *          message ) {
  (void)client; (void)stream; (void)fields; (void)message;
  return 0;
}

int
fd_grpc_client_stream_send_msg1( fd_grpc_client_t *    client,
                                 fd_grpc_h2_stream_t * stream,
                                 uchar const *         protobuf,
                                 ulong                 protobuf_sz ) {
  (void)client; (void)stream; (void)protobuf; (void)protobuf_sz;
  return 0;
}

int
fd_grpc_client_stream_close( fd_grpc_client_t *    client,
                             fd_grpc_h2_stream_t * stream ) {
  (void)client; (void)stream;
  return 0;
}

void
fd_grpc_client_deadline_set( fd_grpc_h2_stream_t * stream,
                             int                   deadline_kind,
                             long                  ts_nanos ) {
  (void)stream; (void)deadline_kind; (void)ts_nanos;
}

int
fd_grpc_client_is_connected( fd_grpc_client_t * client ) {
  (void)client;
  return 0;
}

int
fd_grpc_client_request_is_blocked( fd_grpc_client_t * client ) {
  (void)client;
  return 1;
}

int
fd_grpc_client_request_stream_busy( fd_grpc_client_t * client ) {
  (void)client;
  return 0;
}

fd_h2_rbuf_t *
fd_grpc_client_rbuf_tx( fd_grpc_client_t * client ) {
  (void)client;
  return NULL;
}

fd_h2_rbuf_t *
fd_grpc_client_rbuf_rx( fd_grpc_client_t * client ) {
  (void)client;
  return NULL;
}

fd_h2_conn_t *
fd_grpc_client_h2_conn( fd_grpc_client_t * client ) {
  (void)client;
  return NULL;
}

#endif
