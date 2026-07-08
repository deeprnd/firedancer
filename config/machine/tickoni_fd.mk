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
# overrides LOCAL_MKS so everything.mk's ?= assignment is skipped.
# Note: FIND is defined here because base.mk (which normally sets FIND)
# is not yet loaded — native.mk includes base.mk inside a conditional block.
# The shell command uses $(FIND) so if Make's shell is POSIX, it will use
# the PATH-resolved 'find'. If the shell is dash/bash, it will find 'find'
# on the standard PATH.
FIND := find
LOCAL_MKS := $(shell $(FIND) -L src -type f -name Local.mk)
# Select 5 core dirs. Note: Make's % wildcard matches / too, so src/disco/%
# also matches src/disco/tickoni/% — filter-out removes that subdirectory.
LOCAL_MKS := $(filter src/tango/% src/util/% src/ballet/% src/disco/% src/waltz/%,$(LOCAL_MKS))
LOCAL_MKS := $(filter-out src/discof/% src/disco/tickoni/% src/flamenco/% src/choreo/% src/app/platform/%,$(LOCAL_MKS))

# Use native detection for compiler feature flags.
include config/machine/native.mk
include config/extra/with-hosted.mk
