#!/usr/bin/env bash
# Build Firedancer libs for Tickoni on native Windows runners.
# Usage:
#   bash contrib/fd-build-windows.sh [arch] [compiler]
#   arch: x86_64|arm64 (default: host arch)
#   compiler: clang by default
set -euo pipefail
cd "$(dirname "$0")/.."

raw_arch="${1:-$(uname -m)}"
cc="${2:-${TK_WINDOWS_CC:-clang}}"

case "$raw_arch" in
  x86_64|amd64)
    fd_windows_arch="x86_64"
    ;;
  aarch64|arm64)
    fd_windows_arch="arm64"
    ;;
  *)
    echo "unsupported Windows arch for fd build: $raw_arch" >&2
    exit 1
    ;;
esac

echo "[+] Windows FD build arch=${fd_windows_arch} cc=${cc}"
env FD_WINDOWS_ARCH="$fd_windows_arch" bash contrib/fd-build-lib.sh fd-tickoni-fd "$cc"

# Post-build: compile libuuid_stub.c into a proper libuuid.a archive.
# The prebuilt Windows FD libs reference libuuid.a as a library
# dependency. Zig's C source-file inclusion (addCSourceFiles) only
# adds the .obj to the link — it does NOT satisfy the linker's
# library lookup for libuuid.a. We need an actual static archive.
libdir="build/fd-tickoni-fd/lib"
libdir_native="build/native/gcc/lib"
archive_tool="${AR:-llvm-ar}"
for dir in "$libdir" "$libdir_native"; do
  if [ -d "$dir" ]; then
    echo "[+] Building libuuid.a from stub in ${dir}"
    ${cc:-clang} -c -o "${dir}/libuuid_stub.obj" \
      --target=${fd_windows_arch}-windows-msvc \
      -I src \
      -DFD_HAS_HOSTED=1 \
      -DFD_USING_MSVC=1 \
      src/tickoni/c_abi/shim/libuuid_stub.c
    "${archive_tool}" rcs "${dir}/libuuid.a" "${dir}/libuuid_stub.obj"
    rm -f "${dir}/libuuid_stub.obj"
  fi
done
