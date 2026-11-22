# Deploy SUPRA on Oracle Cloud Always Free

Use a single Always Free eligible Ubuntu 24.04 ARM64 VM.Standard.A1.Flex instance in your home region. Budget **2 OCPUs, 12 GB RAM and a 50 GB boot volume** if that capacity is available within your tenancy's unused allowance. Oracle can reclaim idle free instances. Keep a separate backup of avatars, the model checkpoint and your Supabase database. [Oracle resource limits](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)

Nginx terminates HTTPS and limits username sign-in attempts. The Rust API and Python service listen on loopback. Run one API instance since it owns the alert scheduler. Supabase continues to provide Auth and PostgreSQL.

## 1. Network and release

Assign the VM a public IP in a public subnet with an internet gateway. Point your API hostname's DNS A record to that IP. In both the OCI security list or NSG and Ubuntu's host firewall, allow inbound TCP 80 and 443, and restrict TCP 22 to your administrative IP. Keep ports 3000 and 8001 private. Preserve the image's existing OCI platform firewall rules. Allow outbound DNS, HTTPS for providers, and the database port for the selected Supabase endpoint. [Oracle Linux instance tutorial](https://docs.oracle.com/en-us/iaas/Content/Compute/tutorials/first-linux-instance/overview.htm)

On the development machine, package the working checkout with the trusted trained checkpoint and local GTFS. Record the printed checksum and compare it on the VM after transfer.

```sh
deploy/oracle/package.sh /tmp/supra-release.tar.gz
scp /tmp/supra-release.tar.gz ubuntu@YOUR_VM_IP:
```

On the VM, install the native build dependencies and a current stable Rust toolchain for the deployment user. The project uses Rust edition 2024. Ubuntu 24.04 supplies Python 3.12. Both pinned scientific packages publish Linux ARM64 wheels for this interpreter. [Rust installation](https://rustup.rs/) · [PyTorch wheels](https://download.pytorch.org/whl/cpu/torch/) · [NumPy wheels](https://download.pytorch.org/whl/cpu/numpy/)

```sh
sudo apt-get update
sudo apt-get install -y build-essential pkg-config python3.12-venv nginx certbot
sha256sum ~/supra-release.tar.gz
release=/opt/supra/releases/$(date -u +%Y%m%dT%H%M%SZ)
sudo install -d -m 0755 -o "$(id -un)" -g "$(id -gn)" "$release"
tar -xzf ~/supra-release.tar.gz -C "$release"
cd "$release"
bash deploy/oracle/build.sh
```

The build reads the packaged model on the VM before building the API. Keep the release at its original absolute path for the Python virtual environment.

## 2. Configure staging

Copy the server environment template once, then edit the root-only file.

```sh
sudo install -d -m 0750 /etc/supra
sudo install -m 0600 backend/.env.example /etc/supra/backend.env
sudoedit /etc/supra/backend.env
```

| Setting | Value on Oracle |
| --- | --- |
| DATABASE_URL | An SSL-enabled connection to the staging Supabase database. Use the session pooler with sslmode=require if the VM has IPv4-only connectivity. The migration role needs permission to create a trigger on auth.users. |
| SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY | The same project URL and publishable key used by Flutter. Username login uses the public password grant. |
| PUBLIC_BASE_URL | https:// followed by your actual API hostname |
| BIND_ADDR | 127.0.0.1:3000 |
| INTELLIGENCE_URL | http://127.0.0.1:8001 |
| TRANSJAKARTA_GTFS_DIR | /opt/supra/current/file_gtfs |
| AVATAR_STORAGE_DIR | /var/lib/supra/avatars, persisted by systemd across releases |
| ALERTS_ENABLED | true to evaluate alerts in the background |
| OPENAQ_API_KEY, TOMTOM_API_KEY, GEMINI_API_KEY, GEMINI_MODEL | Supply the provider credentials and Gemini model enabled for staging. |
| SUPABASE_SERVICE_ROLE_KEY | Server-only legacy service-role key for username registration and Auth account deletion. |

## 3. Migrate and start

Back up the staging database before the first upgrade. The username migration renames the profile column. Coordinate this cutover with the new Flutter client, since older builds send full_name. During upgrades, stop the previous API before switching the release. The migration is an explicit one-shot service and fails on a checksum mismatch.

```sh
sudo ln -sfnT "$release" /opt/supra/current
sudo install -m 0644 deploy/oracle/supra-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start supra-migrate && sudo systemctl enable --now supra-api supra-ml
curl -fsS http://127.0.0.1:3000/health/ready
curl -fsS http://127.0.0.1:8001/v1/model
```

## 4. Enable HTTPS and connect Flutter

On a fresh Ubuntu Nginx installation, the default HTTP site serves /var/www/html. With DNS propagated and port 80 reachable, issue the certificate via webroot. Replace the example hostname in the first command.

```sh
domain=api.example.org
sudo certbot certonly --webroot -w /var/www/html -d "$domain"
sed "s/API_HOSTNAME/$domain/g" deploy/oracle/nginx.conf | sudo tee /etc/nginx/sites-available/supra >/dev/null
sudo ln -sfn /etc/nginx/sites-available/supra /etc/nginx/sites-enabled/supra
sudo nginx -t && sudo systemctl reload nginx
printf '#!/bin/sh\nsystemctl reload nginx\n' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx >/dev/null
sudo chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
sudo systemctl enable --now certbot.timer
sudo certbot renew --dry-run
curl -fsS "https://$domain/health/live"
curl -fsS "https://$domain/health/ready"
```

From the Flutter checkout copy mobile/config/local.example.json to mobile/config/local.json. Set SUPRA_API_URL to the HTTPS API origin and enter the matching Supabase URL and publishable key. Build with the chosen configuration from mobile/.

```sh
fvm flutter build apk --release --dart-define-from-file=config/local.json
```

On staging, register with a username and password. Sign in, rename the username in Profile, and sign in again with the new handle. Verify that an existing account still signs in with its assigned username. Upload an avatar, restart the API and confirm the image still loads. Request a named route, forecast and news alerts from Flutter. The readiness probe checks database connectivity only.

For subsequent releases build into a fresh release directory. Preserve /etc/supra/backend.env, /var/lib/supra and the prior release. Stop supra-api and supra-ml, switch the symlink, apply pending migrations and restart both services. Inspect failures with journalctl -u supra-api -u supra-ml -u supra-migrate. A binary rollback needs a compatible schema. For the username cutover, use the pre-upgrade database backup with the previous API and client if rollback is required.
