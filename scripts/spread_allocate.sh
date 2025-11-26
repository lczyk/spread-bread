#spellchecker: ignore noninteractice

set -e

flavour=$(echo "$SPREAD_SYSTEM" | cut -d- -f1)  # e.g., plucky-amd64 -> plucky
arch=$(echo "$SPREAD_SYSTEM" | cut -d- -f2)  # e.g., plucky-amd64 -> amd64
echo "flavour: $flavour"
echo "arch: $arch"

# precompiled docker images for amd64 and arm64
image="sshd-$flavour-$arch"
echo "image: $image"

# Allocate a unique worker number using file locking
worker_lock_file=".spread-worker-lock"
worker_num_file=".spread-worker-num"

# Create lock file if it doesn't exist
touch "$worker_lock_file"

# Acquire exclusive lock and get next worker number
exec 200>"$worker_lock_file"
flock 200

# Read current number or initialize to 0
if [ -f "$worker_num_file" ]; then
    worker_num=$(cat "$worker_num_file")
else
    worker_num=0
fi

# Increment for this worker
worker_num=$((worker_num + 1))
echo "$worker_num" > "$worker_num_file"

# Release lock
flock -u 200

# Append worker number to container name
container_name="${SPREAD_SYSTEM}-${worker_num}"
echo "container_name: $container_name"

# remove any existing container with the same name
docker rm -f "$container_name" 2>/dev/null || true

docker run \
    --rm \
    --platform "linux/$arch" \
    -e DEBIAN_FRONTEND=noninteractice \
    -e "usr=$SPREAD_SYSTEM_USERNAME" \
    -e "pass=$SPREAD_SYSTEM_PASSWORD" \
    --name "$container_name" \
    -d "$image";

ADDRESS "$(docker inspect "$container_name" --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')"