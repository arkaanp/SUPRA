#!/usr/bin/env python3
"""Run the repository suites and retain demonstrable evidence under testing/."""
import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', action='store_true', help='Also run the ignored DB test; set SUPRA_TEST_DATABASE_URL to a disposable *_test DB')
    parser.add_argument('--builds', action='store_true', help='Also build Linux and web')
    args = parser.parse_args()
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    evidence = ROOT / 'testing' / 'evidence' / stamp
    evidence.mkdir(parents=True)
    checks = [('backend', 'backend', ['cargo', 'test', '--locked']),
              ('analyze', 'mobile', ['fvm', 'flutter', 'analyze']),
              ('mobile', 'mobile', ['fvm', 'flutter', 'test', '--no-pub'])]
    if args.database:
        import os
        if not os.environ.get('SUPRA_TEST_DATABASE_URL'):
            parser.error('--database requires SUPRA_TEST_DATABASE_URL')
        checks.append(('database', 'backend', ['cargo', 'test', '--locked', '--', '--ignored']))
    if args.builds:
        checks += [(f'build-{target}', 'mobile', ['fvm', 'flutter', 'build', target]) for target in ('linux', 'web')]
    results = []
    for name, directory, command in checks:
        print(f'Running {name}...', flush=True)
        with (evidence / f'{name}.log').open('w') as log:
            try:
                result = subprocess.run(command, cwd=ROOT / directory, stdout=log, stderr=subprocess.STDOUT)
                code = result.returncode
            except OSError as error:
                log.write(f'Could not launch command: {error.__class__.__name__}\n')
                code = 127
        results.append({'check': name, 'command': command, 'exit_code': code, 'log': f'{name}.log'})
        print(f'{name}: {"PASS" if code == 0 else "FAIL"}', flush=True)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    summary = {'tested_commit': revision, 'utc': stamp, 'checks': results,
               'working_tree_status': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True)}
    (evidence / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(f'Evidence: {evidence.relative_to(ROOT)}')
    return int(any(r['exit_code'] != 0 for r in results))


if __name__ == '__main__':
    raise SystemExit(main())
