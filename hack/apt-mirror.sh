#!/bin/sh -e
# bread-apt-mirror: build-time apt mirror override for docker build, which
# otherwise pulls from archive.ubuntu.com; on ci that is the slow path, while
# the runner itself uses the azure mirror. Same mirror, same failover shape:
# https://github.com/actions/runner-images/blob/main/images/ubuntu/scripts/build/configure-apt-sources.sh
# https://manpages.ubuntu.com/manpages/noble/en/man1/apt-transport-mirror.1.html
#
# Writes into the scratch dir $1 copies of the apt sources with the archive
# uris pointed at a mirrorlist ($APT_MIRROR first, archive.ubuntu.com second)
# plus an apt.conf that makes apt read those copies; the build exports
# APT_CONFIG=<dir>/apt.conf. The image's own /etc/apt is never touched.
# Without APT_MIRROR the apt.conf is empty and apt behaves as stock.
#
# Usage: bread-apt-mirror <scratch-dir>

dir="${1:?scratch dir required}"
mkdir -p "$dir/sources.list.d"
: > "$dir/apt.conf"
[ -n "${APT_MIRROR:-}" ] || exit 0

list="$dir/mirrors.txt"
printf '%s\tpriority:1\nhttp://archive.ubuntu.com/ubuntu/\tpriority:2\n' "$APT_MIRROR" > "$list"

: > "$dir/sources.list"
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    sed "s|http://archive\.ubuntu\.com/ubuntu/|mirror+file:$list|g" "$f" > "$dir/${f#/etc/apt/}"
done

printf 'Dir::Etc::sourcelist "%s/sources.list";\nDir::Etc::sourceparts "%s/sources.list.d";\n' "$dir" "$dir" > "$dir/apt.conf"
