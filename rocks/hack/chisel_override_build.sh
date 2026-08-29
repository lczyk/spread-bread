#!/usr/bin/env bash
# Build chisel + chisel-hacked from source (canonical/chisel @ $CHISEL_REF),
# native arch, into $CRAFT_PART_INSTALL/usr/local/bin. Mirrors the root repo's
# hack/build_binaries.sh, minus the cross-compile -- rockcraft builds natively
# per platform so GOARCH is just the host arch.
#
# Env (from the part's build-environment):
#   CHISEL_REF   git ref for canonical/chisel
set -euo pipefail

: "${CHISEL_REF:?required}"

# go.mod may demand a newer toolchain than the snap ships; let go fetch it.
export GOTOOLCHAIN=auto

out="$CRAFT_PART_INSTALL/usr/local/bin"
mkdir -p "$out"

src="$CRAFT_PART_BUILD/chisel-src"
git clone https://github.com/canonical/chisel "$src"
cd "$src"
git checkout "$CHISEL_REF"

# Inject the version string the way upstream's cmd/mkversion.sh would, so
# `chisel --version` reports the pinned tag instead of "unknown".
ver=$(git describe --tags --dirty --always)
echo "==> chisel version: $ver"

CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X github.com/canonical/chisel/cmd.Version=$ver" \
    -o "$out/chisel" ./cmd/chisel

# chisel-hacked: same source + the CHISEL_HACKS patches, -hacked version suffix.
for p in "$CRAFT_PROJECT_DIR"/patches/chisel/0001-*.patch \
         "$CRAFT_PROJECT_DIR"/patches/chisel/0002-*.patch \
         "$CRAFT_PROJECT_DIR"/patches/chisel/0003-*.patch; do
    echo "==> applying $(basename "$p")"
    git apply "$p"
done

CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X github.com/canonical/chisel/cmd.Version=${ver}-hacked" \
    -o "$out/chisel-hacked" ./cmd/chisel
