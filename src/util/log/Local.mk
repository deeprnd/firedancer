$(call add-hdrs,fd_log.h)
ifdef FD_HAS_WINDOWS
$(call add-objs,fd_log_windows,fd_util)
else
$(call add-objs,fd_log,fd_util)
endif
ifdef FD_HAS_HOSTED
ifndef FD_HAS_WINDOWS
$(call add-objs,fd_backtrace,fd_util)
endif
endif
$(call make-unit-test,test_log,test_log,fd_util)
$(call run-unit-test,test_log)
