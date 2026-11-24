#!/usr/bin/env bash
# LXD contract: pack the host arch's locally built images (hack/pack_lxd.sh),
# serve the packs over http the way the release serves its assets, and run the
# inner contract tasks on the lxd backend of each inlined/<flavour>-<ver>.yaml.
# Exercises what a consumer runs: fingerprint, download, import, launch, peel
# boot, ssh.
#
# Usage: tests/run_lxd.sh [<ver>...]
#   default versions: the ones the docker contract (tests/spread.yaml) covers.
# Needs the bread + bread-chisel-releases images for the host arch (make
# build-bread-chisel-releases ARCH=...), plus lxd, spread and python3.
set -euo pipefail

cd "$(dirname "$0")/.."

case "$(uname -m)" in
    x86_64)  arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *)
        echo "run_lxd: no LXD images for $(uname -m)" >&2
        exit 2
        ;;
esac
if [ "$#" -gt 0 ]; then
    vers=("$@")
else
    vers=(24.04 25.10 26.04 26.10)
fi
flavours=(bread bread-chisel-releases)
port="${BREAD_LXD_TEST_PORT:-8471}"

work=$(mktemp -d)
server=""
cleanup() {
    [ -z "$server" ] || kill "$server" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

for flavour in "${flavours[@]}"; do
    for ver in "${vers[@]}"; do
        hack/pack_lxd.sh "$flavour-$ver-$arch" "$work/serve"
    done
done

python3 -m http.server --bind 127.0.0.1 --directory "$work/serve" "$port" >/dev/null 2>&1 &
server=$!
for _ in $(seq 50); do
    curl -fs -o /dev/null "http://127.0.0.1:$port/" && break
    sleep 0.1
done

failed=()
for flavour in "${flavours[@]}"; do
    for ver in "${vers[@]}"; do
        echo "==> $flavour $ver ($arch) on LXD"
        project="$work/project-$flavour-$ver"
        mkdir -p "$project"
        cp "inlined/$flavour-$ver.yaml" "$project/spread.yaml"
        # Same layouts as tests/contract-*/run/task.yaml.
        case "$flavour" in
            bread)
                cp -r tests/_inner-bread/. "$project/tests"
                ;;
            bread-chisel-releases)
                mkdir -p "$project/tests/spread/integration" "$project/tests/spread/lib"
                cp -r tests/_inner-bread-chisel-releases/. "$project/tests/spread/integration"
                cp tests/lib/clean-rootfs "$project/tests/spread/lib/"
                ;;
        esac
        if ! (cd "$project" && BREAD_LXD_URL="http://127.0.0.1:$port" spread -v lxd:); then
            failed+=("$flavour-$ver")
        fi
        # allocate imported the pack under its fingerprint: proof that
        # pack_lxd.sh computes the one LXD does.
        fingerprint=$(cat "$work/serve/$flavour-$ver-$arch.lxd-fingerprint")
        if ! lxc image delete "$fingerprint"; then
            echo "no LXD image $fingerprint for $flavour-$ver-$arch" >&2
            failed+=("$flavour-$ver (fingerprint)")
        fi
    done
done

if [ "${#failed[@]}" -gt 0 ]; then
    echo "failed: ${failed[*]}" >&2
    exit 1
fi
echo "ok: ${flavours[*]} x ${vers[*]} on LXD ($arch)"
