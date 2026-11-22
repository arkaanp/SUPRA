# Deploy SUPRA to Render Free

The root `render.yaml` creates one Singapore web service. Render terminates HTTPS. Inside the container Nginx exposes the assigned port, limits username sign-in attempts and forwards requests to Axum. PyTorch and the RSS reader share a private loopback listener. The image includes the trained checkpoint and Transjakarta GTFS. Accounts, trips and preferences use the existing Supabase project.

## 1. Publish a demo branch

From the repository root, start with the checkout containing the username changes. Render builds the commit available on GitHub. For this checkout the following commands include those changes and the deployment files. The Oracle guide remains available in the repository for later use.

```bash
git switch -c codex/render-demo
git add -u -- .gitignore backend mobile testing/scripts/run_database_tests.py
git add -- render.yaml deploy/render deploy/oracle backend/migrations/20261121000000_usernames.sql testing/sql/username_migration.sql
git add -f -- ml/artifacts/forecast.pt
git diff --cached --stat
git commit -m "Prepare SUPRA demo for Render Free with username login"
git push -u origin codex/render-demo
```

The force-add selects the existing 65 KiB trained checkpoint, which the project normally ignores. Review the staged file list before committing. Keep backend/.env and mobile/config/local.json local. If your GitHub account deploys from a fork, push the branch there and select that repository in Render.

## 2. Prepare the Supabase database

Use the same Supabase project for the API and Flutter client. For a separate demo, use a staging project. If you use the current project, export a backup first and coordinate the updated client with the migration, which changes the profile column from full_name to username.

In Supabase select **Connect → Session pooler**. Copy the PostgreSQL URI with port 5432, replace the password placeholder with the URL-encoded database password, and use `sslmode=require`. Use the project database role with migration privileges, including permission to create a signup trigger on auth.users. [Supabase connection guide](https://supabase.com/docs/guides/database/connecting-to-postgres)

The URI has the form `postgresql://postgres.PROJECT_REF:ENCODED_PASSWORD@POOLER_HOST:5432/postgres?sslmode=require`. Copy the actual pooler host from Supabase. A host beginning with `db.` and ending in `.supabase.co` is the direct endpoint, which requires IPv6 unless the project has the IPv4 add-on. The shared pooler's transaction-mode URI uses port 6543. Use the session-mode URI for SUPRA.

Run the migration once from your machine in Bash. Paste the intended URI at the hidden prompt. The subshell confines DATABASE_URL to this command.

```bash
(
  cd backend || exit 1
  read -rsp 'Supabase demo database URI: ' DATABASE_URL
  echo
  export DATABASE_URL
  cargo run --locked -- migrate
)
```

Continue after the log says `Database migrations applied`. Apply future pending migrations explicitly as well. Render Free has no pre-deploy command. [Render deployment commands](https://render.com/docs/deploys#pre-deploy-command)

## 3. Create the service

1. Open the Render Dashboard and select **New → Blueprint**. Connect GitHub and choose the SUPRA repository containing the demo branch.
2. Select **codex/render-demo** and leave the Blueprint path as **render.yaml**. Give the Blueprint a name, such as **supra-demo**.
3. Review the preview. It should show **one Docker web service**, **Free**, **Singapore**. The service uses the repository root for its Docker build context.
4. Enter the three values below when prompted, then select **Deploy Blueprint**. Watch the service's **Events** and **Logs** until it is **Live**. Render assigns an HTTPS URL and the startup script uses it for avatar links. [Render Blueprint setup](https://render.com/docs/infrastructure-as-code#setup)

| Required Render variable | Where to get it |
| --- | --- |
| DATABASE_URL | The same session-pooler URI used for the migration |
| SUPABASE_URL | Your project's HTTPS URL, also used by Flutter |
| SUPABASE_PUBLISHABLE_KEY | The project's publishable key, also used by Flutter |

In the service's **Environment** tab, add the server-side keys for the features you want to demonstrate. **GEMINI_API_KEY** enables the Gemini assistant, **TOMTOM_API_KEY** enables traffic, and **OPENAQ_API_KEY** enables station observations. You can also supply **GEMINI_MODEL** if your Google project uses a different model. Use **Save and deploy** after editing. Keep database credentials and provider keys out of the Flutter config. The existing account-deletion integration optionally uses a server-only SUPABASE_SERVICE_ROLE_KEY for deleting the Auth identity.

## 4. Connect and verify Flutter

Use the actual service URL from the Render dashboard.

```bash
api=https://YOUR-SERVICE.onrender.com
curl -fsS "$api/health/live"
curl -fsS "$api/health/ready"
```

Expect `{"status":"ok"}` and `{"status":"ready"}`. The second endpoint exercises PostgreSQL. In mobile/config/local.json set **SUPRA_API_URL** to that same HTTPS origin, with no /api suffix. Keep **SUPABASE_URL** and **SUPABASE_PUBLISHABLE_KEY** pointed at the matching project. If creating this file for the first time, copy mobile/config/local.example.json first.

```bash
cd mobile
fvm flutter run --dart-define-from-file=config/local.json
# To build the Android demo APK:
fvm flutter build apk --release --dart-define-from-file=config/local.json
```

Sign in by email, check the username under Profile, then sign out and sign in by username. Save and reload a trip. Request a transit route and an hourly forecast. Check news and Gemini in the app. Check Render's memory graph while trying these features together. For password recovery, the allowed Supabase redirect should open Flutter. For Android the configured callback is io.supabase.supra://login-callback and can be passed as RECOVERY_REDIRECT_URL in the Flutter config. For Flutter web use its hosted app URL.

## During the demo

- **First request times out.** Render Free sleeps after 15 idle minutes and waking usually takes about a minute. Open /health/ready in a browser and wait for ready before opening SUPRA. Then retry the failed action.
- **Avatars disappear.** Uploaded images are temporary on Render Free and can be lost after spin-down, restart or redeploy. Supabase-backed profile fields and trips persist. Durable avatars would require moving uploads to object storage.
- **Scheduled alerts.** The Blueprint sets ALERTS_ENABLED=false. The app still requests alert evaluation while in use. Continuous background evaluation requires an always-on service.
- **Build cannot find forecast.pt.** Confirm `git ls-tree HEAD ml/artifacts/forecast.pt` prints an entry on the branch Render builds. A local file alone is insufficient.
- **Deploy times out with “Network is unreachable”.** In the Render service, open **Environment**, edit **DATABASE_URL**, replace it with the full Supabase **Session pooler** URI and choose **Save and deploy**. Check for `Database connection pool established` in the new deploy logs, then open `/health/ready`. Keep database credentials in Render's environment settings.
- **Readiness or sign-in fails after wake-up.** Check the service logs, the session pooler URI and whether Supabase is active. Readiness tests the database connection. If email login works but username login fails, check the username migration, project URL and publishable key. A 429 on username login means the demo-wide login rate limit or Supabase's limit was reached. Wait before retrying.
- **Weather or ML forecast is unavailable.** After Render is ready, refresh conditions or enable ML in the signed-in app. Search Render logs for `Weather source unavailable`, `Both weather sources unavailable`, or `/v1/forecast rejected`. Current weather can use BMKG where a verified village code is available. If both preferred sources fail or a coordinate has no BMKG code and Open-Meteo is down, the worker obtains an hourly forecast from MET Norway. When Open-Meteo limits weather or CAMS history, look for `Using weather-only forecast` in the worker logs. The fallback PyTorch model estimates rain and temperature from MET Norway input. Rebuild Flutter from the same revision to display partial forecasts.
- **Traffic reports access denied.** Set `TOMTOM_API_KEY` in the backend environment to a key with Flow Segment Data access, then save and deploy. In TomTom's API Explorer, test **TomTom Maps → Traffic Flow → Flow Segment Data** with the key and the point `-6.2297,106.8295`. HTTP 401 means the credentials were rejected. Copy the active key from the TomTom dashboard into Render. For HTTP 403, check the key's product access and restrictions for server-side requests. A successful response contains `flowSegmentData.currentSpeed`. [Flow Segment Data](https://docs.tomtom.com/traffic-api/documentation/tomtom-maps/v1/traffic-flow/flow-segment-data)
- **Render reports an out-of-memory restart.** Look at the service's Events and Metrics during a route or forecast request. Local startup measurements do not establish capacity for concurrent demo users.

Render currently grants 750 free instance hours per workspace each month, shared across free web services. [Render Free limits and storage behavior](https://render.com/docs/free)
