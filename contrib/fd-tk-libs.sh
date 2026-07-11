#!/usr/bin/env bash
# Shared definitions for building Firedancer libs that Tickoni reuses.
# Source this file, then use FD_TK_LIBS_* variables and fd_build_fd().
#
# To add a new lib dependency: add its source dir to the appropriate
# FD_TK_LIB_*_SRCS array and its .a name to FD_TK_LIBS or FD_TK_LIBS_EXTRA.
# All justfile recipes, quality.sh, and security.sh pick up the change.

# ── Source dirs ────────────────────────────────────────────────────────────────
# The 5-tree core (tango, util, ballet, disco, waltz) + cjson + s2n-bignum.
FD_TK_LIB_SRCS=( src/tango src/util src/ballet src/disco src/waltz \
                 src/third_party/cjson src/third_party/s2n-bignum )

# For unit-test/coverage we also need these third-party dirs compiled.
FD_TK_LIB_TEST_SRCS=( "${FD_TK_LIB_SRCS[@]}" \
                      src/third_party/picohttpparser \
                      src/third_party/blst \
                      src/third_party/lz4 \
                      src/third_party/zstd \
                      src/third_party/nanopb )

# Coverage builds that exclude s2n-bignum (same dirs as FD_TK_LIB_SRCS minus it).
FD_TK_LIB_COV_SRCS=( src/tango src/util src/ballet src/disco src/waltz \
                     src/third_party/cjson )

# Directories compiled into FD but NOT linked into our Tickoni harness libs.
FD_TK_LIB_EXCLUDES='disco/quic/|disco/gui/|ballet/zksdk/|ballet/zstd/|waltz/quic/'

# Base lib list — always compiled into the harness.
FD_TK_LIBS=( libfd_tango.a libfd_util.a libfd_ballet.a libfd_disco.a libfd_waltz.a )

# Extra libs needed for unit-test / coverage builds.
FD_TK_LIBS_EXTRA=( libfd_blst.a libfd_zstd.a libfd_lz4.a )

# ── Helpers ────────────────────────────────────────────────────────────────────

# Compute the LOCAL_MKS string from a given source-dir list.
# Usage: local mks; mks=$(fd_compute_mks "${FD_TK_LIB_SRCS[@]}")
fd_compute_mks() {
  local src_dirs=("$@")
  find "${src_dirs[@]}" -name Local.mk \
    | grep -vE "${FD_TK_LIB_EXCLUDES}" \
    | tr '\n' ' '
}

# Build the 5 FD libs that Tickoni links.
# Optionally builds test binaries or other make targets alongside.
# Usage: fd_build_fd BUILDDIR=<dir> [CC=gcc|clang|...] [EXTRAS=...] \
#        [TARGETS=...] [SRCS=...] [BUILD_TARGET=unit-test|...]
#   BUILDDIR: Firedancer BUILDDIR name (no build/ prefix)
#   CC: compiler binary (default: gcc-12)
#   EXTRAS: extra make vars (default: empty)
#   TARGETS: space-separated .a filenames — defaults to FD_TK_LIBS + FD_TK_LIBS_EXTRA
#   SRCS: space-separated source dirs (justfile expands arrays to one quoted string)
#   BUILD_TARGET: extra make target(s) to build alongside libs
#                 (e.g. unit-test, coverage, etc.)
# On failure, calls exit 1.
fd_build_fd() {
  local BUILDDIR="" CC="gcc-12" EXTRAS="" TARGETS="" SRCS="" BUILD_TARGET=""
  while [ $# -gt 0 ]; do
    case "$1" in
      BUILDDIR=*) BUILDDIR="${1#BUILDDIR=}"; shift ;;
      CC=*) CC="${1#CC=}"; shift ;;
      EXTRAS=*) EXTRAS="${1#EXTRAS=}"; shift ;;
      TARGETS=*) TARGETS="${1#TARGETS=}"; shift ;;
      SRCS=*) SRCS="${1#SRCS=}"; shift ;;
      BUILD_TARGET=*) BUILD_TARGET="${1#BUILD_TARGET=}"; shift ;;
      *) shift ;; # skip unrecognized args
    esac
  done

  : "${BUILDDIR:=fd-tickoni-fd}"

  # If SRCS was not explicitly set, use defaults.
  if [ -z "${SRCS}" ]; then
    SRCS="${FD_TK_LIB_SRCS[*]}"
  fi

  [ -z "${TARGETS}" ] && TARGETS=$(printf '%s\n' "${FD_TK_LIBS[@]}" "${FD_TK_LIBS_EXTRA[@]}" | tr '\n' ' ')

  local mks
  mks=$(fd_compute_mks ${SRCS})

  local -a cmd=( make -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR="${BUILDDIR}" )
  [ -n "${EXTRAS}" ] && cmd+=( "EXTRAS=${EXTRAS}" )
  cmd+=( "CC=${CC}" )
  cmd+=( "LOCAL_MKS=${mks}" )
  cmd+=(${TARGETS})
  [ -n "${BUILD_TARGET}" ] && cmd+=("${BUILD_TARGET}")

  "${cmd[@]}"
}

# Prepend a prefix path to every lib name.
# Usage: local libs; libs=$(fd_lib_prefix "build/fd-gcc/lib" "${FD_TK_LIBS[@]}")
fd_lib_prefix() {
  local prefix="$1"; shift
  local result=()
  for lib in "$@"; do
    result+=("${prefix}/${lib}")
  done
  printf '%s\n' "${result[@]}"
}
