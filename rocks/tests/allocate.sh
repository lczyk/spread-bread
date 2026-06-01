#spellchecker: ignore noninteractive

set -e

# System name encodes flavour, version + arch, e.g.
#   bread-24.04-amd64                  -> dir=bread-24.04
#   bread-chisel-releases-26.04-arm64  -> dir=bread-chisel-releases-26.04
# Parse from the right so the hyphens in bread-chisel-releases don't trip us up.
name="$SPREAD_SYSTEM"
arch="${name##*-}"
rest="${name%-*}"
ver="${rest##*-}"
dir="${rest%-*}-$ver"

# The rock is loaded into the local daemon (by `make load` / the ci test job)
# under this tag before spread runs -- so allocate just `docker run`s it.
tag="spread-rock-$dir:latest"
echo "system: $name -> image: $tag"

# Unique container name per worker (flock counter pattern, cf. charmcraft).
sleep 0.$RANDOM
export counter_file=".spread-worker-num"
instance_num=$(
    flock -x $counter_file bash -c '
    [ -s $counter_file ] || echo 0 > $counter_file
    num=$(< $counter_file) && echo $num
    echo $(( $num + 1 )) > $counter_file'
)
container_name="${name}-${instance_num}"
echo "container: $container_name"

docker rm -f "$container_name" 2>/dev/null || true

# The rock runs pebble as pid 1, which starts the enabled sshd service.
docker run \
    --rm \
    --platform "linux/$arch" \
    --name "$container_name" \
    -d "$tag"

until docker exec "$container_name" pgrep sshd >/dev/null 2>&1; do sleep 1; done

ADDRESS "$(docker inspect "$container_name" --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')"
