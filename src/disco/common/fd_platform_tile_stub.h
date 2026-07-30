#ifndef HEADER_fd_src_disco_common_fd_platform_tile_stub_h
#define HEADER_fd_src_disco_common_fd_platform_tile_stub_h

FD_FN_CONST static inline ulong
fd_platform_tile_stub_scratch_align( void ) {
  return 1UL;
}

FD_FN_PURE static inline ulong
fd_platform_tile_stub_scratch_footprint( fd_topo_tile_t const * tile ) {
  (void)tile;
  return 0UL;
}

FD_FN_PURE static inline ulong
fd_platform_tile_stub_loose_footprint( fd_topo_tile_t const * tile ) {
  (void)tile;
  return 0UL;
}

static inline ulong
fd_platform_tile_stub_populate_allowed_seccomp( fd_topo_t const *      topo,
                                                fd_topo_tile_t const * tile,
                                                ulong                  out_cnt,
                                                struct sock_filter *   out ) {
  (void)topo; (void)tile; (void)out_cnt; (void)out;
  return 0UL;
}

static inline ulong
fd_platform_tile_stub_populate_allowed_fds_none( fd_topo_t const *      topo,
                                                 fd_topo_tile_t const * tile,
                                                 ulong                  out_fds_cnt,
                                                 int *                  out_fds ) {
  (void)topo; (void)tile; (void)out_fds_cnt; (void)out_fds;
  return 0UL;
}

static inline void
fd_platform_tile_stub_privileged_init( fd_topo_t const *      topo,
                                       fd_topo_tile_t const * tile ) {
  (void)topo; (void)tile;
}

static inline void
fd_platform_tile_stub_unprivileged_init( fd_topo_t const *      topo,
                                         fd_topo_tile_t const * tile ) {
  (void)topo; (void)tile;
}

#define FD_PLATFORM_TILE_STUB_NO_FDS   ((ulong (*)( fd_topo_t const *, fd_topo_tile_t const *, ulong, int * ))0)
#define FD_PLATFORM_TILE_STUB_NO_LOOSE ((ulong (*)( fd_topo_tile_t const * ))0)

#define FD_PLATFORM_TILE_STUB_DECLARE_RUN(fn_name,tile_display_name) \
static void \
fn_name( fd_topo_t *      topo, \
         fd_topo_tile_t * tile ) { \
  (void)topo; (void)tile; \
  FD_LOG_ERR(( tile_display_name " tile unsupported on Windows build lane" )); \
}

#define FD_PLATFORM_TILE_STUB_WITH_RUN(symbol,tile_display_name,run_fn,populate_allowed_fds_fn,loose_footprint_fn) \
fd_topo_run_tile_t symbol = { \
  .name                     = tile_display_name, \
  .populate_allowed_seccomp = fd_platform_tile_stub_populate_allowed_seccomp, \
  .populate_allowed_fds     = populate_allowed_fds_fn, \
  .scratch_align            = fd_platform_tile_stub_scratch_align, \
  .scratch_footprint        = fd_platform_tile_stub_scratch_footprint, \
  .loose_footprint          = loose_footprint_fn, \
  .privileged_init          = fd_platform_tile_stub_privileged_init, \
  .unprivileged_init        = fd_platform_tile_stub_unprivileged_init, \
  .run                      = run_fn, \
}

#define FD_PLATFORM_TILE_STUB(symbol,tile_display_name,populate_allowed_fds_fn,loose_footprint_fn) \
FD_PLATFORM_TILE_STUB_DECLARE_RUN( symbol##_run, tile_display_name ); \
FD_PLATFORM_TILE_STUB_WITH_RUN( symbol, tile_display_name, symbol##_run, populate_allowed_fds_fn, loose_footprint_fn )

#endif /* HEADER_fd_src_disco_common_fd_platform_tile_stub_h */
