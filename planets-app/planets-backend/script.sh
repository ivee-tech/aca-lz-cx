#!/usr/bin/env bash
set -euo pipefail

# Configure environment for local SQL run
export PlanetRepository__Provider="Sql"
export PlanetRepository__UseManagedIdentity="false"
export ConnectionStrings__PlanetDb="Server=localhost;Database=Planets;Trusted_Connection=True;Encrypt=False;"

# Run Planets backend API
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pushd "$root_dir" >/dev/null

dotnet run &
API_PID=$!
echo "[script] Planets API running with PID $API_PID"
trap 'echo "Stopping API..."; kill $API_PID; wait $API_PID 2>/dev/null || true' EXIT

# Wait for app to start listening (quick retry loop hitting health endpoint)
API_BASE="http://localhost:5279"
API_BASE="https://fd-nasc-dev-bje4hgeagpgaegcc.b02.azurefd.net"
# publish
curl -X POST ${API_BASE}/api/rockets/publish -H "Content-Type: application/json" -d '{"source":"Earth","destination":"Mars","rocketId":""}'
# stream
for _ in {1..30}; do
  if curl -fsS "$API_BASE/health" >/dev/null 2>&1; then
    echo "[script] API is ready at $API_BASE"
    break
  fi
  sleep 1
  if ! kill -0 $API_PID >/dev/null 2>&1; then
    echo "[script] API process exited unexpectedly" >&2
    exit 1
  fi
  if [[ $_ -eq 30 ]]; then
    echo "[script] Timed out waiting for API to start" >&2
    exit 1
  fi
  done

echo "[script] Streaming rocket events (Ctrl+C to stop)"
{ curl -fsS "$API_BASE/api/rockets/stream" || true; } &
STREAM_PID=$!

sleep 1


wait $STREAM_PID || true

popd >/dev/null
