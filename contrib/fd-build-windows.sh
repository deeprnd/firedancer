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
