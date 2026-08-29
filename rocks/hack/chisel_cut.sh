#!/usr/bin/env bash
# Wrapper around `chisel cut` with retry on known-flaky archive
# errors. Patterns lifted from canonical/chisel-releases'
# .github/scripts/install-slices/install_slices.py.
#
# Usage: chisel_cut.sh <release-dir> <slice> [<slice> ...]
# Requires:
#   - <release-dir> to be a chisel-releases checkout
#   - $CRAFT_PART_INSTALL to be set (rockcraft env)
set -e

N_RETRIES=10
RETRY_DELAY=60
PATTERNS=(
    # https://github.com/canonical/chisel-releases/issues/765
    "cannot fetch from archive"
    # https://github.com/canonical/chisel-releases/issues/766
    "cannot talk to archive"
    # https://github.com/canonical/chisel-releases/issues/768
    "cannot find archive data"
    # transient digest mismatch (chisel bug)
    "expected digest"
)

[ "$#" -ge 2 ] || { echo "usage: $0 <release-dir> <slice> [<slice> ...]" >&2; exit 1; }
[ -n "${CRAFT_PART_INSTALL:-}" ] || { echo "CRAFT_PART_INSTALL unset" >&2; exit 1; }

release_dir=$1
shift

for attempt in $(seq 1 "$N_RETRIES"); do
    err=$(chisel cut \
            --release "$release_dir" \
            --root "$CRAFT_PART_INSTALL" \
            "$@" 2>&1) && rc=0 || rc=$?
    if [ "$rc" -eq 0 ]; then
        printf '%s\n' "$err"
        exit 0
    fi

    matched=""
    matched_line=""
    for p in "${PATTERNS[@]}"; do
        line=$(printf '%s\n' "$err" | grep -F "$p" | head -n1) || true
        if [ -n "$line" ]; then matched=$p; matched_line=$line; break; fi
    done

    if [ -n "$matched" ] && [ "$attempt" -lt "$N_RETRIES" ]; then
        echo "chisel cut failed (attempt $attempt/$N_RETRIES): $matched. Retrying in ${RETRY_DELAY}s..." >&2
        echo "  > $matched_line" >&2
        sleep "$RETRY_DELAY"
        continue
    fi

    printf '%s\n' "$err" >&2
    exit "$rc"
done
