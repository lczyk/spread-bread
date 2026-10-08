#!/bin/bash
# tar-shim: routes tar to bsdtar on hosts where GNU tar cannot do the job.
#
# Installed as /usr/bin/tar, with the real binary diverted to
# /usr/bin/tar.distrib. It has to sit on that path rather than earlier in
# PATH because spread invokes /bin/tar by absolute path.
#
# Ubuntu's patched tar (26.04 ships 1.35+dfsg-4ubuntu0.x) resolves paths
# through a syscall Docker Desktop's Rosetta emulation does not implement, so
# in an amd64 container on Apple Silicon anything below the top level fails
# with ENOSYS -- extracting a nested entry, and creating an archive from a
# member name with a directory component alike. bsdtar is unaffected.
#
# The probe runs once per container, so on unaffected hosts every call is
# plain GNU tar.

_real=/usr/bin/tar.distrib
# Keyed by kernel boot id + arch: /run is an ordinary directory in an image
# layer, so a verdict cached while the image was being built would otherwise
# be trusted forever, on every machine that pulls it.
_marker="/run/bread-tar.$(uname -m).$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
_checked="$_marker.checked"
_broken="$_marker.broken"

_mode() {
    # Bare mode letters are only valid as the first argument; elsewhere an x
    # or a c is as likely to be some option's value.
    case "$1" in
        (x*) echo x; return ;;
        (c*) echo c; return ;;
    esac
    for _a in "$@"; do
        case "$_a" in
            (--) return ;;
            (--extract|--get) echo x; return ;;
            (--create) echo c; return ;;
            (--*) ;;
            (-*x*) echo x; return ;;
            (-*c*) echo c; return ;;
        esac
    done
}

_gnu_tar_broken() {
    [ -e "$_broken" ] && return 0
    [ -e "$_checked" ] && return 1

    _d=$(mktemp -d) || return 1
    _bad=0
    mkdir -p "$_d/a/b" && : > "$_d/a/b/f" \
        && "$_real" -cf "$_d/t.tar" -C "$_d" a && rm -rf "$_d/a" \
        && "$_real" -xf "$_d/t.tar" -C "$_d" 2>/dev/null && [ -f "$_d/a/b/f" ] \
        || _bad=1
    rm -rf "$_d"

    # Markers are a cache; a read-only /run just means every call probes.
    : > "$_checked" 2>/dev/null
    [ "$_bad" = 0 ] && return 1
    : > "$_broken" 2>/dev/null
    return 0
}

# Reports which backend would be used, and warms the probe cache. The allocate
# scripts call it so the fallback shows up in the spread log instead of
# happening silently.
if [ "$1" = --bread-probe ]; then
    if command -v bsdtar >/dev/null 2>&1 && _gnu_tar_broken; then
        echo bsdtar
    else
        echo gnu
    fi
    exit 0
fi

_bsdtar_mode=$(_mode "$@")
if [ -n "$_bsdtar_mode" ] && command -v bsdtar >/dev/null 2>&1 && _gnu_tar_broken; then
    # bsdtar has no bare mode letters, and spread sends with `tar xz`.
    case "$1" in
        (-*) ;;
        (*) _first="-$1"; shift; set -- "$_first" "$@" ;;
    esac

    # -a tar so diagnostics read as tar:, not bsdtar: or tar.distrib:.
    if [ "$_bsdtar_mode" = x ]; then
        exec -a tar bsdtar --no-xattrs --no-mac-metadata "$@"
    fi

    # Creating: bsdtar has no equivalent of these, and refuses to run when
    # given them. Dropping --sort costs archive-order determinism, and
    # --ignore-failed-read costs a nonzero exit on unreadable members; both
    # beat not producing an archive at all.
    _args=()
    for _a in "$@"; do
        case "$_a" in
            (--sort=*|--ignore-failed-read)
                echo "tar: dropping $_a: not supported by the bsdtar fallback" >&2 ;;
            (*) _args+=("$_a") ;;
        esac
    done
    # --format first, so an explicit --format from the caller still wins.
    exec -a tar bsdtar --format=gnutar "${_args[@]}"
fi

exec -a tar "$_real" "$@"
