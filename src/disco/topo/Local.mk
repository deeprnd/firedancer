ifdef FD_HAS_HOSTED
ifdef FD_HAS_THREADS
$(call add-hdrs,fd_topo.h fd_cpu_topo.h fd_topo_platform.h fd_cpu_topo_platform.h)
$(call add-objs,fd_topo fd_topob fd_cpu_topo fd_cpu_topo_platform_linux fd_cpu_topo_platform,fd_disco)
$(call make-unit-test,test_topob,test_topob,fd_disco fd_ballet fd_tango fd_waltz fd_util)
$(call run-unit-test,test_topob)
ifdef FD_HAS_WINDOWS
$(call add-objs,fd_cpu_topo_platform_windows,fd_disco)
else
$(call add-objs,fd_cpu_topo_platform_macos,fd_disco)
endif
ifdef FD_HAS_DOUBLE
$(call add-hdrs,fd_wksp_mon.h)
$(call add-objs,fd_wksp_mon,fd_disco)
endif
endif
endif
