#include "fd_metrics.h"
#include "../topo/fd_topo.h"

#if FD_HAS_WINDOWS

FD_FN_CONST static inline ulong
scratch_align( void ) {
  return 1UL;
}

FD_FN_PURE static inline ulong
scratch_footprint( fd_topo_tile_t const * tile ) {
  (void)tile;
  return 0UL;
}

static void
privileged_init( fd_topo_t const *      topo,
                 fd_topo_tile_t const * tile ) {
  (void)topo; (void)tile;
}

static void
unprivileged_init( fd_topo_t const *      topo,
                   fd_topo_tile_t const * tile ) {
  (void)topo; (void)tile;
}

static ulong
populate_allowed_seccomp( fd_topo_t const *      topo,
                          fd_topo_tile_t const * tile,
                          ulong                  out_cnt,
                          struct sock_filter *   out ) {
  (void)topo; (void)tile; (void)out_cnt; (void)out;
  return 0UL;
}

static void
run( fd_topo_t *      topo,
     fd_topo_tile_t * tile ) {
  (void)topo; (void)tile;
  FD_LOG_ERR(( "metric tile unsupported on Windows build lane" ));
}

fd_topo_run_tile_t fd_tile_metric = {
  .name                     = "metric",
  .populate_allowed_seccomp = populate_allowed_seccomp,
  .scratch_align            = scratch_align,
  .scratch_footprint        = scratch_footprint,
  .privileged_init          = privileged_init,
  .unprivileged_init        = unprivileged_init,
  .run                      = run,
};

#endif
