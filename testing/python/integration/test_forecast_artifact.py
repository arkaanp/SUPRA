"""PyTorch checkpoint persistence and twelve-hour inference integration."""
import datetime as dt
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import torch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'ml'))
from inference import Forecaster
from model import ForecastNet, INPUT_SIZE

NOW = dt.datetime(2026, 11, 16, 3, 30, tzinfo=dt.timezone.utc)

class ForecastArtifactTests(unittest.TestCase):
    def rows(self,count=24):
        end=NOW.replace(minute=0)
        return [{'time':(end-dt.timedelta(hours=count-1-i)).isoformat(),'values':[29.,0.2,20.,70.]} for i in range(count)]

    def test_weather_only_artifact_when_primary_provider_is_rate_limited(self):
        from data import InputUnavailable
        from serve import App
        app = App()
        weather = {'temperature_c': 28.8, 'valid_at': NOW.replace(minute=0).isoformat(),
                   'issued_at': NOW.replace(minute=0).isoformat()}
        first_hour = NOW.replace(minute=0) + dt.timedelta(hours=1)
        with patch.object(app.model, 'forecast', side_effect=InputUnavailable('Open-Meteo weather returned HTTP 429')), \
             patch('serve.forecast_aqi', return_value={first_hour: 82}), \
             patch('air_model.forecast', side_effect=InputUnavailable('No station history')), \
             patch('serve.forecast_symbols', return_value={first_hour: 'partlycloudy_day'}), \
             patch('weather_model.utcnow', return_value=NOW), patch('weather_model.weather_at', return_value=weather):
            payload = app.get('/v1/forecast', {'latitude':['-6.2'], 'longitude':['106.8']})
        self.assertEqual(payload['scope'], 'weather_only')
        self.assertEqual(len(payload['hourly']), 12)
        self.assertIsNone(payload['hourly'][0]['aqi'])
        self.assertEqual(payload['hourly'][0]['provider_aqi'], 82)
        self.assertEqual(payload['hourly'][0]['weather_symbol'], 'partlycloudy_day')
        self.assertIsNone(payload['hourly'][1]['provider_aqi'])
        self.assertTrue(all(0 <= row['rain_probability'] <= 1 for row in payload['hourly']))

    def test_openaq_pytorch_fills_twelve_air_hours_when_cams_is_rate_limited(self):
        from data import InputUnavailable, parse_time
        from serve import App
        from air_model import nowcast_aqi
        app = App()
        anchor = NOW.replace(minute=0)
        times = [anchor-dt.timedelta(hours=h) for h in range(11, -1, -1)]
        weather = {'temperature_c': 28.8, 'valid_at': anchor.isoformat(), 'issued_at': anchor.isoformat()}
        with patch.object(app.model, 'forecast', side_effect=InputUnavailable('HTTP 429')), \
             patch('serve.forecast_aqi', side_effect=InputUnavailable('CAMS HTTP 429')), \
             patch('serve.forecast_symbols', return_value={}), \
             patch('serve.utcnow', return_value=NOW), \
             patch('weather_model.utcnow', return_value=NOW), \
             patch('weather_model.weather_at', return_value=weather), \
             patch('air_model.load_station', return_value=(times, [40.]*12, {
                 'station_name':'Test station','distance_km':2.5})):
            payload = app.get('/v1/forecast', {'latitude':['-6.2'], 'longitude':['106.8']})
        hours = payload['hourly']
        self.assertEqual(len(hours), 12)
        self.assertEqual(parse_time(hours[-1]['target_time']), anchor+dt.timedelta(hours=12))
        self.assertTrue(all(row['aqi'] is None and row['provider_aqi'] is None for row in hours))
        self.assertTrue(all(0 <= row['estimated_aqi'] <= 4000 and 0 <= row['estimated_pm25'] <= 2000 for row in hours))
        self.assertGreater(len({row['estimated_aqi'] for row in hours}), 1)
        history = [40.]*12
        for row in hours:
            history.append(row['estimated_pm25'])
            self.assertEqual(row['estimated_aqi'], nowcast_aqi(history[-12:]))
        self.assertEqual(payload['air_forecast']['station']['station_name'], 'Test station')
        self.assertIn('OpenAQ', payload['sources']['air_forecast'])
        self.assertEqual(parse_time(payload['air_forecast']['expires_at']), anchor+dt.timedelta(hours=2))
        self.assertLessEqual(parse_time(payload['expires_at']), parse_time(payload['air_forecast']['expires_at']))

    def checkpoint(self,path):
        torch.manual_seed(42);net=ForecastNet()
        # Known weights exercise the complete serialization/inference contract.
        for p in net.parameters():p.data.zero_()
        card={'model_id':'test-only','data_through':NOW.isoformat(),'sources':{},'metrics':{'validation':{}},
              'validation_absolute_error_90':{},'limitations':[],'traffic_status':'unavailable'}
        torch.save({'state_dict':net.state_dict(),'xmean':torch.zeros(INPUT_SIZE),'xstd':torch.ones(INPUT_SIZE),
                    'ymean':torch.zeros(4),'ystd':torch.ones(4),'card':card},path)

    def test_saved_weights_generate_twelve_finite_hours_without_traffic(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'testing') as folder:
            path=Path(folder)/'test.pt';self.checkpoint(path)
            service=Forecaster(path,load_history=lambda *a,**kw:self.rows())
            d=service.forecast(-6.2,106.8,NOW)
            self.assertEqual(len(d['hourly']),12)
            self.assertEqual(d['hourly'][0]['temperature_c'],29)
            self.assertIsNone(d['hourly'][0]['traffic_density'])
            self.assertEqual(d['hourly'][0]['rain_probability'],0.5)
            service.history=lambda *a,**kw:self.rows()[:-3]
            with self.assertRaisesRegex(ValueError,'Insufficient'):service.forecast(-6.2,106.8,NOW)


if __name__=='__main__':unittest.main()
