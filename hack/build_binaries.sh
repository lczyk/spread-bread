#!/usr/bin/env bash
# Cross-compile chisel + spread for both target arches inside a single
# Canonical ubuntu/go:1.25-26.04_edge container. Output binaries land in
# ./cache/binaries/{chisel,chisel-hacked,spread}-{amd64,arm64}.
#
# Required env vars (set by makefile):
#   CHISEL_REF        git ref (tag, branch, or SHA) for canonical/chisel
#   SPREAD_REF        git ref for canonical/spread
#   GO_BUILDER_IMAGE  builder image tag
set -euo pipefail

cd "$(dirname "$0")/.."

: "${CHISEL_REF:?required}"
: "${SPREAD_REF:?required}"
: "${GO_BUILDER_IMAGE:?required}"
: "${DOCKER_VERSION:?required}"

mkdir -p cache/binaries

HUID=$(id -u)
HGID=$(id -g)

docker run --rm \
    --entrypoint=/bin/bash \
    -v "$(pwd)/cache/binaries:/out" \
    -v "$(pwd)/patches/chisel:/patches/chisel:ro" \
    -e CHISEL_REF="$CHISEL_REF" \
    -e SPREAD_REF="$SPREAD_REF" \
    -e DOCKER_VERSION="$DOCKER_VERSION" \
    -e HUID="$HUID" \
    -e HGID="$HGID" \
    "$GO_BUILDER_IMAGE" -ceuo pipefail '
# Builder runs natively on host arch and cross-compiles via GOARCH for
# the other arch. Both binaries are pure Go (no CGO), so cross-compile
# is clean.

# Canonical ubuntu/go image has /usr/bin/go as a broken symlink in some
# revisions; pick the actual go binary out of /usr/lib/go-*/bin.
GO_BIN_DIR=$(ls -d /usr/lib/go-*/bin 2>/dev/null | head -1)
if [ -n "$GO_BIN_DIR" ]; then
    export PATH="$GO_BIN_DIR:$PATH"
fi
# Allow go to auto-download a newer toolchain if go.mod demands one
# (image ships fixed minor; targets may need a fresher patch release).
export GOTOOLCHAIN=auto
go version

# Ensure git is available (the ubuntu/go image may not ship it).
if ! command -v git >/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git ca-certificates
fi

# Build helper. extra_ldflags is appended to the standard "-s -w".
build() {
    local name=$1 repo=$2 ref=$3 pkg=$4 extra_ldflags=${5:-}
    git clone "$repo" "/src/$name"
    cd "/src/$name"
    git checkout "$ref"
    for arch in amd64 arm64; do
        echo "==> building $name for $arch"
        CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
            go build -trimpath -ldflags "-s -w $extra_ldflags" \
            -o "/out/$name-$arch" "$pkg"
    done
}

# Inject chisel version into the binary via -X ldflags. Upstream sets this
# via cmd/mkversion.sh at build time; we get the same effect from
# git describe so `chisel --version` reports the pinned tag rather than
# the default "unknown".
( git clone https://github.com/canonical/chisel /src/chisel-vprobe >/dev/null 2>&1
  cd /src/chisel-vprobe && git checkout "$CHISEL_REF" >/dev/null 2>&1
  git describe --tags --dirty --always
) > /tmp/chisel-version 2>/dev/null
CHISEL_VERSION_STRING=$(cat /tmp/chisel-version)
echo "==> chisel version string: $CHISEL_VERSION_STRING"
rm -rf /src/chisel-vprobe

build chisel https://github.com/canonical/chisel  "$CHISEL_REF" ./cmd/chisel \
    "-X github.com/canonical/chisel/cmd.Version=$CHISEL_VERSION_STRING"

# Apply CHISEL_HACKS patches on top of the already-cloned source and build
# the hacked variant. Version string gets a -hacked suffix so `chisel-hacked
# --version` is distinguishable from the unpatched binary.
cd /src/chisel
patches=(
    /patches/chisel/0001-*.patch
    /patches/chisel/0002-*.patch
    /patches/chisel/0003-*.patch
    /patches/chisel/0004-*.patch
)
for p in "${patches[@]}"; do
    echo "==> applying patch: $(basename "$p")"
    git apply "$p"
done
CHISEL_HACKED_VERSION_STRING="${CHISEL_VERSION_STRING}-hacked"
echo "==> chisel-hacked version string: $CHISEL_HACKED_VERSION_STRING"
for arch in amd64 arm64; do
    echo "==> building chisel-hacked for $arch"
    CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
        go build -trimpath -ldflags "-s -w -X github.com/canonical/chisel/cmd.Version=$CHISEL_HACKED_VERSION_STRING" \
        -o "/out/chisel-hacked-$arch" ./cmd/chisel
done
cd /

build spread https://github.com/canonical/spread  "$SPREAD_REF" ./cmd/spread

# Ensure curl + tar present for the docker download step.
if ! command -v curl >/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl
fi

# Fetch the upstream docker static tarball for each target arch and extract
# only the docker CLI. Upstream binaries are built with a recent go toolchain
# (1.26+) and so dodge the qemu emulation bug that hits Ubuntu apt'\''s docker.io
# (built with go 1.24). docker.com uses uname-style arch names: aarch64,
# x86_64.
for arch in amd64 arm64; do
    case "$arch" in
        amd64) docker_arch=x86_64 ;;
        arm64) docker_arch=aarch64 ;;
    esac
    url="https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_VERSION}.tgz"
    echo "==> downloading docker $DOCKER_VERSION for $arch from $url"
    tmpdir=$(mktemp -d)
    curl -fsSL "$url" | tar -xz -C "$tmpdir" docker/docker
    install -m 0755 "$tmpdir/docker/docker" "/out/docker-$arch"
    rm -rf "$tmpdir"
done

# Hand ownership back to the invoking user so make can read/replace later.
chown -R "$HUID:$HGID" /out
'
