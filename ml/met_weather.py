"""Coordinate forecasts from MET Norway, shared by the weather and ML adapters."""
from datetime import timedelta
from email.utils import parsedate_to_datetime
import json
from threading import Lock
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from data import parse_time, utcnow

SOURCE = 'MET Norway Locationforecast (https://api.met.no/), CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).'
_cache = {}
_lock = Lock()
_stripes = [Lock() for _ in range(16)]


def _series(key, now):
    with _stripes[hash(key) % len(_stripes)]:
        with _lock:
            entry = _cache.get(key)
            if entry is None and len(_cache) >= 128:
                for old in [k for k, v in _cache.items() if v[0] <= now]:
                    del _cache[old]
                if len(_cache) >= 128:
                    raise ValueError('Weather cache at capacity')
        if entry and entry[0] > now:
            return entry[2]
        headers = {'User-Agent': 'SUPRA-Commute/1.0 github.com/arkaanp/SUPRA'}
        if entry and entry[1]:
            headers['If-Modified-Since'] = entry[1]
        url = f'https://api.met.no/weatherapi/locationforecast/2.0/compact?lat={key[0]}&lon={key[1]}'
        try:
            with urlopen(Request(url, headers=headers), timeout=4) as response:
                body = response.read(500_001)
                if len(body) > 500_000:
                    raise ValueError('Oversized MET Norway response')
                properties = json.loads(body)['properties']
                data = (parse_time(properties['meta']['updated_at']), properties['timeseries'][:48])
                modified = response.headers.get('Last-Modified')
                expires = response.headers.get('Expires')
        except HTTPError as error:
            if error.code != 304 or not entry:
                raise
            modified, data = entry[1:]
            expires = error.headers.get('Expires')
            error.close()
        reuse_until = now + timedelta(hours=3)
        if expires:
            reuse_until = max(reuse_until, parsedate_to_datetime(expires))
        with _lock:
            _cache[key] = (reuse_until, modified, data)
        return data


def weather_at(latitude, longitude, now=None):
    now = now or utcnow()
    issued, series = _series((f'{latitude:.3f}', f'{longitude:.3f}'), now)
    if issued < now - timedelta(hours=18) or issued > now + timedelta(minutes=15):
        raise ValueError('Expired MET Norway forecast')
    for step in series:
        at = parse_time(step['time'])
        if at <= now < at + timedelta(hours=1):
            instant = step['data']['instant']['details']
            hour = step['data']['next_1_hours']
            temp, rain = instant['air_temperature'], hour['details']['precipitation_amount']
            if not (-60 <= temp <= 65 and 0 <= rain <= 1000):
                raise ValueError('Invalid MET Norway values')
            return {'temperature_c': temp, 'precipitation_mm': rain, 'interval_seconds': 3600,
                    'valid_at': at.isoformat(), 'issued_at': issued.isoformat(),
                    'humidity_percent': instant.get('relative_humidity'),
                    'wind_speed_kmh': instant['wind_speed'] * 3.6,
                    'description': hour['summary']['symbol_code'].split('_')[0], 'attribution': SOURCE}
    raise ValueError('No MET Norway forecast for this hour')
