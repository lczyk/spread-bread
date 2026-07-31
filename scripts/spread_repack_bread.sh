# macOS tar packs an AppleDouble ._* sidecar next to every file and stores
# xattrs as pax headers; the sidecars unpack as real files on the remote and
# GNU tar warns about every xattr header. Repack to remove both.
if [ "$(uname -s)" = Darwin ]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    tar -xf - -C "$tmp" <&3
    ( cd "$tmp" && shopt -s dotglob && COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs -cf - -- * ) >&4
else
    cat <&3 >&4
fi
