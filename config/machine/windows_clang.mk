# Clang on Windows (x86_64 or ARM64 under Git Bash/MSYS environments).
# Auto-detects the target arch at build time, with FD_WINDOWS_ARCH override for CI.

BUILDDIR?=windows/clang

include config/extra/with-clang-pre.mk
include config/base.mk
include config/extra/with-clang.mk
include config/extra/with-debug.mk
include config/extra/with-optimization.mk
include config/extra/with-threads.mk

UNAME?=$(shell uname)
FD_WINDOWS_ARCH?=$(shell uname -m)

FD_HAS_WINDOWS:=1
CPPFLAGS+=-DFD_HAS_WINDOWS=1 -D_CRT_SECURE_NO_WARNINGS

# Firedancer assumes LP64-style ulong-heavy formatting and bit helpers.
# On Windows/LLP64 we carry a Windows-specific 64-bit ulong typedef in
# fd_util_base.h for build compatibility, so suppress the resulting %lu/
# %lx family mismatches in this first-pass build-only lane.
CPPFLAGS+=-Wno-format -Wno-format-extra-args
AR:=llvm-ar
RANLIB:=llvm-ranlib
LD?=$(CC)

ifeq ($(filter arm64 aarch64,$(FD_WINDOWS_ARCH)),)
# Windows x86_64
FD_HAS_INT128:=1
FD_HAS_DOUBLE:=1
FD_HAS_ALLOCA:=1
FD_HAS_THREADS:=1
FD_HAS_X86:=1
FD_HAS_SSE:=1
FD_HAS_AVX:=1
FD_HAS_AVX2:=1
FD_HAS_AESNI:=1
FD_IS_X86_64:=1
CPPFLAGS+=-march=skylake
CPPFLAGS+=-DFD_HAS_X86=1 -DFD_HAS_SSE=1 -DFD_HAS_AVX=1 -DFD_HAS_AVX2=1 -DFD_HAS_AESNI=1 -DFD_IS_X86_64=1 -DFD_HAS_INT128=1 -DFD_HAS_DOUBLE=1 -DFD_HAS_ALLOCA=1 -DFD_HAS_THREADS=1
else
# Windows ARM64
FD_HAS_ARM64:=1
FD_HAS_INT128:=1
FD_HAS_DOUBLE:=1
FD_HAS_ALLOCA:=1
FD_HAS_THREADS:=1
CPPFLAGS+=-DFD_HAS_ARM64=1 -DFD_HAS_INT128=1 -DFD_HAS_DOUBLE=1 -DFD_HAS_ALLOCA=1 -DFD_HAS_THREADS=1
endif
