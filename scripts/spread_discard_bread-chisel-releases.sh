#!/bin/bash

set -e

echo "Discarding container for system: $SPREAD_SYSTEM_ADDRESS"

# The address format tells us how the container was allocated (see the allocate
# script's BREAD_NET modes): "host:port" -> publish mode, bare IP -> bridge mode.
# Inferring from the address makes discard robust even if BREAD_NET is flipped
# between allocate and discard.
container_name=""
case "$SPREAD_SYSTEM_ADDRESS" in
    *:*)
        # publish mode: match the container by its published host port, as it
        # shows up in the ports column, e.g. "127.0.0.1:32768->22/tcp".
        target_port="${SPREAD_SYSTEM_ADDRESS##*:}"
        container_name=$(docker ps -a --filter label=spread-bread --format '{{.Names}} {{.Ports}}' |
            awk -v m=":${target_port}->22/" 'index($0, m) { print $1; exit }')
        not_found="No container found with published port: $target_port"
        ;;
    *)
        # bridge mode: match the container by its bridge IP address.
        ids=$(docker ps -a --filter label=spread-bread --filter network=bridge --format '{{.ID}}')
        if [ -n "$ids" ]; then
            container_name=$(docker inspect $ids --format '{{.Name}} {{.NetworkSettings.Networks.bridge.IPAddress}}' |
                awk -v ip="$SPREAD_SYSTEM_ADDRESS" '$2 == ip { print substr($1, 2); exit }')
        fi
        not_found="No container found with IP address: $SPREAD_SYSTEM_ADDRESS"
        ;;
esac

if [ -n "$container_name" ]; then
    echo "Removing container: $container_name"
    docker rm -f "$container_name" 2>/dev/null || true
else
    echo "$not_found"
    exit 1
fi
