# SUPRA Python intelligence service

A CPU PyTorch model predicts the next 12 hourly values for temperature (°C),
precipitation (mm), PM2.5 (µg/m³), provider US AQI, and wet-hour probability.
The same loopback service reads current ANTARA publisher RSS for commuter news.
Axum authenticates the app and keeps this service off the public network.

## Start the demo

From the repository root:

```sh
python3 -m venv ml/.venv
ml/.venv/bin/python -m pip install -r ml/requirements.txt
ml/.venv/bin/python ml/train.py --days 60 --epochs 100
ml/.venv/bin/python ml/serve.py
```

In another terminal:

```sh
cd backend
# Loads backend/.env; enables scheduled in-app alerts for this process.
ALERTS_ENABLED=true cargo run --locked
```

`INTELLIGENCE_URL=http://127.0.0.1:8001` is the backend default. `--port` changes
the Python port. Both services must be running. The Python listener binds only to
127.0.0.1; place both services together or use a private authenticated network
adapter when deploying separately. Do not expose its unauthenticated port publicly.
The forecast service itself needs no schema change. The later news-severity
preference feature requires `cargo run --locked -- migrate` before using its
updated backend. A separate Python process keeps inference
and training out of the Rust API event loop.

Model weights live in `ml/artifacts/forecast.pt`; downloaded history lives under
`ml/data/`. The environment, data and weights are ignored by Git. Generate weights
with the training command on a fresh checkout/deployment. Source code and
[model_card.json](artifacts/model_card.json) remain visible for demonstration.
Retraining replaces the checkpoint atomically; the running service reloads it on
its next inference request. Use `--reuse-data` to reproduce training on the saved
history. Record a new model card when downloading fresh history.

## Model and validation

- A direct multi-horizon MLP (103→96→48→5) consumes 24 consecutive hourly inputs,
  time-of-day/week features, coordinates and horizon. It predicts residual
  temperature/PM2.5/AQI, log precipitation, and a wet-hour logit.
- Training uses 60 days of public Open-Meteo weather and CAMS global air-model
  history at Jakarta, Depok, Bogor, Bekasi and Tangerang. Hours later than the
  issue time and incomplete/discontinuous windows are excluded.
- The final 14 days are held out chronologically: seven validation days and seven
  test days. Windows cannot straddle target partitions. Input/target normalization
  is fitted on training examples only. Validation selects the checkpoint; test
  data never selects an epoch. Persistence MAE is recorded for comparison.
- The saved run contains 64,650 training, 9,690 validation and 9,750 test examples.
  Overlapping horizons/sites are correlated examples, not independent experiments.
  Held-out test MAE: temperature 0.96°C, rain 0.21 mm, PM2.5 18.46 µg/m³,
  AQI 5.29. Rain Brier score: 0.171. See the model card for exact metrics.
- Outputs are experimental regional model estimates. Targets are provider model
  history, not independent station measurements or an operational accuracy
  certification. Historical provider products can be revised. PM2.5 error is
  substantial; error ranges are empirical validation residuals, not calibrated
  confidence guarantees. CAMS global data are coarse regional coverage.
- Wet-hour probability is learned against >=0.1 mm/hour labels. It is not an
  official weather warning. Traffic remains unavailable: no validated historical
  traffic target set has been provided. No numeric traffic forecast is emitted.

Inference requires 24 contiguous past hours, inputs at most two hours old, finite
bounded values and a checkpoint trained on data no more than 90 days old. It uses
`eval()`, `inference_mode()` and CPU `weights_only=True` loading. Missing inputs,
weights, providers or expired outputs produce unavailable states. Requests do not
train models. Cache entries are bounded, coalesced per location and change at the
hour boundary. Provider failures do not manufacture replacement forecasts.

## Real news alerts

Feeds are ANTARA Metro, current news, Metro Lintas Kota and ANTARA Megapolitan.
Only RSS title/link metadata is redistributed. Commuter topics include weather,
flooding, transit, road restrictions, congestion and air pollution. Reports must
have an original publication time within 48 hours, a trusted HTTPS article URL,
and a named Jabodetabek area. Dateline text alone does not establish relevance.

Area names match an explicit geographic lookup with an approximate radius. These
are publisher reports with **area-level relevance**, not verified live incidents
at an exact point. The article is the source for the report's current status.
Expiry is publication +48 hours; it is never refreshed relative to request time.
Stable article IDs deduplicate inbox entries across manual and scheduled checks.
Failures create no new report. Existing real inbox history/read state remains.
Previous built-in report IDs are suppressed from inbox lists without deleting
stored history.

The backend honors `alert_relevant_news`, matches recent owned trip corridors,
and uses regional commuter reports when the account has no geolocated trip.
The optional `NEWS_INCIDENTS_URL` operator-reviewed JSON feed still works.
Scheduled checks use `ALERTS_ENABLED=true`, with a bounded rotating user batch.
Manual checks use `/api/alerts/evaluate` and immediately return 202. News runs
alongside current-condition checks. Delivery is the **in-app inbox**.

## API and UI

Python endpoints:

- `GET /health/live`: process health, not model readiness.
- `GET /v1/model`: trained model card.
- `GET /v1/forecast?latitude=...&longitude=...`: model/version, issue/input times,
  expiry, source attribution, validation/error metadata and hourly values.
- `GET /v1/news`: current publisher reports with original dates and area basis.

Authenticated Axum endpoint: `GET /api/forecast/hourly?latitude=...&longitude=...`.
It validates location, horizon, freshness, value bounds and model identity before
returning the Python response. Existing stored `/api/predictions` records are a
separate legacy read API; live output is not silently inserted into them.

Home's ML switch loads the current location forecast and updates the 12-hour
strip. The main card shows the next forecast hour and its source/model. Trip's ML
chip shows the origin forecast; route map samples continue showing provider
conditions along selected geometry. Changing origin invalidates the previous
forecast. Missing traffic/model values stay empty. Forecasts do not replace
current-condition evidence for hazard alerts.

## Two testing steps

1. Unit testing: `python3 testing/scripts/run_checks.py --stage unit` includes
   `testing/python/unit/` for chronological split boundaries, invalid/stale/gap
   rejection, RSS timestamps, trust, severity and hourly cache behavior, plus
   Rust and Flutter unit coverage.
2. Integration testing: `python3 testing/scripts/run_checks.py --stage integration`
   includes `testing/python/integration/` for PyTorch checkpoint persistence and
   twelve-hour inference, HTTP adapters and an isolated migrated database for
   publisher inbox preferences and deduplication.

Install `ml/.venv` and requirements first; a missing environment fails the runner.
This cycle does not retrain the model or refresh the historical model-card metrics.
Optional running-service integration: `python3 testing/scripts/intelligence_smoke.py`.
Its `--evaluate` flag explicitly queues news for the desktop account and is not
used by the default test runner. See [testing/README.md](../testing/README.md).

Sources: [Open-Meteo weather](https://open-meteo.com/en/docs),
[CAMS air-quality history/API](https://open-meteo.com/en/docs/air-quality-api),
[ANTARA RSS](https://www.antaranews.com/rss/),
[PyTorch state-dict loading](https://docs.pytorch.org/tutorials/beginner/saving_loading_models.html).
Preserve the supplied Open-Meteo/CAMS attribution and publisher links.

News severity is now classified from reported disruption keywords (Low/Medium/High).
Critical remains reserved for explicitly reviewed feeds. Profile/Alerts minimum
preferences apply to new news delivery and inbox filtering. See
[assistant and alert preferences](../backend/docs/assistant-and-alerts.md).
