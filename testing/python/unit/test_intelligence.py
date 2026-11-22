"""Isolated news, forecast-input and cache unit tests; no provider calls."""
import datetime as dt
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'ml'))
from data import history, merge_history
from inference import Forecaster
from model import INPUT_SIZE
from news import parse_rss,classify_severity
from train import split_examples
UTC=dt.timezone.utc
NOW=dt.datetime(2026,11,16,3,30,tzinfo=UTC)

def rss(title='Hujan dan genangan di Depok',url='https://www.antaranews.com/berita/123/report',date='Mon, 16 Nov 2026 09:00:00 +0700',description=''):
    return f'<rss><channel><item><title>{title}</title><link>{url}</link><pubDate>{date}</pubDate><description>{description}</description></item></channel></rss>'.encode()

class NewsTests(unittest.TestCase):
    def test_original_timestamp_stable_id_and_area_precision(self):
        first=parse_rss(rss(),NOW);second=parse_rss(rss(),NOW+dt.timedelta(minutes=10))
        self.assertEqual(len(first),1);self.assertEqual(first[0]['id'],second[0]['id'])
        self.assertFalse(first[0]['verified']);self.assertEqual(first[0]['location_label'],'Depok')
        self.assertEqual(first[0]['published_at'],'2026-11-16T02:00:00+00:00')
        self.assertEqual(first[0]['expires_at'],'2026-11-18T02:00:00+00:00')
    def test_stale_future_untrusted_and_unrelated_items_rejected(self):
        for raw in [rss(date='Mon, 09 Nov 2026 09:00:00 +0700'),rss(date='Mon, 23 Nov 2026 09:00:00 +0700'),
                    rss(url='https://www.antaranews.com.evil.test/berita'),rss(title='Sepak bola Jakarta'),
                    rss(title='Rekayasa lalu lintas di Bandung',description='Jakarta (ANTARA) - Pengaturan arus di Bandung.')]:
            self.assertEqual(parse_rss(raw,NOW),[])
    def test_severity_classifies_disruptions_not_general_announcements(self):
        self.assertEqual(classify_severity('Pelatihan pelayanan Transjakarta di Jakarta',''),'low')
        self.assertEqual(classify_severity('Rekayasa lalu lintas di Sudirman',''),'medium')
        self.assertEqual(classify_severity('Jalan ditutup total akibat banjir parah di Depok',''),'high')
        self.assertEqual(classify_severity('Tidak ada banjir di Depok',''),'low')
        self.assertEqual(classify_severity('Pemotor luka-luka dalam kecelakaan di Jakarta',''),'medium')
        self.assertEqual(classify_severity('Tidak ada kecelakaan di Depok',''),'low')
    def test_entities_rejected(self):
        with self.assertRaises(ValueError):parse_rss(b'<!DOCTYPE rss><rss/>',NOW)

class ForecastTests(unittest.TestCase):
    def rows(self,count=24):
        end=NOW.replace(minute=0)
        return [{'time':(end-dt.timedelta(hours=count-1-i)).isoformat(),'values':[29.,0.2,20.,70.]} for i in range(count)]
    def test_past_only_merge_drops_future_missing_and_invalid_values(self):
        past=NOW-dt.timedelta(hours=1);future=NOW+dt.timedelta(hours=1)
        rows=merge_history({past:[29,0],future:[30,1]},{past:[20,70],future:[30,80]},NOW)
        self.assertEqual(len(rows),1)
        self.assertEqual(merge_history({past:[29,None]},{past:[20,70]},NOW),[])
    def test_history_combines_live_input_adapters_without_a_cache_directory(self):
        def fetch_fixture(url, **kwargs):
            data = {'pm2_5': [20], 'us_aqi': [70]} if 'air-quality' in url else {
                'temperature_2m': [29], 'precipitation': [0.2],
            }
            return json.dumps({'hourly': {'time': ['2026-11-16T03:00'], **data}})

        with patch('data.fetch', side_effect=fetch_fixture):
            rows = history(-6.2, 106.8, now=NOW)
        self.assertEqual([row['values'] for row in rows], [[29, 0.2, 20, 70]])
    def test_met_cache_reselects_the_valid_hour_without_refetching(self):
        from io import BytesIO
        import met_weather
        anchor = NOW.replace(minute=0)
        def step(hour):
            return {'time': (anchor + dt.timedelta(hours=hour)).isoformat(),
                    'data': {'instant': {'details': {'air_temperature': 28, 'wind_speed': 2}},
                             'next_1_hours': {'details': {'precipitation_amount': hour},
                                              'summary': {'symbol_code': 'rain'}}}}
        response = BytesIO(json.dumps({'properties': {'meta': {'updated_at': anchor.isoformat()},
                           'timeseries': [step(0), step(1)]}}).encode())
        response.headers = {}
        with patch.dict(met_weather._cache, clear=True), patch('met_weather.urlopen', return_value=response) as load:
            for hour in [0, 1]:
                result = met_weather.weather_at(-6.2297, 106.8295, NOW + dt.timedelta(hours=hour))
                self.assertEqual(result['precipitation_mm'], hour)
            self.assertEqual(load.call_count, 1)
            with self.assertRaisesRegex(ValueError, 'No MET Norway forecast'):
                met_weather.weather_at(-6.2297, 106.8295, NOW + dt.timedelta(hours=2))

    def test_chronological_splits_never_cross_target_boundaries(self):
        start=NOW-dt.timedelta(days=5)
        rows=[{'time':(start+dt.timedelta(hours=i)).isoformat(),'values':[i,0.2,20,70]} for i in range(120)]
        a=start+dt.timedelta(days=2);b=start+dt.timedelta(days=4)
        train,val,test=split_examples([{'point':[-6.2,106.8],'rows':rows}],a,b)
        self.assertTrue(all(len(g)>0 for g in [train,val,test]))
        self.assertTrue(all(len(row[0])==INPUT_SIZE for row in train+val+test))
        self.assertTrue(all(y[0]<48 for x,y,base in train))
        self.assertTrue(all(x[92]>=48 and y[0]<96 for x,y,base in val))
        self.assertTrue(all(x[92]>=96 for x,y,base in test))
        self.assertLess(len(train),48*12) # cross-cutoff targets are excluded
    def test_cache_refreshes_at_hour_boundary(self):
        from serve import App
        app=App();calls=[]
        app.model.forecast=lambda *a: calls.append(a) or {'test':len(calls), 'hourly':[]}
        query={'latitude':['-6.2'],'longitude':['106.8']}
        with patch('serve.time.time',return_value=3600), patch('serve.forecast_symbols', return_value={}):
            app.get('/v1/forecast',query);app.get('/v1/forecast',query)
        self.assertEqual(len(calls),1)
        with patch('serve.time.time',return_value=7200), patch('serve.forecast_symbols', return_value={}):app.get('/v1/forecast',query)
        self.assertEqual(len(calls),2)
    def test_wrong_scope_stale_and_gaps_fail_closed(self):
        service=Forecaster(load_history=lambda *a,**kw:self.rows())
        with self.assertRaises(ValueError):service.forecast(-8,106.8,NOW)
        stale=self.rows()
        for r in stale:r['time']=(dt.datetime.fromisoformat(r['time'])-dt.timedelta(hours=3)).isoformat()
        service.history=lambda *a,**kw:stale
        with self.assertRaisesRegex(ValueError,'Stale'):service.forecast(-6.2,106.8,NOW)
        rows=self.rows();rows[12]['time']=rows[11]['time']
        service.history=lambda *a,**kw:rows
        with self.assertRaisesRegex(ValueError,'discontinuous'):service.forecast(-6.2,106.8,NOW)

if __name__=='__main__':unittest.main()
