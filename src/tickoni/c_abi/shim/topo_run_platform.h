#ifndef HEADER_tickoni_c_abi_shim_topo_run_platform_h
#define HEADER_tickoni_c_abi_shim_topo_run_platform_h

#include "../../../disco/topo/fd_topo.h"

void
tk_topo_platform_pre_boot( fd_topo_tile_t const * tile,
                           ulong *                pid,
                           ulong *                tid );

void
tk_topo_platform_join_tile_workspaces( fd_topo_t *      topo,
                                       fd_topo_tile_t * tile,
                                       int              core_dump_level );

#endif /* HEADER_tickoni_c_abi_shim_topo_run_platform_h */
