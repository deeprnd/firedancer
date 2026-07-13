#!/usr/bin/env bash
# Build Firedancer libs for Tickoni on Linux.
# Called by justfile's build-fd recipe via:
#   exec bash contrib/fd-build-linux.sh [compiler]
# Default compiler: gcc (system default, e.g. gcc-13 on ubuntu-24.04)
set -euo pipefail
cd "$(dirname "$0")/.."
CC="${1:-gcc}"
bash contrib/fd-build-lib.sh fd-tickoni-fd "$CC"
