#!/usr/bin/env python3
import argparse
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import urllib.request
from pathlib import Path

DEFAULT_REF = "master"
DEFAULT_URL_TEMPLATE = "https://codeberg.org/ziglang/zig-bootstrap/archive/{ref}.tar.gz"


def eprint(*args):
    print(*args, file=sys.stderr)


def run(cmd, *, cwd=None, dry_run=False, env=None):
    printable = " ".join(str(x) for x in cmd)
    print(f"[run] {printable}")
    if dry_run:
        return
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def detect_windows_native_machine():
    arch_map = {
        "ARM64": "arm64",
        "AMD64": "x86_64",
        "X86": "x86",
    }
    try:
        result = subprocess.run(
            [
                "powershell.exe",
                "-NoProfile",
                "-Command",
                "(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Architecture)",
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        code = result.stdout.strip()
        mapped = {
            "0": "x86",
            "9": "x86_64",
            "12": "arm64",
        }.get(code)
        if mapped:
            return mapped
    except Exception:
        pass
    wow64 = os.environ.get("PROCESSOR_ARCHITEW6432")
    if wow64:
        return arch_map.get(wow64.upper(), wow64.lower())
    proc_arch = os.environ.get("PROCESSOR_ARCHITECTURE")
    if proc_arch:
        mapped = arch_map.get(proc_arch.upper())
        if mapped:
            return mapped
    return None


def detect_target(system_name=None, machine_name=None):
    system_name = (system_name or platform.system()).lower()
    if system_name == "windows":
        machine_name = detect_windows_native_machine() or machine_name or platform.machine()
    else:
        machine_name = machine_name or platform.machine()
    machine_name = machine_name.lower()

    arch_map = {
        "x86_64": "x86_64",
        "amd64": "x86_64",
        "arm64": "aarch64",
        "aarch64": "aarch64",
        "x86": "x86",
        "i386": "x86",
        "i686": "x86",
    }
    arch = arch_map.get(machine_name)
    if arch is None:
        raise SystemExit(f"unsupported architecture for zig-bootstrap target inference: {machine_name}")

    if system_name == "windows":
        return f"{arch}-windows-gnu"
    if system_name == "darwin":
        return f"{arch}-macos-none"
    if system_name == "linux":
        libc = "musl"
        return f"{arch}-linux-{libc}"
    raise SystemExit(f"unsupported operating system for zig-bootstrap target inference: {system_name}")


def default_install_root():
    if os.name == "nt":
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise SystemExit("LOCALAPPDATA is not set")
        return Path(local) / "Programs" / "zig-bootstrap"
    return Path.home() / ".local" / "zig-bootstrap"


def default_cache_root():
    if os.name == "nt":
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise SystemExit("LOCALAPPDATA is not set")
        return Path(local) / "cache" / "zig-bootstrap"
    xdg = os.environ.get("XDG_CACHE_HOME")
    if xdg:
        return Path(xdg) / "zig-bootstrap"
    return Path.home() / ".cache" / "zig-bootstrap"


def bootstrap_archive_url(ref, url_template):
    return url_template.format(ref=ref)


def download_archive(url, dest, dry_run=False):
    print(f"[download] {url} -> {dest}")
    if dry_run:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response, open(dest, "wb") as out:
        shutil.copyfileobj(response, out)


def extract_archive(archive_path, dest_dir, dry_run=False):
    print(f"[extract] {archive_path} -> {dest_dir}")
    if dry_run:
        return
    if dest_dir.exists():
        shutil.rmtree(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "r:gz") as tf:
        tf.extractall(dest_dir)


def resolve_source_dir(extract_root):
    children = [p for p in extract_root.iterdir() if p.is_dir()]
    if len(children) != 1:
        raise SystemExit(f"expected exactly one extracted zig-bootstrap directory in {extract_root}, found {len(children)}")
    return children[0]


def detect_vsdevcmd():
    candidates = []
    program_files_x86 = os.environ.get("ProgramFiles(x86)")
    if program_files_x86:
        candidates.append(Path(program_files_x86) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe")
    for candidate in candidates:
        if candidate.exists():
            result = subprocess.run(
                [str(candidate), "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            install_path = result.stdout.strip()
            if install_path:
                vsdevcmd = Path(install_path) / "Common7" / "Tools" / "VsDevCmd.bat"
                if vsdevcmd.exists():
                    return vsdevcmd
    fallback_candidates = [
        Path(r"C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat"),
        Path(r"C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat"),
        Path(r"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"),
        Path(r"C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"),
    ]
    for candidate in fallback_candidates:
        if candidate.exists():
            return candidate
    raise SystemExit("could not locate VsDevCmd.bat required by zig-bootstrap build.bat")


def build_zig_bootstrap(source_dir, target, mcpu, dry_run=False):
    if os.name == "nt":
        vsdevcmd = detect_vsdevcmd()
        cmdline = f'call "{vsdevcmd}" -arch=amd64 -host_arch=amd64 && build.bat {target} {mcpu}'
        run(["cmd.exe", "/d", "/s", "/c", cmdline], cwd=source_dir, dry_run=dry_run)
    else:
        run(["bash", "build", target, mcpu], cwd=source_dir, dry_run=dry_run)


def copy_tree(src, dst, dry_run=False):
    print(f"[install] {src} -> {dst}")
    if dry_run:
        return
    if dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst)


def add_to_github_path(path_value, dry_run=False):
    github_path = os.environ.get("GITHUB_PATH")
    if not github_path:
        return
    print(f"[github-path] {path_value}")
    if dry_run:
        return
    with open(github_path, "a", encoding="utf-8") as fh:
        fh.write(str(path_value) + os.linesep)


def update_windows_user_path(path_value, dry_run=False):
    if os.name != "nt":
        raise SystemExit("--user-path is currently supported on Windows only")
    current = os.environ.get("PATH", "")
    print(f"[user-path] prepend {path_value}")
    if dry_run:
        return
    ps = textwrap.dedent(
        f"""
        $zigDir = '{str(path_value)}'
        $current = [Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = @()
        if ($current) {{
          $parts = $current -split ';' | Where-Object {{ $_ -and ($_ -ne $zigDir) }}
        }}
        $new = ($zigDir + ';' + ($parts -join ';')).TrimEnd(';')
        [Environment]::SetEnvironmentVariable('Path', $new, 'User')
        """
    ).strip()
    subprocess.run(["powershell.exe", "-NoProfile", "-Command", ps], check=True)


def print_posix_activation(path_value):
    print("[activation] add Zig to your shell PATH with:")
    print(f'  export PATH="{path_value}:$PATH"')


def main():
    parser = argparse.ArgumentParser(description="Install Zig via the official zig-bootstrap project for local development or CI.")
    parser.add_argument("--bootstrap-ref", default=DEFAULT_REF, help="zig-bootstrap git ref or tag to download (default: master)")
    parser.add_argument("--bootstrap-url-template", default=DEFAULT_URL_TEMPLATE, help="archive URL template with {ref} placeholder")
    parser.add_argument("--target", help="zig-bootstrap target triple (default: inferred from host)")
    parser.add_argument("--mcpu", default="baseline", help="zig-bootstrap mcpu argument (default: baseline)")
    parser.add_argument("--install-root", type=Path, default=default_install_root(), help="root directory that will receive zig-<target>-<mcpu>")
    parser.add_argument("--cache-root", type=Path, default=default_cache_root(), help="cache/work directory for zig-bootstrap source and archives")
    parser.add_argument("--user-path", action="store_true", help="persist the installed Zig directory to the Windows user PATH")
    parser.add_argument("--dry-run", action="store_true", help="print the plan without downloading, building, or editing PATH")
    args = parser.parse_args()

    target = args.target or detect_target()
    archive_url = bootstrap_archive_url(args.bootstrap_ref, args.bootstrap_url_template)
    archive_dir = args.cache_root / "archives"
    archive_name = f"zig-bootstrap-{args.bootstrap_ref}.tar.gz"
    archive_path = archive_dir / archive_name
    extract_root = args.cache_root / "src" / f"zig-bootstrap-{args.bootstrap_ref}"

    download_archive(archive_url, archive_path, dry_run=args.dry_run)
    extract_archive(archive_path, extract_root, dry_run=args.dry_run)

    if args.dry_run:
        source_dir = extract_root / f"zig-bootstrap-{args.bootstrap_ref}"
    else:
        source_dir = resolve_source_dir(extract_root)

    build_zig_bootstrap(source_dir, target, args.mcpu, dry_run=args.dry_run)

    output_dir = source_dir / "out" / f"zig-{target}-{args.mcpu}"
    install_dir = args.install_root / args.bootstrap_ref / output_dir.name
    copy_tree(output_dir, install_dir, dry_run=args.dry_run)

    add_to_github_path(install_dir, dry_run=args.dry_run)

    if args.user_path:
        update_windows_user_path(install_dir, dry_run=args.dry_run)
    elif os.name != "nt" and not os.environ.get("GITHUB_PATH"):
        print_posix_activation(install_dir)

    print(f"[done] zig-bootstrap ref={args.bootstrap_ref} target={target} mcpu={args.mcpu} install_dir={install_dir}")


if __name__ == "__main__":
    main()
