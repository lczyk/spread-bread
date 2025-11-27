#!/bin/bash

set -e

# Remove all containers that match the pattern $SPREAD_SYSTEM-*
# This handles multiple workers for the same system
docker ps -a --filter "name=^${SPREAD_SYSTEM}-" --format '{{.Names}}' | while read -r container; do
    if [ -n "$container" ]; then
        echo "Removing container: $container"
        docker rm -f "$container" 2>/dev/null || true
    fi
done
