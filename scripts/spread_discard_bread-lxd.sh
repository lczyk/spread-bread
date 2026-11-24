#!/bin/bash

set -e

echo "Discarding instance for system: $SPREAD_SYSTEM_ADDRESS"

# allocate labels its instances user.spread-bread=true; match ours by address.
instance=$(lxc list --format csv -c n4 user.spread-bread=true |
    awk -F, -v ip="$SPREAD_SYSTEM_ADDRESS" '{ split($2, a, " ") } a[1] == ip { print $1; exit }')

if [ -n "$instance" ]; then
    echo "Removing instance: $instance"
    lxc delete --force "$instance"
else
    echo "No instance found with IP address: $SPREAD_SYSTEM_ADDRESS"
    exit 1
fi
