set shell := ["bash", "-c"]

# Prefer GNU Make 4.x (Homebrew installs it as `gmake` on macOS); fall back to `make`.
# Firedancer's GNUmakefile uses `undefine`, which needs GNU Make >= 3.82.
make := `command -v gmake || command -v make`

# Firedancer/Tickoni build natively only on Linux. On macOS, build/test/run
# recipes transparently re-run inside this Linux container (see the `dock` recipe).
dev_image := "tickoni-dev:24.04"

# Resolve a docker-compatible container CLI: prefer docker, then podman, then
# nerdctl, then colima's bundled nerdctl. Empty if none is installed.
container := `if command -v docker >/dev/null 2>&1; then echo docker; elif command -v podman >/dev/null 2>&1; then echo podman; elif command -v nerdctl >/dev/null 2>&1; then echo nerdctl; elif command -v colima >/dev/null 2>&1; then echo "colima nerdctl -p tickoni --"; else echo ""; fi`

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

# ── All-in ──────────────────────────────────────────────────────────────────

tests-all:
  @just build-all
  @just quality-check-all
  @just security-check-all
  @just security-engine-check-changes
  @just test-all

# ── Build ──────────────────────────────────────────────────────────────────

build-tk:
  ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir=build/fd-tickoni-fd/lib

build-fd-tk-libs:
  @just _build-fd-tk-libs ""

# tickoni_fd machine profile: builds only the 5 Firedancer libraries
# Tickoni reuses (tango, util, ballet, disco, waltz). Excludes
# Solana validator tiles, RPC schemas, unrelated source, unit-test bins,
# fuzz-test bins, and other binaries (RocksDB, io_uring, etc.).
#
# NOTE: Firedancer's everything.mk compiles all sources regardless of
# requested .a targets. We list only the 5 libraries Tickoni needs as
# the final archive targets. build-fd variants must pre-create the obj
# directory because Firedancer writes .d dependency files to nested
# paths (e.g. obj/ballet/zksdk/instructions/...) that don't exist by
# default.
build-fd:
  #!/usr/bin/env bash
  set -euo pipefail
  mkdir -p build/fd-tickoni-fd/obj
  {{make}} -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR=fd-tickoni-fd \
    build/fd-tickoni-fd/lib/libfd_tango.a \
    build/fd-tickoni-fd/lib/libfd_util.a \
    build/fd-tickoni-fd/lib/libfd_ballet.a \
    build/fd-tickoni-fd/lib/libfd_disco.a \
    build/fd-tickoni-fd/lib/libfd_waltz.a

build-fd-gcc:
  #!/usr/bin/env bash
  set -euo pipefail
  mkdir -p build/fd-gcc/obj
  {{make}} -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR=fd-gcc CC=gcc-12 \
    build/fd-gcc/lib/libfd_tango.a \
    build/fd-gcc/lib/libfd_util.a \
    build/fd-gcc/lib/libfd_ballet.a \
    build/fd-gcc/lib/libfd_disco.a \
    build/fd-gcc/lib/libfd_waltz.a

build-fd-clang:
  #!/usr/bin/env bash
  set -euo pipefail
  mkdir -p build/fd-clang/obj
  {{make}} -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR=fd-clang CC=clang-18 \
    build/fd-clang/lib/libfd_tango.a \
    build/fd-clang/lib/libfd_util.a \
    build/fd-clang/lib/libfd_ballet.a \
    build/fd-clang/lib/libfd_disco.a \
    build/fd-clang/lib/libfd_waltz.a

# Compile-only ARM lane matching the CI machine target; Firedancer runtime remains x86-64 Linux only.
build-fd-arm:
  #!/usr/bin/env bash
  set -euo pipefail
  mkdir -p build/fd-arm/obj
  {{make}} -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR=fd-arm CC=gcc-14 \
    build/fd-arm/lib/libfd_tango.a \
    build/fd-arm/lib/libfd_util.a \
    build/fd-arm/lib/libfd_ballet.a \
    build/fd-arm/lib/libfd_disco.a \
    build/fd-arm/lib/libfd_waltz.a

build-fd-dev:
  make -j"$(nproc)" all

build-all:
  python3 contrib/readme/run-badged-command.py build bash -c "just build-fd && just build-tk"

# ── Clean ────────────────────────────────────────────────────────────────────

# Clean all Firedancer and Zig/Tickoni build artifacts.
# Firedancer outputs live under `build/` (BUILDDIR variants).
# Zig/Tickoni outputs live under `target/` and `zig-out/`.
clean-all:
  rm -rf build/ target/ zig-out/

# ── macOS: run any recipe in the Linux dev container ─────────────────────────
# Firedancer/Tickoni build natively only on Linux. The `dock` recipe mounts the
# repo into an ubuntu:24.04 arm64 container (native on Apple Silicon), builds the
# fd_tango/fd_util/fd_ballet libs first (mirroring .github/actions/build-fd-tk-libs), then
# runs the requested recipe. On Linux it runs the recipe natively (no container).
#
# Run any recipe inside the Linux dev container, e.g. `just dock test-unit-tk`.
dock +recipe:
  #!/usr/bin/env bash
  set -euo pipefail
  if [ "$(uname)" != "Darwin" ]; then exec just {{recipe}}; fi
  if [ -z "{{container}}" ]; then
    echo "No container runtime found (checked docker, podman, nerdctl, colima)." >&2
    exit 1
  fi
  # colima's bundled nerdctl needs a VM with the containerd runtime; use a
  # dedicated profile so an existing (docker-runtime) colima setup is untouched.
  case "{{container}}" in
    colima*) colima status -p tickoni >/dev/null 2>&1 || colima start -p tickoni --runtime containerd ;;
  esac
  just _dev-image
  {{container}} run --rm \
    -v "{{justfile_directory()}}":/work -w /work \
    {{dev_image}} \
    bash -lc 'just _build-fd-tk-libs tk-arm && just {{recipe}}'

# Build the Linux dev image once (just + Zig 0.16.0 + build toolchain). Idempotent.
[private]
_build-fd-tk-libs extras="":
  #!/usr/bin/env bash
  set -euo pipefail
  cmd=({{make}} -j"$(nproc)" MACHINE=tickoni_fd)
  if [ -n "{{extras}}" ]; then
    cmd+=("EXTRAS={{extras}}")
  fi
  cmd+=(
    build/native/gcc/lib/libfd_tango.a
    build/native/gcc/lib/libfd_util.a
    build/native/gcc/lib/libfd_ballet.a
    build/native/gcc/lib/libfd_disco.a
    build/native/gcc/lib/libfd_waltz.a
  )
  "${cmd[@]}"

[private]
_dev-image:
  #!/usr/bin/env bash
  set -euo pipefail
  if {{container}} image inspect {{dev_image}} >/dev/null 2>&1; then exit 0; fi
  echo "Building {{dev_image}} (one-time, a few minutes)…" >&2
  ctx="$(mktemp -d "$HOME/.tickoni-devimg.XXXXXX")"  # under $HOME so colima/nerdctl can see the build context
  trap 'rm -rf "$ctx"' EXIT
  printf '%s\n' \
    'FROM ubuntu:24.04' \
    'ENV DEBIAN_FRONTEND=noninteractive' \
    'RUN apt-get update && apt-get install -y --no-install-recommends build-essential git curl ca-certificates xz-utils pkg-config perl && rm -rf /var/lib/apt/lists/*' \
    'RUN curl -sSfL https://just.systems/install.sh | bash -s -- --to /usr/local/bin' \
    'RUN curl -sSfL https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz | tar -xJ -C /opt && ln -s /opt/zig-aarch64-linux-0.16.0/zig /usr/local/bin/zig' \
    > "$ctx/Dockerfile"
  {{container}} build --platform linux/arm64 -t {{dev_image}} "$ctx"

# ── Test ───────────────────────────────────────────────────────────────────

test-all:
  @just test-unit-all
  @just test-integration-all
  @just test-cov-all
  @just test-system-all
  @just test-e2e-all

test-unit-fd:
  #!/usr/bin/env bash
  set -euo pipefail
  # Override LOCAL_MKS so everything.mk's ?= assignment is skipped.
  # Only the 5 Tickoni dirs: tango, util, ballet, disco, waltz —
  # minus subdirs not compiled into the 5 libs (disco/quic, ballet/zksdk,
  # ballet/reedsol, waltz/quic, waltz/tls). Reduces from 195 Local.mks
  # (187 tests, 543 objs) to ~93 Local.mks (4 tests, ~150 objs).
  {{make}} -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR=fd-tickoni-fd \
    "LOCAL_MKS=$(find src/tango src/util src/ballet src/disco src/waltz -name Local.mk | grep -vE 'disco/quic/|ballet/zksdk/|waltz/quic/' | tr '\n' ' ')" \
    unit-test
  {{make}} MACHINE=tickoni_fd BUILDDIR=fd-tickoni-fd run-unit-test TEST_OPTS="--page-sz normal"

# Tickoni unit lane: pure logic and fixture/mock-backed tests only.
# No running servers belong here.
test-unit-tk:
  ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir=build/fd-tickoni-fd/lib test --summary all

# Print computed hash and wire bytes for every audit fixture event, and emit audit JSONL.
# Use the output to understand or snapshot the current encoding after intentional changes.
gen-audit-fixtures:
  TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build test 2>&1
  TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build integration-test 2>&1

test-unit-all:
  python3 contrib/readme/run-badged-command.py unit bash -c "just test-unit-tk && just test-unit-fd"

test-e2e-fd:
  {{make}} -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR=fd-tickoni-fd integration-test && {{make}} MACHINE=tickoni_fd BUILDDIR=fd-tickoni-fd run-integration-test

test-e2e-tk:
  @true

test-e2e-all:
  python3 contrib/readme/run-badged-command.py e2e bash -c "just test-e2e-fd && just test-e2e-tk"

test-integration-fd:
  @true

# Tickoni integration lane: transport and boundary wiring against local mocks.
test-integration-tk:
  ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir=build/fd-tickoni-fd/lib integration-test --summary all

# Deterministic offline investment demo — no llama.cpp required.
demo-tk:
  ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build
  zig-out/bin/tickoni demo investment --fixture --thesis "I want to invest USD 2,000 in AI infrastructure through US-listed ETFs and large-cap equities."

# Tickoni system lane: opt-in real-LLM investment demo proof.
test-system-tk:
  bash contrib/test/run_system_model_tests.sh

test-cli-tk:
  bash contrib/test/run_cli_demo_tests.sh

test-system-fd:
  @true

test-system-all:
  python3 contrib/readme/run-badged-command.py system bash -c "just test-system-tk && just test-system-fd"

infra-run-llamacpp:
  #!/usr/bin/env bash
  set -euo pipefail
  source contrib/test/llama_cpp_env.sh
  llama_dir="$(tk_resolve_llama_cpp_dir)"
  backend=cpu
  if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)"
    if (( gpu_count > 0 )) && ldd "${llama_dir}/llama-server" 2>/dev/null | grep -qi 'cuda\|cublas'; then
      backend=gpu
    fi
  fi
  [[ "$backend" == "gpu" ]] && bash contrib/test/ensure_llama_cpp.sh --gpu || bash contrib/test/ensure_llama_cpp.sh
  bash contrib/test/ensure_hf_model.sh
  exec bash contrib/test/run_llm_server.sh "$backend"

test-integration-all:
  python3 contrib/readme/run-badged-command.py integration bash -c "just test-integration-fd && just test-integration-tk"

# ── Test: Coverage ─────────────────────────────────────────────────────────

test-cov-fd:
  #!/usr/bin/env bash
  set -euo pipefail
  # No hugepage/sudo allocation — matches test-unit-fd (consumer hardware, no root).
  # Same LOCAL_MKS filter as test-unit-fd: only the 5 Tickoni libs.
  # Halve parallelism vs unit-test because llvm-cov inflates per-job RSS.
  jobs=$(( $(nproc) / 2 ))
  (( jobs < 1 )) && jobs=1
  {{make}} -j"${jobs}" MACHINE=tickoni_fd BUILDDIR=fd-cov \
    "LOCAL_MKS=$(find src/tango src/util src/ballet src/disco src/waltz -name Local.mk | grep -vE 'disco/quic/|ballet/zksdk/|waltz/quic/' | tr '\n' ' ')" \
    CC=clang-18 EXTRAS="llvm-cov" unit-test
  {{make}} -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR=fd-cov \
    CC=clang-18 EXTRAS="llvm-cov" run-unit-test TEST_OPTS="--page-sz normal"
  python3 contrib/readme/run-badged-command.py cov-fd bash contrib/test/coverage.sh coverage-fd

test-cov-tk:
  ZIG_GLOBAL_CACHE_DIR=.zig-global-cache python3 contrib/readme/run-badged-command.py cov-tk bash contrib/test/coverage.sh coverage-tk

test-cov-all:
  @just test-cov-fd
  @just test-cov-tk

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

# ── Quality: Proto ─────────────────────────────────────────────────────────

quality-proto-check-fd:
  bash -c "command -v buf >/dev/null || exit 0; buf lint src/disco/events/schema"

quality-proto-check-tk:
  bash -c "command -v buf >/dev/null || exit 0; buf lint src/tickoni/schema"

quality-proto-check-all:
  @just quality-proto-check-fd
  @just quality-proto-check-tk

# ── Quality: All ───────────────────────────────────────────────────────────

quality-check-all:
  python3 contrib/readme/run-badged-command.py quality bash -c "just quality-format-check-all && just quality-lint-check-all && just quality-proto-check-all"

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

security-engine-check-all:
     @just security-engine-check-changes
     @just security-engine-check-orchestration

security-engine-check-changes:
  python3 contrib/engine/engine_check_changes.py

security-engine-check-orchestration:
  python3 contrib/engine/linter.py contrib/engine/checks/ --root {{justfile_directory()}} --severity ERROR

# ── Security: All ──────────────────────────────────────────────────────────

security-check-all:
  python3 contrib/readme/run-badged-command.py security bash -c "just security-engine-check-all && just security-codeql-check-all && just security-gitleaks-check-all && just security-seccomp-check-all && just security-proof-check-all && just security-sanitize-check-all"

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
  just mem-drop-caches

mem-drop-caches:
  sync
  sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
  sudo sh -c 'echo 1 > /proc/sys/vm/compact_memory'

# ── Infra (harness) ─────────────────────────────────────────────────────

infra-check-model:
  bash contrib/test/ensure_hf_model.sh --check-only

infra-ensure-model:
  bash contrib/test/ensure_hf_model.sh

infra-check-llamacpp:
  bash contrib/test/ensure_llama_cpp.sh --check-only

infra-ensure-llamacpp:
  bash contrib/test/ensure_llama_cpp.sh

infra-run-llamacpp-cpu:
  bash contrib/test/run_llm_server.sh cpu

infra-run-llamacpp-gpu:
  bash contrib/test/run_llm_server.sh gpu
