CPPFLAGS+=-fPIC
LDFLAGS_EXE+=-pie
LDFLAGS_SO+=-fPIC

CPPFLAGS+=-Wl,-z,relro,-z,now
LDFLAGS+=-Wl,-z,relro,-z,now

CPPFLAGS+=-fstack-protector-strong
LDFLAGS+=-fstack-protector-strong

ifdef FD_HAS_X86
ifdef FD_HAS_LINUX
# GCC 11 doesn't support -fcf-protection (added in GCC 12); gate behind version
# check so older CI runners (gcc-11.4) can still compile.
ifeq ($(shell test $(CC_MAJOR_VERSION) -ge 12 2>/dev/null && echo yes),yes)
CPPFLAGS+=-fcf-protection=return
LDFLAGS_EXE+=-Wl,-z,shstk
ifdef FD_CET
ifeq ($(FD_CET),1)
LDFLAGS_EXE+=-Wl,-z,cet-report=error
endif
endif
endif
endif
endif
endif

# _FORTIFY_SOURCE only works when optimization is enabled
ifeq ($(FD_DISABLE_OPTIMIZATION),)
CPPFLAGS+=-D_FORTIFY_SOURCE=$(FORTIFY_SOURCE)
endif
