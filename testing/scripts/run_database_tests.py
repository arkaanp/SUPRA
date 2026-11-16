#!/usr/bin/env python3
"""Provision an isolated local PostgreSQL cluster under testing/evidence and run API tests."""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import shlex
import socket
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path)
    args = parser.parse_args()
    directory = (args.evidence_dir or ROOT / 'testing/evidence' / ('db-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))).resolve()
    if not directory.is_relative_to(ROOT / 'testing/evidence'):
        parser.error('--evidence-dir must be under testing/evidence')
    directory.mkdir(parents=True, exist_ok=False)
    data = directory / 'data'
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    started = False
    with (directory / 'integration.log').open('w') as log:
        def run(args, **kwargs):
            return subprocess.run(args, cwd=ROOT / 'backend', stdout=log, stderr=subprocess.STDOUT, **kwargs)
        try:
            run(['initdb', '-D', str(data), '-U', 'postgres', '-A', 'trust', '--no-instructions'], check=True)
            # TCP loopback only; no shared server, existing database, or /tmp artifacts.
            options = shlex.join(['-h', '127.0.0.1', '-p', str(port), '-k', ''])
            run(['pg_ctl', '-D', str(data), '-o', options, '-l', str(directory / 'postgres.log'), '-w', 'start'], check=True)
            started = True
            run(['createdb', '-h', '127.0.0.1', '-p', str(port), '-U', 'postgres', 'supra_test'], check=True)
            env = dict(os.environ)
            env['SUPRA_TEST_DATABASE_URL'] = f'postgres://postgres@127.0.0.1:{port}/supra_test'
            result = run(['cargo', 'test', '--locked', '--offline', '--', '--ignored', '--exact', 'db_tests::migrated_schema_enforces_user_boundaries'], env=env)
            code = result.returncode
        except (OSError, subprocess.CalledProcessError) as error:
            log.write(f"Database setup/test failure: {error}\n")
            code = 1
        finally:
            if started:
                stopped = run(['pg_ctl', '-D', str(data), '-m', 'fast', '-w', 'stop'])
                if stopped.returncode:
                    code = 1
    print(f'Integration: {"PASS" if code == 0 else "FAIL"}; evidence: {directory.relative_to(ROOT)}')
    return code

if __name__ == '__main__':
    raise SystemExit(main())
