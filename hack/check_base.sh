#!/usr/bin/env bash
# Detect upstream ubuntu base-image drift for the bread base Dockerfiles.
#
# Each images/Dockerfile.bread-<ver> pins its base by digest:
#   FROM <registry/repo>:<tag>@sha256:<manifest-list-digest>
# This script resolves the *live* manifest-list digest for each base and
# compares it to the pinned one. The pin is part of hack/hash_inputs.sh's
# hash for the bread flavour, so bumping it busts the image stamp and forces a
# rebuild (bread-chisel-releases + bread-test cascade off .stamp/bread-%).
#
# Usage:
#   check_base.sh [--check]   # report drift; exit 1 if any base drifted (default)
#   check_base.sh --write     # rewrite drifted FROM pins in place; always exit 0
#
# Resolution uses `docker buildx imagetools inspect --raw | sha256sum`, which
# yields the manifest-list (index) digest and is registry-agnostic -- all
# versions now pull from docker.io/library/ubuntu.
set -euo pipefail

cd "$(dirname "$0")/.."

mode="check"
case "${1:-}" in
    ""|--check) mode="check" ;;
    --write)    mode="write" ;;
    *) echo "usage: $0 [--check|--write]" >&2; exit 2 ;;
esac

# Base Dockerfiles only. The [0-9][0-9].[0-9][0-9] glob matches
# Dockerfile.bread-24.04 etc. but not Dockerfile.bread-chisel-releases-*
# (those are FROM bread:<tag>, not upstream bases).
shopt -s nullglob
dockerfiles=(images/Dockerfile.bread-[0-9][0-9].[0-9][0-9])

resolve() {  # <ref-without-digest> -> sha256:<hex>
    local hex
    hex=$(docker buildx imagetools inspect "$1" --raw | sha256sum | cut -d' ' -f1)
    printf 'sha256:%s' "$hex"
}

drift=0
changed=()
for df in "${dockerfiles[@]}"; do
    ver="${df##*-}"   # images/Dockerfile.bread-26.04 -> 26.04
    from=$(grep -m1 -E '^FROM ' "$df" | awk '{print $2}')
    base="${from%@*}"            # strip any existing @sha256:...
    pinned=""
    case "$from" in *@sha256:*) pinned="sha256:${from##*@sha256:}" ;; esac

    live=$(resolve "$base")
    if [ "$live" = "$pinned" ]; then
        echo "$ver: up-to-date ($base)"
        continue
    fi

    drift=1
    changed+=("$ver")
    echo "$ver: drift ${pinned:-<unpinned>} -> $live"

    if [ "$mode" = "write" ]; then
        # Exactly one base FROM per file; rewrite that line, keep the rest.
        awk -v repl="FROM ${base}@${live}" \
            '/^FROM / && !seen {print repl; seen=1; next} {print}' \
            "$df" > "$df.tmp"
        mv "$df.tmp" "$df"
    fi
done

if [ "$mode" = "write" ]; then
    if [ "${#changed[@]}" -gt 0 ]; then
        echo "updated: ${changed[*]}"
    else
        echo "no drift; nothing to write"
    fi
    exit 0
fi

exit "$drift"
