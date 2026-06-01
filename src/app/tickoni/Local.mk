include src/app/tickoni/version.mk
$(info Using FIREDANCER_VERSION=$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH) ($(FIREDANCER_CI_COMMIT)))
$(shell echo "#define FIREDANCER_MAJOR_VERSION $(VERSION_MAJOR)"                          >  src/app/tickoni/version2.h)
$(shell echo "#define FIREDANCER_MINOR_VERSION $(VERSION_MINOR)"                          >> src/app/tickoni/version2.h)
$(shell echo "#define FIREDANCER_PATCH_VERSION $(VERSION_PATCH)"                          >> src/app/tickoni/version2.h)
$(shell echo "#define FIREDANCER_VERSION \"$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)\"" >> src/app/tickoni/version2.h)
$(shell echo '#define FIREDANCER_COMMIT_REF_CSTR "$(FIREDANCER_CI_COMMIT)"'                          >> src/app/tickoni/version2.h)
$(shell echo "#define FIREDANCER_COMMIT_REF_U32 0x$(shell echo $(FIREDANCER_CI_COMMIT) | cut -c -8)" >> src/app/tickoni/version2.h)

# Update version.h only if version changed or doesn't exist
ifneq ($(shell cmp -s src/app/tickoni/version.h src/app/tickoni/version2.h && echo "same"),same)
src/app/tickoni/version.h: src/app/tickoni/version2.h
	cp -f src/app/tickoni/version2.h $@
endif

# Always generate a version file
include src/app/tickoni/version.h

ifdef FD_HAS_HOSTED
ifdef FD_HAS_THREADS
ifdef FD_HAS_ALLOCA
ifdef FD_HAS_DOUBLE
ifdef FD_HAS_INT128
ifdef FD_HAS_ZSTD

$(OBJDIR)/obj/app/tickoni/config.o: src/app/tickoni/config/default.toml
$(OBJDIR)/obj/app/tickoni/config.o: src/app/tickoni/config/testnet.toml
$(OBJDIR)/obj/app/tickoni/config.o: src/app/tickoni/config/devnet.toml
$(OBJDIR)/obj/app/tickoni/config.o: src/app/tickoni/config/mainnet.toml
$(OBJDIR)/obj/app/tickoni/config.o: src/app/tickoni/config/testnet-jito.toml
$(OBJDIR)/obj/app/tickoni/config.o: src/app/tickoni/config/mainnet-jito.toml
$(OBJDIR)/obj/app/tickoni/version.d: src/app/tickoni/version.h

.PHONY: tickoni firedancer

# firedancer core
$(call add-objs,topology,fd_firedancer)
$(call add-objs,config,fd_firedancer)
$(call add-objs,callbacks,fd_firedancer)

# commands
$(call add-objs,commands/add_authorized_voter,fd_firedancer)
$(call add-objs,commands/shred_version,fd_firedancer)
$(call add-objs,commands/set_identity,fd_firedancer)
$(call add-objs,commands/monitor_gossip/monitor_gossip commands/monitor_gossip/gossip_diag,fd_firedancer)

# version
$(call make-lib,firedancer_version)
$(call add-objs,version,firedancer_version)

ifdef FD_HAS_SSE
# ifdef FD_HAS_BLST -- will be a required dependency soon
ifdef FD_HAS_S2NBIGNUM
$(call make-bin,tickoni,main,fd_firedancer fdctl_shared fdctl_platform fd_discof fd_disco fd_choreo fd_flamenco fd_funk fd_quic fd_tls fd_reedsol fd_waltz fd_tango fd_ballet fd_util firedancer_version,$(OPENSSL_LIBS))

# Compatibility alias during rename transition.
firedancer: $(OBJDIR)/bin/firedancer
$(OBJDIR)/bin/firedancer: $(OBJDIR)/bin/tickoni
	$(MKDIR) $(dir $@) && \
ln -sf tickoni $@
endif
# endif
endif

else
$(warning firedancer build disabled due to lack of zstd)
endif
endif
endif
endif
endif
endif
