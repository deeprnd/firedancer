#include "fd_http_server.h"

#include <errno.h>
#include <stdarg.h>
#include <string.h>

#if FD_HAS_WINDOWS

struct __attribute__((aligned(FD_HTTP_SERVER_ALIGN))) fd_http_server_private {
  fd_http_server_params_t    params;
  fd_http_server_callbacks_t callbacks;
  void *                     callback_ctx;
  ulong                      stage_len;
  ulong                      stage_cap;
  int                        listen_fd;
  int                        stage_err;
};

FD_FN_CONST char const *
fd_http_server_connection_close_reason_str( int reason ) {
  (void)reason;
  return "http server unsupported on Windows build lane";
}

FD_FN_CONST char const *
fd_http_server_method_str( uchar method ) {
  switch( method ) {
    case FD_HTTP_SERVER_METHOD_GET:     return "GET";
    case FD_HTTP_SERVER_METHOD_POST:    return "POST";
    case FD_HTTP_SERVER_METHOD_OPTIONS: return "OPTIONS";
    case FD_HTTP_SERVER_METHOD_PUT:     return "PUT";
    default:                            return "UNKNOWN";
  }
}

FD_FN_CONST ulong
fd_http_server_align( void ) {
  return FD_HTTP_SERVER_ALIGN;
}

FD_FN_CONST ulong
fd_http_server_footprint( fd_http_server_params_t params ) {
  ulong footprint = sizeof(fd_http_server_t) + params.outgoing_buffer_sz;
  ulong align = fd_http_server_align();
  return ( footprint + align - 1UL ) & ~( align - 1UL );
}

void *
fd_http_server_new( void *                     shmem,
                    fd_http_server_params_t    params,
                    fd_http_server_callbacks_t callbacks,
                    void *                     callback_ctx ) {
  if( FD_UNLIKELY( !shmem ) ) return NULL;
  if( FD_UNLIKELY( (((ulong)shmem) & ( fd_http_server_align() - 1UL )) ) ) return NULL;
  fd_http_server_t * http = (fd_http_server_t *)shmem;
  *http = (fd_http_server_t){
    .params        = params,
    .callbacks     = callbacks,
    .callback_ctx  = callback_ctx,
    .stage_len     = 0UL,
    .stage_cap     = params.outgoing_buffer_sz,
    .listen_fd     = -1,
    .stage_err     = 0
  };
  return shmem;
}

fd_http_server_t *
fd_http_server_join( void * shhttp ) {
  return (fd_http_server_t *)shhttp;
}

void *
fd_http_server_leave( fd_http_server_t * http ) {
  return (void *)http;
}

void *
fd_http_server_delete( void * shhttp ) {
  return shhttp;
}

int
fd_http_server_fd( fd_http_server_t * http ) {
  return http ? http->listen_fd : -1;
}

fd_http_server_t *
fd_http_server_listen( fd_http_server_t * http,
                       uint               address,
                       ushort             port ) {
  (void)address; (void)port;
  if( FD_UNLIKELY( !http ) ) return NULL;
  errno = ENOTSUP;
  return NULL;
}

void
fd_http_server_close( fd_http_server_t * http,
                      ulong              conn_id,
                      int                reason ) {
  (void)http; (void)conn_id; (void)reason;
}

void
fd_http_server_ws_close( fd_http_server_t * http,
                         ulong              ws_conn_id,
                         int                reason ) {
  (void)http; (void)ws_conn_id; (void)reason;
}

void
fd_http_server_stage_trunc( fd_http_server_t * http,
                            ulong              len ) {
  if( FD_UNLIKELY( !http ) ) return;
  http->stage_len = len < http->stage_len ? len : http->stage_len;
}

ulong
fd_http_server_stage_len( fd_http_server_t * http ) {
  return http ? http->stage_len : 0UL;
}

void
fd_http_server_printf( fd_http_server_t * http,
                       char const *       fmt,
                       ... ) {
  (void)fmt;
  if( FD_UNLIKELY( !http ) ) return;
  http->stage_err = ENOTSUP;
  va_list ap;
  va_start( ap, fmt );
  va_end( ap );
}

void
fd_http_server_memcpy( fd_http_server_t * http,
                       uchar const *      data,
                       ulong              data_len ) {
  (void)data;
  if( FD_UNLIKELY( !http ) ) return;
  if( FD_UNLIKELY( data_len>http->stage_cap-http->stage_len ) ) {
    http->stage_err = ENOSPC;
    return;
  }
  if( data && data_len ) memcpy( ((uchar *)(http+1)) + http->stage_len, data, data_len );
  http->stage_len += data_len;
}

uchar *
fd_http_server_append_start( fd_http_server_t * http,
                             ulong              len ) {
  if( FD_UNLIKELY( !http ) ) return NULL;
  if( FD_UNLIKELY( len>http->stage_cap-http->stage_len ) ) {
    http->stage_err = ENOSPC;
    return NULL;
  }
  return ((uchar *)(http+1)) + http->stage_len;
}

void
fd_http_server_append_end( fd_http_server_t * http,
                           ulong              len ) {
  if( FD_UNLIKELY( !http ) ) return;
  if( FD_UNLIKELY( len>http->stage_cap-http->stage_len ) ) {
    http->stage_err = ENOSPC;
    return;
  }
  http->stage_len += len;
}

void
fd_http_server_unstage( fd_http_server_t * http ) {
  if( FD_UNLIKELY( !http ) ) return;
  http->stage_len = 0UL;
  http->stage_err = 0;
}

int
fd_http_server_stage_body( fd_http_server_t *          http,
                           fd_http_server_response_t * response ) {
  if( FD_UNLIKELY( !http || !response ) ) return -1;
  if( FD_UNLIKELY( http->stage_err ) ) {
    errno = http->stage_err;
    http->stage_err = 0;
    return -1;
  }
  response->_body_off = 0UL;
  response->_body_len = http->stage_len;
  return 0;
}

int
fd_http_server_ws_send( fd_http_server_t * http,
                        ulong              ws_conn_id ) {
  (void)http; (void)ws_conn_id;
  errno = ENOTSUP;
  return -1;
}

int
fd_http_server_ws_broadcast( fd_http_server_t * http ) {
  (void)http;
  errno = ENOTSUP;
  return -1;
}

int
fd_http_server_poll( fd_http_server_t * http,
                     int                poll_timeout ) {
  (void)http; (void)poll_timeout;
  return 0;
}

#endif /* FD_HAS_WINDOWS */
