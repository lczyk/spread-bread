# macOS tar packs an AppleDouble ._* sidecar next to every file; they unpack as
# real files on the remote. `exclude:` can't drop them (tar synthesises them
# below its glob filter), so extract and repack with COPYFILE_DISABLE=1.
# Spread hands the raw pre-gzip tar stream on fd 3 and takes the replacement
# on fd 4.
if [ "$(uname -s)" = Darwin ]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    tar -xf - -C "$tmp" <&3
    # `-- *` + dotglob rather than `.`: retarring `.` emits a ./ entry carrying
    # mktemp's 0700, which would chmod $SPREAD_PATH on the remote.
    ( cd "$tmp" && shopt -s dotglob && COPYFILE_DISABLE=1 tar -cf - -- * ) >&4
else
    cat <&3 >&4
fi
