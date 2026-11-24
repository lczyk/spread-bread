#!/usr/bin/env bash
# Pack one built image as an LXD split image, so LXD can run the very image
# docker does:
#   <out>/<name>.lxd-meta.tar.gz     metadata.yaml + templates
#   <out>/<name>.lxd-rootfs.tar.zst  the image's filesystem
#   <out>/<name>.lxd-fingerprint     the fingerprint LXD gives the pair
#
# The rootfs is what `docker export` gives, less the files docker manages at
# runtime. It boots with peel, which bread ships as /usr/sbin/init (= /sbin/init):
# peel brings up eth0 over DHCP, writes resolv.conf and runs the image's
# entrypoint + cmd, recorded here in /peel/state.json from the image config.
# state.json marks the image as already unpacked, so peel never pulls one.
#
# Split rather than unified (one tarball with the fs under rootfs/), so the
# export goes into the tarball as is: rewriting its paths would mean
# unpacking it, which takes root to keep ownership.
#
# Usage: pack_lxd.sh <flavour>-<ver>-<arch> <out-dir>
#   e.g. pack_lxd.sh bread-chisel-releases-26.04-amd64 lxd-out
# Linux only (GNU tar + date), like LXD itself.
set -euo pipefail

cd "$(dirname "$0")/.."

name="$1"
out="$2"
arch="${name##*-}"
rest="${name%-*}"
ver="${rest##*-}"
flavour="${rest%-*}"
image="$flavour:$ver-$arch"

case "$arch" in
    amd64)   lxd_arch=x86_64 ;;
    arm64)   lxd_arch=aarch64 ;;
    armhf)   lxd_arch=armv7l ;;
    s390x | ppc64le | riscv64) lxd_arch=$arch ;;
    *)
        echo "pack_lxd: no LXD architecture for $arch" >&2
        exit 2
        ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out" "$work/meta/templates" "$work/extra/peel"
chmod 0755 "$work/extra/peel"

echo "==> packing $image for LXD"

# The tag peel's config names (templates/peel-config.tpl below) and state.json
# records. They match, so peel skips the pull. Nothing ever resolves it.
ref=bread

# LXD lists the image under the date docker built it.
created=$(date -d "$(docker image inspect --format '{{.Created}}' "$image")" +%s)

docker image inspect --format \
    '{"reference":"'"$ref"'","runtime":{"entrypoint":{{json .Config.Entrypoint}},"cmd":{{json .Config.Cmd}},"env":{{json .Config.Env}},"working_dir":{{json .Config.WorkingDir}},"user":{{json .Config.User}}}}' \
    "$image" > "$work/extra/peel/state.json"

# docker export takes a container, not an image; this one never starts.
# The files docker bind-mounts at runtime are empty placeholders in the export,
# dropped on the way through: LXD's templates write /etc/hostname + /etc/hosts,
# peel /etc/resolv.conf. Deleting in place corrupts the archive with the tar
# of ubuntu 24.04.
cid=$(docker create --platform "$(hack/build_config.rb --platform "$arch")" "$image")
docker export "$cid" |
    tar --delete -f - .dockerenv etc/hostname etc/hosts etc/resolv.conf > "$work/rootfs.tar"
docker rm "$cid" >/dev/null
tar --append -f "$work/rootfs.tar" --owner=0 --group=0 --numeric-owner -C "$work/extra" peel
zstd -q -T0 -f "$work/rootfs.tar" -o "$out/$name.lxd-rootfs.tar.zst"

cat > "$work/meta/metadata.yaml" <<EOF
architecture: $lxd_arch
creation_date: $created
properties:
  os: ubuntu
  release: "$ver"
  architecture: $arch
  variant: $flavour
  description: spread-bread $flavour $ver $arch
templates:
  /etc/hostname:
    when: [create, copy]
    template: hostname.tpl
  /etc/hosts:
    when: [create, copy]
    template: hosts.tpl
  # peel deletes its config once it has read it, so render it on every start.
  /peel/config.json:
    when: [create, copy, start]
    template: peel-config.tpl
EOF
echo '{{ container.name }}' > "$work/meta/templates/hostname.tpl"
cat > "$work/meta/templates/hosts.tpl" <<'EOF'
127.0.0.1 localhost
127.0.1.1 {{ container.name }}
::1 localhost ip6-localhost ip6-loopback
EOF
echo "{\"image\":\"$ref\"}" > "$work/meta/templates/peel-config.tpl"

tar -C "$work/meta" --owner=0 --group=0 --numeric-owner -czf "$out/$name.lxd-meta.tar.gz" \
    metadata.yaml templates

# LXD fingerprints a split image as the sha256 of its two files in a row.
cat "$out/$name.lxd-meta.tar.gz" "$out/$name.lxd-rootfs.tar.zst" | sha256sum | cut -d' ' -f1 \
    > "$out/$name.lxd-fingerprint"

echo "==> $out/$name.lxd-{meta.tar.gz,rootfs.tar.zst} ($(cat "$out/$name.lxd-fingerprint"))"
