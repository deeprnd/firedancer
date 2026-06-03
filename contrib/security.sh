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
  codeql-check-tk     CodeQL analysis on tk source
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
    bash -c 'BUILDDIR=codeql codeql database create --language=c-cpp --command="make -j tickoni" build/codeql-db'
  run_step "codeql database analyze" \
    codeql database analyze \
      build/codeql-db \
      codeql/cpp-queries:codeql-suites/cpp-code-scanning.qls \
      contrib/codeql/src/nightly \
      --format=sarif-latest \
      --output=build/codeql-results.sarif
}

cmd_codeql_check_tk() {
  run_step "codeql zig support" bash -c '
    if ! codeql resolve languages --format=json |
      grep -Eq "^[[:space:]]*\"zig\"[[:space:]]*:"; then
      echo "[security-codeql] installed CodeQL CLI does not support Zig." >&2
      echo "[security-codeql] \`codeql resolve languages\` does not list \`zig\`." >&2
      exit 1
    fi
  '

  run_step "codeql source snapshot" bash -c '
    rm -rf build/codeql-source-tk &&
    mkdir -p build/codeql-source-tk &&
    git ls-files -co --exclude-standard -z -- build.zig build.zig.zon src/tickoni src/app/tickoni |
      while IFS= read -r -d "" relative_path; do
        if [[ -e "$relative_path" ]]; then
          printf "%s\0" "$relative_path"
        fi
      done |
      rsync -a --delete --from0 --files-from=- ./ build/codeql-source-tk/
  '

  rm -rf build/codeql-db-tk
  run_step "codeql database create" \
    codeql database create build/codeql-db-tk \
      --language=zig \
      --build-mode=none \
      --source-root=build/codeql-source-tk \
      --overwrite

  run_step "codeql database analyze" \
    codeql database analyze build/codeql-db-tk \
      --format=sarifv2.1.0 \
      --output=build/codeql-results-tk.sarif \
      --sarif-category=zig \
      --threads=0

  run_step "codeql threshold check" \
    "${CODEQL_THRESHOLD_CHECK[@]}" \
      build/codeql-results-tk.sarif \
      "$CODEQL_HIGH_SECURITY_THRESHOLD"
}

cmd_gitleaks_check_fd() {
  run_step "gitleaks fd" \
    gitleaks detect --no-git --source src/ \
      --exclude-path src/tickoni \
      --exclude-path src/app/tickoni
}

cmd_gitleaks_check_tk() {
  run_step "gitleaks tk" \
    gitleaks detect --no-git --source src/tickoni
  run_step "gitleaks app/tickoni" \
    gitleaks detect --no-git --source src/app/tickoni
}

cmd_seccomp_check_fd() {
  run_step "seccomp policies" "${MAKE_RUNNER[@]}" seccomp-policies
}

cmd_proof_check_fd() {
  run_step "proof checks" "${MAKE_RUNNER[@]}" proof
}

cmd_sanitize_check_fd() {
  run_step "clang asan+ubsan" \
    make -j BUILDDIR=clang-asan-ubsan CC=clang EXTRAS="asan ubsan" check
}

cmd_sanitize_check_tk() {
  run_step "zig releasesafe" \
    zig build test -Doptimize=ReleaseSafe
}

case "${1:-}" in
  codeql-check-fd)   cmd_codeql_check_fd ;;
  codeql-check-tk)   cmd_codeql_check_tk ;;
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
