# Clang on macOS (Apple Silicon ARM64 or Intel x86_64).
# Auto-detects the target arch at build time.
#
# Usage: MACHINE=macos_clang make ...
#
# On ARM (Apple Silicon): -mcpu=apple-m1 (or newer) with NEON/CRYPTO.
# On Intel: -march=skylake with SSE4.2/AVX2.

BUILDDIR?=macos/clang

include config/extra/with-clang-pre.mk
include config/base.mk
include config/extra/with-clang.mk
include config/extra/with-debug.mk
include config/extra/with-optimization.mk

# Platform detection
UNAME?=$(shell uname)
ifeq ($(UNAME), Darwin)
  FD_HAS_MACOS:=1
  CPPFLAGS+=-DFD_HAS_MACOS=1
else
  # Not macOS — skip
  BUILDDIR?=native/$(notdir $(CC))
  include config/machine/native.mk
  $(eval $(filter-out %,$(BUILDDIR)))
endif

# ARM vs Intel detection
ifeq ($(UNAME), Darwin)
  # Check architecture at build time
  IS_ARM?=$(shell uname -m | grep -qE 'aarch64|arm64' && echo 1 || echo 0)
  
  ifeq ($(IS_ARM),1)
    # Apple Silicon (ARM64)
    FD_HAS_ARM64:=1
    FD_HAS_INT128:=1
    FD_HAS_DOUBLE:=1
    FD_HAS_ALLOCA:=1
    FD_HAS_THREADS:=1
    CPPFLAGS+=-mcpu=apple-m1
    CPPFLAGS+=-DFD_HAS_ARM64=1
  else
    # Intel x86_64
    FD_HAS_INT128:=1
    FD_HAS_DOUBLE:=1
    FD_HAS_ALLOCA:=1
    FD_HAS_THREADS:=1
    FD_HAS_X86:=1
    FD_HAS_SSE:=1
    FD_HAS_AVX:=1
    FD_HAS_AVX2:=1
    FD_HAS_AVX512:=1
    FD_IS_X86_64:=1
    CPPFLAGS+=-march=skylake
    CPPFLAGS+=-DFD_HAS_X86=1 -DFD_HAS_SSE=1 -DFD_HAS_AVX=1 -DFD_HAS_AVX2=1 -DFD_HAS_AVX512=1 -DFD_IS_X86_64=1
  endif
endif
