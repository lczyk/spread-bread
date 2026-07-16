#!/usr/bin/env ruby
# Cross-compile chisel + spread + docker cli for all target arches inside a
# single Canonical ubuntu/go:1.25-26.04_edge container. Output binaries land
# in ./cache/binaries/{chisel,chisel-hacked,spread,docker}-<arch>.
#
# Required env vars (set by makefile):
#   CHISEL_REF        git ref (tag, branch, or SHA) for canonical/chisel
#   SPREAD_REF        git ref for canonical/spread
#   GO_BUILDER_IMAGE  builder image tag
#   DOCKER_VERSION    docker/cli tag (without leading "v")

require "fileutils"

Dir.chdir(File.expand_path("..", __dir__))

%w[CHISEL_REF SPREAD_REF GO_BUILDER_IMAGE DOCKER_VERSION].each do |var|
  if ENV[var].to_s.empty?
    warn "#{var}: required"
    exit 1
  end
end

chisel_ref       = ENV["CHISEL_REF"]
spread_ref       = ENV["SPREAD_REF"]
go_builder_image = ENV["GO_BUILDER_IMAGE"]
docker_version   = ENV["DOCKER_VERSION"]

FileUtils.mkdir_p("cache/binaries")

huid = Process.uid
hgid = Process.gid

# Builder runs natively on host arch and cross-compiles via GOARCH for the
# other arches; both binaries are pure Go (no CGO), so cross-compile is
# clean. This stays bash, not ruby: it runs *inside* GO_BUILDER_IMAGE, which
# has no ruby, and installing one there would add apt cost under qemu
# emulation for the non-native arches -- exactly what we trimmed elsewhere.
container_script = <<~'BASH'
  TARGET_ARCHES="amd64 arm64 s390x ppc64le"

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
      for arch in $TARGET_ARCHES; do
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
  )
  for p in "${patches[@]}"; do
      echo "==> applying patch: $(basename "$p")"
      git apply "$p"
  done
  CHISEL_HACKED_VERSION_STRING="${CHISEL_VERSION_STRING}-hacked"
  echo "==> chisel-hacked version string: $CHISEL_HACKED_VERSION_STRING"
  for arch in $TARGET_ARCHES; do
      echo "==> building chisel-hacked for $arch"
      CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
          go build -trimpath -ldflags "-s -w -X github.com/canonical/chisel/cmd.Version=$CHISEL_HACKED_VERSION_STRING" \
          -o "/out/chisel-hacked-$arch" ./cmd/chisel
  done
  cd /

  build spread https://github.com/canonical/spread  "$SPREAD_REF" ./cmd/spread

  # Build the docker CLI from source for each target arch. docker.com's
  # static tarballs only cover x86_64 / aarch64 at current versions (s390x /
  # ppc64le stopped at 18.06), and Ubuntu apt's docker.io is built with go
  # 1.24 and crashes under qemu emulation -- building from source with the
  # go 1.25 toolchain covers all arches uniformly. docker/cli has no go.mod
  # (vendor.mod + vendor/ instead); the symlink trick puts it in module mode.
  git clone https://github.com/docker/cli /src/docker-cli
  cd /src/docker-cli
  git checkout "v$DOCKER_VERSION"
  ln -s vendor.mod go.mod
  ln -s vendor.sum go.sum
  for arch in $TARGET_ARCHES; do
      echo "==> building docker cli for $arch"
      CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
          go build -mod=vendor -trimpath \
          -ldflags "-s -w -X github.com/docker/cli/cli/version.Version=$DOCKER_VERSION" \
          -o "/out/docker-$arch" ./cmd/docker
  done
  cd /

  # Hand ownership back to the invoking user so make can read/replace later.
  chown -R "$HUID:$HGID" /out
BASH

cmd = [
  "docker", "run", "--rm",
  "--entrypoint=/bin/bash",
  "-v", "#{Dir.pwd}/cache/binaries:/out",
  "-v", "#{Dir.pwd}/patches/chisel:/patches/chisel:ro",
  "-e", "CHISEL_REF=#{chisel_ref}",
  "-e", "SPREAD_REF=#{spread_ref}",
  "-e", "DOCKER_VERSION=#{docker_version}",
  "-e", "HUID=#{huid}",
  "-e", "HGID=#{hgid}",
  go_builder_image,
  "-ceuo", "pipefail",
  container_script,
]

# Array-form exec bypasses the shell entirely, so each element reaches
# docker's argv literally -- no quoting needed even though container_script
# is a multi-line string with embedded quotes. Replacing (not forking) means
# docker's own exit status becomes this script's exit status.
exec(*cmd)
