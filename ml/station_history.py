"""Fresh hourly PM2.5 station history from OpenAQ, bounded by age and distance."""
import datetime as dt
import json
import math
import os
from urllib.parse import urlencode

from data import InputUnavailable, parse_time


def distance_km(latitude, longitude, station):
    lat = station['coordinates']['latitude']
    lon = station['coordinates']['longitude']
    a = math.sin(math.radians(lat-latitude)/2)**2
    a += math.cos(math.radians(lat))*math.cos(math.radians(latitude))*math.sin(math.radians(lon-longitude)/2)**2
    return 6371*2*math.asin(min(1, math.sqrt(a)))


def load_station(latitude, longitude, now):
    key = os.getenv('OPENAQ_API_KEY', '').strip()
    if not key:
        raise InputUnavailable('OpenAQ key is not configured')

    def request(path, params):
        # Keep URLs and keys out of user-facing errors.
        from urllib.request import Request, urlopen
        url = 'https://api.openaq.org/v3/' + path + '?' + urlencode(params)
        try:
            with urlopen(Request(url, headers={'X-API-Key': key, 'User-Agent': 'SUPRA-Commute/1.0'}), timeout=3) as response:
                body = response.read(1_000_001)
            if len(body) > 1_000_000:
                raise ValueError('Oversized OpenAQ response')
            results = json.loads(body)['results']
            if not isinstance(results, list):
                raise ValueError('Invalid OpenAQ results')
            return results
        except (OSError, ValueError, KeyError, TypeError):
            raise InputUnavailable('OpenAQ hourly inputs unavailable') from None

    stations = request('locations', {
        'coordinates': f'{latitude},{longitude}', 'radius': 25000,
        'parameters_id': 2, 'limit': 100,
    })
    candidates = []
    for station in stations:
        try:
            end = parse_time(station['datetimeLast']['utc'])
            distance = distance_km(latitude, longitude, station)
            if station['isMobile'] is not False or not (0 <= (now-end).total_seconds() < 7200) or not (0 <= distance <= 25):
                continue
            candidates.append((distance, station))
        except (KeyError, TypeError, ValueError):
            continue
    candidates.sort(key=lambda pair: pair[0])
    # At most two station histories. A failed or incomplete sensor cannot supply features.
    for distance, station in candidates[:2]:
        sensors = []
        for sensor in station.get('sensors', []):
            try:
                if sensor['parameter']['name'] == 'pm25' and sensor['parameter']['units'] in ('µg/m³', 'μg/m³', 'ug/m3'):
                    sensors.append(sensor)
            except (KeyError, TypeError):
                continue
        for sensor in sensors[:1]:
            try:
                rows = request(f"sensors/{sensor['id']}/hours", {
                    'datetime_from': (now-dt.timedelta(hours=16)).isoformat(),
                    'datetime_to': now.isoformat(), 'limit': 100,
                })
            except InputUnavailable:
                continue
            values = {}
            duplicate = False
            for row in rows:
                try:
                    end = parse_time(row['period']['datetimeTo']['utc'])
                    amount = row['value']
                    if row['parameter']['name'] != 'pm25' or row['parameter']['units'] not in ('µg/m³','μg/m³','ug/m3'):
                        continue
                    if row['period']['interval'] != '01:00:00' or end.minute or end.second or end.microsecond:
                        continue
                    if row.get('flagInfo', {}).get('hasFlags') is True or not 75 <= row['coverage']['percentCoverage'] <= 100:
                        continue
                    if isinstance(amount, bool) or not isinstance(amount, (int, float)) or not math.isfinite(amount) or not 0 <= amount <= 2000 or end > now:
                        continue
                    if end in values:
                        duplicate = True
                        break
                    values[end] = float(amount)
                except (KeyError, TypeError, ValueError):
                    continue
            if not values or duplicate:
                continue
            anchor = max(values)
            times = [anchor-dt.timedelta(hours=h) for h in range(11, -1, -1)]
            if now-anchor >= dt.timedelta(hours=2) or not all(t in values for t in times):
                continue
            return times, [values[t] for t in times], {
                'station_id': station['id'], 'station_name': station['name'],
                'sensor_id': sensor['id'], 'distance_km': distance,
                'coordinates': station['coordinates'], 'provider': station.get('provider'),
                'owner': station.get('owner'), 'licenses': station.get('licenses'),
            }
    raise InputUnavailable('OpenAQ requires 12 recent consecutive hourly PM2.5 readings')
