#!/usr/bin/env python3
"""Update README.md badge image tags between marker comments."""

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

BADGE_SPECS = {
    "build":       ("Build",              "build",              "boolean"),
    "unit":        ("Unit Tests",         "unit tests",         "boolean"),
    "integration": ("Integration Tests",  "integration tests",  "boolean"),
    "quality":     ("Quality",            "quality",            "boolean"),
    "security":    ("Security",           "security",           "boolean"),
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


def badge_for_exit_code(alt: str, label: str, exit_code: int) -> str:
    message, color = BOOLEAN_SUCCESS if exit_code == 0 else BOOLEAN_FAILURE
    return build_badge(alt, label, message, color)


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
    alt, label, _ = BADGE_SPECS[name]
    badge_line = badge_for_exit_code(alt, label, exit_code)
    updated = replace_badge_block(readme, name, badge_line)
    README_PATH.write_text(updated, encoding="utf-8")


def update_readme_badge_unknown(name: str) -> None:
    if name not in BADGE_SPECS:
        raise ValueError(f'Unknown badge "{name}". Expected one of: {", ".join(BADGE_SPECS)}')

    readme = README_PATH.read_text(encoding="utf-8")
    alt, label, _ = BADGE_SPECS[name]
    badge_line = badge_unknown(alt, label)
    updated = replace_badge_block(readme, name, badge_line)
    README_PATH.write_text(updated, encoding="utf-8")


def reset_all_readme_badges() -> None:
    readme = README_PATH.read_text(encoding="utf-8")
    for name, (alt, label, _) in BADGE_SPECS.items():
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
