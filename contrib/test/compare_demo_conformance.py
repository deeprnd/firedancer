#!/usr/bin/env python3
import json
import pathlib
import sys

IGNORED_ARTIFACT_FIELDS = {"runtime_tier", "isolation_tier"}
IGNORED_TOP_LEVEL_FIELDS = {"comparison"}


def normalize_artifact(entry: dict) -> dict:
    return {k: v for k, v in entry.items() if k not in IGNORED_ARTIFACT_FIELDS}


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: compare_demo_conformance.py <linux-json> <retail-json>", file=sys.stderr)
        return 1
    lhs = json.loads(pathlib.Path(sys.argv[1]).read_text())
    rhs = json.loads(pathlib.Path(sys.argv[2]).read_text())

    for key in (set(lhs.keys()) | set(rhs.keys())) - IGNORED_TOP_LEVEL_FIELDS:
        if key == "suite":
            continue
        if lhs.get(key) != rhs.get(key):
            print(f"top-level mismatch: {key}", file=sys.stderr)
            return 1

    lhs_suite = {entry["scenario"]: normalize_artifact(entry) for entry in lhs["suite"]}
    rhs_suite = {entry["scenario"]: normalize_artifact(entry) for entry in rhs["suite"]}
    if lhs_suite.keys() != rhs_suite.keys():
        print("scenario set mismatch", file=sys.stderr)
        return 1

    mismatches: list[str] = []
    for scenario in sorted(lhs_suite.keys()):
        left = lhs_suite[scenario]
        right = rhs_suite[scenario]
        if left != right:
            for field in sorted(set(left.keys()) | set(right.keys())):
                if left.get(field) != right.get(field):
                    mismatches.append(f"{scenario}.{field}: {left.get(field)!r} != {right.get(field)!r}")
    if mismatches:
        print("conformance mismatch detected:", file=sys.stderr)
        for item in mismatches:
            print(f"  - {item}", file=sys.stderr)
        return 1

    print("demo conformance artifacts match on deterministic fields")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
