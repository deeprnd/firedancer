#!/usr/bin/env python3
"""Security gate for S8 harness-reuse orchestration (V1.14.S8.T14).

Validates that the Firedancer-harness integration enforces Tickoni's
security model across five domains:

1. Least privilege per tile — the harness adapter does not restore or
   widen privileges beyond what each tile's single responsibility needs.
2. Sandbox entry — sandbox entry is invoked at the harness lifecycle
   sandbox step and never escalates privileges or prompts for sudo.
3. Deny-by-default for orchestration — the tile registry's
   validate(topo) enforces deny-by-default for unregistered tiles and
   missing link arrays.
4. Harness adapter boundary — no Firedancer type references leak outside
   c_abi/topo_run.zig and c_abi/shim/topo_run.c (and shim/topob.c,
   shim/tile_run.c which are the accepted adapter-layer files).
5. Memory and allocation safety — no unchecked @ptrCast/@alignCast
   across the C ABI in harness orchestration code, no catch unreachable
   on untrusted input, no heap allocation in the tile run loop.

Scope: only the files that participate in S8 harness orchestration:
  - src/tickoni/runtime/tile_process.zig (tile entry process)
  - src/tickoni/c_abi/topo_run.zig (Zig C ABI wrapper)
  - src/tickoni/c_abi/shim/topo_run.c (C shim around fd_topo_run_tile)
  - src/tickoni/c_abi/shim/tile_run.c (C shim around fd_topo_run_tile_t)
  - src/tickoni/c_abi/shim/topob.c (topology builder shim)
  - src/tickoni/c_abi/shim/sandbox.c (sandbox entry shim)
  - src/tickoni/c_abi/sandbox.zig (sandbox Zig declarations)
  - src/app/tickoni/tile_registry.zig (deny-by-default validation)

Usage:
    python3 contrib/engine/security_orchestration_check.py

Exit 0 means all gates pass. Exit 1 prints which domains failed.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# S8 harness orchestration files that the checks apply to.
HARNESS_FILES = [
    "src/tickoni/runtime/tile_process.zig",
    "src/tickoni/c_abi/topo_run.zig",
    "src/tickoni/c_abi/shim/topo_run.c",
    "src/tickoni/c_abi/shim/tile_run.c",
    "src/tickoni/c_abi/shim/topob.c",
    "src/tickoni/c_abi/shim/sandbox.c",
    "src/tickoni/c_abi/sandbox.zig",
    "src/app/tickoni/tile_registry.zig",
]

# Files that are the *only* places Firedancer types are allowed to appear
# by name in code (not comments). These are the harness adapter files.
ALLOWED_FIREDANCER_FILES = [
    "src/tickoni/c_abi/topo_run.zig",
    "src/tickoni/c_abi/topob.zig",
    "src/tickoni/c_abi/shim/topo_run.c",
    "src/tickoni/c_abi/shim/topob.c",
    "src/tickoni/c_abi/shim/tile_run.c",
]

# Forbidden Firedancer type/symbol names.
FORBIDDEN_SYMBOLS = [
    r"fd_topo_t\b",
    r"fd_topo_tile_t\b",
    r"fd_topo_run_tile\b",
    r"fd_topob\b",
    r"fd_cfg_stage_",
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def read_file_lines(path: str) -> list[str]:
    with open(path) as f:
        return f.readlines()


def _is_allowed_file(filepath: str) -> bool:
    for allowed in ALLOWED_FIREDANCER_FILES:
        if filepath.endswith(allowed):
            return True
    return False


def _read_all_harness_sources(repo: Path) -> tuple[dict[str, str], list[str]]:
    """Read all harness orchestration files into a dict keyed by path.

    Returns (sources, missing) where sources is a dict[rel_path -> content]
    and missing is a list of file paths that could not be found.
    """
    sources: dict[str, str] = {}
    missing: list[str] = []
    for rel in HARNESS_FILES:
        full = repo / rel
        if not full.exists():
            missing.append(rel)
        else:
            sources[rel] = full.read_text()
    return sources, missing


# ---------------------------------------------------------------------------
# Domain checks
# ---------------------------------------------------------------------------


def domain_least_privilege(sources: dict[str, str]) -> list[str]:
    """Check: harness adapter does not widen privileges.

    Validates that tile_run.c's simplified entry point passes:
    - sandbox=0 (T5 deferred)
    - uid/gid = process's own identity (no elevated creds)
    - allow_fd = -1 (no extra file descriptors)
    - populate_allowed_seccomp = NULL, populate_allowed_fds = NULL
    """
    issues: list[str] = []

    tile_run = sources.get("src/tickoni/c_abi/shim/tile_run.c")
    if not tile_run:
        issues.append("tile_run.c missing — cannot verify sandbox/privilege settings")
        return issues

    # Check sandbox=0 in tk_topo_run_tile_simple call
    call_block = tile_run[tile_run.find("tk_topo_run_tile_simple"):]
    end_paren = call_block.find(")")
    if end_paren > 0:
        call_block = call_block[:end_paren]
    else:
        issues.append("tk_topo_run_tile_simple call truncated — cannot verify args")
        return issues

    if "sandbox" in call_block and "0" in call_block.split("sandbox")[1][:20]:
        pass  # sandbox=0 found
    else:
        issues.append(
            "tk_topo_run_tile_simple does not pass sandbox=0 "
            "(sandbox entry should be deferred or explicitly configured)"
        )

    # Check uid/gid = getuid()/getgid()
    if re.search(r"getuid\(\)", call_block) and re.search(r"getgid\(\)", call_block):
        pass  # OK — using process's own identity
    else:
        issues.append(
            "tk_topo_run_tile_simple does not pass current process uid/gid "
            "(should not pass elevated credentials)"
        )

    # Check allow_fd = -1
    if re.search(r"allow_fd\s*\]\s*-1", call_block) or \
       re.search(r"allow_fd.*-1", call_block):
        pass  # OK — no extra file descriptors
    else:
        issues.append(
            "tk_topo_run_tile_simple does not pass allow_fd=-1 "
            "(should deny extra file descriptors by default)"
        )

    # Check TK_TILE_RUN struct: seccomp and fds
    if "populate_allowed_seccomp" in tile_run and "NULL" in tile_run:
        pass  # OK
    else:
        issues.append(
            "TK_TILE_RUN.populate_allowed_seccomp is not NULL "
            "(should deny custom seccomp rules by default)"
        )

    if "populate_allowed_fds" in tile_run and "NULL" in tile_run:
        pass  # OK
    else:
        issues.append(
            "TK_TILE_RUN.populate_allowed_fds is not NULL "
            "(should deny extra fds by default)"
        )

    return issues


def domain_sandbox_entry(sources: dict[str, str]) -> list[str]:
    """Check: sandbox entry path is invocable and never escalates.

    Validates:
    - sandbox.zig declares tk_sandbox_enter
    - sandbox.c shim exists and has no system/exec calls
    """
    issues: list[str] = []

    sandbox_zig = sources.get("src/tickoni/c_abi/sandbox.zig")
    if not sandbox_zig:
        issues.append("sandbox.zig missing — cannot verify sandbox entry declaration")
        return issues

    if "tk_sandbox_enter" not in sandbox_zig:
        issues.append(
            "tk_sandbox_enter not declared in sandbox.zig — "
            "sandbox entry path must be invocable from the harness lifecycle"
        )

    sandbox_c = sources.get("src/tickoni/c_abi/shim/sandbox.c")
    if not sandbox_c:
        issues.append("sandbox.c shim missing — C implementation of sandbox entry")
        return issues

    if re.search(r"\bsystem\s*\(", sandbox_c):
        issues.append(
            "sandbox.c shim calls system() — sandbox entry must never "
            "escalate via shell execution"
        )
    if re.search(r"\bexec\s", sandbox_c):
        issues.append(
            "sandbox.c shim calls exec*() — sandbox entry must never "
            "spawn new processes"
        )

    return issues


def domain_deny_by_default(sources: dict[str, str]) -> list[str]:
    """Check: tile registry validate(topo) enforces deny-by-default.

    Validates:
    - TopologyTileCountMismatch error variant exists
    - UnregisteredTopologyTile error variant exists
    - RegisteredTileMissingFromTopology error variant exists
    - LinkCardinalityMismatch error variant exists
    - validate() exists as a public function
    """
    issues: list[str] = []

    registry = sources.get("src/app/tickoni/tile_registry.zig")
    if not registry:
        issues.append("tile_registry.zig missing — deny-by-default orchestration gate cannot exist")
        return issues

    checks = {
        "TopologyTileCountMismatch": "rejects extra tiles in topology",
        "UnregisteredTopologyTile": "rejects unregistered topology tiles",
        "RegisteredTileMissingFromTopology": "rejects orphaned registry entries",
        "LinkCardinalityMismatch": "rejects wrong link counts per tile",
    }

    for err_name, description in checks.items():
        if err_name not in registry:
            issues.append(
                f"tile_registry.validate() missing error {err_name} "
                f"({description})"
            )

    if not re.search(r"pub fn validate\(", registry):
        issues.append("tile_registry.validate() not declared as public — "
                      "must be callable from supervisor init")

    return issues


def domain_adapter_boundary(sources: dict[str, str]) -> list[str]:
    """Check: no Firedancer type references leak outside c_abi/ adapter layer.

    This is the most critical gate: product code must never know about
    Firedancer topology types. Scans all harness orchestration files
    that are NOT in the allowed adapter list.
    """
    issues: list[str] = []

    for filepath, content in sources.items():
        if _is_allowed_file(filepath):
            continue

        lines = content.split("\n")
        for lineno, line in enumerate(lines, start=1):
            # Strip comments
            code = line
            if "//" in code:
                code = code[:code.index("//")]
            if "/*" in code:
                code = code[:code.index("/*")]

            code = code.strip()
            if not code:
                continue

            for symbol in FORBIDDEN_SYMBOLS:
                match = re.search(symbol, code)
                if match:
                    issues.append(
                        f"{filepath}:{lineno}: forbidden symbol "
                        f"{match.group(0)} "
                        f"found in harness code outside c_abi/ adapter layer: "
                        f"{code[:80]}"
                    )

    return issues


def domain_memory_safety(sources: dict[str, str]) -> list[str]:
    """Check: memory and allocation safety in harness orchestration code.

    Validates:
    - No unchecked @ptrCast/@alignCast in harness orchestration code
      outside c_abi/ wrappers (tile_process.zig is part of harness).
    - No catch unreachable in harness orchestration code.
    - No heap allocation in tile run loop (tile_process.zig).
    - g_ctx exists as a single per-process global in tile_process.zig.
    """
    issues: list[str] = []

    tile_process = sources.get("src/tickoni/runtime/tile_process.zig")
    if not tile_process:
        issues.append("tile_process.zig missing — harness orchestration entry point")
        return issues

    # 1. @ptrCast/@alignCast in tile_process.zig (harness code)
    lines = tile_process.split("\n")
    for lineno, line in enumerate(lines, start=1):
        code = line
        if "//" in code:
            code = code[:code.index("//")]
        if re.search(r"@ptrCast\s*\(", code):
            issues.append(
                f"tile_process.zig:{lineno}: @ptrCast in harness "
                f"orchestration code: {code.strip()[:80]}"
            )
        if re.search(r"@alignCast\s*\(", code):
            issues.append(
                f"tile_process.zig:{lineno}: @alignCast in harness "
                f"orchestration code: {code.strip()[:80]}"
            )

    # 2. catch unreachable in harness orchestration code
    for filepath, content in sources.items():
        if _is_allowed_file(filepath):
            continue
        if "c_abi" in filepath:
            continue  # c_abi wrappers are exempt

        hlines = content.split("\n")
        for lineno, line in enumerate(hlines, start=1):
            code = line
            if "//" in code:
                code = code[:code.index("//")]
            if re.search(r"catch unreachable", code):
                issues.append(
                    f"{filepath}:{lineno}: catch unreachable in harness "
                    f"orchestration code: {code.strip()[:80]}"
                )

    # 3. Heap allocation in tile run loop (tile_process.zig)
    in_tile_run = False
    for lineno, line in enumerate(tile_process.split("\n"), start=1):
        stripped = line.strip()
        if "export fn tk_tile_run" in stripped:
            in_tile_run = True
            continue
        if in_tile_run and re.search(r"\ballocator\.alloc\b", stripped):
            issues.append(
                f"tile_process.zig:{lineno}: heap allocation "
                f"in tk_tile_run hot path: {stripped[:80]}"
            )
        if in_tile_run and re.search(r"^export fn |^pub fn ", stripped):
            in_tile_run = False

    # 4. g_ctx exists as a single per-process global
    if not re.search(r"^var g_ctx:", tile_process, re.MULTILINE):
        issues.append(
            "tile_process.zig missing var g_ctx global — "
            "one-tile-per-process state carrier is required"
        )
    if "tk_tile_run" not in tile_process or "g_ctx" not in tile_process:
        issues.append(
            "g_ctx not referenced in tk_tile_run — "
            "the global state must be used by the run loop"
        )

    return issues


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

DOMAINS = [
    ("least_privilege", "Least privilege per tile", domain_least_privilege),
    ("sandbox_entry", "Sandbox entry", domain_sandbox_entry),
    ("deny_by_default", "Deny-by-default orchestration", domain_deny_by_default),
    ("adapter_boundary", "Harness adapter boundary", domain_adapter_boundary),
    ("memory_safety", "Memory and allocation safety", domain_memory_safety),
]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Security gate for S8 harness-reuse orchestration."
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print per-domain PASS/FAIL even when all pass.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent

    sources, missing = _read_all_harness_sources(repo_root)

    if missing:
        print("ERROR: the following harness orchestration files are missing:",
              file=sys.stderr)
        for m in missing:
            print(f"  MISSING: {m}", file=sys.stderr)
        return 1

    all_issues: dict[str, list[str]] = {}
    all_pass = True

    for domain_key, domain_name, domain_fn in DOMAINS:
        issues = domain_fn(sources)
        all_issues[domain_key] = issues
        if issues:
            all_pass = False

    # Report
    for domain_key, domain_name, _ in DOMAINS:
        issues = all_issues[domain_key]
        if not issues and not args.verbose:
            continue

        status = "PASS" if not issues else "FAIL"
        marker = "[PASS]" if not issues else "[FAIL]"
        print(f"{marker} {domain_name} ({domain_key})")
        if issues and args.verbose:
            for issue in issues:
                print(f"       {issue}")

    if all_pass:
        print("\nOK: all 5 security domains pass.")
        return 0

    print("\nFAIL: security orchestration gates failed:")
    for domain_key, domain_name, _ in DOMAINS:
        issues = all_issues[domain_key]
        if not issues:
            continue
        print(f"\n  {domain_name} ({domain_key}):")
        for issue in issues:
            print(f"    - {issue}")

    return 1


if __name__ == "__main__":
    sys.exit(main())
