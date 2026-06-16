#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: contrib/test/ensure_llama_cpp.sh [--check-only]

Ensures llama.cpp is cloned and built locally. If the directory is missing,
clones from https://github.com/ggml-org/llama.cpp and builds for CPU with
OpenBLAS.

Environment overrides:
  TK_LLAMA_CPP_DIR    local directory for the llama.cpp checkout

Defaults:
  TK_LLAMA_CPP_DIR=$HOME/work/git/llama.cpp
USAGE
}

check_only=0
if [[ "${1:-}" == "--check-only" ]]; then
  check_only=1
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
elif [[ $# -gt 0 ]]; then
  usage >&2
  exit 2
fi

llama_dir="${TK_LLAMA_CPP_DIR:-$HOME/work/git/llama.cpp}"

case "$llama_dir" in
  "~")      llama_dir="$HOME" ;;
  "~/"*)    llama_dir="$HOME/${llama_dir:2}" ;;
esac

server_bin="${llama_dir}/llama-server"

if [[ -x "$server_bin" ]]; then
  echo "llama.cpp present: ${llama_dir}"
  exit 0
fi

if (( check_only )); then
  echo "llama.cpp missing: ${llama_dir}" >&2
  exit 1
fi

for cmd in git cmake ninja; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "${cmd} is required to build llama.cpp but was not found in PATH" >&2
    exit 127
  fi
done

if [[ ! -d "$llama_dir" ]]; then
  echo "cloning llama.cpp into ${llama_dir}"
  git clone https://github.com/ggml-org/llama.cpp "$llama_dir"
else
  echo "directory exists, skipping clone: ${llama_dir}"
fi

echo "building llama.cpp (CPU + OpenBLAS) in ${llama_dir}/build"
cmake -B "${llama_dir}/build" -S "$llama_dir" -G Ninja \
  -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS
cmake --build "${llama_dir}/build" --config Release -j 4

echo "copying llama-* binaries to ${llama_dir}"
cp "${llama_dir}/build/bin/llama-"* "${llama_dir}/"

if [[ ! -x "$server_bin" ]]; then
  echo "build finished but llama-server binary is missing: ${server_bin}" >&2
  exit 1
fi

echo "llama.cpp present: ${llama_dir}"
