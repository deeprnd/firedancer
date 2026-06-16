#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: contrib/test/run_llm_server.sh <cpu|gpu>

Runs llama-server with settings tuned for the selected compute backend.

Environment overrides:
  TK_LLAMA_CPP_DIR    local directory for the llama.cpp checkout
  TK_HF_MODEL_DIR     local directory for the model file
  TK_HF_MODEL_FILE    GGUF filename inside TK_HF_MODEL_DIR

Defaults:
  TK_LLAMA_CPP_DIR=$HOME/work/git/llama.cpp
  TK_HF_MODEL_DIR=$HOME/work/models/gemma/gemma-4-E2B-it-qat-GGUF
  TK_HF_MODEL_FILE=gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
USAGE
}

if [[ $# -ne 1 || ( "$1" != "cpu" && "$1" != "gpu" ) ]]; then
  usage >&2
  exit 2
fi
backend="$1"

llama_dir="${TK_LLAMA_CPP_DIR:-$HOME/work/git/llama.cpp}"
model_dir="${TK_HF_MODEL_DIR:-$HOME/work/models/gemma/gemma-4-E2B-it-qat-GGUF}"
model_file="${TK_HF_MODEL_FILE:-gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf}"

case "$llama_dir" in
  "~")    llama_dir="$HOME" ;;
  "~/"*)  llama_dir="$HOME/${llama_dir:2}" ;;
esac
case "$model_dir" in
  "~")    model_dir="$HOME" ;;
  "~/"*)  model_dir="$HOME/${model_dir:2}" ;;
esac

server_bin="${llama_dir}/llama-server"
model_path="${model_dir}/${model_file}"

if [[ ! -x "$server_bin" ]]; then
  echo "llama-server not found: ${server_bin}" >&2
  echo "Run: just test-integration-llama-ensure" >&2
  exit 1
fi

if [[ ! -f "$model_path" ]]; then
  echo "model not found: ${model_path}" >&2
  echo "Run: just test-integration-model-ensure" >&2
  exit 1
fi

if [[ "$backend" == "cpu" ]]; then
  exec "$server_bin" \
    -m "$model_path" \
    --no-mmproj \
    --ctx-size 4096 \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --threads 4 \
    --batch-size 64 \
    --ubatch-size 32 \
    --metrics \
    --slots
else
  exec "$server_bin" \
    -m "$model_path" \
    --no-mmproj \
    --device CUDA0,CUDA1 \
    --split-mode layer \
    --tensor-split 1,1 \
    -ngl all \
    --ctx-size 8192 \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --threads 8 \
    --threads-batch 8 \
    --batch-size 256 \
    --ubatch-size 128 \
    --metrics \
    --slots \
    --verbose \
    --log-file gemma4-e2b-2gpu.log
fi
