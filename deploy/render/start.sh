#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${DATABASE_URL:?Set DATABASE_URL in Render}"
: "${SUPABASE_URL:?Set SUPABASE_URL in Render}"
: "${SUPABASE_PUBLISHABLE_KEY:?Set SUPABASE_PUBLISHABLE_KEY in Render}"
export PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-${RENDER_EXTERNAL_URL:?Set the public HTTPS origin}}"
export BIND_ADDR=127.0.0.1:3000
port=${PORT:-10000}
[[ $port =~ ^[1-9][0-9]{0,4}$ ]] && ((port <= 65535 && port != 3000 && port != 8001)) || {
    echo "PORT must be an available public listener port distinct from 3000 and 8001" >&2
    exit 1
}
sed "s/RENDER_PORT/$port/g" nginx.conf > /tmp/supra-nginx.conf
nginx -e stderr -t -c /tmp/supra-nginx.conf
children=()
stop() {
    for child in "${children[@]}"; do kill "$child" 2>/dev/null || true; done
    wait || true
}
trap stop EXIT
trap 'exit 0' TERM INT
python ml/serve.py & children+=("$!")
supra_backend & children+=("$!")
nginx -e stderr -c /tmp/supra-nginx.conf & children+=("$!")
# Restart the complete service if any required process exits.
wait -n || true
echo "One of the SUPRA service processes exited" >&2
exit 1
