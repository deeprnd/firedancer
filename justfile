set shell := ["bash", "-c"]

default:
  @just --list

help:
  @just --list

# ── Python ─────────────────────────────────────────────────────────────────

python-dev-install extras="dev":
  python3 -m venv .venv
  .venv/bin/python -m pip install --upgrade pip
  .venv/bin/python -m pip install ".[{{extras}}]"

python-dev-install-all:
  @just python-dev-install "dev,protobuf,mathgen,sim,solana,agave-cluster"

# ── Build ──────────────────────────────────────────────────────────────────

build-tk:
  ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build

build-fd:
  make -j"$(nproc)" firedancer

build-fd-gcc:
  make -j"$(nproc)" BUILDDIR=fd-gcc CC=gcc-12 MACHINE=linux_gcc_x86_64 firedancer

build-fd-clang:
  make -j"$(nproc)" BUILDDIR=fd-clang CC=clang-18 MACHINE=linux_clang_x86_64 firedancer

# Compile-only ARM lane matching the CI machine target; Firedancer runtime remains x86-64 Linux only.
build-fd-arm:
  make -j"$(nproc)" BUILDDIR=fd-arm CC=gcc-14 MACHINE=linux_gcc_neoverse_n1 firedancer

build-fd-dev:
  make -j"$(nproc)" firedancer-dev

build-all:
  python3 contrib/readme/run-badged-command.py build bash -c "just build-fd && just build-tk"

# ── Test ───────────────────────────────────────────────────────────────────

test-unit-fd:
  #!/usr/bin/env bash
  set -euo pipefail
  just mem-free || true
  trap 'just mem-free' EXIT
  want=$(free -g | awk '/^Mem:/{print int(($2 - 4) / 6) * 6}')
  (( want > 0 )) && sudo src/util/shmem/fd_shmem_cfg alloc "$want" gigantic 0 >/dev/null 2>&1 || true
  pages=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages 2>/dev/null || echo 0)
  sudo prlimit --pid $$ --memlock=unlimited
  make -j"$(nproc)" unit-test
  if (( pages >= 6 )); then
    echo "allocated $pages gigantic pages on NUMA 0"
    make run-unit-test
  else
    echo "gigantic pages unavailable, falling back to normal pages"
    make run-unit-test TEST_OPTS="--page-sz normal"
  fi

test-unit-tk:
  zig build test

test-unit-all:
  python3 contrib/readme/run-badged-command.py unit bash -c "just test-unit-tk && just test-unit-fd"

test-e2e-fd:
  make -j"$(nproc)" integration-test && make run-integration-test

test-e2e-tk:
  @true

test-e2e-all:
  python3 contrib/readme/run-badged-command.py e2e bash -c "just test-e2e-fd && just test-e2e-tk"

test-integration-fd:
  @true

test-integration-tk:
  @true

test-integration-all:
  python3 contrib/readme/run-badged-command.py integration bash -c "just test-integration-fd && just test-integration-tk"

test-all:
  @just test-unit-all
  @just test-integration-all
  @just test-e2e-all

# ── Test: Coverage ─────────────────────────────────────────────────────────

test-cov-fd:
  #!/usr/bin/env bash
  set -euo pipefail
  just mem-free || true
  trap 'just mem-free' EXIT
  want=$(free -g | awk '/^Mem:/{print int(($2 - 4) / 6) * 6}')
  (( want > 0 )) && sudo src/util/shmem/fd_shmem_cfg alloc "$want" gigantic 0 >/dev/null 2>&1 || true
  pages=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages 2>/dev/null || echo 0)
  sudo prlimit --pid $$ --memlock=unlimited
  # llvm-cov inflates per-job RSS to ~5 GB; halve parallelism to stay within
  # the 16 GB GitHub ubuntu-24.04 runner limit (vs. make -j$(nproc) used for unit tests).
  jobs=$(( $(nproc) / 2 ))
  (( jobs < 1 )) && jobs=1
  make -j"${jobs}" BUILDDIR=fd-cov CC=clang-18 MACHINE=linux_clang_x86_64 EXTRAS="llvm-cov" unit-test
  export TEST_OPTS=""
  (( pages < 6 )) && export TEST_OPTS="--page-sz normal" || true
  python3 contrib/readme/run-badged-command.py cov-fd bash contrib/test/coverage.sh coverage-fd

test-cov-tk:
  python3 contrib/readme/run-badged-command.py cov-tk bash contrib/test/coverage.sh coverage-tk

test-cov-all:
  @just test-cov-fd
  @just test-cov-tk

tests-all:
  @just build-all
  @just quality-check-all
  @just security-check-all
  @just test-all

# ── Quality: Format ────────────────────────────────────────────────────────

quality-format-check-fd:
  bash contrib/quality.sh format-check-fd

quality-format-fix-fd:
  bash contrib/quality.sh format-fix-fd

quality-format-check-tk:
  bash contrib/quality.sh format-check-tk

quality-format-fix-tk:
  bash contrib/quality.sh format-fix-tk

quality-format-check-all:
  @just quality-format-check-fd
  @just quality-format-check-tk

quality-format-fix-all:
  @just quality-format-fix-fd
  @just quality-format-fix-tk

# ── Quality: Lint ──────────────────────────────────────────────────────────

quality-lint-check-fd:
  bash contrib/quality.sh lint-check-fd
  command -v shellcheck >/dev/null || exit 0; bash contrib/quality.sh lint-shellcheck-fd

quality-lint-check-tk:
  bash contrib/quality.sh lint-check-tk

quality-lint-check-all:
  @just quality-lint-check-fd
  @just quality-lint-check-tk

# ── Quality: All ───────────────────────────────────────────────────────────

quality-check-all:
  python3 contrib/readme/run-badged-command.py quality bash -c "just quality-format-check-all && just quality-lint-check-all"

# ── Security: CodeQL ───────────────────────────────────────────────────────

security-codeql-check-fd:
  @true ## bash contrib/security.sh codeql-check-fd, opened issue https://github.com/firedancer-io/firedancer/issues/10058

security-codeql-check-tk:
  @true

security-codeql-check-all:
  @just security-codeql-check-fd
  @just security-codeql-check-tk

# ── Security: Gitleaks ─────────────────────────────────────────────────────

security-gitleaks-check-fd:
  bash contrib/security.sh gitleaks-check-fd

security-gitleaks-check-tk:
  bash contrib/security.sh gitleaks-check-tk

security-gitleaks-check-all:
  @just security-gitleaks-check-fd
  @just security-gitleaks-check-tk

# ── Security: SecComp ──────────────────────────────────────────────────────

security-seccomp-check-fd:
  @true # bash contrib/security.sh seccomp-check-fd

security-seccomp-check-tk:
  @true

security-seccomp-check-all:
  @just security-seccomp-check-fd
  @just security-seccomp-check-tk

# ── Security: Proof ────────────────────────────────────────────────────────

security-proof-check-fd:
  bash contrib/security.sh proof-check-fd

security-proof-check-tk:
  @true

security-proof-check-all:
  @just security-proof-check-fd
  @just security-proof-check-tk

# ── Security: ASan/UBSan ───────────────────────────────────────────────────

security-sanitize-check-fd:
  bash contrib/security.sh sanitize-check-fd

security-sanitize-check-tk:
  bash contrib/security.sh sanitize-check-tk

security-sanitize-check-all:
  @just security-sanitize-check-fd
  @just security-sanitize-check-tk

# ── Security: All ──────────────────────────────────────────────────────────

security-check-all:
  python3 contrib/readme/run-badged-command.py security bash -c "just security-codeql-check-all && just security-gitleaks-check-all && just security-seccomp-check-all && just security-proof-check-all && just security-sanitize-check-all"

# ── Memory (hugepages) ─────────────────────────────────────────────────────

mem-init mode="0700" user="":
  #!/usr/bin/env bash
  set -euo pipefail
  owner="{{user}}"
  if [ -z "$owner" ]; then owner="$USER"; fi
  sudo src/util/shmem/fd_shmem_cfg init {{mode}} "$owner" ""

mem-query:
  sudo src/util/shmem/fd_shmem_cfg query

mem-reset:
  sudo src/util/shmem/fd_shmem_cfg reset

mem-fini:
  sudo src/util/shmem/fd_shmem_cfg fini

mem-alloc pages="24" page_type="gigantic" numa="0":
  sudo src/util/shmem/fd_shmem_cfg alloc {{pages}} {{page_type}} {{numa}}

mem-alloc-auto numa="0":
  pages="$(( ((( $(awk '/MemTotal:/ {print $2}' /proc/meminfo) * 1024 )) - (4 * 1024 * 1024 * 1024)) / (6 * 1024 * 1024 * 1024) * 6 ))"; \
  if [ "$pages" -lt 0 ]; then pages=0; fi; \
  echo "allocating $pages gigantic pages on NUMA {{numa}}"; \
  sudo src/util/shmem/fd_shmem_cfg alloc "$pages" gigantic {{numa}}

mem-free page_type="gigantic" numa="0":
  sudo src/util/shmem/fd_shmem_cfg free {{page_type}} {{numa}}
  sync
  sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
  sudo sh -c 'echo 1 > /proc/sys/vm/compact_memory'
