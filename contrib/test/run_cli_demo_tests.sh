#!/usr/bin/env bash
# Ensure llama.cpp and model exist, start the local server, run the CLI investment
# demo proofs, then stop the server.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

llama_dir="${TK_LLAMA_CPP_DIR:-$HOME/work/git/llama.cpp}"
case "$llama_dir" in
  "~")    llama_dir="$HOME" ;;
  "~/"*)  llama_dir="$HOME/${llama_dir:2}" ;;
esac

backend=cpu
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)"
  if (( gpu_count > 0 )); then
    if ldd "${llama_dir}/llama-server" 2>/dev/null | grep -qi 'cuda\|cublas'; then
      backend=gpu
    else
      echo "note: GPU detected but llama.cpp binary has no CUDA support; using cpu"
    fi
  fi
fi
echo "compute backend: ${backend}"

if [[ "$backend" == "gpu" ]]; then
  bash "${SCRIPT_DIR}/ensure_llama_cpp.sh" --gpu
else
  bash "${SCRIPT_DIR}/ensure_llama_cpp.sh"
fi

bash "${SCRIPT_DIR}/ensure_hf_model.sh"

server_pid=
log_file="/tmp/llama_server_cli_$$.log"
cleanup() {
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
  [[ -n "$server_pid" ]] && wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

echo "starting llama-server (${backend}) — log: ${log_file}"
bash "${SCRIPT_DIR}/run_llm_server.sh" "$backend" >"$log_file" 2>&1 &
server_pid=$!

endpoint="${TK_LLM_ENDPOINT:-http://127.0.0.1:8080/v1}"
health_url="${endpoint%/v1}/health"
echo "waiting for llama-server at ${health_url}"
ready=0
for i in $(seq 1 60); do
  if curl -sf "$health_url" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "llama-server exited prematurely; log: ${log_file}" >&2
    head -3 "$log_file" >&2
    echo "..." >&2
    tail -20 "$log_file" >&2
    exit 1
  fi
  sleep 2
done
if (( !ready )); then
  echo "llama-server did not become ready within 120s; log: ${log_file}" >&2
  head -3 "$log_file" >&2
  echo "..." >&2
  tail -20 "$log_file" >&2
  exit 1
fi
echo "llama-server ready"

echo "building tickoni CLI"
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build --summary all

run_and_assert() {
  local thesis="$1"
  local expected_scenario="$2"
  local expected_policy="$3"
  local expected_ticket_id="$4"
  local expected_blocked_reason="$5"
  local expected_failed_scope_dim="$6"

  local output
  output="$(zig-out/bin/tickoni demo investment --json --thesis "$thesis")"
  JSON_OUTPUT="$output" \
  EXPECTED_SCENARIO="$expected_scenario" \
  EXPECTED_POLICY="$expected_policy" \
  EXPECTED_TICKET_ID="$expected_ticket_id" \
  EXPECTED_BLOCKED_REASON="$expected_blocked_reason" \
  EXPECTED_FAILED_SCOPE_DIM="$expected_failed_scope_dim" \
  python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["JSON_OUTPUT"])
assert payload["scenario"] == os.environ["EXPECTED_SCENARIO"], payload
assert payload["policy_outcome"] == os.environ["EXPECTED_POLICY"], payload
expected_ticket_id = os.environ["EXPECTED_TICKET_ID"]
if expected_ticket_id:
    assert payload["ticket_id"] == expected_ticket_id, payload
else:
    assert payload["ticket_id"] is None, payload
expected_blocked_reason = os.environ["EXPECTED_BLOCKED_REASON"]
if expected_blocked_reason:
    assert payload["blocked_reason"] == expected_blocked_reason, payload
else:
    assert payload["blocked_reason"] is None, payload
expected_failed_scope_dim = os.environ["EXPECTED_FAILED_SCOPE_DIM"]
if expected_failed_scope_dim:
    assert payload["failed_scope_dim"] == expected_failed_scope_dim, payload
else:
    assert payload["failed_scope_dim"] is None, payload
assert payload["matched_ticker"], payload
assert payload["model_id"], payload
assert payload["excerpt"], payload
assert payload["replay_match"] is True, payload
assert payload["external_effects_disabled"] is True, payload
assert payload["divergence_count"] == 0, payload
PY
}

echo "running CLI allowed scenario"
run_and_assert \
  "I want to invest USD 2,000 in AI infrastructure through US-listed ETFs and large-cap equities." \
  "allowed" \
  "allow" \
  "ticket_ai_infra_2000_market" \
  "" \
  ""

echo "running CLI oversized blocked scenario"
run_and_assert \
  "I want to invest USD 25,000 in AI infrastructure through US-listed ETFs and large-cap equities." \
  "oversized_blocked" \
  "deny" \
  "ticket_ai_infra_25000_blocked" \
  "per_order_notional_exceeded" \
  "per_order_notional"

echo "running CLI restricted ticker scenario"
run_and_assert \
  "Buy SOXL in an AI infrastructure basket with USD 2,000." \
  "restricted_instrument" \
  "deny" \
  "" \
  "restricted_instrument" \
  "restricted_instrument"
