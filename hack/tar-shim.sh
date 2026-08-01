#!/bin/sh
# tar-shim: routes extraction to bsdtar on hosts where GNU tar cannot do it.
#
# Installed as /usr/bin/tar, with the real binary diverted to
# /usr/bin/tar.distrib. It has to sit on that path rather than earlier in
# PATH because spread invokes /bin/tar by absolute path.
#
# Ubuntu's patched tar (26.04 ships 1.35+dfsg-4ubuntu0.x) resolves extraction
# paths through a syscall Docker Desktop's Rosetta emulation does not
# implement, so in an amd64 container on Apple Silicon every entry below the
# top level fails with ENOSYS -- which spread reports as "cannot send project
# content", then as a failure to allocate the system. bsdtar is unaffected.
#
# Only extraction is routed: bsdtar has no --sort=name, which spread passes
# when packing artifacts. The probe runs once per container, so on unaffected
# hosts every call is plain GNU tar.

_real=/usr/bin/tar.distrib
_checked=/run/bread-tar-checked
_broken=/run/bread-tar-broken

_extracting() {
    # Bare mode letters are only valid as the first argument; elsewhere an x
    # is just as likely to be an option's value.
    case "$1" in
        (x*) return 0 ;;
    esac
    for _a in "$@"; do
        case "$_a" in
            (--) return 1 ;;
            (--extract|--get) return 0 ;;
            (--*) ;;
            (-*x*) return 0 ;;
        esac
    done
    return 1
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

# Reports which backend extraction would use, and warms the probe cache. The
# allocate scripts call it so the fallback shows up in the spread log instead
# of happening silently.
if [ "$1" = --bread-probe ]; then
    if command -v bsdtar >/dev/null 2>&1 && _gnu_tar_broken; then
        echo bsdtar
    else
        echo gnu
    fi
    exit 0
fi

if _extracting "$@" && command -v bsdtar >/dev/null 2>&1 && _gnu_tar_broken; then
    # bsdtar has no bare mode letters, and spread sends with `tar xz`.
    case "$1" in
        (-*) ;;
        (*) _mode="-$1"; shift; set -- "$_mode" "$@" ;;
    esac
    exec bsdtar --no-xattrs --no-mac-metadata "$@"
fi

exec "$_real" "$@"
