#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "agave-guard: $1" >&2
  exit 1
}

TICKONI_SHIM_REMOVAL_DATE="2026-12-31"

if [[ -f .gitmodules ]]; then
  fail ".gitmodules exists; agave submodule metadata must stay removed"
fi

if [[ ! -d src/app/firedancer || ! -d src/app/firedancer-dev ]]; then
  fail "firedancer app paths must exist"
fi

for removed_path in .github/workflows/test_firedancer_localnet.yml \
                    .github/workflows/test_firedancer_testnet.yml \
                    .github/actions/submodule-init/action.yml; do
  if [[ -e "$removed_path" ]]; then
    fail "$removed_path must stay removed"
  fi
done

if [[ -d src/app/tickoni || -d src/app/tickoni-dev ]]; then
  fail "tickoni app paths must stay removed after rollback"
fi

if [[ ! -f doc/tickoni-interface-contract.md ]]; then
  fail "doc/tickoni-interface-contract.md must exist"
fi

if ! rg -n "Removal date: \`${TICKONI_SHIM_REMOVAL_DATE}\`" doc/tickoni-interface-contract.md >/dev/null; then
  fail "tickoni interface contract must declare shim removal date ${TICKONI_SHIM_REMOVAL_DATE}"
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

if ! rg -n 'targets: ".*tickoni.*"' .github/workflows/tests.yml >/dev/null; then
  fail "tests.yml default CI matrix must include tickoni target"
fi

if ! rg -n 'targets: tickoni' .github/workflows/codeql.yml >/dev/null; then
  fail "codeql.yml must build tickoni target"
fi

if ! rg -n 'TARGETS="all integration-test tickoni"' contrib/test/ci_tests.sh >/dev/null; then
  fail "contrib/test/ci_tests.sh default TARGETS must include tickoni"
fi

if ! rg -n 'make-bin,tickoni' src/app/firedancer/Local.mk >/dev/null; then
  fail "src/app/firedancer/Local.mk must define tickoni binary target"
fi

if ! rg -n "Removal date: ${TICKONI_SHIM_REMOVAL_DATE}" src/app/firedancer/Local.mk >/dev/null; then
  fail "firedancer compatibility shim must carry explicit removal date ${TICKONI_SHIM_REMOVAL_DATE}"
fi

if ! rg -n '^\$\(OBJDIR\)/bin/firedancer: \$\(OBJDIR\)/bin/tickoni$' src/app/firedancer/Local.mk >/dev/null; then
  fail "firedancer compatibility shim must alias to tickoni binary"
fi

for workflow in .github/workflows/tests.yml \
                .github/workflows/builds.yml \
                .github/workflows/codeql.yml \
                .github/workflows/coverage_report.yml; do
  if rg -n 'submodule-init' "$workflow" >/dev/null; then
    fail "$workflow must not depend on submodule-init"
  fi
done

if rg -n 'submodule-init' .github/workflows >/dev/null; then
  fail ".github/workflows must not reference submodule-init"
fi

if [[ -e src/app/fdctl/commands/run_agave.c || -e src/app/fdctl/commands/run_agave.h ]]; then
  fail "run-agave command sources must remain removed"
fi

for path in .github/workflows/tests.yml \
            .github/workflows/builds.yml \
            .github/workflows/codeql.yml \
            .github/workflows/coverage_report.yml \
            contrib/test/ci_tests.sh \
            contrib/build.sh; do
  if rg -n '/bin/firedancer([[:space:]]|$)|make([[:space:]]+-j)?[[:space:]]+firedancer([[:space:]]|$)|FIREDANCER_CONFIG_TOML' "$path" >/dev/null; then
    fail "$path reintroduced legacy firedancer runtime surface"
  fi
done

for path in src/app/shared \
            src/app/firedancer \
            src/app/firedancer-dev \
            .github/workflows/tests.yml \
            .github/workflows/builds.yml \
            .github/workflows/codeql.yml \
            .github/workflows/coverage_report.yml; do
  if rg -n '\bagave\b|run-agave|FD_WITH_AGAVE|no_agave|is_agave' "$path" >/dev/null; then
    fail "$path contains removed agave-era runtime hooks"
  fi
done

echo "agave-guard: OK"
