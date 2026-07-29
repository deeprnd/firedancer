#include "fd_netdb.h"

#if FD_HAS_WINDOWS

fd_netdb_fds_t *
fd_netdb_open_fds( fd_netdb_fds_t * fds ) {
  if( fds ) {
    fds->etc_hosts       = -1;
    fds->etc_resolv_conf = -1;
    return fds;
  }

  static FD_TL fd_netdb_fds_t fallback_fds = { .etc_hosts = -1, .etc_resolv_conf = -1 };
  return &fallback_fds;
}

int
fd_getaddrinfo( char const * restrict          node,
                fd_addrinfo_t const * restrict hints,
                fd_addrinfo_t **  restrict     res,
                void **                        out_mem,
                ulong                          out_max ) {
  (void)node;
  (void)hints;
  (void)res;
  (void)out_mem;
  (void)out_max;
  return FD_EAI_NONAME;
}

char const *
fd_gai_strerror( int gai ) {
  switch( gai ) {
  case FD_EAI_BADFLAGS: return "bad flags";
  case FD_EAI_NONAME:   return "resolver unsupported on Windows build lane";
  case FD_EAI_AGAIN:    return "temporary failure";
  case FD_EAI_FAIL:     return "permanent failure";
  case FD_EAI_NODATA:   return "no data";
  case FD_EAI_FAMILY:   return "unsupported address family";
  case FD_EAI_MEMORY:   return "out of memory";
  default:              return "resolver unsupported on Windows build lane";
  }
}

#endif
