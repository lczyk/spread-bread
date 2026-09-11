#!/bin/sh -e
# bread-apt-mirror: build-time apt mirror override. `on` points the archive
# sources at a mirrorlist that tries $APT_MIRROR first and archive.ubuntu.com
# second; `off` puts the original sources back so the shipped image keeps the
# defaults. No-op without APT_MIRROR.
#
# The mirrorlist shape (mirror+file: with priorities, failover to the main
# archive) follows what GitHub's hosted runners configure for themselves:
# https://github.com/actions/runner-images/blob/main/images/ubuntu/scripts/build/configure-apt-sources.sh
# Semantics: https://manpages.ubuntu.com/manpages/noble/en/man1/apt-transport-mirror.1.html
#
# Usage: bread-apt-mirror on|off

[ -n "${APT_MIRROR:-}" ] || exit 0

list=/etc/apt/apt-mirrors.txt
sources=$(find /etc/apt -maxdepth 2 -type f \( -name sources.list -o -name '*.sources' \))

case "${1:-}" in
    on)
        printf '%s\tpriority:1\nhttp://archive.ubuntu.com/ubuntu/\tpriority:2\n' "$APT_MIRROR" > "$list"
        for f in $sources; do
            cp -p "$f" "$f.bread-orig"
            sed -i "s|http://archive\.ubuntu\.com/ubuntu/|mirror+file:$list|g" "$f"
        done
        ;;
    off)
        for f in $sources; do
            mv "$f.bread-orig" "$f"
        done
        rm -f "$list"
        ;;
    *)
        printf 'usage: bread-apt-mirror on|off\n' >&2
        exit 2
        ;;
esac
