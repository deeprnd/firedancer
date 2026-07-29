$(call add-hdrs,fd_log.h)
$(call add-objs,fd_log,fd_util)
ifdef FD_HAS_HOSTED
ifndef FD_HAS_WINDOWS
$(call add-objs,fd_backtrace,fd_util)
endif
endif
$(call make-unit-test,test_log,test_log,fd_util)
$(call run-unit-test,test_log)
