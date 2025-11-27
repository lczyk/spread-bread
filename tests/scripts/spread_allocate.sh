#spellchecker: ignore noninteractice

set -e

flavour=$(echo "$SPREAD_SYSTEM" | cut -d- -f1)  # e.g., plucky-amd64 -> plucky
arch=$(echo "$SPREAD_SYSTEM" | cut -d- -f2)  # e.g., plucky-amd64 -> amd64
echo "flavour: $flavour"
echo "arch: $arch"

# precompiled docker images for amd64 and arm64
image="sshd-$flavour-$arch"
echo "image: $image"

# Add random suffix to container name for uniqueness
random_suffix=$(head /dev/urandom | tr -dc a-f0-9 | head -c8)
container_name="${SPREAD_SYSTEM}-${random_suffix}"
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