$(call add-hdrs,fd_bundle_crank.h)
$(call add-objs,fd_bundle_crank,fd_disco,fd_flamenco)
$(call make-unit-test,test_bundle_crank,test_bundle_crank,fd_disco fd_flamenco fd_ballet fd_util)
$(call run-unit-test,test_bundle_crank)

$(call add-hdrs,fd_bundle_tile.h)
ifdef FD_HAS_HOSTED
ifdef FD_HAS_WINDOWS
$(call add-objs,fd_bundle_windows_stub,fd_disco)
else
$(call add-objs,fd_bundle_auth fd_bundle_client,fd_disco)
$(call make-unit-test,test_bundle_client,test_bundle_client,fd_disco fd_waltz fd_flamenco fd_tango fd_ballet fd_util,$(OPENSSL_LIBS))
$(call run-unit-test,test_bundle_client)
$(call make-unit-test,test_bundle_client_wraparound,test_bundle_client_wraparound,fd_disco fd_waltz fd_flamenco fd_tango fd_ballet fd_util,$(OPENSSL_LIBS))
$(call run-unit-test,test_bundle_client_wraparound)
$(call make-fuzz-test,fuzz_bundle_client,fuzz_bundle_client,fd_disco fd_waltz fd_flamenco fd_tango fd_ballet fd_util,$(OPENSSL_LIBS))
$(call make-fuzz-test,fuzz_bundle_auth_resp,fuzz_bundle_auth_resp,fd_disco fd_waltz fd_flamenco fd_tango fd_ballet fd_util,$(OPENSSL_LIBS))
ifdef FD_HAS_DOUBLE
$(call make-unit-test,test_bundle_tile,test_bundle_tile,fd_disco fd_waltz fd_flamenco fd_tango fd_ballet fd_util,$(OPENSSL_LIBS))
$(call run-unit-test,test_bundle_tile)
endif
endif
endif

ifdef FD_HAS_HOSTED
ifdef FD_HAS_WINDOWS
# fd_bundle_windows_stub already provides fd_tile_bundle for Windows build lanes.
else
ifdef FD_HAS_DOUBLE
$(call add-objs,fd_bundle_tile,fd_disco)
endif
endif
endif
