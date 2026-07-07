# Tickoni retail build machine profile.
#
# Scopes the Firedancer build to the libraries Tickoni actually reuses:
#   libfd_tango.a   - queues / workspaces / topology primitives
#   libfd_util.a    - shared-memory, logging, hash, topology, sandbox
#   libfd_ballet.a  - crypto / hashing / encoding primitives
#   libfd_disco.a   - metrics, diagnostics, verification, event handling
#   libfd_discof.a  - validator infrastructure (reasm, sched, replay, etc.)
#   libfd_waltz.a   - HTTP/sockets / networking primitives
#   libfd_flamenco.a - Solana runtime primitives (pubkey, txn parsing, system IDs)
#   libfd_choreo.a   - consensus choreography (ghost, hfork, eqvoc, votes, tower)
#   libfdctl_platform.a - app platform utilities (file sys net utils)
#
# This excludes Solana validator tiles, RPC schemas, and unrelated Firedancer
# source that retail targets don't need.
#
# overrides LOCAL_MKS so everything.mk's ?= assignment is skipped.
# Note: FIND is defined here because base.mk (which normally sets FIND)
# is not yet loaded — native.mk includes base.mk inside a conditional block.
# The shell command uses $(FIND) so if Make's shell is POSIX, it will use
# the PATH-resolved 'find'. If the shell is dash/bash, it will find 'find'
# on the standard PATH.
FIND := find
LOCAL_MKS := $(shell $(FIND) -L src -type f -name Local.mk)
LOCAL_MKS := $(filter src/tango/% src/util/% src/ballet/% src/disco/% src/discof/% src/disco/tickoni/% src/waltz/% src/flamenco/% src/choreo/% src/app/platform/%,$(LOCAL_MKS))

# Use native detection for compiler feature flags.
include config/machine/native.mk
include config/extra/with-hosted.mk
