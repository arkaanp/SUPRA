"""Public hourly model history. Forecast hours after the issue time are never features."""
import datetime as dt
from functools import lru_cache
from concurrent.futures import ThreadPoolExecutor
import json
import math
import os
from pathlib import Path
from threading import Lock
import time
from urllib.parse import urlencode
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

UTC = dt.timezone.utc
ROOT = Path(__file__).resolve().parent
SITES = [(-6.23,106.83),(-6.37,106.83),(-6.60,106.80),(-6.24,107.00),(-6.18,106.63)]
FIELDS = ['temperature_c','precipitation_mm','pm25_ug_m3','aqi']
SOURCES = {'weather':'Open-Meteo weather models', 'air':'CAMS global via Open-Meteo',
           'attribution':'Open-Meteo.com / Copernicus CAMS, CC BY 4.0',
           'weather_url':'https://open-meteo.com/en/docs',
           'air_url':'https://open-meteo.com/en/docs/air-quality-api'}

class InputUnavailable(ValueError):
    pass


_retry_after = {}
_retry_lock = Lock()

def utcnow():
    return dt.datetime.now(UTC)

def parse_time(value):
    value = dt.datetime.fromisoformat(value.replace('Z','+00:00'))
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC)

def fetch(url, limit=4_000_000, timeout=15, attempts=2):
    request = Request(url, headers={'User-Agent':'SUPRA-Commute/1.0', 'Accept':'application/json, application/rss+xml, text/xml'})
    for attempt in range(attempts):
        try:
            with urlopen(request, timeout=timeout) as response:
                body=response.read(limit+1)
                if len(body)>limit:
                    raise ValueError('Provider response too large')
                return body
        except HTTPError as error:
            if error.code < 500 or attempt + 1 == attempts:
                raise
            time.sleep(0.5)
        except OSError:
            if attempt+1==attempts: raise
            time.sleep(0.5)

def hourly_data(kind, latitude, longitude, days=3, cache_dir=None):
    params = dict(latitude=latitude, longitude=longitude, past_days=days,
                  forecast_days=2, timezone='UTC')
    if kind == 'air':
        key = os.getenv('OPEN_METEO_API_KEY', '').strip()
        host = 'customer-air-quality-api' if key else 'air-quality-api'
        base = f'https://{host}.open-meteo.com/v1/air-quality'
        params.update(hourly='pm2_5,us_aqi', domains='cams_global')
        if key:
            params['apikey'] = key
    else:
        base = 'https://api.open-meteo.com/v1/forecast'
        params['hourly'] = 'temperature_2m,precipitation'

    with _retry_lock:
        if time.monotonic() < _retry_after.get(kind, 0):
            raise InputUnavailable(f'Open-Meteo {kind} returned HTTP 429')
    try:
        raw = fetch(base + '?' + urlencode(params), timeout=4 if days <= 3 else 15)
        hourly = json.loads(raw)['hourly']
        times = [parse_time(t) for t in hourly['time']]
        columns = [hourly[name] for name in params['hourly'].split(',')]
        if any(len(column) != len(times) for column in columns):
            raise ValueError('Mismatched hourly arrays')
    except HTTPError as error:
        if error.code == 429:
            wait = error.headers.get('Retry-After', '') if error.headers else ''
            with _retry_lock:
                _retry_after[kind] = time.monotonic() + (int(wait) if wait.isdigit() else 300)
        raise InputUnavailable(f'Open-Meteo {kind} returned HTTP {error.code}') from None
    except (OSError, KeyError, TypeError, ValueError):
        raise InputUnavailable(f'Open-Meteo {kind} inputs unavailable') from None
    if cache_dir:
        (cache_dir / f'{latitude}_{longitude}_{kind}.json').write_bytes(raw)
    return dict(zip(times, zip(*columns)))


def history(latitude, longitude, days=3, now=None, cache_dir=None):
    if cache_dir:
        cache_dir = Path(cache_dir)
        cache_dir.mkdir(parents=True, exist_ok=True)

    def load(kind):
        if kind == 'air' and days == 3 and cache_dir is None:
            return _recent_air_data(latitude, longitude, int(time.monotonic() // 300))
        return hourly_data(kind, latitude, longitude, days, cache_dir)

    with ThreadPoolExecutor(max_workers=2) as pool:
        weather, air = pool.map(load, ('weather', 'air'))
    return merge_history(weather, air, now or utcnow())


@lru_cache(maxsize=32)
def _recent_air_data(latitude, longitude, bucket):
    return hourly_data('air', latitude, longitude)


def forecast_aqi(latitude, longitude):
    air = _recent_air_data(latitude, longitude, int(time.monotonic() // 300))
    return {at: aqi for at, (_, aqi) in air.items()
            if isinstance(aqi, (float, int)) and math.isfinite(aqi) and 0 <= aqi <= 2000}


def merge_history(weather,air,now):
    rows=[]
    for at in sorted(weather.keys() & air.keys()):
        values=[*weather[at], *air[at]]
        if at>now or not all(isinstance(v,(float,int)) and math.isfinite(v) for v in values): continue
        if not (-50<=values[0]<=60 and 0<=values[1]<=500 and 0<=values[2]<=2000 and 0<=values[3]<=1000): continue
        rows.append({'time':at.isoformat(), 'values':values})
    return rows
