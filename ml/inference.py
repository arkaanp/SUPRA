"""CPU inference from saved weights with fresh, contiguous, past-only inputs."""
import datetime as dt
import math
import threading
import numpy as np
import torch
from data import InputUnavailable, FIELDS, ROOT, history, parse_time, utcnow
from model import ForecastNet, LOOKBACK, HORIZON, features

class Forecaster:
    def __init__(self,path=None,load_history=history):
        self.path=path or ROOT/'artifacts/forecast.pt'
        self.history=load_history;self.lock=threading.Lock();self.net=None
        self.stamp=None
    def load(self):
        stamp=self.path.stat().st_mtime_ns
        if self.stamp==stamp:return
        state=torch.load(self.path,map_location='cpu',weights_only=True)
        net=ForecastNet();net.load_state_dict(state['state_dict']);net.eval()
        self.net=net;self.state=state;self.stamp=stamp
    def forecast(self,latitude,longitude,now=None):
        now=now or utcnow()
        if not math.isfinite(latitude) or not math.isfinite(longitude) or not (-6.9<=latitude<=-5.8 and 106.3<=longitude<=107.3):
            raise ValueError('Forecast location outside Greater Jakarta')
        rows=self.history(latitude,longitude,days=3,now=now)
        window=[r for r in rows if parse_time(r['time'])<=now][-LOOKBACK:]
        if len(window)!=LOOKBACK:raise InputUnavailable('Insufficient hourly inputs')
        times=[parse_time(r['time']) for r in window];anchor=times[-1]
        if now-anchor>dt.timedelta(hours=2) or any(b-a!=dt.timedelta(hours=1) for a,b in zip(times,times[1:])):
            raise InputUnavailable('Stale or discontinuous forecast inputs')
        if any(len(r['values'])!=4 or not all(isinstance(v,(float,int)) and math.isfinite(v) for v in r['values']) for r in window):
            raise ValueError('Invalid forecast inputs')
        targets=[anchor+dt.timedelta(hours=h) for h in range(1,HORIZON+1)]
        x=np.asarray([features([r['values'] for r in window],latitude,longitude,t,h)
                      for h,t in enumerate(targets,1)],dtype=np.float32)
        with self.lock:
            self.load();state=self.state
            if now-parse_time(state['card']['data_through'])>dt.timedelta(days=90):
                raise ValueError('Model needs retraining')
            with torch.inference_mode():
                out=self.net((torch.tensor(x)-state['xmean'])/state['xstd'])
                pred=(out[:,:4]*state['ystd']+state['ymean']).numpy()
                probability=out[:,4].sigmoid().tolist()
            card=state['card']
        pred[:,[0,2,3]]+=np.asarray(window[-1]['values'])[[0,2,3]]
        pred[:,1]=np.expm1(np.clip(pred[:,1],0,6));pred[:,2:]=np.maximum(pred[:,2:],0)
        if not np.isfinite(pred).all():raise ValueError('Nonfinite model output')
        hourly=[]
        for t,values,prob in zip(targets,pred,probability):
            if t<=now:continue
            if not (-50<=values[0]<=60 and values[1]<=500 and values[2]<=2000 and values[3]<=1000):
                raise ValueError('Out-of-range model output')
            hourly.append({'target_time':t.isoformat(),**dict(zip(FIELDS,map(float,values))),
                           'rain_probability':prob,'traffic_speed_kmh':None,'traffic_density':None})
        return {'latitude':latitude,'longitude':longitude,'generated_at':now.isoformat(),
                'input_through':anchor.isoformat(),'expires_at':(anchor+dt.timedelta(hours=2)).isoformat(),
                'model_id':card['model_id'],'framework':'PyTorch','status':'experimental',
                'sources':card['sources'],'validation':card['metrics']['validation'],
                'error_90':card['validation_absolute_error_90'],
                'limitations':card['limitations'],'traffic_status':card['traffic_status'],'hourly':hourly}
