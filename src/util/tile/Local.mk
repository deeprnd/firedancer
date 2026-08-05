$(call add-hdrs,fd_tile.h)
$(call add-objs,fd_tile,fd_util)
ifdef FD_HAS_THREADS
$(call make-unit-test,test_cpuset,test_cpuset,fd_util)
$(call run-unit-test,test_cpuset)
$(call add-objs,fd_tile_threads_platform_linux fd_tile_threads,fd_util)
ifdef FD_HAS_WINDOWS
$(call add-objs,fd_tile_threads_platform_windows,fd_util)
else
$(call add-objs,fd_tile_threads_platform_macos,fd_util)
endif
$(call add-objs,fd_tile_threads,fd_util)
else
$(call add-objs,fd_tile_nothreads,fd_util)
endif
$(call make-unit-test,test_tile,test_tile,fd_util)
$(call run-unit-test,test_tile)

