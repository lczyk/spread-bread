#spellchecker: ignore noninteractice

set -e

ver=$(echo "$SPREAD_SYSTEM" | cut -d- -f2)   # e.g., ubuntu-24.04-amd64 -> 24.04
arch=$(echo "$SPREAD_SYSTEM" | cut -d- -f3)  # e.g., ubuntu-24.04-amd64 -> amd64
echo "ver: $ver"
echo "arch: $arch"

image="ghcr.io/lczyk/spread-bread/bread:$ver"
echo "image: $image"

# Use a counter file to ensure unique container names.
# snippet thanks to @lengau
# https://github.com/canonical/charmcraft/blob/120a00a50f7ed3d0ae2fc2bea69e2e43b68b1594/spread.yaml#L72-L79
sleep 0.$RANDOM  # Minimize chances of a race condition
export counter_file=".spread-worker-num"
instance_num=$(
    flock -x $counter_file bash -c '
    [ -s $counter_file ] || echo 0 > $counter_file
    num=$(< $counter_file) && echo $num
    echo $(( $num + 1 )) > $counter_file'
)

container_name="bread-${ver}-${arch}-${instance_num}"
echo "container_name: $container_name"

docker run \
    --rm \
    --platform "linux/$arch" \
    -e DEBIAN_FRONTEND=noninteractice \
    -e "usr=$SPREAD_SYSTEM_USERNAME" \
    -e "pass=$SPREAD_SYSTEM_PASSWORD" \
    --name "$container_name" \
    -d "$image"

until docker exec "$container_name" pgrep sshd; do sleep 1; done

ADDRESS "$(docker inspect "$container_name" --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')"
