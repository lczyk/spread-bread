set -e

ver=$(echo "$SPREAD_SYSTEM" | cut -d- -f2)   # e.g., ubuntu-24.04-amd64 -> 24.04
arch=$(echo "$SPREAD_SYSTEM" | cut -d- -f3)  # e.g., ubuntu-24.04-amd64 -> amd64
echo "ver: $ver"
echo "arch: $arch"

image="ghcr.io/lczyk/spread-bread/bread-chisel-releases:$ver"
echo "image: $image"

# Networking mode: how spread reaches the container's sshd.
#   bridge  -- connect to the container's docker bridge IP. Works where the host
#              shares the docker bridge network (linux native), so 172.17.x.x is
#              routable from the spread host.
#   publish -- publish sshd to 127.0.0.1:<ephemeral host port> and connect there.
#              Needed where the bridge IP is not host-routable, e.g. Docker
#              Desktop on macOS (docker runs in a VM).
# Default is per-OS; override with BREAD_NET=bridge|publish.
mode="${BREAD_NET:-}"
if [ -z "$mode" ]; then
    case "$(uname -s)" in
        Darwin) mode=publish ;;
        *)      mode=bridge ;;
    esac
fi
case "$mode" in
    bridge|publish) ;;
    *) echo "BREAD_NET must be 'bridge' or 'publish', got: '$mode'" >&2; exit 1 ;;
esac
echo "net mode: $mode"

if [ "$mode" = bridge ]; then
    sleep 0.$RANDOM  # Minimize chances of a race condition
    export counter_file=".spread-worker-num"
    instance_num=$(
        flock -x $counter_file bash -c '
        [ -s $counter_file ] || echo 0 > $counter_file
        num=$(< $counter_file) && echo $num
        echo $(( $num + 1 )) > $counter_file'
    )
    container_name="bread-chisel-releases-${ver}-${arch}-${instance_num}"
    publish_flag=""
else
    # publish mode: no shared counter file (no flock dependency); a pid+RANDOM
    # suffix is unique enough for a name. Docker picks the free host port.
    container_name="bread-chisel-releases-${ver}-${arch}-$$-${RANDOM}"
    publish_flag="-p 127.0.0.1::22"
fi
echo "container_name: $container_name"

docker run \
    --rm \
    --platform "linux/$arch" \
    --privileged \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e DEBIAN_FRONTEND=noninteractive \
    -e "usr=$SPREAD_SYSTEM_USERNAME" \
    -e "pass=$SPREAD_SYSTEM_PASSWORD" \
    $publish_flag \
    --name "$container_name" \
    -d "$image"

until docker exec "$container_name" pgrep sshd; do sleep 1; done

if [ "$mode" = publish ]; then
    # The ephemeral host port docker mapped to the container's sshd.
    port=$(docker port "$container_name" 22 | head -n1 | cut -d: -f2)
    [ -n "$port" ] || { echo "could not find published sshd port for $container_name" >&2; exit 1; }
    ADDRESS "127.0.0.1:$port"
else
    ADDRESS "$(docker inspect "$container_name" --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')"
fi
