#!/usr/bin/env bash
# push.sh <node> - upload the prepared tree (staging/) to <node>'s work directory,
# into <workdir>/<name>-<version with dots as underscores>, e.g. [.LIBSSH2-1_11_1].
# Only files whose content changed since the last push are uploaded.
set -euo pipefail
export LC_ALL=C

top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: push.sh <node>}
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
stage=$top/staging/$name
remote=$(echo "$name" | tr . _)
[ -d "$stage/vms" ] || { echo "push: run tools/prepare.sh first" >&2; exit 1; }

pack=$top/cache/push-$name-$node
rm -rf "$pack"; mkdir -p "$pack/$remote"
cp -a "$stage/include" "$stage/src" "$stage/vms" "$stage/COPYING" "$pack/$remote/"

echo "push: -> $node:[.$(echo "$remote" | tr a-z A-Z)]"
read -r _ _ HOST PORT USER WORKDIR SFTPDIR < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
manifest=$top/cache/pushed-$name-$node.sha
[ "${PUSH_ALL:-}" = 1 ] && rm -f "$manifest"
touch "$manifest"
(cd "$pack" && find "$remote" -type f -print0 | sort -z | xargs -0 sha256sum) > "$pack.sha"
changed=$(comm -23 <(awk '{print $2" "$1}' "$pack.sha" | sort) \
                   <(awk '{print $2" "$1}' "$manifest" | sort) | awk '{print $1}')
echo "push: $(echo "$changed" | grep -c . || true) changed of $(wc -l < "$pack.sha") files"
batch=$pack/sftp.batch
{
    echo "cd $SFTPDIR"
    (cd "$pack" && find "$remote" -type d) | sed 's/^/-mkdir /'
    for f in $changed; do echo "put $pack/$f $f"; done
} > "$batch"
sftp -P "$PORT" -i "${VMS_SSH_KEY:-$HOME/.ssh/vms_ed25519}" -o BatchMode=yes -b "$batch" "$USER@$HOST" \
    2>&1 >/dev/null | grep -vE '^ *Welcome to|^ *$|^remote mkdir .*Failure' >&2 || true
cp "$pack.sha" "$manifest"
echo "push: done"
