# macOS tar packs an AppleDouble ._* sidecar next to every file; they unpack as
# real files on the remote. Repack to remove them.
if [ "$(uname -s)" = Darwin ]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    tar -xf - -C "$tmp" <&3
    ( cd "$tmp" && shopt -s dotglob && COPYFILE_DISABLE=1 tar -cf - -- * ) >&4
else
    cat <&3 >&4
fi
