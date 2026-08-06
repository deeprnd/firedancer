#!/usr/bin/env python3
"""Update doc/execution/testing-tickoni.md badge image tags between marker comments."""

import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent
TESTING_DOC_PATH = REPO_ROOT / "doc/execution/testing-tickoni.md"
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
    "system":      ("System Tests",      "system tests",      "boolean",  None),
    "e2e":         ("E2E Tests",         "e2e tests",         "boolean",  None),
    "cov-fd":      ("Engine Coverage",   "engine coverage",      "coverage", REPO_ROOT / "build/coverage/fd/coverage-summary.json"),
    "cov-tk":      ("AI Harness Coverage",    "harness coverage",     "coverage", REPO_ROOT / "build/coverage/tk/coverage-summary.json"),
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
    """Return branch coverage percentage, or None if nothing was measured."""
    if not path.exists():
        raise FileNotFoundError(f"Missing coverage summary: {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ValueError(f"Failed to parse {path}: {exc}") from exc
    total = data.get("total", {})
    branches = total.get("branches", {})
    total_count = branches.get("total", 0)
    if total_count == 0:
        return None
    pct = branches.get("pct", None)
    if pct is None:
        return None
    return round(float(pct), 1)


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


def replace_badge_block(doc_text: str, name: str, badge_line: str) -> str:
    start_marker = f"<!-- badge:{name}:start -->"
    end_marker   = f"<!-- badge:{name}:end -->"

    start = doc_text.find(start_marker)
    end   = doc_text.find(end_marker)

    if start == -1 or end == -1:
        raise ValueError(f"Badge markers missing for '{name}'")
    if end < start:
        raise ValueError(f"Badge markers out of order for '{name}'")

    # Extract leading whitespace from the badge line (between markers)
    newline = "\r\n" if "\r\n" in doc_text else "\n"
    after_start = start + len(start_marker) + len(newline)
    next_line_end = doc_text.find(newline, after_start)
    if next_line_end == -1:
        next_line_end = len(doc_text)
    next_line = doc_text[after_start : next_line_end]
    leading = next_line[: len(next_line) - len(next_line.lstrip())] if next_line.lstrip() else ""

    block = f"{start_marker}{newline}{leading}{badge_line}{newline}{end_marker}"
    return doc_text[:start] + block + doc_text[end + len(end_marker):]


def update_readme_badge(name: str, exit_code: int, doc_path: Path | None = None) -> None:
    if name not in BADGE_SPECS:
        raise ValueError(f'Unknown badge "{name}". Expected one of: {", ".join(BADGE_SPECS)}')

    doc_path = doc_path or TESTING_DOC_PATH
    doc_text = doc_path.read_text(encoding="utf-8")
    alt, label, badge_type, cov_path = BADGE_SPECS[name]
    if badge_type == "coverage":
        badge_line = badge_for_coverage(alt, label, exit_code, cov_path)
    else:
        badge_line = badge_for_exit_code(alt, label, exit_code)
    updated = replace_badge_block(doc_text, name, badge_line)
    doc_path.write_text(updated, encoding="utf-8")


def update_readme_badge_unknown(name: str, doc_path: Path | None = None) -> None:
    if name not in BADGE_SPECS:
        raise ValueError(f'Unknown badge "{name}". Expected one of: {", ".join(BADGE_SPECS)}')

    doc_path = doc_path or TESTING_DOC_PATH
    doc_text = doc_path.read_text(encoding="utf-8")
    alt, label, _badge_type, _cov_path = BADGE_SPECS[name]
    badge_line = badge_unknown(alt, label)
    updated = replace_badge_block(doc_text, name, badge_line)
    doc_path.write_text(updated, encoding="utf-8")


def reset_all_readme_badges(doc_path: Path | None = None) -> None:
    doc_path = doc_path or TESTING_DOC_PATH
    doc_text = doc_path.read_text(encoding="utf-8")
    for name, (alt, label, _badge_type, _cov_path) in BADGE_SPECS.items():
        doc_text = replace_badge_block(doc_text, name, badge_unknown(alt, label))
    doc_path.write_text(doc_text, encoding="utf-8")


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
