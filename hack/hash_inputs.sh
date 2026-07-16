#!/usr/bin/env bash
# Compute single sha256 over all inputs that affect a given image build,
# or for the cross-compiled go binaries cache.
#
# Usage:
#   hash_inputs.sh <flavour-ver-arch>     # for image stamps
#   hash_inputs.sh binaries               # for cache/binaries stamp
#
# Stdout: hex digest only.
set -euo pipefail

cd "$(dirname "$0")/.."

name="$1"

if [ "$name" = "binaries" ]; then
    # Binary cache hash combines:
    #   - hack/build_binaries.rb content (drives how things build)
    #   - CHISEL_REF + SPREAD_REF + GO_BUILDER_IMAGE env vars (drive what is built)
    : "${CHISEL_REF:?required}"
    : "${SPREAD_REF:?required}"
    : "${GO_BUILDER_IMAGE:?required}"
    : "${DOCKER_VERSION:?required}"
    { sha256sum hack/build_binaries.rb patches/chisel/*.patch; \
      printf 'CHISEL_REF=%s\nSPREAD_REF=%s\nGO_BUILDER_IMAGE=%s\nDOCKER_VERSION=%s\n' \
          "$CHISEL_REF" "$SPREAD_REF" "$GO_BUILDER_IMAGE" "$DOCKER_VERSION"; \
    } | sha256sum | cut -d' ' -f1
    exit 0
fi

arch="${name##*-}"
rest="${name%-*}"
ver="${rest##*-}"
flavour="${rest%-*}"

case "$flavour" in
    bread)
        inputs=(
            "images/Dockerfile.bread-$ver"
            "hack/bread-warning.sh"
            "hack/banner.txt"
        )
        ;;
    bread-chisel-releases)
        inputs=(
            "images/Dockerfile.bread-chisel-releases-$ver"
            "hack/lazy-apt.sh"
            ".stamp/bread-$ver-$arch"
            ".stamp/binaries"
        )
        ;;
    bread-test)
        inputs=(
            "tests/Dockerfile.bread-test-$ver"
            ".stamp/bread-$ver-$arch"
            ".stamp/binaries"
        )
        ;;
    *)
        echo "unknown flavour: $flavour" >&2
        exit 2
        ;;
esac

sha256sum "${inputs[@]}" | sha256sum | cut -d' ' -f1
