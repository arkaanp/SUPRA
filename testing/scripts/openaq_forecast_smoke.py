#!/usr/bin/env python3
"""Live OpenAQ/MET Norway HTTP check with Open-Meteo/CAMS failure injected."""
import argparse
import datetime as dt
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import shlex
import sys
import threading
from unittest.mock import patch
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'ml'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env-file', type=Path, help='Read only OPENAQ_API_KEY from this local file')
    parser.add_argument('--latitude', type=float, default=-6.2297)
    parser.add_argument('--longitude', type=float, default=106.8295)
    args = parser.parse_args()
    if args.env_file:
        for line in args.env_file.read_text().splitlines():
            key, sep, value = line.partition('=')
            if sep and key.strip() == 'OPENAQ_API_KEY':
                tokens = shlex.split(value, comments=True)
                os.environ['OPENAQ_API_KEY'] = tokens[0] if tokens else ''
    import serve
    from data import InputUnavailable, parse_time
    import torch
    torch.set_num_threads(1)
    server = ThreadingHTTPServer(('127.0.0.1', 0), serve.Handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    summary = {'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
               'scenario': 'Open-Meteo/CAMS outage injected; live OpenAQ and MET Norway',
               'latitude': args.latitude, 'longitude': args.longitude, 'status': 'FAIL'}
    try:
        with patch.object(serve.app.model, 'forecast', side_effect=InputUnavailable('Injected weather outage')), \
             patch('serve.forecast_aqi', side_effect=InputUnavailable('Injected CAMS outage')):
            thread.start()
            with urlopen(f'http://127.0.0.1:{server.server_port}/v1/forecast?latitude={args.latitude}&longitude={args.longitude}', timeout=28) as response:
                payload = json.load(response)
                summary['http_status'] = response.status
        now = dt.datetime.now(dt.timezone.utc)
        assert len(payload['hourly']) == 12
        assert all(row.get('estimated_aqi') is not None and row['aqi'] is None for row in payload['hourly'])
        assert parse_time(payload['expires_at']) > now
        assert all(parse_time(row['target_time']) > now for row in payload['hourly'])
        summary.update(status='PASS', air_forecast=payload['air_forecast'], hourly=payload['hourly'])
    except Exception as error:
        summary['error_type'] = type(error).__name__
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    folder = ROOT/'testing/evidence'/dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')/'integration'
    folder.mkdir(parents=True)
    path = folder/'live-openaq-forecast.json'
    path.write_text(json.dumps(summary, indent=2)+'\n')
    print(f'{summary["status"]}; evidence: {path.relative_to(ROOT)}')
    return int(summary['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
