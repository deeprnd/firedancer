#include "fd_event_client.h"
#include "../common/fd_platform_tile_stub.h"

#if FD_HAS_WINDOWS

FD_PLATFORM_TILE_STUB( fd_tile_event,
                       "event",
                       fd_platform_tile_stub_populate_allowed_fds_none,
                       fd_platform_tile_stub_loose_footprint );

#endif
