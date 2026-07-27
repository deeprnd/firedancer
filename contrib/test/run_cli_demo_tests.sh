#!/usr/bin/env bash
# Focused S6 CLI verification: build the supervisor demo binary, validate usage
# failures, then assert the fixture-backed conformance suite JSON contract.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

build_cmd=(zig build -Dfd-lib-dir=build/fd-tickoni-fd/lib --summary all)
manifest="src/tickoni/demo/fixtures/demo.manifest.json"
binary="zig-out/bin/tickoni-supervisor"

export ZIG_GLOBAL_CACHE_DIR=.zig-global-cache

printf 'building tickoni-supervisor with fixture-backed demo modules\n'
if ! "${build_cmd[@]}"; then
  echo "build failed" >&2
  exit 1
fi

printf 'verifying bare demo usage fails closed\n'
usage_output="$($binary demo 2>&1)"
usage_status=$?
if [[ $usage_status -eq 0 ]]; then
  echo "expected bare demo invocation to fail" >&2
  exit 1
fi
python3 - <<'PY' "$usage_output"
import sys
text = sys.argv[1]
assert 'demo usage error' in text or 'Usage:' in text, text
PY

printf 'running JSON conformance suite\n'
json_output="$($binary demo investment --json --manifest "$manifest")" || exit 1
python3 - <<'PY' "$json_output"
import json, sys
payload = json.loads(sys.argv[1])
assert payload['preflight'] == 'passed', payload
suite = payload['suite']
assert len(suite) == 4, suite
scenarios = {item['scenario']: item for item in suite}
assert set(scenarios) == {'allowed', 'oversized_blocked', 'restricted_instrument', 'tampered_replay'}, scenarios
assert scenarios['allowed']['policy_outcome'] == 'allow', scenarios['allowed']
assert scenarios['allowed']['external_effects_disabled'] is True, scenarios['allowed']
assert scenarios['oversized_blocked']['policy_outcome'] == 'deny', scenarios['oversized_blocked']
assert scenarios['oversized_blocked']['blocked_diagnostic']['code'] == 'policy_denied', scenarios['oversized_blocked']
assert scenarios['restricted_instrument']['blocked_diagnostic']['code'] == 'restricted_instrument', scenarios['restricted_instrument']
assert scenarios['tampered_replay']['blocked_diagnostic']['code'] == 'tampered_replay_artifact', scenarios['tampered_replay']
assert scenarios['tampered_replay']['replay_result']['replay_match'] is False, scenarios['tampered_replay']
for item in suite:
    assert item['runtime_tier'], item
    assert item['isolation_tier'], item
    assert item['normalized_event_hash'], item
    assert item['proposal_hash'] is not None, item
PY

printf 'running plain-text conformance suite\n'
plain_output="$($binary demo investment --plain --manifest "$manifest")" || exit 1
python3 - <<'PY' "$plain_output"
import sys
text = sys.argv[1]
assert text.count('manifest_id: demo.investment.v1') == 4, text
assert 'scenario: tampered_replay' in text, text
assert 'blocked_code: tampered_replay_artifact' in text, text
PY

printf 'PASS: tickoni-supervisor demo contract and suite outputs verified\n'
