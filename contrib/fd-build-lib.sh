#!/usr/bin/env bash
# Thin wrapper around fd_build_fd() from contrib/fd-tk-libs.sh.
# Usage: contrib/fd-build-lib.sh <BUILDDIR> [CC] [MODE]
#   BUILDDIR: Firedancer BUILDDIR name (no build/ prefix)
#   CC:       compiler binary (default: gcc-12)
#   MODE:     "libs" (default), "test", or "cov"
#              libs = basic 5 libs, basic SRCS (tango util ballet disco waltz + cjson + s2n-bignum)
#              test = 5 libs + extras (blst/zstd/lz4/nanopb), build unit-test target
#              cov  = coverage build (clang-18, llvm-cov, basic SRCS + cjson)
set -euo pipefail
cd "$(dirname "$0")/.."
source contrib/fd-tk-libs.sh

BUILDDIR="${1:?usage: fd-build-lib.sh <BUILDDIR> [CC] [MODE]}"
CC="${2:-gcc-12}"
MODE="${3:-libs}"

LIBDIR="build/${BUILDDIR}/lib"
OBJDIR="build/${BUILDDIR}/obj"
mkdir -p "$OBJDIR" "$LIBDIR"

# Select source dirs based on mode
case "$MODE" in
  libs)  SRCS=( "${FD_TK_LIB_SRCS[@]}" ) ;;
  test)  SRCS=( "${FD_TK_LIB_TEST_SRCS[@]}" ) ;;
  cov)   SRCS=( "${FD_TK_LIB_COV_SRCS[@]}" ) ;;
  *)     echo "Unknown mode: $MODE" >&2; exit 1 ;;
esac

# Build full target paths (lib names -> full paths)
TARGETS=()
for lib in "${FD_TK_LIBS[@]}"; do
  TARGETS+=( "${LIBDIR}/${lib}" )
done
for lib in "${FD_TK_LIBS_EXTRA[@]}"; do
  TARGETS+=( "${LIBDIR}/${lib}" )
done

# Compute LOCAL_MKS and run fd_build_fd
# For test mode, pass EXTRAS so tickoni_fd.mk gets FD_HAS_LZ4/BLST/ZSTD
# and the libs are compiled with the right flags from the start.
# tickoni_fd.mk doesn't include with-lz4/with-blst/with-zstd by default,
# so without this, libfd_util.a has zero LZ4 symbols (fd_checkpt.c
# #if FD_HAS_LZ4 blocks are skipped), and unit-test link fails.
# Use BUILD_TARGET=unit-test so unit-test binaries are linked in the same
# make invocation — if we split into two make calls, libs are "up to date"
# in the second call and won't be recompiled with the new flags.
#
# Also delete stale extra libs (libfd_lz4.a, libfd_blst.a, libfd_zstd.a)
# from a prior MODE=libs build. Those are empty archives (no EXTRAS) and
# make considers them up-to-date, preventing recompilation with the correct
# FD_HAS_* flags in the second invocation.
if [ "$MODE" = "test" ]; then
  # Remove stale objects from any prior build without EXTRAS.
  # Without this, make sees .o files newer than .c files and skips
  # recompilation, so FD_HAS_LZ4/BLST/ZSTD flags never take effect.
  rm -rf "${OBJDIR:?}/"*
  # Also delete empty extra-libs from a prior MODE=libs build — make
  # would consider them up-to-date and skip recompilation with EXTRAS.
  rm -f "${LIBDIR:?}/libfd_lz4.a" "${LIBDIR}/libfd_blst.a" "${LIBDIR}/libfd_zstd.a"
  fd_build_fd BUILDDIR="${BUILDDIR}" CC="${CC}" "TARGETS=${TARGETS[*]}" "SRCS=${SRCS[*]}" EXTRAS="lz4 blst zstd" BUILD_TARGET="unit-test"
else
  fd_build_fd BUILDDIR="${BUILDDIR}" CC="${CC}" "TARGETS=${TARGETS[*]}" "SRCS=${SRCS[*]}"
fi

# Post-build: cov mode runs unit-test with coverage after libs.
# Only needs llvm-cov (lz4 not required for coverage build).
if [ "$MODE" = "cov" ]; then
  make -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR="${BUILDDIR}" CC="${CC}" \
    EXTRAS="llvm-cov" LOCAL_MKS="$(fd_compute_mks "${SRCS[@]}")" \
    unit-test
fi
