#!/bin/sh
# lazy-apt: on first non-update call, runs apt-get update then replaces both
# shims with symlinks to real apt. Installed at /usr/local/bin/apt and
# /usr/local/bin/apt-get (ahead of /usr/bin in PATH) so tests that call
# apt/apt-get without an explicit update still work after the image was built
# with apt lists wiped.
#
# Replaces with symlinks rather than deleting: bash hashes the shim path on
# first use, so deletion would leave a stale hash entry causing subsequent
# calls to fail with "No such file or directory".

real="/usr/bin/$(basename "$0")"

if [ "$1" != "update" ]; then
    /usr/bin/apt-get update
fi

ln -sf /usr/bin/apt     /usr/local/bin/apt
ln -sf /usr/bin/apt-get /usr/local/bin/apt-get

exec "$real" "$@"
