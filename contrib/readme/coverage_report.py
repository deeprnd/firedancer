#!/usr/bin/env python3
"""Parse coverage data, write Istanbul-format summary JSON, and check thresholds.

Thresholds are read from a per-component config file (vitest-style):
  { "coverage": { "thresholds": { "lines": 20, "statements": 20, "branches": 20, "functions": 20 } } }

Usage:
  python3 contrib/readme/coverage_report.py coverage-fd <covdir> <output.json> --config contrib/test/coverage-fd.json
  python3 contrib/readme/coverage_report.py coverage-tk <kcov-merged-dir> <output.json> --config contrib/test/coverage-tk.json
"""

import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent

METRICS = ("lines", "statements", "branches", "functions")


# ── helpers ────────────────────────────────────────────────────────────────

def _pct(covered: int, total: int) -> float:
    if total == 0:
        return 100.0
    return round(covered / total * 100, 1)


def _color_label(pct: float) -> str:
    if pct < 60:
        return "red"
    if pct < 80:
        return "orange"
    if pct < 90:
        return "yellowgreen"
    return "brightgreen"


def _load_thresholds(config_path: Path) -> dict:
    if not config_path.exists():
        raise FileNotFoundError(f"Coverage config not found: {config_path}")
    data = json.loads(config_path.read_text(encoding="utf-8"))
    thresholds = data.get("coverage", {}).get("thresholds", {})
    return {m: thresholds.get(m, 0) for m in METRICS}


def _write_summary(summary: dict, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


def _check_thresholds(summary: dict, thresholds: dict) -> int:
    """Check all metrics. Metrics with total==0 are skipped (not measured)."""
    failed = False
    for metric in METRICS:
        threshold = thresholds.get(metric, 0)
        stats = summary.get("total", {}).get(metric, {})
        total = stats.get("total", 0)
        pct = stats.get("pct", 0.0)

        if total == 0:
            print(f"  {metric:<12s}  N/A (not measured by this tool)")
            continue

        color = _color_label(pct)
        ok = pct >= threshold
        status = "ok" if ok else "FAIL"
        print(f"  {metric:<12s}  {pct:5.1f}%  (threshold {threshold:.1f}%)  [{color}]  {status}")
        if not ok:
            failed = True

    return 1 if failed else 0


def _build_summary(
    lines_covered: int, lines_total: int,
    branches_covered: int = 0, branches_total: int = 0,
    functions_covered: int = 0, functions_total: int = 0,
) -> dict:
    return {
        "total": {
            "lines":      {"total": lines_total,     "covered": lines_covered,     "skipped": 0, "pct": _pct(lines_covered,     lines_total)},
            "statements": {"total": lines_total,     "covered": lines_covered,     "skipped": 0, "pct": _pct(lines_covered,     lines_total)},
            "branches":   {"total": branches_total,  "covered": branches_covered,  "skipped": 0, "pct": _pct(branches_covered,  branches_total)},
            "functions":  {"total": functions_total, "covered": functions_covered, "skipped": 0, "pct": _pct(functions_covered, functions_total)},
        }
    }


# ── fd (LLVM source-based coverage) ───────────────────────────────────────

def cmd_coverage_fd(covdir: Path, output: Path, config: Path) -> int:
    profdata = covdir / "cov.profdata"
    mappings_ar = covdir / "mappings.ar"

    if not profdata.exists():
        print(f"ERROR: {profdata} not found — run the unit tests with EXTRAS=llvm-cov first", file=sys.stderr)
        return 1
    if not mappings_ar.exists():
        print(f"ERROR: {mappings_ar} not found — coverage mappings archive was not built", file=sys.stderr)
        return 1

    result = subprocess.run(
        [
            "llvm-cov", "export",
            "--format=text",
            "--summary-only",
            f"--instr-profile={profdata}",
            "--ignore-filename-regex=(test_|fuzz_).*\\.c",
            str(mappings_ar),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise RuntimeError(f"llvm-cov export failed (exit {result.returncode})")

    totals = json.loads(result.stdout)["data"][0]["totals"]
    lines     = totals["lines"]
    branches  = totals.get("branches", {"count": 0, "covered": 0})
    functions = totals["functions"]

    summary = _build_summary(
        lines_covered=lines["covered"],     lines_total=lines["count"],
        branches_covered=branches.get("covered", 0), branches_total=branches.get("count", 0),
        functions_covered=functions["covered"], functions_total=functions["count"],
    )
    _write_summary(summary, output)

    thresholds = _load_thresholds(config)
    return _check_thresholds(summary, thresholds)


# ── tk (kcov) ──────────────────────────────────────────────────────────────

def cmd_coverage_tk(kcov_dir: Path, output: Path, config: Path) -> int:
    coverage_json = kcov_dir / "coverage.json"
    if not coverage_json.exists():
        print(f"ERROR: {coverage_json} not found — kcov did not produce output", file=sys.stderr)
        return 1

    data = json.loads(coverage_json.read_text(encoding="utf-8"))
    covered = int(data.get("covered_lines", 0))
    total   = int(data.get("total_lines", 0))
    # Use kcov's own percentage to avoid rounding discrepancies.
    pct = float(data.get("percent_covered", _pct(covered, total)))

    summary = _build_summary(lines_covered=covered, lines_total=total)
    summary["total"]["lines"]["pct"]      = round(pct, 1)
    summary["total"]["statements"]["pct"] = round(pct, 1)

    _write_summary(summary, output)

    thresholds = _load_thresholds(config)
    return _check_thresholds(summary, thresholds)


# ── main ───────────────────────────────────────────────────────────────────

def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="Parse coverage output, write Istanbul-format JSON, check thresholds."
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    for name in ("coverage-fd", "coverage-tk"):
        sp = sub.add_parser(name)
        sp.add_argument("covdir",  type=Path, help="Coverage data directory")
        sp.add_argument("output",  type=Path, help="Output coverage-summary.json path")
        sp.add_argument("--config", type=Path, required=True,
                        help="Threshold config (e.g. contrib/test/coverage-fd.json)")

    args = parser.parse_args()

    try:
        if args.cmd == "coverage-fd":
            sys.exit(cmd_coverage_fd(args.covdir, args.output, args.config))
        elif args.cmd == "coverage-tk":
            sys.exit(cmd_coverage_tk(args.covdir, args.output, args.config))
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
