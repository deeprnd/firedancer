#!/usr/bin/env python3
"""Run a shell command and update the named README.md badge with the result."""

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent
LOCK_PATH = REPO_ROOT / "README.md.lock"
LOCK_POLL_S = 0.05
LOCK_TIMEOUT_S = 30

import importlib.util as _ilu

_spec = _ilu.spec_from_file_location("refresh_badges", SCRIPT_DIR / "refresh-badges.py")
_mod = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
update_readme_badge = _mod.update_readme_badge
update_readme_badge_unknown = _mod.update_readme_badge_unknown


def is_process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def acquire_lock() -> None:
    deadline = time.monotonic() + LOCK_TIMEOUT_S
    while time.monotonic() < deadline:
        try:
            fd = os.open(str(LOCK_PATH), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return
        except FileExistsError:
            try:
                owner = int(LOCK_PATH.read_text(encoding="utf-8").strip())
                if not is_process_alive(owner):
                    LOCK_PATH.unlink(missing_ok=True)
                    continue
            except (ValueError, OSError):
                pass  # lock disappeared between checks — retry
        time.sleep(LOCK_POLL_S)
    raise TimeoutError(f"Timed out waiting for README lock after {LOCK_TIMEOUT_S}s")


def release_lock() -> None:
    LOCK_PATH.unlink(missing_ok=True)


def run_shell_command(command: str) -> int:
    shell = os.environ.get("SHELL", "bash")
    result = subprocess.run([shell, "-c", command])
    return result.returncode


def update_badge_with_lock(update_fn, badge_name: str, *args) -> int:
    status = 0
    acquire_lock()
    try:
        update_fn(badge_name, *args)
    except Exception as e:
        print(str(e), file=sys.stderr)
        status = 1
    finally:
        release_lock()
    return status


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 2:
        print("Usage: run-badged-command.py <badge-name> <command>", file=sys.stderr)
        sys.exit(1)

    badge_name = args[0]
    command = " ".join(args[1:])

    def _cleanup(signum, frame):
        release_lock()
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, _cleanup)

    badge_status = update_badge_with_lock(update_readme_badge_unknown, badge_name)
    command_status = run_shell_command(command)
    badge_status |= update_badge_with_lock(update_readme_badge, badge_name, command_status)

    sys.exit(command_status if command_status != 0 else badge_status)


if __name__ == "__main__":
    main()
