#spellchecker: ignore noninteractice

set -e

flavour=$(echo "$SPREAD_SYSTEM" | cut -d- -f1)  # e.g., plucky-amd64 -> plucky
arch=$(echo "$SPREAD_SYSTEM" | cut -d- -f2)  # e.g., plucky-amd64 -> amd64
echo "flavour: $flavour"
echo "arch: $arch"

# precompiled docker images for amd64 and arm64
image="bread-sshd-$flavour-$arch"
echo "image: $image"

# Use a counter file to ensure unique container names
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

container_name="bread-${SPREAD_SYSTEM}-${instance_num}"
echo "container_name: $container_name"

docker run \
    --rm \
    --platform "linux/$arch" \
    -e DEBIAN_FRONTEND=noninteractice \
    -e "usr=$SPREAD_SYSTEM_USERNAME" \
    -e "pass=$SPREAD_SYSTEM_PASSWORD" \
    --name "$container_name" \
    -d "$image";

until docker exec "$container_name" pgrep sshd; do sleep 1; done

ADDRESS "$(docker inspect "$container_name" --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')"