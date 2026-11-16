"""PyTorch checkpoint persistence and twelve-hour inference integration."""
import datetime as dt
from pathlib import Path
import sys
import tempfile
import unittest
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
