#!/usr/bin/env python3
"""Update README.md badge image tags between marker comments."""

import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent
README_PATH = REPO_ROOT / "README.md"

SHIELDS_BASE_URL = "https://img.shields.io/badge"
SHIELDS_STYLE = "flat-square"

BOOLEAN_SUCCESS = ("passing", "brightgreen")
BOOLEAN_FAILURE = ("failing", "red")
UNKNOWN = ("unknown", "lightgrey")

# (alt_text, label, type, coverage_json_path | None)
BADGE_SPECS = {
    "build":       ("Build",             "build",             "boolean",  None),
    "unit":        ("Unit Tests",        "unit tests",        "boolean",  None),
    "integration": ("Integration Tests", "integration tests", "boolean",  None),
    "quality":     ("Quality",           "quality",           "boolean",  None),
    "security":    ("Security",          "security",          "boolean",  None),
    "cov-fd":      ("HFT Engine Coverage",        "engine coverage",      "coverage", REPO_ROOT / "build/coverage/fd/coverage-summary.json"),
    "cov-tk":      ("AI Harness Coverage",        "harness coverage",     "coverage", REPO_ROOT / "build/coverage/tk/coverage-summary.json"),
}


def encode_segment(value: str) -> str:
    return value.replace("%", "%25").replace(" ", "%20")


def build_badge(alt: str, label: str, message: str, color: str) -> str:
    url = (
        f"{SHIELDS_BASE_URL}/{encode_segment(label)}"
        f"-{encode_segment(message)}"
        f"-{encode_segment(color)}?style={SHIELDS_STYLE}"
    )
    return f'<img alt="{alt}" src="{url}" />'


def _coverage_color(pct: float) -> str:
    if pct < 60:
        return "red"
    if pct < 80:
        return "orange"
    if pct < 90:
        return "yellowgreen"
    return "brightgreen"


def _read_coverage_pct(path: Path) -> float | None:
    """Return average line/branch/function coverage, or None if nothing was measured."""
    if not path.exists():
        raise FileNotFoundError(f"Missing coverage summary: {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ValueError(f"Failed to parse {path}: {exc}") from exc
    total = data.get("total", {})
    pcts = [
        float(total[m]["pct"])
        for m in ("lines", "branches", "functions")
        if isinstance(total.get(m, {}).get("pct"), (int, float))
        and total[m].get("total", 0) > 0
    ]
    if not pcts:
        return None
    return round(sum(pcts) / len(pcts), 1)


def badge_for_exit_code(alt: str, label: str, exit_code: int) -> str:
    message, color = BOOLEAN_SUCCESS if exit_code == 0 else BOOLEAN_FAILURE
    return build_badge(alt, label, message, color)


def badge_for_coverage(alt: str, label: str, exit_code: int, cov_path: Path) -> str:
    if exit_code != 0:
        return build_badge(alt, label, BOOLEAN_FAILURE[0], BOOLEAN_FAILURE[1])
    pct = _read_coverage_pct(cov_path)
    if pct is None:
        return build_badge(alt, label, *UNKNOWN)
    return build_badge(alt, label, f"{pct:.1f}%", _coverage_color(pct))


def badge_unknown(alt: str, label: str) -> str:
    return build_badge(alt, label, *UNKNOWN)


def replace_badge_block(readme: str, name: str, badge_line: str) -> str:
    start_marker = f"<!-- badge:{name}:start -->"
    end_marker   = f"<!-- badge:{name}:end -->"

    start = readme.find(start_marker)
    end   = readme.find(end_marker)

    if start == -1 or end == -1:
        raise ValueError(f"Badge markers missing for '{name}'")
    if end < start:
        raise ValueError(f"Badge markers out of order for '{name}'")

    newline = "\r\n" if "\r\n" in readme else "\n"
    block = f"{start_marker}{newline}{badge_line}{newline}{end_marker}"
    return readme[:start] + block + readme[end + len(end_marker):]


def update_readme_badge(name: str, exit_code: int) -> None:
    if name not in BADGE_SPECS:
        raise ValueError(f'Unknown badge "{name}". Expected one of: {", ".join(BADGE_SPECS)}')

    readme = README_PATH.read_text(encoding="utf-8")
    alt, label, badge_type, cov_path = BADGE_SPECS[name]
    if badge_type == "coverage":
        badge_line = badge_for_coverage(alt, label, exit_code, cov_path)
    else:
        badge_line = badge_for_exit_code(alt, label, exit_code)
    updated = replace_badge_block(readme, name, badge_line)
    README_PATH.write_text(updated, encoding="utf-8")


def update_readme_badge_unknown(name: str) -> None:
    if name not in BADGE_SPECS:
        raise ValueError(f'Unknown badge "{name}". Expected one of: {", ".join(BADGE_SPECS)}')

    readme = README_PATH.read_text(encoding="utf-8")
    alt, label, _badge_type, _cov_path = BADGE_SPECS[name]
    badge_line = badge_unknown(alt, label)
    updated = replace_badge_block(readme, name, badge_line)
    README_PATH.write_text(updated, encoding="utf-8")


def reset_all_readme_badges() -> None:
    readme = README_PATH.read_text(encoding="utf-8")
    for name, (alt, label, _badge_type, _cov_path) in BADGE_SPECS.items():
        readme = replace_badge_block(readme, name, badge_unknown(alt, label))
    README_PATH.write_text(readme, encoding="utf-8")


if __name__ == "__main__":
    args = sys.argv[1:]

    if not args:
        print(
            "Usage: refresh-badges.py <badge-name> <exit-code|unknown> | reset-all",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        if args[0] == "reset-all":
            reset_all_readme_badges()
        else:
            if len(args) < 2:
                raise ValueError("Missing badge state argument")
            name = args[0]
            if args[1] == "unknown":
                update_readme_badge_unknown(name)
            else:
                try:
                    exit_code = int(args[1])
                    if exit_code < 0:
                        raise ValueError()
                except ValueError:
                    raise ValueError(f"Invalid exit code: {args[1]}")
                update_readme_badge(name, exit_code)
    except Exception as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
