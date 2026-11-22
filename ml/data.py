"""Public hourly model history. Forecast hours after the issue time are never features."""
import datetime as dt
from concurrent.futures import ThreadPoolExecutor
import json
import math
from pathlib import Path
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

def history(latitude,longitude,days=3,now=None,cache_dir=None):
    now=now or utcnow()
    if cache_dir:
        cache_dir = Path(cache_dir)
        cache_dir.mkdir(parents=True, exist_ok=True)
    sources = [
        ('weather','https://api.open-meteo.com/v1/forecast','temperature_2m,precipitation'),
        ('air','https://air-quality-api.open-meteo.com/v1/air-quality','pm2_5,us_aqi'),
    ]

    def load(source):
        kind, base, variables = source
        params=dict(latitude=latitude,longitude=longitude,hourly=variables,past_days=days,forecast_days=1,timezone='UTC')
        try:
            raw = fetch(base + '?' + urlencode(params), timeout=4 if days <= 3 else 15)
        except HTTPError as error:
            raise ValueError(f'Open-Meteo {kind} returned HTTP {error.code}') from error
        except (URLError, TimeoutError) as error:
            raise ValueError(f'Open-Meteo {kind} connection failed') from error
        if cache_dir:
            (cache_dir/f'{latitude}_{longitude}_{kind}.json').write_bytes(raw)
        value=json.loads(raw)
        hourly=value['hourly']
        return {parse_time(t): [hourly[k][i] for k in variables.split(',')]
                for i,t in enumerate(hourly['time'])}

    # Both inputs are independent. Keep their combined latency within the API
    # deadline even when one source needs a second attempt.
    with ThreadPoolExecutor(max_workers=2) as pool:
        weather, air = pool.map(load, sources)
    return merge_history(weather, air, now)

def merge_history(weather,air,now):
    rows=[]
    for at in sorted(weather.keys() & air.keys()):
        values=weather[at]+air[at]
        if at>now or not all(isinstance(v,(float,int)) and math.isfinite(v) for v in values): continue
        if not (-50<=values[0]<=60 and 0<=values[1]<=500 and 0<=values[2]<=2000 and 0<=values[3]<=1000): continue
        rows.append({'time':at.isoformat(), 'values':values})
    return rows
