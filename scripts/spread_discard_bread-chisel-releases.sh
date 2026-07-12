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
        # publish mode: match the container by its published host port.
        target_port="${SPREAD_SYSTEM_ADDRESS##*:}"
        for cid in $(docker ps -a --format '{{.ID}}'); do
            if docker port "$cid" 22 2>/dev/null | grep -q ":${target_port}\$"; then
                container_name=$(docker inspect "$cid" --format '{{.Name}}' | sed 's#^/##')
                break
            fi
        done
        not_found="No container found with published port: $target_port"
        ;;
    *)
        # bridge mode: match the container by its bridge IP address.
        for cid in $(docker ps -a --filter "network=bridge" --format '{{.ID}}'); do
            cname=$(docker inspect "$cid" --format '{{.Name}}' | sed 's/^\/\(.*\)/\1/')
            cip=$(docker inspect "$cid" --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' || echo "")
            if [ "$cip" == "$SPREAD_SYSTEM_ADDRESS" ]; then
                container_name="$cname"
                break
            fi
        done
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
