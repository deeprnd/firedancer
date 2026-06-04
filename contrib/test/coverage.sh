#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

MAKE_RUNNER=(./contrib/make-j)

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
Usage: bash contrib/test/coverage.sh <command>

Commands:
  coverage-fd   Firedancer (HFT Engine) coverage via LLVM source-based instrumentation
  coverage-tk   Tickoni (AI Harness) coverage via kcov
EOF
}

cmd_coverage_fd() {
  local builddir="fd-cov"
  local covdir="build/${builddir}/cov"
  local summary="build/coverage/fd/coverage-summary.json"
  local config="contrib/test/coverage-fd.json"

  run_step "build fd with llvm-cov" \
    "${MAKE_RUNNER[@]}" BUILDDIR="$builddir" CC=clang-18 \
    MACHINE=linux_clang_x86_64 EXTRAS="llvm-cov" unit-test

  # TEST_OPTS is set by the caller (test-cov-fd justfile recipe) which handles
  # hugepage allocation and prlimit before invoking this script.
  run_step "run unit tests" \
    make run-unit-test BUILDDIR="$builddir" CC=clang-18 \
    MACHINE=linux_clang_x86_64 EXTRAS="llvm-cov" TEST_OPTS="${TEST_OPTS:-}"

  run_step "merge llvm profiles" bash -c "
    mkdir -p '${covdir}'
    llvm-profdata merge -o '${covdir}/cov.profdata' '${covdir}/raw/'*.profraw
  "

  run_step "build mappings archive" bash -c "
    rm -f '${covdir}/mappings.ar'
    find 'build/${builddir}/obj' -name '*.o' -exec sh -c '
      [ -n \"\$(llvm-objdump -h \"\$1\" | grep llvm_covmap)\" ] \
        && llvm-ar --thin q '${covdir}/mappings.ar' \"\$1\"
    ' sh {} \;
  "

  run_step "check coverage thresholds" \
    python3 contrib/readme/coverage_report.py coverage-fd \
      "${covdir}" \
      "${summary}" \
      --config "${config}"
}

cmd_coverage_tk() {
  command -v kcov >/dev/null 2>&1 || {
    echo "ERROR: kcov not found. Install it with: sudo apt-get install kcov" >&2
    exit 1
  }

  local cov_bins="zig-out/cov"
  local cov_raw="build/coverage/tk/kcov"
  local summary="build/coverage/tk/coverage-summary.json"
  local config="contrib/test/coverage-tk.json"

  run_step "build zig test binaries" zig build cov

  mkdir -p "$cov_raw"

  run_step "run tests via kcov" bash -c "
    for bin in '${cov_bins}'/*; do
      [ -f \"\$bin\" ] || continue
      name=\"\$(basename \"\$bin\")\"
      kcov --include-pattern=src/tickoni \
        '${cov_raw}'/\"\$name\" \
        \"\$bin\"
    done
  "

  run_step "merge kcov outputs" bash -c "
    dirs=()
    for d in '${cov_raw}'/test-*; do
      [ -d \"\$d\" ] && dirs+=(\"\$d\")
    done
    if [ \${#dirs[@]} -gt 1 ]; then
      kcov --merge '${cov_raw}/merged' \"\${dirs[@]}\"
    elif [ \${#dirs[@]} -eq 1 ]; then
      ln -sfn \"\$(realpath \"\${dirs[0]}\")\" '${cov_raw}/merged'
    else
      echo 'ERROR: no kcov output directories found' >&2
      exit 1
    fi
  "

  run_step "check coverage thresholds" \
    python3 contrib/readme/coverage_report.py coverage-tk \
      "${cov_raw}/merged" \
      "${summary}" \
      --config "${config}"
}

main() {
  case "${1:-}" in
    coverage-fd) cmd_coverage_fd ;;
    coverage-tk) cmd_coverage_tk ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
