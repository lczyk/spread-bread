#!/bin/bash

set -e

echo "Discarding instance for system: $SPREAD_SYSTEM_ADDRESS"

# allocate records each instance's address in user.spread-bread-address.
instance=$(lxc list --format csv -c n,user.spread-bread-address user.spread-bread=true |
    awk -F, -v ip="$SPREAD_SYSTEM_ADDRESS" '$2 == ip { print $1; exit }')

if [ -n "$instance" ]; then
    echo "Removing instance: $instance"
    lxc delete --force "$instance"
else
    echo "No instance found with IP address: $SPREAD_SYSTEM_ADDRESS"
    exit 1
fi
