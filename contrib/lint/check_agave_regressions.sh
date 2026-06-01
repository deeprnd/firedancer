#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "agave-guard: $1" >&2
  exit 1
}

if [[ -f .gitmodules ]]; then
  fail ".gitmodules exists; agave submodule metadata must stay removed"
fi

if [[ -e src/app/fdctl/with-agave.mk ]]; then
  fail "src/app/fdctl/with-agave.mk exists; legacy Agave version shim must stay removed"
fi

rg -n '^FD_WITH_AGAVE \?= 0$' src/app/fdctl/Local.mk >/dev/null \
  || fail "src/app/fdctl/Local.mk must default FD_WITH_AGAVE to 0"
rg -n '^FD_WITH_AGAVE \?= 0$' src/app/fddev/Local.mk >/dev/null \
  || fail "src/app/fddev/Local.mk must default FD_WITH_AGAVE to 0"
rg -n '^FD_WITH_AGAVE \?= 0$' src/app/fdctl/with-version.mk >/dev/null \
  || fail "src/app/fdctl/with-version.mk must default FD_WITH_AGAVE to 0"

if rg -n 'agave/target' config/everything.mk >/dev/null; then
  fail "config/everything.mk must not clean agave/target anymore"
fi

if rg -n 'targets: ".*fdctl.*"' .github/workflows/tests.yml >/dev/null; then
  fail "tests.yml must not include fdctl target in default CI matrix"
fi

if rg -n 'targets: ".*firedancer.*"' .github/workflows/tests.yml >/dev/null; then
  fail "tests.yml default CI matrix must use tickoni target"
fi

if [[ -e src/app/fdctl/commands/run_agave.c || -e src/app/fdctl/commands/run_agave.h ]]; then
  fail "run-agave command sources must remain removed"
fi

echo "agave-guard: OK"
