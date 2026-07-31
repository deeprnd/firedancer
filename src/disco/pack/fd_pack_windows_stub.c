#include "../tiles.h"
#include "../common/fd_platform_tile_stub.h"

#if FD_HAS_WINDOWS

static ulong
fd_pack_tile_stub_populate_allowed_fds( fd_topo_t const *      topo,
                                        fd_topo_tile_t const * tile,
                                        ulong                  out_fds_cnt,
                                        int *                  out_fds ) {
  (void)topo; (void)tile; (void)out_fds_cnt;
  out_fds[0] = 2;
  if( -1!=fd_log_private_logfile_fd() ) out_fds[1] = fd_log_private_logfile_fd();
  return 2UL;
}

FD_PLATFORM_TILE_STUB( fd_tile_pack,
                       "pack",
                       fd_pack_tile_stub_populate_allowed_fds,
                       FD_PLATFORM_TILE_STUB_NO_LOOSE );

#endif
