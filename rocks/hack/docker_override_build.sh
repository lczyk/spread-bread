#!/usr/bin/env bash
# Fetch the upstream docker static CLI for the build-for arch and drop it at
# /usr/local/bin/docker. Upstream's static build uses a recent go toolchain and
# so dodges the qemu emulation bug that hits ubuntu apt's docker.io (go 1.24).
#
# Env (from the part's build-environment):
#   DOCKER_VERSION   docker static release version
set -euo pipefail

: "${DOCKER_VERSION:?required}"

# docker.com static uses uname-style arch names.
case "$CRAFT_ARCH_BUILD_FOR" in
    amd64) docker_arch=x86_64 ;;
    arm64) docker_arch=aarch64 ;;
    *) echo "unsupported arch: $CRAFT_ARCH_BUILD_FOR" >&2; exit 1 ;;
esac

out="$CRAFT_PART_INSTALL/usr/local/bin"
mkdir -p "$out"

url="https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_VERSION}.tgz"
echo "==> downloading docker $DOCKER_VERSION for $CRAFT_ARCH_BUILD_FOR from $url"

tmp=$(mktemp -d)
curl -fsSL "$url" | tar -xz -C "$tmp" docker/docker
install -m0755 "$tmp/docker/docker" "$out/docker"
rm -rf "$tmp"
