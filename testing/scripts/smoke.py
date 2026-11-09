#!/usr/bin/env python3
"""Read-only HTTP checks against an already running backend; no token required."""
import argparse
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, HTTPRedirectHandler

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='http://localhost:3000')
    args = parser.parse_args()
    opener = build_opener(NoRedirect())
    failed = False
    for path, expected, field, value in [('/health/live', 200, 'status', 'ok'),
                                         ('/health/ready', 200, 'status', 'ready'),
                                         ('/api/trips', 401, 'code', 'unauthorized'),
                                         ('/api/does-not-exist', 404, 'code', 'not_found')]:
        try:
            try:
                response = opener.open(Request(args.base_url.rstrip('/') + path), timeout=5)
            except HTTPError as error:
                response = error
            with response:
                status = response.code
                body = json.loads(response.read(65536))
            passed = status == expected and body.get(field) == value
            print(f'{path}: HTTP {status}; {"PASS" if passed else "FAIL"}')
        except (OSError, URLError, ValueError):
            passed = False
            print(f'{path}: FAIL (unreachable or invalid JSON)')
        failed |= not passed
    return int(failed)

if __name__ == '__main__':
    raise SystemExit(main())
