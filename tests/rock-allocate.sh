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

ip=$(docker inspect "$container_name" --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')

# Bounded wait for sshd to actually accept TCP on :22 (pgrep is not enough -- a
# process can exist without listening). On timeout, dump pebble/sshd output so
# ci shows WHY sshd isn't listening, then fail fast instead of letting spread
# spin to the kill-timeout.
ready=
for _ in $(seq 1 60); do
    if timeout 1 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 1
done

if [ -z "$ready" ]; then
    echo "ERROR: sshd not listening on $container_name ($ip:22) after 60s" >&2
    echo "--- docker logs $container_name ---" >&2
    docker logs "$container_name" >&2 2>&1 || true
    echo "--- pebble services + sshd -t + sshd bits ---" >&2
    docker exec "$container_name" sh -c 'pgrep -a sshd; /usr/sbin/sshd -t; ls -l /usr/sbin/sshd /usr/lib/openssh /run/sshd /etc/ssh' >&2 2>&1 || true
    docker rm -f "$container_name" >/dev/null 2>&1 || true
    exit 1
fi

ADDRESS "$ip"
