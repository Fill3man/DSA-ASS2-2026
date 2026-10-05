#!/usr/bin/env bash
# Builds every Ballerina service jar so `docker compose up --build` can package them.
#   ./scripts/build-all.sh                 # all services
#   ./scripts/build-all.sh order-service   # just one
#   OFFLINE=1 ./scripts/build-all.sh       # use only the local package cache
set -uo pipefail
cd "$(dirname "$0")/../services"

# bal defaults to a 2 GB heap; cap it so builds work on 4-8 GB machines.
export JAVA_OPTS="${JAVA_OPTS:--Xmx768m -XX:+UseSerialGC}"

services=("$@")
[ ${#services[@]} -eq 0 ] && services=(*/)

failed=()
for svc in "${services[@]}"; do
  svc=${svc%/}
  echo "==> $svc"
  (cd "$svc" && bal build ${OFFLINE:+--offline}) || failed+=("$svc")
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}"; exit 1
fi
echo "All services built. Next: docker compose up -d --build"
