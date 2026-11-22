"""OpenAQ history quality gates and projected PM2.5 NowCast boundaries."""
import copy
import datetime as dt
from io import BytesIO
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'ml'))
from air_model import nowcast_aqi
from data import InputUnavailable
from station_history import load_station

NOW = dt.datetime(2026, 11, 16, 3, 30, tzinfo=dt.timezone.utc)
ANCHOR = NOW.replace(minute=0)


class StationAirTests(unittest.TestCase):
    def fixture(self):
        station = {'id': 1, 'name': 'Station', 'isMobile': False,
                   'coordinates': {'latitude': -6.2, 'longitude': 106.8},
                   'datetimeLast': {'utc': ANCHOR.isoformat()},
                   'sensors': [{'id': 10, 'parameter': {'name': 'pm25', 'units': 'µg/m³'}}]}
        rows = [{'period': {'interval': '01:00:00', 'datetimeTo': {
                    'utc': (ANCHOR-dt.timedelta(hours=i)).isoformat()}},
                 'parameter': {'name': 'pm25', 'units': 'µg/m³'}, 'value': 40+i,
                 'flagInfo': {'hasFlags': False}, 'coverage': {'percentCoverage': 100}}
                for i in range(12)]
        return station, rows

    def load(self, station, rows, now=NOW):
        requests = []
        def respond(request, **kwargs):
            requests.append(request.full_url)
            data = [station] if '/locations?' in request.full_url else rows
            return BytesIO(json.dumps({'results': data}).encode())
        with patch.dict(os.environ, {'OPENAQ_API_KEY': 'test-key'}), \
             patch('urllib.request.urlopen', side_effect=respond):
            result = load_station(-6.2, 106.8, now)
        return result, requests

    def test_consecutive_fresh_hours_and_correct_openaq_date_filters(self):
        station, rows = self.fixture()
        (times, values, meta), requests = self.load(station, rows)
        self.assertEqual(len(times), 12)
        self.assertEqual(values, list(range(51, 39, -1)))
        self.assertEqual(meta['sensor_id'], 10)
        self.assertEqual(meta['distance_km'], 0)
        params = parse_qs(urlparse(requests[-1]).query)
        self.assertIn('datetime_from', params)
        self.assertIn('datetime_to', params)
        self.assertNotIn('date_from', params)

    def test_missing_flagged_low_coverage_duplicate_or_invalid_hours_rejected(self):
        station, rows = self.fixture()
        variants = [rows[:-1], rows+[rows[0]]]
        for field, value in [('value', -1), ('value', float('nan')),
                             ('flagInfo', {'hasFlags': True}), ('coverage', {'percentCoverage': 74})]:
            bad = copy.deepcopy(rows)
            bad[4][field] = value
            variants.append(bad)
        for bad in variants:
            with self.subTest(rows=bad), self.assertRaises(InputUnavailable):
                self.load(station, bad)

    def test_stale_mobile_distant_or_future_stations_rejected(self):
        station, rows = self.fixture()
        for field, value in [('isMobile', True),
                             ('coordinates', {'latitude': -7, 'longitude': 106.8}),
                             ('datetimeLast', {'utc': (NOW+dt.timedelta(hours=1)).isoformat()}),
                             ('datetimeLast', {'utc': (NOW-dt.timedelta(hours=2)).isoformat()})]:
            bad = {**station, field: value}
            with self.subTest(field=field), self.assertRaises(InputUnavailable):
                self.load(bad, rows)
        with self.assertRaises(InputUnavailable):
            self.load(station, rows, ANCHOR+dt.timedelta(hours=2))

    def test_hourly_anchor_age_is_checked_independently_of_station_last_update(self):
        station, rows = self.fixture()
        for row in rows:
            at = dt.datetime.fromisoformat(row['period']['datetimeTo']['utc'])
            row['period']['datetimeTo']['utc'] = (at-dt.timedelta(hours=2)).isoformat()
        with self.assertRaises(InputUnavailable):
            self.load(station, rows)

    def test_pm25_nowcast_uses_updated_breakpoints_and_history_weighting(self):
        for pm, index in [(0, 0), (9, 50), (9.1, 51), (35.4, 100),
                          (55.4, 150), (125.4, 200), (225.4, 300), (325.4, 500)]:
            self.assertEqual(nowcast_aqi([pm]*12), index)
        self.assertGreater(nowcast_aqi([10]*11+[100]), nowcast_aqi([100]+[10]*11))


if __name__ == '__main__':
    unittest.main()
