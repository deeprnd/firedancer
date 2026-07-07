#!/usr/bin/env bash
# Coverage report generator.
# Usage: coverage.sh <job-name>
set -euo pipefail
JOB="${1:?Usage: coverage.sh <job-name>}"

if [ "$JOB" = "coverage-fd" ]; then
    COVDIR=build/fd-cov
    RAWDIR="${COVDIR}/raw"
    OBJDIR=build/fd-cov/obj

    # Build cov.profdata from .profraw files (llvm-cov step 1.3).
    if [ ! -f "${COVDIR}/cov.profdata" ]; then
        mkdir -p "${COVDIR}"
        llvm-profdata merge -o "${COVDIR}/cov.profdata" "${RAWDIR}"/*.profraw
    fi

    # Build mappings.ar from .o files with __llvm_covmap sections (llvm-cov step 1.4).
    if [ ! -f "${COVDIR}/mappings.ar" ]; then
        rm -f "${COVDIR}/mappings.ar"
        mkdir -p "${COVDIR}"
        while IFS= read -r -d '' obj; do
            if llvm-objdump -h "$obj" 2>/dev/null | grep -q llvm_covmap; then
                llvm-ar --thin q "${COVDIR}/mappings.ar" "$obj"
            fi
        done < <(find "${OBJDIR}" -name '*.o' -print0)
    fi

    python3 contrib/readme/coverage_report.py coverage-fd \
        "${COVDIR}" \
        build/coverage/fd/coverage-summary.json \
        --config contrib/test/coverage-fd.json
elif [ "$JOB" = "coverage-tk" ]; then
    command -v kcov >/dev/null 2>&1 || {
        echo "ERROR: kcov not found. Install it with: sudo apt-get install kcov" >&2
        exit 1
    }

    COV_BINS="zig-out/cov"
    COV_RAW="build/coverage/tk/kcov"
    SUMMARY="build/coverage/tk/coverage-summary.json"
    CONFIG="contrib/test/coverage-tk.json"

    # ReleaseSafe triggers DWARFv4 output (via LLVM backend), which kcov handles
    # correctly across multiple CUs. Debug mode emits DWARFv5 with per-CU
    # rnglists_base; kcov v44 only honours the first CU's base, silently dropping
    # all subsequent user-code CUs from the coverage report.
    zig build cov -Doptimize=ReleaseSafe -Dfd-lib-dir=build/fd-tickoni-fd/lib

    mkdir -p "$COV_RAW"

    # Run tests via kcov
    for bin in "${COV_BINS}"/*; do
        [ -f "$bin" ] || continue
        name="$(basename "$bin")"
        kcov --include-pattern=src/tickoni \
            "${COV_RAW}"/"$name" \
            "$bin"
    done

    # Merge kcov outputs
    MERGED="${COV_RAW}/merged"
    if [ -d "${COV_RAW}/test-0" ] && [ -d "${COV_RAW}/test-1" ]; then
        kcov --merge "$MERGED" "${COV_RAW}/test-0" "${COV_RAW}/test-1"
    elif [ -d "${COV_RAW}/test-0" ]; then
        ln -sfn "$(realpath "${COV_RAW}/test-0")" "$MERGED"
    else
        echo 'ERROR: no kcov output directories found' >&2
        exit 1
    fi

    python3 contrib/readme/coverage_report.py coverage-tk \
        "${COV_RAW}/merged" \
        "$SUMMARY" \
        --config "$CONFIG"
else
    echo "Unknown job: $JOB"
    exit 1
fi
