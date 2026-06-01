#!/bin/sh
# lazy-apt: on first non-update call, runs apt-get update then self-destructs.
# Installed at /usr/local/bin/apt and /usr/local/bin/apt-get (ahead of /usr/bin
# in PATH) so tests that apt-install without an explicit update still work after
# the image was built with apt lists wiped.

real="/usr/bin/$(basename "$0")"

if [ "$1" != "update" ]; then
    /usr/bin/apt-get update
fi

rm -f /usr/local/bin/apt /usr/local/bin/apt-get

exec "$real" "$@"
