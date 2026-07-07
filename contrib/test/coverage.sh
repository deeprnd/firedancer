#!/usr/bin/env bash
# Coverage report generator.
# Usage: coverage.sh <job-name>
set -euo pipefail
JOB="${1:?Usage: coverage.sh <job-name>}"

if [ "$JOB" = "coverage-fd" ]; then
    COVDIR=build/fd-cov/cov
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
        build/fd-cov/cov \
        build/coverage/fd/coverage-summary.json \
        --config contrib/test/coverage-fd.json
elif [ "$JOB" = "coverage-tk" ]; then
    echo "Coverage complete: $JOB"
else
    echo "Unknown job: $JOB"
    exit 1
fi
