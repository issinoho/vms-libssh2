#!/usr/bin/env bash
# prepare.sh - build a VMS-ready libssh2 source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#
# libssh2 has no configure on VMS: vms/libssh2_config.h (upstream's, patched)
# is the configuration and [.VMS]BUILD.COM compiles src/Makefile.inc's CSOURCES.
# Nothing in staging/ is ever edited by hand: fix things in patches/ or overlay/.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
tarball=$top/cache/$(basename "$UPSTREAM_URL")
stage=$top/staging/$name

step() { echo "prepare: $*"; }
die() { echo "prepare: error: $*" >&2; exit 1; }

"$top/tools/fetch.sh" >/dev/null

step "extracting $name"
rm -rf "$stage"; mkdir -p "$top/staging"
tar -xzf "$tarball" -C "$top/staging"
[ -d "$stage" ] || die "tarball did not unpack to $stage"

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    step "patch $p"
    patch -d "$stage" -p1 -s --no-backup-if-mismatch -F0 < "$top/patches/$p" ||
        die "patch $p does not apply cleanly"
done < "$top/patches/series"

(cd "$top/overlay" && find . -type f) | while read -r f; do
    [ -e "$stage/$f" ] && die "overlay/$f would replace an upstream file; use a patch"
    true
done
cp -a "$top/overlay/." "$stage/"

step "source list"
# CSOURCES from src/Makefile.inc, one name per line, for BUILD.COM.
sed -n '/^CSOURCES *=/,/^$/p' "$stage/src/Makefile.inc" | tr -d '\\' | tr ' ' '\n' |
    sed -n 's/^\([a-z0-9_-]*\)\.c$/\1/p' > "$stage/vms/sources.txt"
step "$(wc -l < "$stage/vms/sources.txt") library sources"
step "staged $stage"
