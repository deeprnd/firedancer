#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "agave-guard: $1" >&2
  exit 1
}

if [[ -f .gitmodules ]]; then
  fail ".gitmodules exists; agave submodule metadata must stay removed"
fi

if [[ -d src/app/firedancer || -d src/app/firedancer-dev ]]; then
  fail "legacy app paths src/app/firedancer* must stay removed"
fi

if [[ ! -d src/app/tickoni || ! -d src/app/tickoni-dev ]]; then
  fail "tickoni app paths must exist"
fi

if rg -n 'agave/target' config/everything.mk >/dev/null; then
  fail "config/everything.mk must not clean agave/target anymore"
fi

if rg -n 'targets: ".*fdctl.*"' .github/workflows/tests.yml >/dev/null; then
  fail "tests.yml must not include fdctl target in default CI matrix"
fi

if rg -n 'targets: ".*firedancer.*"' .github/workflows/tests.yml >/dev/null; then
  fail "tests.yml default CI matrix must use tickoni target"
fi

for workflow in .github/workflows/tests.yml \
                .github/workflows/builds.yml \
                .github/workflows/codeql.yml \
                .github/workflows/coverage_report.yml; do
  if rg -n 'submodule-init' "$workflow" >/dev/null; then
    fail "$workflow must not depend on submodule-init"
  fi
done

if [[ -e src/app/fdctl/commands/run_agave.c || -e src/app/fdctl/commands/run_agave.h ]]; then
  fail "run-agave command sources must remain removed"
fi

for path in src/app/shared \
            src/app/tickoni \
            src/app/tickoni-dev \
            .github/workflows/tests.yml \
            .github/workflows/builds.yml \
            .github/workflows/codeql.yml \
            .github/workflows/coverage_report.yml; do
  if rg -n '\bagave\b|run-agave|FD_WITH_AGAVE|no_agave|is_agave' "$path" >/dev/null; then
    fail "$path contains removed agave-era runtime hooks"
  fi
done

echo "agave-guard: OK"
