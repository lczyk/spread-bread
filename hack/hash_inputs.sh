#!/usr/bin/env bash
# Compute single sha256 over all inputs that affect a given image build.
# Usage: hash_inputs.sh <flavour-ver-arch>
#   flavour-ver-arch examples:
#     bread-24.04-amd64
#     bread-chisel-releases-25.10-arm64
# Stdout: hex digest only.
set -euo pipefail

cd "$(dirname "$0")/.."

name="$1"
arch="${name##*-}"
rest="${name%-*}"
ver="${rest##*-}"
flavour="${rest%-*}"

case "$flavour" in
    bread)
        inputs=("images/Dockerfile.bread-$ver")
        ;;
    bread-chisel-releases)
        inputs=(
            "images/Dockerfile.bread-chisel-releases-$ver"
            ".stamp/bread-$ver-$arch"
        )
        ;;
    *)
        echo "unknown flavour: $flavour" >&2
        exit 2
        ;;
esac

sha256sum "${inputs[@]}" | sha256sum | cut -d' ' -f1
