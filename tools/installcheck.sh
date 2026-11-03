#!/usr/bin/env bash
# installcheck.sh <node> - install the node's kit, verify it, build the smoke test
# against the installed headers and options file, run its handshake against the
# node's own sshd, and remove the kit again.  This changes the system while it
# runs (PCSI database, SYS$COMMON:[LIBSSH2], LIBSSH2$ROOT); run kit.sh first.
# Output: out/install-<node>.txt (don't redirect this script's stdout there).
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: installcheck.sh <node>}
. "$top/upstream.conf"
REMOTE=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _ | tr a-z A-Z)
"$top/tools/vms.sh" "$node" put "$top/tools/vms_installcheck.com" >/dev/null
read -r _ _ _ PORT _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
job=$top/cache/installcheck-$node.com
printf '$ set noon\n$ @%sVMS_INSTALLCHECK.COM %s %s\n' "$WORKDIR" "$REMOTE" "$PORT" > "$job"
VMS_TIMEOUT=1800 "$top/tools/vms.sh" "$node" run "$job" > "$top/out/install-$node.txt" 2>&1
grep -aE 'install status|Installed|startup procedure|LIBSSH2\$ROOT|LIBSSH2.OPT:|SMOKE:|remove status|after removal|items found' "$top/out/install-$node.txt"
grep -q 'SMOKE: ok handshake' "$top/out/install-$node.txt" &&
    ! grep -q 'SMOKE: FAIL' "$top/out/install-$node.txt" &&
    grep -q 'LIBSSH2\$ROOT after removal: \[\]' "$top/out/install-$node.txt" &&
    grep -q 'startup after removal: \[\]' "$top/out/install-$node.txt"
