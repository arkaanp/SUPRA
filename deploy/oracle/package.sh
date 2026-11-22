#!/usr/bin/env bash
# Build a source bundle on the development machine, including the trained weights.
set -euo pipefail
if [[ $# != 1 ]]; then echo "Usage: $0 OUTPUT.tar.gz" >&2; exit 2; fi
output=$(realpath -m -- "$1")
cd "$(dirname "$0")/../.."
test -s ml/artifacts/forecast.pt || { echo "Missing trained ml/artifacts/forecast.pt" >&2; exit 1; }
# Explicit inputs exclude .env, local SDKs, uploads, caches and test evidence.
tar -czf "$output" backend/{Cargo.toml,Cargo.lock,build.rs,src,migrations,.env.example} \
    file_gtfs/*.txt ml/{data,inference,model,news,serve}.py ml/requirements.txt \
    ml/artifacts/{model_card.json,forecast.pt} deploy/oracle/{README.md,build.sh,nginx.conf,supra-*.service}
sha256sum "$output"
