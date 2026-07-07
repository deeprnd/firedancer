$(call make-lib,fd_disco)
$(call add-hdrs,fd_disco_base.h fd_disco.h shim/fd_disco_pubkey.h shim/fd_leaders_shim.h)
$(call add-objs,shim/fd_disco_pubkey shim/fd_leaders_shim,fd_disco)
$(call make-unit-test,test_disco_base,test_disco_base,fd_disco fd_tango fd_util)
$(call run-unit-test,test_disco_base)
ifdef FD_HAS_DOUBLE
$(call add-hdrs,fd_clock_tile.h)
endif
