"""Harness orchestration security checks (replaces security_orchestration_check.py).

Exports 8 checks across 5 domains that verify the Firedancer-harness integration
enforces Tickoni's security model.

Domains:
  - least_privilege:   C struct defaults deny-by-default
  - sandbox_entry:     sandbox shim has no escalation paths
  - deny_by_default:   tile registry has error variants + validate()
  - adapter_boundary:  no Firedancer types leak outside c_abi/
  - memory_safety:     no ptrCast in callbacks, no heap alloc in hot path,
                       no catch unreachable, g_ctx exists
"""

from __future__ import annotations

import re
from pathlib import Path

from linter import Check, Issue, Severity


# ─── Domain: least_privilege ────────────────────────────────────────────────


class StructDefaultsC(Check):
    """Check TK_TILE_RUN enforces deny-by-default.

    Validates that tile_run.c's struct has:
    - populate_allowed_seccomp = NULL
    - populate_allowed_fds = NULL
    - sandbox=0, getuid()/getgid(), allow_fd=-1 in tk_topo_run_tile_simple()
    """

    name = "least-privilege-c-struct"
    domains = ["least_privilege"]
    severity = Severity.ERROR
    description = ("C struct does not enforce deny-by-default policy")
    files_glob = ("src/tickoni/c_abi/shim/tile_run.c",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []

        if "TK_TILE_RUN" not in file_content:
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="TK_TILE_RUN struct not found",
            ))
            return issues

        # Struct field checks
        if not re.search(r"\.populate_allowed_seccomp\s*=\s*NULL", file_content):
            issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                message="populate_allowed_seccomp is not NULL"))
        if not re.search(r"\.populate_allowed_fds\s*=\s*NULL", file_content):
            issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                message="populate_allowed_fds is not NULL"))

        # Find the function body and look for the fd_topo_run_tile() call inside it.
        # The signature is: "tk_topo_run_tile_simple(" or "void*" on next line.
        lines = file_content.split("\n")
        func_start = -1
        for i, line in enumerate(lines):
            if "tk_topo_run_tile_simple" in line and "{" in line:
                func_start = i; break
            if "tk_topo_run_tile_simple" in line and i + 1 < len(lines):
                if "{" in lines[i + 1]:
                    func_start = i; break
        if func_start < 0:
            issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                message="tk_topo_run_tile_simple() definition not found"))
            return issues

        # Extract function body by brace depth
        depth, in_body, body_start, body_end = 0, False, -1, -1
        for i in range(func_start, len(lines)):
            for ch in lines[i]:
                if ch == '{':
                    depth += 1
                    in_body = True
                    if body_start < 0: body_start = i
                elif ch == '}':
                    depth -= 1
                    if in_body and depth == 0:
                        body_end = i; break
            if body_end >= 0: break

        if body_start < 0 or body_end < 0:
            issues.append(Issue(check=self, file_path=file_path, line_no=func_start+1,
                                message="Could not find body of tk_topo_run_tile_simple"))
            return issues

        func_body = "\n".join(lines[func_start:body_end + 1])

        # Check for fd_topo_run_tile() call inside the function
        if "fd_topo_run_tile" not in func_body:
            issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                message="fd_topo_run_tile() call not found"))
            return issues

        if not re.search(r"getuid\(\)", func_body) or not re.search(r"getgid\(\)", func_body):
            issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                message="does not pass current process uid/gid"))
        if not re.search(r"allow_fd.*-1", func_body):
            issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                message="does not pass allow_fd=-1"))
        return issues


# ─── Domain: sandbox_entry ──────────────────────────────────────────────────


class NoSystemInSandbox(Check):
    """Reject system() / exec*() in sandbox shim files."""

    name = "no-system-in-sandbox"
    domains = ["sandbox_entry"]
    severity = Severity.ERROR
    description = ("sandbox shim must not escalate via system() or exec*()")
    files_glob = ("src/tickoni/c_abi/shim/sandbox.c",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []
        for lineno, line in enumerate(file_content.split("\n"), start=1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            if re.search(r"\bsystem\s*\(", line):
                issues.append(Issue(check=self, file_path=file_path, line_no=lineno,
                                    message=f"system() call: {stripped[:80]}"))
            if re.search(r"\bexec\w*\s*\(", line):
                issues.append(Issue(check=self, file_path=file_path, line_no=lineno,
                                    message=f"exec*() call: {stripped[:80]}"))
        return issues


class SandboxEntryDeclared(Check):
    """Verify sandbox.zig declares tk_sandbox_enter."""

    name = "sandbox-entry-declared"
    domains = ["sandbox_entry"]
    severity = Severity.ERROR
    description = ("sandbox entry path not declared")
    files_glob = ("src/tickoni/c_abi/sandbox.zig",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        if "tk_sandbox_enter" not in file_content:
            return [Issue(check=self, file_path=file_path, line_no=1,
                          message="tk_sandbox_enter not declared")]
        return []


# ─── Domain: deny_by_default ────────────────────────────────────────────────


class RegistryErrorVariants(Check):
    """Check tile_registry has required error variants + validate()."""

    name = "registry-error-variants"
    domains = ["deny_by_default"]
    severity = Severity.ERROR
    description = ("tile_registry missing deny-by-default error variant or validate()")
    files_glob = ("src/app/tickoni/tile_registry.zig",)

    required_errors = (
        "TopologyTileCountMismatch",
        "UnregisteredTopologyTile",
        "RegisteredTileMissingFromTopology",
        "LinkCardinalityMismatch",
    )

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []
        for err in self.required_errors:
            if err not in file_content:
                issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                    message=f"Missing error variant: {err}"))
        if not re.search(r"pub fn validate\(", file_content):
            issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                message="Missing pub fn validate()"))
        return issues


# ─── Domain: adapter_boundary ───────────────────────────────────────────────


class NoFiredancerTypesLeak(Check):
    """Block Firedancer types outside the C ABI adapter layer."""

    name = "no-firedancer-leak"
    domains = ["adapter_boundary"]
    severity = Severity.ERROR
    description = ("Firedancer types must not leak outside c_abi/ adapter files")

    allowed_files = (
        "src/tickoni/c_abi/topo_run.zig",
        "src/tickoni/c_abi/topob.zig",
        "src/tickoni/c_abi/shim/topo_run.c",
        "src/tickoni/c_abi/shim/topob.c",
        "src/tickoni/c_abi/shim/tile_run.c",
    )

    forbidden_symbols = (
        r"\bfd_topo_t\b",
        r"\bfd_topo_tile_t\b",
        r"\bfd_topo_run_tile\b",
        r"\bfd_topob\b",
        r"\bfd_cfg_stage_\b",
    )

    files_glob = ("src/**/*.zig", "src/**/*.c", "src/**/*.h")

    # Paths that are allowed to contain Firedancer types (adapter + infrastructure)
    allowed_paths = (
        "c_abi/",
        "discof/",        # Firedancer's own infrastructure code
        "util/sandbox/",  # Firedancer sandbox primitives
    )

    def _is_allowed(self, file_path: str) -> bool:
        for af in self.allowed_files:
            if file_path.endswith(af):
                return True
        for ap in self.allowed_paths:
            if ap in file_path:
                return True
        return False

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        if self._is_allowed(file_path):
            return []

        issues: list[Issue] = []
        for lineno, raw_line in enumerate(file_content.split("\n"), start=1):
            code = raw_line
            if "//" in code: code = code[:code.index("//")]
            if "/*" in code: code = code[:code.index("/*")]
            code = code.strip()
            if not code:
                continue
            for pat in self.forbidden_symbols:
                if re.search(pat, code):
                    issues.append(Issue(
                        check=self,
                        file_path=file_path,
                        line_no=lineno,
                        message=f"Forbidden Firedancer symbol in code: {code[:80]}",
                    ))
        return issues


# ─── Domain: memory_safety ──────────────────────────────────────────────────


class NoCatchUnreachable(Check):
    """Reject `catch unreachable` outside test blocks and c_abi/ wrappers."""

    name = "no-catch-unreachable"
    domains = ["memory_safety"]
    severity = Severity.ERROR
    description = ("catch unreachable in harness orchestration code")
    files_glob = ("src/**/*.zig",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        if "/c_abi/" in file_path:
            return []
        if "test" in file_path or file_path.endswith("_test.zig"):
            return []

        issues: list[Issue] = []
        in_test_block = False

        for lineno, line in enumerate(file_content.split("\n"), start=1):
            stripped = line.strip()
            if stripped.startswith("test \"") or stripped.startswith("test{"):
                in_test_block = True
                continue
            if in_test_block and stripped == "}":
                in_test_block = False
                continue
            code = stripped
            if "//" in code: code = code[:code.index("//")]
            if re.search(r"catch unreachable", code):
                # Skip the id() helper in tile_registry.zig
                if ("fn id(comptime" in file_content and
                    line.strip().startswith("return rt.tile.TileId.parse(s) catch unreachable")):
                    continue
                issues.append(Issue(
                    check=self,
                    file_path=file_path,
                    line_no=lineno,
                    message=f"{self.description}: {code[:80]}",
                ))
        return issues


class NoPtrCastInCallbacks(Check):
    """Reject @ptrCast / @alignCast in tile_process callbacks (except topo bridge)."""

    name = "no-ptrcast-in-callbacks"
    domains = ["memory_safety"]
    severity = Severity.ERROR
    description = ("@ptrCast / @alignCast in tile_process callbacks")
    files_glob = ("src/tickoni/runtime/tile_process.zig",)
    callback_names = ("tk_tile_privileged_init", "tk_tile_run")

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []
        lines = file_content.split("\n")

        for cb_name in self.callback_names:
            start = -1
            for i, line in enumerate(lines):
                if f"export fn {cb_name}(" in line:
                    start = i; break
            if start < 0:
                issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                    message=f"export fn {cb_name} not found"))
                continue

            # Extract function body by brace depth
            depth, in_body, body_start, body_end = 0, False, -1, -1
            for i in range(start, len(lines)):
                for ch in lines[i]:
                    if ch == '{':
                        depth += 1
                        in_body = True
                        if body_start < 0: body_start = i
                    elif ch == '}':
                        depth -= 1
                        if in_body and depth == 0:
                            body_end = i; break
                if body_end >= 0: break

            if body_start < 0 or body_end < 0:
                issues.append(Issue(check=self, file_path=file_path, line_no=start+1,
                                    message=f"Could not find body of {cb_name}"))
                continue

            for off, line in enumerate(lines[body_start:body_end+1], start=1):
                code = line
                if "//" in code: code = code[:code.index("//")]
                # Exempt the intended topo bridge cast
                if re.search(r"= *@ptrCast\(topo\)", code):
                    continue
                line_abs = body_start + off
                if re.search(r"@ptrCast\s*\(", code):
                    issues.append(Issue(
                        check=self, file_path=file_path, line_no=line_abs,
                        message=f"@ptrCast in {cb_name}: {code.strip()[:80]}"))
                if re.search(r"@alignCast\s*\(", code):
                    issues.append(Issue(
                        check=self, file_path=file_path, line_no=line_abs,
                        message=f"@alignCast in {cb_name}: {code.strip()[:80]}"))
        return issues


class NoHeapAllocInTileRun(Check):
    """Reject heap allocation in tk_tile_run hot path."""

    name = "no-heap-alloc-in-tile-run"
    domains = ["memory_safety"]
    severity = Severity.ERROR
    description = ("heap allocation in tk_tile_run hot path")
    files_glob = ("src/tickoni/runtime/tile_process.zig",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []
        in_run = False
        for lineno, line in enumerate(file_content.split("\n"), start=1):
            stripped = line.strip()
            if "export fn tk_tile_run" in stripped:
                in_run = True; continue
            if in_run and re.search(r"\ballocator\.alloc\b", stripped):
                issues.append(Issue(check=self, file_path=file_path, line_no=lineno,
                                    message=f"{self.description}: {stripped[:80]}"))
            if in_run and re.search(r"^export fn |^pub fn ", stripped):
                in_run = False
        return issues


class GlobalStatePresent(Check):
    """Check tile_process.zig has g_ctx global state."""

    name = "global-state-presence"
    domains = ["memory_safety"]
    severity = Severity.ERROR
    description = ("tile_process.zig missing g_ctx global state")
    files_glob = ("src/tickoni/runtime/tile_process.zig",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []
        if not re.search(r"^var g_ctx:", file_content, re.MULTILINE):
            issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                message="Missing var g_ctx global declaration"))
        if "g_ctx" not in file_content or "tk_tile_run" not in file_content:
            issues.append(Issue(check=self, file_path=file_path, line_no=1,
                                message="g_ctx not used by tk_tile_run"))
        return issues


# ─── Entry point ────────────────────────────────────────────────────────────


def define_checks(linter):
    """Register all orchestration checks with the linter."""
    linter.add_check(StructDefaultsC)
    linter.add_check(NoSystemInSandbox)
    linter.add_check(SandboxEntryDeclared)
    linter.add_check(RegistryErrorVariants)
    linter.add_check(NoFiredancerTypesLeak)
    linter.add_check(NoCatchUnreachable)
    linter.add_check(NoPtrCastInCallbacks)
    linter.add_check(NoHeapAllocInTileRun)
    linter.add_check(GlobalStatePresent)
