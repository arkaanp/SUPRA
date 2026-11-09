#!/usr/bin/env python3
"""Inspect schema metadata only. Never applies migrations or reads account rows."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess
from urllib.parse import unquote, urlsplit

QUERY = """
BEGIN READ ONLY;
SELECT version, success FROM _sqlx_migrations ORDER BY version;
SELECT table_name, column_name FROM information_schema.columns
WHERE table_schema='public' AND (
 (table_name='users' AND column_name IN ('avatar_url','password_hash')) OR
 (table_name='trips' AND column_name IN ('confirmed_at','transport_mode','active_until','route_waypoints')) OR
 (table_name='notification_preferences' AND column_name='alert_relevant_news') OR
 (table_name='notifications' AND column_name IN ('event_key','source_url','context')))
ORDER BY table_name, column_name;
SELECT table_name FROM information_schema.tables WHERE table_schema='public'
AND table_name IN ('saved_places','routine_trips','alert_decisions');
ROLLBACK;
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend-env', action='store_true', help='Read DATABASE_URL from backend/.env if absent from the shell')
    args = parser.parse_args()
    url = os.environ.get('DATABASE_URL')
    if not url and args.backend_env:
        for line in (Path(__file__).resolve().parents[2] / 'backend' / '.env').read_text().splitlines():
            if line.strip().startswith('DATABASE_URL='):
                values = shlex.split(line.split('=', 1)[1], comments=True)
                url = values[0] if values else None
    if not url:
        parser.error('Set DATABASE_URL or use --backend-env. Connection values are not printed.')
    try:
        parsed = urlsplit(url)
        if parsed.scheme not in ('postgres', 'postgresql') or not parsed.hostname:
            raise ValueError()
        env = dict(os.environ)
        env.update(PGHOST=parsed.hostname, PGPORT=str(parsed.port or 5432),
                   PGUSER=unquote(parsed.username or 'postgres'), PGPASSWORD=unquote(parsed.password or ''),
                   PGDATABASE=unquote(parsed.path.lstrip('/')), PGCONNECT_TIMEOUT='8',
                   PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=10000')
        from urllib.parse import parse_qs
        options = parse_qs(parsed.query)
        if 'sslmode' in options:
            env['PGSSLMODE'] = options['sslmode'][0]
        result = subprocess.run(['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-c', QUERY], env=env,
                                capture_output=True, text=True, timeout=20)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        print('Schema audit failed: check connection configuration, psql installation and reachability.')
        return 1
    if result.returncode:
        print('Schema audit failed: check database access and migration tracking. Connection details suppressed.')
        return 1
    print(result.stdout)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
