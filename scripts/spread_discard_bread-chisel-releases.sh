#!/bin/bash

set -e

echo "Discarding container for system: $SPREAD_SYSTEM_ADDRESS"

container_name=""
for cid in $(docker ps -a --filter "network=bridge" --format '{{.ID}}'); do
    cname=$(docker inspect "$cid" --format '{{.Name}}' | sed 's/^\/\(.*\)/\1/')
    cip=$(docker inspect "$cid" --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' || echo "")
    if [ "$cip" == "$SPREAD_SYSTEM_ADDRESS" ]; then
        container_name="$cname"
        break
    fi
done

if [ -n "$container_name" ]; then
    echo "Removing container: $container_name"
    docker rm -f "$container_name" 2>/dev/null || true
else
    echo "No container found with IP address: $SPREAD_SYSTEM_ADDRESS"
    exit 1
fi
