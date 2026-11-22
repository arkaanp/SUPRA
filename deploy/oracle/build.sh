#!/usr/bin/env bash
# Run as the deployment user inside the extracted release on the A1 VM.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3.12 -m venv ml/.venv
ml/.venv/bin/python -m pip install --only-binary=:all: -r ml/requirements.txt
(cd ml && .venv/bin/python -c 'from inference import Forecaster; f = Forecaster(); f.load(); print(f.state["card"]["model_id"])')
test -s file_gtfs/stop_times.txt
cargo build --manifest-path backend/Cargo.toml --locked --release -j 2
