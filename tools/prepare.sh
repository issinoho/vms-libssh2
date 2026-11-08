#!/usr/bin/env bash
# prepare.sh - build a VMS-ready libssh2 source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#   3. write the PCSI kit inputs
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
if [ -d "$stage/vms/kit" ]; then
step "PCSI kit inputs"
: "${KIT_PRODUCER:=ISSINOHO}"
# Three-part versions, as the family's other ports: the third part is the PCSI
# update and our VMS patch level the ECO, so 1.11.1-vms1 is V1.11-1E1.
IFS=. read -r major minor update _ <<< "$UPSTREAM_VERSION"
pcsiversion="V$major.$minor-${update:-0}E$VMS_PATCH_LEVEL"
kitversion="$UPSTREAM_VERSION-vms$VMS_PATCH_LEVEL"
kit=$stage/vms/kit
subst() {
    sed -e "s/@PRODUCER@/$KIT_PRODUCER/g" -e "s/@BASE@/$1/g" \
        -e "s/@PCSIVERSION@/$pcsiversion/g" -e "s/@VERSION@/$UPSTREAM_VERSION/g" \
        -e "s/@KITVERSION@/$kitversion/g" -e "s/@ARCH@/$2/g"
}
for base in I64VMS X86VMS AXPVMS; do
    subst $base "" < "$kit/libssh2.pcsi\$desc_template" > "$kit/LIBSSH2-$base.PCSI\$DESC"
    subst $base "" < "$kit/libssh2.pcsi\$text_template" > "$kit/LIBSSH2-$base.PCSI\$TEXT"
done
rm -f "$kit/libssh2.pcsi\$desc_template" "$kit/libssh2.pcsi\$text_template"
mv "$kit/libssh2\$startup.com" "$kit/LIBSSH2\$STARTUP.COM"
subst "" "IA64 and x86-64" < "$kit/readme.vms" > "$kit/README.VMS"; rm -f "$kit/readme.vms"
mkdir -p "$kit/doc"
cp "$stage/COPYING" "$kit/doc/COPYING."
cp "$stage/RELEASE-NOTES" "$kit/doc/RELEASE-NOTES."
printf 'KIT_PRODUCER=%s\nPCSI_VERSION=%s\nKIT_VERSION=%s\n' "$KIT_PRODUCER" "$pcsiversion" \
    "$kitversion" > "$kit/kit.env"
fi

step "staged $stage"
