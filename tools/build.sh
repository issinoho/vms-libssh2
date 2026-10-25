#!/usr/bin/env bash
# build.sh <node> [target] [KEEP_GOING] - push the prepared tree and run [.VMS]BUILD.COM on <node>.
# The build runs in an ssh session (batch queues may be busy); its log is printed and saved to out/build-<node>.log.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: build.sh <node> [target]}
target=${2:-ALL}
keep=${3:-}
variant=${4:-}
. "$top/upstream.conf"
remote=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _ | tr a-z A-Z)
read -r _ _ _ _ _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")

"$top/tools/push.sh" "$node"
mkdir -p "$top/out"
job=$top/cache/build-$node.com
cat > "$job" <<DCL
\$ set noon
\$ set process/parse_style=extended
\$ purge/nolog ${WORKDIR%]}.$remote...]*.*
\$ @${WORKDIR%]}.$remote.VMS]BUILD.COM "$target" "$keep" "$variant"
DCL
VMS_TIMEOUT=${VMS_BUILD_TIMEOUT:-5400} "$top/tools/vms.sh" "$node" run "$job" | tee "$top/out/build-$node$variant.log"
grep -q 'BUILD: done' "$top/out/build-$node$variant.log"
# A link with undefined symbols still writes the image, which then fails at
# run time (%SYSTEM-F-CALLUNDEFSYM); and MMS carries on past a failed
# compile ("-" actions) and still says "BUILD: done".  Treat all as failures.
if grep -aE 'USEUNDEF|UNDFSYM|%DCL-[WEF]-|%MMS-[EF]-|%CC-[EF]-|%I?LINK-[EF]-' "$top/out/build-$node$variant.log" >&2; then
    echo "build: errors or undefined symbols in out/build-$node$variant.log" >&2
    exit 1
fi
