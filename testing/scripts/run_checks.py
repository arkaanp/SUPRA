#!/usr/bin/env python3
"""Run unit and integration suites, retaining separate evidence under testing/."""
import argparse
from collections import Counter
import datetime as dt
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def validate_partition(groups, discovered):
    """Every discovered Rust case must have exactly one explicit classification."""
    counts = Counter(case for cases in groups.values() for case in cases)
    duplicates = sorted(case for case, count in counts.items() if count != 1)
    missing = sorted(set(discovered) - counts.keys())
    removed = sorted(counts.keys() - set(discovered))
    empty = [group for group in ('unit', 'integration', 'database', 'gtfs', 'live') if not groups.get(group)]
    if duplicates or missing or removed or empty:
        raise ValueError(f'Invalid testing/suites.json: duplicates={duplicates}, unclassified={missing}, removed={removed}, empty={empty}')


def passed_count(output, kind):
    patterns = {'rust': r'test result: ok\. (\d+) passed;',
                'flutter': r'\+(\d+).*All tests passed',
                'python': r'Ran (\d+) tests?\b'}
    matches = re.findall(patterns[kind], output)
    return sum(map(int, matches)) if kind == 'rust' else (int(matches[-1]) if matches else 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', choices=('unit', 'integration', 'all'), default='all')
    parser.add_argument('--live', action='store_true', help='Also run the two public Commute API integrations (requires network)')
    args = parser.parse_args()
    if args.live and args.stage == 'unit':
        parser.error('--live requires integration or all')
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    evidence = ROOT / 'testing/evidence' / stamp
    evidence.mkdir(parents=True)
    results = []

    def run(stage, name, directory, command, kind=None, expected=None, count_log=None):
        folder = evidence / stage
        folder.mkdir(exist_ok=True)
        log_path = folder / f'{name}.log'
        print(f'Running {stage}/{name}...', flush=True)
        with log_path.open('w') as log:
            try:
                code = subprocess.run(command, cwd=ROOT / directory, stdout=log, stderr=subprocess.STDOUT).returncode
            except OSError as error:
                log.write(f'Could not launch command: {error}\n')
                code = 127
        output = log_path.read_text()
        count_output = count_log.read_text() if count_log and count_log.exists() else output
        count = passed_count(count_output, kind) if kind else None
        # Empty selections must never look like a successful test run.
        if kind and (not count or (expected is not None and count != expected)):
            code = code or 1
        results.append({'stage': stage, 'check': name, 'command': command,
                        'exit_code': code, 'passed': count, 'expected': expected,
                        'log': str(log_path.relative_to(evidence)),
                        'assertion_log': str(count_log.relative_to(evidence)) if count_log else None})
        print(f'{stage}/{name}: {"PASS" if code == 0 else "FAIL"}' + (f' ({count} tests)' if kind else ''), flush=True)
        return code, output

    # Discovery is a supporting validation, not another testing stage.
    code, listing = run('support', 'rust-inventory', 'backend', ['cargo', 'test', '--locked', '--', '--list'])
    manifest = json.loads((ROOT / 'testing/suites.json').read_text())
    try:
        if code:
            raise ValueError('Rust test discovery failed')
        validate_partition(manifest['rust'], [line[:-6] for line in listing.splitlines() if line.endswith(': test')])
        for path in ('mobile/test', 'testing/python'):
            if list((ROOT / path).glob('*test*.py')) or list((ROOT / path).glob('*_test.dart')):
                raise ValueError(f'Unclassified flat tests in {path}')
    except ValueError as error:
        print(error, flush=True)
        results.append({'stage': 'support', 'check': 'classification', 'exit_code': 1, 'error': str(error)})
    else:
        stages = ('unit', 'integration') if args.stage == 'all' else (args.stage,)
        for stage in stages:
            cases = manifest['rust'][stage]
            run(stage, 'rust', 'backend', ['cargo', 'test', '--locked', '--', '--exact', *cases], 'rust', len(cases))
            run(stage, 'flutter', 'mobile', ['fvm', 'flutter', 'test', '--no-pub', '--reporter', 'expanded', f'test/{stage}'], 'flutter')
            run(stage, 'python', '.', [str(ROOT / 'ml/.venv/bin/python'), '-m', 'unittest', 'discover', '-s', f'testing/python/{stage}', '-v'], 'python')
            if stage == 'integration':
                run(stage, 'database', '.', [sys.executable, 'testing/scripts/run_database_tests.py', '--evidence-dir', str(evidence / 'integration/database')], 'rust', 1, evidence / 'integration/database/integration.log')
                run(stage, 'gtfs', 'backend', ['cargo', 'test', '--locked', '--', '--ignored', '--exact', *manifest['rust']['gtfs']], 'rust', 1)
                if args.live:
                    run(stage, 'live-transit', 'backend', ['cargo', 'test', '--locked', '--', '--ignored', '--exact', *manifest['rust']['live']], 'rust', 2)
        run('support', 'analyze', 'mobile', ['fvm', 'flutter', 'analyze'])
    summary = {'tested_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
               'utc': stamp, 'stage': args.stage, 'live_integrations': 'requested' if args.live else 'not run (opt-in)',
               'rust_partition': manifest['rust'], 'checks': results,
               'working_tree_status': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True)}
    summary['status'] = 'FAIL' if any(r['exit_code'] for r in results) else 'PASS'
    (evidence / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(f'{summary["status"]}; evidence: {evidence.relative_to(ROOT)}', flush=True)
    return int(summary['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
