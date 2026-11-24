#!/bin/bash

set -e

echo "Discarding instance for system: $SPREAD_SYSTEM_ADDRESS"

# spread runs this with a fixed PATH, which leaves out homebrew on Apple Silicon.
PATH="$PATH:/opt/homebrew/bin"

# allocate records each instance's address in user.spread-bread-address.
instance=$(lxc list --format csv -c n,user.spread-bread-address user.spread-bread=true |
    awk -F, -v ip="$SPREAD_SYSTEM_ADDRESS" '$2 == ip { print $1; exit }')

if [ -n "$instance" ]; then
    echo "Removing instance: $instance"
    lxc delete --force "$instance"
else
    echo "No instance found with address: $SPREAD_SYSTEM_ADDRESS"
    exit 1
fi
