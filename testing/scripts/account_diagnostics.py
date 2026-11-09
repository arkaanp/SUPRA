#!/usr/bin/env python3
"""Time read requests using the running Linux app session; never prints credentials or profile data."""
import json
from pathlib import Path
import time
from urllib.error import HTTPError
from urllib.request import Request, build_opener, ProxyHandler


def main():
    path = Path.home() / '.local/share/com.example.supra_mobile_ui/shared_preferences.json'
    prefs = json.loads(path.read_text())
    session = None
    for key, value in prefs.items():
        if key.endswith('-auth-token') and isinstance(value, str):
            try:
                candidate = json.loads(value)
            except ValueError:
                continue
            if isinstance(candidate, dict) and candidate.get('access_token'):
                session = candidate
                break
    if not session:
        print('No saved session found. Sign in to the Linux app first.')
        return 1
    opener = build_opener(ProxyHandler({}))
    failed = False
    user_id = session.get('user', {}).get('id')
    endpoints = ['/api/profile', '/api/trips']
    if user_id:
        endpoints += [f'/api/users/{user_id}/notifications?limit=100', f'/api/users/{user_id}/preferences']
    for endpoint in endpoints:
        label = endpoint.replace(user_id, '{id}') if user_id else endpoint
        started = time.monotonic()
        try:
            try:
                response = opener.open(Request('http://localhost:3000' + endpoint,
                    headers={'Authorization': 'Bearer ' + session['access_token']}), timeout=20)
            except HTTPError as error:
                response = error
            with response:
                payload = response.read()
                print(label, 'HTTP', response.code, 'seconds', round(time.monotonic()-started, 2))
                if response.code >= 400:
                    failed = True
                    body = json.loads(payload)
                    print('Error code:', body.get('code', 'unknown'))
        except (OSError, ValueError):
            failed = True
            print(label, 'failed/timed out; seconds', round(time.monotonic()-started, 2))
    return int(failed)

if __name__ == '__main__':
    raise SystemExit(main())
