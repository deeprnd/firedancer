# Tickoni aarch64 harness build extra.
#
# When the Firedancer C libs (fd_util, fd_ballet) are compiled by GCC on aarch64
# and then linked into the Zig harness, GCC's default "outline atomics" emit
# calls to libgcc helpers (__aarch64_cas*_sync, __aarch64_ldadd*_sync, ...).
# Zig links with its own compiler-rt, which does not provide the *_sync variants,
# so the link fails with undefined symbols. Forcing inline atomics avoids the
# libgcc dependency. This never applies on x86-64 (CI), and the flag is aarch64
# only, so guard it on the host architecture.
ifneq ($(filter aarch64 arm64,$(shell uname -m)),)
CFLAGS+=-mno-outline-atomics
endif
