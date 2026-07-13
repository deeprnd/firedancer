# Tickoni retail build machine profile.
#
# Scopes the Firedancer build to the 5 core libraries Tickoni actually reuses:
#   libfd_tango.a  - queues / workspaces / topology primitives
#   libfd_util.a   - shared-memory, logging, hash, topology, sandbox
#   libfd_ballet.a - crypto / hashing / encoding primitives
#   libfd_disco.a  - metrics, diagnostics, verification, event handling
#   libfd_waltz.a  - HTTP/sockets / networking primitives
#
# This excludes:
#   src/discof/%       - validator infrastructure (reasm, sched, replay)
#   src/disco/tickoni/% - Tickoni disco tiles (not yet needed for build)
#   src/flamenco/%     - Solana runtime primitives
#   src/choreo/%       - consensus choreography
#   src/app/platform/% - fdctl platform utilities
#
# Overrides LOCAL_MKS so everything.mk's ?= assignment is skipped.
# Note: FIND is defined here because base.mk (which normally sets FIND)
# is not yet loaded — native.mk includes base.mk inside a conditional block.
# The shell command uses $(FIND) so if Make's shell is POSIX, it will use
# the PATH-resolved 'find'. If the shell is dash/bash, it will find 'find'
# on the standard PATH.
# If LOCAL_MKS is set via command line (e.g. from fd-build-lib.sh), use it as-is.
# Otherwise apply the default filter for the 5 core dirs only.
ifeq ($(origin LOCAL_MKS),undefined)
FIND := find
LOCAL_MKS := $(shell $(FIND) -L src -type f -name Local.mk)
# Note: Make's % wildcard matches / too, so src/disco/%
# also matches src/disco/tickoni/% — filter-out removes that subdirectory.
LOCAL_MKS := $(filter src/tango/% src/util/% src/ballet/% src/disco/% src/waltz/% src/third_party/%,$(LOCAL_MKS))
LOCAL_MKS := $(filter-out src/discof/% src/disco/tickoni/% src/flamenco/% src/choreo/% src/app/platform/%,$(LOCAL_MKS))
endif

# Use native detection for compiler feature flags.
include config/machine/native.mk
include config/extra/with-hosted.mk

# Platform detection — define FD_HAS_LINUX/FD_HAS_MACOS/FD_HAS_WINDOWS
# so source code can gate platform-specific implementations.
# MUST come after native.mk (which includes base.mk that does
# CPPFLAGS:=...) because base.mk resets CPPFLAGS with :=, wiping
# out any += we do before it.  Use ?= so command-line -D can still
# override.
UNAME?=$(shell uname)
ifeq ($(UNAME), Linux)
  CPPFLAGS+=-DFD_HAS_LINUX=1
  FD_HAS_LINUX:=1
else ifeq ($(UNAME), Darwin)
  CPPFLAGS+=-DFD_HAS_MACOS=1
  FD_HAS_MACOS:=1
endif

# Parse EXTRAS from the command line to include corresponding with-*.mk files.
# This is necessary because tickoni_fd.mk overrides LOCAL_MKS and doesn't
# include the extras infrastructure like the default machine profiles do.
ifneq ($(EXTRAS),)
$(foreach extra,$(EXTRAS),\
  $(eval include config/extra/with-$(extra).mk))
endif
