#!/usr/bin/env bash
# Build one image if its input hash differs from the stamp.
# Usage: build_image.sh <flavour-ver-arch>
#   flavour-ver-arch examples:
#     bread-24.04-amd64
#     bread-chisel-releases-25.10-arm64
set -euo pipefail

cd "$(dirname "$0")/.."

name="$1"
arch="${name##*-}"
rest="${name%-*}"
ver="${rest##*-}"
flavour="${rest%-*}"

stamp=".stamp/$name"

new=$(hack/hash_inputs.sh "$name")
cur=$(cat "$stamp" 2>/dev/null || true)

if [ "$new" = "$cur" ]; then
    echo "==> ${flavour}:${ver}-${arch} up-to-date (stamp matches)"
    exit 0
fi

echo "==> building ${flavour}:${ver}-${arch} (inputs changed)"

case "$flavour" in
    bread)
        docker build \
            --tag "bread:$ver-$arch" \
            --file "images/Dockerfile.bread-$ver" \
            --platform "linux/$arch" \
            .
        ;;
    bread-chisel-releases)
        docker build \
            --tag "bread-chisel-releases:$ver-$arch" \
            --build-arg "BASE_TAG=$ver-$arch" \
            --build-arg "BUILD_ARCH=$arch" \
            --file "images/Dockerfile.bread-chisel-releases-$ver" \
            --platform "linux/$arch" \
            .
        ;;
    bread-test)
        docker build \
            --tag "bread-test:$ver-$arch" \
            --build-arg "BASE_TAG=$ver-$arch" \
            --build-arg "BUILD_ARCH=$arch" \
            --file "tests/Dockerfile.bread-test-$ver" \
            --platform "linux/$arch" \
            .
        ;;
    *)
        echo "unknown flavour: $flavour" >&2
        exit 2
        ;;
esac

echo "$new" > "$stamp"
