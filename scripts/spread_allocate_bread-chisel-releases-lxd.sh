set -e

flavour=bread-chisel-releases
ver=$(echo "$SPREAD_SYSTEM" | cut -d- -f2)   # e.g., ubuntu-24.04 -> 24.04
# LXD runs containers of the host's arch only, so the system name has none.
case "$(uname -m)" in
    x86_64)  arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) FATAL "no $flavour LXD image for $(uname -m)" ;;
esac
name="$flavour-$ver-$arch"
echo "image: $name"

# The images are release assets: a split LXD image (see hack/pack_lxd.sh) and
# its fingerprint. BREAD_LXD_URL serves them from elsewhere, e.g. a local
# directory of hack/pack_lxd.sh output over http.
base="${BREAD_LXD_URL:-https://github.com/lczyk/spread-bread/releases/latest/download}/$name"
fingerprint=$(curl -fsSL "$base.lxd-fingerprint")
[ -n "$fingerprint" ] || FATAL "no fingerprint at $base.lxd-fingerprint"

# Workers allocate in parallel: one imports, the rest wait for it.
lock="${TMPDIR:-/tmp}/spread-bread-lxd-$name.lock"
(
    flock -x 9
    lxc image info "$fingerprint" >/dev/null 2>&1 && exit 0
    # A snap-confined lxc reads files only from a few places, its own
    # per-user dir among them.
    dl_root="$HOME/snap/lxd/common"
    [ -d "$dl_root" ] || dl_root="${TMPDIR:-/tmp}"
    dl=$(mktemp -d -p "$dl_root")
    trap 'rm -rf "$dl"' EXIT
    echo "downloading $name ($fingerprint)"
    curl -fsSL -o "$dl/meta.tar.gz" "$base.lxd-meta.tar.gz"
    curl -fsSL -o "$dl/rootfs.tar.zst" "$base.lxd-rootfs.tar.zst"
    lxc image import "$dl/meta.tar.gz" "$dl/rootfs.tar.zst" >/dev/null
    # Drop the copies of this image older releases left behind.
    lxc image list --format csv -c fd | while IFS=, read -r short desc; do
        if [ "$desc" = "spread-bread $flavour $ver $arch" ] && [ "${fingerprint#"$short"}" = "$fingerprint" ]; then
            lxc image delete "$short" || true
        fi
    done
) 9>"$lock"
lxc image info "$fingerprint" >/dev/null 2>&1 ||
    FATAL "$base.lxd-* changed while downloading; try again"

instance="$flavour-${ver//./}-$$-$RANDOM"
echo "instance: $instance"
lxc launch --ephemeral "$fingerprint" "$instance" -c user.spread-bread=true >/dev/null

fail() {
    echo "$1" >&2
    lxc console "$instance" --show-log >&2 2>&1 || true
    lxc delete --force "$instance" >/dev/null 2>&1 || true
    # A plain exit 1 has spread retry the allocation for 5 minutes; FATAL does not.
    FATAL "$1"
}

# peel brings eth0 up over DHCP and starts sshd within a second or two.
addr=""
for ((i = 0; i < 120; i++)); do
    addr=$(lxc list --format csv -c n4 user.spread-bread=true |
        awk -F, -v n="$instance" '$1 == n { split($2, a, " "); print a[1]; exit }')
    [ -n "$addr" ] && break
    [ "$(lxc list --format csv -c ns user.spread-bread=true | awk -F, -v n="$instance" '$1 == n { print $2 }')" = RUNNING ] ||
        fail "$instance is not running"
    sleep 0.5
done
[ -n "$addr" ] || fail "$instance got no IPv4 address in 60s"

if command -v ssh-keyscan >/dev/null 2>&1; then
    handshake=""
    for ((i = 0; i < 30; i++)); do
        if ssh-keyscan -T 2 -t ed25519 "$addr" 2>/dev/null | grep -q .; then
            handshake=1
            break
        fi
        sleep 0.5
    done
    [ -n "$handshake" ] || fail "sshd in $instance is running but no ssh handshake completes"
fi

ADDRESS "$addr"
