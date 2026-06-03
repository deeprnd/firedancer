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
  zig build

build-fd:
  make -j"$(nproc)" tickoni

build-fd-dev:
  make -j"$(nproc)" firedancer-dev

build-all:
  python3 contrib/readme/run-badged-command.py build "just build-tk && just build-fd"

# ── Test ───────────────────────────────────────────────────────────────────

test-unit-tk:
  zig build test

test-integration-fd:
  make -j"$(nproc)" itest

test-unit-all:
  python3 contrib/readme/run-badged-command.py unit "just test-unit-tk"

test-integration-all:
  python3 contrib/readme/run-badged-command.py integration "just test-integration-fd"

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
  python3 contrib/readme/run-badged-command.py quality "just quality-format-check-all && just quality-lint-check-all"

# ── Security: CodeQL ───────────────────────────────────────────────────────

security-codeql-check-fd:
  bash contrib/security.sh codeql-check-fd

security-codeql-check-tk:
  bash contrib/security.sh codeql-check-tk

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
  bash contrib/security.sh seccomp-check-fd

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
  bash contrib/security.sh asan-check-fd

security-sanitize-check-tk:
  bash contrib/security.sh asan-check-tk

security-sanitize-check-all:
  @just security-sanitize-check-fd
  @just security-sanitize-check-tk

# ── Security: All ──────────────────────────────────────────────────────────

security-check-all:
  python3 contrib/readme/run-badged-command.py security "just security-codeql-check-all && just security-gitleaks-check-all && just security-seccomp-check-all && just security-proof-check-all && just security-sanitize-check-all"

# ── Memory (hugepages) ─────────────────────────────────────────────────────

mem-init:
  sudo src/util/shmem/fd_shmem_cfg init 0700 "$USER" ""

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
