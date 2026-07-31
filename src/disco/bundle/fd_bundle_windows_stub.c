#include "fd_bundle_tile.h"
#include "../common/fd_platform_tile_stub.h"

#if FD_HAS_WINDOWS

FD_PLATFORM_TILE_STUB( fd_tile_bundle,
                       "bundle",
                       fd_platform_tile_stub_populate_allowed_fds_none,
                       fd_platform_tile_stub_loose_footprint );

#endif
