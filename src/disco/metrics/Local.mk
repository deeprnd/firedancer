ifdef FD_HAS_HOSTED
$(call add-hdrs,fd_prometheus.h fd_metrics.h)
$(call add-objs,fd_prometheus fd_metrics,fd_disco)
ifdef FD_HAS_WINDOWS
# Windows build lane uses stub; non-Windows keeps the real metric tile.
$(call add-objs,fd_metric_windows_stub,fd_disco)
else
$(call add-objs,fd_metric_tile,fd_disco)
endif
endif
