# Setup, Testing & Render Deployment

## 1. Prerequisites
- **Rust toolchain** (supports `edition = "2024"` and `Cargo.lock` v4; e.g. Rust `>= 1.85`)
- **Flutter via FVM** (see `mobile/.fvmrc`)
- **Python 3.12+** (with `venv` for the ML/RSS service and test runner)
- **Supabase project** with **ES256 / RS256** JWT signing keys (HS256 is unsupported by Axum's JWKS verifier) and a server-only PostgreSQL `DATABASE_URL`

---

## 2. Local Development Setup

### A. Python ML & News Service (`ml/`)
From the repository root:
```sh
python3 -m venv ml/.venv
ml/.venv/bin/python -m pip install -r ml/requirements.txt
# Train baseline 60-day weights (saved to ml/artifacts/forecast.pt, gitignored)
ml/.venv/bin/python ml/train.py --days 60 --epochs 100
ml/.venv/bin/python ml/serve.py
```
On Windows PowerShell, substitute `ml\.venv\Scripts\python.exe`.

### B. Rust / Axum Backend (`backend/`)
1. Copy [`backend/.env.example`](../backend/.env.example) to `backend/.env` (never commit `.env`):
   - `DATABASE_URL` & `SUPABASE_URL`
   - `OPENAQ_API_KEY`, `TOMTOM_API_KEY`
   - `GEMINI_API_KEY` & `GEMINI_MODEL` (e.g. `gemini-2.5-flash` or supported project model)
   - `INTELLIGENCE_URL=http://127.0.0.1:8001`
   - `ALERTS_ENABLED=true` (optional background worker)
   - `PUBLIC_BASE_URL=http://localhost:3000`
   - `AVATAR_STORAGE_DIR=uploads/avatars`
   - `VALHALLA_ROUTE_URL`, `COMMUTE_API_URL`, optional `TRANSJAKARTA_GTFS_DIR` (defaults to `../file_gtfs`)
2. Apply migrations and run the server:
   ```sh
   cd backend
   cargo run --locked -- migrate
   ALERTS_ENABLED=true cargo run --locked
   ```

### C. Flutter Client (`mobile/`)
1. Copy [`mobile/config/local.example.json`](../mobile/config/local.example.json) to `mobile/config/local.json` and set `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `SUPRA_API_URL` (`http://localhost:3000` on desktop/web, `http://10.0.2.2:3000` on Android emulator). Keep all secret API keys out of `local.json`.
2. Fetch packages and run:
   ```sh
   cd mobile
   fvm flutter pub get
   fvm flutter run --dart-define-from-file=config/local.json
   ```

---

## 3. Automated Testing (`testing/`)

The repository separates testing into **Unit**, **Integration**, and **System** stages (detailed in [`testing/README.md`](../testing/README.md) and [`docs/testing/00-integration.md`](testing/00-integration.md)):

- **Run unit + integration suites with evidence capture:**
  ```sh
  python3 testing/scripts/run_checks.py
  # Or target a single stage:
  python3 testing/scripts/run_checks.py --stage unit
  python3 testing/scripts/run_checks.py --stage integration
  ```
  Logs and `summary.json` are written to `testing/evidence/<UTC timestamp>/`.
- **Direct package commands:**
  - Backend unit/router suites: `cd backend && cargo test --locked`
  - Flutter analyzer & tests: `cd mobile && fvm flutter analyze && fvm flutter test`
  - Python ML/RSS unit & artifact tests: `ml/.venv/bin/python -m unittest discover -s testing/python -v`
- **Test Inventory Guardrail:** `testing/suites.json` classifies every Rust test case (`unit`, `integration`, `database`, `gtfs`, `live`), enforced by `validate_partition` during `run_checks.py`.
- **Live & Diagnostic Smoke Scripts:** `smoke.py`, `schema_audit.py`, `provider_freshness.py`, `conditions_smoke.py`, `transit_smoke.py`, `intelligence_smoke.py`, `assistant_smoke.py`, `alerts_smoke.py`, `account_diagnostics.py`, `database_diagnostics.py`, and `run_database_tests.py`.

---

## 4. Production Deployment on Render

Because Render has no native Rust runtime and `ml/serve.py` binds exclusively to `127.0.0.1:8001`, [`Dockerfile`](../Dockerfile) packages the compiled Rust binary (`rust:1-slim-bookworm`), CPU PyTorch + Python runtime (`python:3.12-slim-bookworm`), and `file_gtfs/` together in one container, orchestrated by [`render.yaml`](../render.yaml).

1. **Create Blueprint on Render:** Connect `arkaanp/SUPRA` (`main`) via **New + → Blueprint**; Render reads `render.yaml`.
2. **Fill Secret Environment Variables:**
   - `DATABASE_URL` (use Supabase's IPv4-compatible **Session Pooler** URI if needed)
   - `SUPABASE_URL`, `PUBLIC_BASE_URL` (`https://<your-service>.onrender.com`)
   - `OPENAQ_API_KEY`, `TOMTOM_API_KEY`, `GEMINI_API_KEY` (and confirm `GEMINI_MODEL`)
   - Non-secret defaults (`PORT=3000`, `INTELLIGENCE_URL=http://127.0.0.1:8001`, `TRANSJAKARTA_GTFS_DIR=/app/file_gtfs`, `AVATAR_STORAGE_DIR=/app/uploads/avatars`, `ALERTS_ENABLED=true`) are pre-configured in `render.yaml`.
3. **Verify Health:** Check `GET /health/live` and `GET /health/ready` return `200 OK`.
4. **Build Clients Against Render:** Set `SUPRA_API_URL` in `mobile/config/local.json` to `https://<your-service>.onrender.com` and build APK/AAB (`fvm flutter build apk --release --dart-define-from-file=config/local.json`) or Web (`fvm flutter build web --dart-define-from-file=config/local.json`).
