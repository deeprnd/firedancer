#include "fd_metrics.h"
#include "../topo/fd_topo.h"
#include "../common/fd_platform_tile_stub.h"

#if FD_HAS_WINDOWS

FD_PLATFORM_TILE_STUB( fd_tile_metric,
                       "metric",
                       FD_PLATFORM_TILE_STUB_NO_FDS,
                       FD_PLATFORM_TILE_STUB_NO_LOOSE );

#endif
