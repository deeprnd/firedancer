# CI

This document describes the GitHub Actions CI workflows for Tickoni.

---

## Contents

- [Overview](#overview)
- [Workflow Summary](#workflow-summary)
- [Change Detection](#change-detection)
- [Build](#build)
- [Quality](#quality)
- [Security](#security)
- [Tests / Short](#tests--short)
- [Tests / Long](#tests--long)
- [Tests / XLong](#tests--xlong)
- [Integration Tests: Secrets](#integration-tests-secrets)
- [Upstream Firedancer Workflows](#upstream-firedancer-workflows)

---

## Overview

All six Tickoni workflows trigger on pull requests targeting `main` and are also dispatchable manually via `workflow_dispatch`. Every workflow uses GitHub-hosted runners only — no self-hosted infrastructure is required.

Upstream Firedancer workflows co-exist in `.github/workflows/` and are described in [Upstream Firedancer Workflows](#upstream-firedancer-workflows).

---

## Workflow Summary

| Workflow                              | Runner(s)                           | Jobs                                                         | Timeout |
| ------------------------------------- | ----------------------------------- | ------------------------------------------------------------ | ------- |
| `.github/workflows/build.yml`         | `ubuntu-24.04`, `ubuntu-24.04-arm`  | Engine Build (GCC, Clang, ARM), Harness Build                | 20–30 m |
| `.github/workflows/quality.yml`       | `ubuntu-24.04`                      | Format Check, Lint Check                                     | 20–30 m |
| `.github/workflows/security.yml`      | `ubuntu-24.04`                      | Gitleaks, Sanitizers                                         | 20–45 m |
| `.github/workflows/tests-short.yml`   | `ubuntu-24.04`                      | Harness Unit Tests, Harness Integration Tests, Harness Coverage | 20 m    |
| `.github/workflows/tests-long.yml`    | `ubuntu-24.04`                      | Engine Unit Tests, Engine Coverage                           | 45–90 m |
| `.github/workflows/tests-xlong.yml`   | `ubuntu-latest`                     | Engine E2E Tests (disabled), LLM System Tests                | 60–90 m |

All `detect-changes` jobs run on `ubuntu-slim`.

---

## Change Detection

Each workflow begins with a `detect-changes` job that compares the PR diff against a path regex. Subsequent jobs run only if at least one matching path changed. Manual `workflow_dispatch` runs always proceed regardless of path matches.

| Workflow          | Paths that trigger jobs                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------------------- |
| `build.yml`       | `src/`, `config/`, `deps.sh`, `contrib/deps-bundle.sh`, `justfile`, `.github/actions/`, workflow file   |
| `quality.yml`     | `src/`, `build.zig`, `build.zig.zon`, `justfile`, `contrib/quality.sh`, lint script, `.github/actions/`, workflow file |
| `security.yml`    | `src/`, `build.zig`, `build.zig.zon`, `justfile`, `contrib/security.sh`, gitleaks config, CodeQL config, `.github/actions/`, workflow file |
| `tests-short.yml` | `src/app/tickoni/`, `src/tickoni/`, `build.zig`, `build.zig.zon`, `justfile`, quality/security scripts, coverage configs, `.github/actions/`, workflow file |
| `tests-long.yml`  | `src/`, `build.zig`, `build.zig.zon`, `justfile`, `contrib/test/`, `contrib/make-j`, coverage report script, `.github/actions/`, workflow file |
| `tests-xlong.yml` | `src/`, `build.zig`, `build.zig.zon`, `justfile`, `contrib/test/`, `contrib/make-j`, `.github/actions/`, workflow file |

---

## Build

**File:** `.github/workflows/build.yml`

Compiles the Firedancer engine and the Tickoni Zig harness. Four parallel build jobs run after `detect-changes`:

| Job                      | Runner             | Compiler        | Command              |
| ------------------------ | ------------------ | --------------- | -------------------- |
| Engine Build / GCC       | `ubuntu-24.04`     | GCC 12          | `just build-fd-gcc`  |
| Engine Build / Clang     | `ubuntu-24.04`     | Clang 18        | `just build-fd-clang`|
| Engine Build / ARM       | `ubuntu-24.04-arm` | GCC 14          | `just build-fd-arm`  |
| Harness Build            | `ubuntu-24.04`     | Zig (toolchain) | `just build-tk`      |

The ARM job uses the `ubuntu-24.04-arm` GitHub-hosted runner to catch architecture-specific issues without a self-hosted machine.

---

## Quality

**File:** `.github/workflows/quality.yml`

Static quality checks run as a matrix so they report independently and do not fail-fast:

| Job           | Command                        | What it checks                              |
| ------------- | ------------------------------ | ------------------------------------------- |
| Format Check  | `just quality-format-check-all`| `zig fmt`, C formatting, whitespace rules   |
| Lint Check    | `just quality-lint-check-all`  | include guards, shellcheck, pre-commit hooks|

Both jobs build the shared Firedancer/Tickoni library set via `.github/actions/build-fd-tk-libs` before running checks. The `detect-changes` step creates a local `main` branch so diff-based quality scripts have a comparison ref.

---

## Security

**File:** `.github/workflows/security.yml`

Security checks run as a matrix with independent reporting:

| Job        | Compiler | Command                           | What it checks                          |
| ---------- | -------- | --------------------------------- | --------------------------------------- |
| Gitleaks   | GCC      | `just security-gitleaks-check-all`| Secret scanning via gitleaks            |
| Sanitizers | Clang 18 | `just security-sanitize-check-all`| ASan/UBSan on Firedancer and Tickoni C/Zig code |

The Sanitizers job installs Clang 18, builds shared libs, then runs `just security-sanitize-check-all`.

---

## Tests / Short

**File:** `.github/workflows/tests-short.yml`

Covers the Tickoni Zig harness (`src/app/tickoni/`, `src/tickoni/`). Path filter is scoped to Tickoni sources only so these jobs do not re-run on pure Firedancer C changes.

| Job                       | Command                    | Output artifact                               |
| ------------------------- | -------------------------- | --------------------------------------------- |
| Harness Unit Tests        | `just test-unit-tk`        | —                                             |
| Harness Integration Tests | `just test-integration-tk` | —                                             |
| Harness Tests Coverage    | `just test-cov-tk`         | `coverage-tk` — `build/coverage/tk/coverage-summary.json` |

Coverage artifact is uploaded even on failure (`if: always()`).

---

## Tests / Long

**File:** `.github/workflows/tests-long.yml`

Covers the Firedancer engine test suite and produces engine coverage using LLVM tooling.

| Job                   | Compiler | Command             | Timeout | Output artifact                               |
| --------------------- | -------- | ------------------- | ------- | --------------------------------------------- |
| Engine Unit Tests     | GCC      | `just test-unit-fd` | 45 m    | —                                             |
| Engine Tests Coverage | Clang 18 | `just test-cov-fd`  | 90 m    | `coverage-fd` — `build/coverage/fd/coverage-summary.json` |

The coverage job installs `llvm-18` and sets up `llvm-profdata`, `llvm-objdump`, `llvm-ar`, and `llvm-cov` via `update-alternatives` before running.

---

## Tests / XLong

**File:** `.github/workflows/tests-xlong.yml`

Contains long-running tests that require additional infrastructure or model assets.

| Job              | Runner          | Command              | Timeout | Status                     |
| ---------------- | --------------- | -------------------- | ------- | -------------------------- |
| Engine E2E Tests | `ubuntu-24.04`  | `just test-e2e-fd`   | 60 m    | **Disabled** (`if: false`) |
| LLM System Tests | `ubuntu-latest` | see steps below      | 90 m    | Active                     |

**Engine E2E Tests** — condition is hard-coded `if: false && …`, so it never runs. Remove `false &&` to re-enable. When enabled it configures pages via the Tickoni-owned `.github/actions/memory-management` action (not the upstream `.github/actions/hugepages` action). The `memory-management` action wraps the `just mem-*` recipes and degrades gracefully when a free GitHub-hosted runner cannot reserve all requested gigantic/huge pages, whereas upstream `hugepages` targets persistent self-hosted runners and fails the step on a short reservation. Keeping a separate action lets the shared `hugepages` file track Firedancer upstream without merge conflicts.

**LLM System Tests** — runs the explicit live-model compatibility lane against a real local `llama.cpp` server. Steps in order:

1. Install `cmake`, `libopenblas-dev`, `libopenblas64-dev` via apt.
2. `just infra-ensure-llamacpp` — clones `https://github.com/ggml-org/llama.cpp` into `~/work/git/llama.cpp` (if absent), builds for CPU with OpenBLAS via cmake, and copies `llama-*` binaries to the clone root.
3. `just infra-ensure-model` — downloads the GGUF model via the `hf` CLI (Hugging Face Hub) if not already present.
4. `just test-system-tk` — ensures llama.cpp and model are present, starts the server, runs `zig build integration-test-live-model`, and stops the server.

The llama.cpp path and model path can be overridden with `TK_LLAMA_CPP_DIR`, `TK_HF_MODEL_DIR`, and `TK_HF_MODEL_FILE` environment variables (see `contrib/test/ensure_llama_cpp.sh` and `contrib/test/ensure_hf_model.sh`).

---

## LLM System Tests: Secrets

The LLM System Tests job uses `HF_TOKEN` to authenticate with Hugging Face when downloading the model. Public models (e.g. unsloth repos) do not strictly require a token, but setting one avoids rate-limiting and allows access to gated models.

To configure it: **GitHub → Repository → Settings → Secrets and variables → Actions → New repository secret**, name `HF_TOKEN`, value: a Hugging Face access token with at least read scope.

The job passes the secret as `env: HF_TOKEN: ${{ secrets.HF_TOKEN }}`. If the secret is absent the `hf` CLI falls back to unauthenticated access; the job will still pass for public models but may hit rate limits on busy runners.

---

## Upstream Firedancer Workflows

The repository also contains upstream Firedancer CI workflows (e.g. `on_pull_request.yml`, `cbmc.yml`, `check_seccomp.yml`, `trailing_whitespace.yml`, `builds.yml`, and others). Every job in these workflows is guarded by:

```yaml
if: ${{ vars.SKIP_FIREDANCER_CI != 'true' }}
```

With `SKIP_FIREDANCER_CI = true` set as a GitHub Actions repository variable, all upstream jobs are skipped on every event. They appear in the Actions UI with status **Skipped** rather than being absent.

To inspect or change this variable: **GitHub → Repository → Settings → Actions → Variables**.

These workflows are retained as-is to avoid unnecessary conflicts when merging from upstream Firedancer while Tickoni's own CI surface remains narrower. Do not remove or rewrite them as part of ordinary Tickoni changes unless the task is explicitly about that migration.

Note: CodeQL `justfile` recipes are currently no-ops as documented in [Security](./security.md). Do not silently add new CodeQL pull request hooks.
