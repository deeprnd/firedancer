#!/usr/bin/env bash
# Coverage report generator.
# Usage: coverage.sh <job-name>
set -euo pipefail
JOB="${1:?Usage: coverage.sh <job-name>}"

_start=$(date +%s)
log() { echo "[$(date +%H:%M:%S)] [$(( $(date +%s) - _start ))s] $*"; }

if [ "$JOB" = "coverage-fd" ]; then
    COVDIR=build/fd-cov
    RAWDIR="${COVDIR}/cov/raw"
    OBJDIR=build/fd-cov/obj

    # Always start fresh — delete coverage artifacts to prevent stale state.
    rm -f "${COVDIR}/cov.profdata" "${COVDIR}/mappings.ar"

    # Build cov.profdata from .profraw files (llvm-cov step 1.3).
    mkdir -p "${COVDIR}"
    _t0=$(date +%s)
    llvm-profdata merge -o "${COVDIR}/cov.profdata" "${RAWDIR}"/*.profraw
    log "[profdata] merge done in $(( $(date +%s) - _t0 ))s"

    # Build mappings.ar from .o files with __llvm_covmap sections (llvm-cov step 1.4).
    # Only scan .o files from the coverage source dirs (FD_TK_LIB_COV_SRCS):
    #   tango, util, ballet, disco, waltz, cjson, picohttpparser, blst, lz4, zstd, nanopb
    # Exclude test_* binaries and generated protobuf files (*.pb.o) — they'll be
    # filtered by --ignore-filename-regex anyway, but keeping them inflates mappings.ar
    # and makes llvm-cov export slow.
    mkdir -p "${COVDIR}"
    _t0=$(date +%s)
    _count=0
    _found=0

    # Coverage source dirs to scan (relative to OBJDIR) — only core Tickoni libs
    # (tango, util, ballet, disco, waltz); third-party sources excluded.
    _cov_dirs=(tango util ballet disco waltz)

    # First pass: collect candidate objects into a temp file
    _tmpfile=$(mktemp)
    for _cov_dir in "${_cov_dirs[@]}"; do
        _dir="${OBJDIR}/${_cov_dir}"
        if [ -d "$_dir" ]; then
            while IFS= read -r -d '' obj; do
                _count=$((_count + 1))
                if llvm-objdump -h "$obj" 2>/dev/null | grep -q llvm_covmap; then
                    bn=$(basename "$obj")
                    case "$bn" in
                        test_*.o|*.pb.o)
                            continue
                            ;;
                        *)
                            echo "$obj" >> "$_tmpfile"
                            _found=$((_found + 1))
                            if [ $((_found % 50)) -eq 0 ]; then
                                log "[mappings] scan: $_count scanned, $_found accepted so far"
                            fi
                            ;;
                    esac
                fi
            done < <(find "$_dir" -name '*.o' -print0 2>/dev/null)
        fi
    done
    log "[mappings] scan complete: $_count scanned, $_found objects passed filter"

    # Second pass: create archive in batches of 50 to avoid command-line limits
    if [ $_found -gt 0 ]; then
        log "[mappings] creating mappings.ar with $_found objects..."
        _t1=$(date +%s)
        _added=0
        _batch=()
        while IFS= read -r obj; do
            _batch+=("$obj")
            if [ ${#_batch[@]} -ge 50 ]; then
                llvm-ar --thin q "${COVDIR}/mappings.ar" "${_batch[@]}" 2>/dev/null
                _added=$((_added + ${#_batch[@]}))
                log "[mappings] added $_added of $_found objects"
                _batch=()
            fi
        done < "$_tmpfile"
        rm -f "$_tmpfile"
        # Add remaining objects
        if [ ${#_batch[@]} -gt 0 ]; then
            llvm-ar --thin q "${COVDIR}/mappings.ar" "${_batch[@]}" 2>/dev/null
            _added=$((_added + ${#_batch[@]}))
        fi
        log "[mappings] archive created in $(( $(date +%s) - _t1 ))s: $_added objects, size=$(du -h "${COVDIR}/mappings.ar" | cut -f1)"
    fi

    # Ensure .profdata is the newest file — llvm-cov export skips cross-validation
    # when profile data is newer than all objects. Without this, llvm-cov spends
    # minutes re-scanning symbols when .o files are newer (touch by llvm-ar).
    touch -r "${COVDIR}/mappings.ar" "${COVDIR}/cov.profdata" 2>/dev/null || true
    log "[profdata] timestamp updated to match mappings.ar"

    # List objects in the archive and their coverage data
    if [ -f "${COVDIR}/mappings.ar" ]; then
        _ar_entries=$(llvm-ar t "${COVDIR}/mappings.ar" | wc -l)
        log "[mappings] archive has $_ar_entries entries"
    fi

    # Run coverage report with a hard timeout. llvm-cov export can hang on
    # stale/mismatched .o files or very large mappings.ar (>600s). 900s gives
    # a 5-minute grace period over the Python default before giving up.
    _t0=$(date +%s)
    set +e
    timeout 900 python3 contrib/readme/coverage_report.py coverage-fd \
        "${COVDIR}" \
        build/coverage/fd/coverage-summary.json \
        --config contrib/test/coverage-fd.json
    cov_rc=$?
    set -e
    _t1=$(( $(date +%s) - _t0 ))
    log "[coverage-report] exit=$cov_rc in ${_t1}s"
    if [ "$cov_rc" -eq 137 ]; then
        echo "ERROR: llvm-cov export timed out after 900s — stale artifacts. Clean with:" >&2
        echo "  rm -rf build/fd-cov/cov.profdata build/fd-cov/mappings.ar" >&2
        exit 1
    fi
    exit "$cov_rc"
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

    # Merge kcov outputs — find directories created by each binary run
    MERGED="${COV_RAW}/merged"
    kcov_dirs=()
    for d in "${COV_RAW}"/*/; do
        [ -d "$d" ] || continue
        base="$(basename "$d")"
        [ "$base" = "merged" ] && continue
        kcov_dirs+=("$d")
    done
    if [ "${#kcov_dirs[@]}" -ge 2 ]; then
        kcov --merge "$MERGED" "${kcov_dirs[@]}"
    elif [ "${#kcov_dirs[@]}" -eq 1 ]; then
        mkdir -p "$MERGED"
        ln -sfn "$(realpath "${kcov_dirs[0]}")" "$MERGED"
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
