#include "fd_wksp_private.h"
#include <errno.h>
#include <string.h>

#if FD_HAS_WINDOWS

int
fd_wksp_private_checkpt_v1( fd_tpool_t * tpool,
                            ulong        t0,
                            ulong        t1,
                            fd_wksp_t *  wksp,
                            char const * path,
                            ulong        mode,
                            char const * uinfo ) {
  (void)tpool; (void)t0; (void)t1; (void)wksp; (void)path; (void)mode; (void)uinfo;
  FD_LOG_WARNING(( "fd_wksp_private_checkpt_v1 unsupported on Windows build lane" ));
  return FD_WKSP_ERR_FAIL;
}

int
fd_wksp_private_restore_v1( fd_tpool_t * tpool,
                            ulong        t0,
                            ulong        t1,
                            fd_wksp_t *  wksp,
                            char const * path,
                            uint         new_seed ) {
  (void)tpool; (void)t0; (void)t1; (void)wksp; (void)path; (void)new_seed;
  FD_LOG_WARNING(( "fd_wksp_private_restore_v1 unsupported on Windows build lane" ));
  return FD_WKSP_ERR_FAIL;
}

int
fd_wksp_private_checkpt_v2( fd_tpool_t * tpool,
                            ulong        t0,
                            ulong        t1,
                            fd_wksp_t *  wksp,
                            char const * path,
                            ulong        mode,
                            char const * uinfo,
                            int          frame_style_compressed ) {
  (void)tpool; (void)t0; (void)t1; (void)wksp; (void)path; (void)mode; (void)uinfo; (void)frame_style_compressed;
  FD_LOG_WARNING(( "fd_wksp_private_checkpt_v2 unsupported on Windows build lane" ));
  return FD_WKSP_ERR_FAIL;
}

int
fd_wksp_private_restore_v2( fd_tpool_t * tpool,
                            ulong        t0,
                            ulong        t1,
                            fd_wksp_t *  wksp,
                            char const * path,
                            uint         new_seed ) {
  (void)tpool; (void)t0; (void)t1; (void)wksp; (void)path; (void)new_seed;
  FD_LOG_WARNING(( "fd_wksp_private_restore_v2 unsupported on Windows build lane" ));
  return FD_WKSP_ERR_FAIL;
}

int
fd_wksp_preview( char const *        path,
                 fd_wksp_preview_t * opt_preview ) {
  (void)opt_preview;
  if( FD_UNLIKELY( !path ) ) return FD_WKSP_ERR_INVAL;
  return FD_WKSP_ERR_FAIL;
}

int
fd_wksp_checkpt_tpool( fd_tpool_t * tpool,
                       ulong        t0,
                       ulong        t1,
                       fd_wksp_t *  wksp,
                       char const * path,
                       ulong        mode,
                       int          style,
                       char const * uinfo ) {
  (void)tpool; (void)t0; (void)t1; (void)wksp; (void)path; (void)mode; (void)style; (void)uinfo;
  FD_LOG_WARNING(( "fd_wksp_checkpt_tpool unsupported on Windows build lane" ));
  return FD_WKSP_ERR_FAIL;
}

int
fd_wksp_restore_tpool( fd_tpool_t * tpool,
                       ulong        t0,
                       ulong        t1,
                       fd_wksp_t *  wksp,
                       char const * path,
                       uint         new_seed ) {
  (void)tpool; (void)t0; (void)t1; (void)wksp; (void)path; (void)new_seed;
  FD_LOG_WARNING(( "fd_wksp_restore_tpool unsupported on Windows build lane" ));
  return FD_WKSP_ERR_FAIL;
}

int
fd_wksp_printf( int          fd,
                char const * path,
                int          verbose ) {
  (void)verbose;
  if( FD_UNLIKELY( !path ) ) return -1;
  errno = ENOTSUP;
  if( fd>=0 ) {
    char const * msg = "fd_wksp_printf unsupported on Windows build lane\n";
    ulong out_sz = 0UL;
    (void)fd_io_write( fd, msg, 0UL, strlen( msg ), &out_sz );
  }
  return -1;
}

#endif
