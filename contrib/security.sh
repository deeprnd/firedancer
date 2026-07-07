#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MAKE_RUNNER=(./contrib/make-j)
CODEQL_THRESHOLD_CHECK=(python3 ./contrib/codeql-threshold-check.py)
CODEQL_HIGH_SECURITY_THRESHOLD=4.0

log() {
  printf '\n[%s] %s\n' "$1" "$2"
}

run_step() {
  local name="$1"
  shift
  log "run" "$name"
  "$@"
}

usage() {
  cat <<'EOF'
Usage: bash contrib/security.sh <command>

Commands:
  codeql-check-fd     CodeQL analysis on C source
  gitleaks-check-fd   Secret scanning on fd source tree
  gitleaks-check-tk   Secret scanning on tk source tree
  seccomp-check-fd    Verify seccomp policies for fd tiles
  proof-check-fd      CBMC proof checks on C source
  sanitize-check-fd   Build fd with Clang ASan + UBSan
  sanitize-check-tk   Build tk with ReleaseSafe (Zig built-in safety checks)
EOF
}

cmd_codeql_check_fd() {
  run_step "codeql pack install" codeql pack install contrib/codeql/test
  run_step "codeql pack tests" codeql test run contrib/codeql/test
  run_step "codeql pack download" codeql pack download codeql/cpp-queries
  rm -rf build/codeql-db
  run_step "codeql database create" \
    bash -c 'BUILDDIR=codeql codeql database create --language=c-cpp --command="make -j$(nproc) firedancer" build/codeql-db'
  run_step "codeql database analyze" \
    codeql database analyze \
      build/codeql-db \
      codeql/cpp-queries:codeql-suites/cpp-code-scanning.qls \
      contrib/codeql/src/nightly \
      --format=sarif-latest \
      --output=build/codeql-results.sarif
}

cmd_gitleaks_check_fd() {
  run_step "gitleaks fd" \
    gitleaks detect --no-git --verbose --source src/ \
      --config contrib/gitleaks-fd.toml
}

cmd_gitleaks_check_tk() {
  run_step "gitleaks tk" \
    gitleaks detect --no-git --verbose --source src/tickoni
  run_step "gitleaks app/tickoni" \
    gitleaks detect --no-git --verbose --source src/app/tickoni
}

cmd_seccomp_check_fd() {
  run_step "seccomp policies" "${MAKE_RUNNER[@]}" seccomp-policies
}

cmd_proof_check_fd() {
  run_step "proof checks" "${MAKE_RUNNER[@]}" proof
}

cmd_sanitize_check_fd() {
  # Same 5-lib LOCAL_MKS filter as cov/build/test — only tango, util, ballet,
  # disco, waltz (minus disco/quic, ballet/zksdk, waltz/quic).  Excludes
  # flamenco and other dirs so we only compile what gets linked into the
  # Tickoni harness libs.
  _local_mks=$(find src/tango src/util src/ballet src/disco src/waltz \
    -name Local.mk | grep -vE 'disco/quic/|ballet/zksdk/|waltz/quic/' | tr '\n' ' ')
  if [ ! -d "build/clang-asan-ubsan" ]; then
    run_step "clang asan+ubsan build" \
      make -j"$(nproc)" BUILDDIR=clang-asan-ubsan CC=clang EXTRAS="asan ubsan" \
        "LOCAL_MKS=$_local_mks" \
        unit-test
  fi
  run_step "clang asan+ubsan check" \
    make -j"$(nproc)" BUILDDIR=clang-asan-ubsan CC=clang EXTRAS="asan ubsan" \
      "LOCAL_MKS=$_local_mks" \
      unit-test
}

cmd_sanitize_check_tk() {
  run_step "zig releasesafe" \
    zig build test -Dfd-lib-dir=build/fd-tickoni-fd/lib -Doptimize=ReleaseSafe
}

case "${1:-}" in
  codeql-check-fd)   cmd_codeql_check_fd ;;
  gitleaks-check-fd) cmd_gitleaks_check_fd ;;
  gitleaks-check-tk) cmd_gitleaks_check_tk ;;
  seccomp-check-fd)  cmd_seccomp_check_fd ;;
  proof-check-fd)    cmd_proof_check_fd ;;
  sanitize-check-fd)  cmd_sanitize_check_fd ;;
  sanitize-check-tk)  cmd_sanitize_check_tk ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
